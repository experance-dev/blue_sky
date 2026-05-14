/**
 * @description Happy-path tests for `EngagementTouchesSelector`. Phase 1 scope —
 *              every public method exercised at least once. All tests run as a
 *              standard-license user with the `Additional_Permissions_Marketing_Influence_Integration` perm
 *              set so that USER_MODE enforcement matches the production caller.
 * @group Engagement Attribution
 * @see EngagementTouchesSelector
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementTouchesSelectorTest {
  // ─── Constants ────────────────────────────────────────────────────────────────

  private static final String PERMISSION_SET = 'Additional_Permissions_Marketing_Influence_Integration';
  private static final String USER_LAST_NAME = 'EngageSelTest';

  // ─── Setup ───────────────────────────────────────────────────────────────────

  /**
   * @description Provision a standard-license user assigned to the
   *              Additional_Permissions_Marketing_Influence_Integration permission set. Seed data is built
   *              per-test (some tests need 2 accounts, some 1, etc.).
   */
  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    // Delegates to the shared fixture, which wraps the User +
    // PermissionSetAssignment inserts in `System.runAs(adminUser)` to avoid
    // MIXED_DML against the prior Process_Automation_Switch__c upsert.
    EngagementTestFixtures.provisionEngagementUser(USER_LAST_NAME);
  }

  // ─── Tests: selectByAccountIds ────────────────────────────────────────────────

  /**
   * @description Inserts 3 active touches across 2 Accounts, queries by 1 Account
   *              Id, asserts 2 touches returned and ordered Occurred_At DESC.
   */
  @IsTest
  static void selectByAccountIdsReturnsActiveTouchesForAccount() {
    System.runAs(getTestUser()) {
      Account a1 = newAccount('Acct One');
      Account a2 = newAccount('Acct Two');
      Database.insert(new List<Account>{ a1, a2 }, AccessLevel.SYSTEM_MODE);

      DateTime now = Datetime.now();
      Engagement_Touch__c t1 = newTouch(a1.Id, now.addMinutes(-30));
      Engagement_Touch__c t2 = newTouch(a1.Id, now.addMinutes(-10));
      Engagement_Touch__c t3 = newTouch(a2.Id, now.addMinutes(-5));
      Database.insert(
        new List<Engagement_Touch__c>{ t1, t2, t3 },
        AccessLevel.SYSTEM_MODE
      );

      Test.startTest();
      List<Engagement_Touch__c> result = EngagementTouchesSelector.selectByAccountIds(
        new Set<Id>{ a1.Id }
      );
      Test.stopTest();

      Assert.areEqual(2, result.size(), 'Expected 2 touches on Account One.');
      Assert.areEqual(
        t2.Id,
        result[0].Id,
        'Expected the most recent touch first (Occurred_At DESC).'
      );
      Assert.areEqual(t1.Id, result[1].Id, 'Expected the older touch second.');
    }
  }

  /**
   * @description Inserts 1 active + 1 inactive touch on the same Account; only the
   *              active touch should be returned.
   */
  @IsTest
  static void selectByAccountIdsExcludesInactive() {
    System.runAs(getTestUser()) {
      Account a = newAccount('Acct Active');
      Database.insert(a, AccessLevel.SYSTEM_MODE);

      DateTime now = Datetime.now();
      Engagement_Touch__c active = newTouch(a.Id, now.addMinutes(-15));
      Engagement_Touch__c inactive = newTouch(a.Id, now.addMinutes(-5));
      inactive.Is_Active__c = false;
      Database.insert(
        new List<Engagement_Touch__c>{ active, inactive },
        AccessLevel.SYSTEM_MODE
      );

      Test.startTest();
      List<Engagement_Touch__c> result = EngagementTouchesSelector.selectByAccountIds(
        new Set<Id>{ a.Id }
      );
      Test.stopTest();

      Assert.areEqual(
        1,
        result.size(),
        'Expected only the active touch to be returned.'
      );
      Assert.areEqual(active.Id, result[0].Id, 'Expected the active touch Id.');
    }
  }

  /**
   * @description Passing an empty Account Id set should short-circuit to an empty
   *              list without running a query.
   */
  @IsTest
  static void selectByAccountIdsEmptySetReturnsEmpty() {
    System.runAs(getTestUser()) {
      Test.startTest();
      List<Engagement_Touch__c> result = EngagementTouchesSelector.selectByAccountIds(
        new Set<Id>()
      );
      Test.stopTest();

      Assert.areEqual(
        0,
        result.size(),
        'Expected empty list for empty input set.'
      );
      Assert.isNotNull(result, 'Expected non-null list.');
    }
  }

  // ─── Tests: selectByOpportunityWithTopics ─────────────────────────────────────

  /**
   * @description 1 Account + 2 Touch_Topics + 1 Opportunity + 3 touches (2 with
   *              Topic_A, 1 with Topic_B). Querying with `Set<Id>{topicAId}` returns
   *              the 2 Topic_A touches only.
   */
  @IsTest
  static void selectByOpportunityWithTopicsFiltersByTopic() {
    System.runAs(getTestUser()) {
      Account acct = newAccount('Topic Filter Acct');
      Database.insert(acct, AccessLevel.SYSTEM_MODE);

      Touch_Topic__c topicA = new Touch_Topic__c(
        Name = 'Topic_A',
        External_Code__c = 'TPCA'
      );
      Touch_Topic__c topicB = new Touch_Topic__c(
        Name = 'Topic_B',
        External_Code__c = 'TPCB'
      );
      Database.insert(
        new List<Touch_Topic__c>{ topicA, topicB },
        AccessLevel.SYSTEM_MODE
      );

      Opportunity opp = new Opportunity(
        Name = 'Topic Filter Opp',
        AccountId = acct.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today().addDays(30)
      );
      Database.insert(opp, AccessLevel.SYSTEM_MODE);

      DateTime now = Datetime.now();
      Engagement_Touch__c a1 = newTouch(acct.Id, now.addMinutes(-30));
      a1.Topic__c = topicA.Id;
      Engagement_Touch__c a2 = newTouch(acct.Id, now.addMinutes(-20));
      a2.Topic__c = topicA.Id;
      Engagement_Touch__c b1 = newTouch(acct.Id, now.addMinutes(-10));
      b1.Topic__c = topicB.Id;
      Database.insert(
        new List<Engagement_Touch__c>{ a1, a2, b1 },
        AccessLevel.SYSTEM_MODE
      );

      Test.startTest();
      List<Engagement_Touch__c> result = EngagementTouchesSelector.selectByOpportunityWithTopics(
        opp.Id,
        new Set<Id>{ topicA.Id }
      );
      Test.stopTest();

      Assert.areEqual(2, result.size(), 'Expected only the 2 Topic_A touches.');
      for (Engagement_Touch__c t : result) {
        Assert.areEqual(
          topicA.Id,
          t.Topic__c,
          'Every returned touch should carry Topic_A.'
        );
      }
    }
  }

  /**
   * @description When the topic filter set is empty, all 3 active account touches
   *              should be returned (filter degrades to "no constraint").
   */
  @IsTest
  static void selectByOpportunityWithTopicsNoTopicFilterReturnsAll() {
    System.runAs(getTestUser()) {
      Account acct = newAccount('No Topic Filter Acct');
      Database.insert(acct, AccessLevel.SYSTEM_MODE);

      Touch_Topic__c topicA = new Touch_Topic__c(
        Name = 'Topic_A',
        External_Code__c = 'TPCA2'
      );
      Touch_Topic__c topicB = new Touch_Topic__c(
        Name = 'Topic_B',
        External_Code__c = 'TPCB2'
      );
      Database.insert(
        new List<Touch_Topic__c>{ topicA, topicB },
        AccessLevel.SYSTEM_MODE
      );

      Opportunity opp = new Opportunity(
        Name = 'No Topic Filter Opp',
        AccountId = acct.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today().addDays(30)
      );
      Database.insert(opp, AccessLevel.SYSTEM_MODE);

      DateTime now = Datetime.now();
      Engagement_Touch__c a1 = newTouch(acct.Id, now.addMinutes(-30));
      a1.Topic__c = topicA.Id;
      Engagement_Touch__c a2 = newTouch(acct.Id, now.addMinutes(-20));
      a2.Topic__c = topicA.Id;
      Engagement_Touch__c b1 = newTouch(acct.Id, now.addMinutes(-10));
      b1.Topic__c = topicB.Id;
      Database.insert(
        new List<Engagement_Touch__c>{ a1, a2, b1 },
        AccessLevel.SYSTEM_MODE
      );

      Test.startTest();
      List<Engagement_Touch__c> result = EngagementTouchesSelector.selectByOpportunityWithTopics(
        opp.Id,
        new Set<Id>()
      );
      Test.stopTest();

      Assert.areEqual(
        3,
        result.size(),
        'Expected all 3 active account touches when topic filter is empty.'
      );
    }
  }

  /**
   * @description Querying with a fake Opportunity Id (no matching row visible to
   *              the user) should return an empty list.
   */
  @IsTest
  static void selectByOpportunityWithTopicsOppNotFoundReturnsEmpty() {
    System.runAs(getTestUser()) {
      Id fakeOppId = (Id) Utilities.getFakeId(Opportunity.SObjectType);

      Test.startTest();
      List<Engagement_Touch__c> result = EngagementTouchesSelector.selectByOpportunityWithTopics(
        fakeOppId,
        new Set<Id>()
      );
      Test.stopTest();

      Assert.areEqual(
        0,
        result.size(),
        'Expected empty list when Opportunity Id has no match.'
      );
      Assert.isNotNull(result, 'Expected non-null list.');
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  /**
   * @description Builds a base, active, Processed `Engagement_Touch__c` referencing
   *              the supplied Account and Occurred_At. Tests set additional fields
   *              (e.g. Topic__c) as needed before insert.
   * @param accountId Account to attribute the touch to.
   * @param occurred  Occurred_At value.
   * @return A populated, not-yet-inserted Engagement_Touch__c.
   */
  private static Engagement_Touch__c newTouch(Id accountId, DateTime occurred) {
    return new Engagement_Touch__c(
      Account__c = accountId,
      Is_Active__c = true,
      Processing_Status__c = 'Processed',
      Resolution_Status__c = 'Resolved',
      Source_System__c = 'Manual',
      Source_Event_Type__c = 'Download',
      Touch_Type__c = 'Download',
      Occurred_At__c = occurred,
      External_Id__c = 'EXT-' + Crypto.getRandomInteger()
    );
  }

  /**
   * @description Builds a not-yet-inserted Account with the supplied name.
   * @param name Account Name.
   * @return A populated, not-yet-inserted Account.
   */
  private static Account newAccount(String name) {
    return new Account(Name = name);
  }

  /**
   * @description Resolves the seeded test user from `@TestSetup`.
   * @return The seeded standard-license test user.
   */
  private static User getTestUser() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :USER_LAST_NAME
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  // ─── Persona coverage ─────────────────────────────────────────────────────

  /**
   * @description Persona-coverage fan-out for `selectByAccountIds`. Verifies
   *              the selector returns the same active-touch list under every
   *              MI persona granted Account read + Engagement_Touch__c read.
   *              The shared Account + Touch records are explicitly shared to
   *              each persona because the seed runs as one user under
   *              OWD-Private and the cross-reference visibility otherwise
   *              hides them from other personas.
   *
   *              The `no_perm` persona is NOT asserted on touch visibility
   *              here — its expected outcome is `Engagement_Touch__c` not
   *              readable at all (Apex class access blocks the LWC call,
   *              and the LWC component-visibility rule hides the panel).
   *              That contract is gated at the metadata layer, not the SOQL
   *              layer; a runtime assertion would either succeed for the
   *              wrong reason (record was shared) or fail with a noisy
   *              field-access exception that obscures intent.
   */
  @IsTest
  static void selectByAccountIdsAcrossPersonas() {
    // Build a fresh Account + 2 active touches under the seed user; then
    // share to all good-path personas. This is independent of the per-test
    // data shapes inside the other test methods.
    Account acct;
    List<Engagement_Touch__c> seededTouches;
    System.runAs(getTestUser()) {
      acct = newAccount('Persona Coverage Account');
      Database.insert(acct, AccessLevel.SYSTEM_MODE);
      DateTime now = Datetime.now();
      Engagement_Touch__c t1 = newTouch(acct.Id, now.addMinutes(-30));
      Engagement_Touch__c t2 = newTouch(acct.Id, now.addMinutes(-10));
      seededTouches = new List<Engagement_Touch__c>{ t1, t2 };
      Database.insert(seededTouches, AccessLevel.SYSTEM_MODE);
    }

    List<String> goodPathPersonas = new List<String>{
      PersonaTestFactory.VIEW,
      PersonaTestFactory.POWER_USER,
      PersonaTestFactory.ADMIN,
      PersonaTestFactory.INTEGRATION
    };

    List<User> goodPathUsers = new List<User>();
    for (String persona : goodPathPersonas) {
      goodPathUsers.add(PersonaTestFactory.userFor(persona));
    }

    // Share the Account (cascades OpportunityAccessLevel — irrelevant here
    // but harmless) and the Engagement_Touch__c rows to every persona at Read.
    EngagementTestFixtures.shareRecordsToUsers(
      new List<SObject>{ acct },
      goodPathUsers,
      'Read'
    );
    EngagementTestFixtures.shareRecordsToUsers(
      seededTouches,
      goodPathUsers,
      'Read'
    );

    Test.startTest();
    for (String persona : goodPathPersonas) {
      System.runAs(PersonaTestFactory.userFor(persona)) {
        List<Engagement_Touch__c> result = EngagementTouchesSelector.selectByAccountIds(
          new Set<Id>{ acct.Id }
        );
        Assert.areEqual(
          2,
          result.size(),
          'Persona ' +
            persona +
            ' should see both shared touches on the Account (got ' +
            result.size() +
            ').'
        );
      }
    }
    Test.stopTest();
  }
}
