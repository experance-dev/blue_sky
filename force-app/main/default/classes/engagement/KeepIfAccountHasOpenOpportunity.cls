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
 *              **Bulk-aware.** Implements `IBulkPrimablePredicate` — the
 *              framework calls `primeBulkCache(chunk)` once per
 *              `RecordCleanupBatch` execute chunk before the per-record
 *              `shouldKeep` loop. Priming resolves every touch's account
 *              (direct or via Contact.AccountId) and asks Opportunity once,
 *              in bulk, which of those accounts has an open deal. Per-record
 *              `shouldKeep` then resolves in-memory off two Maps and one Set
 *              — zero SOQL inside the loop, no governor risk at 200-record
 *              chunks.
 *
 * @group Engagement
 * @author David Wood
 * @since May 2026
 * @last 2026-05-16 — PR #6: SOQL-in-loop eliminated. Lifecycle hook (`primeBulkCache`) builds chunk-scoped caches of touch→account and account→hasOpenOpp; `shouldKeep` is now pure in-memory lookup. Two SOQL per chunk instead of two SOQL per record.
 */
public with sharing class KeepIfAccountHasOpenOpportunity implements IRecordRetentionPredicate, IBulkPrimablePredicate {
  // Chunk-scoped caches — rebuilt by primeBulkCache on every chunk.
  // touchId → resolved Account Id (null when unresolvable).
  @TestVisible
  private Map<Id, Id> accountIdByTouchId = new Map<Id, Id>();
  // Account ids known to have at least one open Opportunity in this chunk.
  @TestVisible
  private Set<Id> accountsWithOpenOpp = new Set<Id>();

  /**
   * @description Declares the projection fields the framework must include
   *              on every loaded `Engagement_Touch__c` so `primeBulkCache`
   *              can resolve the account anchor without a per-record re-query.
   *
   * @return Field API names: `Account__c`, `Contact__c`.
   */
  public List<String> requiredFields() {
    return new List<String>{ 'Account__c', 'Contact__c' };
  }

  /**
   * @description Bulk-prefetches the data `shouldKeep` needs for every touch
   *              in this chunk. Resolves each touch's account either directly
   *              from `Account__c` or by traversing `Contact.AccountId`, then
   *              issues one Opportunity SOQL to determine which of those
   *              accounts has at least one open deal.
   *
   * @param chunk The candidate `Engagement_Touch__c` records about to be
   *              evaluated by `shouldKeep`.
   */
  public void primeBulkCache(List<SObject> chunk) {
    // Reset previous chunk's state. Predicate instances are reused across
    // chunks within a batch run.
    accountIdByTouchId = new Map<Id, Id>();
    accountsWithOpenOpp = new Set<Id>();

    if (chunk == null || chunk.isEmpty()) {
      return;
    }

    Set<Id> contactIdsToResolve = resolveDirectAccountAnchors(chunk);
    resolveAccountAnchorsViaContact(chunk, contactIdsToResolve);
    cacheAccountsWithOpenOpp();
  }

  /**
   * @description Pass 1 — populates `accountIdByTouchId` for touches whose
   *              `Account__c` is set directly, and collects Contact ids that
   *              still need a Contact → Account hop.
   *
   * @param chunk The candidate touches.
   * @return      Contact ids needing the hop in pass 2.
   */
  @TestVisible
  private Set<Id> resolveDirectAccountAnchors(List<SObject> chunk) {
    Set<Id> contactIdsToResolve = new Set<Id>();
    for (SObject record : chunk) {
      Engagement_Touch__c touch = (Engagement_Touch__c) record;
      if (touch.Account__c != null) {
        accountIdByTouchId.put(touch.Id, touch.Account__c);
      } else if (touch.Contact__c != null) {
        contactIdsToResolve.add(touch.Contact__c);
      }
    }
    return contactIdsToResolve;
  }

  /**
   * @description Pass 2 — one bulk SOQL on Contact to resolve the
   *              Contact → AccountId hop for touches that had no direct
   *              Account anchor, then back-fills `accountIdByTouchId`.
   *
   * @param chunk                The candidate touches.
   * @param contactIdsToResolve  Contact ids identified by pass 1.
   */
  @TestVisible
  private void resolveAccountAnchorsViaContact(
    List<SObject> chunk,
    Set<Id> contactIdsToResolve
  ) {
    if (contactIdsToResolve.isEmpty()) {
      return;
    }
    Map<Id, Id> accountIdByContactId = new Map<Id, Id>();
    for (Contact c : [
      SELECT Id, AccountId
      FROM Contact
      WHERE Id IN :contactIdsToResolve
      WITH USER_MODE
    ]) {
      accountIdByContactId.put(c.Id, c.AccountId);
    }
    for (SObject record : chunk) {
      Engagement_Touch__c touch = (Engagement_Touch__c) record;
      if (touch.Account__c != null || touch.Contact__c == null) {
        continue;
      }
      Id resolved = accountIdByContactId.get(touch.Contact__c);
      if (resolved != null) {
        accountIdByTouchId.put(touch.Id, resolved);
      }
    }
  }

  /**
   * @description Pass 3 — one bulk SOQL on Opportunity to identify which of
   *              the resolved accounts has at least one open deal. Populates
   *              `accountsWithOpenOpp`.
   */
  @TestVisible
  private void cacheAccountsWithOpenOpp() {
    Set<Id> accountIdsToCheck = new Set<Id>(accountIdByTouchId.values());
    accountIdsToCheck.remove(null);
    if (accountIdsToCheck.isEmpty()) {
      return;
    }
    for (Opportunity opp : [
      SELECT AccountId
      FROM Opportunity
      WHERE AccountId IN :accountIdsToCheck AND IsClosed = FALSE
      WITH USER_MODE
    ]) {
      accountsWithOpenOpp.add(opp.AccountId);
    }
  }

  /**
   * @description Decides whether to keep this engagement touch. Pure
   *              in-memory lookup against the chunk caches built by
   *              `primeBulkCache`.
   *
   * @param record Expected to be an `Engagement_Touch__c`.
   * @return       `true` to keep, `false` to allow deletion.
   */
  public Boolean shouldKeep(SObject record) {
    if (record == null) {
      return true; // Conservative — never delete on null.
    }

    Engagement_Touch__c touch = (Engagement_Touch__c) record;
    Id accountId = accountIdByTouchId.get(touch.Id);
    if (accountId == null) {
      return true; // No account anchor resolved — keep.
    }

    return accountsWithOpenOpp.contains(accountId);
  }
}
