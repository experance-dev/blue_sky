/**
 * @description Before-delete handler on Lead. Cascade-deletes Engagement
 *              Attribution records that point at the Lead via `Lead__c`
 *              (typically untransferred touches captured before Lead
 *              conversion — converted Leads will have already been
 *              reparented by `LeadEngagementReparentHandler`, so the
 *              cascade is normally a no-op for the converted case).
 *
 *              Runs alongside `LeadEngagementReparentHandler` on the same
 *              trigger; both are dispatched by the `TriggerHandler`
 *              framework, each handling its own event context.
 *
 *              On cascade failure, surfaces an `EngagementException` so the
 *              Lead delete is aborted rather than leaving residual
 *              behavioural data behind.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class LeadEngagementErasureHandler extends TriggerHandler {
  private static final String CLASS_NAME = 'LeadEngagementErasureHandler';

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
   * @description Before-delete hook. Collects the doomed Lead ids and
   *              delegates the cascade to `EngagementErasureService`.
   */
  private void handleBeforeDelete() {
    if (Trigger.old == null) {
      return;
    }
    Set<Id> leadIds = new Map<Id, SObject>((List<Lead>) Trigger.old).keySet();
    if (leadIds.isEmpty()) {
      return;
    }
    try {
      EngagementErasureService.ErasureSummary s = EngagementErasureService.eraseForLeads(
        leadIds
      );
      Logger.info(
        String.format(
          'Subject-erasure cascade for {0} Lead(s): deleted {1} touch(es), {2} signal(s).',
          new List<Object>{ leadIds.size(), s.touchesDeleted, s.signalsDeleted }
        ),
        CLASS_NAME,
        'beforeDelete'
      );
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'beforeDelete');
      throw new EngagementException(
        'Engagement cascade-delete failed: ' +
          e.getMessage() +
          '. Touches / signals may still exist for this Lead.'
      );
    }
  }
}
