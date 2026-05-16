/**
 * @description LWC-facing controller for the Phase 4 admin tools: Test-a-Touch,
 *              Rule Coverage, and Error Queue. Wraps the routing + identity
 *              resolution services so admins can validate the pipeline and
 *              triage problem touches without touching the seed scripts or
 *              REST endpoint. Every catch funnels through `Logger.error` and
 *              rethrows `AuraHandledException` with a sanitized user message
 *              so the LWC layer never receives a raw stack trace.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 * @last 2026-05-16 — PR #6 sweep: §3.4 admin moderation audit-trail (Logger.info on testTouch/retryResolution/ignoreTouch success); §3.2 txn correlation ID via buildAura() on every AuraHandledException; §3.1 Logger.logException across all catch sites; §1.2.1 Touch_Routing_Rule__mdt.getInstance() over CMDT SOQL; validateRoutingRulePayload decomposed into focused per-field helpers.
 */
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity')
public with sharing class EngagementAdminController {
  // §12 narrow waiver — Class-level CC + Cognitive: this controller fronts
  // four independent admin surfaces (Test-a-Touch, Rule Coverage, Routing
  // Rule CRUD, Error Queue). Per-method complexity is in spec (highest is 10,
  // and that's the canonical try/catch + AuraHandledException perimeter on
  // updateTouchRoutingRule); the class-level total flags because the surface
  // count is high, not because any path is dense. Proposed standards-doc
  // canon: class-level CC waiver on @AuraEnabled-only controllers whose
  // per-method CC is ≤10.
  // ─── Constants ────────────────────────────────────────────────────────────

  private static final String CLASS_NAME = 'EngagementAdminController';
  private static final String STATUS_RESOLVED = 'Resolved';
  private static final String STATUS_AMBIGUOUS = 'Ambiguous';
  private static final String STATUS_NO_MATCH = 'NoMatch';
  private static final String PROC_NEW = 'New';
  private static final String PROC_PROCESSED = 'Processed';
  private static final String PROC_ERROR = 'Error';
  private static final String PROC_IGNORED = 'Ignored';
  private static final String DEFAULT_SOURCE = 'Manual';
  private static final Integer DEFAULT_ISSUE_LIMIT = 50;
  private static final Integer COVERAGE_WINDOW_DAYS = 30;
  private static final String GENERIC_FAILURE = 'Unable to complete the request. Check the Engagement logs for details.';
  private static final Set<String> VALID_INTENT_LEVELS = new Set<String>{
    'Low',
    'Medium',
    'High'
  };
  private static final Set<String> VALID_TOUCH_TYPES = new Set<String>{
    'Page',
    'Download',
    'Webinar',
    'Form',
    'Event'
  };

  /**
   * @description Builds a sanitized AuraHandledException carrying the txn
   *              correlation ID. Per §3.2 the admin gets an actionable
   *              "Error ID: X" thread to query Logger_Log__c against — the
   *              raw stack stays in Logger via `Logger.logException`.
   * @return AuraHandledException with the generic-failure message + txn ID.
   */
  private static AuraHandledException buildAura() {
    return new AuraHandledException(
      GENERIC_FAILURE +
        ' Error ID: ' +
        System.Request.getCurrent().getRequestId()
    );
  }

  // ─── Test-a-Touch ─────────────────────────────────────────────────────────

  /**
   * @description Synthesizes a single `Engagement_Touch__c`, runs it through
   *              identity resolution and the signal router, and returns a
   *              human-readable summary so the admin can verify rules in one
   *              click. The touch is persisted (Is_Active__c=true) so the
   *              resulting signals stay traceable to the source.
   * @param input Form-supplied touch attributes (email is required).
   * @return TestTouchResult summarizing what the pipeline did.
   */
  @AuraEnabled
  public static TestTouchResult testTouch(TestTouchInput input) {
    try {
      validateInput(input);
      Id topicId = lookupTopicId(input.topicExternalCode);
      Engagement_Touch__c touch = buildTouch(input, topicId);

      List<String> messages = new List<String>();
      messages.add('Created Engagement_Touch__c from form input.');

      DMLManager.insertAsUser(touch);

      Engagement_Touch__c reloaded = reloadTouch(touch.Id);
      runResolution(reloaded, messages);

      Set<Id> signalIds = routeIfResolved(reloaded, messages);
      // §3.4 — admin moderation audit. Captures actor + action + target on the
      // success path so "who synthesised this touch" is recoverable without
      // git-archaeology.
      Logger.info(
        UserInfo.getUserName() +
          ' tested touch ' +
          reloaded.Id +
          ' email=' +
          input.email +
          ' resolution=' +
          reloaded.Resolution_Status__c +
          ' signals=' +
          signalIds.size(),
        CLASS_NAME,
        'testTouch'
      );
      return buildResult(reloaded, signalIds, messages);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'testTouch');
      throw buildAura();
    }
  }

  // ─── Rule Coverage ────────────────────────────────────────────────────────

  /**
   * @description Returns one row per active `Touch_Routing_Rule__mdt` paired
   *              with a signal count by `Match_Path__c` for the last 30 days.
   *              Counts are per-match-path (Phase 1 fidelity) — two rules
   *              that share a path will report the same count. Per-rule
   *              accuracy is parked for Phase 4.1 (needs
   *              `Rule_Developer_Name__c` on the signal object).
   * @return List of RuleCoverage rows ordered by rule priority ascending.
   */
  @AuraEnabled(cacheable=true)
  public static List<RuleCoverage> getRuleCoverage() {
    try {
      List<Touch_Routing_Rule__mdt> rules = TouchRoutingRulesSelector.selectActiveOrderedByPriority();
      Map<String, Integer> countsByPath = countSignalsByMatchPath();
      return assembleRuleCoverage(rules, countsByPath);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'getRuleCoverage');
      throw buildAura();
    }
  }

  // ─── Routing Rule Authoring (Add / Edit) ──────────────────────────────────

  /**
   * @description Creates a new `Touch_Routing_Rule__mdt` row from the
   *              admin-facing payload assembled by
   *              `c-touch-routing-rule-modal`. CMDT inserts are deployed
   *              asynchronously via `Metadata.Operations.enqueueDeployment` —
   *              the returned job Id lets the LWC surface status / poll.
   *
   *              Payload shape (camelCase keys; values are `Object`):
   *                developerName       (String, required, ~A-Z, 0-9, _)
   *                masterLabel         (String, required, ≤80)
   *                description         (String, optional, ≤255)
   *                matchPath           (String, required, ≤80)
   *                confidence          (Integer, required, 0-100)
   *                priority            (Integer, required, ≥1)
   *                active              (Boolean)
   *                requireSameAccount  (Boolean)
   *                requireTopicMatch   (Boolean)
   *                minIntentLevel      (String, optional — Low|Medium|High)
   *                personaFilter       (String, optional, ≤80)
   *                touchTypeFilter     (String, optional, semicolon-joined)
   *
   *              Validation rejects bad input with `AuraHandledException`
   *              before the deploy is enqueued. Per the platform contract,
   *              CMDT deploys are system-mode by nature; the
   *              `Marketing_Influence_Admin` permission set controls who can
   *              reach this Apex method via the LWC.
   *
   *              **Implementation status**: contract + validation are in
   *              place. The `enqueueDeployment` call + `Metadata.DeployCallback`
   *              implementation lands in a follow-up commit. Until then this
   *              method throws an `AuraHandledException` so the LWC error
   *              surface lights up cleanly during local development.
   *
   * @param payload Routing-rule attributes (see above).
   * @return Deployment job Id once enqueued.
   */
  @AuraEnabled
  public static String createTouchRoutingRule(Map<String, Object> payload) {
    try {
      validateRoutingRulePayload(payload, true);
      // TODO: David Wood — wire enqueueDeployment + DeployCallback.
      throw new AuraHandledException(
        'Routing rule deploy is not yet implemented. Track CSI-7162 follow-up.'
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'createTouchRoutingRule');
      throw buildAura();
    }
  }

  /**
   * @description Updates an existing `Touch_Routing_Rule__mdt` row. Same
   *              payload shape as `createTouchRoutingRule` minus
   *              `developerName` (which is immutable on a deployed CMDT
   *              row — supplied as a separate parameter so the LWC's
   *              edit-mode form can leave the field read-only).
   *
   *              **Implementation status**: contract + validation are in
   *              place. The deploy guts land in a follow-up commit.
   *
   * @param developerName CMDT row to update. Must already exist.
   * @param payload Mutable routing-rule attributes (see `createTouchRoutingRule`).
   * @return Deployment job Id once enqueued.
   */
  @AuraEnabled
  public static String updateTouchRoutingRule(
    String developerName,
    Map<String, Object> payload
  ) {
    try {
      return doUpdateTouchRoutingRule(developerName, payload);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'updateTouchRoutingRule');
      throw buildAura();
    }
  }

  /**
   * @description Inner step for `updateTouchRoutingRule` — validates the
   *              identifier + payload, confirms the CMDT row exists, then
   *              delegates to the (still-pending) deploy pipeline. Split
   *              out so the public method retains a clean try/catch
   *              perimeter without inflating cyclomatic complexity.
   * @param developerName CMDT DeveloperName of the rule to update.
   * @param payload Mutable routing-rule attributes (see `createTouchRoutingRule`).
   * @return Deployment job Id (or throws when the deploy pipeline is wired).
   */
  private static String doUpdateTouchRoutingRule(
    String developerName,
    Map<String, Object> payload
  ) {
    if (String.isBlank(developerName)) {
      throw new AuraHandledException('Developer Name is required.');
    }
    validateRoutingRulePayload(payload, false);
    // §1.2.1 — Type.getInstance() over CMDT SOQL: zero governor cost.
    if (Touch_Routing_Rule__mdt.getInstance(developerName) == null) {
      throw new AuraHandledException(
        'Routing rule not found: ' + developerName
      );
    }
    // TODO: David Wood — wire enqueueDeployment + DeployCallback.
    throw new AuraHandledException(
      'Routing rule deploy is not yet implemented. Track CSI-7162 follow-up.'
    );
  }

  // ─── Error Queue ──────────────────────────────────────────────────────────

  /**
   * @description Returns active touches stuck in NoMatch, Ambiguous, or
   *              processing Error. Caps to `limitN` (default 50, max 200)
   *              ordered by most recent ingest first.
   * @param limitN Page size (null → 50).
   * @return List of TouchIssue DTOs for the LWC table.
   */
  @AuraEnabled(cacheable=true)
  public static List<TouchIssue> getTouchesWithIssues(Integer limitN) {
    try {
      Integer pageSize = capLimit(limitN);
      return queryTouchIssues(pageSize);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'getTouchesWithIssues');
      throw buildAura();
    }
  }

  /**
   * @description Re-runs identity resolution against the single touch — if
   *              the upstream world has changed (a Contact was created,
   *              merged, or moved Accounts) the touch may now resolve.
   *              When the retry promotes the touch to Resolved, routing
   *              runs immediately so signals materialize.
   * @param touchId Engagement_Touch__c Id to retry.
   * @return TestTouchResult mirroring `testTouch` so the LWC can render
   *         the before/after state with no additional fetches.
   */
  @AuraEnabled
  public static TestTouchResult retryResolution(Id touchId) {
    try {
      if (touchId == null) {
        throw new AuraHandledException('Touch Id is required.');
      }
      Engagement_Touch__c reloaded = reloadTouch(touchId);
      if (reloaded == null) {
        throw new AuraHandledException('Touch not found.');
      }

      List<String> messages = new List<String>();
      messages.add('Retry initiated for ' + reloaded.Name + '.');
      runResolution(reloaded, messages);
      Set<Id> signalIds = routeIfResolved(reloaded, messages);
      // §3.4 — admin moderation audit on the success path.
      Logger.info(
        UserInfo.getUserName() +
          ' retried resolution for touch ' +
          touchId +
          ' resolution=' +
          reloaded.Resolution_Status__c +
          ' signals=' +
          signalIds.size(),
        CLASS_NAME,
        'retryResolution'
      );
      return buildResult(reloaded, signalIds, messages);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'retryResolution');
      throw buildAura();
    }
  }

  /**
   * @description Marks the supplied touch as ignored — flips `Is_Active__c`
   *              off, stamps `Archived_At__c`, sets the processing status
   *              to `Ignored`, and stores the admin-supplied reason in
   *              `Processing_Message__c`. The row stays for audit.
   * @param touchId Engagement_Touch__c Id to retire.
   * @param reason Free-form admin note (required, max ~ 32k by field).
   */
  @AuraEnabled
  public static void ignoreTouch(Id touchId, String reason) {
    try {
      if (touchId == null) {
        throw new AuraHandledException('Touch Id is required.');
      }
      Engagement_Touch__c touchUpdate = new Engagement_Touch__c(
        Id = touchId,
        Is_Active__c = false,
        Processing_Status__c = PROC_IGNORED,
        Archived_At__c = System.now(),
        Processing_Message__c = String.isBlank(reason)
          ? 'Ignored by admin.'
          : reason
      );
      DMLManager.updateAsUser(touchUpdate);
      // §3.4 — admin moderation audit on the success path. Reason is captured
      // verbatim so a future reviewer can reconstruct the rationale; the touch
      // row itself also retains Processing_Message__c for direct inspection.
      Logger.info(
        UserInfo.getUserName() +
          ' ignored touch ' +
          touchId +
          ' reason=' +
          (String.isBlank(reason) ? 'Ignored by admin.' : reason),
        CLASS_NAME,
        'ignoreTouch'
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'ignoreTouch');
      throw buildAura();
    }
  }

  // ─── Private — Test-a-Touch helpers ───────────────────────────────────────

  private static void validateInput(TestTouchInput input) {
    if (input == null || String.isBlank(input.email)) {
      throw new AuraHandledException('Email is required to test a touch.');
    }
  }

  private static Id lookupTopicId(String externalCode) {
    if (String.isBlank(externalCode)) {
      return null;
    }
    List<Touch_Topic__c> matches = [
      SELECT Id
      FROM Touch_Topic__c
      WHERE External_Code__c = :externalCode
      WITH USER_MODE
      LIMIT 1
    ];
    return matches.isEmpty() ? null : matches[0].Id;
  }

  private static Engagement_Touch__c buildTouch(
    TestTouchInput input,
    Id topicId
  ) {
    Engagement_Touch__c t = new Engagement_Touch__c();
    t.External_Id__c = 'ADMIN-TEST-' + System.now().getTime();
    t.Source_System__c = DEFAULT_SOURCE;
    t.Source_Event_Type__c = input.touchType;
    t.Email_At_Touch__c = input.email;
    t.Occurred_At__c = System.now();
    t.Ingested_At__c = System.now();
    t.Asset_Name__c = input.assetName;
    t.Touch_Type__c = input.touchType;
    t.Persona__c = input.persona;
    t.Intent_Level__c = input.intentLevel;
    t.Is_Active__c = true;
    t.Resolution_Status__c = 'Pending';
    t.Topic__c = topicId;
    return t;
  }

  private static Engagement_Touch__c reloadTouch(Id touchId) {
    List<Engagement_Touch__c> rows = [
      SELECT
        Id,
        Name,
        Email_At_Touch__c,
        Account__c,
        Contact__c,
        Contact__r.Name,
        Account__r.Name,
        Topic__c,
        Persona__c,
        Touch_Type__c,
        Intent_Level__c,
        Resolution_Status__c,
        Processing_Status__c,
        Processing_Message__c,
        Asset_Name__c,
        Occurred_At__c,
        Source_System__c,
        Is_Active__c
      FROM Engagement_Touch__c
      WHERE Id = :touchId
      WITH USER_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  private static void runResolution(
    Engagement_Touch__c touch,
    List<String> messages
  ) {
    IdentityResolutionService.resolveAll(
      new List<Engagement_Touch__c>{ touch }
    );
    touch.Processing_Status__c = (touch.Resolution_Status__c == STATUS_NO_MATCH)
      ? PROC_NEW
      : PROC_PROCESSED;
    DMLManager.updateAsUser(touch);
    messages.add(
      'Identity resolution returned ' + touch.Resolution_Status__c + '.'
    );
  }

  private static Set<Id> routeIfResolved(
    Engagement_Touch__c touch,
    List<String> messages
  ) {
    Set<Id> signalIds = new Set<Id>();
    if (touch.Resolution_Status__c != STATUS_RESOLVED) {
      messages.add('Routing skipped — touch is not Resolved.');
      return signalIds;
    }
    EngagementSignalRouter.routeTouches(new Set<Id>{ touch.Id });
    for (Opportunity_Engagement_Signal__c sig : [
      SELECT Id
      FROM Opportunity_Engagement_Signal__c
      WHERE Engagement_Touch__c = :touch.Id
      WITH USER_MODE
    ]) {
      signalIds.add(sig.Id);
    }
    messages.add(
      'Routing produced ' +
        signalIds.size() +
        ' signal' +
        (signalIds.size() == 1 ? '' : 's') +
        '.'
    );
    return signalIds;
  }

  private static TestTouchResult buildResult(
    Engagement_Touch__c touch,
    Set<Id> signalIds,
    List<String> messages
  ) {
    TestTouchResult result = new TestTouchResult();
    result.touchId = touch.Id;
    result.resolutionStatus = touch.Resolution_Status__c;
    result.contactId = touch.Contact__c;
    result.contactName = touch.Contact__r == null
      ? null
      : touch.Contact__r.Name;
    result.accountId = touch.Account__c;
    result.accountName = touch.Account__r == null
      ? null
      : touch.Account__r.Name;
    result.signalsCreated = signalIds.size();
    result.signals = signalIds.isEmpty()
      ? new List<SignalSummary>()
      : loadSignalSummaries(signalIds);
    result.messages = messages;
    return result;
  }

  private static List<SignalSummary> loadSignalSummaries(Set<Id> signalIds) {
    List<SignalSummary> summaries = new List<SignalSummary>();
    for (Opportunity_Engagement_Signal__c sig : [
      SELECT
        Id,
        Opportunity__c,
        Opportunity__r.Name,
        Match_Path__c,
        Confidence__c
      FROM Opportunity_Engagement_Signal__c
      WHERE Id IN :signalIds
      WITH USER_MODE
      ORDER BY Confidence__c DESC NULLS LAST
    ]) {
      SignalSummary s = new SignalSummary();
      s.signalId = sig.Id;
      s.opportunityId = sig.Opportunity__c;
      s.opportunityName = sig.Opportunity__r == null
        ? null
        : sig.Opportunity__r.Name;
      s.matchPath = sig.Match_Path__c;
      s.confidence = sig.Confidence__c;
      summaries.add(s);
    }
    return summaries;
  }

  // ─── Private — Rule Coverage helpers ──────────────────────────────────────

  private static Map<String, Integer> countSignalsByMatchPath() {
    Map<String, Integer> counts = new Map<String, Integer>();
    DateTime cutoff = System.now().addDays(-COVERAGE_WINDOW_DAYS);
    for (AggregateResult ar : [
      SELECT Match_Path__c path, COUNT(Id) total
      FROM Opportunity_Engagement_Signal__c
      WHERE CreatedDate >= :cutoff
      WITH USER_MODE
      GROUP BY Match_Path__c
    ]) {
      String path = (String) ar.get('path');
      Integer total = (Integer) ar.get('total');
      if (path != null) {
        counts.put(path, total);
      }
    }
    return counts;
  }

  private static List<RuleCoverage> assembleRuleCoverage(
    List<Touch_Routing_Rule__mdt> rules,
    Map<String, Integer> countsByPath
  ) {
    List<RuleCoverage> rows = new List<RuleCoverage>();
    for (Touch_Routing_Rule__mdt rule : rules) {
      RuleCoverage row = new RuleCoverage();
      row.ruleDeveloperName = rule.DeveloperName;
      row.ruleLabel = rule.Label;
      row.priority = rule.Priority__c;
      row.matchPath = rule.Match_Path__c;
      row.targetConfidence = rule.Confidence__c;
      row.signalsLast30Days = countsByPath.containsKey(rule.Match_Path__c)
        ? countsByPath.get(rule.Match_Path__c)
        : 0;
      row.isActive = rule.Active__c;
      rows.add(row);
    }
    return rows;
  }

  // ─── Private — Routing Rule validation ────────────────────────────────────

  /**
   * @description Validates the routing-rule payload against CMDT field
   *              constraints. Mirrors the client-side validation in
   *              `c-touch-routing-rule-modal` so the server is the source
   *              of truth — the LWC validation is an optimization, not a
   *              guarantee.
   *
   *              `isCreate=true` requires `developerName`; `isCreate=false`
   *              ignores it (the caller passes it separately).
   *
   *              Throws `AuraHandledException` on the first failure with a
   *              user-facing message; the LWC binds the exception body to
   *              `errorMessage` for inline display.
   * @param payload Routing-rule attributes (see `createTouchRoutingRule`).
   * @param isCreate True when the request is a create (forces DeveloperName
   *                 validation); false on update (DeveloperName is supplied
   *                 separately and immutable).
   */
  private static void validateRoutingRulePayload(
    Map<String, Object> payload,
    Boolean isCreate
  ) {
    if (payload == null) {
      throw new AuraHandledException('Payload is required.');
    }
    if (isCreate) {
      validateDeveloperName((String) payload.get('developerName'));
    }
    validateLabel((String) payload.get('masterLabel'));
    validateDescription((String) payload.get('description'));
    validateMatchPath((String) payload.get('matchPath'));
    validateConfidence(toInteger(payload.get('confidence')));
    validatePriority(toInteger(payload.get('priority')));
    validateIntentLevel((String) payload.get('minIntentLevel'));
    validatePersonaFilter((String) payload.get('personaFilter'));
    validateTouchTypeFilter((String) payload.get('touchTypeFilter'));
  }

  private static void validateDeveloperName(String devName) {
    if (String.isBlank(devName)) {
      throw new AuraHandledException('Developer Name is required.');
    }
    if (!Pattern.matches('^[A-Za-z][A-Za-z0-9_]{0,39}$', devName)) {
      throw new AuraHandledException(
        'Developer Name must start with a letter and contain only letters, numbers, and underscores (max 40 chars).'
      );
    }
  }

  private static void validateLabel(String label) {
    if (String.isBlank(label)) {
      throw new AuraHandledException('Label is required.');
    }
    if (label.length() > 80) {
      throw new AuraHandledException('Label must be 80 characters or fewer.');
    }
  }

  private static void validateDescription(String description) {
    if (description != null && description.length() > 255) {
      throw new AuraHandledException(
        'Description must be 255 characters or fewer.'
      );
    }
  }

  private static void validateMatchPath(String matchPath) {
    if (String.isBlank(matchPath)) {
      throw new AuraHandledException('Match Path is required.');
    }
    if (matchPath.length() > 80) {
      throw new AuraHandledException(
        'Match Path must be 80 characters or fewer.'
      );
    }
  }

  private static void validateConfidence(Integer confidence) {
    if (confidence == null) {
      throw new AuraHandledException('Confidence is required.');
    }
    if (confidence < 0 || confidence > 100) {
      throw new AuraHandledException('Confidence must be between 0 and 100.');
    }
  }

  private static void validatePriority(Integer priority) {
    if (priority == null) {
      throw new AuraHandledException('Priority is required.');
    }
    if (priority < 1) {
      throw new AuraHandledException('Priority must be a whole number ≥ 1.');
    }
  }

  private static void validateIntentLevel(String intentLevel) {
    if (
      String.isNotBlank(intentLevel) &&
      !VALID_INTENT_LEVELS.contains(intentLevel)
    ) {
      throw new AuraHandledException(
        'Min Intent Level must be Low, Medium, or High.'
      );
    }
  }

  private static void validatePersonaFilter(String personaFilter) {
    if (personaFilter != null && personaFilter.length() > 80) {
      throw new AuraHandledException(
        'Persona Filter must be 80 characters or fewer.'
      );
    }
  }

  private static void validateTouchTypeFilter(String touchTypeFilter) {
    if (String.isBlank(touchTypeFilter)) {
      return;
    }
    for (String tt : touchTypeFilter.split(';')) {
      if (String.isBlank(tt)) {
        continue;
      }
      if (!VALID_TOUCH_TYPES.contains(tt.trim())) {
        throw new AuraHandledException(
          'Touch Type Filter contains an unsupported value: ' + tt
        );
      }
    }
  }

  /**
   * @description Helper — accepts Integer, Decimal, or numeric String and
   *              returns Integer (or null on blank). JSON-bound payloads
   *              tend to arrive as Decimal; we normalize once.
   * @param v Object to coerce (Integer, Decimal, Double, String, or null).
   * @return Integer value, or null when the input is null, blank, or
   *         non-numeric.
   */
  private static Integer toInteger(Object v) {
    if (v == null) {
      return null;
    }
    if (v instanceof Integer) {
      return (Integer) v;
    }
    if (v instanceof Decimal) {
      return ((Decimal) v).intValue();
    }
    if (v instanceof Double) {
      return Integer.valueOf((Double) v);
    }
    String s = String.valueOf(v);
    if (String.isBlank(s)) {
      return null;
    }
    try {
      return Integer.valueOf(s);
    } catch (Exception e) {
      return null;
    }
  }

  // ─── Private — Error Queue helpers ────────────────────────────────────────

  private static Integer capLimit(Integer requested) {
    if (requested == null || requested <= 0) {
      return DEFAULT_ISSUE_LIMIT;
    }
    return Math.min(requested, 200);
  }

  private static List<TouchIssue> queryTouchIssues(Integer pageSize) {
    List<TouchIssue> rows = new List<TouchIssue>();
    for (Engagement_Touch__c t : [
      SELECT
        Id,
        Name,
        Email_At_Touch__c,
        Asset_Name__c,
        Resolution_Status__c,
        Processing_Message__c,
        Occurred_At__c,
        Source_System__c
      FROM Engagement_Touch__c
      WHERE
        Is_Active__c = TRUE
        AND (Resolution_Status__c = :STATUS_NO_MATCH
        OR Resolution_Status__c = :STATUS_AMBIGUOUS
        OR Processing_Status__c = :PROC_ERROR)
      WITH USER_MODE
      ORDER BY Ingested_At__c DESC NULLS LAST
      LIMIT :pageSize
    ]) {
      TouchIssue issue = new TouchIssue();
      issue.touchId = t.Id;
      issue.touchName = t.Name;
      issue.email = t.Email_At_Touch__c;
      issue.assetName = t.Asset_Name__c;
      issue.resolutionStatus = t.Resolution_Status__c;
      issue.processingMessage = t.Processing_Message__c;
      issue.occurredAt = t.Occurred_At__c;
      issue.sourceSystem = t.Source_System__c;
      rows.add(issue);
    }
    return rows;
  }

  // ─── DTO inner classes ────────────────────────────────────────────────────

  /**
   * @description Form payload from `c-engagement-test-a-touch`. Mirrors the
   *              admin-facing fields exposed in the LWC card.
   */
  public class TestTouchInput {
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String topicExternalCode;
    @AuraEnabled
    public String touchType;
    @AuraEnabled
    public String persona;
    @AuraEnabled
    public String intentLevel;
    @AuraEnabled
    public String assetName;
  }

  /**
   * @description Result shape for `testTouch` and `retryResolution` — keeps
   *              the LWC's render contract identical between the two flows
   *              so the result card is the same component in both screens.
   */
  public class TestTouchResult {
    @AuraEnabled
    public Id touchId;
    @AuraEnabled
    public String resolutionStatus;
    @AuraEnabled
    public Id contactId;
    @AuraEnabled
    public String contactName;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Integer signalsCreated;
    @AuraEnabled
    public List<SignalSummary> signals;
    @AuraEnabled
    public List<String> messages;
  }

  /**
   * @description Per-signal summary embedded in `TestTouchResult`. Holds the
   *              opportunity hotlink target plus the rule outcome columns
   *              the admin needs to verify routing.
   */
  public class SignalSummary {
    @AuraEnabled
    public Id signalId;
    @AuraEnabled
    public Id opportunityId;
    @AuraEnabled
    public String opportunityName;
    @AuraEnabled
    public String matchPath;
    @AuraEnabled
    public Decimal confidence;
  }

  /**
   * @description Per-rule row for the Rule Coverage admin table.
   */
  public class RuleCoverage {
    @AuraEnabled
    public String ruleDeveloperName;
    @AuraEnabled
    public String ruleLabel;
    @AuraEnabled
    public Decimal priority;
    @AuraEnabled
    public String matchPath;
    @AuraEnabled
    public Decimal targetConfidence;
    @AuraEnabled
    public Integer signalsLast30Days;
    @AuraEnabled
    public Boolean isActive;
  }

  /**
   * @description Per-touch row for the Error Queue admin table.
   */
  public class TouchIssue {
    @AuraEnabled
    public Id touchId;
    @AuraEnabled
    public String touchName;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String assetName;
    @AuraEnabled
    public String resolutionStatus;
    @AuraEnabled
    public String processingMessage;
    @AuraEnabled
    public DateTime occurredAt;
    @AuraEnabled
    public String sourceSystem;
  }
}
