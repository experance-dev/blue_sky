/**
 * @description Tests for JiraPushService publish-side behavior:
 *              recursion guard, change-type tagging, CMDT publish-side
 *              kill-switch, EventBus publish-failure logging, getConfig
 *              cache semantics, and bulk safety. Field-change qualification
 *              is NOT this class's responsibility - that lives in the calling
 *              domain service - so no tests for it here.
 *
 *              Recursion-guard key shape since H4 (CSI-7162, 2026-05-12):
 *              SObjectName + ':' + Id + ':' + ChangeType. Tests assert the
 *              full shape so the contract is locked in.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author      | Description                                  |
 * |------------|----------|-------------|----------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood  | Tests for publishInserts/publishUpdates path |
 * | 2026-05-12 | CSI-7162 | Pippa Codey | H4 key-shape sync; add bulk + cache + reset  |
 * |            |          |             | + heterogeneous-list + insert-then-update    |
 * |            |          |             | + CMDT kill-switch coverage.                 |
 */
@IsTest
private class JiraPushServiceTest {
  /**
   * @description IEventPublisher stub that fabricates Database.SaveResult
   *              failure results without actually publishing - lets us
   *              exercise JiraPushService's publish-failure branch (which
   *              calls Logger.logApiException).
   *
   *              Fragility note: Database.SaveResult has no public
   *              constructor so a hand-rolled JSON blob is the only way
   *              to build one in test context. The previous version of
   *              this stub would silently pass if Salesforce ever changed
   *              the SaveResult schema (a missing `success` field defaults
   *              to false, so `isSuccess()` returns false even if the
   *              deserialization didn't populate anything else). Mitigation:
   *              this version asserts the result actually deserialized to a
   *              not-success shape so a future API-version drift fails the
   *              test loudly with a clear message instead of producing a
   *              false negative.
   *
   *              Production-code request to Boomer: change IEventPublisher
   *              to return a List<JiraPushService.PublishResult> DTO and
   *              translate from Database.SaveResult at the seam. That kills
   *              this whole hack class.
   */
  public class FailingPublisher implements JiraPushService.IEventPublisher {
    public Integer publishCount = 0;
    public List<Database.SaveResult> publish(List<SObject> events) {
      publishCount++;
      List<Database.SaveResult> results = new List<Database.SaveResult>();
      String failJson =
        '{"success":false,"errors":[' +
        '{"statusCode":"FIELD_CUSTOM_VALIDATION_EXCEPTION",' +
        '"message":"forced","fields":[]}]}';
      for (Integer i = 0; i < events.size(); i++) {
        Database.SaveResult sr = (Database.SaveResult) JSON.deserialize(
          failJson,
          Database.SaveResult.class
        );
        Assert.areEqual(
          false,
          sr.isSuccess(),
          'FailingPublisher must deserialize to a not-success SaveResult; ' +
            'if this assertion fires, the SaveResult schema has drifted and ' +
            'the IEventPublisher seam needs a DTO wrapper (see class header).'
        );
        results.add(sr);
      }
      return results;
    }
  }

  /**
   * @description IEventPublisher stub that records what was published but
   *              returns synthetic SUCCESS results. Useful for bulk tests
   *              that need to assert one EventBus.publish call without
   *              actually firing the platform-event pipeline (which would
   *              trip the dispatcher and rack up Limits in stopTest).
   */
  public class RecordingPublisher implements JiraPushService.IEventPublisher {
    public Integer publishCount = 0;
    public List<SObject> lastEvents;
    public List<Database.SaveResult> publish(List<SObject> events) {
      publishCount++;
      lastEvents = events;
      List<Database.SaveResult> results = new List<Database.SaveResult>();
      for (Integer i = 0; i < events.size(); i++) {
        results.add(
          (Database.SaveResult) JSON.deserialize(
            '{"success":true,"id":"e01000000000000AAA"}',
            Database.SaveResult.class
          )
        );
      }
      return results;
    }
  }

