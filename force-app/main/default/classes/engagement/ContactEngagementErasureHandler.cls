/**
 * @description Before-delete handler on Contact. When a Contact is being
 *              deleted (typically as part of a CCPA / GDPR subject-erasure
 *              request), cascade-delete all Engagement Attribution records
 *              that reference that Contact.
 *
 *              Runs in BEFORE delete so children are cleaned up before the
 *              platform clears foreign-key references on cascade. Catching
 *              the delete event also handles operator-initiated Contact
 *              deletes — not just compliance workflows — keeping the
 *              engagement model internally consistent.
 *
 *              Errors during the cascade are logged via Logger and then
 *              re-thrown as `EngagementException` so the deletion DML fails
 *              loudly. A silent partial-cascade would be a compliance gap
 *              (residual PII / behavioural data tied to an "erased" subject).
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class ContactEngagementErasureHandler extends TriggerHandler {
  private static final String CLASS_NAME = 'ContactEngagementErasureHandler';

  /**
   * @description Framework entry point. Branches on trigger context and
   *              delegates to the relevant hook helper.
   */
  public void initialise() {
    if (Trigger.isBefore && Trigger.isDelete) {
      handleBeforeDelete();
    }
  }

  /**
   * @description Before-delete hook. Collects the doomed Contact ids and
   *              delegates the cascade to `EngagementErasureService`.
   */
  private void handleBeforeDelete() {
    if (Trigger.old == null) {
      return;
    }
    Set<Id> contactIds = new Map<Id, SObject>((List<Contact>) Trigger.old)
      .keySet();
    if (contactIds.isEmpty()) {
      return;
    }
    try {
      EngagementErasureService.ErasureSummary s = EngagementErasureService.eraseForContacts(
        contactIds
      );
      Logger.info(
        String.format(
          'Subject-erasure cascade for {0} Contact(s): deleted {1} touch(es), {2} signal(s), {3} dismissal(s).',
          new List<Object>{
            contactIds.size(),
            s.touchesDeleted,
            s.signalsDeleted,
            s.dismissalsDeleted
          }
        ),
        CLASS_NAME,
        'beforeDelete'
      );
    } catch (Exception e) {
      // The platform's deleteConstraint will SetNull the references when the
      // Contact delete actually fires, so the parent delete won't be blocked
      // by FK violations — but the touches/signals/dismissals would remain,
      // which is a compliance gap. Re-throw to abort the Contact delete and
      // surface the failure to the operator / compliance officer.
      Logger.logException(e, CLASS_NAME, 'beforeDelete');
      throw new EngagementException(
        'Engagement cascade-delete failed: ' +
          e.getMessage() +
          '. Touches / signals / dismissals may still exist for this Contact.'
      );
    }
  }
}
