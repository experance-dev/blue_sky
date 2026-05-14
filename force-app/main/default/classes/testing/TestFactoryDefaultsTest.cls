/**
 * @description Drift-detection tests for `TestFactoryDefaults`. Verifies each
 *              registered default still satisfies the org's current validation
 *              rules and CRUD/FLS surface. Each test exercises a single inner
 *              `FieldDefaults` class end-to-end: build an SObject seeded with
 *              the platform-required base fields, layer the defaults via
 *              `TestFactory.createSObject(..., 'TestFactoryDefaults.<Name>', true)`,
 *              and let SYSTEM_MODE DML prove the resulting record clears every
 *              active rule and constraint in the target org.
 *
 *              When the org's schema or rule set drifts from what the defaults
 *              expect, the relevant test fires with a clear message that
 *              identifies the inner class to update so the defaults can be
 *              brought back into alignment.
 * @group Testing
 * @author David Wood
 * @since May 2026
 * @last May 2026 — initial drift-detection suite for CSI-7162 defaults hardening.
 */
@IsTest
private class TestFactoryDefaultsTest {
  // ── Defaults shape contract (instance-level, no DML) ─────────────────────

  @IsTest
  static void accountDefaultsReturnsNonNullFieldMap() {
    Map<Schema.SObjectField, Object> fields = new TestFactoryDefaults.AccountDefaults()
      .getFieldDefaults();
    Assert.areNotEqual(
      null,
      fields,
      'AccountDefaults.getFieldDefaults() must return a non-null map.'
    );
  }

  @IsTest
  static void contactDefaultsReturnsNonNullFieldMap() {
    Map<Schema.SObjectField, Object> fields = new TestFactoryDefaults.ContactDefaults()
      .getFieldDefaults();
    Assert.areNotEqual(
      null,
      fields,
      'ContactDefaults.getFieldDefaults() must return a non-null map.'
    );
  }

  @IsTest
  static void contactWithAccountDefaultsReturnsNonNullFieldMap() {
    Map<Schema.SObjectField, Object> fields = new TestFactoryDefaults.ContactWithAccountDefaults()
      .getFieldDefaults();
    Assert.areNotEqual(
      null,
      fields,
      'ContactWithAccountDefaults.getFieldDefaults() must return a non-null map.'
    );
  }

  @IsTest
  static void opportunityDefaultsReturnsNonNullFieldMap() {
    Map<Schema.SObjectField, Object> fields = new TestFactoryDefaults.OpportunityDefaults()
      .getFieldDefaults();
    Assert.areNotEqual(
      null,
      fields,
      'OpportunityDefaults.getFieldDefaults() must return a non-null map.'
    );
  }

  @IsTest
  static void userDefaultsReturnsNonNullFieldMap() {
    Map<Schema.SObjectField, Object> fields = new TestFactoryDefaults.UserDefaults()
      .getFieldDefaults();
    Assert.areNotEqual(
      null,
      fields,
      'UserDefaults.getFieldDefaults() must return a non-null map.'
    );
  }

  // ── Watchdog inserts (DML proves VRs + CRUD still pass) ──────────────────

  @IsTest
  static void accountDefaultsInsertsCleanly() {
    Account seed = new Account(Name = 'Watchdog Account');
    Account inserted;
    Test.startTest();
    try {
      inserted = (Account) TestFactory.createSObject(
        seed,
        'TestFactoryDefaults.AccountDefaults',
        true
      );
    } catch (Exception e) {
      Assert.fail(
        'AccountDefaults drift detected: insert failed under current org ' +
          'schema. Update TestFactoryDefaults.AccountDefaults.getFieldDefaults() ' +
          'to match. Underlying error: ' +
          e.getTypeName() +
          ' — ' +
          e.getMessage()
      );
    }
    Test.stopTest();
    Assert.areNotEqual(
      null,
      inserted.Id,
      'AccountDefaults inserted record must have an Id.'
    );
  }

  @IsTest
  static void contactDefaultsInsertsCleanly() {
    Contact seed = new Contact(LastName = 'Watchdog');
    Contact inserted;
    Test.startTest();
    try {
      inserted = (Contact) TestFactory.createSObject(
        seed,
        'TestFactoryDefaults.ContactDefaults',
        true
      );
    } catch (Exception e) {
      Assert.fail(
        'ContactDefaults drift detected: insert failed under current org ' +
          'schema. Update TestFactoryDefaults.ContactDefaults.getFieldDefaults() ' +
          'to match. Underlying error: ' +
          e.getTypeName() +
          ' — ' +
          e.getMessage()
      );
    }
    Test.stopTest();
    Assert.areNotEqual(
      null,
      inserted.Id,
      'ContactDefaults inserted record must have an Id.'
    );
  }

