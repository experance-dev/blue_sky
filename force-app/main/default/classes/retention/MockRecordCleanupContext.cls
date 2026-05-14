/**
 * @description Test double for `RecordCleanupContext`. Returns whatever rules
 *              the caller supplies so batch tests never touch CMDT (which is
 *              org-state, not test-fixture material).
 *
 * @group Cleanup
 * @see RecordCleanupContext
 * @author David Wood
 * @since May 2026
 */
@IsTest
public without sharing class MockRecordCleanupContext extends RecordCleanupContext {
  private List<RecordCleanupRule> rules;

  /**
   * @description Constructs the mock with a fixed rule list.
   *
   * @param rules The retention rules this context should return.
   */
  public MockRecordCleanupContext(List<RecordCleanupRule> rules) {
    this.rules = rules;
  }

  /** @return The rules supplied at construction time. */
  public override List<RecordCleanupRule> getActiveRules() {
    return rules;
  }
}
