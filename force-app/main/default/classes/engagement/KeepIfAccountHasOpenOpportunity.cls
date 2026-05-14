/**
 * @description Retention predicate for `Engagement_Touch__c`. Returns `true`
 *              (keep this touch) when the touch's contact's account has at
 *              least one open Opportunity. Returns `false` (allow delete)
 *              when there is no open opportunity context — the touch is no
 *              longer commercially relevant.
 *
 *              **Defensive defaults.** When the touch has no Contact, no
 *              AccountId, or the Account doesn't exist, the predicate
 *              returns `true` (keep) — better to retain than to delete on
 *              ambiguity.
 *
 *              **Bulk-aware.** Each call traverses Contact → Account →
 *              Opportunity in a single SOQL; not chunk-cached because the
 *              RecordCleanupBatch chunk size is bounded by the platform.
 *              If a consumer sees governor pressure they should subclass and
 *              cache the open-account set on first call.
 *
 * @group Engagement
 * @author David Wood
 * @since May 2026
 */
public with sharing class KeepIfAccountHasOpenOpportunity implements IRecordRetentionPredicate {
  /**
   * @description Decides whether to keep this engagement touch.
   *
   * @param record Expected to be an `Engagement_Touch__c`. Must have either
   *               a Contact__c or an Account__c populated for the predicate
   *               to make a positive (= delete) decision.
   * @return       `true` to keep, `false` to allow deletion.
   */
  public Boolean shouldKeep(SObject record) {
    if (record == null) {
      return true; // Conservative — never delete on null.
    }

    Engagement_Touch__c touch = (Engagement_Touch__c) record;
    Id accountId = resolveAccountId(touch);
    if (accountId == null) {
      return true; // No account anchor — keep.
    }

    return accountHasOpenOpportunity(accountId);
  }

  /**
   * @description Resolves the touch's account either directly or by
   *              traversing through Contact.AccountId.
   *
   * @param touch The engagement touch.
   * @return      The resolved Account Id, or `null` when unresolvable.
   */
  @TestVisible
  private Id resolveAccountId(Engagement_Touch__c touch) {
    if (touch.Account__c != null) {
      return touch.Account__c;
    }
    if (touch.Contact__c == null) {
      return null;
    }
    List<Contact> contacts = [
      SELECT AccountId
      FROM Contact
      WHERE Id = :touch.Contact__c
      WITH USER_MODE
      LIMIT 1
    ];
    return contacts.isEmpty() ? null : contacts[0].AccountId;
  }

  /**
   * @description Checks whether an account has at least one open opportunity.
   *
   * @param accountId The account to check.
   * @return          `true` when at least one open opportunity exists.
   */
  @TestVisible
  private Boolean accountHasOpenOpportunity(Id accountId) {
    Integer openCount = [
      SELECT COUNT()
      FROM Opportunity
      WHERE AccountId = :accountId AND IsClosed = FALSE
      WITH USER_MODE
      LIMIT 1
    ];
    return openCount > 0;
  }
}
