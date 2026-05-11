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
  /**
   * @description IEventPublisher stub that fabricates Database.SaveResult
   *              failure results without actually publishing - lets us
   *              exercise JiraPushService's publish-failure branch (which
   *              calls Logger.logApiException).
   */
  public class FailingPublisher implements JiraPushService.IEventPublisher {
    public List<Database.SaveResult> publish(List<SObject> events) {
      List<Database.SaveResult> results = new List<Database.SaveResult>();
      String failJson =
        '{"success":false,"errors":[' +
        '{"statusCode":"FIELD_CUSTOM_VALIDATION_EXCEPTION",' +
        '"message":"forced","fields":[]}]}';
      for (Integer i = 0; i < events.size(); i++) {
        results.add(
          (Database.SaveResult) JSON.deserialize(failJson, Database.SaveResult.class)
        );
      }
      return results;
    }
  }

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
  static void testPublishInsertsMarksRecordsAsPublished() {
    silenceDispatcher();
    Account a = JiraPushDispatcherTest.buildAccount();

    Test.startTest();
    JiraPushService.publishInserts(new List<Account>{ a });
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains('Account:' + a.Id),
      'Insert should mark record as published'
    );
  }

  @IsTest
  static void testPublishUpdatesMarksRecordsAsPublished() {
    silenceDispatcher();
    Account a = JiraPushDispatcherTest.buildAccount();

    Test.startTest();
    JiraPushService.publishUpdates(new List<Account>{ a });
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains('Account:' + a.Id),
      'Update should mark record as published'
    );
  }

  @IsTest
  static void testPublishRecursionGuardSuppressesSecondPublish() {
    silenceDispatcher();
    Account a = JiraPushDispatcherTest.buildAccount();

    Test.startTest();
    JiraPushService.publishUpdates(new List<Account>{ a });
    Integer afterFirst = Limits.getPublishImmediateDml();
    JiraPushService.publishUpdates(new List<Account>{ a });
    Integer afterSecond = Limits.getPublishImmediateDml();
    Test.stopTest();

    Assert.areEqual(
      afterFirst,
      afterSecond,
      'Recursion guard should suppress duplicate publish in same transaction'
    );
  }

  @IsTest
  static void testPublishEmptyAndNullInputAreNoOp() {
    silenceDispatcher();

    Test.startTest();
    JiraPushService.publishInserts(null);
    JiraPushService.publishInserts(new List<Account>());
    JiraPushService.publishUpdates(null);
    JiraPushService.publishUpdates(new List<Account>());
    Test.stopTest();

    Assert.isTrue(JiraPushService.alreadyPublished.isEmpty());
  }

  @IsTest
  static void testPublishLogsApiExceptionWhenEventBusPublishFails() {
    // Negative path: every SaveResult comes back failed, so the publish
    // loop hits Logger.logApiException for each event.
    silenceDispatcher();
    JiraPushService.eventPublisher = new FailingPublisher();

    Account a = JiraPushDispatcherTest.buildAccount();

    Test.startTest();
    JiraPushService.publishInserts(new List<Account>{ a });
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM API_Exception_Log__c],
      'Failed EventBus.publish should produce one log row per event'
    );
  }

  @IsTest
  static void testGetConfigQueriesCmdtWhenNoOverride() {
    // Positive path: with no configCacheOverride set, getConfig runs
    // the real SOQL against Jira_Push_Object__mdt. The deploy seeded
    // Opportunity and Case records, so this should return Opportunity.
    JiraPushService.configCacheOverride = null;
    JiraPushService.configCache = null;

    Test.startTest();
    Jira_Push_Object__mdt cfg = JiraPushService.getConfig('Opportunity');
    Test.stopTest();

    Assert.areNotEqual(null, cfg, 'CMDT row should exist for Opportunity');
    Assert.areEqual('Opportunity', cfg.SObject_API_Name__c);
    Assert.areEqual(true, cfg.Active__c);
  }

  @IsTest
  static void testPublishSkipsRecordsWithoutId() {
    silenceDispatcher();
    Account a = new Account(Name = 'NoId'); // not inserted -> Id is null

    Test.startTest();
    JiraPushService.publishInserts(new List<Account>{ a });
    Test.stopTest();

    Assert.isTrue(JiraPushService.alreadyPublished.isEmpty());
  }
}
