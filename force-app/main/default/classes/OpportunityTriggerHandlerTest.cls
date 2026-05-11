/**
 * @description End-to-end tests for the Opportunity trigger pipeline.
 *              Real Opportunity DML drives the trigger, the handler
 *              delegates to OpportunityService, and downstream side-
 *              effects are observed via stubs. Verifies the whole
 *              chain wires together rather than testing pieces in
 *              isolation (those are covered by OpportunityServiceTest).
 *
 * @group Opportunity
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                            |
 * |------------|----------|------------|--------------------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | E2E coverage of the Opportunity -> Jira-push pipeline. |
 */
@IsTest
private class OpportunityTriggerHandlerTest {
  private static void silenceFramework() {
    JiraPushDispatcher.jcfs = new JiraPushDispatcherTest.RecordingJcfs();
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>{
      'Opportunity' => new Jira_Push_Object__mdt(
        MasterLabel = 'Opportunity',
        DeveloperName = 'Opportunity',
        SObject_API_Name__c = 'Opportunity',
        Active__c = true
      )
    };
  }

  @IsTest
  static void testAfterInsertEndToEndReachesJcfs() {
    silenceFramework();
    JiraPushDispatcherTest.RecordingJcfs stub = (JiraPushDispatcherTest.RecordingJcfs) JiraPushDispatcher.jcfs;

    // Real DML - drives OpportunityTrigger -> Handler -> Service -> PE.
    // Required fields set explicitly because TestFactoryDefaults is empty
    // in this branch; in the work org, the defaults class fills them.
    Opportunity o = new Opportunity(
      Name = 'E2E Insert',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30)
    );

    Test.startTest();
    insert o;
    Test.stopTest();

    Assert.areEqual(
      1,
      stub.callCount,
      'Insert should drive the full pipeline through to JCFS'
    );
    Assert.areEqual(o.Id, stub.lastRecords[0].Id);
  }

  @IsTest
  static void testAfterUpdateQualifyingFieldChangeEndToEnd() {
    silenceFramework();

    Opportunity o = new Opportunity(
      Name = 'E2E Update',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30)
    );
    insert o;

    // Reset the recording stub so we only count the update-driven call.
    JiraPushDispatcherTest.RecordingJcfs stub = new JiraPushDispatcherTest.RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;
    JiraPushService.alreadyPublished.clear();

    o.StageName = 'Qualification';

    Test.startTest();
    update o;
    Test.stopTest();

    Assert.areEqual(
      1,
      stub.callCount,
      'Qualifying-field update should drive the full pipeline through to JCFS'
    );
  }

}
// Note: the non-qualifying update case (Description change etc.) is covered
// directly by OpportunityServiceTest.handleAfterUpdate_skipsWhenNoQualifying-
// FieldChanged. Re-testing it through real DML would conflict with the
// insert's deferred PE delivery and adds no wiring assurance.
