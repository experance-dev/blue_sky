/**
 * @description Tests for `IdentityResolutionService.resolveAll`. Each test
 *              constructs in-memory `Engagement_Touch__c` records (no DML
 *              required for the SUT — the service only reads Contact / Lead),
 *              invokes `resolveAll`, and asserts the mutated record fields.
 * @group Engagement Attribution
 * @see IdentityResolutionService
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class IdentityResolutionServiceTest {
  private static final String PERMISSION_SET = 'Engagement_Attribution_User';
  private static final String USER_LAST_NAME = 'IdResolveTest';
  private static final String SARAH_EMAIL = 'sarah.johnson@uhc.example.com';
  private static final String LEAD_EMAIL = 'prospect@vendor.example.com';

  /**
   * @description Provisions the test user and seeds a known-Contact / Lead
   *              world so every resolution path has a deterministic input.
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
   * @description Happy path — exactly one Contact matches the email,
   *              resolution flips to `Resolved` with Contact + Account set.
   */
  @IsTest
  static void resolveAllHappyPathSingleContactMatch() {
    System.runAs(getTestUser()) {
      Engagement_Touch__c t = new Engagement_Touch__c(
        Email_At_Touch__c = SARAH_EMAIL.toUpperCase()
      );
      List<Engagement_Touch__c> input = new List<Engagement_Touch__c>{ t };

      Test.startTest();
      IdentityResolutionService.resolveAll(input);
      Test.stopTest();

      Assert.areEqual(
        'Resolved',
        input[0].Resolution_Status__c,
        'Expected single Contact match to resolve.'
      );
      Assert.isNotNull(
        input[0].Contact__c,
        'Expected Contact__c populated on resolved touch.'
      );
      Assert.isNotNull(
        input[0].Account__c,
        'Expected Account__c populated from Contact.AccountId.'
      );
    }
  }

  /**
   * @description Two Contacts share the same email → `Ambiguous`, with
   *              Contact and Account left null.
   */
  @IsTest
  static void resolveAllAmbiguousMultiContactMatch() {
    System.runAs(getTestUser()) {
      Account acct = [SELECT Id FROM Account LIMIT 1];
      Database.insert(
        new Contact(
          FirstName = 'Twin',
          LastName = 'Sarah',
          Email = SARAH_EMAIL,
          AccountId = acct.Id
        ),
        AccessLevel.SYSTEM_MODE
      );

      Engagement_Touch__c t = new Engagement_Touch__c(
        Email_At_Touch__c = SARAH_EMAIL
      );
      List<Engagement_Touch__c> input = new List<Engagement_Touch__c>{ t };

      Test.startTest();
      IdentityResolutionService.resolveAll(input);
      Test.stopTest();

      Assert.areEqual(
        'Ambiguous',
        input[0].Resolution_Status__c,
        'Expected multi-match to resolve Ambiguous.'
      );
      Assert.isNull(
        input[0].Contact__c,
        'Expected Contact__c null on Ambiguous resolution.'
      );
    }
  }

  /**
   * @description No Contact matches, exactly one Lead does — touch binds to
   *              the Lead with status `Resolved`.
   */
  @IsTest
  static void resolveAllLeadOnlyMatchResolvesToLead() {
    System.runAs(getTestUser()) {
      Engagement_Touch__c t = new Engagement_Touch__c(
        Email_At_Touch__c = LEAD_EMAIL
      );
      List<Engagement_Touch__c> input = new List<Engagement_Touch__c>{ t };

      Test.startTest();
      IdentityResolutionService.resolveAll(input);
      Test.stopTest();

      Assert.areEqual(
        'Resolved',
        input[0].Resolution_Status__c,
        'Expected single Lead match to resolve.'
      );
      Assert.isNotNull(
        input[0].Lead__c,
        'Expected Lead__c populated on Lead-only resolution.'
      );
      Assert.isNull(
        input[0].Contact__c,
        'Expected Contact__c null on Lead resolution.'
      );
    }
  }

  /**
   * @description Email matches neither Contact nor Lead → `NoMatch`, every
   *              binding lookup left null.
   */
  @IsTest
  static void resolveAllNoMatchFallback() {
    System.runAs(getTestUser()) {
      Engagement_Touch__c t = new Engagement_Touch__c(
        Email_At_Touch__c = 'ghost@nowhere.example.com'
      );
      List<Engagement_Touch__c> input = new List<Engagement_Touch__c>{ t };

      Test.startTest();
      IdentityResolutionService.resolveAll(input);
      Test.stopTest();

      Assert.areEqual(
        'NoMatch',
        input[0].Resolution_Status__c,
        'Expected NoMatch when neither Contact nor Lead matches.'
      );
      Assert.isNull(input[0].Contact__c, 'Expected Contact__c null.');
      Assert.isNull(input[0].Lead__c, 'Expected Lead__c null.');
      Assert.isNull(input[0].Account__c, 'Expected Account__c null.');
    }
  }

  /**
   * @description Blank email short-circuits to `NoMatch` without issuing a
   *              query — defensive coverage for callers that bypass the
   *              REST endpoint's own validation.
   */
  @IsTest
  static void resolveAllBlankEmailMarksNoMatch() {
    System.runAs(getTestUser()) {
      Engagement_Touch__c t = new Engagement_Touch__c(Email_At_Touch__c = null);
      List<Engagement_Touch__c> input = new List<Engagement_Touch__c>{ t };

      Test.startTest();
      IdentityResolutionService.resolveAll(input);
      Test.stopTest();

      Assert.areEqual(
        'NoMatch',
        input[0].Resolution_Status__c,
        'Expected blank-email input to resolve NoMatch.'
      );
    }
  }

  // ─── Setup helpers ────────────────────────────────────────────────────────

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
      Email = 'idresolve@test.example.com',
      Username = 'idresolve' + Crypto.getRandomInteger() + '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'idres',
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

  private static void seedWorld() {
    Account acct = new Account(Name = 'United Healthcare Test');
    Database.insert(acct, AccessLevel.SYSTEM_MODE);

    Contact sarah = new Contact(
      FirstName = 'Sarah',
      LastName = 'Johnson',
      Email = SARAH_EMAIL,
      AccountId = acct.Id
    );
    Database.insert(sarah, AccessLevel.SYSTEM_MODE);

    Lead l = new Lead(
      FirstName = 'Pat',
      LastName = 'Prospect',
      Company = 'Vendor Co',
      Email = LEAD_EMAIL
    );
    Database.insert(l, AccessLevel.SYSTEM_MODE);
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
