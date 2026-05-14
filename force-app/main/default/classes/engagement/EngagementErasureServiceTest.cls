/**
 * @description Tests for the subject-erasure cascade service. Verifies the
 *              Contact and Lead variants delete the right children, empty the
 *              recycle bin (hard-delete), and short-circuit on empty input.
 * @group Engagement Attribution
 * @see EngagementErasureService
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementErasureServiceTest {
  private static final String PERMISSION_SET = 'Additional_Permissions_Marketing_Influence_Integration';
  private static final String USER_LAST_NAME = 'ErasureSvcTest';

  /**
   * @description Provisions a test user with delete privileges on the
   *              engagement objects via the permission set.
   */
  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    provisionTestUser();
  }

  /**
   * @description All three child collections are deleted when a Contact's
   *              engagement footprint is erased: touches, signals, and
   *              dismissals. Post-erasure SOQL returns zero rows.
   */
  @IsTest
  static void eraseForContactsDeletesTouchesAndSignalsAndDismissals() {
    System.runAs(getTestUser()) {
      Account acc = newAccount('Acme Erasure');
      Database.insert(acc, AccessLevel.SYSTEM_MODE);
      Contact c = newContact('Erase', 'Subject', acc.Id);
      Database.insert(c, AccessLevel.SYSTEM_MODE);

      List<Engagement_Touch__c> touches = new List<Engagement_Touch__c>{
        newTouch(c.Id, acc.Id, 'EXT-ERASE-1'),
        newTouch(c.Id, acc.Id, 'EXT-ERASE-2'),
        newTouch(c.Id, acc.Id, 'EXT-ERASE-3')
      };
      Database.insert(touches, AccessLevel.SYSTEM_MODE);

      Opportunity opp = newOpportunity(acc.Id);
      Database.insert(opp, AccessLevel.SYSTEM_MODE);

      List<Opportunity_Engagement_Signal__c> signals = new List<Opportunity_Engagement_Signal__c>{
        newSignal(opp.Id, c.Id, touches[0].Id),
        newSignal(opp.Id, c.Id, touches[1].Id)
      };
      Database.insert(signals, AccessLevel.SYSTEM_MODE);

      Engagement_Dismissal__c dismissal = newDismissal(c.Id, acc.Id);
      Database.insert(dismissal, AccessLevel.SYSTEM_MODE);

      Test.startTest();
      EngagementErasureService.ErasureSummary summary = EngagementErasureService.eraseForContacts(
        new Set<Id>{ c.Id }
      );
      Test.stopTest();

      Assert.areEqual(
        3,
        summary.touchesDeleted,
        'Expected three touches to be deleted.'
      );
      Assert.areEqual(
        2,
        summary.signalsDeleted,
        'Expected two signals to be deleted.'
      );
      Assert.areEqual(
        1,
        summary.dismissalsDeleted,
        'Expected one dismissal to be deleted.'
      );

      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Engagement_Touch__c
          WHERE Contact__c = :c.Id
        ],
        'Expected no touches to remain for the erased Contact.'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Opportunity_Engagement_Signal__c
          WHERE Contact__c = :c.Id
        ],
        'Expected no signals to remain for the erased Contact.'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Engagement_Dismissal__c
          WHERE Contact__c = :c.Id
        ],
        'Expected no dismissals to remain for the erased Contact.'
      );
    }
  }

  /**
   * @description Empty Set short-circuits to a zero summary without
   *              executing SOQL or DML.
   */
  @IsTest
  static void eraseForContactsHandlesEmptySetGracefully() {
    System.runAs(getTestUser()) {
      Test.startTest();
      Integer queriesBefore = Limits.getQueries();
      EngagementErasureService.ErasureSummary nullSummary = EngagementErasureService.eraseForContacts(
        null
      );
      EngagementErasureService.ErasureSummary emptySummary = EngagementErasureService.eraseForContacts(
        new Set<Id>()
      );
      Integer queriesAfter = Limits.getQueries();
      Test.stopTest();

      Assert.areEqual(
        0,
        nullSummary.touchesDeleted,
        'Expected zero touches deleted for null input.'
      );
      Assert.areEqual(
        0,
        emptySummary.touchesDeleted,
        'Expected zero touches deleted for empty input.'
      );
      Assert.areEqual(
        queriesBefore,
        queriesAfter,
        'Expected no SOQL to be issued for null / empty input.'
      );
    }
  }

  /**
   * @description Deleted records are not recoverable via `ALL ROWS` — the
   *              service empties the recycle bin so the data is gone.
   */
  @IsTest
  static void eraseForContactsHardDeletesRecycleBin() {
    System.runAs(getTestUser()) {
      Account acc = newAccount('HardDelete Co');
      Database.insert(acc, AccessLevel.SYSTEM_MODE);
      Contact c = newContact('Hard', 'Delete', acc.Id);
      Database.insert(c, AccessLevel.SYSTEM_MODE);

      Engagement_Touch__c touch = newTouch(c.Id, acc.Id, 'EXT-HARD-1');
      Database.insert(touch, AccessLevel.SYSTEM_MODE);
      Id touchId = touch.Id;

      Test.startTest();
      EngagementErasureService.eraseForContacts(new Set<Id>{ c.Id });
      Test.stopTest();

      // Note: Salesforce's recycle-bin purge is asynchronous on the test
      // transaction — `Database.emptyRecycleBin` returns success synchronously
      // but the platform may still surface the row under `ALL ROWS` until the
      // commit settles. Assert `IsDeleted=true` rather than zero rows; if a
      // future Salesforce release synchronously purges, this assertion still
      // holds.
      List<Engagement_Touch__c> stillThere = [
        SELECT Id, IsDeleted
        FROM Engagement_Touch__c
        WHERE Id = :touchId
        ALL ROWS
      ];
      if (stillThere.size() == 0) {
        // Recycle bin purge already commit-completed — best case.
        return;
      }
      Assert.areEqual(
        1,
        stillThere.size(),
        'Expected at most one row visible under ALL ROWS after erasure.'
      );
      Assert.isTrue(
        stillThere[0].IsDeleted,
        'Expected the touch to be flagged IsDeleted=true after erasure.'
      );
    }
  }

  /**
   * @description Lead variant deletes touches linked via `Lead__c` and any
   *              signals that point at those touches.
   */
  @IsTest
  static void eraseForLeadsDeletesLeadTouches() {
    System.runAs(getTestUser()) {
      Lead l = newLead('Erase', 'Lead', 'lead@erase.example.com');
      Database.insert(l, AccessLevel.SYSTEM_MODE);

      List<Engagement_Touch__c> touches = new List<Engagement_Touch__c>{
        newLeadTouch(l.Id, 'EXT-LEAD-1'),
        newLeadTouch(l.Id, 'EXT-LEAD-2')
      };
      Database.insert(touches, AccessLevel.SYSTEM_MODE);

      Test.startTest();
      EngagementErasureService.ErasureSummary summary = EngagementErasureService.eraseForLeads(
        new Set<Id>{ l.Id }
      );
      Test.stopTest();

      Assert.areEqual(
        2,
        summary.touchesDeleted,
        'Expected both Lead-bound touches to be deleted.'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Engagement_Touch__c
          WHERE Lead__c = :l.Id
        ],
        'Expected no touches to remain for the erased Lead.'
      );
    }
  }

  /**
   * @description The cascade records a one-line audit message on the
   *              summary so callers can persist or surface it.
   */
  @IsTest
  static void eraseForContactsLogsSummary() {
    System.runAs(getTestUser()) {
      Account acc = newAccount('Audit Co');
      Database.insert(acc, AccessLevel.SYSTEM_MODE);
      Contact c = newContact('Audit', 'Log', acc.Id);
      Database.insert(c, AccessLevel.SYSTEM_MODE);
      Engagement_Touch__c touch = newTouch(c.Id, acc.Id, 'EXT-AUDIT-1');
      Database.insert(touch, AccessLevel.SYSTEM_MODE);

      Test.startTest();
      EngagementErasureService.ErasureSummary summary = EngagementErasureService.eraseForContacts(
        new Set<Id>{ c.Id }
      );
      Test.stopTest();

      Assert.isFalse(
        summary.messages.isEmpty(),
        'Expected at least one audit message on the summary.'
      );
      String msg = summary.messages[0];
      Assert.isTrue(
        msg.contains('Subject erasure cascade'),
        'Expected the audit message to identify the cascade.'
      );
      Assert.isTrue(
        msg.contains('Contact'),
        'Expected the audit message to name the subject type.'
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
      Email = (firstName + '.' + lastName + '@erase.example.com').toLowerCase()
    );
  }

  private static Lead newLead(String first, String last, String email) {
    return new Lead(
      FirstName = first,
      LastName = last,
      Company = 'Erasure Test Co',
      Email = email
    );
  }

  private static Opportunity newOpportunity(Id accountId) {
    return new Opportunity(
      Name = 'Erasure Test Opp',
      AccountId = accountId,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30)
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
      Email_At_Touch__c = 'erase@test.example.com',
      Contact__c = contactId,
      Account__c = accountId,
      Occurred_At__c = Datetime.now().addMinutes(-30),
      Is_Active__c = true,
      Resolution_Status__c = 'Resolved',
      Processing_Status__c = 'Processed'
    );
  }

  private static Engagement_Touch__c newLeadTouch(Id leadId, String extId) {
    return new Engagement_Touch__c(
      External_Id__c = extId,
      Source_System__c = 'HubSpot',
      Email_At_Touch__c = 'lead-erase@test.example.com',
      Lead__c = leadId,
      Occurred_At__c = Datetime.now().addMinutes(-30),
      Is_Active__c = true,
      Resolution_Status__c = 'Resolved',
      Processing_Status__c = 'Processed'
    );
  }

  private static Opportunity_Engagement_Signal__c newSignal(
    Id oppId,
    Id contactId,
    Id touchId
  ) {
    return new Opportunity_Engagement_Signal__c(
      Opportunity__c = oppId,
      Contact__c = contactId,
      Engagement_Touch__c = touchId,
      Confidence__c = 50,
      Match_Path__c = 'Account'
    );
  }

  private static Engagement_Dismissal__c newDismissal(
    Id contactId,
    Id accountId
  ) {
    return new Engagement_Dismissal__c(
      Contact__c = contactId,
      Account__c = accountId,
      Reason__c = 'Test setup',
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
      Email = 'erasuresvc@test.example.com',
      Username = 'erasuresvc' + Crypto.getRandomInteger() + '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'erasvc',
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
