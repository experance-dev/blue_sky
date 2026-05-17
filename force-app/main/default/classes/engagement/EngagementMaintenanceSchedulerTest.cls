/**
 * @description Smoke test for `EngagementMaintenanceScheduler`. Confirms the
 *              scheduler queues both maintenance batches without throwing.
 *              Inside `Test.startTest`/`Test.stopTest`, queued batches run
 *              synchronously, so this test also exercises both batch bodies
 *              against an empty dataset.
 * @group Engagement Attribution
 * @see EngagementMaintenanceScheduler
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementMaintenanceSchedulerTest {
  private static final String PERMISSION_SET = 'Additional_Permissions_Marketing_Influence_Integration';
  private static final String USER_LAST_NAME = 'MaintSchedTest';

  /** @description Provisions a permission-set-assigned test user. */
  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    provisionTestUser();
  }

  /**
   * @description Invoking `execute()` must not throw and must enqueue both
   *              maintenance batches. Asserts on AsyncApexJob count after
   *              `Test.stopTest()` so the batches' synchronous finish is
   *              already recorded.
   */
  @IsTest
  static void executeKicksOffBoth() {
    System.runAs(getTestUser()) {
      EngagementMaintenanceScheduler scheduler = new EngagementMaintenanceScheduler();

      Test.startTest();
      scheduler.execute(null);
      Test.stopTest();

      Integer batchJobCount = [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE
          JobType = 'BatchApex'
          AND ApexClass.Name IN (
            'EngagementSignalDecayBatch',
            'EngagementTouchArchivalBatch'
          )
      ];
      Assert.areEqual(
        2,
        batchJobCount,
        'Expected exactly two batch jobs (decay + archival) to be enqueued.'
      );
    }
  }

  // ─── Setup helpers ─────────────────────────────────────────────────────────

  private static User provisionTestUser() {
    Profile standard = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    User u = new User(
      ProfileId = standard.Id,
      LastName = USER_LAST_NAME,
      Email = 'maintsched@test.example.com',
      Username = 'maintsched' + Crypto.getRandomInteger() + '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'mntsc',
      TimeZoneSidKey = 'America/Los_Angeles',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US'
    );
    Database.insert(u, AccessLevel.SYSTEM_MODE);

    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :PERMISSION_SET
      LIMIT 1
    ];
    Database.insert(
      new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id),
      AccessLevel.SYSTEM_MODE
    );
    return u;
  }

  private static User getTestUser() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :USER_LAST_NAME
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }
}
