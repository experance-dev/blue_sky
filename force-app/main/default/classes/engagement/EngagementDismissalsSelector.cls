/**
 * @description Selector for `Engagement_Dismissal__c`. Returns the running
 *              user's most-recent dismissal per Contact, scoped to either an
 *              Opportunity or an Account. Multiple dismissal rows per
 *              (user, contact, scope) are reduced to MAX(Dismissed_At__c) via
 *              an ORDER BY Dismissed_At DESC pass with first-write-wins into
 *              a Map. Bind-variable queries only; every query enforces
 *              CRUD/FLS via `WITH USER_MODE`. No business logic. No DML.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class EngagementDismissalsSelector {
  // ─── Constants ────────────────────────────────────────────────────────────────

  private static final Integer DEFAULT_ROW_CAP = 5000;

  // ─── Public selector methods ──────────────────────────────────────────────────

  /**
   * @description Returns the running user's most-recent dismissal per Contact
   *              for the given Opportunity scope. Multiple dismissal records
   *              per (user, contact, opp) are reduced to MAX(Dismissed_At__c)
   *              because the query orders DESC and the Map only keeps the
   *              first value per Contact key.
   * @param opportunityId Opportunity scope for the dismissal lookup. A null
   *                      Id short-circuits to an empty map without a query.
   * @return Map keyed by Contact Id with the latest Dismissed_At DateTime.
   */
  public static Map<Id, DateTime> selectLatestByOpportunityForCurrentUser(
    Id opportunityId
  ) {
    Map<Id, DateTime> result = new Map<Id, DateTime>();
    if (opportunityId == null) {
      return result;
    }
    for (Engagement_Dismissal__c d : [
      SELECT Contact__c, Dismissed_At__c
      FROM Engagement_Dismissal__c
      WHERE
        Opportunity__c = :opportunityId
        AND CreatedById = :UserInfo.getUserId()
        AND Contact__c != NULL
      WITH USER_MODE
      ORDER BY Dismissed_At__c DESC
      LIMIT 5000
    ]) {
      if (!result.containsKey(d.Contact__c)) {
        result.put(d.Contact__c, d.Dismissed_At__c);
      }
    }
    return result;
  }

  /**
   * @description Returns the running user's most-recent dismissal per Contact
   *              for the given Account scope. Same semantics as the
   *              Opportunity-scoped variant: ORDER BY DESC + first-write-wins
   *              yields MAX(Dismissed_At__c) in a single pass.
   * @param accountId Account scope for the dismissal lookup. A null Id
   *                  short-circuits to an empty map without a query.
   * @return Map keyed by Contact Id with the latest Dismissed_At DateTime.
   */
  public static Map<Id, DateTime> selectLatestByAccountForCurrentUser(
    Id accountId
  ) {
    Map<Id, DateTime> result = new Map<Id, DateTime>();
    if (accountId == null) {
      return result;
    }
    for (Engagement_Dismissal__c d : [
      SELECT Contact__c, Dismissed_At__c
      FROM Engagement_Dismissal__c
      WHERE
        Account__c = :accountId
        AND CreatedById = :UserInfo.getUserId()
        AND Contact__c != NULL
      WITH USER_MODE
      ORDER BY Dismissed_At__c DESC
      LIMIT 5000
    ]) {
      if (!result.containsKey(d.Contact__c)) {
        result.put(d.Contact__c, d.Dismissed_At__c);
      }
    }
    return result;
  }
}
