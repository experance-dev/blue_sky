/**
 * @description Tests for JiraPushDispatcher: event grouping, config gating,
 *              ID-only SObject construction, type coercion, JCFS seam, and
 *              bulk PE-batch survival. Houses the shared RecordingJcfs stub
 *              and buildAccount helper that other test classes reuse via
 *              JiraPushDispatcherTest.*.
 *
 *              DML-less: the dispatcher only needs an Id to call
 *              SObjectType.newSObject(id) - the record doesn't need to
 *              exist in the DB. buildAccount() uses TestFactory.getFakeId
 *              to mint a syntactically-valid Id with zero DML.
 *
 *              ╔══════════════════════════════════════════════════════════╗
 *              ║ PUBLIC TEST-HELPER CONTRACT                              ║
 *              ║                                                          ║
 *              ║ The following are consumed by five other test classes    ║
 *              ║ (JiraPushServiceTest, JiraPushRequestHandlerTest,        ║
 *              ║  OpportunityServiceTest, OpportunityTriggerHandlerTest,  ║
 *              ║  LoggerApiExceptionTest, JiraPushTestFixtures). Renaming ║
 *              ║ or refactoring breaks all of them - update callers in    ║
 *              ║ the same commit:                                         ║
 *              ║                                                          ║
 *              ║   - public class RecordingJcfs (IJcfsApi stub)           ║
 *              ║   - public class ThrowingJcfsApi (IJcfsApi stub)         ║
 *              ║   - public static Account buildAccount()                 ║
 *              ╚══════════════════════════════════════════════════════════╝
 *
 *              JcfsApiAdapter intentional test gap: the adapter is the
 *              production binding for IJcfsApi and is .forceignore'd from
 *              scratch-org deploys (the JCFS managed package isn't there).
 *              We test the seam via RecordingJcfs, and the NoOp fallback
 *              via testProcessUsesNoOpFallbackWhenAdapterNotDeployed +
 *              testNoOpFallbackBehaviorRegressionLock below. The adapter
 *              itself runs in CI environments that DO have JCFS installed.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author      | Description                                |
 * |------------|----------|-------------|--------------------------------------------|
 * | 2026-05-12 | CSI-7162 | David Wood  | Tests for dispatcher and JCFS seam: bulk PE batch, re-fire dedup, NoOp regression lock |
 */
@IsTest
public class JiraPushDispatcherTest {
  /** Throws on every call - used to exercise dispatcher's JCFS-failure catch path. */
  public class ThrowingJcfsApi implements JiraPushDispatcher.IJcfsApi {
    public List<JiraPushDispatcher.JcfsPushResult> pushUpdates(
      List<SObject> records
    ) {
      throw new System.DmlException('forced JCFS failure');
    }
  }

  /** Records the typed list passed to JCFS for assertion. */
  public class RecordingJcfs implements JiraPushDispatcher.IJcfsApi {
    public Integer callCount = 0;
    public List<SObject> lastRecords;
    public String lastListRender;
    // Per-record results returned to the dispatcher; default is success
    // for each input record. Set `simulatedResults` directly if a test
    // wants to assert the dispatcher's per-record failure logging path.
    public List<JiraPushDispatcher.JcfsPushResult> simulatedResults;

    public List<JiraPushDispatcher.JcfsPushResult> pushUpdates(
      List<SObject> records
    ) {
      callCount++;
      lastRecords = records;
      lastListRender = String.valueOf(records);
      if (simulatedResults != null) {
        return simulatedResults;
      }
      List<JiraPushDispatcher.JcfsPushResult> results = new List<JiraPushDispatcher.JcfsPushResult>();
      if (records != null) {
        for (SObject r : records) {
          results.add(
            new JiraPushDispatcher.JcfsPushResult(r.Id, true, null, null)
          );
        }
      }
      return results;
    }
  }

  /**
   * @description Builds an Account in memory with a fake Id. Shared with
   *              JiraPushServiceTest, JiraPushRequestHandlerTest, and
   *              LoggerApiExceptionTest - those classes call this directly
   *              as JiraPushDispatcherTest.buildAccount().
   */
  public static Account buildAccount() {
    return (Account) TestFactory.createSObject(
      new Account(Id = TestFactory.getFakeId(Account.SObjectType))
    );
  }

