/**
 * @description One-line trigger on Engagement_Touch__c. Delegates to
 *              `EngagementTouchTriggerHandler`, which extends the project's
 *              `TriggerHandler` framework. No business logic in the trigger
 *              body — every dispatcher concern lives in the handler so the
 *              framework's bypass / loop-count machinery can do its job.
 */
trigger EngagementTouchTrigger on Engagement_Touch__c(
  after insert,
  after update
) {
  TriggerHandler.initialiseHandler(EngagementTouchTriggerHandler.class);
}
