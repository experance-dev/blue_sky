/**
 * @description Tests for the before-delete cascade triggered when Contacts
 *              are erased. Verifies that the platform's invocation of
 *              `ContactTrigger` cleans up engagement children both for a
 *              single Contact and across a bulk delete.
 * @group Engagement Attribution
 * @see ContactEngagementErasureHandler
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class ContactEngagementErasureHandlerTest {
  private static final String PERMISSION_SET = 'Engagement_Attribution_User';
  private static final String USER_LAST_NAME = 'ContactErasureTest';

  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    provisionTestUser();
  }

  /**
   * @description Deleting a single Contact cascades to its touch and
   *              dismissal. Both rows are gone post-delete.
   */
  @IsTest
  static void deletingContactErasesEngagementData() {
    System.runAs(getTestUser()) {
      Account acc = newAccount('Single Erase Co');
      Database.insert(acc, AccessLevel.SYSTEM_MODE);
      Contact c = newContact('Single', 'Erase', acc.Id);
      Database.insert(c, AccessLevel.SYSTEM_MODE);

      Engagement_Touch__c touch = newTouch(c.Id, acc.Id, 'EXT-CT-1');
      Database.insert(touch, AccessLevel.SYSTEM_MODE);
      Engagement_Dismissal__c dismissal = newDismissal(c.Id, acc.Id);
      Database.insert(dismissal, AccessLevel.SYSTEM_MODE);

      Test.startTest();
      Database.delete(c, AccessLevel.SYSTEM_MODE);
      Test.stopTest();

      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Engagement_Touch__c
          WHERE External_Id__c = 'EXT-CT-1'
        ],
        'Expected the touch to be cascade-deleted with the Contact.'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Engagement_Dismissal__c
          WHERE Id = :dismissal.Id
        ],
        'Expected the dismissal to be cascade-deleted with the Contact.'
      );
    }
  }

  /**
   * @description Deleting five Contacts in one DML cascades touches for all
   *              of them in the same transaction. Verifies bulk-safety.
   */
  @IsTest
  static void bulkDeleteContactsCascadesAcrossAll() {
    System.runAs(getTestUser()) {
      Account acc = newAccount('Bulk Erase Co');
      Database.insert(acc, AccessLevel.SYSTEM_MODE);

      List<Contact> contacts = new List<Contact>();
      for (Integer i = 0; i < 5; i++) {
        contacts.add(newContact('Bulk' + i, 'Erase', acc.Id));
      }
      Database.insert(contacts, AccessLevel.SYSTEM_MODE);

      List<Engagement_Touch__c> touches = new List<Engagement_Touch__c>();
      for (Integer i = 0; i < contacts.size(); i++) {
        touches.add(newTouch(contacts[i].Id, acc.Id, 'EXT-BULK-' + i));
      }
      Database.insert(touches, AccessLevel.SYSTEM_MODE);

      Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
      Assert.areEqual(
        5,
        [
          SELECT COUNT()
          FROM Engagement_Touch__c
          WHERE Contact__c IN :contactIds
        ],
        'Expected five touches pre-delete.'
      );

      Test.startTest();
      Database.delete(contacts, AccessLevel.SYSTEM_MODE);
      Test.stopTest();

      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Engagement_Touch__c
          WHERE Contact__c IN :contactIds
        ],
        'Expected all five touches to be cascade-deleted.'
      );
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  private static Account newAccount(String name) {
    return new Account(Name = name);
  }

  private static Contact newContact(
    String firstName,
    String lastName,
    Id accountId
  ) {
    return new Contact(
      FirstName = firstName,
      LastName = lastName,
      AccountId = accountId,
      Email = (firstName +
        '.' +
        lastName +
        '@cterase.example.com')
        .toLowerCase()
    );
  }

  private static Engagement_Touch__c newTouch(
    Id contactId,
    Id accountId,
    String extId
  ) {
    return new Engagement_Touch__c(
      External_Id__c = extId,
      Source_System__c = 'HubSpot',
      Email_At_Touch__c = 'cterase@test.example.com',
      Contact__c = contactId,
      Account__c = accountId,
      Occurred_At__c = Datetime.now().addMinutes(-30),
      Is_Active__c = true,
      Resolution_Status__c = 'Resolved',
      Processing_Status__c = 'Processed'
    );
  }

  private static Engagement_Dismissal__c newDismissal(
    Id contactId,
    Id accountId
  ) {
    return new Engagement_Dismissal__c(
      Contact__c = contactId,
      Account__c = accountId,
      Reason__c = 'Trigger test',
      Dismissed_At__c = Datetime.now()
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
      Email = 'cterasure@test.example.com',
      Username = 'cterasure' + Crypto.getRandomInteger() + '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'cter',
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
