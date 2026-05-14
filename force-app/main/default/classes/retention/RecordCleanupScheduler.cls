/**
 * @description Schedulable entry point that fires `RecordCleanupBatch` on its
 *              configured cron schedule. No business logic — delegates
 *              entirely to the batch. `global` so subscriber orgs (in a
 *              managed-package distribution) can schedule it via Setup or
 *              `System.schedule()`.
 *
 *              Schedule example (recommended: nightly off-hours):
 *
 *              ```apex
 *              String cron = '0 0 2 * * ?'; // 2am every night
 *              System.schedule('RecordCleanup nightly', cron, new RecordCleanupScheduler());
 *              ```
 *
 * @group Cleanup
 * @author David Wood
 * @since May 2026
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
global without sharing class RecordCleanupScheduler implements Schedulable {
  /**
   * @description Launches `RecordCleanupBatch` with the default production
   *              context. Batch size of 200 — standard SObject chunk.
   *
   * @param sc The schedulable context reference.
   */
  global void execute(SchedulableContext sc) {
    Database.executeBatch(new RecordCleanupBatch(), 200);
  }
}
