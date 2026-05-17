/**
 * @description After-insert / after-update handler that routes resolved touches
 *              into `Opportunity_Engagement_Signal__c` records. Only routes
 *              touches whose `Resolution_Status__c` just became `Resolved`:
 *              new inserts that arrive resolved, or updates that flipped to
 *              resolved. Idempotency for re-fires is enforced inside
 *              `EngagementSignalRouter.routeTouches`.
 *
 *              Extends the project's `TriggerHandler` framework so this handler
 *              participates in the org-wide loop-count and bypass machinery.
 *              The framework's hook method names are `afterInsert` and
 *              `afterUpdate` — confirmed against `TriggerHandler.dispatchToHook`.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class EngagementTouchTriggerHandler extends TriggerHandler {
  private static final String STATUS_RESOLVED = 'Resolved';

  /**
   * @description Framework entry point. Branches on trigger context and
   *              delegates to the relevant hook helper.
   */
  public void initialise() {
    if (Trigger.isAfter && Trigger.isInsert) {
      handleAfterInsert();
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
      handleAfterUpdate();
    }
  }

  /**
   * @description After-insert hook. Collects ids of newly inserted touches
   *              that arrive already-resolved and routes them.
   */
  private void handleAfterInsert() {
    List<Engagement_Touch__c> newList = (List<Engagement_Touch__c>) Trigger.new;
    if (newList == null) {
      return;
    }
    Set<Id> resolvedIds = new Set<Id>();
    for (Engagement_Touch__c t : newList) {
      if (t.Resolution_Status__c == STATUS_RESOLVED) {
        resolvedIds.add(t.Id);
      }
    }
    if (!resolvedIds.isEmpty()) {
      EngagementSignalRouter.routeTouches(resolvedIds);
    }
  }

  /**
   * @description After-update hook. Detects the *transition* into Resolved
   *              from any other status — routing an already-resolved touch
   *              again on an unrelated field update would be wasted work
   *              (idempotency would catch it, but the early exit is cleaner).
   */
  private void handleAfterUpdate() {
    Map<Id, Engagement_Touch__c> oldMap = (Map<Id, Engagement_Touch__c>) Trigger.oldMap;
    List<Engagement_Touch__c> newList = (List<Engagement_Touch__c>) Trigger.new;
    if (newList == null || oldMap == null) {
      return;
    }
    Set<Id> newlyResolvedIds = new Set<Id>();
    for (Engagement_Touch__c t : newList) {
      Engagement_Touch__c o = oldMap.get(t.Id);
      if (
        o != null &&
        o.Resolution_Status__c != STATUS_RESOLVED &&
        t.Resolution_Status__c == STATUS_RESOLVED
      ) {
        newlyResolvedIds.add(t.Id);
      }
    }
    if (!newlyResolvedIds.isEmpty()) {
      EngagementSignalRouter.routeTouches(newlyResolvedIds);
    }
  }
}
