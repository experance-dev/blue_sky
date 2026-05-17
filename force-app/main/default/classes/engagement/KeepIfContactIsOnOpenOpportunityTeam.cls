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
 *              **Bulk-aware.** Implements `IBulkPrimablePredicate` — the
 *              framework calls `primeBulkCache(chunk)` once per
 *              `RecordCleanupBatch` execute chunk before the per-record
 *              `shouldKeep` loop. Priming collects every Contact id in the
 *              chunk and asks `OpportunityContactRole` once, in bulk, which
 *              of those contacts is on any open deal. Per-record `shouldKeep`
 *              is then a pure `Set.contains` — zero SOQL inside the loop.
 *
 * @group Engagement
 * @author David Wood
 * @since May 2026
 * @last 2026-05-16 — PR #6: SOQL-in-loop eliminated. Lifecycle hook (`primeBulkCache`) builds a chunk-scoped Set of contacts with open-deal OCR presence; `shouldKeep` is now pure in-memory lookup. One SOQL per chunk instead of one SOQL per record.
 */
public with sharing class KeepIfContactIsOnOpenOpportunityTeam implements IRecordRetentionPredicate, IBulkPrimablePredicate {
  // Chunk-scoped cache — rebuilt by primeBulkCache on every chunk.
  // Contact ids that appear on at least one open Opportunity's OCR.
  @TestVisible
  private Set<Id> contactsOnOpenDealTeam = new Set<Id>();

  /**
   * @description Declares the projection fields the framework must include
   *              on every loaded `Engagement_Touch__c` so `primeBulkCache`
   *              can collect contact ids without a per-record re-query.
   *
   * @return Field API names: `Contact__c`.
   */
  public List<String> requiredFields() {
    return new List<String>{ 'Contact__c' };
  }

  /**
   * @description Bulk-prefetches the OCR presence Set for every Contact in
   *              this chunk. One SOQL covers the whole chunk.
   *
   * @param chunk The candidate `Engagement_Touch__c` records about to be
   *              evaluated by `shouldKeep`.
   */
  public void primeBulkCache(List<SObject> chunk) {
    // Reset previous chunk's state. Predicate instances are reused across
    // chunks within a batch run.
    contactsOnOpenDealTeam = new Set<Id>();

    if (chunk == null || chunk.isEmpty()) {
      return;
    }

    Set<Id> contactIds = new Set<Id>();
    for (SObject record : chunk) {
      Engagement_Touch__c touch = (Engagement_Touch__c) record;
      if (touch.Contact__c != null) {
        contactIds.add(touch.Contact__c);
      }
    }
    if (contactIds.isEmpty()) {
      return;
    }

    for (OpportunityContactRole ocr : [
      SELECT ContactId
      FROM OpportunityContactRole
      WHERE ContactId IN :contactIds AND Opportunity.IsClosed = FALSE
      WITH USER_MODE
    ]) {
      contactsOnOpenDealTeam.add(ocr.ContactId);
    }
  }

  /**
   * @description Decides whether to keep this engagement touch. Pure
   *              in-memory lookup against the chunk cache built by
   *              `primeBulkCache`.
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
    return contactsOnOpenDealTeam.contains(touch.Contact__c);
  }
}
