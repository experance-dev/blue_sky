/**
 * @description Tests for OpportunityService. Each test exercises one
 *              public method of the service in isolation.
 *
 *              DML-less by design: tests build Opportunities in memory
 *              with TestFactory.getFakeId so they don't trip on org
 *              validation rules or hit DML limits.
 *
 * @group Opportunity
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                                          |
 * |------------|----------|------------|----------------------------------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Add tests for handleJiraPushInsert / handleJiraPushUpdate routing.   |
 */
@IsTest
private class OpportunityServiceTest {
  // Wires up a RecordingJcfs stub + CMDT override so events published in
  // these tests don't reach the real JCFS managed package during Test.stopTest.
  // Static state is per-transaction, so this can't live in @TestSetup
  // (which is its own transaction) - has to be called in each @IsTest.
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

  /**
   * @description Builds an Opportunity in memory with a fake Id and the
   *              StageName the test cares about. TestFactoryDefaults.Opp-
   *              ortunityDefaults fills the rest. No DML.
   */
  private static Opportunity buildOppty(String stage) {
    return (Opportunity) TestFactory.createSObject(
      new Opportunity(
        Id = TestFactory.getFakeId(Opportunity.SObjectType),
        StageName = stage
      )
    );
  }

  @IsTest
  static void testHandleJiraPushInsertPublishesEveryNewOpportunity() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');

    Test.startTest();
    OpportunityService.handleJiraPushInsert(new List<Opportunity>{ o });
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains('Opportunity:' + o.Id),
      'Insert should publish unconditionally'
    );
  }

  @IsTest
  static void testHandleJiraPushUpdatePublishesWhenStageNameChanged() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    Opportunity old = o.clone(true, true, true, true); // preserves Id
    o.StageName = 'Qualification';

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains('Opportunity:' + o.Id),
      'StageName change should publish'
    );
  }

  @IsTest
  static void testHandleJiraPushUpdatePublishesWhenAmountChanged() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    Opportunity old = o.clone(true, true, true, true);
    o.Amount = 999;

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains('Opportunity:' + o.Id),
      'Amount change should publish'
    );
  }

  @IsTest
  static void testHandleJiraPushUpdateSkipsWhenNoQualifyingFieldChanged() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    Opportunity old = o.clone(true, true, true, true);
    // Description isn't in JIRA_QUALIFYING_FIELDS - changing it shouldn't trigger sync
    o.Description = 'changed but not qualifying';

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    Assert.isTrue(
      !JiraPushService.alreadyPublished.contains('Opportunity:' + o.Id),
      'Non-qualifying change should not publish'
    );
  }

  @IsTest
  static void testHandleJiraPushUpdateBulkFiltersOnlyChangedRecords() {
    silenceFramework();
    List<Opportunity> opps = new List<Opportunity>{
      buildOppty('Prospecting'),
      buildOppty('Prospecting'),
      buildOppty('Prospecting')
    };

    Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>();
    for (Opportunity o : opps) {
      oldMap.put(o.Id, o.clone(true, true, true, true));
    }
    // Only the first record gets a qualifying change.
    opps[0].StageName = 'Closed Won';

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(opps, oldMap);
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains('Opportunity:' + opps[0].Id),
      'Changed Oppty should publish'
    );
    Assert.isTrue(
      !JiraPushService.alreadyPublished.contains('Opportunity:' + opps[1].Id),
      'Unchanged Oppty #2 should NOT publish'
    );
    Assert.isTrue(
      !JiraPushService.alreadyPublished.contains('Opportunity:' + opps[2].Id),
      'Unchanged Oppty #3 should NOT publish'
    );
  }

  @IsTest
  static void testHandleJiraPushUpdateSkipsRecordMissingFromOldMap() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>() // empty - simulates the edge case
    );
    Test.stopTest();

    Assert.isTrue(
      !JiraPushService.alreadyPublished.contains('Opportunity:' + o.Id),
      'Missing oldMap entry should skip safely (no throw, no publish)'
    );
  }

  @IsTest
  static void testHandlersEmptyAndNullInputAreNoOp() {
    silenceFramework();

    Test.startTest();
    OpportunityService.handleJiraPushInsert(null);
    OpportunityService.handleJiraPushInsert(new List<Opportunity>());
    OpportunityService.handleJiraPushUpdate(null, null);
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>(),
      new Map<Id, Opportunity>()
    );
    Test.stopTest();

    Assert.isTrue(JiraPushService.alreadyPublished.isEmpty());
  }
}
