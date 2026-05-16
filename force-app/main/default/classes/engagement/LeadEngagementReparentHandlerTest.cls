/**
 * @description Tests for the Lead-conversion reparenting trigger handler.
 *              Each scenario inserts a Lead + N `Engagement_Touch__c` rows
 *              pointing at that Lead, exercises `Database.convertLead`, then
 *              re-queries the touches to confirm the lookup swap was applied.
 *              The Salesforce platform fires `LeadTrigger` automatically as
 *              part of conversion, so tests do not invoke the handler directly.
 * @group Engagement Attribution
 * @see LeadEngagementReparentHandler
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class LeadEngagementReparentHandlerTest {
  private static final String PERMISSION_SET = 'Additional_Permissions_Marketing_Influence_Integration';
  private static final String USER_LAST_NAME = 'LeadReparentTest';
  private static final String CONVERTED_STATUS_FALLBACK = 'Closed - Converted';

  /**
   * @description Provisions a test user with the engagement permission set
   *              plus permission to modify Leads. No seed world is created —
   *              each test method builds its own Leads/touches so the
   *              conversion data stays isolated per-method.
   */
  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    provisionTestUser();
  }

  /**
   * @description Converting a Lead with three touches in flight reparents
   *              every touch to the converted Contact + Account in one DML.
   *              `Lead__c` is nulled out on all three.
   */
  @IsTest
  static void convertingLeadReparentsTouchesToContactAndAccount() {
    System.runAs(getTestUser()) {
      Lead l = newLead(
        'Pat',
        'Prospect',
        'Vendor Co',
        'pat@vendor.example.com'
      );
      Database.insert(l, AccessLevel.SYSTEM_MODE);

      List<Engagement_Touch__c> seeded = new List<Engagement_Touch__c>();
      for (Integer i = 0; i < 3; i++) {
        seeded.add(newTouch(l.Id, 'EXT-CONV-' + i));
      }
      Database.insert(seeded, AccessLevel.SYSTEM_MODE);

      Test.startTest();
      Database.LeadConvertResult lcr = convertLead(l.Id);
      Test.stopTest();

      Assert.isTrue(
        lcr.isSuccess(),
        'Expected Lead conversion to succeed in test context.'
      );

      List<Engagement_Touch__c> after = [
        SELECT Id, Contact__c, Account__c, Lead__c
        FROM Engagement_Touch__c
        WHERE External_Id__c LIKE 'EXT-CONV-%'
      ];
      Assert.areEqual(3, after.size(), 'Expected the three seeded touches.');
      for (Engagement_Touch__c t : after) {
        Assert.areEqual(
          lcr.getContactId(),
          t.Contact__c,
          'Expected Contact__c reparented to the converted Contact.'
        );
        Assert.areEqual(
          lcr.getAccountId(),
          t.Account__c,
          'Expected Account__c reparented to the converted Account.'
        );
        Assert.isNull(t.Lead__c, 'Expected Lead__c nulled after reparenting.');
      }
    }
  }

  /**
   * @description Updating a Lead field other than `IsConverted` must NOT
   *              cause any touch to be reparented — the handler short-circuits
   *              on the false→true transition.
   */
  @IsTest
  static void nonConversionLeadUpdateDoesNotReparent() {
    System.runAs(getTestUser()) {
      Lead l = newLead(
        'Quiet',
        'Lead',
        'Stable Co',
        'quiet@vendor.example.com'
      );
      Database.insert(l, AccessLevel.SYSTEM_MODE);

      Engagement_Touch__c touch = newTouch(l.Id, 'EXT-NOOP-1');
      Database.insert(touch, AccessLevel.SYSTEM_MODE);

      Test.startTest();
      l.Title = 'Director of Stuff';
      Database.update(l, AccessLevel.SYSTEM_MODE);
      Test.stopTest();

      Engagement_Touch__c after = [
        SELECT Id, Lead__c, Contact__c, Account__c
        FROM Engagement_Touch__c
        WHERE External_Id__c = 'EXT-NOOP-1'
        LIMIT 1
      ];
      Assert.areEqual(
        l.Id,
        after.Lead__c,
        'Expected Lead__c untouched on a non-conversion update.'
      );
      Assert.isNull(
        after.Contact__c,
        'Expected Contact__c still null on a non-conversion update.'
      );
      Assert.isNull(
        after.Account__c,
        'Expected Account__c still null on a non-conversion update.'
      );
    }
  }

  /**
   * @description Bulk: two Leads with two touches each, all four touches
   *              must reparent to the correct (and different) Contact / Account
   *              in the same transaction.
   */
  @IsTest
  static void multipleLeadsConvertedInBulk() {
    System.runAs(getTestUser()) {
      Lead leadA = newLead('Anna', 'A', 'Co A', 'anna@a.example.com');
      Lead leadB = newLead('Bob', 'B', 'Co B', 'bob@b.example.com');
      Database.insert(new List<Lead>{ leadA, leadB }, AccessLevel.SYSTEM_MODE);

      List<Engagement_Touch__c> seeded = new List<Engagement_Touch__c>{
        newTouch(leadA.Id, 'EXT-A-1'),
        newTouch(leadA.Id, 'EXT-A-2'),
        newTouch(leadB.Id, 'EXT-B-1'),
        newTouch(leadB.Id, 'EXT-B-2')
      };
      Database.insert(seeded, AccessLevel.SYSTEM_MODE);

      Test.startTest();
      Database.LeadConvert lcA = buildLeadConvert(leadA.Id);
      Database.LeadConvert lcB = buildLeadConvert(leadB.Id);
      List<Database.LeadConvertResult> results = Database.convertLead(
        new List<Database.LeadConvert>{ lcA, lcB },
        true
      );
      Test.stopTest();

      Assert.areEqual(
        2,
        results.size(),
        'Expected two conversion results from the bulk call.'
      );
      Id contactA = results[0].getContactId();
      Id accountA = results[0].getAccountId();
      Id contactB = results[1].getContactId();
      Id accountB = results[1].getAccountId();

      Map<String, Engagement_Touch__c> byExtId = new Map<String, Engagement_Touch__c>();
      for (Engagement_Touch__c t : [
        SELECT Id, External_Id__c, Lead__c, Contact__c, Account__c
        FROM Engagement_Touch__c
        WHERE External_Id__c LIKE 'EXT-%'
      ]) {
        byExtId.put(t.External_Id__c, t);
      }
      Assert.areEqual(4, byExtId.size(), 'Expected all four touches loaded.');
      assertReparented(byExtId.get('EXT-A-1'), contactA, accountA);
      assertReparented(byExtId.get('EXT-A-2'), contactA, accountA);
      assertReparented(byExtId.get('EXT-B-1'), contactB, accountB);
      assertReparented(byExtId.get('EXT-B-2'), contactB, accountB);
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  private static void assertReparented(
    Engagement_Touch__c t,
    Id expectedContactId,
    Id expectedAccountId
  ) {
    Assert.isNotNull(t, 'Expected the touch to exist.');
    Assert.areEqual(
      expectedContactId,
      t.Contact__c,
      'Expected the touch reparented to the converted Contact.'
    );
    Assert.areEqual(
      expectedAccountId,
      t.Account__c,
      'Expected the touch reparented to the converted Account.'
    );
    Assert.isNull(t.Lead__c, 'Expected Lead__c nulled after reparenting.');
  }

  private static Database.LeadConvertResult convertLead(Id leadId) {
    Database.LeadConvert lc = buildLeadConvert(leadId);
    return Database.convertLead(lc, true);
  }

  private static Database.LeadConvert buildLeadConvert(Id leadId) {
    Database.LeadConvert lc = new Database.LeadConvert();
    lc.setLeadId(leadId);
    lc.setConvertedStatus(resolveConvertedStatus());
    lc.setDoNotCreateOpportunity(true);
    return lc;
  }

  private static String resolveConvertedStatus() {
    List<LeadStatus> statuses = [
      SELECT MasterLabel
      FROM LeadStatus
      WHERE IsConverted = TRUE
      LIMIT 1
    ];
    return statuses.isEmpty()
      ? CONVERTED_STATUS_FALLBACK
      : statuses[0].MasterLabel;
  }

  private static Lead newLead(
    String first,
    String last,
    String company,
    String email
  ) {
    return new Lead(
      FirstName = first,
      LastName = last,
      Company = company,
      Email = email
    );
  }

  private static Engagement_Touch__c newTouch(Id leadId, String externalId) {
    return new Engagement_Touch__c(
      External_Id__c = externalId,
      Source_System__c = 'HubSpot',
      Email_At_Touch__c = 'reparent@test.example.com',
      Lead__c = leadId,
      Occurred_At__c = Datetime.now().addMinutes(-30),
      Is_Active__c = true,
      Resolution_Status__c = 'Resolved',
      Processing_Status__c = 'Processed'
    );
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
      Email = 'leadreparent@test.example.com',
      Username = 'leadreparent' +
        Crypto.getRandomInteger() +
        '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'ldrep',
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
