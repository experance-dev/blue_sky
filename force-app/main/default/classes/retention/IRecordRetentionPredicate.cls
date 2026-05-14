/**
 * @description Hook for adding business rules to a retention rule defined in
 *              `Record_Retention_Rule__mdt`. Implementations decide whether a
 *              single record should be kept (returned `true`) or allowed to be
 *              deleted/archived (returned `false`). The framework calls
 *              `shouldKeep(record)` once per candidate record after the SOQL
 *              age and field filters have already passed.
 *
 *              **Positive framing on purpose.** `shouldKeep` reads naturally
 *              from a CMDT row name — `KeepIfAccountHasOpenOpportunity` —
 *              and avoids the double-negative trap of "reject" predicates.
 *
 *              Implementations must be:
 *              - **Bulk-aware.** The framework only calls `shouldKeep` per
 *                record, but the predicate is free to lazy-load and cache any
 *                related data on first call so repeated calls within one batch
 *                chunk are cheap.
 *              - **Side-effect free.** No DML. No state that leaks across
 *                batch chunks.
 *              - **Defensive.** Return `true` (= keep, do nothing) on any
 *                ambiguity rather than mistakenly delete a record.
 *
 * @group Cleanup
 * @author David Wood
 * @since May 2026
 */
public interface IRecordRetentionPredicate {
  /**
   * @description Decide whether a candidate record should be kept.
   *
   * @param record The candidate record loaded by `RecordCleanupBatch`. Includes
   *               every field the SOQL projection requested — at minimum the
   *               Id and the configured age field.
   * @return       `true` to keep the record (skip delete/archive); `false` to
   *               allow the framework to delete/archive it.
   */
  Boolean shouldKeep(SObject record);
}
