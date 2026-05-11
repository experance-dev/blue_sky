/**
 * @description Trigger entry point for Opportunity. Instantiates the
 *              TriggerHandler-based dispatcher; all behavior lives in
 *              OpportunityTriggerHandler and downstream services.
 *
 * @group Opportunity
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                            |
 * |------------|----------|------------|--------------------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Initial trigger; routes after-insert / after-update to |
 * |            |          |            | OpportunityTriggerHandler for Jira-push integration.   |
 */
trigger OpportunityTrigger on Opportunity(after insert, after update) {
  new OpportunityTriggerHandler().run();
}
