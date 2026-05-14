/**
 * @description Tests for the before-delete cascade triggered when Leads
 *              are erased. The Salesforce platform fires `LeadTrigger`
 *              automatically on the delete; the test asserts that the
 *              cascade removed every touch pointed at the deleted Lead.
 * @group Engagement Attribution
 * @see LeadEngagementErasureHandler
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class LeadEngagementErasureHandlerTest {
  private static final String PERMISSION_SET = 'Engagement_Attribution_User';
  private static final String USER_LAST_NAME = 'LeadErasureTest';

  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    provisionTestUser();
  }

  /**
   * @description Deleting a Lead with two associated touches cascades to
   *              both. Post-delete count is zero.
   */
  @IsTest
  static void deletingLeadErasesLeadTouches() {
    System.runAs(getTestUser()) {
      Lead l = newLead('Lead', 'Erase', 'lead.erase@test.example.com');
      Database.insert(l, AccessLevel.SYSTEM_MODE);

      List<Engagement_Touch__c> touches = new List<Engagement_Touch__c>{
        newLeadTouch(l.Id, 'EXT-LD-1'),
        newLeadTouch(l.Id, 'EXT-LD-2')
      };
      Database.insert(touches, AccessLevel.SYSTEM_MODE);

      Test.startTest();
      Database.delete(l, AccessLevel.SYSTEM_MODE);
      Test.stopTest();

      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Engagement_Touch__c
          WHERE External_Id__c LIKE 'EXT-LD-%'
        ],
        'Expected both Lead-bound touches to be cascade-deleted.'
      );
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  private static Lead newLead(String first, String last, String email) {
    return new Lead(
      FirstName = first,
      LastName = last,
      Company = 'Erasure Test Co',
      Email = email
    );
  }

  private static Engagement_Touch__c newLeadTouch(Id leadId, String extId) {
    return new Engagement_Touch__c(
      External_Id__c = extId,
      Source_System__c = 'HubSpot',
      Email_At_Touch__c = 'lderase@test.example.com',
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
      Email = 'lderasure@test.example.com',
      Username = 'lderasure' + Crypto.getRandomInteger() + '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'lder',
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
