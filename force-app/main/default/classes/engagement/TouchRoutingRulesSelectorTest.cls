/**
 * @description Tests for `TouchRoutingRulesSelector`. CMT rows cannot be
 *              inserted at test runtime — the records under assertion are the
 *              seeded `customMetadata/Touch_Routing_Rule.*.md-meta.xml` files
 *              deployed alongside this class.
 * @group Engagement Attribution
 * @see TouchRoutingRulesSelector
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class TouchRoutingRulesSelectorTest {
  /**
   * @description Confirms the selector returns the seeded rule set and that
   *              the ORDER BY Priority ASC contract is preserved (the
   *              OCR_Exact_Match rule has Priority=10 and must be first).
   */
  @IsTest
  static void selectActiveOrderedByPriorityReturnsSeededRules() {
    // CMT reads are SYSTEM-context by platform contract; runAs is a pure
    // PMD-rule satisfier here (the selector ignores user context for CMT).
    System.runAs(TestFactory.createTestUser(true, 'Standard User')) {
      Test.startTest();
      List<Touch_Routing_Rule__mdt> rules = TouchRoutingRulesSelector.selectActiveOrderedByPriority();
      Test.stopTest();

      Assert.isTrue(
        rules.size() >= 5,
        'Expected at least 5 seeded active routing rules; found ' + rules.size()
      );
      Assert.areEqual(
        10,
        (Integer) rules[0].Priority__c,
        'Expected the highest-priority rule (Priority=10) first.'
      );
    }
  }
}
