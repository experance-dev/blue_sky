/**
 * @description Selector for `Touch_Routing_Rule__mdt`. Returns the ordered set
 *              of active routing rules consumed by `EngagementSignalRouter` to
 *              translate resolved `Engagement_Touch__c` records into
 *              `Opportunity_Engagement_Signal__c` rows.
 *
 *              Custom Metadata Type queries are not subject to USER_MODE
 *              FLS — visibility is platform-enforced — so the SOQL here omits
 *              the `WITH USER_MODE` clause intentionally (apex.md ยง Conventions).
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class TouchRoutingRulesSelector {
  /**
   * @description Returns all ACTIVE routing rules, sorted by Priority ASC so
   *              the highest-priority (lowest-number) rule is evaluated first.
   * @return List<Touch_Routing_Rule__mdt> ordered by Priority__c ASC.
   */
  public static List<Touch_Routing_Rule__mdt> selectActiveOrderedByPriority() {
    return [
      SELECT
        DeveloperName,
        Label,
        Priority__c,
        Active__c,
        Match_Path__c,
        Require_Same_Account__c,
        Require_Topic_Match__c,
        Persona_Filter__c,
        Touch_Type_Filter__c,
        Min_Intent_Level__c,
        Confidence__c,
        Description__c
      FROM Touch_Routing_Rule__mdt
      WHERE Active__c = TRUE
      ORDER BY Priority__c ASC
    ];
  }
}