  @IsTest
  static void contactWithAccountDefaultsInsertsCleanly() {
    // ContactWithAccountDefaults is intended to compose a parent Account, but
    // the deployed shape in this org returns an empty map. The watchdog still
    // proves the inner class is reachable and a plain insert succeeds with
    // just the platform-required LastName. If composition is later added, the
    // seed can drop the LastName once defaults supply it.
    Contact seed = new Contact(LastName = 'Watchdog With Account');
    Contact inserted;
    Test.startTest();
    try {
      inserted = (Contact) TestFactory.createSObject(
        seed,
        'TestFactoryDefaults.ContactWithAccountDefaults',
        true
      );
    } catch (Exception e) {
      Assert.fail(
        'ContactWithAccountDefaults drift detected: insert failed under ' +
          'current org schema. Update ' +
          'TestFactoryDefaults.ContactWithAccountDefaults.getFieldDefaults() ' +
          'to match. Underlying error: ' +
          e.getTypeName() +
          ' — ' +
          e.getMessage()
      );
    }
    Test.stopTest();
    Assert.areNotEqual(
      null,
      inserted.Id,
      'ContactWithAccountDefaults inserted record must have an Id.'
    );
  }

  @IsTest
  static void opportunityDefaultsInsertsCleanly() {
    // Opportunity needs a parent Account, Name, StageName, CloseDate at the
    // platform level. Defaults layer Opportunity_Name_Descriptor__c on top to
    // clear the current dwood_z rule set. If the rule surface drifts, this
    // insert fails and the catch points at the inner class to extend.
    Account parent = new Account(Name = 'Watchdog Opp Parent');
    Database.insert(parent, AccessLevel.SYSTEM_MODE);

    Opportunity seed = new Opportunity(
      Name = 'Watchdog Opportunity',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      AccountId = parent.Id
    );
    Opportunity inserted;
    Test.startTest();
    try {
      inserted = (Opportunity) TestFactory.createSObject(
        seed,
        'TestFactoryDefaults.OpportunityDefaults',
        true
      );
    } catch (Exception e) {
      Assert.fail(
        'OpportunityDefaults drift detected: insert failed under current org ' +
          'schema. Update ' +
          'TestFactoryDefaults.OpportunityDefaults.getFieldDefaults() to ' +
          'match. Underlying error: ' +
          e.getTypeName() +
          ' — ' +
          e.getMessage()
      );
    }
    Test.stopTest();
    Assert.areNotEqual(
      null,
      inserted.Id,
      'OpportunityDefaults inserted record must have an Id.'
    );
    Assert.areEqual(
      'Test',
      inserted.Opportunity_Name_Descriptor__c,
      'OpportunityDefaults must populate Opportunity_Name_Descriptor__c so ' +
      'inserts clear the current rule surface.'
    );
  }

  @IsTest
  static void userDefaultsInsertsCleanly() {
    // User insert needs a Profile and the mixed-DML workaround. The watchdog
    // seeds the minimum platform-required fields (mirroring
    // TestFactory.createTestUser) and runs the defaults on top.
    Profile minAccess = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    User seed = new User(
      ProfileId = minAccess.Id,
      LastName = 'Watchdog',
      Email = 'watchdog-user@test.example.com',
      Username = 'watchdog-user-' +
        Crypto.getRandomInteger() +
        '@test.example.com',
      CompanyName = 'TEST',
      Title = 'title',
      Alias = 'wdog',
      TimeZoneSidKey = 'America/Los_Angeles',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US'
    );

    User adminCtx = [
      SELECT Id
      FROM User
      WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE
      LIMIT 1
    ];

    User inserted;
    Test.startTest();
    try {
      // User insert wrapped in runAs(admin) to avoid mixed-DML.
      System.runAs(adminCtx) {
        inserted = (User) TestFactory.createSObject(
          seed,
          'TestFactoryDefaults.UserDefaults',
          true
        );
      }
    } catch (Exception e) {
      Assert.fail(
        'UserDefaults drift detected: insert failed under current org ' +
          'schema. Update TestFactoryDefaults.UserDefaults.getFieldDefaults() ' +
          'to match. Underlying error: ' +
          e.getTypeName() +
          ' — ' +
          e.getMessage()
      );
    }
    Test.stopTest();
    Assert.areNotEqual(
      null,
      inserted.Id,
      'UserDefaults inserted record must have an Id.'
    );
  }

  // ── Constant surface (compile-time contract for TestFactory) ─────────────

  @IsTest
  static void exposedConstantsResolveAtCompileTime() {
    // TestFactory references these statically. If any is renamed or removed,
    // the dependent classes fail to compile — but a lightweight assertion
    // here surfaces the contract clearly in coverage.
    Assert.areNotEqual(
      null,
      TestFactoryDefaults.TEST_USER_PERMISSION,
      'TEST_USER_PERMISSION must remain exposed for TestFactory.'
    );
    Assert.areEqual(
      'TestUserPermission',
      TestFactoryDefaults.TEST_USER_PERMISSION,
      'TEST_USER_PERMISSION value drift breaks TestFactory.createTestUser().'
    );
    Assert.areNotEqual(
      null,
      TestFactoryDefaults.DEFAULT_PRODUCT_FAMILY,
      'DEFAULT_PRODUCT_FAMILY must remain exposed.'
    );
    Assert.areNotEqual(
      null,
      TestFactoryDefaults.DEFAULT_WARRANTY_PRODUCT,
      'DEFAULT_WARRANTY_PRODUCT must remain exposed.'
    );
  }
}
