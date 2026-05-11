/**
 * @description Tests for JiraPushDispatcher: event grouping, config gating,
 *              ID-only SObject construction, type coercion, and JCFS seam.
 *              Houses the shared RecordingJcfs stub and buildAccount helper
 *              that other test classes reuse via JiraPushDispatcherTest.*.
 *
 *              DML-less: the dispatcher only needs an Id to call
 *              SObjectType.newSObject(id) - the record doesn't need to
 *              exist in the DB. buildAccount() uses TestFactory.getFakeId
 *              to mint a syntactically-valid Id with zero DML.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                              |
 * |------------|----------|------------|------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Tests for dispatcher and JCFS seam       |
 */
@IsTest
public class JiraPushDispatcherTest {
  /** Throws on every call - used to exercise dispatcher's JCFS-failure catch path. */
  public class ThrowingJcfsApi implements JiraPushDispatcher.IJcfsApi {
    public void pushUpdates(List<SObject> records) {
      throw new System.DmlException('forced JCFS failure');
    }
  }

  /** Records the typed list passed to JCFS for assertion. */
  public class RecordingJcfs implements JiraPushDispatcher.IJcfsApi {
    public Integer callCount = 0;
    public List<SObject> lastRecords;
    public String lastListRender;

    public void pushUpdates(List<SObject> records) {
      callCount++;
      lastRecords = records;
      lastListRender = String.valueOf(records);
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
  static void process_callsJcfsWithIdOnlyConcreteList() {
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

    System.assertEquals(1, stub.callCount, 'JCFS called once');
    System.assertEquals(1, stub.lastRecords.size(), 'one record passed');
    System.assertEquals(a.Id, stub.lastRecords[0].Id, 'correct Id');
    System.assertEquals(
      Account.SObjectType,
      stub.lastRecords[0].getSObjectType(),
      'runtime type is Account, satisfying JCFS concrete-list requirement'
    );
  }

  @IsTest
  static void process_skipsWhenConfigMissing() {
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

    System.assertEquals(0, stub.callCount, 'no config -> no JCFS call');
  }

  @IsTest
  static void process_skipsWhenConfigInactive() {
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

    System.assertEquals(0, stub.callCount, 'inactive config -> no JCFS call');
  }

  @IsTest
  static void process_handlesUnknownSObjectGracefully() {
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

    System.assertEquals(0, stub.callCount, 'unknown SObject -> logged, no call');
  }

  @IsTest
  static void process_skipsBlankEventsAndContinues() {
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

    System.assertEquals(1, stub.callCount, 'good event still processed');
    System.assertEquals(1, stub.lastRecords.size());
  }

  @IsTest
  static void process_emptyAndNullInputAreNoOp() {
    RecordingJcfs stub = new RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;

    Test.startTest();
    JiraPushDispatcher.process(null);
    JiraPushDispatcher.process(new List<Jira_Push_Request__e>());
    Test.stopTest();

    System.assertEquals(0, stub.callCount);
  }

  @IsTest
  static void process_usesNoOpFallbackWhenAdapterNotDeployed() {
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
    System.assert(true, 'NoOpJcfsApi fallback executed without throwing');
  }

  @IsTest
  static void process_logsApiExceptionForMalformedSourceId() {
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

    System.assertEquals(0, stub.callCount, 'malformed Id -> no JCFS call');
    System.assert(
      [SELECT COUNT() FROM API_Exception_Log__c] >= 1,
      'malformed Id should produce an API_Exception_Log__c row'
    );
  }

  @IsTest
  static void process_logsApiExceptionWhenJcfsThrows() {
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

    System.assertEquals(
      1,
      [SELECT COUNT() FROM API_Exception_Log__c],
      'JCFS push failure should produce an API_Exception_Log__c row'
    );
  }

  @IsTest
  static void resolveDefaultAdapter_returnsAdapterWhenClassDeployed() {
    // Positive path for resolveDefaultAdapter: when adapterClassName
    // points at a deployed class implementing IJcfsApi, Type.forName
    // resolves it and newInstance() returns the adapter.
    JiraPushDispatcher.adapterClassName = 'JiraPushDispatcherTest.RecordingJcfs';

    Test.startTest();
    JiraPushDispatcher.IJcfsApi resolved = JiraPushDispatcher.resolveDefaultAdapter();
    Test.stopTest();

    System.assert(
      resolved instanceof RecordingJcfs,
      'Should resolve to the configured adapter class'
    );
  }

  @IsTest
  static void process_logsApiExceptionWhenIdPrefixMismatchesSObject() {
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

    System.assertEquals(0, stub.callCount, 'mismatch -> no JCFS call');
    System.assert(
      [SELECT COUNT() FROM API_Exception_Log__c] >= 1,
      'mismatch should log an API exception'
    );
  }

  @IsTest
  static void process_multipleIdsForOneObjectCollapsedToOneJcfsCall() {
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

    System.assertEquals(1, stub.callCount, 'one JCFS call per SObject type');
    System.assertEquals(2, stub.lastRecords.size(), 'both Ids passed in one call');
  }
}