  private static Jira_Push_Object__mdt accountConfig(Boolean active) {
    return new Jira_Push_Object__mdt(
      MasterLabel = 'Account',
      DeveloperName = 'Account',
      SObject_API_Name__c = 'Account',
      Active__c = active
    );
  }

  private static void overrideConfig(Jira_Push_Object__mdt cfg) {
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>{
      'Account' => cfg
    };
  }

  @IsTest
  static void testProcessCallsJcfsWithIdOnlyConcreteList() {
    overrideConfig(accountConfig(true));
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Account a = buildAccount();
    Jira_Push_Request__e e = new Jira_Push_Request__e(
      Source_Object__c = 'Account',
      Source_Id__c = String.valueOf(a.Id),
      Change_Type__c = 'Update',
      Event_Timestamp__c = Datetime.now(),
      Transaction_Id__c = 'tx-1'
    );

    Test.startTest();
    JiraPushDispatcher.process(new List<Jira_Push_Request__e>{ e });
    Test.stopTest();

    Assert.areEqual(1, stub.callCount, 'JCFS called once');
    Assert.areEqual(1, stub.lastRecords.size(), 'one record passed');
    Assert.areEqual(a.Id, stub.lastRecords[0].Id, 'correct Id');
    Assert.areEqual(
      Account.SObjectType,
      stub.lastRecords[0].getSObjectType(),
      'runtime type is Account, satisfying JCFS concrete-list requirement'
    );
  }

  @IsTest
  static void testProcessSkipsWhenConfigMissing() {
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>();
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Account a = buildAccount();

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now()
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(0, stub.callCount, 'no config -> no JCFS call');
  }

  @IsTest
  static void testProcessSkipsWhenConfigInactive() {
    overrideConfig(accountConfig(false));
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Account a = buildAccount();

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now()
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(0, stub.callCount, 'inactive config -> no JCFS call');
  }

  @IsTest
  static void testProcessHandlesUnknownSObjectGracefully() {
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>{
      'NotARealSObject__c' => new Jira_Push_Object__mdt(
        MasterLabel = 'X',
        DeveloperName = 'X',
        SObject_API_Name__c = 'NotARealSObject__c',
        Active__c = true
      )
    };
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'NotARealSObject__c',
          Source_Id__c = '001000000000000AAA',
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now()
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(0, stub.callCount, 'unknown SObject -> logged, no call');
  }

  @IsTest
  static void testProcessSkipsBlankEventsAndContinues() {
    overrideConfig(accountConfig(true));
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Account a = buildAccount();

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(Source_Object__c = '', Source_Id__c = ''),
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now()
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(1, stub.callCount, 'good event still processed');
    Assert.areEqual(1, stub.lastRecords.size());
  }

  @IsTest
  static void testProcessEmptyAndNullInputAreNoOp() {
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Test.startTest();
    JiraPushDispatcher.process(null);
    JiraPushDispatcher.process(new List<Jira_Push_Request__e>());
    Test.stopTest();

    Assert.areEqual(0, stub.callCount);
  }

