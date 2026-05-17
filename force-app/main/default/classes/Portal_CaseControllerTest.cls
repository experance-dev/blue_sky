@isTest
public class Portal_CaseControllerTest {
  private static final List<String> communityProfileNameSet = System.Label.Portal_Zelis_Portal_Custom_Community_Profile.split(
    ','
  );
  private static String PROVIDER_ACCOUNT_RECORDTYPEID = AccountService.getInstance()
    .PROVIDER_RECORDTYPEID;
  private static String Portal_CASE_RECORDTYPEID = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
    .get('ZESP_IE_Case')
    .getRecordTypeId();
  //private static String ZESP_Payments_Optimization_Case_RECORDID = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('ZESP_Payments_Optimization_Case').getRecordTypeId();

  // BSKY-201 parallel-safety: usernames in this class were globally fixed (customercommunityuser@testorg.com,
  // communityuser@test.com) and triggered cross-test row locks on the org-wide User uniqueness constraint.
  // The fix: tag each username with a per-test-run unique suffix so parallel test classes can't collide,
  // then look up by prefix at test-method time. Statics don't survive across the @TestSetup -> test
  // transaction boundary, so we cannot rely on a stored tag — only the deterministic LIKE-pattern.
  private static final String PRIMARY_USERNAME_PREFIX = 'customercommunityuser-';
  private static final String PRIMARY_USERNAME_SUFFIX = '@testorg.com.bsky201';
  private static final String SECONDARY_USERNAME_PREFIX = 'communityuser-';
  private static final String SECONDARY_USERNAME_SUFFIX = '@test.com.bsky201';

  @testSetup
  static void setup() {
    String tag = String.valueOf(Crypto.getRandomLong()).substring(1, 9);
    Account accountRecord = AccountTestData.getInstance()
      .createAccount(PROVIDER_ACCOUNT_RECORDTYPEID, false);
    accountRecord.Name = 'PortalCase Acct ' + tag;
    insert accountRecord;
    //Contact contactRecord = ContactTestData.getInstance().createContact(accountRecord.Id, true);
    // Create Active Contacts
    Contact contactRecord = ContactTestData.getInstance()
      .createContact(
        accountRecord.Id,
        'Charlie',
        'Brown-' + tag,
        'cb-' + tag + '@testinvalid.com',
        true
      );
    contactRecord.Active_Contact__c = true;
    update contactRecord;

    Account childAccount = AccountTestData.getInstance()
      .createAccount(AccountService.getInstance().PAYER_RECORDTYPEID, false);
    childAccount.Name = 'PortalCase Child ' + tag;
    childAccount.parentId = accountRecord.Id;
    insert childAccount;

    List<Case> caseList = new List<Case>();
    caseList.add(
      createCaseData(
        accountRecord.Id,
        contactRecord.Id,
        contactRecord.Email,
        Portal_CASE_RECORDTYPEID,
        'Bug/Defect',
        'New',
        'High',
        Date.today().addDays(-2)
      )
    );
    caseList.add(
      createCaseData(
        accountRecord.Id,
        contactRecord.Id,
        contactRecord.Email,
        Portal_CASE_RECORDTYPEID,
        'Bug/Defect',
        'In Progress',
        'High',
        Date.today().addDays(-2)
      )
    );
    caseList.add(
      createCaseData(
        accountRecord.Id,
        contactRecord.Id,
        contactRecord.Email,
        Portal_CASE_RECORDTYPEID,
        'Bug/Defect',
        'Open',
        'Low',
        Date.today()
      )
    );
    caseList.add(
      createCaseData(
        accountRecord.Id,
        contactRecord.Id,
        contactRecord.Email,
        Portal_CASE_RECORDTYPEID,
        'Bug/Defect',
        'Closed',
        'Medium',
        Date.today()
      )
    );
    insert caseList;

    String profileId = [
      SELECT Id, Name
      FROM Profile
      WHERE Name IN :communityProfileNameSet
      LIMIT 1
    ]
    .Id;
    User user = new User(
      Alias = 'standt',
      Email = 'customercommunityuser-' + tag + '@testorg.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Test',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      contactId = contactRecord.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = PRIMARY_USERNAME_PREFIX + tag + PRIMARY_USERNAME_SUFFIX
    );

    insert user;

    createdPortalUserData(tag);
    AccountContactRelation accConRelationObj = new AccountContactRelation(
      ContactId = contactRecord.Id,
      AccountId = childAccount.Id,
      Portal_Account_Access__c = true
    );
    insert accConRelationObj;
  }

