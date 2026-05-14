/**
 * @description Tests that `EngagementTouchTrigger` fires the routing pipeline
 *              for the two events that matter: inserts arriving already-
 *              resolved, and updates that transition into Resolved.
 * @group Engagement Attribution
 * @see EngagementTouchTriggerHandler
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementTouchTriggerHandlerTest {
  private static final String PERMISSION_SET = 'Engagement_Attribution_User';
  private static final String USER_LAST_NAME = 'TouchTriggerTest';

  /**
   * @description Seeds the world with the (Account, Contact, Topic, open
   *              Opportunity) tuple needed for any routing rule to fire. The
   *              touch itself is created per-test to control timing.
   */
  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    User u = provisionTestUser();
    System.runAs(u) {
      seedWorld();
    }
  }

  /**
   * @description A fresh insert with Resolution_Status='Resolved' should
   *              produce at least one signal — the priority-50 Account default
   *              rule will fire on the matching account + topic.
   */
  @IsTest
  static void insertResolvedTouchCreatesSignal() {
    System.runAs(getTestUser()) {
      Engagement_Touch__c t = buildTouch('EXT-INS-1', 'Resolved');

      Test.startTest();
      Database.insert(t, AccessLevel.SYSTEM_MODE);
      Test.stopTest();

      Integer count = [
        SELECT COUNT()
        FROM Opportunity_Engagement_Signal__c
        WHERE Engagement_Touch__c = :t.Id
      ];
      Assert.isTrue(
        count >= 1,
        'Expected at least one signal from an after-insert resolved touch; found ' +
        count
      );
    }
  }

  /**
   * @description Inserting with Pending then updating to Resolved exercises
   *              the afterUpdate transition path. The first insert must NOT
   *              create a signal; the update must.
   */
  @IsTest
  static void updateToResolvedTriggersRouting() {
    System.runAs(getTestUser()) {
      Engagement_Touch__c t = buildTouch('EXT-UPD-1', 'Pending');
      Database.insert(t, AccessLevel.SYSTEM_MODE);

      Integer beforeCount = [
        SELECT COUNT()
        FROM Opportunity_Engagement_Signal__c
        WHERE Engagement_Touch__c = :t.Id
      ];
      Assert.areEqual(
        0,
        beforeCount,
        'Expected no signals while touch is still Pending.'
      );

      t.Resolution_Status__c = 'Resolved';

      Test.startTest();
      Database.update(t, AccessLevel.SYSTEM_MODE);
      Test.stopTest();

      Integer afterCount = [
        SELECT COUNT()
        FROM Opportunity_Engagement_Signal__c
        WHERE Engagement_Touch__c = :t.Id
      ];
      Assert.isTrue(
        afterCount >= 1,
        'Expected at least one signal once the touch flips to Resolved; found ' +
        afterCount
      );
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  private static Engagement_Touch__c buildTouch(
    String externalId,
    String resolutionStatus
  ) {
    Account a = [
      SELECT Id
      FROM Account
      WHERE Name = 'UHC Trigger Test'
      LIMIT 1
    ];
    Contact c = [
      SELECT Id
      FROM Contact
      WHERE Email = 'trigger@test.example.com'
      LIMIT 1
    ];
    Touch_Topic__c topic = [
      SELECT Id
      FROM Touch_Topic__c
      WHERE External_Code__c = 'TOPIC_TRIGGER_TEST'
      LIMIT 1
    ];
    return new Engagement_Touch__c(
      External_Id__c = externalId,
      Source_System__c = 'HubSpot',
      Email_At_Touch__c = 'trigger@test.example.com',
      Contact__c = c.Id,
      Account__c = a.Id,
      Topic__c = topic.Id,
      Occurred_At__c = Datetime.now().addMinutes(-5),
      Is_Active__c = true,
      Resolution_Status__c = resolutionStatus,
      Processing_Status__c = 'Processed',
      Persona__c = 'Executive',
      Intent_Level__c = 'Medium',
      Touch_Type__c = 'Download'
    );
  }

  private static void seedWorld() {
    Account a = new Account(Name = 'UHC Trigger Test');
    Database.insert(a, AccessLevel.SYSTEM_MODE);

    Contact c = new Contact(
      FirstName = 'Trigger',
      LastName = 'Tester',
      Email = 'trigger@test.example.com',
      AccountId = a.Id
    );
    Database.insert(c, AccessLevel.SYSTEM_MODE);

    Touch_Topic__c topic = new Touch_Topic__c(
      Topic_Name__c = 'Network Management',
      External_Code__c = 'TOPIC_TRIGGER_TEST'
    );
    Database.insert(topic, AccessLevel.SYSTEM_MODE);

    Opportunity opp = new Opportunity(
      Name = 'Trigger Test Opp',
      AccountId = a.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      Touch_Topic__c = topic.Id
    );
    Database.insert(opp, AccessLevel.SYSTEM_MODE);
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
      Email = 'touchtrigger@test.example.com',
      Username = 'touchtrigger' +
        Crypto.getRandomInteger() +
        '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'tchtr',
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
