trigger JiraPushRequestTrigger on Jira_Push_Request__e(after insert) {
  new JiraPushRequestHandler().run();
}
