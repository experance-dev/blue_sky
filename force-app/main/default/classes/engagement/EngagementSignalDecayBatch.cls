/**
 * @description Recomputes `Opportunity_Engagement_Signal__c.Confidence__c`
 *              as a linear function of the parent touch's age. Older touches
 *              get lower confidence; a touch older than
 *              `Engagement_Settings__c.Signal_Decay_Days__c` (default 90)
 *              floors at zero.
 *
 *              The decay is **absolute** (a function of age, not a stepwise
 *              decrement) so the job is idempotent — re-running it on the
 *              same scope is a no-op once each signal has converged on its
 *              age-derived confidence.
 *
 *              Dismissed signals and signals already at zero are filtered out
 *              of `start()` so we never touch records that can't change.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class EngagementSignalDecayBatch implements Database.Batchable<SObject>, Database.Stateful {
  private static final String CLASS_NAME = 'EngagementSignalDecayBatch';
  private static final Integer DEFAULT_DECAY_DAYS = 90;
  private static final Decimal MIN_DELTA_TO_UPDATE = 1;

  @TestVisible
  private static Engagement_Settings__c settingsOverride;

  private Integer processedCount = 0;
  private Integer flooredCount = 0;

  /**
   * @description Returns every non-dismissed signal whose confidence still has
   *              room to fall (Confidence__c > 0). Signals at the zero floor
   *              are filtered out so re-runs of an aged dataset do no work.
   * @param bc The batchable context reference.
   * @return Query locator over the candidate signals.
   */
  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT Id, Confidence__c, Engagement_Touch__c, Dismissed__c
        FROM Opportunity_Engagement_Signal__c
        WHERE Dismissed__c = FALSE AND Confidence__c > 0
        WITH USER_MODE
      ]
    );
  }

  /**
   * @description Recomputes confidence for each signal in the chunk based on
   *              the age of its parent `Engagement_Touch__c.Occurred_At__c`.
   *              Updates only those whose new confidence differs from the
   *              stored value by at least one unit.
   * @param bc    The batchable context reference.
   * @param scope The signals to evaluate in this chunk.
   */
  public void execute(
    Database.BatchableContext bc,
    List<Opportunity_Engagement_Signal__c> scope
  ) {
    if (scope == null || scope.isEmpty()) {
      return;
    }

    Map<Id, DateTime> occurredAtByTouchId = loadTouchOccurredAt(scope);
    Integer decayDays = resolveDecayDays();
    List<Opportunity_Engagement_Signal__c> toUpdate = new List<Opportunity_Engagement_Signal__c>();

    for (Opportunity_Engagement_Signal__c sig : scope) {
      DateTime occurredAt = occurredAtByTouchId.get(sig.Engagement_Touch__c);
      if (occurredAt == null) {
        continue;
      }
      Decimal computed = computeConfidence(occurredAt, decayDays);
      Decimal current = sig.Confidence__c == null ? 0 : sig.Confidence__c;
      if (Math.abs(computed - current) < MIN_DELTA_TO_UPDATE) {
        continue;
      }
      sig.Confidence__c = computed;
      toUpdate.add(sig);
      processedCount++;
      if (computed == 0) {
        flooredCount++;
      }
    }

    if (toUpdate.isEmpty()) {
      return;
    }
    persist(toUpdate);
  }

  /**
   * @description Logs aggregate counts. Counts persist across chunks because
   *              this class implements `Database.Stateful`.
   * @param bc The batchable context reference.
   */
  public void finish(Database.BatchableContext bc) {
    Logger.info(
      'SignalDecay processed ' +
        processedCount +
        ' records, ' +
        flooredCount +
        ' decayed to floor.',
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

  private static Integer resolveDecayDays() {
    Engagement_Settings__c settings = loadSettings();
    if (settings == null || settings.Signal_Decay_Days__c == null) {
      return DEFAULT_DECAY_DAYS;
    }
    Integer days = settings.Signal_Decay_Days__c.intValue();
    return days <= 0 ? DEFAULT_DECAY_DAYS : days;
  }

  private static Map<Id, DateTime> loadTouchOccurredAt(
    List<Opportunity_Engagement_Signal__c> scope
  ) {
    Set<Id> touchIds = new Set<Id>();
    for (Opportunity_Engagement_Signal__c sig : scope) {
      if (sig.Engagement_Touch__c != null) {
        touchIds.add(sig.Engagement_Touch__c);
      }
    }
    Map<Id, DateTime> result = new Map<Id, DateTime>();
    if (touchIds.isEmpty()) {
      return result;
    }
    for (Engagement_Touch__c t : [
      SELECT Id, Occurred_At__c
      FROM Engagement_Touch__c
      WHERE Id IN :touchIds
      WITH USER_MODE
    ]) {
      result.put(t.Id, t.Occurred_At__c);
    }
    return result;
  }

  /**
   * @description Linear decay: 100 at age 0, floors at 0 when age >= decayDays.
   *              Rounded to whole numbers because `Confidence__c` has scale 0.
   * @param occurredAt Touch occurrence timestamp (parent of the signal).
   * @param decayDays Whole-day decay window — confidence floors at 0 once age
   *                  reaches this value.
   * @return Computed confidence in the [0, 100] integer range.
   */
  @TestVisible
  private static Decimal computeConfidence(
    DateTime occurredAt,
    Integer decayDays
  ) {
    Integer ageDays = occurredAt.date().daysBetween(Date.today());
    if (ageDays <= 0) {
      return 100;
    }
    if (ageDays >= decayDays) {
      return 0;
    }
    Decimal raw = 100 - ((Decimal) ageDays * 100 / decayDays);
    return Math.max(0, raw.setScale(0, System.RoundingMode.HALF_UP));
  }

  private static void persist(List<Opportunity_Engagement_Signal__c> toUpdate) {
    try {
      DMLManager.updateAsUser(toUpdate);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'execute');
      throw new EngagementException(
        'Signal decay update failed. Contact your Administrator and let them know: ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }
  }
}
