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
 * @last 2026-05-16 — PR #6 sweep: §2.4 isAccessible() guards on Contact-path cascade (collectTouchIdsForContacts, deleteSignalsForContacts, deleteDismissalsForContacts) mirroring the Lead-path canonical; §3.0 stack-trace removed from rethrow messages, txn correlator added; before-delete trigger-context gate enforces the GDPR cascade boundary.
 */
public with sharing class EngagementErasureService {
  private static final String CLASS_NAME = 'EngagementErasureService';

  /**
   * @description Trigger-context gate flag, test-side opt-in. The cascade
   *              public API (`eraseForContacts` / `eraseForLeads`) is only
   *              legitimate when invoked from a before-delete trigger
   *              handler — any other caller (a future LWC admin tool, an
   *              inbound REST endpoint, a batch) would be invoking
   *              compliance erasure outside the GDPR cascade boundary and
   *              the residual cleanup audit-trail would be missed.
   *              Defense-in-depth: `with sharing` and DMLManager still
   *              enforce CRUD/FLS, but this guard makes the abuse path
   *              loudly fail rather than silently delete.
   *
   *              **Test-context behaviour.** `Test.isRunningTest()` opts
   *              out by default — service-level unit tests should not need
   *              to fake a trigger context to exercise the cascade.
   *              Tests that explicitly want to assert the gate behaviour
   *              set `enforceTriggerGateInTest = true` and verify the
   *              `EngagementException` is thrown when invoked outside a
   *              before-delete trigger context.
   */
  @TestVisible
  private static Boolean enforceTriggerGateInTest = false;

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

    /**
     * @description No-arg constructor — initialises counters to zero and
     *              the messages list to empty so callers can increment +
     *              append without null-check noise.
     */
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
    enforceTriggerGate('eraseForContacts');
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
        'Subject-erasure cascade failed for Contacts. Contact your Administrator and let them know: ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
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
    enforceTriggerGate('eraseForLeads');
    try {
      Set<Id> touchIds = collectTouchIdsForLeads(leadIds);
      deleteSignalsForTouches(touchIds, summary);
      deleteTouches(touchIds, summary);
      logSummary(summary, 'Lead', leadIds.size());
      return summary;
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'eraseForLeads');
      throw new EngagementException(
        'Subject-erasure cascade failed for Leads. Contact your Administrator and let them know: ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }
  }

  // ─── Private — caller gate ────────────────────────────────────────────────

  /**
   * @description Asserts the caller is executing inside a delete-trigger
   *              context. Throws `EngagementException` (logged) when invoked
   *              from a non-trigger context — protects the compliance API
   *              from incidental misuse by future LWC tools, REST endpoints,
   *              or batches that would skip the cascade audit-trail.
   *              In test context the gate is opt-in via
   *              `enforceTriggerGateInTest` so existing service-level unit
   *              tests don't need to fake a trigger to exercise the
   *              cascade.
   * @param methodName Service method name surfaced in the Logger entry and
   *                   in the rejected-call audit trail.
   */
  private static void enforceTriggerGate(String methodName) {
    if (Test.isRunningTest() && !enforceTriggerGateInTest) {
      return;
    }
    if (!Trigger.isExecuting || !Trigger.isBefore || !Trigger.isDelete) {
      Logger.error(
        UserInfo.getUserName() +
          ' invoked ' +
          methodName +
          ' outside a before-delete trigger context — rejected.',
        CLASS_NAME,
        methodName
      );
      throw new EngagementException(
        'Subject-erasure cascade may only be invoked from a before-delete trigger handler. Contact your Administrator. [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }
  }

  // ─── Private — Contact cascade helpers ────────────────────────────────────

  private static Set<Id> collectTouchIdsForContacts(Set<Id> contactIds) {
    // Mirrors the Lead-path guard at collectTouchIdsForLeads. A Contact can be
    // deleted by any user in the org — including users with no MI permset and
    // therefore no FLS on Engagement_Touch__c.Contact__c. Under WITH USER_MODE
    // such a user's SOQL raises QueryException ("No such column") because
    // USER_MODE hides FLS-blocked fields from the schema. No-op when the
    // deleting user can't see the field — the cascade must never block Contact
    // delete for non-MI personas.
    if (
      !Schema.sObjectType.Engagement_Touch__c.fields.Contact__c.isAccessible()
    ) {
      return new Set<Id>();
    }

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
    // Signal-side mirror of the Touch-side guard above. If the deleting user
    // can't see Opportunity_Engagement_Signal__c.Contact__c, the SOQL's first
    // disjunct would raise QueryException under WITH USER_MODE. No-op silently
    // — non-MI personas have no cascade work in their user-mode view.
    if (
      !Schema.sObjectType.Opportunity_Engagement_Signal__c.fields.Contact__c.isAccessible()
    ) {
      return;
    }

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
    // Dismissal-side mirror of the Touch-side guard above. If the deleting
    // user can't see Engagement_Dismissal__c.Contact__c under WITH USER_MODE,
    // no-op — the cascade must never block Contact delete for non-MI personas.
    if (
      !Schema.sObjectType.Engagement_Dismissal__c.fields.Contact__c.isAccessible()
    ) {
      return;
    }

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
    // Marketing Influence is an OWD-Private, permset-gated feature. A Lead can
    // be deleted by any user in the org — including users with no MI permset
    // and therefore no FLS on Engagement_Touch__c.Lead__c. Under WITH USER_MODE
    // such a user's SOQL on Lead__c raises QueryException ("No such column")
    // because USER_MODE hides FLS-blocked fields from the schema. Gate on
    // Lead__c accessibility and no-op silently when the deleting user can't
    // see the field — there is nothing for that user to cascade in their
    // user-mode view, and the cascade must never block Lead delete for
    // non-MI personas. Mirrors LeadEngagementReparentHandler.reparentTouches.
    if (!Schema.sObjectType.Engagement_Touch__c.fields.Lead__c.isAccessible()) {
      return new Set<Id>();
    }

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
