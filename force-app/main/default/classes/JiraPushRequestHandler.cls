/**
 * @description TriggerHandler for Jira_Push_Request__e. Platform Event triggers
 *              only fire after insert; we delegate to JiraPushDispatcher which
 *              groups by SObjectType, re-queries, and calls JCFS.
 *
 * @group Jira Integration
 */
public with sharing class JiraPushRequestHandler extends TriggerHandler {
  protected override void afterInsert() {
    JiraPushDispatcher.process(
      (List<Jira_Push_Request__e>) Trigger.new
    );
  }
}
