/**
 * @description Generic, SObject-agnostic retention batch driven by
 *              `Record_Retention_Rule__mdt`. For each active rule:
 *                1. Builds a dynamic SOQL query against the configured
 *                   SObject, filtering by age and any rule-provided SOQL
 *                   WHERE fragment.
 *                2. Optionally post-filters records by regex against a
 *                   configured field.
 *                3. Optionally calls a `IRecordRetentionPredicate` to apply
 *                   business rules (e.g. *keep this engagement touch if the
 *                   contact's account has an open opportunity*).
 *                4. Deletes the survivors in `execute` chunks.
 *
 *              **Logs are just another record.** The same engine that purges
 *              `Engagement_Touch__c` rows purges `Log__c`, `Audit_Trail__c`,
 *              or any other SObject — no special-casing for log objects.
 *              See the README for log-shaped and business-data examples
 *              side-by-side.
 *
 *              **System-mode delete is intentional.** Scheduled retention
 *              must remove records regardless of the running user's FLS /
 *              CRUD. Goes through `DMLManager.deleteAsSystem` so the bypass
 *              is auditable through the project's DML chokepoint, not raw
 *              `Database.delete`.
 *
 *              **`Database.Stateful`** so cross-execute counters can
 *              accumulate. The framework keeps a per-rule `deletedCount` and
 *              `errorCount` map for the `finish` log line.
 *
 * @group Cleanup
 * @author David Wood
 * @since May 2026
 * @last 2026-05-16 — PR #6 framework extension: applyPredicate invokes IBulkPrimablePredicate.primeBulkCache(candidates) once per chunk before the per-record loop — predicates that need bulk pre-fetch opt in by additionally implementing the sub-interface. Eliminates SOQL-in-loop governor risk for KeepIf-style traversal predicates.
 */
