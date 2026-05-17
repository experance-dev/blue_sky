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
 * @last 2026-05-16 — PR #6 sweep: §1.2.1 SOQL → Type.getAll() conversion; in-memory filter + sort.
 */
public virtual inherited sharing class RecordCleanupContext {
  /**
   * @description Loads every active `Record_Retention_Rule__mdt` row and maps
   *              each to a `RecordCleanupRule` value object. Inactive rows are
   *              excluded — the `Active__c` checkbox is a per-rule kill-switch.
   *
   *              Per §1.2.1 reads `Record_Retention_Rule__mdt.getAll().values()`
   *              over SOQL: zero governor cost, platform-cached, and there is
   *              no `pmd:ApexCRUDViolation` flag to suppress. In-memory filter
   *              + sort runs on what is realistically a dozens-of-rules
   *              collection.
   *
   * @return The active retention rules, ordered by SObject API name then label
   *         for stable processing order.
   */
  public virtual List<RecordCleanupRule> getActiveRules() {
    List<Record_Retention_Rule__mdt> active = new List<Record_Retention_Rule__mdt>();
    for (
      Record_Retention_Rule__mdt row : Record_Retention_Rule__mdt.getAll()
        .values()
    ) {
      if (row.Active__c == true) {
        active.add(row);
      }
    }
    sortBySObjectThenLabel(active);

    List<RecordCleanupRule> rules = new List<RecordCleanupRule>();
    for (Record_Retention_Rule__mdt row : active) {
      rules.add(RecordCleanupRule.fromMetadata(row));
    }
    return rules;
  }

  /**
   * @description In-place sort by `SObject_API_Name__c` ASC then `Label` ASC,
   *              nulls last on each key. Insertion-style swap because Apex's
   *              `List.sort()` requires Comparable on the element type and
   *              `__mdt` rows are not comparable.
   * @param rules CMDT row list to sort; mutated in place.
   */
  private static void sortBySObjectThenLabel(
    List<Record_Retention_Rule__mdt> rules
  ) {
    Integer size = rules.size();
    for (Integer i = 1; i < size; i++) {
      Record_Retention_Rule__mdt current = rules[i];
      Integer j = i - 1;
      while (j >= 0 && compareRows(rules[j], current) > 0) {
        rules[j + 1] = rules[j];
        j--;
      }
      rules[j + 1] = current;
    }
  }

  private static Integer compareRows(
    Record_Retention_Rule__mdt a,
    Record_Retention_Rule__mdt b
  ) {
    Integer primary = compareNullable(
      a.SObject_API_Name__c,
      b.SObject_API_Name__c
    );
    if (primary != 0) {
      return primary;
    }
    return compareNullable(a.Label, b.Label);
  }

  private static Integer compareNullable(String a, String b) {
    if (a == b) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }
}
