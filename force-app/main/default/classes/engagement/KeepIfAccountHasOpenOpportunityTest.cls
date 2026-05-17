/**
 * @description Test class for `KeepIfAccountHasOpenOpportunity`. Verifies the
 *              predicate keeps touches whose account has an open opportunity
 *              and releases touches whose account has no open opportunity,
 *              including the defensive null-handling cases.
 *
 *              Uses `Database.insert(..., AccessLevel.SYSTEM_MODE)` for
 *              Engagement_Touch__c setup — matches the pattern used by
 *              `EngagementServiceImplTest`, since the seeded System Admin
 *              profile in this org does not carry FLS for every custom
 *              field on the object.
 *
 * @group Engagement
 * @see KeepIfAccountHasOpenOpportunity
 * @author David Wood
 * @since May 2026
 */
@IsTest
public without sharing class KeepIfAccountHasOpenOpportunityTest {
  @TestSetup
  static void setup() {
    TestFactory.createTestUser(true, 'System Administrator');
  }

  /**
   * @description Account has an open opportunity → keep the touch.
   */
  @IsTest
  static void testKeepsWhenAccountHasOpenOpportunity() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      Account acct = new Account(Name = 'OpenAcct');
      insert acct;

      Contact contact = new Contact(LastName = 'Doe', AccountId = acct.Id);
      insert contact;

      Opportunity opp = new Opportunity(
        Name = 'OpenOpp',
        AccountId = acct.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today().addDays(30),
        Opportunity_Name_Descriptor__c = 'Test'
      );
      insert opp;

      Engagement_Touch__c touch = new Engagement_Touch__c(
        Occurred_At__c = DateTime.now(),
        Contact__c = contact.Id,
        External_Id__c = 'TEST_KEEP_OPEN'
      );
      Database.insert(touch, AccessLevel.SYSTEM_MODE);

      KeepIfAccountHasOpenOpportunity predicate = new KeepIfAccountHasOpenOpportunity();
      predicate.primeBulkCache(new List<SObject>{ touch });
      Boolean shouldKeep = predicate.shouldKeep(touch);

      Assert.isTrue(
        shouldKeep,
        'Expected predicate to keep the touch because account has an open opportunity.'
      );
    }
  }

  /**
   * @description Account has only closed opportunities → release the touch.
   */
  @IsTest
  static void testReleasesWhenAccountHasOnlyClosedOpportunities() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      Account acct = new Account(Name = 'ClosedAcct');
      insert acct;

      Contact contact = new Contact(LastName = 'Doe', AccountId = acct.Id);
      insert contact;

      // Open insert + add OCR + close. Zelis requires a Contact Role before
      // closing and a future CloseDate at insert time.
      Opportunity opp = new Opportunity(
        Name = 'ClosedOpp',
        AccountId = acct.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today().addDays(30),
        Opportunity_Name_Descriptor__c = 'Test'
      );
      insert opp;

      OpportunityContactRole ocr = new OpportunityContactRole(
        OpportunityId = opp.Id,
        ContactId = contact.Id,
        Role = 'Decision Maker'
      );
      insert ocr;

      opp.StageName = 'Closed Lost';
      update opp;

      Engagement_Touch__c touch = new Engagement_Touch__c(
        Occurred_At__c = DateTime.now(),
        Contact__c = contact.Id,
        External_Id__c = 'TEST_RELEASE_CLOSED'
      );
      Database.insert(touch, AccessLevel.SYSTEM_MODE);

      KeepIfAccountHasOpenOpportunity predicate = new KeepIfAccountHasOpenOpportunity();
      predicate.primeBulkCache(new List<SObject>{ touch });
      Boolean shouldKeep = predicate.shouldKeep(touch);

      Assert.isFalse(
        shouldKeep,
        'Expected predicate to release the touch when only closed opportunities exist.'
      );
    }
  }

  /**
   * @description Account__c populated directly (no Contact) — short-circuit branch.
   */
  @IsTest
  static void testHonorsDirectAccountReference() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      Account acct = new Account(Name = 'DirectAcct');
      insert acct;

      Opportunity opp = new Opportunity(
        Name = 'DirectOpenOpp',
        AccountId = acct.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today().addDays(30),
        Opportunity_Name_Descriptor__c = 'Test'
      );
      insert opp;

      Engagement_Touch__c touch = new Engagement_Touch__c(
        Occurred_At__c = DateTime.now(),
        Account__c = acct.Id,
        External_Id__c = 'TEST_DIRECT_ACCT'
      );
      Database.insert(touch, AccessLevel.SYSTEM_MODE);

      KeepIfAccountHasOpenOpportunity predicate = new KeepIfAccountHasOpenOpportunity();
      predicate.primeBulkCache(new List<SObject>{ touch });
      Assert.isTrue(
        predicate.shouldKeep(touch),
        'Expected predicate to honor the direct Account__c reference and keep the touch.'
      );
    }
  }

  /**
   * @description Touch has a Contact but the Contact has no Account →
   *              predicate cannot resolve an account, conservatively keeps.
   */
  @IsTest
  static void testKeepsWhenContactHasNoAccount() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      Contact orphan = new Contact(LastName = 'Orphan');
      insert orphan;

      Engagement_Touch__c touch = new Engagement_Touch__c(
        Occurred_At__c = DateTime.now(),
        Contact__c = orphan.Id,
        External_Id__c = 'TEST_ORPHAN_CONTACT'
      );
      Database.insert(touch, AccessLevel.SYSTEM_MODE);

      KeepIfAccountHasOpenOpportunity predicate = new KeepIfAccountHasOpenOpportunity();
      predicate.primeBulkCache(new List<SObject>{ touch });
      Assert.isTrue(
        predicate.shouldKeep(touch),
        'Touch with a Contact lacking an Account should be conservatively kept.'
      );
    }
  }

  /**
   * @description Null record → conservative keep.
   */
  @IsTest
  static void testNullRecordIsConservativelyKept() {
    // Pure in-memory predicate dispatch; runAs satisfies PMD without changing
    // semantics (no SOQL/DML touches the user context).
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      KeepIfAccountHasOpenOpportunity predicate = new KeepIfAccountHasOpenOpportunity();
      Assert.isTrue(
        predicate.shouldKeep(null),
        'Null record should be conservatively kept.'
      );
    }
  }

  /**
   * @description Touch with no Contact and no Account → conservative keep.
   */
  @IsTest
  static void testTouchWithNoAnchorsIsConservativelyKept() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      Engagement_Touch__c touch = new Engagement_Touch__c(
        Occurred_At__c = DateTime.now(),
        External_Id__c = 'TEST_NO_ANCHOR'
      );
      Database.insert(touch, AccessLevel.SYSTEM_MODE);

      KeepIfAccountHasOpenOpportunity predicate = new KeepIfAccountHasOpenOpportunity();
      predicate.primeBulkCache(new List<SObject>{ touch });
      Assert.isTrue(
        predicate.shouldKeep(touch),
        'Touch with no Contact and no Account should be conservatively kept.'
      );
    }
  }
}
