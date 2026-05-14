/**
 * @description Tests for `EngagementTouchArchivalBatch`. The archival window
 *              is pinned to 30 days via the static settings override so the
 *              cutoff is deterministic regardless of the org default.
 * @group Engagement Attribution
 * @see EngagementTouchArchivalBatch
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementTouchArchivalBatchTest {
  private static final String PERMISSION_SET = 'Engagement_Attribution_User';
  private static final String USER_LAST_NAME = 'ArchivalBatchTest';
  private static final Integer WINDOW_DAYS = 30;

  /** @description Provisions a permission-set-assigned test user. */
  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    provisionTestUser();
  }

  /**
   * @description A touch 60 days old (older than the 30-day window) must be
   *              archived: `Is_Active__c = false`, `Archived_At__c` populated.
   */
  @IsTest
  static void executeArchivesOldTouches() {
    System.runAs(getTestUser()) {
      overrideWindowDays(WINDOW_DAYS);
      Id touchId = seedTouch(60, true, null);

      Test.startTest();
      Database.executeBatch(new EngagementTouchArchivalBatch(), 200);
      Test.stopTest();

      Engagement_Touch__c reloaded = queryTouch(touchId);
      Assert.areEqual(
        false,
        reloaded.Is_Active__c,
        'Expected an aged touch to be marked inactive.'
      );
      Assert.isNotNull(
        reloaded.Archived_At__c,
        'Expected Archived_At__c to be populated on archived touch.'
      );
    }
  }

  /**
   * @description A 5-day-old touch is well inside the active window and must
   *              be left untouched.
   */
  @IsTest
  static void executeSkipsRecentTouches() {
    System.runAs(getTestUser()) {
      overrideWindowDays(WINDOW_DAYS);
      Id touchId = seedTouch(5, true, null);

      Test.startTest();
      Database.executeBatch(new EngagementTouchArchivalBatch(), 200);
      Test.stopTest();

      Engagement_Touch__c reloaded = queryTouch(touchId);
      Assert.areEqual(
        true,
        reloaded.Is_Active__c,
        'Expected a recent touch to remain active.'
      );
      Assert.isNull(
        reloaded.Archived_At__c,
        'Expected Archived_At__c to remain null on a recent touch.'
      );
    }
  }

  /**
   * @description Already-archived touches are filtered out at `start()` and
   *              must not have their `Archived_At__c` re-stamped.
   */
  @IsTest
  static void executeSkipsAlreadyArchivedTouches() {
    System.runAs(getTestUser()) {
      overrideWindowDays(WINDOW_DAYS);
      DateTime original = DateTime.now().addDays(-10);
      Id touchId = seedTouch(120, false, original);

      Test.startTest();
      Database.executeBatch(new EngagementTouchArchivalBatch(), 200);
      Test.stopTest();

      Engagement_Touch__c reloaded = queryTouch(touchId);
      Assert.areEqual(
        false,
        reloaded.Is_Active__c,
        'Expected pre-archived touch to stay inactive.'
      );
      Assert.areEqual(
        original,
        reloaded.Archived_At__c,
        'Expected the original Archived_At__c to be preserved.'
      );
    }
  }

  // ─── Setup helpers ─────────────────────────────────────────────────────────

  private static void overrideWindowDays(Integer days) {
    EngagementTouchArchivalBatch.settingsOverride = new Engagement_Settings__c(
      Active_Window_Days__c = days
    );
  }

  private static Id seedTouch(
    Integer ageDays,
    Boolean isActive,
    DateTime archivedAt
  ) {
    Account a = new Account(
      Name = 'UHC Archive Test ' + Crypto.getRandomInteger()
    );
    Database.insert(a, AccessLevel.SYSTEM_MODE);

    Contact c = new Contact(
      FirstName = 'Archive',
      LastName = 'Tester',
      Email = 'archive' + Crypto.getRandomInteger() + '@test.example.com',
      AccountId = a.Id
    );
    Database.insert(c, AccessLevel.SYSTEM_MODE);

    Touch_Topic__c topic = new Touch_Topic__c(
      Topic_Name__c = 'Network Management',
      External_Code__c = 'TOPIC_ARCHIVE_' + Crypto.getRandomInteger()
    );
    Database.insert(topic, AccessLevel.SYSTEM_MODE);

    Engagement_Touch__c t = new Engagement_Touch__c(
      External_Id__c = 'EXT-ARCH-' + Crypto.getRandomInteger(),
      Source_System__c = 'HubSpot',
      Email_At_Touch__c = c.Email,
      Contact__c = c.Id,
      Account__c = a.Id,
      Topic__c = topic.Id,
      Occurred_At__c = DateTime.now().addDays(-ageDays),
      Is_Active__c = isActive,
      Archived_At__c = archivedAt,
      Resolution_Status__c = 'Resolved',
      Processing_Status__c = 'Processed',
      Persona__c = 'Executive',
      Intent_Level__c = 'Medium',
      Touch_Type__c = 'Download'
    );
    Database.insert(t, AccessLevel.SYSTEM_MODE);
    return t.Id;
  }

  private static Engagement_Touch__c queryTouch(Id touchId) {
    return [
      SELECT Id, Is_Active__c, Archived_At__c, Occurred_At__c
      FROM Engagement_Touch__c
      WHERE Id = :touchId
      LIMIT 1
    ];
  }

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
      Email = 'archivalbatch@test.example.com',
      Username = 'archivalbatch' +
        Crypto.getRandomInteger() +
        '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'arcbt',
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