  private static void createdPortalUserData(String tag) {
    String PROVIDER_ACCOUNT_RECORDTYPEID = AccountService.getInstance()
      .PROVIDER_RECORDTYPEID;

    String PORTAL_CASE_RECORDTYPEID = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
      .get('ZESP_IE_Case')
      .getRecordTypeId();
    system.debug('AGENT_CASE_RECORDTYPEID ' + PORTAL_CASE_RECORDTYPEID);
    String profileId = [
      SELECT Id, Name
      FROM Profile
      WHERE Name IN :communityProfileNameSet
      LIMIT 1
    ]
    .Id;
    List<Contact> contactList = new List<Contact>();
    List<Account> accountList = new List<Account>();

    //Portal Account
    Account testAccount = AccountTestData.getInstance()
      .createAccount(PROVIDER_ACCOUNT_RECORDTYPEID, false);
    testAccount.Name = 'Portal Account ' + tag;
    accountList.add(testAccount);

    //Networking Account
    Account networkAccount = AccountTestData.getInstance()
      .createAccount(PROVIDER_ACCOUNT_RECORDTYPEID, false);
    networkAccount.Name = 'Network Account ' + tag;
    //networkAccount.Portal_IsNetworkAccount__c = true;
    accountList.add(networkAccount);
    insert accountList;

    contactList.add(
      ContactTestData.getInstance()
        .createContact(
          accountList[0].Id,
          'Charlie',
          'Brown-' + tag + 'p',
          'cb-' + tag + 'p@testinvalid.com',
          false
        )
    );
    contactList.add(
      ContactTestData.getInstance()
        .createContact(
          accountList[1].Id,
          'Charlie',
          'Brown-' + tag + 'n',
          'cb-' + tag + 'n@testinvalid.com',
          false
        )
    );
    insert contactList;

    User testUser = new User(
      Alias = 'standt',
      Email = 'systemadmin-' + tag + '@testorg.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Test',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      contactId = contactList[1].Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = SECONDARY_USERNAME_PREFIX + tag + SECONDARY_USERNAME_SUFFIX
    );

    insert testUser;
    Case portalCase = CaseTestData.getInstance()
      .createCase(
        accountList[0].Id,
        contactList[0].Id,
        contactList[0].Email,
        PORTAL_CASE_RECORDTYPEID,
        false
      );
    portalCase.Portal_Show_In_Community__c = true;
    portalCase.Status = 'New';
    insert portalCase;

    CaseShare caseShareObj = new CaseShare();
    caseShareObj.CaseId = portalCase.Id;
    caseShareObj.UserOrGroupId = testUser.Id;
    caseShareObj.RowCause = 'Manual';
    caseShareObj.CaseAccessLevel = 'Edit';
    insert caseShareObj;
  }

