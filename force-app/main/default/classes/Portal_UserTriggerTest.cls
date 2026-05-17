@isTest
public class Portal_UserTriggerTest {
  private static final List<String> communityProfileNameSet = System.Label.Portal_Zelis_Portal_Custom_Community_Profile.split(
    ','
  );

  // BSKY-201 parallel-safety: every username/email/account name is uniquified per test method/class
  // to eliminate org-wide unique-constraint row locks. Suffix is regenerated on demand so methods
  // don't share a tag.
  private static String uniqueTag() {
    return String.valueOf(Crypto.getRandomLong()).substring(1, 9);
  }

  @TestSetup
  private static void createdData() {
    String PROVIDER_ACCOUNT_RECORDTYPEID = AccountService.getInstance()
      .PROVIDER_RECORDTYPEID;
    String AGENT_CASE_RECORDTYPEID = Schema.SobjectType.Case.getRecordTypeInfosByDeveloperName()
      .get('ZESP_IE_Case')
      .getRecordTypeId();
    String tag = uniqueTag();
    List<Contact> contactList = new List<Contact>();
    List<Account> accountList = new List<Account>();

    // Portal Account
    Account testAccount = AccountTestData.getInstance()
      .createAccount(PROVIDER_ACCOUNT_RECORDTYPEID, false);
    testAccount.Name = 'Portal Account ' + tag;
    accountList.add(testAccount);

    // Networking Account
    Account networkAccount = AccountTestData.getInstance()
      .createAccount(PROVIDER_ACCOUNT_RECORDTYPEID, false);
    networkAccount.Name = 'Network Account ' + tag;
    accountList.add(networkAccount);
    insert accountList;

    contactList.add(
      ContactTestData.getInstance()
        .createContact(
          accountList[0].Id,
          'Charlie',
          'Brown-' + tag,
          'cb-' + tag + '@testinvalid.com',
          false
        )
    );
    contactList.add(
      ContactTestData.getInstance()
        .createContact(
          accountList[0].Id,
          'Charlie',
          'Brown-' + tag + 'b',
          'cb-' + tag + 'b@testinvalid.com',
          false
        )
    );
    contactList.add(
      ContactTestData.getInstance()
        .createContact(
          accountList[1].Id,
          'Charlie',
          'Brown-' + tag + 'c',
          'cb-' + tag + 'c@testinvalid.com',
          false
        )
    );
    insert contactList;

    Case portalCase = CaseTestData.getInstance()
      .createCase(
        accountList[0].Id,
        contactList[0].Id,
        contactList[0].Email,
        AGENT_CASE_RECORDTYPEID,
        false
      );
    portalCase.Portal_Show_In_Community__c = true;
    insert portalCase;
  }

  @isTest
  private static void insertUserTest() {
    Test.startTest();
    insert getUserList();
    Test.stopTest();
  }

  // Helper method to create users — each call generates a fresh tag so parallel methods don't collide
  private static List<User> getUserList() {
    Profile communityProfile = [
      SELECT Id
      FROM Profile
      WHERE Name IN :communityProfileNameSet
      LIMIT 1
    ];
    List<Contact> contactList = [SELECT Id FROM Contact];
    String tag = uniqueTag();
    List<User> userList = new List<User>();
    for (Integer index = 0; index < 2; index++) {
      userList.add(
        new User(
          Alias = 'standt',
          Email = 'portal12-' + tag + '@testorg.com',
          EmailEncodingKey = 'UTF-8',
          LastName = 'Test',
          LanguageLocaleKey = 'en_US',
          LocaleSidKey = 'en_US',
          ProfileId = communityProfile.Id,
          ContactId = contactList[index].Id,
          TimeZoneSidKey = 'America/Los_Angeles',
          UserName = 'portal-' + tag + '-' + index + '@testorg.com'
        )
      );
    }
    return userList;
  }

  @isTest
  private static void Portal_UserTriggerHandlerMethods() {
    Portal_UserTriggerHandler handler = new Portal_UserTriggerHandler();
    Test.startTest();
    handler.beforeUpdate(
      new List<SObject>(),
      new Map<Id, SObject>(),
      new List<SObject>(),
      new Map<Id, SObject>()
    );
    handler.afterUpdate(
      new List<SObject>(),
      new Map<Id, SObject>(),
      new List<SObject>(),
      new Map<Id, SObject>()
    );
    handler.beforeDelete(new List<SObject>(), new Map<Id, SObject>());
    handler.afterDelete(new List<SObject>(), new Map<Id, SObject>());
    handler.afterUndelete(new List<SObject>(), new Map<Id, SObject>());
    Test.stopTest();
  }

  /**
   * @description Test method to verify the updatePortalContact invocable method functionality.
   */
  @isTest
  static void testSingleUpdatePortalContact() {
    Profile communityProfile = [
      SELECT Id
      FROM Profile
      WHERE Name IN :communityProfileNameSet
      LIMIT 1
    ];
    List<Contact> contactList = [
      SELECT Id, LastName, Salesforce_Portal_Contact__c
      FROM Contact
    ];
    String tag = uniqueTag();
    User testUser = new User(
      Alias = 'tuser',
      Email = 'testuser-' + tag + '@test.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'TestUser',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = communityProfile.Id,
      ContactId = contactList[0].Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = 'testuser-' +
        tag +
        '.' +
        DateTime.now().getTime() +
        '@test.com'
    );
    insert testUser;
    Portal_UserTriggerHelper.UpdatePortalContactInput inp = new Portal_UserTriggerHelper.UpdatePortalContactInput();
    inp.userId = testUser.Id;
    inp.isPortalContact = true;
    Test.startTest();
    Portal_UserTriggerHelper.updatePortalContact(
      new List<Portal_UserTriggerHelper.UpdatePortalContactInput>{ inp }
    );
    Test.stopTest();
    List<Contact> contacts = [
      SELECT Id, Salesforce_Portal_Contact__c
      FROM Contact
      WHERE Id = :testUser.ContactId
      LIMIT 1
    ];
    Assert.areEqual(false, contacts.isEmpty(), 'Contact must exist.');
    Assert.areEqual(
      true,
      contacts[0].Salesforce_Portal_Contact__c,
      'Contact Portal field should be TRUE'
    );
  }
}
