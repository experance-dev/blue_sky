trigger OpportunityTrigger on Opportunity(after insert, after update) {
  new OpportunityTriggerHandler().run();
}
