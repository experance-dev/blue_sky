/**
 * @description Test-only predicate that always returns `false` (delete every
 *              candidate). Used to verify the predicate hook fires and the
 *              candidate set reaches the DML step.
 *
 * @group Cleanup
 * @author David Wood
 * @since May 2026
 */
@IsTest
public without sharing class TestDeleteEverythingPredicate implements IRecordRetentionPredicate {
  /** @param record Ignored. @return Always `false`. */
  public Boolean shouldKeep(SObject record) {
    return false;
  }
}
