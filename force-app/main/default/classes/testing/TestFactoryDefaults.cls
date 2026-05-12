/**
 * @description Per-SObject `FieldDefaults` registry consumed by
 *              `TestFactory.createSObject`. Convention: a default class for
 *              SObject `Foo` is named `FooDefaults` (or `FooXxxDefaults` for
 *              record-type flavors); `TestFactory` finds the right one via
 *              `Type.forName('TestFactoryDefaults.' + Name)`. Custom-object
 *              suffixes (`__c`, `__`) are stripped before the lookup.
 *
 *              Composition lives in the defaults: a defaults class that needs
 *              a parent record should call `TestFactory.createSObject(...)`
 *              itself, so improvements to `AccountDefaults` propagate
 *              automatically to every child defaults class that hangs off it.
 *
 *              dwood_z reality check (validation-rule audit, 2026-05-12):
 *              63 active validation rules across Account / Opportunity /
 *              Contact. ~56 of them gate on
 *              `$Setup.Process_Automation_Switch__c.Validation_Rules_Disabled__c`.
 *              The first thing any dwood_z test does is flip that switch ON
 *              via `disableValidationRules()` — that single move neutralises
 *              ~89% of the rule surface. The remaining 7 outlier rules are
 *              handled by the individual `*Defaults` classes below (don't
 *              populate `LID__LinkedIn_Company_Id__c` with non-numeric,
 *              don't tick `Fee_Holiday_Requested__c`, don't set
 *              `Type_of_Sale__c='True-Up'`, always set `Email` on
 *              `Payer_Contact`, etc.).
 *
 *              Record-type flavors: dwood_z's Opportunity has 6 active RTs
 *              with very different validation profiles. Use the matching
 *              `Opportunity*Defaults` flavor (e.g.
 *              `OpportunityPEProviderDefaults`) when a test needs an Opp of
 *              that RT instead of stacking field defaults manually. Same
 *              pattern for Account (Payer vs Provider).
 *
 * @group Testing
 * @see TestFactory
 * @author David Wood
 * @since December 2020
 * @last 2026-05-12 — CSI-7162: dwood_z-tailored per-SObject defaults +
 *                    disableValidationRules() @TestSetup kill-switch helper +
 *                    per-RecordType flavors (Opportunity PE/Enterprise/IE,
 *                    Account Payer/Provider).
 */
