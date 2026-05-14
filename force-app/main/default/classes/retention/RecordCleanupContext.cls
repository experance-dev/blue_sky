/**
 * @description Reads active rules from `Record_Retention_Rule__mdt` and returns
 *              them as immutable value objects (`RecordCleanupRule`) for the
 *              batch to iterate. Encapsulates the CMDT shape so the batch never
 *              touches CMDT directly — this is what makes the framework easy
 *              to unit-test (subclass + override `getActiveRules` for fakes).
 *
 *              **Why this class exists separate from the batch.** The batch
 *              cares about *what to delete*; the context cares about *what the
 *              rules say*. Splitting them lets tests inject deterministic rule
 *              lists without touching CMDT (which is org-state, not test
 *              fixture material).
 *
 * @group Cleanup
 * @author David Wood
 * @since May 2026
 */
public virtual inherited sharing class RecordCleanupContext {
  /**
   * @description Loads every active `Record_Retention_Rule__mdt` row and maps
   *              each to a `RecordCleanupRule` value object. Inactive rows are
   *              excluded — the `Active__c` checkbox is a per-rule kill-switch.
   *
   *              Uses `WITH SYSTEM_MODE` per project convention for CMDT reads
   *              (CMDT bypasses CRUD/FLS by platform rule; `USER_MODE` is
   *              policy-theater on `__mdt`).
   *
   * @return The active retention rules, ordered by SObject API name then label
   *         for stable processing order.
   */
  public virtual List<RecordCleanupRule> getActiveRules() {
    List<Record_Retention_Rule__mdt> rows = [
      SELECT
        DeveloperName,
        Label,
        SObject_API_Name__c,
        Age_Field_API_Name__c,
        Age_Threshold_Days__c,
        Predicate_Apex_Class__c,
        SOQL_Where_Clause__c,
        Field_Regex_Match__c,
        Field_Regex_Pattern__c,
        Action__c,
        Active__c
      FROM Record_Retention_Rule__mdt
      WHERE Active__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY SObject_API_Name__c, Label
    ];

    List<RecordCleanupRule> rules = new List<RecordCleanupRule>();
    for (Record_Retention_Rule__mdt row : rows) {
      rules.add(RecordCleanupRule.fromMetadata(row));
    }
    return rules;
  }
}