@SuppressWarnings('PMD.CyclomaticComplexity')
// §12.1 narrow waiver — class-total CC=48 is the post-Item-3 framework
// extension cost. The alternative is folding newPredicateOrNull /
// applyPredicate / buildCandidateQuery / collectCandidatesForRule back into a
// single mega-method, which trades scanner-clean for unreadable. Pending
// Magnus sign-off; flagged in PR #6 follow-up comment.
public without sharing class RecordCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {
  /** @description Custom exception for errors raised inside this batch. */
  public class RecordCleanupBatchException extends UtilitiesModuleException {
  }

  private RecordCleanupContext context;

  // Stateful — accumulated across execute() chunks.
  @TestVisible
  private Map<String, Integer> deletedCountByRule = new Map<String, Integer>();
  @TestVisible
  private Map<String, Integer> errorCountByRule = new Map<String, Integer>();

  /** @description Default constructor; uses the production `RecordCleanupContext`. */
  public RecordCleanupBatch() {
    this(new RecordCleanupContext());
  }

  /**
   * @description Injection constructor used in tests.
   *
   * @param context The `RecordCleanupContext` (or mock) to source rules from.
   */
  @TestVisible
  public RecordCleanupBatch(RecordCleanupContext context) {
    this.context = context;
  }

  // ─── Batchable ────────────────────────────────────────────────────────────

  /**
   * @description Collects every candidate record from every active rule.
   *              Returns `Iterable<SObject>` (not `QueryLocator`) because the
   *              batch processes multiple heterogeneous SObject types in one
   *              run — a single `QueryLocator` cannot span objects.
   *
   *              Dynamic SOQL is unavoidable: the target SObject is runtime
   *              data from CMDT. No user input is concatenated; CMDT rows are
   *              authored only via metadata deploy.
   *
   * @param bc The batchable context reference.
   * @return   The combined candidate set across all rules.
   */
  public Iterable<SObject> start(Database.BatchableContext bc) {
    Logger.info(
      'RecordCleanupBatch starting — collecting candidates from active rules.',
      'RecordCleanupBatch',
      'start'
    );

    List<SObject> allCandidates = new List<SObject>();
    List<RecordCleanupRule> rules = context.getActiveRules();

    for (RecordCleanupRule rule : rules) {
      try {
        allCandidates.addAll(collectCandidatesForRule(rule));
      } catch (Exception ex) {
        Logger.logException(ex, 'RecordCleanupBatch', 'start');
        incrementError(rule.developerName);
      }
    }

    return allCandidates;
  }

  /**
   * @description Deletes one chunk of candidate records. Each record carries
   *              a hidden `Cleanup_Rule_Name__c`-style hint? — no: the chunk
   *              may be mixed-SObject, so we re-evaluate the rule for each
   *              record by looking up its SObjectType. We delete in
   *              SObjectType groups so a failure on one type doesn't poison
   *              the others.
   *
   * @param bc    The batchable context reference.
   * @param scope The candidate records to delete in this chunk.
   */
  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    if (scope == null || scope.isEmpty()) {
      Logger.debug(
        'RecordCleanupBatch.execute — empty scope, nothing to do.',
        'RecordCleanupBatch',
        'execute'
      );
      return;
    }

    // Group by SObjectType so each type deletes as one DML call.
    Map<SObjectType, List<SObject>> byType = groupBySObjectType(scope);

    for (SObjectType type : byType.keySet()) {
      List<SObject> recordsOfType = byType.get(type);
      try {
        DMLManager.deleteAsSystem(recordsOfType);
        incrementDeleted(String.valueOf(type), recordsOfType.size());
      } catch (Exception ex) {
        // Log + continue per type. Throwing here would roll back the entire
        // chunk and starve other SObject types in the same scope.
        Logger.logException(ex, 'RecordCleanupBatch', 'execute');
        incrementError(String.valueOf(type));
      }
    }
  }

  /**
   * @description Emits a single summary log line per run.
   *
   * @param bc The batchable context reference.
   */
  public void finish(Database.BatchableContext bc) {
    Logger.info(
      'RecordCleanupBatch finished. Deleted: ' +
        deletedCountByRule +
        ' Errors: ' +
        errorCountByRule,
      'RecordCleanupBatch',
      'finish'
    );
  }

  // ─── Candidate collection ─────────────────────────────────────────────────

  /**
   * @description Builds and executes the SOQL for one rule, then post-filters
   *              by optional regex and optional predicate. Instantiates the
   *              predicate up front so a bulk-primable predicate can extend
   *              the SOQL projection with the fields it needs to satisfy
   *              `shouldKeep` from the loaded records (avoids per-record
   *              re-querying).
   *
   * @param rule The rule to evaluate.
   * @return     The records this rule allows the batch to delete.
   */
  @TestVisible
  private List<SObject> collectCandidatesForRule(RecordCleanupRule rule) {
    IRecordRetentionPredicate predicate = newPredicateOrNull(rule);
    List<String> extraFields = predicate instanceof IBulkPrimablePredicate
      ? ((IBulkPrimablePredicate) predicate).requiredFields()
      : null;

    String query = buildCandidateQuery(rule, extraFields);
    Date cutoffDate = Date.today().addDays(-rule.ageThresholdDays); //NOPMD — bind below

    List<SObject> rawCandidates = Database.queryWithBinds( //NOPMD
      query,
      new Map<String, Object>{ 'cutoffDate' => cutoffDate },
      AccessLevel.SYSTEM_MODE
    );

    List<SObject> afterRegex = applyRegexFilter(rule, rawCandidates);
    List<SObject> afterPredicate = applyPredicate(rule, predicate, afterRegex);

    return afterPredicate;
  }

  /**
   * @description Instantiates the rule's predicate via reflection. Returns
   *              `null` (no predicate gate) when the rule has none configured
   *              OR when instantiation fails — the latter increments the
   *              error counter, logs, and lets the rule fall through with no
   *              predicate, which produces the conservative "skip this rule's
   *              candidates" behaviour at `applyPredicate`.
   *
   * @param rule The rule whose predicate to instantiate.
   * @return     The predicate instance, or `null` when none configured /
   *             instantiation failed.
   */
  @TestVisible
  private IRecordRetentionPredicate newPredicateOrNull(RecordCleanupRule rule) {
    if (!rule.hasPredicate()) {
      return null;
    }
    try {
      Type predicateType = Type.forName(rule.predicateApexClass);
      if (predicateType == null) {
        throw new RecordCleanupBatchException(
          'Predicate class not found: ' + rule.predicateApexClass
        );
      }
      return (IRecordRetentionPredicate) predicateType.newInstance();
    } catch (Exception ex) {
      Logger.logException(ex, 'RecordCleanupBatch', 'newPredicateOrNull');
      incrementError(rule.developerName);
      return null;
    }
  }

  /**
   * @description Composes the dynamic SOQL for a rule. Always selects `Id`
   *              and the configured age field; appends an optional caller-
   *              supplied `SOQL_Where_Clause__c`; appends any extra fields
   *              the predicate declared via `IBulkPrimablePredicate.requiredFields()`.
   *
   *              Bind variable `:cutoffDate` is provided by the caller.
   *
   * @param rule        The rule whose SObject + age field + WHERE fragment we use.
   * @param extraFields Additional field API names to project (e.g. those the
   *                    bulk-primable predicate needs for in-memory resolution).
   * @return            The composed SOQL string.
   */
  @TestVisible
  private String buildCandidateQuery(
    RecordCleanupRule rule,
    List<String> extraFields
  ) {
    String fieldList = 'Id, ' + rule.ageFieldApiName;
    if (rule.hasRegexFilter()) {
      // Regex post-filter needs the field in the projection.
      if (!fieldList.containsIgnoreCase(rule.fieldRegexMatch)) {
        fieldList += ', ' + rule.fieldRegexMatch;
      }
    }
    if (extraFields != null) {
      for (String field : extraFields) {
        if (String.isNotBlank(field) && !fieldList.containsIgnoreCase(field)) {
          fieldList += ', ' + field;
        }
      }
    }

    String whereClause = rule.ageFieldApiName + ' < :cutoffDate';

    if (String.isNotBlank(rule.soqlWhereClause)) {
      whereClause += ' AND (' + rule.soqlWhereClause + ')';
    }

    return 'SELECT ' +
      fieldList +
      ' FROM ' +
      rule.sobjectApiName +
      ' WHERE ' +
      whereClause;
  }

  /**
   * @description Applies the optional regex filter. A record is kept (i.e.
   *              remains a delete candidate) when its value of
   *              `fieldRegexMatch` matches `fieldRegexPattern`. Null or empty
   *              field values are excluded from candidates by default.
   *
   * @param rule       The rule providing the regex configuration.
   * @param candidates The records to filter.
   * @return           The subset whose configured field matches the regex.
   */
  @TestVisible
  private List<SObject> applyRegexFilter(
    RecordCleanupRule rule,
    List<SObject> candidates
  ) {
    if (!rule.hasRegexFilter() || candidates.isEmpty()) {
      return candidates;
    }

    Pattern compiled = Pattern.compile(rule.fieldRegexPattern);
    List<SObject> matches = new List<SObject>();
    for (SObject record : candidates) {
      Object raw = record.get(rule.fieldRegexMatch);
      if (raw == null) {
        continue;
      }
      String value = String.valueOf(raw);
      if (compiled.matcher(value).matches()) {
        matches.add(record);
      }
    }
    return matches;
  }

  /**
   * @description Applies the optional `IRecordRetentionPredicate` to remove
   *              records the business rule says to keep. When the predicate
   *              also implements `IBulkPrimablePredicate`, `primeBulkCache`
   *              is invoked once on the chunk before the per-record loop so
   *              implementations can issue one bulk SOQL up front and resolve
   *              `shouldKeep` from in-memory caches. When the rule configured
   *              a predicate but instantiation failed upstream
   *              (`predicate == null` while `rule.hasPredicate()` is true),
   *              the conservative path is to skip this rule's candidates
   *              rather than risk deleting records the predicate would have
   *              kept.
   *
   * @param rule       The rule providing the predicate class name.
   * @param predicate  The instantiated predicate, or `null` when none /
   *                   instantiation failed.
   * @param candidates The post-SOQL, post-regex candidate list.
   * @return           Records the predicate says are OK to delete.
   */
  @TestVisible
  private List<SObject> applyPredicate(
    RecordCleanupRule rule,
    IRecordRetentionPredicate predicate,
    List<SObject> candidates
  ) {
    if (candidates.isEmpty()) {
      return candidates;
    }
    if (!rule.hasPredicate()) {
      return candidates;
    }
    if (predicate == null) {
      // Instantiation failed upstream — error already logged + counted.
      // Conservative: skip this rule's candidates rather than risk deletion.
      return new List<SObject>();
    }

    // Optional bulk-cache priming. Predicates that satisfy `shouldKeep` via
    // SOQL traversal (e.g. KeepIfAccountHasOpenOpportunity) issue one bulk
    // SOQL per chunk here, then resolve per-record with in-memory lookups —
    // avoids the 100-query governor on 200-record chunks.
    if (predicate instanceof IBulkPrimablePredicate) {
      try {
        ((IBulkPrimablePredicate) predicate).primeBulkCache(candidates);
      } catch (Exception ex) {
        Logger.logException(ex, 'RecordCleanupBatch', 'applyPredicate');
        incrementError(rule.developerName);
        // Priming failed — conservative path is to skip this rule's chunk
        // rather than fall back to per-record SOQL that risks governor blow-up.
        return new List<SObject>();
      }
    }

    List<SObject> allowed = new List<SObject>();
    for (SObject record : candidates) {
      try {
        if (!predicate.shouldKeep(record)) {
          allowed.add(record);
        }
      } catch (Exception ex) {
        Logger.logException(ex, 'RecordCleanupBatch', 'applyPredicate');
        incrementError(rule.developerName);
        // On predicate failure for one record, conservative path: keep it.
      }
    }
    return allowed;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /**
   * @description Groups a mixed-type scope by `SObjectType` so the batch can
   *              issue one DML per type.
   *
   * @param scope The mixed candidate list.
   * @return      Map of SObjectType to its records in `scope`.
   */
  @TestVisible
  private Map<SObjectType, List<SObject>> groupBySObjectType(
    List<SObject> scope
  ) {
    Map<SObjectType, List<SObject>> byType = new Map<SObjectType, List<SObject>>();
    for (SObject record : scope) {
      SObjectType type = record.getSObjectType();
      if (!byType.containsKey(type)) {
        byType.put(type, new List<SObject>());
      }
      byType.get(type).add(record);
    }
    return byType;
  }

  /**
   * @description Increments the stateful deleted counter for a key.
   *
   * @param key      The bucket key (rule name or SObject API name).
   * @param howMany  How many records were deleted in this chunk.
   */
  private void incrementDeleted(String key, Integer howMany) {
    Integer current = deletedCountByRule.containsKey(key)
      ? deletedCountByRule.get(key)
      : 0;
    deletedCountByRule.put(key, current + howMany);
  }

  /**
   * @description Increments the stateful error counter for a key.
   *
   * @param key The bucket key (rule name or SObject API name).
   */
  private void incrementError(String key) {
    Integer current = errorCountByRule.containsKey(key)
      ? errorCountByRule.get(key)
      : 0;
    errorCountByRule.put(key, current + 1);
  }
}