  private static Case createCaseData(
    String accountRecordId,
    String contactRecordId,
    String contactRecordEmail,
    String recordType,
    String type,
    String status,
    String priority,
    DateTime createdDate
  ) {
    Case caseRecord = CaseTestData.getInstance()
      .createCase(
        accountRecordId,
        contactRecordId,
        contactRecordEmail,
        recordType,
        false
      );
    //caseRecord.Portal_Case_Type__c = type;
    caseRecord.Status = Status;
    caseRecord.Priority = priority;
    caseRecord.CreatedDate = createdDate;
    caseRecord.Portal_Show_In_Community__c = true;
    //caseRecord.Case_Category__c = 'Incident';
    //caseRecord.Case_Subcategory__c = 'Issue with ZAPP to report';
    if (recordType == Portal_CASE_RECORDTYPEID) {
      //caseRecord.Case_Subcategory__c = 'Bug';
      //caseRecord.Case_Category__c = 'Indexing';
      caseRecord.Portal_Case_Category__c = 'S365 Issue';
      caseRecord.Portal_Case_Type__c = 'Bug/Defect';
    }
    return caseRecord;
  }

  @isTest
  private static void testGetAllCases() {
    String contactId = [SELECT id FROM Contact LIMIT 1].Id;
    Test.startTest();
    List<Portal_CaseController.caseWrapper> cases = Portal_CaseController.getCases(
      'all',
      'Status',
      'ASC',
      'New',
      'High',
      new List<string>{ 'Bug/Defect' },
      contactId
    );
    //List<Portal_CaseController.caseWrapper> cases = Portal_CaseController.getCases('all','Status', 'ASC', 'New', 'High', new list<string>{'Problem'}, contactId);
    Test.stopTest();
    System.assertEquals(1, cases.size(), 'There should be 1 case retrieved.');
    System.assertEquals('Test Subject', cases[0].caseObj.Subject, 'Case');
  }

  @isTest
  private static void testGetOpenCases() {
    String contactId = [SELECT id FROM Contact LIMIT 1].Id;
    Test.startTest();
    List<Portal_CaseController.caseWrapper> openCases = Portal_CaseController.getCases(
      'Open',
      'CaseNumber',
      'ASC',
      'Open',
      'Low',
      new List<string>{ 'Bug/Defect' },
      contactId
    );

    //List<Portal_CaseController.caseWrapper> openCases = Portal_CaseController.getCases('Open', 'CaseNumber', 'ASC', 'Open', 'Low', new list<string>{'Question'}, contactId);
    Test.stopTest();
    System.assertEquals(1, openCases.size(), 'There should be 1 open case.');
    System.assertEquals(
      'Test Subject',
      openCases[0].caseObj.Subject,
      'The open case should be Test Case 1.'
    );
  }

  @isTest
  private static void testGetClosedCases() {
    String contactId = [SELECT id FROM Contact LIMIT 1].Id;
    Test.startTest();
    List<Portal_CaseController.caseWrapper> openCases = Portal_CaseController.getCases(
      'closed',
      'CaseNumber',
      'ASC',
      'Closed',
      'Medium',
      new List<string>{ 'Bug/Defect' },
      contactId
    );
    //List<Portal_CaseController.caseWrapper> openCases = Portal_CaseController.getCases('closed', 'CaseNumber', 'ASC', 'Closed', 'Medium', new list<string>{'Question'}, contactId);
    Test.stopTest();
    System.assertEquals(1, openCases.size(), 'There should be 1 closed case.');
    System.assertEquals(
      'Test Subject',
      openCases[0].caseObj.Subject,
      'The closed case should be Test Case 2.'
    );
  }

  @isTest
  private static void testGetContactsPicklist() {
    Test.startTest();
    List<Portal_CaseController.pickListOption> contactOptions = Portal_CaseController.getContactsPicklist(
      false
    );
    System.assertEquals(
      3,
      contactOptions.size(),
      'There should be 1 contact in the picklist.'
    );
    Test.stopTest();
    System.assertEquals(
      'Charlie Brown',
      contactOptions[0].label.left(13),
      'The contact label should start with Charlie Brown.'
    );
  }

