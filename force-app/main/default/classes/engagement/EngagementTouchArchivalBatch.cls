/**
 * @description Archives `Engagement_Touch__c` records whose `Occurred_At__c`
 *              is older than `Engagement_Settings__c.Active_Window_Days__c`
 *              (default 180). Sets `Is_Active__c = false` and stamps
 *              `Archived_At__c`.
 *
 *              Idempotent: `start()` filters out records that have already
 *              been archived (`Is_Active__c = true`), so re-runs over an
 *              aged dataset do no work after the first pass.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class EngagementTouchArchivalBatch implements Database.Batchable<SObject>, Database.Stateful {
  private static final String CLASS_NAME = 'EngagementTouchArchivalBatch';
  private static final Integer DEFAULT_WINDOW_DAYS = 180;

  @TestVisible
  private static Engagement_Settings__c settingsOverride;

  private Integer archivedCount = 0;

  /**
   * @description Returns active touches older than the configured archival
   *              window. The cutoff is computed once at the start of the job;
   *              all chunks share the same boundary.
   * @param bc The batchable context reference.
   * @return Query locator over the candidate touches.
   */
  public Database.QueryLocator start(Database.BatchableContext bc) {
    DateTime cutoff = DateTime.now().addDays(-resolveWindowDays());
    return Database.getQueryLocator(
      [
        SELECT Id, Is_Active__c, Archived_At__c, Occurred_At__c
        FROM Engagement_Touch__c
        WHERE Is_Active__c = TRUE AND Occurred_At__c < :cutoff
        WITH USER_MODE
      ]
    );
  }

  /**
   * @description Flips `Is_Active__c` to false and stamps `Archived_At__c`
   *              on every touch in the chunk, then persists in one DML.
   * @param bc    The batchable context reference.
   * @param scope The touches to archive in this chunk.
   */
  public void execute(
    Database.BatchableContext bc,
    List<Engagement_Touch__c> scope
  ) {
    if (scope == null || scope.isEmpty()) {
      return;
    }
    DateTime archivedAt = DateTime.now();
    for (Engagement_Touch__c t : scope) {
      t.Is_Active__c = false;
      t.Archived_At__c = archivedAt;
    }
    persist(scope);
    archivedCount += scope.size();
  }

  /**
   * @description Logs the aggregate archived count. Counts persist across
   *              chunks via `Database.Stateful`.
   * @param bc The batchable context reference.
   */
  public void finish(Database.BatchableContext bc) {
    Logger.info(
      'Touch archival complete. Archived ' + archivedCount + ' records.',
      CLASS_NAME,
      'finish'
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  private static Engagement_Settings__c loadSettings() {
    if (settingsOverride != null) {
      return settingsOverride;
    }
    return Engagement_Settings__c.getOrgDefaults();
  }

  private static Integer resolveWindowDays() {
    Engagement_Settings__c settings = loadSettings();
    if (settings == null || settings.Active_Window_Days__c == null) {
      return DEFAULT_WINDOW_DAYS;
    }
    Integer days = settings.Active_Window_Days__c.intValue();
    return days <= 0 ? DEFAULT_WINDOW_DAYS : days;
  }

  private static void persist(List<Engagement_Touch__c> scope) {
    try {
      DMLManager.updateAsUser(scope);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'execute');
      throw new EngagementException(
        'Touch archival update failed. Contact your Administrator and let them know: ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }
  }
}
