/**
 * @description Test class for `KeepIfContactIsOnOpenOpportunityTeam`.
 *              Verifies the predicate keeps touches whose contact is on an
 *              OpportunityContactRole for an open Opportunity, and releases
 *              touches whose contact is not on any open OCR.
 *
 *              Uses `Database.insert(..., AccessLevel.SYSTEM_MODE)` for
 *              `Engagement_Touch__c` setup — see the same comment on
 *              `KeepIfAccountHasOpenOpportunityTest`.
 *
 * @group Engagement
 * @see KeepIfContactIsOnOpenOpportunityTeam
 * @author David Wood
 * @since May 2026
 */
@IsTest
public without sharing class KeepIfContactIsOnOpenOpportunityTeamTest {
  @TestSetup
  static void setup() {
    TestFactory.createTestUser(true, 'System Administrator');
  }

  /**
   * @description Contact has an OCR on an open opportunity → keep.
   */
  @IsTest
  static void testKeepsWhenContactIsOnOpenOcr() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      Account acct = new Account(Name = 'OcrAcct');
      insert acct;

      Contact contact = new Contact(LastName = 'OnTeam', AccountId = acct.Id);
      insert contact;

      Opportunity opp = new Opportunity(
        Name = 'OcrOpenOpp',
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

      Engagement_Touch__c touch = new Engagement_Touch__c(
        Occurred_At__c = DateTime.now(),
        Contact__c = contact.Id,
        External_Id__c = 'TEST_KEEP_OCR'
      );
      Database.insert(touch, AccessLevel.SYSTEM_MODE);

      KeepIfContactIsOnOpenOpportunityTeam predicate = new KeepIfContactIsOnOpenOpportunityTeam();
      Assert.isTrue(
        predicate.shouldKeep(touch),
        'Contact on open OCR should keep the touch.'
      );
    }
  }

  /**
   * @description Contact has no OCRs → release.
   */
  @IsTest
  static void testReleasesWhenContactHasNoOcr() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      Account acct = new Account(Name = 'NoOcrAcct');
      insert acct;

      Contact contact = new Contact(LastName = 'NoTeam', AccountId = acct.Id);
      insert contact;

      Engagement_Touch__c touch = new Engagement_Touch__c(
        Occurred_At__c = DateTime.now(),
        Contact__c = contact.Id,
        External_Id__c = 'TEST_RELEASE_OCR'
      );
      Database.insert(touch, AccessLevel.SYSTEM_MODE);

      KeepIfContactIsOnOpenOpportunityTeam predicate = new KeepIfContactIsOnOpenOpportunityTeam();
      Assert.isFalse(
        predicate.shouldKeep(touch),
        'Contact with no OCRs should release the touch.'
      );
    }
  }

  /**
   * @description Contact has only OCRs on closed opportunities → release.
   */
  @IsTest
  static void testReleasesWhenContactOnlyOnClosedOcr() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      Account acct = new Account(Name = 'ClosedOcrAcct');
      insert acct;

      Contact contact = new Contact(
        LastName = 'ClosedOnly',
        AccountId = acct.Id
      );
      insert contact;

      // Open insert + add OCR + then close. Zelis requires a Contact Role
      // before allowing the Closed transition; Close_Date must also be future
      // at insert time per "Close_Date_Must_be_a_Future_Date_2".
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

      opp.StageName = 'Closed Won';
      update opp;

      Engagement_Touch__c touch = new Engagement_Touch__c(
        Occurred_At__c = DateTime.now(),
        Contact__c = contact.Id,
        External_Id__c = 'TEST_RELEASE_CLOSED_OCR'
      );
      Database.insert(touch, AccessLevel.SYSTEM_MODE);

      KeepIfContactIsOnOpenOpportunityTeam predicate = new KeepIfContactIsOnOpenOpportunityTeam();
      Assert.isFalse(
        predicate.shouldKeep(touch),
        'Contact only on closed OCRs should release the touch.'
      );
    }
  }

  /**
   * @description Null record → conservative keep.
   */
  @IsTest
  static void testNullRecordIsConservativelyKept() {
    KeepIfContactIsOnOpenOpportunityTeam predicate = new KeepIfContactIsOnOpenOpportunityTeam();
    Assert.isTrue(
      predicate.shouldKeep(null),
      'Null record should be conservatively kept.'
    );
  }

  /**
   * @description Touch with no Contact → conservative keep.
   */
  @IsTest
  static void testTouchWithNoContactIsConservativelyKept() {
    System.runAs(TestFactory.getTestUser('System Administrator')) {
      Engagement_Touch__c touch = new Engagement_Touch__c(
        Occurred_At__c = DateTime.now(),
        External_Id__c = 'TEST_NO_CONTACT'
      );
      Database.insert(touch, AccessLevel.SYSTEM_MODE);

      KeepIfContactIsOnOpenOpportunityTeam predicate = new KeepIfContactIsOnOpenOpportunityTeam();
      Assert.isTrue(
        predicate.shouldKeep(touch),
        'Touch with no Contact should be conservatively kept.'
      );
    }
  }
}
