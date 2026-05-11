/**
 * @description End-to-end test that verifies the platform-event trigger fires,
 *              the handler runs, and the dispatcher is invoked when an event
 *              is published via EventBus.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                              |
 * |------------|----------|------------|------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | E2E test for PE trigger -> dispatcher    |
 */
@IsTest
private class JiraPushRequestHandlerTest {
  @IsTest
  static void publishedEventInvokesDispatcherAndJcfs() {
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>{
      'Account' => new Jira_Push_Object__mdt(
        MasterLabel = 'Account',
        DeveloperName = 'Account',
        SObject_API_Name__c = 'Account',
        Active__c = true
      )
    };
    JiraPushDispatcherTest.RecordingJcfs stub = new JiraPushDispatcherTest.RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Account a = (Account) TestFactory.createSObject(new Account(), true);

    Test.startTest();
    EventBus.publish(
      new Jira_Push_Request__e(
        Source_Object__c = 'Account',
        Source_Id__c = String.valueOf(a.Id),
        Change_Type__c = 'Update',
        Event_Timestamp__c = Datetime.now(),
        Transaction_Id__c = 'e2e-1'
      )
    );
    Test.stopTest();

    System.assertEquals(
      1,
      stub.callCount,
      'Trigger -> Handler -> Dispatcher -> JCFS chain should fire once'
    );
    System.assertEquals(a.Id, stub.lastRecords[0].Id);
  }
}
