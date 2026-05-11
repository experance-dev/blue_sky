/**
 * @description Tests for JiraPushService publish-side behavior:
 *              recursion guard, change-type tagging, empty-input
 *              short-circuits. Field-change qualification is NOT this
 *              class's responsibility - that lives in the calling
 *              domain service - so no tests for it here.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                  |
 * |------------|----------|------------|----------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Tests for publishInserts/publishUpdates path |
 */
@IsTest
private class JiraPushServiceTest {
  /** Quiets the dispatcher so PE delivery in stopTest doesn't try real JCFS. */
  private static void silenceDispatcher() {
    JiraPushDispatcher.jcfs = new JiraPushDispatcherTest.RecordingJcfs();
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>{
      'Account' => new Jira_Push_Object__mdt(
        MasterLabel = 'Account',
        DeveloperName = 'Account',
        SObject_API_Name__c = 'Account',
        Active__c = true
      )
    };
  }

  @IsTest
  static void publishInserts_marksRecordsAsPublished() {
    silenceDispatcher();
    Account a = new Account(Name = 'New');
    insert a;

    Test.startTest();
    JiraPushService.publishInserts(new List<Account>{ a });
    Test.stopTest();

    System.assert(
      JiraPushService.alreadyPublished.contains('Account:' + a.Id),
      'Insert should mark record as published'
    );
  }

  @IsTest
  static void publishUpdates_marksRecordsAsPublished() {
    silenceDispatcher();
    Account a = new Account(Name = 'Updated');
    insert a;

    Test.startTest();
    JiraPushService.publishUpdates(new List<Account>{ a });
    Test.stopTest();

    System.assert(
      JiraPushService.alreadyPublished.contains('Account:' + a.Id),
      'Update should mark record as published'
    );
  }

  @IsTest
  static void publish_recursionGuardSuppressesSecondPublish() {
    silenceDispatcher();
    Account a = new Account(Name = 'Once');
    insert a;

    Test.startTest();
    JiraPushService.publishUpdates(new List<Account>{ a });
    Integer afterFirst = Limits.getPublishImmediateDml();
    JiraPushService.publishUpdates(new List<Account>{ a });
    Integer afterSecond = Limits.getPublishImmediateDml();
    Test.stopTest();

    System.assertEquals(
      afterFirst,
      afterSecond,
      'Recursion guard should suppress duplicate publish in same transaction'
    );
  }

  @IsTest
  static void publish_emptyAndNullInputAreNoOp() {
    silenceDispatcher();

    Test.startTest();
    JiraPushService.publishInserts(null);
    JiraPushService.publishInserts(new List<Account>());
    JiraPushService.publishUpdates(null);
    JiraPushService.publishUpdates(new List<Account>());
    Test.stopTest();

    System.assert(JiraPushService.alreadyPublished.isEmpty());
  }

  @IsTest
  static void publish_skipsRecordsWithoutId() {
    silenceDispatcher();
    Account a = new Account(Name = 'NoId'); // not inserted -> Id is null

    Test.startTest();
    JiraPushService.publishInserts(new List<Account>{ a });
    Test.stopTest();

    System.assert(JiraPushService.alreadyPublished.isEmpty());
  }
}
