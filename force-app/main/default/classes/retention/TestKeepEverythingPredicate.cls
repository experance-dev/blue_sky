/**
 * @description Test-only predicate that always returns `true` (keep every
 *              record). Used to verify `RecordCleanupBatch` honors the
 *              predicate when it says "keep this" — nothing should be deleted
 *              when this predicate is wired up.
 *
 * @group Cleanup
 * @author David Wood
 * @since May 2026
 */
@IsTest
public without sharing class TestKeepEverythingPredicate implements IRecordRetentionPredicate {
  /** @param record Ignored. @return Always `true`. */
  public Boolean shouldKeep(SObject record) {
    return true;
  }
}
