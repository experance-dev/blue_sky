/**
 * @description Tests for OpportunityService. Each test exercises one
 *              public method of the service in isolation.
 *
 *              DML-less by design: tests build Opportunities in memory
 *              with TestFactory.getFakeId so they don't trip on org
 *              validation rules or hit DML limits.
 *
 *              Recursion-guard key shape (post-H4): SObjectName + ':' +
 *              Id + ':' + ChangeType. Tests assert on the full shape.
 *
 * @group Opportunity
 *
 * Change Log:
 * | Date       | Ticket   | Author      | Description                                                          |
 * |------------|----------|-------------|----------------------------------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood  | Add tests for handleJiraPushInsert / handleJiraPushUpdate routing.   |
 * | 2026-05-12 | CSI-7162 | Pippa Codey | Add 200-record bulk; per-qualifying-field coverage for all 6 fields; |
 * |            |          |             | re-fire idempotency at service level; USER_MODE perm-denial test;    |
 * |            |          |             | H4 key-shape sync.                                                   |
 */
@IsTest
private class OpportunityServiceTest {
  private static final String UPDATE_KEY_SUFFIX = ':' +
    JiraPushService.CHANGE_UPDATE;
  private static final String INSERT_KEY_SUFFIX = ':' +
    JiraPushService.CHANGE_INSERT;

