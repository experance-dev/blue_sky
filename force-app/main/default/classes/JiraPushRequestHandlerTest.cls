/**
 * @description End-to-end tests that verify the platform-event trigger fires,
 *              the handler runs, and the dispatcher is invoked when events
 *              are published via EventBus. Covers single-event happy path
 *              and 200-event bulk delivery.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author      | Description                              |
 * |------------|----------|-------------|------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood  | E2E test for PE trigger -> dispatcher    |
 * | 2026-05-12 | CSI-7162 | Pippa Codey | Add 200-event bulk PE delivery coverage  |
 */
@IsTest
private class JiraPushRequestHandlerTest {
  @IsTest
  static void testPublishedEventInvokesDispatcherAndJcfs() {
    JiraPushDispatcherTest.RecordingJcfs stub = JiraPushTestFixtures.silenceFramework(
      'Account'
    );

    Account a = JiraPushDispatcherTest.buildAccount();

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

    Assert.areEqual(
      1,
      stub.callCount,
      'Trigger -> Handler -> Dispatcher -> JCFS chain should fire once'
    );
    Assert.areEqual(a.Id, stub.lastRecords[0].Id);
  }

  /**
   * @description Bulk PE delivery: 200 events spanning Account + Opportunity
   *              published in one EventBus call. After Test.stopTest() the
   *              PE trigger fires, the handler delegates, and the dispatcher
   *              must group into exactly two JCFS calls (one per SObject).
   *              Asserts Limits.getDmlStatements stays bounded.
   */
  @IsTest
  static void testBulkPEPublishDeliversAllEventsToDispatcher() {
    JiraPushDispatcherTest.RecordingJcfs stub = JiraPushTestFixtures.silenceFramework(
      new List<String>{ 'Account', 'Opportunity' }
    );

    List<Account> accts = JiraPushTestFixtures.bulkAccounts(120);
    List<Opportunity> opps = JiraPushTestFixtures.bulkOpportunities(
      80,
      'Prospecting'
    );

    List<Jira_Push_Request__e> events = new List<Jira_Push_Request__e>();
    Datetime ts = Datetime.newInstance(2026, 5, 12, 12, 0, 0);
    for (Account a : accts) {
      events.add(
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = ts,
          Transaction_Id__c = 'bulk-pe'
        )
      );
    }
    for (Opportunity o : opps) {
      events.add(
        new Jira_Push_Request__e(
          Source_Object__c = 'Opportunity',
          Source_Id__c = String.valueOf(o.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = ts,
          Transaction_Id__c = 'bulk-pe'
        )
      );
    }

    Test.startTest();
    Integer dmlBefore = Limits.getDmlStatements();
    EventBus.publish(events);
    Test.stopTest();
    Integer dmlAfter = Limits.getDmlStatements();

    Assert.areEqual(
      2,
      stub.callCount,
      'One JCFS call per SObject type across the 200-event PE batch'
    );
    Assert.isTrue(
      dmlAfter - dmlBefore < 5,
      'PE publish + trigger pipeline must not amplify DML beyond a small budget'
    );
  }
}
