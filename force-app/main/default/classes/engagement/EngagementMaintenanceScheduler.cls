/**
 * @description Weekly scheduled maintenance entry point. Fires both engagement
 *              maintenance batches: the signal-decay recompute and the touch
 *              archival sweep. The two are submitted independently rather than
 *              chained — neither holds external resources, and decoupling them
 *              keeps the scheduler trivially debuggable.
 *
 *              Recommended cron: `0 0 2 ? * MON` (Mondays at 02:00 server time).
 *              Submit via:
 *                System.schedule(
 *                  'Engagement Weekly Maintenance',
 *                  '0 0 2 ? * MON',
 *                  new EngagementMaintenanceScheduler()
 *                );
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class EngagementMaintenanceScheduler implements Schedulable {
  private static final Integer BATCH_SIZE = 200;

  /**
   * @description Queues both maintenance batches for asynchronous execution.
   * @param sc The schedulable context reference.
   */
  public void execute(SchedulableContext sc) {
    Database.executeBatch(new EngagementSignalDecayBatch(), BATCH_SIZE);
    Database.executeBatch(new EngagementTouchArchivalBatch(), BATCH_SIZE);
  }
}
