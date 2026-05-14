trigger JiraPushRequestTrigger on Jira_Push_Request__e(after insert) {
  TriggerHandler.initialiseHandler(JiraPushRequestHandler.class);
}
