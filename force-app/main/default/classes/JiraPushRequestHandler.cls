/**
 * @description TriggerHandler for Jira_Push_Request__e. Platform Event triggers
 *              only fire after insert; we delegate to JiraPushDispatcher which
 *              groups by SObjectType and calls JCFS.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                              |
 * |------------|----------|------------|------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Initial PE trigger handler               |
 */
public with sharing class JiraPushRequestHandler extends TriggerHandler {
  protected override void afterInsert() {
    JiraPushDispatcher.process(
      (List<Jira_Push_Request__e>) Trigger.new
    );
  }
}
