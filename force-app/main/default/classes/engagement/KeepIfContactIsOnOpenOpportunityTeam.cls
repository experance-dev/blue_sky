/**
 * @description Retention predicate for `Engagement_Touch__c`. Returns `true`
 *              (keep) when the touch's Contact appears on an OpportunityContactRole
 *              for any open Opportunity. Returns `false` (allow delete) when
 *              the contact has no presence on any open deal's contact roles.
 *
 *              **Why OCR, not Account.** The 1.5-year tier intentionally
 *              tightens past the account-level rule: a touch outlives the
 *              account-has-open-deal check only when the specific Contact is
 *              still actively on a deal team. Touches for contacts who
 *              haven't been formally added to any opportunity team after
 *              ~18 months are removed.
 *
 *              **Defensive defaults.** When the touch has no Contact, the
 *              predicate returns `true` (keep).
 *
 * @group Engagement
 * @author David Wood
 * @since May 2026
 */
public with sharing class KeepIfContactIsOnOpenOpportunityTeam implements IRecordRetentionPredicate {
  /**
   * @description Decides whether to keep this engagement touch.
   *
   * @param record Expected to be an `Engagement_Touch__c`.
   * @return       `true` to keep, `false` to allow deletion.
   */
  public Boolean shouldKeep(SObject record) {
    if (record == null) {
      return true;
    }
    Engagement_Touch__c touch = (Engagement_Touch__c) record;
    if (touch.Contact__c == null) {
      return true; // No contact anchor — keep.
    }
    return contactIsOnAnyOpenOpportunityContactRole(touch.Contact__c);
  }

  /**
   * @description Checks whether the contact is an `OpportunityContactRole` on
   *              at least one open Opportunity.
   *
   * @param contactId The contact to check.
   * @return          `true` when the contact appears on any open OCR.
   */
  @TestVisible
  private Boolean contactIsOnAnyOpenOpportunityContactRole(Id contactId) {
    Integer roleCount = [
      SELECT COUNT()
      FROM OpportunityContactRole
      WHERE ContactId = :contactId AND Opportunity.IsClosed = FALSE
      WITH USER_MODE
      LIMIT 1
    ];
    return roleCount > 0;
  }
}
