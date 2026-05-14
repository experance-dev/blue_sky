/**
 * @description Tests for `EngagementDismissalsSelector`. Seeds an Account,
 *              a Contact, an Opportunity, and a mix of dismissal records
 *              (multiple per contact, multiple scopes, multiple users) to
 *              exercise the MAX(Dismissed_At) reduction, scope isolation,
 *              and per-user filtering.
 * @group Engagement Attribution
 * @see EngagementDismissalsSelector
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementDismissalsSelectorTest {
  // ─── Constants ────────────────────────────────────────────────────────────

  private static final String PERMISSION_SET = 'Engagement_Attribution_User';
  private static final String USER_LAST_NAME = 'EngageDisSelTest';
  private static final String OTHER_USER_LAST_NAME = 'EngageDisSelOther';
  private static final String ACCOUNT_NAME = 'Dismissal Selector Test Acct';
  private static final String OPP_NAME = 'Dismissal Selector Test Opp';
  private static final String SECONDARY_OPP_NAME = 'Dismissal Selector Other Opp';
  private static final String PRIMARY_CONTACT_LAST = 'PrimaryContact';
  private static final String OTHER_CONTACT_LAST = 'OtherContact';

  // ─── Setup ────────────────────────────────────────────────────────────────

  /**
   * @description Provisions the running test user and a second user, then
   *              seeds the Account/Contact/Opportunity graph and a layered
   *              set of dismissals as the primary user: three on the primary
   *              contact for the primary Opp (different timestamps), one on
   *              the other contact for the primary Opp, and one on the
   *              primary contact for the secondary Opp.
   */
  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    User primaryUser = provisionUser(USER_LAST_NAME, 'disselprim');
    User otherUser = provisionUser(OTHER_USER_LAST_NAME, 'disselother');

    System.runAs(primaryUser) {
      Account acct = new Account(Name = ACCOUNT_NAME);
      Database.insert(acct, AccessLevel.SYSTEM_MODE);

      Contact primary = new Contact(
        FirstName = 'Primary',
        LastName = PRIMARY_CONTACT_LAST,
        AccountId = acct.Id
      );
      Contact other = new Contact(
        FirstName = 'Other',
        LastName = OTHER_CONTACT_LAST,
        AccountId = acct.Id
      );
      Database.insert(
        new List<Contact>{ primary, other },
        AccessLevel.SYSTEM_MODE
      );

      Opportunity opp = new Opportunity(
        Name = OPP_NAME,
        AccountId = acct.Id,
        StageName = 'Proposal/Quote',
        CloseDate = Date.today().addDays(30)
      );
      Opportunity opp2 = new Opportunity(
        Name = SECONDARY_OPP_NAME,
        AccountId = acct.Id,
        StageName = 'Proposal/Quote',
        CloseDate = Date.today().addDays(30)
      );
      Database.insert(
        new List<Opportunity>{ opp, opp2 },
        AccessLevel.SYSTEM_MODE
      );

      DateTime now = Datetime.now();
      List<Engagement_Dismissal__c> dismissals = new List<Engagement_Dismissal__c>{
        // Three dismissals for primary contact on primary opp (oldest first).
        newDismissal(primary.Id, opp.Id, null, now.addMinutes(-180)),
        newDismissal(primary.Id, opp.Id, null, now.addMinutes(-60)),
        newDismissal(primary.Id, opp.Id, null, now.addMinutes(-1)),
        // One dismissal for the OTHER contact on the primary opp.
        newDismissal(other.Id, opp.Id, null, now.addMinutes(-30)),
        // One dismissal for primary contact on a DIFFERENT opp.
        newDismissal(primary.Id, opp2.Id, null, now.addMinutes(-15))
      };
      Database.insert(dismissals, AccessLevel.USER_MODE);
    }
  }

  // ─── Tests ────────────────────────────────────────────────────────────────

  /**
   * @description The selector must reduce multiple dismissals per Contact to
   *              MAX(Dismissed_At__c) — i.e., the most-recent timestamp,
   *              never the earliest.
   */
  @IsTest
  static void selectLatestByOpportunityReturnsMostRecentPerContact() {
    System.runAs(getPrimaryUser()) {
      Id opportunityId = lookupOppId(OPP_NAME);
      Id primaryContactId = lookupContactIdByLastName(PRIMARY_CONTACT_LAST);

      DateTime expectedMax = [
        SELECT Dismissed_At__c
        FROM Engagement_Dismissal__c
        WHERE Opportunity__c = :opportunityId AND Contact__c = :primaryContactId
        ORDER BY Dismissed_At__c DESC
        LIMIT 1
      ]
      .Dismissed_At__c;

      Test.startTest();
      Map<Id, DateTime> result = EngagementDismissalsSelector.selectLatestByOpportunityForCurrentUser(
        opportunityId
      );
      Test.stopTest();

      Assert.isTrue(
        result.containsKey(primaryContactId),
        'Expected the primary contact to appear in the dismissals map.'
      );
      Assert.areEqual(
        expectedMax,
        result.get(primaryContactId),
        'Expected the map to carry MAX(Dismissed_At__c), not the earliest.'
      );
    }
  }

  /**
   * @description Null Opportunity Id must short-circuit to an empty map
   *              without running a query.
   */
  @IsTest
  static void selectLatestByOpportunityNullReturnsEmpty() {
    System.runAs(getPrimaryUser()) {
      Test.startTest();
      Map<Id, DateTime> result = EngagementDismissalsSelector.selectLatestByOpportunityForCurrentUser(
        null
      );
      Test.stopTest();

      Assert.areEqual(
        0,
        result.size(),
        'Expected an empty map for a null opportunityId.'
      );
    }
  }

  /**
   * @description Scope isolation: a dismissal recorded against the Account
   *              must NOT bleed into the Opportunity-scoped query, and vice
   *              versa. Insert one dismissal of each scope for the same
   *              contact, then assert each method returns only its own.
   */
  @IsTest
  static void selectLatestByAccountIsolatesByScope() {
    System.runAs(getPrimaryUser()) {
      Id accountId = lookupAccountId();
      Id opportunityId = lookupOppId(OPP_NAME);
      Id primaryContactId = lookupContactIdByLastName(PRIMARY_CONTACT_LAST);

      // The setup seeded an Opp-scoped dismissal already. Add one Account-scoped.
      Engagement_Dismissal__c accountScoped = newDismissal(
        primaryContactId,
        null,
        accountId,
        Datetime.now().addMinutes(-5)
      );
      Database.insert(accountScoped, AccessLevel.USER_MODE);

      Test.startTest();
      Map<Id, DateTime> oppResult = EngagementDismissalsSelector.selectLatestByOpportunityForCurrentUser(
        opportunityId
      );
      Map<Id, DateTime> acctResult = EngagementDismissalsSelector.selectLatestByAccountForCurrentUser(
        accountId
      );
      Test.stopTest();

      Assert.isTrue(
        oppResult.containsKey(primaryContactId),
        'Expected the Opp-scoped query to return the Opp dismissal.'
      );
      Assert.isTrue(
        acctResult.containsKey(primaryContactId),
        'Expected the Account-scoped query to return the Account dismissal.'
      );
      Assert.areEqual(
        accountScoped.Dismissed_At__c,
        acctResult.get(primaryContactId),
        'Expected the Account-scoped result to carry the Account dismissal timestamp, not the Opp one.'
      );
    }
  }

  /**
   * @description Per-user filtering: a dismissal recorded by a different
   *              user must not be visible to the running user's query.
   */
  @IsTest
  static void selectLatestByOpportunityScopesToCurrentUser() {
    Id opportunityId;
    Id primaryContactId;
    System.runAs(getPrimaryUser()) {
      opportunityId = lookupOppId(OPP_NAME);
      primaryContactId = lookupContactIdByLastName(PRIMARY_CONTACT_LAST);
    }

    // Insert a dismissal as the OTHER user, well in the future so any
    // first-in-Map sort would surface it if scoping were broken.
    System.runAs(getOtherUser()) {
      Engagement_Dismissal__c otherUsersDismissal = newDismissal(
        primaryContactId,
        opportunityId,
        null,
        Datetime.now().addMinutes(120)
      );
      Database.insert(otherUsersDismissal, AccessLevel.USER_MODE);
    }

    System.runAs(getPrimaryUser()) {
      Test.startTest();
      Map<Id, DateTime> result = EngagementDismissalsSelector.selectLatestByOpportunityForCurrentUser(
        opportunityId
      );
      Test.stopTest();

      Assert.isTrue(
        result.containsKey(primaryContactId),
        'Expected the primary user to still see their own dismissals.'
      );
      Assert.isTrue(
        result.get(primaryContactId) < Datetime.now().addMinutes(60),
        'Expected the other user\'s future-dated dismissal to be filtered out.'
      );
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  private static User provisionUser(String lastName, String aliasPrefix) {
    Profile standard = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    User u = new User(
      ProfileId = standard.Id,
      LastName = lastName,
      Email = aliasPrefix + '@test.example.com',
      Username = aliasPrefix + Crypto.getRandomInteger() + '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = aliasPrefix.left(8),
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

  private static Engagement_Dismissal__c newDismissal(
    Id contactId,
    Id opportunityId,
    Id accountId,
    DateTime dismissedAt
  ) {
    return new Engagement_Dismissal__c(
      Contact__c = contactId,
      Opportunity__c = opportunityId,
      Account__c = accountId,
      Dismissed_At__c = dismissedAt
    );
  }

  private static User getPrimaryUser() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :USER_LAST_NAME
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  private static User getOtherUser() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :OTHER_USER_LAST_NAME
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  private static Id lookupAccountId() {
    return [SELECT Id FROM Account WHERE Name = :ACCOUNT_NAME LIMIT 1].Id;
  }

  private static Id lookupOppId(String name) {
    return [SELECT Id FROM Opportunity WHERE Name = :name LIMIT 1].Id;
  }

  private static Id lookupContactIdByLastName(String lastName) {
    return [SELECT Id FROM Contact WHERE LastName = :lastName LIMIT 1].Id;
  }
}
