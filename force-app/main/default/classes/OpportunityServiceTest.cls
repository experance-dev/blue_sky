/**
 * @description Tests for OpportunityService - verifies which Opportunities
 *              get handed to JiraPushService for insert and update flows,
 *              including bulk and edge cases.
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

  private static Opportunity makeOppty(String stage) {
    return new Opportunity(
      Name = 'OppT ' + Math.mod(Crypto.getRandomLong(), 1000000),
      StageName = stage,
      CloseDate = Date.today().addDays(30),
      Amount = 100
    );
  }

  @IsTest
  static void handleAfterInsert_publishesEveryNewOpportunity() {
    silenceFramework();
    Opportunity o = makeOppty('Prospecting');
    insert o;

    Test.startTest();
    OpportunityService.handleAfterInsert(new List<Opportunity>{ o });
    Test.stopTest();

    System.assert(
      JiraPushService.alreadyPublished.contains('Opportunity:' + o.Id),
      'Insert should publish unconditionally'
    );
  }

  @IsTest
  static void handleAfterUpdate_publishesWhenStageNameChanged() {
    silenceFramework();
    Opportunity o = makeOppty('Prospecting');
    insert o;
    Opportunity old = o.clone(true, true, true, true); // preserves Id
    o.StageName = 'Qualification';

    Test.startTest();
    OpportunityService.handleAfterUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    System.assert(
      JiraPushService.alreadyPublished.contains('Opportunity:' + o.Id),
      'StageName change should publish'
    );
  }

  @IsTest
  static void handleAfterUpdate_publishesWhenAmountChanged() {
    silenceFramework();
    Opportunity o = makeOppty('Prospecting');
    insert o;
    Opportunity old = o.clone(true, true, true, true);
    o.Amount = 999;

    Test.startTest();
    OpportunityService.handleAfterUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    System.assert(
      JiraPushService.alreadyPublished.contains('Opportunity:' + o.Id),
      'Amount change should publish'
    );
  }

  @IsTest
  static void handleAfterUpdate_skipsWhenNoQualifyingFieldChanged() {
    silenceFramework();
    Opportunity o = makeOppty('Prospecting');
    insert o;
    Opportunity old = o.clone(true, true, true, true);
    // Description isn't in QUALIFYING_FIELDS - changing it shouldn't trigger sync
    o.Description = 'changed but not qualifying';

    Test.startTest();
    OpportunityService.handleAfterUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    System.assert(
      !JiraPushService.alreadyPublished.contains('Opportunity:' + o.Id),
      'Non-qualifying change should not publish'
    );
  }

  @IsTest
  static void handleAfterUpdate_bulkFiltersOnlyChangedRecords() {
    silenceFramework();
    List<Opportunity> opps = new List<Opportunity>{
      makeOppty('Prospecting'),
      makeOppty('Prospecting'),
      makeOppty('Prospecting')
    };
    insert opps;

    Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>();
    for (Opportunity o : opps) {
      oldMap.put(o.Id, o.clone(true, true, true, true));
    }
    // Only the first record gets a qualifying change.
    opps[0].StageName = 'Closed Won';

    Test.startTest();
    OpportunityService.handleAfterUpdate(opps, oldMap);
    Test.stopTest();

    System.assert(
      JiraPushService.alreadyPublished.contains('Opportunity:' + opps[0].Id),
      'Changed Oppty should publish'
    );
    System.assert(
      !JiraPushService.alreadyPublished.contains('Opportunity:' + opps[1].Id),
      'Unchanged Oppty #2 should NOT publish'
    );
    System.assert(
      !JiraPushService.alreadyPublished.contains('Opportunity:' + opps[2].Id),
      'Unchanged Oppty #3 should NOT publish'
    );
  }

  @IsTest
  static void handleAfterUpdate_skipsRecordMissingFromOldMap() {
    silenceFramework();
    Opportunity o = makeOppty('Prospecting');
    insert o;

    Test.startTest();
    OpportunityService.handleAfterUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>() // empty - simulates the edge case
    );
    Test.stopTest();

    System.assert(
      !JiraPushService.alreadyPublished.contains('Opportunity:' + o.Id),
      'Missing oldMap entry should skip safely (no throw, no publish)'
    );
  }

  @IsTest
  static void handlers_emptyAndNullInputAreNoOp() {
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

    System.assert(JiraPushService.alreadyPublished.isEmpty());
  }
}