@IsTest
public without sharing class TestFactoryDefaults {
  // Permission set assigned to the default `TestFactory.createTestUser()`.
  // Update to the dwood_z permset that grants MI access once one exists.
  public static final String TEST_USER_PERMISSION = 'TestUserPermission';

  // Generic product-family literal for any TestFactoryDefaults default that
  // doesn't care about the value (left empty so a test that DOES care must
  // override deliberately).
  public static final String DEFAULT_PRODUCT_FAMILY = '';
  public static final String DEFAULT_WARRANTY_PRODUCT = '';

  // ─── @TestSetup kill-switch helper (the single highest-leverage move) ─────

  /**
   * @description Flips `Process_Automation_Switch__c.Validation_Rules_Disabled__c`
   *              and `All_Process_Disabled__c` to `true` for the running org
   *              (org-default hierarchy custom setting) IF the setting type
   *              is deployed. Suppresses ~89% of dwood_z's active validation
   *              rules in tests. Idempotent — call from `@TestSetup`.
   *
   *              Per the validation-rule audit (2026-05-12): 56 of 63 active
   *              rules on Account / Opportunity / Contact include the formula
   *              clause `$Setup.Process_Automation_Switch__c.Validation_Rules_Disabled__c = FALSE`.
   *              When this flag is true those rules return false and the
   *              record saves. The 7 outliers must be satisfied by field
   *              values (see the per-SObject defaults below).
   *
   *              Portability: dynamic dispatch via `Schema.getGlobalDescribe`
   *              so this method compiles and runs in orgs (scratch, main
   *              dev) where the custom setting isn't deployed — it's a
   *              silent no-op there. In dwood_z and any other receiving org
   *              that DOES carry `Process_Automation_Switch__c`, the upsert
   *              fires normally. This lets MI tests call
   *              `disableValidationRules()` unconditionally in `@TestSetup`
   *              and have the right thing happen everywhere.
   *
   *              Why dynamic instead of a direct compile-time reference?
   *              merged main and most scratch orgs don't carry the custom
   *              setting; a direct reference would fail to compile here
   *              and block the deploy. The dynamic dispatch is verbose but
   *              keeps the test scaffolding portable.
   */
  public static void disableValidationRules() {
    Schema.SObjectType settingType = Schema.getGlobalDescribe()
      .get('Process_Automation_Switch__c');
    if (settingType == null) {
      // Receiving org doesn't carry the setting — nothing to flip.
      return;
    }
    Schema.DescribeSObjectResult describe = settingType.getDescribe();
    Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
    Schema.SObjectField vrDisabled = fieldMap.get(
      'Validation_Rules_Disabled__c'
    );
    Schema.SObjectField allDisabled = fieldMap.get('All_Process_Disabled__c');
    if (vrDisabled == null || allDisabled == null) {
      // Setting exists but with a different field shape — bail rather
      // than guess. Surfaces as a clear "switch not flipped" symptom if
      // someone forks the setting schema.
      return;
    }
    SObject sw = settingType.newSObject();
    sw.put(vrDisabled, true);
    sw.put(allDisabled, true);
    // Custom-setting upsert by SetupOwnerId is what makes this an
    // org-default. Hierarchy custom settings use SetupOwnerId = the org
    // Id for the default row.
    sw.put('SetupOwnerId', UserInfo.getOrganizationId());
    upsert sw;
  }

  // ─── Account ──────────────────────────────────────────────────────────────

  /**
   * @description Base Account defaults. After `disableValidationRules()`
   *              fires only 4 ungated Account rules remain: reserved-name
   *              gating, LID company-id format, Zelis Provider Id change-
   *              gate (UPDATE only), Fee_Holiday field-completion. These
   *              defaults steer clear of all four.
   */
  public class AccountDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String suffix = uniqueSuffix();
      return new Map<Schema.SObjectField, Object>{
        // Generic name — Account_Creation_Restricton blocks a fixed list of
        // reserved names (Customer Service, Payer Operations, EDI SUPPORT, …)
        // and only fires for Agent_Account / Holding_Account RTs. "MI Test
        // Account <N>" is safe across all RTs.
        Account.Name => 'MI Test Account ' + suffix,
        Account.BillingStreet => '1 Test St',
        Account.BillingCity => 'Test City',
        Account.BillingState => 'TN',
        // PayerAccount RT under US billing must match \d{5}(-\d{4})? per
        // US_Billing_Zip_Code. 5-digit covers both.
        Account.BillingPostalCode => '37201',
        Account.BillingCountry => 'USA'
        // Intentionally NOT setting:
        //   LID__LinkedIn_Company_Id__c (LID__Check_Company_Id_Value: must be
        //     numeric if populated; the safe default is to omit).
        //   Zelis_Provider_Id__c (ZelisProviderID_Restriction: gates on
        //     ISCHANGED; insert is OK but tests that update this field
        //     must runAs a Connected App user).
        //   Fee_Holiday_Requested__c (Fee_Holiday_Field_Completion: if true,
        //     all four sub-fields must be set).
        //   Client_Globalization_Consent__c (Client_Consent_Exceptions_Yes:
        //     'Yes with Exceptions' requires Detailed_Requirements_*).
      };
    }
  }

  /**
   * @description Account with PayerAccount RecordType. Same base values
   *              plus the RT assignment. Use when a test needs a payer-side
   *              account specifically (e.g. for US_Billing_Zip_Code coverage).
   */
  public class AccountPayerDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      Map<Schema.SObjectField, Object> base = new AccountDefaults()
        .getFieldDefaults();
      Id payerRtId = getRecordTypeId(
        Account.SObjectType,
        'PayerAccount'
      );
      if (payerRtId != null) {
        base.put(Account.RecordTypeId, payerRtId);
      }
      return base;
    }
  }

  /**
   * @description Account with ProviderAccount RecordType. Mirror of
   *              `AccountPayerDefaults` for the provider side; resolves the
   *              RT by developer name so the default is portable across
   *              orgs that may not have the exact same RT (it just falls
   *              back to no RT if absent).
   */
  public class AccountProviderDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      Map<Schema.SObjectField, Object> base = new AccountDefaults()
        .getFieldDefaults();
      Id providerRtId = getRecordTypeId(
        Account.SObjectType,
        'ProviderAccount'
      );
      if (providerRtId != null) {
        base.put(Account.RecordTypeId, providerRtId);
      }
      return base;
    }
  }

  // ─── Contact ──────────────────────────────────────────────────────────────

  /**
   * @description Base Contact defaults. Always sets `Email` — covers the
   *              single ungated Contact rule (Email_Address_is_Required,
   *              which fires when RT=Payer_Contact and Email is blank).
   *              Default unconditionally so any RT-flavor inherits the
   *              email and a Payer_Contact override doesn't have to
   *              remember.
   */
  public class ContactDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String suffix = uniqueSuffix();
      return new Map<Schema.SObjectField, Object>{
        Contact.FirstName => 'Test',
        Contact.LastName => 'Contact ' + suffix,
        Contact.Email => 'mi-test-' + suffix + '@example.invalid'
      };
    }
  }

  // ─── Opportunity ──────────────────────────────────────────────────────────

  /**
   * @description Base Opportunity defaults (no record type set). With
   *              `disableValidationRules()` in `@TestSetup`, ~all gated
   *              Opportunity rules are silent. The ungated outliers are
   *              avoided here by:
   *                - not setting `LID__LinkedIn_Company_Id__c`
   *                - not setting `Type_of_Sale__c='True-Up'`
   *                - using a future `CloseDate` (defends against
   *                  Close_Date_Must_be_a_Future_Date_2 in case the
   *                  kill-switch is ever off).
   */
  public class OpportunityDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String suffix = uniqueSuffix();
      return new Map<Schema.SObjectField, Object>{
        Opportunity.Name => 'MI Test Opportunity ' + suffix,
        Opportunity.StageName => 'Prospecting',
        Opportunity.CloseDate => Date.today().addDays(30),
        Opportunity.Probability => 10
      };
    }
  }

  /**
   * @description Opportunity flavored for the `PE_Provider_Opportunity`
   *              record type — the only RT that opts into the Jira push
   *              integration per `OpportunityService.JIRA_PUSH_RT_DEVELOPER_NAMES`.
   *              Sets `LeadSource` (Opportunity.Lead_Source rule fires
   *              ungated for PEPO when LeadSource is blank) and uses
   *              `Discovery (10%)` as the safest insert-stage.
   */
  public class OpportunityPEProviderDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      Map<Schema.SObjectField, Object> base = new OpportunityDefaults()
        .getFieldDefaults();
      Id rtId = getRecordTypeId(
        Opportunity.SObjectType,
        'PE_Provider_Opportunity'
      );
      if (rtId != null) {
        base.put(Opportunity.RecordTypeId, rtId);
      }
      // Lead_Source rule (ungated, RT=PEPO, LeadSource blank). Default to
      // 'Other' so the test doesn't have to think about it.
      base.put(Opportunity.LeadSource, 'Other');
      return base;
    }
  }

  /**
   * @description Opportunity flavored for the `Enterprise` record type.
   *              Sets `Opportunity_Name_Descriptor__c` if the field exists
   *              (Name_Descriptor_Validation rule). Field is set
   *              dynamically because not every org carries this custom
   *              field — falls back gracefully.
   */
  public class OpportunityEnterpriseDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      Map<Schema.SObjectField, Object> base = new OpportunityDefaults()
        .getFieldDefaults();
      Id rtId = getRecordTypeId(Opportunity.SObjectType, 'Enterprise');
      if (rtId != null) {
        base.put(Opportunity.RecordTypeId, rtId);
      }
      Schema.SObjectField descriptor = Opportunity.SObjectType.getDescribe()
        .fields.getMap()
        .get('Opportunity_Name_Descriptor__c');
      if (descriptor != null) {
        base.put(descriptor, 'MI Enterprise Test');
      }
      return base;
    }
  }

  /**
   * @description Opportunity flavored for the `Insights_Empowerment` (IE)
   *              record type. IE has the densest validation-rule surface
   *              on dwood_z; this default sets the fields the
   *              `IE_*_Required` family checks at insert (Opportunity_Source,
   *              I&E Core Product, Opportunity_Name_Descriptor) plus
   *              `StageName='Discovery (10%)'` to clear IE_Stage_Locked_On_New.
   *              All custom-field assignments are dynamic so the default
   *              is portable to orgs that may not carry the IE schema.
   */
  public class OpportunityIEDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      Map<Schema.SObjectField, Object> base = new OpportunityDefaults()
        .getFieldDefaults();
      Id rtId = getRecordTypeId(
        Opportunity.SObjectType,
        'Insights_Empowerment'
      );
      if (rtId != null) {
        base.put(Opportunity.RecordTypeId, rtId);
      }
      base.put(Opportunity.StageName, 'Discovery (10%)');
      Map<String, Schema.SObjectField> fieldMap = Opportunity.SObjectType.getDescribe()
        .fields.getMap();
      putIfFieldExists(
        base,
        fieldMap,
        'Opportunity_Source__c',
        'Conference'
      );
      putIfFieldExists(
        base,
        fieldMap,
        'I_E_Core_Product__c',
        'S365'
      );
      putIfFieldExists(
        base,
        fieldMap,
        'Opportunity_Name_Descriptor__c',
        'MI IE Test'
      );
      return base;
    }
  }

  /**
   * @description Opportunity flavored for the `ZNA` record type. ZNA shares
   *              the `Name_Descriptor_Validation` rule with Enterprise/IE
   *              at insert. Other ZNA rules are stage-gated and won't
   *              fire on a default Prospecting-stage insert.
   */
  public class OpportunityZNADefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      Map<Schema.SObjectField, Object> base = new OpportunityDefaults()
        .getFieldDefaults();
      Id rtId = getRecordTypeId(Opportunity.SObjectType, 'ZNA');
      if (rtId != null) {
        base.put(Opportunity.RecordTypeId, rtId);
      }
      Schema.SObjectField descriptor = Opportunity.SObjectType.getDescribe()
        .fields.getMap()
        .get('Opportunity_Name_Descriptor__c');
      if (descriptor != null) {
        base.put(descriptor, 'MI ZNA Test');
      }
      return base;
    }
  }

  // ─── User ─────────────────────────────────────────────────────────────────

  /**
   * @description Generic Standard User default. Use
   *              `TestFactory.createTestUser(true, 'Standard User')` when
   *              you don't need a specific profile; this default is for
   *              callers that want to drive the user through TestFactory's
   *              `createSObject` convention.
   */
  public class UserDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      String suffix = uniqueSuffix();
      Profile p = [
        SELECT Id
        FROM Profile
        WHERE Name = 'Standard User'
        LIMIT 1
      ];
      return new Map<Schema.SObjectField, Object>{
        User.Alias => ('mi' + suffix).left(8),
        User.Email => 'mi-' + suffix + '@example.invalid',
        User.EmailEncodingKey => 'UTF-8',
        User.LastName => 'MI Test User',
        User.LanguageLocaleKey => 'en_US',
        User.LocaleSidKey => 'en_US',
        User.ProfileId => p.Id,
        User.TimeZoneSidKey => 'America/New_York',
        User.UserName => 'mi-' + suffix + '@example.invalid.test'
      };
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /**
   * @description Returns a short unique-ish suffix for default field values.
   *              `Crypto.getRandomInteger()` is fast and good enough for
   *              test-data uniqueness; we don't need cryptographic
   *              guarantees here.
   */
  private static String uniqueSuffix() {
    return String.valueOf(Crypto.getRandomInteger()).right(6);
  }

  /**
   * @description Resolves a RecordTypeId by developer name. Returns null
   *              if the SObject has no record type by that name — the
   *              calling default treats null as "skip the RT assignment"
   *              so per-RT flavors degrade gracefully in orgs that don't
   *              carry the matching record type.
   */
  private static Id getRecordTypeId(
    Schema.SObjectType sot,
    String developerName
  ) {
    Schema.RecordTypeInfo info = sot.getDescribe()
      .getRecordTypeInfosByDeveloperName()
      .get(developerName);
    return info == null ? null : info.getRecordTypeId();
  }

  /**
   * @description Conditional `put` for default maps — sets the value only
   *              if the named field exists on the SObject. Lets a default
   *              reference custom fields that may not be deployed in
   *              every receiving org without throwing at runtime.
   */
  private static void putIfFieldExists(
    Map<Schema.SObjectField, Object> target,
    Map<String, Schema.SObjectField> fieldMap,
    String apiName,
    Object value
  ) {
    Schema.SObjectField token = fieldMap.get(apiName);
    if (token != null) {
      target.put(token, value);
    }
  }
}
