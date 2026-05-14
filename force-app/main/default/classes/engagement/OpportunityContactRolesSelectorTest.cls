/**
 * @description Tests for OpportunityContactRolesSelector — happy path plus
 *              null/empty guards for both selector methods.
 * @group Engagement Attribution
 * @see OpportunityContactRolesSelector
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class OpportunityContactRolesSelectorTest {
  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    User testUser = TestFactory.createTestUser(true, 'Standard User');
    System.runAs(testUser) {
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
    System.runAs(TestFactory.getTestUser('Standard User')) {
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
    System.runAs(TestFactory.getTestUser('Standard User')) {
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
    System.runAs(TestFactory.getTestUser('Standard User')) {
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
    System.runAs(TestFactory.getTestUser('Standard User')) {
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
}