  @IsTest
  static void testPublishInsertsMarksRecordsAsPublished() {
    JiraPushTestFixtures.silenceFramework('Account');
    Account a = JiraPushDispatcherTest.buildAccount();

    Test.startTest();
    JiraPushService.publishInserts(new List<Account>{ a });
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        'Account:' + a.Id + ':' + JiraPushService.CHANGE_INSERT
      ),
      'Insert should mark record as published with Create change-type'
    );
  }

  @IsTest
  static void testPublishUpdatesMarksRecordsAsPublished() {
    JiraPushTestFixtures.silenceFramework('Account');
    Account a = JiraPushDispatcherTest.buildAccount();

    Test.startTest();
    JiraPushService.publishUpdates(new List<Account>{ a });
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        'Account:' + a.Id + ':' + JiraPushService.CHANGE_UPDATE
      ),
      'Update should mark record as published with Update change-type'
    );
  }

  @IsTest
  static void testPublishRecursionGuardSuppressesSecondPublish() {
    JiraPushTestFixtures.silenceFramework('Account');
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
      'Recursion guard should suppress duplicate same-change-type publish'
    );
  }

  /**
   * @description H4-driven test. With the recursion-guard key now including
   *              ChangeType, an insert-then-update on the same record in the
   *              same transaction must produce two events (one Create, one
   *              Update). Before H4, the second publish was suppressed.
   */
  @IsTest
  static void testPublishAllowsInsertThenUpdateSameRecordSameTransaction() {
    JiraPushTestFixtures.silenceFramework('Account');
    Account a = JiraPushDispatcherTest.buildAccount();

    Test.startTest();
    JiraPushService.publishInserts(new List<Account>{ a });
    JiraPushService.publishUpdates(new List<Account>{ a });
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        'Account:' + a.Id + ':' + JiraPushService.CHANGE_INSERT
      ),
      'Insert change-type should be marked published'
    );
    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        'Account:' + a.Id + ':' + JiraPushService.CHANGE_UPDATE
      ),
      'Update change-type should also be marked published (H4 fix)'
    );
  }

  @IsTest
  static void testPublishEmptyAndNullInputAreNoOp() {
    JiraPushTestFixtures.silenceFramework('Account');

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
    JiraPushTestFixtures.silenceFramework('Account');
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
    JiraPushService.resetTransientState();

    Test.startTest();
    Jira_Push_Object__mdt cfg = JiraPushService.getConfig('Opportunity');
    Test.stopTest();

    Assert.areNotEqual(null, cfg, 'CMDT row should exist for Opportunity');
    Assert.areEqual('Opportunity', cfg.SObject_API_Name__c);
    Assert.areEqual(true, cfg.Active__c);
  }

  /**
   * @description Cache-hit coverage. getConfig must populate the cache on
   *              the first call and return cache entries on subsequent
   *              calls. CMDT SOQL doesn't always tick Limits.getQueries
   *              in test context, so the assertion is on the cache state
   *              directly: configCache is null before first call, non-null
   *              after, and the same map instance after a second call.
   */
  @IsTest
  static void testGetConfigCachesAcrossInvocations() {
    JiraPushService.resetTransientState();

    Test.startTest();
    Assert.areEqual(
      null,
      JiraPushService.configCache,
      'Precondition: cache must start null'
    );
    JiraPushService.getConfig('Opportunity');
    Map<String, Jira_Push_Object__mdt> cacheAfterFirst = JiraPushService.configCache;
    Assert.areNotEqual(
      null,
      cacheAfterFirst,
      'First getConfig call must populate the cache'
    );
    JiraPushService.getConfig('Opportunity');
    JiraPushService.getConfig('Case');
    Map<String, Jira_Push_Object__mdt> cacheAfterSecond = JiraPushService.configCache;
    Test.stopTest();

    Assert.isTrue(
      cacheAfterFirst === cacheAfterSecond,
      'Subsequent calls must reuse the same cache instance (no re-query)'
    );
  }

  @IsTest
  static void testPublishSkipsRecordsWithoutId() {
    JiraPushTestFixtures.silenceFramework('Account');
    Account a = new Account(Name = 'NoId'); // not inserted -> Id is null

    Test.startTest();
    JiraPushService.publishInserts(new List<Account>{ a });
    Test.stopTest();

    Assert.isTrue(JiraPushService.alreadyPublished.isEmpty());
  }

  /**
   * @description Bulk safety: 200 Account records produce exactly one
   *              EventBus.publish call. Asserts Limits.getPublishImmediateDml
   *              advances by exactly 1 and the publisher saw all 200 events.
   *              This is the test that catches a regression where someone
   *              moves EventBus.publish inside the per-record loop.
   */
  @IsTest
  static void testPublishInsertsBulkTwoHundredRecords() {
    JiraPushTestFixtures.silenceFramework('Account');
    RecordingPublisher pub = new RecordingPublisher();
    JiraPushService.eventPublisher = pub;
    List<Account> accts = JiraPushTestFixtures.bulkAccounts(200);

    Test.startTest();
    Integer publishesBefore = Limits.getPublishImmediateDml();
    Integer queriesBefore = Limits.getQueries();
    JiraPushService.publishInserts(accts);
    Integer publishesAfter = Limits.getPublishImmediateDml();
    Integer queriesAfter = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      1,
      pub.publishCount,
      'IEventPublisher.publish should be called exactly once for the batch'
    );
    Assert.areEqual(
      200,
      pub.lastEvents.size(),
      'All 200 records should be published in the single call'
    );
    Assert.areEqual(
      publishesBefore,
      publishesAfter,
      'Stubbed publisher must not consume getPublishImmediateDml budget'
    );
    Assert.areEqual(
      queriesBefore,
      queriesAfter,
      'publish() must not run any SOQL beyond the CMDT cache (already warm)'
    );
  }

  /**
   * @description CMDT publish-side kill-switch (M1, landed by Boomer).
   *              When isActive returns false, publish must skip and not
   *              touch the recursion guard or the event publisher.
   */
  @IsTest
  static void testPublishSkipsWhenCmdtInactive() {
    // Override with an inactive CMDT row.
    JiraPushService.resetTransientState();
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>{
      'Account' => new Jira_Push_Object__mdt(
        MasterLabel = 'Account',
        DeveloperName = 'Account',
        SObject_API_Name__c = 'Account',
        Active__c = false
      )
    };
    RecordingPublisher pub = new RecordingPublisher();
    JiraPushService.eventPublisher = pub;
    Account a = JiraPushDispatcherTest.buildAccount();

    Test.startTest();
    JiraPushService.publishInserts(new List<Account>{ a });
    Test.stopTest();

    Assert.areEqual(
      0,
      pub.publishCount,
      'Inactive CMDT must short-circuit before reaching the publisher'
    );
    Assert.isTrue(
      JiraPushService.alreadyPublished.isEmpty(),
      'Inactive CMDT must not populate the recursion guard'
    );
  }

  /**
   * @description CMDT publish-side kill-switch: missing CMDT row also
   *              fails closed (isActive returns false when CMDT lookup
   *              returns null).
   */
  @IsTest
  static void testPublishSkipsWhenCmdtRowMissing() {
    JiraPushService.resetTransientState();
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>();
    RecordingPublisher pub = new RecordingPublisher();
    JiraPushService.eventPublisher = pub;
    Account a = JiraPushDispatcherTest.buildAccount();

    Test.startTest();
    JiraPushService.publishInserts(new List<Account>{ a });
    Test.stopTest();

    Assert.areEqual(
      0,
      pub.publishCount,
      'Missing CMDT row must short-circuit (fail-closed)'
    );
  }

  /**
   * @description Heterogeneous-list defensive coverage. JiraPushService.publish
   *              captures sobjectName from records[0] and applies it to every
   *              event. If callers pass a mixed-type list (contract violation),
   *              the second record's events would mis-classify to the first
   *              record's SObject. This test asserts the current behavior so
   *              the silent mis-classification is at least visible in the suite;
   *              a redesign request lives in the handback.
   *
   *              Test mode: Account is active in CMDT, Opportunity is not.
   *              The Opportunity record will be miss-routed to Account's
   *              kill-switch (gating on records[0]'s type). The expectation
   *              is "both records publish under Account" because the caller
   *              violated the homogeneity contract; we lock this behavior
   *              in so a future caller-contract-tightening change is loud.
   *
   *              REDESIGN flagged for Boomer: either Assert.areEqual the
   *              SObject types of all records (throw JiraPushServiceException
   *              on mismatch) OR group by SObject type before publishing.
   */
  @IsTest
  static void testPublishHandlesHeterogeneousRecordListSafely() {
    JiraPushTestFixtures.silenceFramework('Account');
    RecordingPublisher pub = new RecordingPublisher();
    JiraPushService.eventPublisher = pub;

    Account a = JiraPushDispatcherTest.buildAccount();
    Opportunity o = (Opportunity) TestFactory.createSObject(
      new Opportunity(
        Id = TestFactory.getFakeId(Opportunity.SObjectType),
        Name = 'Mixed',
        StageName = 'Prospecting',
        CloseDate = Date.today().addDays(30)
      )
    );

    Test.startTest();
    JiraPushService.publishInserts(new List<SObject>{ a, o });
    Test.stopTest();

    // Current behavior: both events publish, both tagged 'Account' (records[0]
    // wins). This is the contract-violation silent mis-classification flagged
    // in the review.
    Assert.areEqual(
      1,
      pub.publishCount,
      'Single publish call regardless of mixed types'
    );
    Assert.areEqual(
      2,
      pub.lastEvents.size(),
      'Both events present in batch'
    );
    Jira_Push_Request__e firstEvent = (Jira_Push_Request__e) pub.lastEvents[0];
    Jira_Push_Request__e secondEvent = (Jira_Push_Request__e) pub.lastEvents[1];
    Assert.areEqual('Account', firstEvent.Source_Object__c);
    Assert.areEqual(
      'Account',
      secondEvent.Source_Object__c,
      'Mis-classification: Opportunity tagged Account because records[0] won. ' +
        'See class header REDESIGN note for the fix.'
    );
  }

  /**
   * @description Verifies the @TestVisible resetTransientState() helper
   *              clears the per-transaction statics it covers. Other test
   *              classes rely on this to pin a clean slate.
   *
   *              NOTE: as currently shipped (post-Boomer rewrite), reset
   *              clears alreadyPublished + configCache + configCacheOverride
   *              but does NOT reset eventPublisher. Tests that override
   *              eventPublisher must clear it manually. Flagged for Boomer:
   *              eventPublisher should also be reset to avoid carryover
   *              between sequential test methods that share statics.
   */
  @IsTest
  static void testResetTransientStateClearsTrackedStatics() {
    // Pollute every static the reset covers.
    JiraPushService.alreadyPublished.add('Account:001x:Create');
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>{
      'Foo' => new Jira_Push_Object__mdt()
    };
    JiraPushService.configCache = new Map<String, Jira_Push_Object__mdt>{
      'Bar' => new Jira_Push_Object__mdt()
    };

    Test.startTest();
    JiraPushService.resetTransientState();
    Test.stopTest();

    Assert.isTrue(
      JiraPushService.alreadyPublished.isEmpty(),
      'alreadyPublished must be empty after reset'
    );
    Assert.areEqual(
      null,
      JiraPushService.configCacheOverride,
      'configCacheOverride must be cleared'
    );
    Assert.areEqual(
      null,
      JiraPushService.configCache,
      'configCache must be cleared'
    );
  }
}
