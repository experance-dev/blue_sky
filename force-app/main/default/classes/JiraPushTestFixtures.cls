/**
 * @description Shared test-only fixtures for the CSI-7162 Jira push framework.
 *              Lifts the silenceFramework() / silenceDispatcher() helper that
 *              previously lived (drift-prone) in four separate test classes
 *              into a single source of truth. Returns the RecordingJcfs stub
 *              that callers will assert against so tests stay terse.
 *
 *              Cross-class fixtures intentionally consolidated here:
 *              - silenceFramework(sobjectName) ............. wires the
 *                  RecordingJcfs stub + a single-SObject CMDT override.
 *              - silenceFramework(sobjectNames) ............ wires a stub
 *                  plus a CMDT override covering many SObjects (bulk tests
 *                  that span Account + Opportunity + Case need this).
 *              - activeConfig(sobjectName) ................. builds an
 *                  Active__c = true Jira_Push_Object__mdt row in memory.
 *              - bulkOpportunities(count, stage) ........... in-memory list
 *                  of fake-Id Opportunities for service-layer bulk tests.
 *              - bulkAccounts(count) ....................... same for Account.
 *              - publishedKey(sObj) ........................ the recursion-
 *                  guard key, exposed so tests don't string-format their own.
 *
 *              All methods are deterministic - no Datetime.now(), no
 *              random ids beyond TestFactory.getFakeId's monotonic counter.
 *
 *              Coverage: this class is exercised by every test that calls
 *              its helpers. It contains no production logic.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author      | Description                            |
 * |------------|----------|-------------|----------------------------------------|
 * | 2026-05-12 | CSI-7162 | Pippa Codey | Lift duplicated silenceFramework into  |
 * |            |          |             | one helper; add bulk-fixture builders. |
 */
@IsTest
public class JiraPushTestFixtures {
  /**
   * @description Silences the dispatcher (so PE delivery during stopTest
   *              hits a recording stub, not real JCFS) and overrides the
   *              CMDT cache to mark the named SObject as Active.
   * @param sobjectName API name of the SObject under test.
   * @return The RecordingJcfs stub now wired into JiraPushDispatcher.
   */
  public static JiraPushDispatcherTest.RecordingJcfs silenceFramework(
    String sobjectName
  ) {
    return silenceFramework(new List<String>{ sobjectName });
  }

  /**
   * @description Multi-SObject variant. Tests that publish events for more
   *              than one SObject in a single batch (the dispatcher bulk
   *              test, the trigger-pipeline bulk test) need every relevant
   *              SObject marked Active in the CMDT override.
   * @param sobjectNames API names to mark active.
   * @return The shared RecordingJcfs stub.
   */
  public static JiraPushDispatcherTest.RecordingJcfs silenceFramework(
    List<String> sobjectNames
  ) {
    JiraPushService.resetTransientState();
    JiraPushDispatcherTest.RecordingJcfs stub = new JiraPushDispatcherTest.RecordingJcfs();
    JiraPushDispatcher.jcfs = stub;
    Map<String, Jira_Push_Object__mdt> overrideMap = new Map<String, Jira_Push_Object__mdt>();
    for (String name : sobjectNames) {
      overrideMap.put(name, activeConfig(name));
    }
    JiraPushService.configCacheOverride = overrideMap;
    return stub;
  }

  /**
   * @description Builds an Active CMDT row in memory. Tests that need an
   *              inactive row can construct one directly - this helper is
   *              for the common active-path case.
   */
  public static Jira_Push_Object__mdt activeConfig(String sobjectName) {
    return new Jira_Push_Object__mdt(
      MasterLabel = sobjectName,
      DeveloperName = sobjectName,
      SObject_API_Name__c = sobjectName,
      Active__c = true
    );
  }

  /**
   * @description Builds N Opportunities in memory, each with a fake Id and
   *              the supplied StageName. No DML, no validation-rule risk.
   *              The fake-Id sequence is monotonic so .Id values are stable.
   */
  public static List<Opportunity> bulkOpportunities(
    Integer count,
    String stage
  ) {
    List<Opportunity> opps = new List<Opportunity>();
    for (Integer i = 0; i < count; i++) {
      opps.add(
        new Opportunity(
          Id = TestFactory.getFakeId(Opportunity.SObjectType),
          Name = 'Bulk ' + i,
          StageName = stage,
          CloseDate = Date.today().addDays(30)
        )
      );
    }
    return opps;
  }

  /**
   * @description Builds N Accounts in memory with fake Ids. Used by the
   *              dispatcher bulk test that needs a mix of SObjects.
   */
  public static List<Account> bulkAccounts(Integer count) {
    List<Account> accts = new List<Account>();
    for (Integer i = 0; i < count; i++) {
      accts.add(
        new Account(
          Id = TestFactory.getFakeId(Account.SObjectType),
          Name = 'Bulk Acct ' + i
        )
      );
    }
    return accts;
  }

  /**
   * @description Builds N Cases in memory with fake Ids. Used by the
   *              dispatcher bulk test.
   */
  public static List<Case> bulkCases(Integer count) {
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < count; i++) {
      cases.add(new Case(Id = TestFactory.getFakeId(Case.SObjectType)));
    }
    return cases;
  }

  /**
   * @description Returns the recursion-guard key the service uses internally
   *              (SObjectName + ':' + Id). Tests assert on this string a lot;
   *              centralizing the format keeps tests in sync if the format
   *              ever changes.
   */
  public static String publishedKey(SObject rec) {
    return rec.getSObjectType().getDescribe().getName() + ':' + rec.Id;
  }
}
