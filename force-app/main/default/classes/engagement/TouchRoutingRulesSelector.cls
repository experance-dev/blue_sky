/**
 * @description Selector for `Touch_Routing_Rule__mdt`. Returns the ordered set
 *              of active routing rules consumed by `EngagementSignalRouter` to
 *              translate resolved `Engagement_Touch__c` records into
 *              `Opportunity_Engagement_Signal__c` rows.
 *
 *              Per §1.2.1 the implementation prefers
 *              `Touch_Routing_Rule__mdt.getAll().values()` over SOQL: CMDT
 *              is platform-cached, the Type accessor is zero-SOQL, and the
 *              in-memory filter + insertion sort is fast at any realistic
 *              CMDT cardinality. Drops the prior `pmd:ApexCRUDViolation`
 *              risk surface entirely.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 * @last 2026-05-16 — PR #6 sweep: §1.2.1 SOQL → Type.getAll() conversion; in-memory filter + sort.
 */
public with sharing class TouchRoutingRulesSelector {
  /**
   * @description Returns all ACTIVE routing rules, sorted by Priority ASC so
   *              the highest-priority (lowest-number) rule is evaluated first.
   *              Reads `Touch_Routing_Rule__mdt.getAll().values()` (zero
   *              SOQL — platform-cached). Insertion-sort over the active
   *              subset keeps the sort O(n^2) on a collection whose realistic
   *              max is in the dozens.
   * @return List<Touch_Routing_Rule__mdt> ordered by Priority__c ASC.
   */
  public static List<Touch_Routing_Rule__mdt> selectActiveOrderedByPriority() {
    List<Touch_Routing_Rule__mdt> active = new List<Touch_Routing_Rule__mdt>();
    for (
      Touch_Routing_Rule__mdt rule : Touch_Routing_Rule__mdt.getAll().values()
    ) {
      if (rule.Active__c == true) {
        active.add(rule);
      }
    }
    sortByPriorityAsc(active);
    return active;
  }

  /**
   * @description In-place sort by `Priority__c` ASC, nulls last. Implemented
   *              as an insertion-style swap loop because Apex's `List.sort()`
   *              requires Comparable on the element type and `__mdt`
   *              instances are not comparable.
   * @param rules CMDT row list to sort; mutated in place.
   */
  private static void sortByPriorityAsc(List<Touch_Routing_Rule__mdt> rules) {
    Integer size = rules.size();
    for (Integer i = 1; i < size; i++) {
      Touch_Routing_Rule__mdt current = rules[i];
      Integer j = i - 1;
      while (j >= 0 && compareAsc(rules[j], current) > 0) {
        rules[j + 1] = rules[j];
        j--;
      }
      rules[j + 1] = current;
    }
  }

  private static Integer compareAsc(
    Touch_Routing_Rule__mdt a,
    Touch_Routing_Rule__mdt b
  ) {
    if (a.Priority__c == b.Priority__c) {
      return 0;
    }
    if (a.Priority__c == null) {
      return 1;
    }
    if (b.Priority__c == null) {
      return -1;
    }
    return (a.Priority__c < b.Priority__c) ? -1 : 1;
  }
}