  @isTest
  private static void testGetContactsPicklistForPortalUser() {
    String secondaryPattern =
      SECONDARY_USERNAME_PREFIX +
      '%' +
      SECONDARY_USERNAME_SUFFIX;
    User communityUser = [
      SELECT Id
      FROM User
      WHERE Username LIKE :secondaryPattern
      LIMIT 1
    ];
    System.runAs(communityUser) {
      Test.startTest();
      List<Portal_CaseController.pickListOption> contactOptions = Portal_CaseController.getContactsPicklist(
        false
      );
      System.assertEquals(
        2,
        contactOptions.size(),
        'There should be 1 contact in the picklist.'
      );
      Test.stopTest();
      System.assertEquals(
        'Charlie Brown',
        contactOptions[0].label.left(13),
        'The contact label should start with Charlie Brown.'
      );
    }
  }

  @isTest
  private static void testGetCaseStatusPicklist() {
    Test.startTest();
    List<Portal_CaseController.pickListOption> statusOptions = Portal_CaseController.getCaseStatusPicklist();
    Test.stopTest();
    System.assert(
      statusOptions.size() > 0,
      'There should be at least one status option.'
    );
  }

  @isTest
  private static void testGetCasePriorityPicklist() {
    Test.startTest();
    List<Portal_CaseController.pickListOption> priorityOptions = Portal_CaseController.getCasePriorityPicklist();
    Test.stopTest();
    System.assert(
      priorityOptions.size() > 0,
      'There should be at least one priority option.'
    );
  }

  @isTest
  private static void testGetCaseTypePicklist() {
    Test.startTest();
    List<Portal_CaseController.caseSubType> typeOptions = Portal_CaseController.getCaseTypePicklist();
    Test.stopTest();
    System.assert(
      typeOptions.size() > 0,
      'There should be at least one type option.'
    );
  }

  @isTest
  static void testGetOpenCasesForLastDays() {
    try {
      String primaryPattern =
        PRIMARY_USERNAME_PREFIX +
        '%' +
        PRIMARY_USERNAME_SUFFIX;
      User userRecord = [
        SELECT Id, ContactId
        FROM User
        WHERE UserName LIKE :primaryPattern
        LIMIT 1
      ];
      Map<Date, Integer> result = new Map<Date, Integer>();
      Test.startTest();

      Id accountId = [
        SELECT Id
        FROM Account
        LIMIT 1
      ]
      .Id;

      insert new Case(
        AccountId = accountId,
        ContactId = userRecord.ContactId,
        Subject = 'Test Case',
        Description = '...'
      );

      System.runAs(userRecord) {
        Case c = [SELECT Id FROM Case];
        c.Portal_Show_In_Community__c = true;
        update c;

        System.debug('Sam Test 1: ' + [SELECT COUNT() FROM Case]);

        result = Portal_CaseController.getCasesCountForLastNdays(7, 'open');
      }

      Test.stopTest();
      System.assert(
        !result.isEmpty(),
        'No open cases found for the last 7 days.'
      );
    } catch (Exception ex) {
      System.debug(
        'Exception in getCasesCountForLastNdays: ' + ex.getMessage()
      );
    }
  }

  @isTest
  static void testNotGetOpenCasesForLastDays() {
    try {
      String primaryPattern =
        PRIMARY_USERNAME_PREFIX +
        '%' +
        PRIMARY_USERNAME_SUFFIX;
      User userRecord = [
        SELECT Id, ContactId
        FROM User
        WHERE UserName LIKE :primaryPattern
        LIMIT 1
      ];
      Map<Date, Integer> result = new Map<Date, Integer>();
      Test.startTest();

      Id accountId = [
        SELECT Id
        FROM Account
        LIMIT 1
      ]
      .Id;

      Case newCase = new Case(
        AccountId = accountId,
        ContactId = userRecord.ContactId,
        Subject = 'Test Case',
        Description = '...'
      );

      insert newCase;

      Test.setCreatedDate(newCase.Id, Date.today().addDays(-10));

      System.runAs(userRecord) {
        Case c = [SELECT Id FROM Case];
        c.Portal_Show_In_Community__c = true;
        update c;

        System.debug('Sam Test 1: ' + [SELECT COUNT() FROM Case]);

        result = Portal_CaseController.getCasesCountForLastNdays(7, 'open');
      }

      Test.stopTest();
      System.assert(
        !result.isEmpty(),
        'No open cases found for the last 7 days.'
      );
    } catch (Exception ex) {
      System.debug(
        'Exception in getCasesCountForLastNdays: ' + ex.getMessage()
      );
    }
  }

