/**
 * @description Optional lifecycle hook for `IRecordRetentionPredicate` impls
 *              that need to pre-fetch related data once per `RecordCleanupBatch`
 *              `execute` chunk. Predicates that issue per-record SOQL — e.g.
 *              "keep this touch if the contact's account has an open
 *              opportunity" — would otherwise blow the 100-SOQL governor at a
 *              200-record chunk size and only need to issue **one** SOQL per
 *              chunk if they cache the resolved set in advance.
 *
 *              **Contract.** `RecordCleanupBatch.applyPredicate` checks each
 *              candidate predicate for `instanceof IBulkPrimablePredicate` and,
 *              when matched, calls `primeBulkCache(chunk)` exactly once before
 *              the per-record `shouldKeep` loop. Implementations should:
 *
 *              - **Bulk-fetch and cache.** Build a Set<Id> (or analogous
 *                lookup) from one bulk SOQL covering every relevant id in the
 *                chunk; store it as instance state.
 *              - **Be re-priming safe.** The same predicate instance is reused
 *                across chunks within one batch run, so the impl should clear
 *                or overwrite previous chunk state on each call.
 *              - **Stay side-effect free.** No DML. No leaking state across
 *                batch runs (each run instantiates a fresh predicate).
 *
 *              **Why a sub-interface, not a method on `IRecordRetentionPredicate`.**
 *              Apex interfaces have no default-method support, so widening the
 *              base interface would force every implementer (including the two
 *              test-only `TestKeepEverythingPredicate` /
 *              `TestDeleteEverythingPredicate` no-ops) to declare an empty
 *              method. Modelling the hook as an opt-in sub-interface keeps the
 *              base contract minimal, makes the bulk-caching intent visible
 *              from the class declaration, and gives the framework a clean
 *              `instanceof` dispatch.
 *
 * @group Cleanup
 * @author David Wood
 * @since May 2026
 */
public interface IBulkPrimablePredicate {
  /**
   * @description Declare any additional fields the framework must include in
   *              the candidate SOQL projection so this predicate can
   *              bulk-resolve from records loaded by `RecordCleanupBatch`.
   *              Called by the framework before SOQL composition.
   *
   *              Example: `KeepIfAccountHasOpenOpportunity` needs `Account__c`
   *              and `Contact__c` on every loaded `Engagement_Touch__c` so the
   *              priming pass can resolve the account anchor without a
   *              per-record re-query. Returning `null` or an empty list means
   *              the predicate is happy with the framework's default
   *              projection (Id + age field).
   *
   * @return Field API names to add to the candidate SOQL projection, or null
   *         / empty for none.
   */
  List<String> requiredFields();

  /**
   * @description Pre-fetch any related data needed to satisfy `shouldKeep` for
   *              every record in this chunk in one bulk SOQL. Called by
   *              `RecordCleanupBatch.applyPredicate` once per chunk, before the
   *              per-record evaluation loop. Implementations must reset any
   *              previous chunk's cached state — predicate instances are
   *              reused across chunks within a single batch run.
   *
   * @param chunk The candidate records about to be passed through
   *              `shouldKeep`. Always non-null and non-empty when this hook is
   *              invoked.
   */
  void primeBulkCache(List<SObject> chunk);
}
