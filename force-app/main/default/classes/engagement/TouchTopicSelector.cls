/**
 * @description Selector for Touch_Topic__c records. Centralizes SOQL used by
 *              the Engagement Attribution feature to render the topic taxonomy
 *              and to scope topic lookups to a single Opportunity. Phase 1
 *              leverages the simple Opportunity.Touch_Topic__c lookup added in
 *              Wave A; Phase 3 will replace that with a Product2 → Topic map.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class TouchTopicSelector {
  /**
   * @description Returns the full Touch_Topic catalog, alphabetized by Topic_Name__c.
   *              Bounded at 200 rows — the topic taxonomy is intentionally small
   *              (handoff §Touch_Topic seed lists ~6 entries).
   * @return List of Touch_Topic__c records ordered by Topic_Name__c ascending.
   */
  public static List<Touch_Topic__c> selectAll() {
    return [
      SELECT
        Id,
        Name,
        Topic_Name__c,
        External_Code__c,
        Parent_Topic__c,
        Parent_Topic__r.Name
      FROM Touch_Topic__c
      WITH USER_MODE
      ORDER BY Topic_Name__c ASC
      LIMIT 200
    ];
  }

  /**
   * @description Returns the requested Touch_Topic records keyed by Id for O(1)
   *              lookup in the Service layer. Null or empty input returns an
   *              empty map — callers should not have to null-check the result.
   * @param topicIds Set of Touch_Topic__c Ids to load.
   * @return Map of Id to Touch_Topic__c (empty when input is null or empty).
   */
  public static Map<Id, Touch_Topic__c> selectByIds(Set<Id> topicIds) {
    if (topicIds == null || topicIds.isEmpty()) {
      return new Map<Id, Touch_Topic__c>();
    }
    return new Map<Id, Touch_Topic__c>(
      [
        SELECT
          Id,
          Name,
          Topic_Name__c,
          External_Code__c,
          Parent_Topic__c,
          Parent_Topic__r.Name
        FROM Touch_Topic__c
        WHERE Id IN :topicIds
        WITH USER_MODE
      ]
    );
  }

  /**
   * @description Phase 1: returns all topics. Phase 3 will filter by the
   *              Opportunity's Product2 → Touch_Topic mapping. As an interim,
   *              when the Opportunity has a single Touch_Topic__c lookup set
   *              (added in Wave A), this returns only that topic — letting the
   *              Service layer scope the engagement query without waiting for
   *              the Product2 junction.
   * @param opportunityId Id of the Opportunity providing topic context.
   * @return List of Touch_Topic__c records — scoped to the opportunity's
   *         Touch_Topic__c when set, otherwise the full catalog.
   */
  public static List<Touch_Topic__c> selectByOpportunityId(Id opportunityId) {
    if (opportunityId == null) {
      return selectAll();
    }
    List<Opportunity> opps = [
      SELECT Touch_Topic__c
      FROM Opportunity
      WHERE Id = :opportunityId
      WITH USER_MODE
      LIMIT 1
    ];
    if (opps.isEmpty() || opps[0].Touch_Topic__c == null) {
      return selectAll();
    }
    return selectByIds(new Set<Id>{ opps[0].Touch_Topic__c }).values();
  }
}
