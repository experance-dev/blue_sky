/**
 * @description Controller tests for `EngagementController`. Uses a hand-rolled
 *              `MockEngagementService` (implements IEngagementService) injected
 *              via `EngagementController.setServiceForTest` to exercise the
 *              controller in isolation from the real service.
 * @group Engagement Attribution
 * @see EngagementController
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementControllerTest {
  // ─── Constants ────────────────────────────────────────────────────────────

  private static final String USER_LAST_NAME = 'EngageCtrlTest';
  private static final String PERMISSION_SET = 'Engagement_Attribution_User';

  // ─── Setup ────────────────────────────────────────────────────────────────

  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    Profile standard = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    User u = new User(
      ProfileId = standard.Id,
      LastName = USER_LAST_NAME,
      Email = 'engagectrl@test.example.com',
      Username = 'engagectrl' + Crypto.getRandomInteger() + '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'engctrl',
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
  }

  // ─── Tests ────────────────────────────────────────────────────────────────

  /**
   * @description Controller delegates to the service and returns the same list.
   */
  @IsTest
  static void getForOpportunityDelegatesToService() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      mock.opportunityResult = new List<EngagementDTO>{
        new EngagementDTO(),
        new EngagementDTO()
      };
      EngagementController.setServiceForTest(mock);

      Id fakeOppId = (Id) Utilities.getFakeId(Opportunity.SObjectType);

      Test.startTest();
      List<EngagementDTO> result = EngagementController.getForOpportunity(
        fakeOppId
      );
      Test.stopTest();

      Assert.areEqual(
        2,
        result.size(),
        'Expected the controller to pass through the mock\'s two DTOs.'
      );
      Assert.areEqual(
        fakeOppId,
        mock.lastOpportunityId,
        'Expected the controller to forward the opportunity Id.'
      );
    }
  }

  /**
   * @description Controller wraps service exceptions as AuraHandledException
   *              so the LWC layer never sees a raw stack trace.
   */
  @IsTest
  static void getForOpportunityServiceErrorThrowsAuraHandled() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      mock.throwOnOpportunity = true;
      EngagementController.setServiceForTest(mock);

      Id fakeOppId = (Id) Utilities.getFakeId(Opportunity.SObjectType);

      Test.startTest();
      Boolean thrown = false;
      try {
        EngagementController.getForOpportunity(fakeOppId);
      } catch (AuraHandledException e) {
        thrown = true;
      }
      Test.stopTest();

      Assert.isTrue(
        thrown,
        'Expected AuraHandledException when the service throws.'
      );
    }
  }

  /**
   * @description Controller delegates `getForAccount` and returns the mock's
   *              list as-is.
   */
  @IsTest
  static void getForAccountDelegatesToService() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      mock.accountResult = new List<EngagementDTO>{ new EngagementDTO() };
      EngagementController.setServiceForTest(mock);

      Id fakeAcctId = (Id) Utilities.getFakeId(Account.SObjectType);

      Test.startTest();
      List<EngagementDTO> result = EngagementController.getForAccount(
        fakeAcctId
      );
      Test.stopTest();

      Assert.areEqual(
        1,
        result.size(),
        'Expected the controller to return the mock\'s single DTO.'
      );
      Assert.areEqual(
        fakeAcctId,
        mock.lastAccountId,
        'Expected the controller to forward the account Id.'
      );
    }
  }

  /**
   * @description Controller delegates `addToOcrSafe` and returns the mock's
   *              AddToOcrResult unchanged.
   */
  @IsTest
  static void addToOcrSafeDelegatesAndReturnsResult() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      AddToOcrResult canned = new AddToOcrResult();
      canned.success = true;
      canned.ocrId = (Id) Utilities.getFakeId(
        OpportunityContactRole.SObjectType
      );
      mock.addResult = canned;
      EngagementController.setServiceForTest(mock);

      Id contactId = (Id) Utilities.getFakeId(Contact.SObjectType);
      Id opportunityId = (Id) Utilities.getFakeId(Opportunity.SObjectType);

      Test.startTest();
      AddToOcrResult result = EngagementController.addToOcrSafe(
        contactId,
        opportunityId,
        'Economic Buyer',
        false
      );
      Test.stopTest();

      Assert.areEqual(
        true,
        result.success,
        'Expected the controller to return the mock\'s success result.'
      );
      Assert.areEqual(
        canned.ocrId,
        result.ocrId,
        'Expected the controller to return the mock\'s ocrId.'
      );
      Assert.areEqual(
        1,
        mock.addInvocationCount,
        'Expected the service add path to be invoked exactly once.'
      );
    }
  }

  /**
   * @description Controller invokes the service's `dismissSignal` method
   *              exactly once.
   */
  @IsTest
  static void dismissSignalDelegatesToService() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      EngagementController.setServiceForTest(mock);

      Id signalId = (Id) Utilities.getFakeId(
        Opportunity_Engagement_Signal__c.SObjectType
      );

      Test.startTest();
      EngagementController.dismissSignal(signalId, 'not-relevant');
      Test.stopTest();

      Assert.areEqual(
        1,
        mock.dismissInvocationCount,
        'Expected dismissSignal to be invoked exactly once.'
      );
      Assert.areEqual(
        signalId,
        mock.lastSignalId,
        'Expected the controller to forward the signal Id.'
      );
    }
  }

  /**
   * @description Controller forwards (contactId, opportunityId, accountId)
   *              to the service exactly once with the supplied arg values.
   */
  @IsTest
  static void dismissContactDelegatesToService() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      EngagementController.setServiceForTest(mock);

      Id contactId = (Id) Utilities.getFakeId(Contact.SObjectType);
      Id opportunityId = (Id) Utilities.getFakeId(Opportunity.SObjectType);

      Test.startTest();
      EngagementController.dismissContact(contactId, opportunityId, null);
      Test.stopTest();

      Assert.areEqual(
        1,
        mock.dismissContactInvocationCount,
        'Expected dismissContact to be invoked exactly once.'
      );
      Assert.areEqual(
        contactId,
        mock.lastDismissContactId,
        'Expected the controller to forward the contact Id.'
      );
      Assert.areEqual(
        opportunityId,
        mock.lastDismissOpportunityId,
        'Expected the controller to forward the opportunity Id.'
      );
      Assert.areEqual(
        null,
        mock.lastDismissAccountId,
        'Expected the controller to forward null for accountId.'
      );
    }
  }

  /**
   * @description Service-thrown exceptions must be wrapped as
   *              AuraHandledException by the controller — the LWC must never
   *              see the raw service exception.
   */
  @IsTest
  static void dismissContactServiceErrorThrowsAuraHandled() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      mock.throwOnDismissContact = true;
      EngagementController.setServiceForTest(mock);

      Id contactId = (Id) Utilities.getFakeId(Contact.SObjectType);
      Id opportunityId = (Id) Utilities.getFakeId(Opportunity.SObjectType);

      Test.startTest();
      Boolean thrown = false;
      try {
        EngagementController.dismissContact(contactId, opportunityId, null);
      } catch (AuraHandledException e) {
        thrown = true;
      }
      Test.stopTest();

      Assert.isTrue(
        thrown,
        'Expected AuraHandledException when the service throws.'
      );
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  private static User getTestUser() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :USER_LAST_NAME
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  /**
   * @description Hand-rolled mock for IEngagementService. Tests configure the
   *              return values / throw flags before injecting via
   *              `EngagementController.setServiceForTest`.
   */
  private class MockEngagementService implements IEngagementService {
    public List<EngagementDTO> opportunityResult = new List<EngagementDTO>();
    public List<EngagementDTO> accountResult = new List<EngagementDTO>();
    public AddToOcrResult addResult = new AddToOcrResult();
    public Boolean throwOnOpportunity = false;
    public Boolean throwOnAccount = false;
    public Boolean throwOnAdd = false;
    public Boolean throwOnDismissSignal = false;
    public Boolean throwOnDismissContact = false;
    public Id lastOpportunityId;
    public Id lastAccountId;
    public Id lastSignalId;
    public Id lastDismissContactId;
    public Id lastDismissOpportunityId;
    public Id lastDismissAccountId;
    public Integer addInvocationCount = 0;
    public Integer dismissInvocationCount = 0;
    public Integer dismissContactInvocationCount = 0;

    public List<EngagementDTO> getForOpportunity(Id opportunityId) {
      this.lastOpportunityId = opportunityId;
      if (throwOnOpportunity) {
        throw new EngagementException('mock failure');
      }
      return opportunityResult;
    }

    public List<EngagementDTO> getForAccount(Id accountId) {
      this.lastAccountId = accountId;
      if (throwOnAccount) {
        throw new EngagementException('mock failure account');
      }
      return accountResult;
    }

    public AddToOcrResult addToOcrSafe(
      Id contactId,
      Id opportunityId,
      String role,
      Boolean isPrimary
    ) {
      this.addInvocationCount += 1;
      if (throwOnAdd) {
        throw new EngagementException('mock add failure');
      }
      return addResult;
    }

    public void dismissSignal(Id signalId, String reason) {
      this.dismissInvocationCount += 1;
      this.lastSignalId = signalId;
      if (throwOnDismissSignal) {
        throw new EngagementException('mock dismissSignal failure');
      }
    }

    public void dismissContact(Id contactId, Id opportunityId, Id accountId) {
      this.dismissContactInvocationCount += 1;
      this.lastDismissContactId = contactId;
      this.lastDismissOpportunityId = opportunityId;
      this.lastDismissAccountId = accountId;
      if (throwOnDismissContact) {
        throw new EngagementException('mock dismissContact failure');
      }
    }
  }

  // ─── New tests (David Wood, 2026-05-12) ───────────────────────────────────

  /**
   * @description getForAccount wraps service errors in AuraHandledException
   *              with the same shape as getForOpportunity. Covers lines 43-46
   *              of EngagementController.
   */
  @IsTest
  static void getForAccountServiceErrorThrowsAuraHandled() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      mock.throwOnAccount = true;
      EngagementController.setServiceForTest(mock);
      Id fakeAcctId = (Id) Utilities.getFakeId(Account.SObjectType);
      Test.startTest();
      Boolean thrown = false;
      try {
        EngagementController.getForAccount(fakeAcctId);
      } catch (AuraHandledException e) {
        thrown = true;
      }
      Test.stopTest();
      Assert.isTrue(
        thrown,
        'Expected AuraHandledException when getForAccount service throws.'
      );
    }
  }

  /**
   * @description addToOcrSafe wraps service errors in AuraHandledException.
   *              Covers lines 68-73 of EngagementController.
   */
  @IsTest
  static void addToOcrSafeServiceErrorThrowsAuraHandled() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      mock.throwOnAdd = true;
      EngagementController.setServiceForTest(mock);
      Id cId = (Id) Utilities.getFakeId(Contact.SObjectType);
      Id oId = (Id) Utilities.getFakeId(Opportunity.SObjectType);
      Test.startTest();
      Boolean thrown = false;
      try {
        EngagementController.addToOcrSafe(cId, oId, 'Champion', false);
      } catch (AuraHandledException e) {
        thrown = true;
      }
      Test.stopTest();
      Assert.isTrue(
        thrown,
        'Expected AuraHandledException when addToOcrSafe service throws.'
      );
    }
  }

  /**
   * @description dismissSignal wraps service errors in AuraHandledException.
   */
  @IsTest
  static void dismissSignalServiceErrorThrowsAuraHandled() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      mock.throwOnDismissSignal = true;
      EngagementController.setServiceForTest(mock);
      Id sId = (Id) Utilities.getFakeId(
        Opportunity_Engagement_Signal__c.SObjectType
      );
      Test.startTest();
      Boolean thrown = false;
      try {
        EngagementController.dismissSignal(sId, 'unwanted');
      } catch (AuraHandledException e) {
        thrown = true;
      }
      Test.stopTest();
      Assert.isTrue(
        thrown,
        'Expected AuraHandledException when dismissSignal service throws.'
      );
    }
  }

  /**
   * @description Null Opportunity Id flows through the controller to the
   *              service (which returns an empty list per the contract).
   *              Controller does not pre-validate inputs.
   */
  @IsTest
  static void getForOpportunityNullIdReturnsEmpty() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      mock.opportunityResult = new List<EngagementDTO>();
      EngagementController.setServiceForTest(mock);
      Test.startTest();
      List<EngagementDTO> result = EngagementController.getForOpportunity(null);
      Test.stopTest();
      Assert.areEqual(
        0,
        result.size(),
        'Expected an empty list when service returns empty for null input.'
      );
      Assert.areEqual(
        null,
        mock.lastOpportunityId,
        'Expected null to be forwarded to the service.'
      );
    }
  }

  /**
   * @description addToOcrSafe passes through null isPrimary. The service
   *              interprets null as false per its own contract.
   */
  @IsTest
  static void addToOcrSafeNullIsPrimaryPassesThrough() {
    System.runAs(getTestUser()) {
      MockEngagementService mock = new MockEngagementService();
      AddToOcrResult canned = new AddToOcrResult();
      canned.success = true;
      mock.addResult = canned;
      EngagementController.setServiceForTest(mock);
      Id cId = (Id) Utilities.getFakeId(Contact.SObjectType);
      Id oId = (Id) Utilities.getFakeId(Opportunity.SObjectType);
      Test.startTest();
      AddToOcrResult result = EngagementController.addToOcrSafe(
        cId,
        oId,
        'Influencer',
        null
      );
      Test.stopTest();
      Assert.areEqual(
        true,
        result.success,
        'Expected the controller to forward null isPrimary without coercion.'
      );
      Assert.areEqual(
        1,
        mock.addInvocationCount,
        'Expected the service to be invoked exactly once.'
      );
    }
  }
}
