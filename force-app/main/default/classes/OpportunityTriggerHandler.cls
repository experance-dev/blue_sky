/**
 * @description Trigger handler for Opportunity. Extends the generic
 *              TriggerHandler framework and delegates each phase to
 *              OpportunityService, which owns the domain decisions.
 *              Add additional afterInsert/afterUpdate side-effects to
 *              OpportunityService - the handler stays a thin dispatcher.
 *
 * @group Opportunity
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                              |
 * |------------|----------|------------|------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Initial implementation                   |
 */
public with sharing class OpportunityTriggerHandler extends TriggerHandler {
  protected override void afterInsert() {
    OpportunityService.handleAfterInsert((List<Opportunity>) Trigger.new);
  }

  protected override void afterUpdate() {
    OpportunityService.handleAfterUpdate(
      (List<Opportunity>) Trigger.new,
      (Map<Id, Opportunity>) Trigger.oldMap
    );
  }
}
