/**
 * @description Tests for OpportunityContactRolesSelector — happy path plus
 *              null/empty guards for both selector methods, AND a persona-coverage
 *              test that exercises the same selectByOpportunityId assertion under
 *              every MI persona that should be able to read OCRs (View, Power
 *              User, Admin, Integration). Persona coverage doubles as the test
 *              gate for the Contact.Title FLS — `OpportunityContactRolesSelector`
 *              selects `Contact.Title`, which is granted on every MI permset but
 *              missing on a raw `Standard User` profile.
 * @group Engagement Attribution
 * @see OpportunityContactRolesSelector
 * @author David Wood
 * @since May 2026
 * @last May 2026 — switched seeded user from raw 'Standard User' to a
 *                  PersonaTestFactory.VIEW user so Contact.Title FLS is granted;
 *                  added selectByOpportunityIdAcrossPersonas for persona fan-out
 *                  coverage of the MI permset ladder.
 */
@IsTest
private class OpportunityContactRolesSelectorTest {
  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    // Seed the MI View persona; reused across the existing happy-path tests
    // because `Contact.Title` (referenced by the selector) is granted on the
    // MI permset ladder but not on a raw Standard User profile. The persona
    // pre-existence saves the AcrossPersonas test method one setup-DML round.
    User viewUser = PersonaTestFactory.userFor(PersonaTestFactory.VIEW);
    System.runAs(viewUser) {
      Account acct = (Account) TestFactory.createSObject(
        new Account(Name = 'United Healthcare'),
        true
      );
      Contact c1 = (Contact) TestFactory.createSObject(
        new Contact(LastName = 'Johnson', AccountId = acct.Id),
        true
      );
      Contact c2 = (Contact) TestFactory.createSObject(
        new Contact(LastName = 'Smith', AccountId = acct.Id),
        true
      );
      Opportunity opp = (Opportunity) TestFactory.createSObject(
        new Opportunity(
          Name = 'Network Pricing Implementation',
          StageName = 'Prospecting',
          CloseDate = Date.today().addDays(30),
          AccountId = acct.Id
        ),
        true
      );
      OpportunityContactRole ocr1 = new OpportunityContactRole(
        OpportunityId = opp.Id,
        ContactId = c1.Id,
        Role = 'Economic Buyer',
        IsPrimary = true
      );
      OpportunityContactRole ocr2 = new OpportunityContactRole(
        OpportunityId = opp.Id,
        ContactId = c2.Id,
        Role = 'Evaluator'
      );
      Database.insert(
        new List<OpportunityContactRole>{ ocr1, ocr2 },
        AccessLevel.SYSTEM_MODE
      );
    }
  }

  /**
   * @description Verifies selectByOpportunityId returns every OCR on the
   *              Opportunity, ordered by CreatedDate descending.
   */
  @IsTest
  static void selectByOpportunityIdReturnsAllOcrsForOpp() {
    System.runAs(PersonaTestFactory.userFor(PersonaTestFactory.VIEW)) {
      Opportunity opp = [
        SELECT Id
        FROM Opportunity
        WHERE Name = 'Network Pricing Implementation'
        LIMIT 1
      ];

      Test.startTest();
      List<OpportunityContactRole> results = OpportunityContactRolesSelector.selectByOpportunityId(
        opp.Id
      );
      Test.stopTest();

      Assert.areEqual(
        2,
        results.size(),
        'Expected two OCRs for the seeded Opportunity.'
      );
      Assert.isTrue(
        results[0].CreatedDate >= results[1].CreatedDate,
        'Expected results ordered by CreatedDate descending.'
      );
    }
  }

  /**
   * @description Verifies selectByOpportunityId returns an empty list when
   *              passed a null Opportunity Id (no SOQL fired).
   */
  @IsTest
  static void selectByOpportunityIdEmptyOppIdReturnsEmpty() {
    System.runAs(PersonaTestFactory.userFor(PersonaTestFactory.VIEW)) {
      Test.startTest();
      List<OpportunityContactRole> results = OpportunityContactRolesSelector.selectByOpportunityId(
        null
      );
      Test.stopTest();

      Assert.areEqual(
        0,
        results.size(),
        'Expected empty list when Opportunity Id is null.'
      );
    }
  }

  /**
   * @description Verifies the (opp, contact) selector returns exactly one
   *              record for an existing pairing.
   */
  @IsTest
  static void selectByOpportunityAndContactReturnsOneWhenExists() {
    System.runAs(PersonaTestFactory.userFor(PersonaTestFactory.VIEW)) {
      Opportunity opp = [
        SELECT Id
        FROM Opportunity
        WHERE Name = 'Network Pricing Implementation'
        LIMIT 1
      ];
      Contact target = [
        SELECT Id
        FROM Contact
        WHERE LastName = 'Johnson'
        LIMIT 1
      ];

      Test.startTest();
      List<OpportunityContactRole> results = OpportunityContactRolesSelector.selectByOpportunityAndContact(
        opp.Id,
        target.Id
      );
      Test.stopTest();

      Assert.areEqual(
        1,
        results.size(),
        'Expected exactly one OCR for the seeded (opp, contact) pair.'
      );
      Assert.areEqual(
        target.Id,
        results[0].ContactId,
        'Expected the OCR to reference the requested Contact.'
      );
    }
  }

  /**
   * @description Verifies the (opp, contact) selector returns an empty list
   *              when the contact is not on the opportunity.
   */
  @IsTest
  static void selectByOpportunityAndContactReturnsEmptyWhenNotExists() {
    System.runAs(PersonaTestFactory.userFor(PersonaTestFactory.VIEW)) {
      Opportunity opp = [
        SELECT Id
        FROM Opportunity
        WHERE Name = 'Network Pricing Implementation'
        LIMIT 1
      ];
      Account acct = [
        SELECT Id
        FROM Account
        WHERE Name = 'United Healthcare'
        LIMIT 1
      ];
      Contact unrelated = (Contact) TestFactory.createSObject(
        new Contact(LastName = 'Unrelated', AccountId = acct.Id),
        true
      );

      Test.startTest();
      List<OpportunityContactRole> results = OpportunityContactRolesSelector.selectByOpportunityAndContact(
        opp.Id,
        unrelated.Id
      );
      Test.stopTest();

      Assert.areEqual(
        0,
        results.size(),
        'Expected empty list when Contact is not on the Opportunity.'
      );
    }
  }

  /**
   * @description Persona-coverage fan-out. Every MI permset (View, Power User,
   *              Admin, Integration) grants Contact.Title FLS and OCR object
   *              read; the selector must return the same two seeded OCRs for
   *              all four. A user WITHOUT any MI permset (`no_perm`) does NOT
   *              get Contact.Title FLS, so the selector's WITH USER_MODE clause
   *              throws QueryException on field accessibility — asserted as
   *              the negative persona path.
   *
   *              One test method, five persona scenarios, identical
   *              assertion shape. If the selector's behaviour drifts under one
   *              persona, the fail-message identifies which.
   *
   *              `OperationWithLimitsInLoop` is suppressed because the SOQL
   *              inside the loop is the contract under test — each persona
   *              evaluates a distinct USER_MODE / sharing context, so
   *              hoisting the query outside the loop would discard the
   *              per-persona signal. Persona-coverage pattern, see
   *              feedback-persona-path-coverage.
   */
  @IsTest
  @SuppressWarnings('PMD.OperationWithLimitsInLoop')
  static void selectByOpportunityIdAcrossPersonas() {
    // Resolve the seeded record graph and the personas we need to assert
    // against. The seed in @TestSetup runs `System.runAs(viewUser)` so the
    // Account / Contact / Opportunity are viewUser-owned; under OWD-Private,
    // a different persona running `WITH USER_MODE` SOQL sees zero OCRs even
    // with the permset granted, because OCR visibility cascades from
    // Contact + Opportunity sharing. Explicit shares to each good-path
    // persona before assertion remove the cross-reference invisibility.
    Account acct;
    List<Contact> seededContacts;
    Opportunity opp;
    System.runAs(PersonaTestFactory.userFor(PersonaTestFactory.VIEW)) {
      acct = [SELECT Id FROM Account WHERE Name = 'United Healthcare' LIMIT 1];
      opp = [
        SELECT Id
        FROM Opportunity
        WHERE Name = 'Network Pricing Implementation'
        LIMIT 1
      ];
      seededContacts = [
        SELECT Id
        FROM Contact
        WHERE LastName IN ('Johnson', 'Smith')
      ];
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

    // Share the Account (which cascades Opportunity visibility via the
    // AccountShare.OpportunityAccessLevel field) and the Contacts (whose
    // visibility OCRs inherit) to every good-path persona at Read.
    EngagementTestFixtures.shareRecordsToUsers(
      new List<SObject>{ acct },
      goodPathUsers,
      'Read'
    );
    EngagementTestFixtures.shareRecordsToUsers(
      seededContacts,
      goodPathUsers,
      'Read'
    );
    EngagementTestFixtures.shareRecordsToUsers(
      new List<SObject>{ opp },
      goodPathUsers,
      'Read'
    );

    Test.startTest();

    // Good-path personas: every MI permset, once granted Account+Contact+Opp
    // visibility, should yield the two seeded OCRs.
    for (String persona : goodPathPersonas) {
      System.runAs(PersonaTestFactory.userFor(persona)) {
        List<OpportunityContactRole> results = OpportunityContactRolesSelector.selectByOpportunityId(
          opp.Id
        );
        Assert.areEqual(
          2,
          results.size(),
          'Persona ' +
            persona +
            ' should see both seeded OCRs (got ' +
            results.size() +
            ').'
        );
      }
    }

    // Bad-path persona: a User with no MI permset lacks Contact.Title FLS,
    // and the selector's WITH USER_MODE clause must reject the SOQL. Assert on
    // the exception type rather than the message — the message text is
    // platform-controlled and shifts between releases.
    System.runAs(PersonaTestFactory.userFor(PersonaTestFactory.NO_PERM)) {
      try {
        OpportunityContactRolesSelector.selectByOpportunityId(opp.Id);
        Assert.fail(
          'Expected QueryException for no_perm persona — Contact.Title FLS missing should block the SOQL.'
        );
      } catch (System.QueryException expected) {
        // Pinned: the WITH USER_MODE clause rejects Contact.Title.
        Assert.isTrue(
          expected.getMessage().containsIgnoreCase('title') ||
            expected.getMessage().containsIgnoreCase('field') ||
            expected.getMessage().containsIgnoreCase('access'),
          'Expected QueryException message to reference the field-access cause; got: ' +
          expected.getMessage()
        );
      }
    }

    Test.stopTest();
  }
}
