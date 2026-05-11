/**
 * @description Tests for JiraPushService publish-side behavior: qualifying-field
 *              evaluation, recursion guard, config gating, and empty-input
 *              short-circuits. Uses Account as the test SObject and the shared
 *              RecordingJcfs stub from JiraPushDispatcherTest to silence the
 *              dispatcher during PE delivery.
 *
 * @group Jira Integration
 */
@IsTest
private class JiraPushServiceTest {
  private static Jira_Push_Object__mdt accountConfig(
    String qualifyingFieldsCSV,
    Boolean active
  ) {
    return new Jira_Push_Object__mdt(
      MasterLabel = 'Account',
      DeveloperName = 'Account',
      SObject_API_Name__c = 'Account',
      Qualifying_Fields__c = qualifyingFieldsCSV,
      Active__c = active
    );
  }

  private static void overrideConfig(Jira_Push_Object__mdt cfg) {
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>{
      'Account' => cfg
    };
  }

  /** Quiets the dispatcher so PE delivery in stopTest doesn't try the real JCFS. */
  private static void silenceDispatcher() {
    JiraPushDispatcher.jcfs = new JiraPushDispatcherTest.RecordingJcfs();
  }

  @IsTest
  static void publishIfQualifies_publishesOnInsert() {
    overrideConfig(accountConfig('Name', true));
    silenceDispatcher();

    Account a = new Account(Name = 'Created');
    insert a;

    Test.startTest();
    JiraPushService.publishIfQualifies(new List<Account>{ a }, null);
    Test.stopTest();

    System.assert(
      JiraPushService.alreadyPublished.contains('Account:' + a.Id),
      'Insert should mark record as published'
    );
  }

  @IsTest
  static void publishIfQualifies_publishesWhenQualifyingFieldChanged() {
    overrideConfig(accountConfig('Name', true));
    silenceDispatcher();

    Account a = new Account(Name = 'New');
    insert a;
    Account old = new Account(Id = a.Id, Name = 'Old');

    Test.startTest();
    JiraPushService.publishIfQualifies(
      new List<Account>{ a },
      new Map<Id, Account>{ a.Id => old }
    );
    Test.stopTest();

    System.assert(
      JiraPushService.alreadyPublished.contains('Account:' + a.Id),
      'Field change should publish'
    );
  }

  @IsTest
  static void publishIfQualifies_skipsWhenNoQualifyingFieldChanged() {
    overrideConfig(accountConfig('Name', true));
    silenceDispatcher();

    Account a = new Account(Name = 'Same');
    insert a;
    Account old = new Account(Id = a.Id, Name = 'Same');

    Test.startTest();
    JiraPushService.publishIfQualifies(
      new List<Account>{ a },
      new Map<Id, Account>{ a.Id => old }
    );
    Test.stopTest();

    System.assert(
      !JiraPushService.alreadyPublished.contains('Account:' + a.Id),
      'No change -> no publish'
    );
  }

  @IsTest
  static void publishIfQualifies_blankQualifyingFieldsPublishesEveryUpdate() {
    overrideConfig(accountConfig(null, true));
    silenceDispatcher();

    Account a = new Account(Name = 'X');
    insert a;
    Account old = new Account(Id = a.Id, Name = 'X');

    Test.startTest();
    JiraPushService.publishIfQualifies(
      new List<Account>{ a },
      new Map<Id, Account>{ a.Id => old }
    );
    Test.stopTest();

    System.assert(
      JiraPushService.alreadyPublished.contains('Account:' + a.Id),
      'Blank Qualifying_Fields__c => publish on every update'
    );
  }

  @IsTest
  static void publishIfQualifies_skipsWhenInactive() {
    overrideConfig(accountConfig('Name', false));
    silenceDispatcher();

    Account a = new Account(Name = 'Off');
    insert a;

    Test.startTest();
    JiraPushService.publishIfQualifies(new List<Account>{ a }, null);
    Test.stopTest();

    System.assert(
      !JiraPushService.alreadyPublished.contains('Account:' + a.Id),
      'Inactive config -> no publish'
    );
  }

  @IsTest
  static void publishIfQualifies_skipsWhenNoConfigForObject() {
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>();
    silenceDispatcher();

    Account a = new Account(Name = 'NoCfg');
    insert a;

    Test.startTest();
    JiraPushService.publishIfQualifies(new List<Account>{ a }, null);
    Test.stopTest();

    System.assert(
      !JiraPushService.alreadyPublished.contains('Account:' + a.Id),
      'No config row -> no publish'
    );
  }

  @IsTest
  static void publishIfQualifies_recursionGuardSuppressesSecondPublish() {
    overrideConfig(accountConfig('Name', true));
    silenceDispatcher();

    Account a = new Account(Name = 'First');
    insert a;

    Test.startTest();
    JiraPushService.publishIfQualifies(new List<Account>{ a }, null);
    Integer publishedDmlAfterFirst = Limits.getPublishImmediateDml();
    JiraPushService.publishIfQualifies(new List<Account>{ a }, null);
    Integer publishedDmlAfterSecond = Limits.getPublishImmediateDml();
    Test.stopTest();

    System.assertEquals(
      publishedDmlAfterFirst,
      publishedDmlAfterSecond,
      'Recursion guard should suppress duplicate publish in same transaction'
    );
  }

  @IsTest
  static void publishIfQualifies_emptyAndNullInputAreNoOp() {
    overrideConfig(accountConfig('Name', true));
    silenceDispatcher();

    Test.startTest();
    JiraPushService.publishIfQualifies(null, null);
    JiraPushService.publishIfQualifies(new List<Account>(), null);
    Test.stopTest();

    System.assert(JiraPushService.alreadyPublished.isEmpty());
  }
}
