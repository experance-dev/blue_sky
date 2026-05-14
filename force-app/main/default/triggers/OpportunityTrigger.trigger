/**
 * @description Trigger entry point for Opportunity. Routes to the
 *              OpportunityTriggerHandler via the Zelis TriggerHandler
 *              framework; all behavior lives in OpportunityTriggerHandler
 *              and downstream services.
 *
 * @group Opportunity
 * @author David Wood
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                                                 |
 * |------------|----------|------------|-----------------------------------------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Route after-insert / after-update to OpportunityTriggerHandler for the      |
 * |            |          |            | Jira-push integration.                                                      |
 * | 2026-05-12 | CSI-7162 | David Wood | Migrate to Zelis TriggerHandler.initialiseHandler API.                      |
 */
trigger OpportunityTrigger on Opportunity(after insert, after update) {
  TriggerHandler.initialiseHandler(OpportunityTriggerHandler.class);
}
