/**
 * @description Trigger handler for Opportunity. Extends the generic
 *              TriggerHandler framework and delegates each phase to the
 *              OpportunityService domain layer. The handler stays a
 *              thin dispatcher - add new side-effects on Opportunity
 *              by adding methods to OpportunityService, not here.
 *
 * @group Opportunity
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                            |
 * |------------|----------|------------|--------------------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Initial handler; wire afterInsert / afterUpdate to     |
 * |            |          |            | OpportunityService for Jira-push integration.          |
 */
public with sharing class OpportunityTriggerHandler extends TriggerHandler {
  protected override void afterInsert() {
    OpportunityService.handleJiraPushInsert((List<Opportunity>) Trigger.new);
  }

  protected override void afterUpdate() {
    OpportunityService.handleJiraPushUpdate(
      (List<Opportunity>) Trigger.new,
      (Map<Id, Opportunity>) Trigger.oldMap
    );
  }
}
