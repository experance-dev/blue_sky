/**
 * @description Immutable value object describing a single retention rule.
 *              Wraps a `Record_Retention_Rule__mdt` row in a typed shape the
 *              batch can consume without ever touching the raw CMDT SObject.
 *              Tests build instances directly via the constructor; production
 *              code goes through `fromMetadata(row)`.
 *
 *              **Field meanings** (from the CMDT):
 *              - `sobjectApiName` — target SObject, e.g. `Engagement_Touch__c`.
 *              - `ageFieldApiName` — DateTime field for age comparison;
 *                defaults to `CreatedDate` when blank on the CMDT row.
 *              - `ageThresholdDays` — records older than this many days are
 *                candidates for deletion.
 *              - `predicateApexClass` — optional Apex class implementing
 *                `IRecordRetentionPredicate` for business-rule gating.
 *              - `soqlWhereClause` — optional raw SOQL fragment appended to
 *                the candidate-selection query. Use with care: this is
 *                concatenated into a dynamic SOQL string. Author CMDT rows
 *                only via the metadata-deploy path (no user input).
 *              - `fieldRegexMatch` / `fieldRegexPattern` — optional field-name
 *                + regex pair for an additional post-SOQL filter.
 *              - `action` — `Delete` or `Archive`. (Archive deferred — see
 *                `RecordCleanupBatch.execute`.)
 *
 * @group Cleanup
 * @author David Wood
 * @since May 2026
 */
public inherited sharing class RecordCleanupRule {
  public static final String DEFAULT_AGE_FIELD = 'CreatedDate';

  public String developerName { get; private set; }
  public String label { get; private set; }
  public String sobjectApiName { get; private set; }
  public String ageFieldApiName { get; private set; }
  public Integer ageThresholdDays { get; private set; }
  public String predicateApexClass { get; private set; }
  public String soqlWhereClause { get; private set; }
  public String fieldRegexMatch { get; private set; }
  public String fieldRegexPattern { get; private set; }
  public String action { get; private set; }

  /**
   * @description Full-fidelity constructor — used by tests and `fromMetadata`.
   *              All optional fields accept `null`.
   *
   * @param developerName     CMDT row DeveloperName (stable id for logging).
   * @param label             CMDT row Label (human-readable rule name).
   * @param sobjectApiName    Required target SObject API name.
   * @param ageFieldApiName   DateTime field for age comparison; `CreatedDate`
   *                          if blank.
   * @param ageThresholdDays  Required positive day count.
   * @param predicateApexClass Optional Apex class for keep/discard gating.
   * @param soqlWhereClause   Optional raw SOQL fragment.
   * @param fieldRegexMatch   Optional field name for regex post-filter.
   * @param fieldRegexPattern Optional regex pattern.
   * @param action            Required: `Delete` or `Archive`.
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public RecordCleanupRule(
    String developerName,
    String label,
    String sobjectApiName,
    String ageFieldApiName,
    Integer ageThresholdDays,
    String predicateApexClass,
    String soqlWhereClause,
    String fieldRegexMatch,
    String fieldRegexPattern,
    String action
  ) {
    this.developerName = developerName;
    this.label = label;
    this.sobjectApiName = sobjectApiName;
    this.ageFieldApiName = String.isBlank(ageFieldApiName)
      ? DEFAULT_AGE_FIELD
      : ageFieldApiName;
    this.ageThresholdDays = ageThresholdDays;
    this.predicateApexClass = predicateApexClass;
    this.soqlWhereClause = soqlWhereClause;
    this.fieldRegexMatch = fieldRegexMatch;
    this.fieldRegexPattern = fieldRegexPattern;
    this.action = action;
  }

  /**
   * @description Maps a CMDT row to a `RecordCleanupRule`.
   *
   * @param row A `Record_Retention_Rule__mdt` record loaded by the context.
   * @return    The value-object form of the rule.
   */
  public static RecordCleanupRule fromMetadata(Record_Retention_Rule__mdt row) {
    Integer thresholdDays = row.Age_Threshold_Days__c == null
      ? null
      : Integer.valueOf(row.Age_Threshold_Days__c);

    return new RecordCleanupRule(
      row.DeveloperName,
      row.Label,
      row.SObject_API_Name__c,
      row.Age_Field_API_Name__c,
      thresholdDays,
      row.Predicate_Apex_Class__c,
      row.SOQL_Where_Clause__c,
      row.Field_Regex_Match__c,
      row.Field_Regex_Pattern__c,
      row.Action__c
    );
  }

  /**
   * @description True when this rule has a custom predicate to invoke after
   *              the SOQL candidate set has been loaded.
   *
   * @return Whether `predicateApexClass` is set.
   */
  public Boolean hasPredicate() {
    return String.isNotBlank(predicateApexClass);
  }

  /**
   * @description True when this rule has both a field name and a regex
   *              configured for the optional regex post-filter.
   *
   * @return Whether the regex filter is fully configured.
   */
  public Boolean hasRegexFilter() {
    return String.isNotBlank(fieldRegexMatch) &&
      String.isNotBlank(fieldRegexPattern);
  }
}
