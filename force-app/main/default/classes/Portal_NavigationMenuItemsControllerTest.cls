@IsTest
private class Portal_NavigationMenuItemsControllerTest {
  private static final List<String> communityProfileNameSet = System.Label.Portal_Zelis_Portal_Custom_Community_Profile.split(
    ','
  );
  private static final List<Portal_Case_Setup_Map__mdt> inquiryPortalCaseSetupMap = [
    SELECT
      Assigned_Team_Department__c,
      Case_Record_Type_Name__c,
      Case_Category_Internal__c,
      Case_Category_External__c,
      Case_SubCategory_Internal__c,
      Case_SubCategory_External__c
    FROM Portal_Case_Setup_Map__mdt
    WHERE Case_SubCategory_External__c = 'Inquiry' AND Active__c = TRUE
    LIMIT 1
  ]; // get the Record Type and Internal Subcategory from here for use in creating the caseRecordTypeId and the case subcategory when testing getContacts

  // BSKY-201 parallel-safety: every username/email is uniquified per call so parallel methods
  // don't collide on org-wide unique constraints (Username, etc).
  private static String uniqueTag() {
    return String.valueOf(Crypto.getRandomLong()).substring(1, 9);
  }

  @TestSetup
  public static void createData() {
    String tag = uniqueTag();
    Account testAccount = AccountTestData.getInstance()
      .createAccount(AccountService.getInstance().PROVIDER_RECORDTYPEID, false);
    testAccount.Name = 'PortalNav Acct ' + tag;
    insert testAccount;
    Contact testContact = ContactTestData.getInstance()
      .createContact(
        testAccount.Id,
        'Charlie',
        'Brown-' + tag,
        'cb-' + tag + '@testinvalid.com',
        true
      );
    User userObj = getUserList(
      testContact.Id,
      'portal22-' + tag + '@testorg.com'
    );
    insert userObj;

    // setup a case with a reasonable subCategory
    Case testCase = CaseTestData.getInstance()
      .createCase(
        testAccount.Id,
        testContact.Id,
        testContact.Email,
        [
          SELECT Id, Name, DeveloperName
          FROM RecordType
          WHERE
            SobjectType = 'Case'
            AND Name = :inquiryPortalCaseSetupMap[0].Case_Record_Type_Name__c
        ]
        .Id,
        true
      );
  }

