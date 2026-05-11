/**
 * @description Tests for OpportunityService - verifies which Opportunities
 *              get handed to JiraPushService for insert and update flows,
 *              including bulk and edge cases.
 *
 *              DML-less by design: the only thing under test that touches
 *              an Opportunity Id is the in-memory recursion-guard key and
 *              the published event payload. TestFactory.getFakeId mints
 *              a syntactically-valid 18-char Id without DML, so every
 *              test builds its Opportunities in memory.
 *
 *              No @TestSetup: nothing to insert.
 *
 * @group Opportunity
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                            |
 * |------------|----------|------------|--------------------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Initial - covers insert (all), update (filtered), bulk |
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
  static void testHandleAfterInsertPublishesEveryNewOpportunity() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');

    Test.startTest();
    OpportunityService.handleAfterInsert(new List<Opportunity>{ o });
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains('Opportunity:' + o.Id),
      'Insert should publish unconditionally'
    );
  }

  @IsTest
  static void testHandleAfterUpdatePublishesWhenStageNameChanged() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    Opportunity old = o.clone(true, true, true, true); // preserves Id
    o.StageName = 'Qualification';

    Test.startTest();
    OpportunityService.handleAfterUpdate(
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
  static void testHandleAfterUpdatePublishesWhenAmountChanged() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    Opportunity old = o.clone(true, true, true, true);
    o.Amount = 999;

    Test.startTest();
    OpportunityService.handleAfterUpdate(
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
  static void testHandleAfterUpdateSkipsWhenNoQualifyingFieldChanged() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    Opportunity old = o.clone(true, true, true, true);
    // Description isn't in QUALIFYING_FIELDS - changing it shouldn't trigger sync
    o.Description = 'changed but not qualifying';

    Test.startTest();
    OpportunityService.handleAfterUpdate(
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
  static void testHandleAfterUpdateBulkFiltersOnlyChangedRecords() {
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
    OpportunityService.handleAfterUpdate(opps, oldMap);
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
  static void testHandleAfterUpdateSkipsRecordMissingFromOldMap() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');

    Test.startTest();
    OpportunityService.handleAfterUpdate(
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
    OpportunityService.handleAfterInsert(null);
    OpportunityService.handleAfterInsert(new List<Opportunity>());
    OpportunityService.handleAfterUpdate(null, null);
    OpportunityService.handleAfterUpdate(
      new List<Opportunity>(),
      new Map<Id, Opportunity>()
    );
    Test.stopTest();

    Assert.isTrue(JiraPushService.alreadyPublished.isEmpty());
  }
}