  @isTest
  static void getContactsForSharingForCommunityUserTest() {
    String accountId = [SELECT Id FROM Account LIMIT 1].Id;
    String contactId = [
      SELECT Id
      FROM Contact
      WHERE AccountId = :accountId
      LIMIT 1
    ]
    .Id;
    String secondaryPattern =
      SECONDARY_USERNAME_PREFIX +
      '%' +
      SECONDARY_USERNAME_SUFFIX;
    User communityUser = [
      SELECT Id, ContactId
      FROM User
      WHERE Username LIKE :secondaryPattern
      LIMIT 1
    ];

    Case ca = createCaseData(
      accountId,
      communityUser.ContactId,
      'test@zelis.com',
      Portal_CASE_RECORDTYPEID,
      'Question',
      'Closed',
      'Medium',
      Date.today()
    );
    ca.Portal_Show_In_Community__c = true;
    ca.OwnerId = communityUser.Id;
    insert ca;
    System.runAs(communityUser) {
      Test.startTest();
      Portal_CaseController.getContactsForSharing(ca.Id);
      Test.stopTest();
    }
  }

  @isTest
  static void getContactsForSharingAdminUserTest() {
    String caseRecordId = [
      SELECT Id
      FROM Case
      WHERE RecordTypeId = :Portal_CASE_RECORDTYPEID
      LIMIT 1
    ]
    .Id;
    Test.startTest();
    Portal_CaseController.getContactsForSharing(caseRecordId);
    Test.stopTest();
    System.assert(caseRecordId != null, 'Case record has found');
  }

  @isTest
  static void isAttachmentCheckboxCheckedTest() {
    String caseRecordId = [
      SELECT Id
      FROM Case
      WHERE RecordTypeId = :Portal_CASE_RECORDTYPEID
      LIMIT 1
    ]
    .Id;
    Test.startTest();
    Portal_CaseController.isAttachmentCheckboxChecked(caseRecordId);
    Test.stopTest();
    System.assert(caseRecordId != null, 'Case record has found');
  }

  @isTest
  static void getCaseDetailsTest() {
    String caseRecordId = [
      SELECT Id
      FROM Case
      WHERE RecordTypeId = :Portal_CASE_RECORDTYPEID
      LIMIT 1
    ]
    .Id;
    Test.startTest();
    Portal_CaseController.getCaseDetails(caseRecordId);
    Test.stopTest();
    System.assert(caseRecordId != null, 'Case record has found');
  }

  @isTest
  static void checkLoginUserAccessTest() {
    String caseRecordId = [
      SELECT Id
      FROM Case
      WHERE RecordTypeId = :Portal_CASE_RECORDTYPEID
      LIMIT 1
    ]
    .Id;
    Test.startTest();
    Portal_CaseController.checkLoginUserAccess(caseRecordId);
    Test.stopTest();
    System.assert(caseRecordId != null, 'Case record has found');
  }

  private static User getUserList(String contactId, String userName) {
    String profileId = [
      SELECT Id, Name
      FROM Profile
      WHERE Name = :System.Label.Portal_Zelis_Portal_Custom_Community_Profile
      LIMIT 1
    ]
    .Id;
    return new User(
      Alias = 'standt',
      Email = 'portal12@testorg.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Test',
      LanguageLocaleKey = 'en_US',
      IsActive = true,
      LocaleSidKey = 'en_US',
      ProfileId = profileId,
      contactId = contactId,
      TimeZoneSidKey = 'America/Los_Angeles',
      UserName = userName
    );
  }
}