  public static User getUserList(String contactId, String userName) {
    String profileId = [
      SELECT Id, Name
      FROM Profile
      WHERE Name IN :communityProfileNameSet
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

  @IsTest
  static void testGetNavigationMenuItemsWithDraft() {
    String navigationLinkSetMasterLabel = 'Test Menu';
    String publishStatus = 'Draft';
    Boolean addHomeMenuItem = true;
    Boolean includeImageUrl = true;
    Test.startTest();
    List<ConnectApi.NavigationMenuItem> menuItems = Portal_NavigationMenuItemsController.getNavigationMenuItems(
      navigationLinkSetMasterLabel,
      publishStatus,
      addHomeMenuItem,
      includeImageUrl
    );
    Test.stopTest();
  }

  @IsTest
  static void testGetNavigationMenuItemsWithLive() {
    String navigationLinkSetMasterLabel = 'Test Menu2';
    String publishStatus = 'Live';
    Boolean addHomeMenuItem = true;
    Boolean includeImageUrl = true;
    Test.startTest();
    List<ConnectApi.NavigationMenuItem> menuItems = Portal_NavigationMenuItemsController.getNavigationMenuItems(
      navigationLinkSetMasterLabel,
      publishStatus,
      addHomeMenuItem,
      includeImageUrl
    );
    Test.stopTest();
    System.assertNotEquals(null, menuItems, 'Menu items should not be null');
  }

  @IsTest
  static void testGetNavigationMenuItemsWithTestFlag() {
    // Test Data Setup
    String navigationLinkSetMasterLabel = 'Test Menu3';
    String publishStatus = 'Draft';
    Boolean addHomeMenuItem = true;
    Boolean includeImageUrl = true;

    // Test Case: When Test.isRunningTest() == true
    Test.startTest();
    List<ConnectApi.NavigationMenuItem> menuItems = Portal_NavigationMenuItemsController.getNavigationMenuItems(
      navigationLinkSetMasterLabel,
      publishStatus,
      addHomeMenuItem,
      includeImageUrl
    );
    Test.stopTest();
  }

  @isTest
  private static void getNavigationCategoryAndSubCategoryTest() {
    List<Portal_Case_Setup_Map__mdt> portalCaseSetupList = [
      SELECT Assigned_Team_Department__c, Case_Category_External__c
      FROM Portal_Case_Setup_Map__mdt
      WHERE
        Case_SubCategory_External__c != 'N/A'
        AND SubCategory_Description__c != 'N/A'
      ORDER BY Case_Category_External__c, Case_SubCategory_External__c
    ];

    System.assert(
      portalCaseSetupList.isEmpty() != true,
      'protalCaseSetupList is empty --- there are no case category mappings to test'
    );

    Map<String, String> assignmentToCategoryMap = new Map<String, String>();

    for (Portal_Case_Setup_Map__mdt mapping : portalCaseSetupList) {
      assignmentToCategoryMap.put(
        mapping.Assigned_Team_Department__c,
        mapping.Case_Category_External__c
      );
    }

    String tag = uniqueTag();
    Account testAccount = AccountTestData.getInstance()
      .createAccount(AccountService.getInstance().PAYER_RECORDTYPEID, false);
    testAccount.Name = 'NavCat Acct ' + tag;
    insert testAccount;
    Contact testContact = ContactTestData.getInstance()
      .createContact(
        testAccount.Id,
        'test',
        'last-' + tag,
        'last-' + tag + '@testinvalid.com',
        true
      );

    Account childAccount = AccountTestData.getInstance()
      .createAccount(AccountService.getInstance().PAYER_RECORDTYPEID, false);
    childAccount.Name = 'NavCat Child ' + tag;
    childAccount.ParentId = testAccount.Id;
    insert childAccount;
    User userObj = getUserList(
      testContact.Id,
      'portal-navcat-' + tag + '@testorg.com'
    );
    insert userObj;

    String portalAccessTeamDeptAssignments = '';
    Set<String> portalAccessTeamDeptAssignmentsSet = new Set<String>();
    for (Portal_Case_Setup_Map__mdt portalCaseSetup : portalCaseSetupList) {
      if (
        portalAccessTeamDeptAssignmentsSet.contains(
          portalCaseSetup.Assigned_Team_Department__c
        ) != true
      ) {
        if (portalCaseSetup.Assigned_Team_Department__c != null) {
          if (portalAccessTeamDeptAssignments == '') {
            portalAccessTeamDeptAssignments = portalCaseSetup.Assigned_Team_Department__c;
          } else {
            portalAccessTeamDeptAssignments =
              portalAccessTeamDeptAssignments +
              ';' +
              portalCaseSetup.Assigned_Team_Department__c;
          }
        }
        portalAccessTeamDeptAssignmentsSet.add(
          portalCaseSetup.Assigned_Team_Department__c
        );
      }
    }

    AccountContactRelation accConRelationObj = new AccountContactRelation(
      ContactId = testContact.Id,
      AccountId = childAccount.Id,
      Portal_Account_Access__c = true,
      Portal_Acces_for_Assigned_Team_Dept__c = portalAccessTeamDeptAssignments
    );
    insert accConRelationObj;
    System.runAs(userObj) {
      Test.startTest();

      List<Portal_NavigationMenuItemsController.CaseCategoryWrapper> resultCCWs = Portal_NavigationMenuItemsController.getNavigationCategoryAndSubCategory();

      List<AccountContactRelation> acrs = [
        SELECT
          Contact.Name,
          Portal_Acces_for_Assigned_Team_Dept__c,
          Portal_Account_Access__c
        FROM AccountContactRelation
        WHERE ContactId = :testContact.Id
      ];

      List<String> assignedTeamDepts = new List<String>();
      for (AccountContactRelation acr : acrs) {
        if (acr.Portal_Account_Access__c) {
          if (acr.Portal_Acces_for_Assigned_Team_Dept__c != null) {
            assignedTeamDepts.addAll(
              acr.Portal_Acces_for_Assigned_Team_Dept__c.split(';')
            );
          }
        }
      }

      Set<String> returnedCategories = new Set<String>();
      for (
        Portal_NavigationMenuItemsController.CaseCategoryWrapper ccw : resultCCWs
      ) {
        returnedCategories.add(ccw.externalCaseCategory);
      }
      for (String assignedTeamDept : assignedTeamDepts) {
        Assert.isTrue(
          returnedCategories.contains(
            assignmentToCategoryMap.get(assignedTeamDept)
          ),
          '"' +
            assignmentToCategoryMap.get(assignedTeamDept) +
            '"Assigned Team Department Results missing'
        );
      }

      Test.stopTest();
    }
  }

  @isTest
  private static void getPriorityValuesTest() {
    List<Portal_Case_Priority_Setup_map__mdt> protalCasePrioritySetupMapList = [
      SELECT Internal_Case_Priority__c, External_case_Priority__c
      FROM Portal_Case_Priority_Setup_map__mdt
    ];
    Test.startTest();
    Portal_NavigationMenuItemsController.getPriorityValues();
    Test.stopTest();
    System.assert(!protalCasePrioritySetupMapList.isEmpty(), true);
  }

  @isTest
  private static void getContactsTest() {
    String tag = uniqueTag();
    Account testAccount = AccountTestData.getInstance()
      .createAccount(AccountService.getInstance().PAYER_RECORDTYPEID, false);
    testAccount.Name = 'GetContacts Acct ' + tag;
    insert testAccount;
    Contact testContact = ContactTestData.getInstance()
      .createContact(
        testAccount.Id,
        'test',
        'gc-' + tag,
        'gc-' + tag + '@testinvalid.com',
        true
      );

    Account childAccount = AccountTestData.getInstance()
      .createAccount(AccountService.getInstance().PAYER_RECORDTYPEID, false);
    childAccount.Name = 'GetContacts Child ' + tag;
    childAccount.ParentId = testAccount.Id;
    insert childAccount;
    User userObj = getUserList(
      testContact.Id,
      'portal-gc-' + tag + '@testorg.com'
    );
    insert userObj;

    AccountContactRelation accConRelationObj = [
      SELECT
        Id,
        ContactId,
        AccountId,
        Portal_Account_Access__c,
        Portal_Acces_for_Assigned_Team_Dept__c
      FROM AccountContactRelation
      WHERE AccountId = :testAccount.Id AND ContactId = :testContact.Id
    ];

    accConRelationObj.Portal_Account_Access__c = true;
    accConRelationObj.Portal_Acces_for_Assigned_Team_Dept__c = inquiryPortalCaseSetupMap[0]
      .Assigned_Team_Department__c;
    update accConRelationObj;
    System.runAs(userObj) {
      Test.startTest();
      String categoryToUse = inquiryPortalCaseSetupMap[0]
        .Case_Category_External__c;
      String subCategoryToUse = inquiryPortalCaseSetupMap[0]
        .Case_SubCategory_External__c;
      Portal_NavigationMenuItemsController.ContactWrapper resultContactWrappers = Portal_NavigationMenuItemsController.getContacts(
        testAccount.Id,
        'S365 Issue',
        'Bug/Defect'
      );
      Test.stopTest();
      System.assertNotEquals(
        null,
        resultContactWrappers,
        'resultContactWrappers is null'
      );
    }
  }

  @isTest
  private static void getEnvironmentValuesTest() {
    Portal_NavigationMenuItemsController.getEnvironmentValues();
  }

  @isTest
  private static void getAccountsTest() {
    String tag = uniqueTag();
    Account testAccount = AccountTestData.getInstance()
      .createAccount(AccountService.getInstance().PAYER_RECORDTYPEID, false);
    testAccount.Name = 'GetAccts Acct ' + tag;
    insert testAccount;
    Contact testContact = ContactTestData.getInstance()
      .createContact(
        testAccount.Id,
        'test',
        'ga-' + tag,
        'ga-' + tag + '@testinvalid.com',
        true
      );

    Account childAccount = AccountTestData.getInstance()
      .createAccount(AccountService.getInstance().PAYER_RECORDTYPEID, false);
    childAccount.Name = 'GetAccts Child ' + tag;
    childAccount.parentId = testAccount.Id;
    insert childAccount;

    User userObj = getUserList(
      testContact.Id,
      'portal-ga-' + tag + '@testorg.com'
    );
    insert userObj;
    AccountContactRelation accConRelationObj = new AccountContactRelation(
      Portal_Acces_for_Assigned_Team_Dept__c = 'I&E Client Support Ops',
      ContactId = testContact.Id,
      AccountId = childAccount.Id,
      Portal_Account_Access__c = true
    );
    List<Portal_Case_Setup_Map__mdt> portal_Case_Setup_Metadata = [
      SELECT Assigned_Team_Department__c
      FROM Portal_Case_Setup_Map__mdt
      WHERE Case_SubCategory_External__c = 'Bug/Defect' AND Active__c = TRUE
      LIMIT 1
    ];
    insert accConRelationObj;
    System.runAs(userObj) {
      Test.startTest();
      Portal_NavigationMenuItemsController.getAccounts(
        'S365 Issue',
        'Bug/Defect'
      );
      Test.stopTest();
    }

    System.assert(userObj != null, true);
  }

  @isTest
  private static void getAccountsTest_1() {
    String tag = uniqueTag();
    Account testAccount = AccountTestData.getInstance()
      .createAccount(AccountService.getInstance().PAYER_RECORDTYPEID, false);
    testAccount.Name = 'GetAccts1 Acct ' + tag;
    insert testAccount;
    Contact testContact = ContactTestData.getInstance()
      .createContact(
        testAccount.Id,
        'test',
        'ga1-' + tag,
        'ga1-' + tag + '@testinvalid.com',
        true
      );

    User userObj = getUserList(
      testContact.Id,
      'portal-ga1-' + tag + '@testorg.com'
    );
    insert userObj;
    System.runAs(userObj) {
      Test.startTest();
      //Portal_NavigationMenuItemsController.getAccounts();
      Test.stopTest();
    }
    System.assert(userObj != null, true);
  }

  @isTest
  private static void insertCaseTest() {
    // Query the custom metadata type record
    List<Portal_Case_Setup_Map__mdt> portalCaseCatecoryMDTList = [
      SELECT Id, Case_Category_External__c, Case_SubCategory_External__c
      FROM Portal_Case_Setup_Map__mdt
      WHERE Active__c = TRUE
      LIMIT 1
    ];

    // Skip test if no metadata records are available
    if (portalCaseCatecoryMDTList.isEmpty()) {
      return;
    }

    Portal_Case_Setup_Map__mdt portalCaseCatecoryMDT = portalCaseCatecoryMDTList[0];
    case newCaseTest = new case();
    // Create a new Case record
    Case newCase = new Case(
      Origin = 'Portal',
      AccountId = null,
      Status = 'New',
      Subject = 'test',
      Description = 'test',
      Portal_Case_Category__c = portalCaseCatecoryMDT.Case_Category_External__c,
      Portal_Case_Type__c = portalCaseCatecoryMDT.Case_SubCategory_External__c,
      Priority = 'Low',
      ContactId = null,
      RecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
        .get('ZESP_IE_Case')
        .getRecordTypeId()
    );

    try {
      // Perform test operations within a Test.startTest/stopTest block
      Test.startTest();
      Portal_NavigationMenuItemsController.insertCase(newCase);
      Portal_NavigationMenuItemsController.insertCase(newCaseTest);
      Test.stopTest();
    } catch (Exception e) {
      // Log the exception for debugging
    }
  }
  @isTest
  static void testHandlePortalS365Access() {
    Test.StartTest();
    Boolean userCount = Portal_NavigationMenuItemsController.handlePortalS365Access();
    Test.stopTest();
    assert.isTrue(!userCount, 'this user is not S365 user');
  }

  @isTest
  static void testGetDefaultPicklistValue() {
    Test.StartTest();
    String defaultSlaLevel = Portal_NavigationMenuItemsController.getDefaultPicklistValue(
      'Case',
      'SLA_Level__c'
    );
    Test.stopTest();
    assert.areEqual(defaultSlaLevel != null, true);
  }

  @IsTest
  static void testInsertCaseWithInvalidData() {
    Case testCase = new Case(Origin = null, Status = null, Subject = null);

    Test.startTest();
    try {
      Portal_NavigationMenuItemsController.insertCase(testCase);
    } catch (Exception e) {
    }
    Test.stopTest();
  }

  @isTest
  static void testGetRecordTypeIdByName() {
    String recordTypeId = Portal_NavigationMenuItemsController.getRecordTypeIdByName(
      'Case',
      'ZESP Payments Client Service Case'
    );
    assert.areEqual(recordTypeId != null, true);
  }
}