  @IsTest
  static void testProcessUsesNoOpFallbackWhenAdapterNotDeployed() {
    // Negative path: when JcfsApiAdapter isn't in the org, the dispatcher
    // falls back to NoOpJcfsApi at class-load time. By NOT overriding
    // jcfs in this test, we exercise that fallback.
    overrideConfig(accountConfig(true));
    Account a = buildAccount();

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now()
        )
      }
    );
    Test.stopTest();

    // No exception thrown = NoOpJcfsApi handled the call.
    Assert.isTrue(true, 'NoOpJcfsApi fallback executed without throwing');
  }

  @IsTest
  static void testProcessLogsApiExceptionForMalformedSourceId() {
    // Negative path: bad Id string triggers the StringException catch.
    overrideConfig(accountConfig(true));
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = 'not-a-valid-id',
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now(),
          Transaction_Id__c = 'tx-bad'
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(0, stub.callCount, 'malformed Id -> no JCFS call');
    Assert.isTrue(
      [SELECT COUNT() FROM API_Exception_Log__c] >= 1,
      'malformed Id should produce an API_Exception_Log__c row'
    );
  }

  @IsTest
  static void testProcessLogsApiExceptionWhenJcfsThrows() {
    // Negative path: JCFS-side failure is caught and logged, not propagated.
    overrideConfig(accountConfig(true));
    JiraPushDispatcher.jcfs = new ThrowingJcfsApi();

    Account a = buildAccount();

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now()
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM API_Exception_Log__c],
      'JCFS push failure should produce an API_Exception_Log__c row'
    );
  }

  @IsTest
  static void testResolveDefaultAdapterReturnsAdapterWhenClassDeployed() {
    // Positive path for resolveDefaultAdapter: when adapterClassName
    // points at a deployed class implementing IJcfsApi, Type.forName
    // resolves it and newInstance() returns the adapter.
    JiraPushDispatcher.adapterClassName = 'JiraPushDispatcherTest.RecordingJcfs';

    Test.startTest();
    JiraPushDispatcher.IJcfsApi resolved = JiraPushDispatcher.resolveDefaultAdapter();
    Test.stopTest();

    Assert.isTrue(
      resolved instanceof RecordingJcfs,
      'Should resolve to the configured adapter class'
    );
  }

  @IsTest
  static void testProcessLogsApiExceptionWhenIdPrefixMismatchesSObject() {
    // Negative path: sot.newSObject(id) throws when id's prefix doesn't
    // match the SObjectType - drives the list-construction catch block.
    overrideConfig(accountConfig(true));
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Id caseFakeId = TestFactory.getFakeId(Case.SObjectType);

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(caseFakeId),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now()
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(0, stub.callCount, 'mismatch -> no JCFS call');
    Assert.isTrue(
      [SELECT COUNT() FROM API_Exception_Log__c] >= 1,
      'mismatch should log an API exception'
    );
  }

  @IsTest
  static void testProcessMultipleIdsForOneObjectCollapsedToOneJcfsCall() {
    overrideConfig(accountConfig(true));
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Account a1 = buildAccount();
    Account a2 = buildAccount();

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a1.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now()
        ),
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a2.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now()
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(1, stub.callCount, 'one JCFS call per SObject type');
    Assert.areEqual(2, stub.lastRecords.size(), 'both Ids passed in one call');
  }

  /**
   * @description Bulk safety: 200 events across three SObject types yields
   *              exactly three JCFS calls (one per type), each with a
   *              concretely-typed list of the right count. Asserts
   *              Limits.getQueries and Limits.getDmlStatements stay flat
   *              because the dispatcher should never SOQL or DML in the
   *              hot path (CMDT comes from the cache override; the JCFS
   *              stub captures the list).
   */
  @IsTest
  static void testDispatcherProcessesBulkPEBatchOfTwoHundredEvents() {
    JiraPushService.resetTransientState();
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>{
      'Account' => new Jira_Push_Object__mdt(
        MasterLabel = 'Account',
        DeveloperName = 'Account',
        SObject_API_Name__c = 'Account',
        Active__c = true
      ),
      'Opportunity' => new Jira_Push_Object__mdt(
        MasterLabel = 'Opportunity',
        DeveloperName = 'Opportunity',
        SObject_API_Name__c = 'Opportunity',
        Active__c = true
      ),
      'Case' => new Jira_Push_Object__mdt(
        MasterLabel = 'Case',
        DeveloperName = 'Case',
        SObject_API_Name__c = 'Case',
        Active__c = true
      )
    };
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    List<Account> accts = JiraPushTestFixtures.bulkAccounts(80);
    List<Opportunity> opps = JiraPushTestFixtures.bulkOpportunities(
      80,
      'Prospecting'
    );
    List<Case> cases = JiraPushTestFixtures.bulkCases(40);

    List<Jira_Push_Request__e> events = new List<Jira_Push_Request__e>();
    Datetime ts = Datetime.newInstance(2026, 5, 12, 12, 0, 0);
    for (Account a : accts) {
      events.add(
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = ts,
          Transaction_Id__c = 'bulk'
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
          Transaction_Id__c = 'bulk'
        )
      );
    }
    for (Case c : cases) {
      events.add(
        new Jira_Push_Request__e(
          Source_Object__c = 'Case',
          Source_Id__c = String.valueOf(c.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = ts,
          Transaction_Id__c = 'bulk'
        )
      );
    }
    Assert.areEqual(
      200,
      events.size(),
      'PE batch is exactly 200 events spanning three SObjects'
    );

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    Integer dmlBefore = Limits.getDmlStatements();
    JiraPushDispatcher.process(events);
    Integer queriesAfter = Limits.getQueries();
    Integer dmlAfter = Limits.getDmlStatements();
    Test.stopTest();

    Assert.areEqual(
      3,
      stub.callCount,
      'Exactly one JCFS call per SObject type regardless of record count'
    );
    Assert.areEqual(
      queriesBefore,
      queriesAfter,
      'Dispatcher hot path must not run any SOQL with the CMDT cache warm'
    );
    Assert.areEqual(
      dmlBefore,
      dmlAfter,
      'Dispatcher hot path must not DML (no exceptions expected, none logged)'
    );
  }

  /**
   * @description Re-fire dedup: two events with identical Source_Object__c
   *              and Source_Id__c in the same batch must yield one record
   *              in the typed list passed to JCFS (Set<Id> semantics).
   *              Locks the Set-based accumulation at lines 112-115.
   */
  @IsTest
  static void testDispatcherHandlesReFireWithinSamePEBatch() {
    overrideConfig(accountConfig(true));
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Account a = buildAccount();

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now()
        ),
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now()
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(1, stub.callCount, 'one JCFS call');
    Assert.areEqual(
      1,
      stub.lastRecords.size(),
      'Duplicate Id in batch deduped by Set<Id> accumulation'
    );
  }

  /**
   * @description Regression lock for the NoOpJcfsApi fallback. Verifies:
   *               1. resolveDefaultAdapter() returns a non-null IJcfsApi
   *                  when the adapter class doesn't exist (NoOp lands).
   *               2. process() completes without throwing.
   *               3. The NoOp's pushUpdates returns one JcfsPushResult per
   *                  input record with success=false and the diagnostic
   *                  message - so support reports show Jira-not-called.
   *              We invoke pushUpdates directly on the resolved IJcfsApi
   *              to assert the result shape, rather than going through
   *              the full dispatcher whose per-record logging path has
   *              environment-dependent FLS behavior (see Logger DMLManager
   *              regression in the handback).
   *              Complements testProcessUsesNoOpFallbackWhenAdapterNotDeployed.
   */
  @IsTest
  static void testNoOpFallbackBehaviorRegressionLock() {
    overrideConfig(accountConfig(true));
    JiraPushDispatcher.adapterClassName = 'DoesNotExist__NoOpForceFallback';
    JiraPushDispatcher.IJcfsApi resolved = JiraPushDispatcher.resolveDefaultAdapter();
    Assert.areNotEqual(
      null,
      resolved,
      'resolveDefaultAdapter must always return a non-null IJcfsApi'
    );

    Account a1 = buildAccount();
    Account a2 = buildAccount();
    JiraPushDispatcher.jcfs = resolved;

    Test.startTest();
    // Direct call to assert result shape:
    List<JiraPushDispatcher.JcfsPushResult> results = resolved.pushUpdates(
      new List<Account>{ a1, a2 }
    );
    // Dispatcher round-trip to assert no-throw under the full pipeline:
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a1.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now(),
          Transaction_Id__c = 'noop-1'
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      results.size(),
      'NoOp must return one JcfsPushResult per input record'
    );
    for (JiraPushDispatcher.JcfsPushResult r : results) {
      Assert.areEqual(false, r.success, 'NoOp results are always failures');
      Assert.isTrue(
        r.errorMessage != null &&
          r.errorMessage.contains('JcfsApiAdapter not deployed'),
        'NoOp errorMessage must clearly identify the scratch-org fallback state'
      );
    }
  }

  /**
   * @description M3 typed-exception coverage. Malformed Source_Id__c now
   *              raises JiraPushDispatcherException internally and is caught
   *              + logged by the dispatcher (process() does not propagate
   *              the throw to the caller). The Exception_Type__c column on
   *              the log row must read JiraPushDispatcherException so support
   *              can filter the failure class quickly.
   */
  @IsTest
  static void testProcessMalformedSourceIdLogsTypedException() {
    overrideConfig(accountConfig(true));
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = 'definitely-not-an-id',
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now(),
          Transaction_Id__c = 'm3-typed'
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(0, stub.callCount, 'malformed Id never reaches JCFS');
    List<API_Exception_Log__c> rows = [
      SELECT Exception_Type__c, Message__c
      FROM API_Exception_Log__c
    ];
    Assert.areEqual(1, rows.size(), 'one API_Exception_Log__c row per bad Id');
    Assert.isTrue(
      rows[0].Exception_Type__c != null &&
        rows[0]
          .Exception_Type__c.endsWith('JiraPushDispatcherException'),
      'Typed exception must be captured in Exception_Type__c; got: ' +
        rows[0].Exception_Type__c
    );
    Assert.isTrue(
      rows[0].Message__c.contains('definitely-not-an-id'),
      'Message must include the offending Source_Id for triage'
    );
  }

  /**
   * @description M2 per-Id resilience: 199 valid Ids and 1 mismatched-
   *              prefix Id in the same batch. The bad Id logs and is
   *              skipped; the other 199 still reach JCFS in one call.
   *              Locks the per-Id try/catch (was an outer-loop catch
   *              before M2, which sank the whole batch).
   */
  @IsTest
  static void testProcessOneBadIdInBatchStillShipsTheRest() {
    overrideConfig(accountConfig(true));
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    List<Account> goodAccts = JiraPushTestFixtures.bulkAccounts(199);
    Id badIdForAccount = TestFactory.getFakeId(Case.SObjectType); // wrong prefix

    List<Jira_Push_Request__e> events = new List<Jira_Push_Request__e>();
    for (Account a : goodAccts) {
      events.add(
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now(),
          Transaction_Id__c = 'm2'
        )
      );
    }
    events.add(
      new Jira_Push_Request__e(
        Source_Object__c = 'Account',
        Source_Id__c = String.valueOf(badIdForAccount),
        Change_Type__c = 'Update',
        Event_Timestamp__c = Datetime.now(),
        Transaction_Id__c = 'm2'
      )
    );

    Test.startTest();
    JiraPushDispatcher.process(events);
    Test.stopTest();

    Assert.areEqual(
      1,
      stub.callCount,
      'One JCFS call despite the bad Id - the 199 good Ids still ship'
    );
    Assert.areEqual(
      199,
      stub.lastRecords.size(),
      'Bad Id skipped, 199 valid records sent to JCFS'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM API_Exception_Log__c],
      'Bad Id produced exactly one API_Exception_Log__c row'
    );
  }

  /**
   * @description H3 per-record failure logging. RecordingJcfs lets a test
   *              pre-load simulatedResults with mixed success/failure; the
   *              dispatcher should log Logger.info for successes (no
   *              API_Exception_Log__c row) and Logger.logApiException for
   *              failures (one row per failed record).
   */
  @IsTest
  static void testProcessLogsPerRecordJcfsFailures() {
    overrideConfig(accountConfig(true));
    RecordingJcfs stub = new RecordingJcfs();
    Account a1 = buildAccount();
    Account a2 = buildAccount();
    Account a3 = buildAccount();
    stub.simulatedResults = new List<JiraPushDispatcher.JcfsPushResult>{
      new JiraPushDispatcher.JcfsPushResult(a1.Id, true, null, 'CSI-1'),
      new JiraPushDispatcher.JcfsPushResult(a2.Id, false, 'rate limited', null),
      new JiraPushDispatcher.JcfsPushResult(a3.Id, false, 'invalid project', null)
    };
    JiraPushDispatcher.jcfs = stub;

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a1.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now(),
          Transaction_Id__c = 'per-rec'
        ),
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a2.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now(),
          Transaction_Id__c = 'per-rec'
        ),
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a3.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now(),
          Transaction_Id__c = 'per-rec'
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      [SELECT COUNT() FROM API_Exception_Log__c],
      'Two failed records -> two API_Exception_Log__c rows; success is debug-only'
    );
  }

  /**
   * @description Covers the no-arg JcfsPushResult() constructor (line 45).
   */
  @IsTest
  static void testJcfsPushResultNoArgConstructorIsUsable() {
    Test.startTest();
    JiraPushDispatcher.JcfsPushResult r = new JiraPushDispatcher.JcfsPushResult();
    r.recordId = TestFactory.getFakeId(Account.SObjectType);
    r.success = true;
    r.jiraIssueKey = 'JIRA-1';
    Test.stopTest();

    Assert.areEqual(true, r.success, 'No-arg ctor + setters work');
    Assert.areEqual('JIRA-1', r.jiraIssueKey, 'jiraIssueKey settable');
    Assert.isNotNull(r.recordId, 'recordId settable');
  }

  /**
   * @description Covers the @TestVisible private muteForTest() seam
   *              (lines 106-109) plus the NoOp's null-records guard
   *              (line 134-135).
   */
  @IsTest
  static void testMuteForTestSwapsInNoOpStubAndHandlesNullRecords() {
    Test.startTest();
    JiraPushDispatcher.IJcfsApi stub = JiraPushDispatcher.muteForTest();
    List<JiraPushDispatcher.JcfsPushResult> nullResults = stub.pushUpdates(
      null
    );
    Test.stopTest();

    Assert.isNotNull(stub, 'muteForTest returns the wired stub');
    Assert.areEqual(
      0,
      nullResults.size(),
      'NoOp returns empty list when input is null (guard at line 134-135)'
    );
  }

  /**
   * @description Adapter returns null - the dispatcher must early-return
   *              without throwing or writing per-record exception logs.
   *              Covers line 309-311.
   */
  @IsTest
  static void testProcessHandlesNullResultsListFromAdapterGracefully() {
    NullReturningJcfs stub = new NullReturningJcfs();
    JiraPushDispatcher.jcfs = stub;

    Account a = new Account(Name = 'Null Results Account');
    insert a;

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now(),
          Transaction_Id__c = 'null-results'
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      stub.callCount,
      'Adapter invoked once before returning null'
    );
  }

  /**
   * @description Adapter returns a list with a null element. Dispatcher's
   *              per-result loop must `continue` past the null. Covers
   *              line 313-314.
   */
  @IsTest
  static void testProcessSkipsNullEntriesInResultsList() {
    NullEntryJcfs stub = new NullEntryJcfs();
    JiraPushDispatcher.jcfs = stub;

    Account a = new Account(Name = 'Null Entry Account');
    insert a;

    Test.startTest();
    JiraPushDispatcher.process(
      new List<Jira_Push_Request__e>{
        new Jira_Push_Request__e(
          Source_Object__c = 'Account',
          Source_Id__c = String.valueOf(a.Id),
          Change_Type__c = 'Update',
          Event_Timestamp__c = Datetime.now(),
          Transaction_Id__c = 'null-entry'
        )
      }
    );
    Test.stopTest();

    Assert.areEqual(1, stub.callCount, 'Adapter invoked');
  }

  /** Stub that returns null from pushUpdates - drives null-results early-return. */
  public class NullReturningJcfs implements JiraPushDispatcher.IJcfsApi {
    public Integer callCount = 0;
    public List<JiraPushDispatcher.JcfsPushResult> pushUpdates(
      List<SObject> records
    ) {
      callCount++;
      return null;
    }
  }

  /** Stub that returns a list with one null element - drives null-entry continue. */
  public class NullEntryJcfs implements JiraPushDispatcher.IJcfsApi {
    public Integer callCount = 0;
    public List<JiraPushDispatcher.JcfsPushResult> pushUpdates(
      List<SObject> records
    ) {
      callCount++;
      return new List<JiraPushDispatcher.JcfsPushResult>{ null };
    }
  }
}