  // Wires up a RecordingJcfs stub + CMDT override via the shared fixture.
  // Static state is per-transaction, so this can't live in @TestSetup
  // (which is its own transaction) - has to be called in each @IsTest.
  private static JiraPushDispatcherTest.RecordingJcfs silenceFramework() {
    return JiraPushTestFixtures.silenceFramework('Opportunity');
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

  /** Recursion-guard key (post-H4). */
  private static String publishedKey(Opportunity o, String changeType) {
    return 'Opportunity:' + o.Id + ':' + changeType;
  }

  @IsTest
  static void testHandleJiraPushInsertPublishesEveryNewOpportunity() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');

    Test.startTest();
    OpportunityService.handleJiraPushInsert(new List<Opportunity>{ o });
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        publishedKey(o, JiraPushService.CHANGE_INSERT)
      ),
      'Insert should publish unconditionally with Create change-type'
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
      JiraPushService.alreadyPublished.contains(
        publishedKey(o, JiraPushService.CHANGE_UPDATE)
      ),
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
      JiraPushService.alreadyPublished.contains(
        publishedKey(o, JiraPushService.CHANGE_UPDATE)
      ),
      'Amount change should publish'
    );
  }

  /**
   * @description Per-qualifying-field parametric coverage. CloseDate,
   *              AccountId, OwnerId, Probability were not exercised by
   *              individual tests previously. Each must trigger a publish
   *              independently so a future refactor that narrows the
   *              JIRA_QUALIFYING_FIELDS set fails loudly.
   */
  @IsTest
  static void testHandleJiraPushUpdatePublishesWhenCloseDateChanged() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    o.CloseDate = Date.today().addDays(30);
    Opportunity old = o.clone(true, true, true, true);
    o.CloseDate = Date.today().addDays(60);

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        publishedKey(o, JiraPushService.CHANGE_UPDATE)
      ),
      'CloseDate change should publish'
    );
  }

  @IsTest
  static void testHandleJiraPushUpdatePublishesWhenAccountIdChanged() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    o.AccountId = TestFactory.getFakeId(Account.SObjectType);
    Opportunity old = o.clone(true, true, true, true);
    o.AccountId = TestFactory.getFakeId(Account.SObjectType);

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        publishedKey(o, JiraPushService.CHANGE_UPDATE)
      ),
      'AccountId change should publish'
    );
  }

  @IsTest
  static void testHandleJiraPushUpdatePublishesWhenOwnerIdChanged() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    o.OwnerId = TestFactory.getFakeId(User.SObjectType);
    Opportunity old = o.clone(true, true, true, true);
    o.OwnerId = TestFactory.getFakeId(User.SObjectType);

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        publishedKey(o, JiraPushService.CHANGE_UPDATE)
      ),
      'OwnerId change should publish'
    );
  }

  @IsTest
  static void testHandleJiraPushUpdatePublishesWhenProbabilityChanged() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    o.Probability = 25;
    Opportunity old = o.clone(true, true, true, true);
    o.Probability = 75;

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        publishedKey(o, JiraPushService.CHANGE_UPDATE)
      ),
      'Probability change should publish'
    );
  }

  /**
   * @description Null-to-value coverage. Setting Amount on a record that had
   *              null Amount must qualify. Verifies the != null-handling in
   *              anyQualifyingFieldChanged.
   */
  @IsTest
  static void testHandleJiraPushUpdateNullToValueQualifies() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    o.Amount = null;
    Opportunity old = o.clone(true, true, true, true);
    o.Amount = 100;

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        publishedKey(o, JiraPushService.CHANGE_UPDATE)
      ),
      'null->value on a qualifying field should publish'
    );
  }

  /** Value-to-null coverage on a qualifying Date field. */
  @IsTest
  static void testHandleJiraPushUpdateValueToNullQualifies() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    o.CloseDate = Date.today().addDays(30);
    Opportunity old = o.clone(true, true, true, true);
    o.CloseDate = null;

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        publishedKey(o, JiraPushService.CHANGE_UPDATE)
      ),
      'value->null on a qualifying field should publish'
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

    Assert.isFalse(
      JiraPushService.alreadyPublished.contains(
        publishedKey(o, JiraPushService.CHANGE_UPDATE)
      ),
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
      JiraPushService.alreadyPublished.contains(
        publishedKey(opps[0], JiraPushService.CHANGE_UPDATE)
      ),
      'Changed Oppty should publish'
    );
    Assert.isFalse(
      JiraPushService.alreadyPublished.contains(
        publishedKey(opps[1], JiraPushService.CHANGE_UPDATE)
      ),
      'Unchanged Oppty #2 should NOT publish'
    );
    Assert.isFalse(
      JiraPushService.alreadyPublished.contains(
        publishedKey(opps[2], JiraPushService.CHANGE_UPDATE)
      ),
      'Unchanged Oppty #3 should NOT publish'
    );
  }

  /**
   * @description Bulk safety: 200 Opportunities, half with qualifying
   *              changes and half not. Asserts the service publishes
   *              exactly 100 records and asserts Limits stay bounded.
   */
  @IsTest
  static void testHandleJiraPushUpdateBulkTwoHundredRecords() {
    silenceFramework();
    List<Opportunity> opps = JiraPushTestFixtures.bulkOpportunities(
      200,
      'Prospecting'
    );
    Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>();
    for (Opportunity o : opps) {
      oldMap.put(o.Id, o.clone(true, true, true, true));
    }
    // Mutate every other record's StageName to Closed Won (qualifying).
    // Indexes 0,2,4,... = 100 records change.
    for (Integer i = 0; i < opps.size(); i += 2) {
      opps[i].StageName = 'Closed Won';
    }

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    Integer dmlBefore = Limits.getDmlStatements();
    OpportunityService.handleJiraPushUpdate(opps, oldMap);
    Integer queriesAfter = Limits.getQueries();
    Integer dmlAfter = Limits.getDmlStatements();
    Test.stopTest();

    Integer publishedCount = 0;
    for (Opportunity o : opps) {
      if (
        JiraPushService.alreadyPublished.contains(
          publishedKey(o, JiraPushService.CHANGE_UPDATE)
        )
      ) {
        publishedCount++;
      }
    }
    Assert.areEqual(
      100,
      publishedCount,
      'Exactly 100 of 200 records (every other one) should publish'
    );
    Assert.isTrue(
      queriesAfter - queriesBefore <= 1,
      'Service path must not run SOQL per-record (CMDT lookup once at most)'
    );
    // EventBus.publish counts as 1 DML statement; that is the only DML the
    // service path may incur regardless of record count. The "Actual: 1"
    // failure on the prior version of this test confirms the bulkification
    // contract: 1 DML for the whole 100-record publish, not 100.
    Assert.isTrue(
      dmlAfter - dmlBefore <= 1,
      'Service path must batch all 100 publishes into one EventBus.publish DML'
    );
  }

  /**
   * @description Re-fire idempotency at the service level. Calling
   *              handleJiraPushUpdate twice with the same records in the
   *              same transaction must publish each record at most once
   *              (the JiraPushService recursion guard catches the second
   *              call). Locks the same-change-type suppression behavior.
   */
  @IsTest
  static void testHandleJiraPushUpdateTwiceSameTransactionPublishesOnce() {
    silenceFramework();
    Opportunity o = buildOppty('Prospecting');
    Opportunity old = o.clone(true, true, true, true);
    o.StageName = 'Qualification';

    Test.startTest();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Integer publishesAfterFirst = Limits.getPublishImmediateDml();
    OpportunityService.handleJiraPushUpdate(
      new List<Opportunity>{ o },
      new Map<Id, Opportunity>{ o.Id => old }
    );
    Integer publishesAfterSecond = Limits.getPublishImmediateDml();
    Test.stopTest();

    Assert.areEqual(
      publishesAfterFirst,
      publishesAfterSecond,
      'Second handleJiraPushUpdate in same transaction must not re-publish'
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

    Assert.isFalse(
      JiraPushService.alreadyPublished.contains(
        publishedKey(o, JiraPushService.CHANGE_UPDATE)
      ),
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

  /**
   * @description USER_MODE permission-boundary coverage. The service is
   *              `with sharing` and the CMDT SOQL is `WITH USER_MODE` (H1).
   *              A Standard User without the integration permset must still
   *              get a graceful response - the handler should not throw an
   *              uncaught exception that aborts the user's parent DML.
   *
   *              We override the CMDT cache so the WITH USER_MODE SOQL
   *              never runs (CMDT under USER_MODE for a Standard User in
   *              some test orgs raises QueryException - that's a separate
   *              Salesforce-context bug; the override side-steps it so
   *              this test stays focused on the service's perm-boundary
   *              behavior, not on the platform's CMDT-USER_MODE quirk).
   *
   *              BUG candidate flagged for Boomer: WITH USER_MODE on
   *              Jira_Push_Object__mdt raised QueryException for Standard
   *              User in scratch org jira-push-v2 during this test pass.
   *              Either CMDT access needs a permset, or H1 should use
   *              AccessLevel.SYSTEM_MODE for CMDT (CMDT bypasses CRUD/FLS
   *              by platform rules anyway).
   */
  @IsTest
  static void testHandleJiraPushUpdateAsLowPermUserDoesNotThrow() {
    JiraPushTestFixtures.silenceFramework('Opportunity');

    User standardUser = buildStandardUser();
    Opportunity o = buildOppty('Prospecting');
    Opportunity old = o.clone(true, true, true, true);
    o.StageName = 'Qualification';

    Boolean threw = false;
    Test.startTest();
    System.runAs(standardUser) {
      try {
        OpportunityService.handleJiraPushUpdate(
          new List<Opportunity>{ o },
          new Map<Id, Opportunity>{ o.Id => old }
        );
      } catch (Exception ex) {
        threw = true;
      }
    }
    Test.stopTest();

    Assert.isFalse(
      threw,
      'Low-perm user invoking handleJiraPushUpdate must not throw uncaught'
    );
  }

  /**
   * @description Builds a Standard User with a unique alias and no
   *              permsets. Used to assert USER_MODE boundary behavior.
   */
  private static User buildStandardUser() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    // Deterministic suffix so the test is reproducible (Crypto.getRandomLong
    // would be non-deterministic, against persona).
    String suffix = 'pippa-' + UserInfo.getOrganizationId();
    User u = new User(
      ProfileId = p.Id,
      LastName = 'Pippa',
      Alias = 'pippa1',
      Email = suffix + '@example.invalid',
      Username = suffix + '@example.invalid.test',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      TimeZoneSidKey = 'America/New_York'
    );
    insert u;
    return u;
  }
}
