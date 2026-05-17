/**
 * @description Selector for `Engagement_Touch__c`. All SOQL for the object lives here.
 *              Returns active, not-errored touches in canonical field shape with parent
 *              detail for downstream DTO assembly. Bind-variable queries only; every
 *              query enforces CRUD/FLS via `WITH USER_MODE`. No business logic. No DML.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class EngagementTouchesSelector {
  // ─── Constants ────────────────────────────────────────────────────────────────

  private static final Integer DEFAULT_ROW_CAP = 5000;
  private static final Set<String> ACTIVE_PROCESSING_STATUSES = new Set<String>{
    'New',
    'Processed'
  };

  // ─── Public selector methods ──────────────────────────────────────────────────

  /**
   * @description Returns active engagement touches (Processing_Status in {New, Processed},
   *              Is_Active = true) for the supplied set of Account Ids, ordered by
   *              Occurred_At descending. Capped at 5,000 rows defensively.
   * @param accountIds Account Ids to filter on. A null or empty set short-circuits
   *                   to an empty list without running a query.
   * @return List of `Engagement_Touch__c` records with parent Contact, Topic, and
   *         Campaign fields populated.
   */
  public static List<Engagement_Touch__c> selectByAccountIds(
    Set<Id> accountIds
  ) {
    if (accountIds == null || accountIds.isEmpty()) {
      return new List<Engagement_Touch__c>();
    }
    Set<String> activeStatuses = ACTIVE_PROCESSING_STATUSES;
    return [
      SELECT
        Id,
        Name,
        Account__c,
        Contact__c,
        Contact__r.Name,
        Contact__r.Title,
        Contact__r.Is_Consultant__c,
        Contact__r.Account.Name,
        Topic__c,
        Topic__r.Name,
        Campaign__c,
        Campaign__r.Name,
        Asset_Name__c,
        Asset_Url__c,
        Touch_Type__c,
        Touch_Subtype__c,
        Source_Event_Type__c,
        Email_At_Touch__c,
        Persona__c,
        Intent_Level__c,
        Occurred_At__c,
        Resolution_Status__c,
        Source_System__c
      FROM Engagement_Touch__c
      WHERE
        Account__c IN :accountIds
        AND Is_Active__c = TRUE
        AND Processing_Status__c IN :activeStatuses
      WITH USER_MODE
      ORDER BY Occurred_At__c DESC
      LIMIT 5000
    ];
  }

  /**
   * @description Returns active engagement touches for the Opportunity's Account,
   *              optionally narrowed by Touch_Topic Ids. Resolves the Opportunity's
   *              AccountId in a separate query first; if the Opportunity does not
   *              exist or the calling user cannot see it under USER_MODE, returns
   *              an empty list.
   *
   *              Topic filter degrades gracefully: when `topicIds` is null or empty,
   *              the method returns every active touch on the Opportunity's Account
   *              (no topic constraint applied).
   * @param opportunityId Opportunity whose AccountId scopes the second query.
   * @param topicIds      Optional Touch_Topic Ids; empty/null skips topic filtering.
   * @return List of `Engagement_Touch__c` records ordered by Occurred_At descending,
   *         capped at 5,000.
   */
  public static List<Engagement_Touch__c> selectByOpportunityWithTopics(
    Id opportunityId,
    Set<Id> topicIds
  ) {
    if (opportunityId == null) {
      return new List<Engagement_Touch__c>();
    }

    List<Opportunity> opps = [
      SELECT AccountId
      FROM Opportunity
      WHERE Id = :opportunityId
      WITH USER_MODE
      LIMIT 1
    ];
    if (opps.isEmpty() || opps[0].AccountId == null) {
      return new List<Engagement_Touch__c>();
    }

    Id accountId = opps[0].AccountId;
    Boolean filterByTopic = topicIds != null && !topicIds.isEmpty();
    Set<Id> effectiveTopicIds = filterByTopic ? topicIds : new Set<Id>();
    Set<String> activeStatuses = ACTIVE_PROCESSING_STATUSES;

    if (filterByTopic) {
      return [
        SELECT
          Id,
          Name,
          Account__c,
          Contact__c,
          Contact__r.Name,
          Contact__r.Title,
          Contact__r.Is_Consultant__c,
          Contact__r.Account.Name,
          Topic__c,
          Topic__r.Name,
          Campaign__c,
          Campaign__r.Name,
          Asset_Name__c,
          Asset_Url__c,
          Touch_Type__c,
          Touch_Subtype__c,
          Source_Event_Type__c,
          Email_At_Touch__c,
          Persona__c,
          Intent_Level__c,
          Occurred_At__c,
          Resolution_Status__c,
          Source_System__c
        FROM Engagement_Touch__c
        WHERE
          Account__c = :accountId
          AND Topic__c IN :effectiveTopicIds
          AND Is_Active__c = TRUE
          AND Processing_Status__c IN :activeStatuses
        WITH USER_MODE
        ORDER BY Occurred_At__c DESC
        LIMIT 5000
      ];
    }

    return [
      SELECT
        Id,
        Name,
        Account__c,
        Contact__c,
        Contact__r.Name,
        Contact__r.Title,
        Contact__r.Is_Consultant__c,
        Contact__r.Account.Name,
        Topic__c,
        Topic__r.Name,
        Campaign__c,
        Campaign__r.Name,
        Asset_Name__c,
        Asset_Url__c,
        Touch_Type__c,
        Touch_Subtype__c,
        Source_Event_Type__c,
        Email_At_Touch__c,
        Persona__c,
        Intent_Level__c,
        Occurred_At__c,
        Resolution_Status__c,
        Source_System__c
      FROM Engagement_Touch__c
      WHERE
        Account__c = :accountId
        AND Is_Active__c = TRUE
        AND Processing_Status__c IN :activeStatuses
      WITH USER_MODE
      ORDER BY Occurred_At__c DESC
      LIMIT 5000
    ];
  }
}
