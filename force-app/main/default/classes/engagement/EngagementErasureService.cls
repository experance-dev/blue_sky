/**
 * @description Subject-erasure cascade for the Engagement Attribution module.
 *              When a Contact or Lead is the subject of a CCPA "Delete My
 *              Data" / GDPR right-to-be-forgotten request, this service hard-
 *              deletes every dependent record across the three engagement
 *              objects so no residual PII or behavioural data remains.
 *
 *              Cascade order (Contact subject):
 *                1. Resolve `Engagement_Touch__c` ids where `Contact__c IN`.
 *                2. Hard-delete `Opportunity_Engagement_Signal__c` rows that
 *                   reference the subject directly (`Contact__c IN`) OR point
 *                   at one of the doomed touches (`Engagement_Touch__c IN`).
 *                3. Hard-delete `Engagement_Dismissal__c` rows where
 *                   `Contact__c IN`.
 *                4. Hard-delete the `Engagement_Touch__c` rows themselves.
 *                5. `Database.emptyRecycleBin` on each batch so the data is
 *                   irrecoverable — compliance requires hard-delete, not soft.
 *
 *              Lead variant follows the same shape, scoped to touches whose
 *              `Lead__c` lookup names the subject (unconverted Leads still
 *              accrue touches; converted Leads have already been reparented
 *              by `LeadEngagementReparentHandler` so the cascade short-
 *              circuits there).
 *
 *              All SOQL uses `WITH USER_MODE`; all DML routes through
 *              `DMLManager.deleteAsUser` per best-practices/apex.md.
 *              Failures are wrapped in `EngagementException` so the trigger
 *              layer can surface a compliance-gap warning to the caller.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class EngagementErasureService {
  private static final String CLASS_NAME = 'EngagementErasureService';

  // ─── Result type ──────────────────────────────────────────────────────────

  /**
   * @description Audit record for a single cascade invocation. Returned to
   *              callers so they can persist or log compliance evidence.
   */
  public class ErasureSummary {
    public Integer dismissalsDeleted;
    public Integer signalsDeleted;
    public Integer touchesDeleted;
    public List<String> messages;

    public ErasureSummary() {
      this.dismissalsDeleted = 0;
      this.signalsDeleted = 0;
      this.touchesDeleted = 0;
      this.messages = new List<String>();
    }
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  /**
   * @description Erase all Engagement Attribution data associated with the
   *              supplied Contacts (CCPA / GDPR subject erasure). Hard-deletes
   *              dismissals, signals, and touches; empties the recycle bin
   *              so the data is irrecoverable.
   * @param contactIds The Contact ids whose engagement data should be erased.
   * @return ErasureSummary counts of each deleted child collection.
   */
  public static ErasureSummary eraseForContacts(Set<Id> contactIds) {
    ErasureSummary summary = new ErasureSummary();
    if (contactIds == null || contactIds.isEmpty()) {
      return summary;
    }
    try {
      Set<Id> touchIds = collectTouchIdsForContacts(contactIds);
      deleteSignalsForContacts(contactIds, touchIds, summary);
      deleteDismissalsForContacts(contactIds, summary);
      deleteTouches(touchIds, summary);
      logSummary(summary, 'Contact', contactIds.size());
      return summary;
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'eraseForContacts');
      throw new EngagementException(
        'Subject-erasure cascade failed for Contacts: ' +
          e.getMessage() +
          ' - ' +
          e.getStackTraceString()
      );
    }
  }

  /**
   * @description Erase all Engagement Attribution data associated with the
   *              supplied Leads. Targets touches whose `Lead__c` lookup names
   *              the subject — converted Leads will normally have zero such
   *              rows because `LeadEngagementReparentHandler` reparents on
   *              conversion. Hard-delete + recycle-bin empty, same as the
   *              Contact variant.
   * @param leadIds The Lead ids whose engagement data should be erased.
   * @return ErasureSummary counts of each deleted child collection.
   */
  public static ErasureSummary eraseForLeads(Set<Id> leadIds) {
    ErasureSummary summary = new ErasureSummary();
    if (leadIds == null || leadIds.isEmpty()) {
      return summary;
    }
    try {
      Set<Id> touchIds = collectTouchIdsForLeads(leadIds);
      deleteSignalsForTouches(touchIds, summary);
      deleteTouches(touchIds, summary);
      logSummary(summary, 'Lead', leadIds.size());
      return summary;
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'eraseForLeads');
      throw new EngagementException(
        'Subject-erasure cascade failed for Leads: ' +
          e.getMessage() +
          ' - ' +
          e.getStackTraceString()
      );
    }
  }

  // ─── Private — Contact cascade helpers ────────────────────────────────────

  private static Set<Id> collectTouchIdsForContacts(Set<Id> contactIds) {
    List<Engagement_Touch__c> touches = [
      SELECT Id
      FROM Engagement_Touch__c
      WHERE Contact__c IN :contactIds
      WITH USER_MODE
    ];
    return new Map<Id, SObject>(touches).keySet();
  }

  private static void deleteSignalsForContacts(
    Set<Id> contactIds,
    Set<Id> touchIds,
    ErasureSummary summary
  ) {
    List<Opportunity_Engagement_Signal__c> signals = [
      SELECT Id
      FROM Opportunity_Engagement_Signal__c
      WHERE Contact__c IN :contactIds OR Engagement_Touch__c IN :touchIds
      WITH USER_MODE
    ];
    if (signals.isEmpty()) {
      return;
    }
    DMLManager.deleteAsUser(signals);
    Database.emptyRecycleBin(signals);
    summary.signalsDeleted += signals.size();
  }

  private static void deleteDismissalsForContacts(
    Set<Id> contactIds,
    ErasureSummary summary
  ) {
    List<Engagement_Dismissal__c> dismissals = [
      SELECT Id
      FROM Engagement_Dismissal__c
      WHERE Contact__c IN :contactIds
      WITH USER_MODE
    ];
    if (dismissals.isEmpty()) {
      return;
    }
    DMLManager.deleteAsUser(dismissals);
    Database.emptyRecycleBin(dismissals);
    summary.dismissalsDeleted += dismissals.size();
  }

  // ─── Private — Lead cascade helpers ───────────────────────────────────────

  private static Set<Id> collectTouchIdsForLeads(Set<Id> leadIds) {
    List<Engagement_Touch__c> touches = [
      SELECT Id
      FROM Engagement_Touch__c
      WHERE Lead__c IN :leadIds
      WITH USER_MODE
    ];
    return new Map<Id, SObject>(touches).keySet();
  }

  private static void deleteSignalsForTouches(
    Set<Id> touchIds,
    ErasureSummary summary
  ) {
    if (touchIds.isEmpty()) {
      return;
    }
    List<Opportunity_Engagement_Signal__c> signals = [
      SELECT Id
      FROM Opportunity_Engagement_Signal__c
      WHERE Engagement_Touch__c IN :touchIds
      WITH USER_MODE
    ];
    if (signals.isEmpty()) {
      return;
    }
    DMLManager.deleteAsUser(signals);
    Database.emptyRecycleBin(signals);
    summary.signalsDeleted += signals.size();
  }

  // ─── Private — shared ─────────────────────────────────────────────────────

  private static void deleteTouches(Set<Id> touchIds, ErasureSummary summary) {
    if (touchIds.isEmpty()) {
      return;
    }
    List<Engagement_Touch__c> touches = new List<Engagement_Touch__c>();
    for (Id touchId : touchIds) {
      touches.add(new Engagement_Touch__c(Id = touchId));
    }
    DMLManager.deleteAsUser(touches);
    Database.emptyRecycleBin(touches);
    summary.touchesDeleted += touches.size();
  }

  private static void logSummary(
    ErasureSummary summary,
    String subjectType,
    Integer subjectCount
  ) {
    String msg = String.format(
      'Subject erasure cascade — {0} subject(s) of type {1}: deleted {2} touch(es), {3} signal(s), {4} dismissal(s).',
      new List<Object>{
        subjectCount,
        subjectType,
        summary.touchesDeleted,
        summary.signalsDeleted,
        summary.dismissalsDeleted
      }
    );
    summary.messages.add(msg);
    Logger.info(msg, CLASS_NAME, 'logSummary');
  }
}
