/**
 * @description Default field-value sets for every SObject type used in tests.
 *              Inner-class names follow the convention `[ObjectName]Defaults` and
 *              `TestFactory.createSObject(sObj)` auto-discovers them by reflection.
 *              Custom-object suffixes (`__c`, `__`) are stripped before the lookup
 *              so a defaults class for `Engagement_Touch__c` would be named
 *              `Engagement_TouchDefaults`. A named variant (for example
 *              `OpportunityWithAccountDefaults`) lets callers reach a different
 *              defaults shape for the same SObjectType.
 *
 *              Composition lives in the defaults: a defaults class that needs a
 *              parent record should call `TestFactory.createSObject(...)` itself,
 *              so improvements to `AccountDefaults` propagate automatically to
 *              every child defaults class that hangs off it.
 *
 *              CSI-7162 Wave A skeleton kept the inner classes empty so the
 *              TestFactory entry points compile. Wave B (this change) populates
 *              OpportunityDefaults with the single field required by an active
 *              VR in dwood_z that fires on every Opportunity insert. Every
 *              other defaults class stays empty - add fields here as VRs are
 *              encountered so the fix lands in one place, not scattered across
 *              17 test classes.
 * @group Testing
 * @author David Wood
 * @since December 2020
 * @last May 2026 — CSI-7162 Wave B: populate OpportunityDefaults with
 *                 Opportunity_Name_Descriptor__c so every test inserting an
 *                 Opportunity satisfies the dwood_z VR by default.
 */
@IsTest
public without sharing class TestFactoryDefaults {
  // Constants referenced by TestFactory at compile time.
  public static final String TEST_USER_PERMISSION = 'TestUserPermission';
  public static final String DEFAULT_PRODUCT_FAMILY = '';
  public static final String DEFAULT_WARRANTY_PRODUCT = '';

  // TODO: Wave B — build Account defaults to satisfy active validation rules.
  public class AccountDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{};
    }
  }

  // TODO: Wave B — build Contact defaults to satisfy active validation rules.
  public class ContactDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{};
    }
  }

  /**
   * @description Named variant of ContactDefaults referenced by
   *              UtilitiesHelperTest and UtilitiesTest via reflection
   *              (`TestFactory.createSObject(sObj, 'TestFactoryDefaults.ContactWithAccountDefaults')`).
   *              Stubbed Wave A; Wave B can layer Account composition in.
   */
  public class ContactWithAccountDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{};
    }
  }

  /**
   * @description Defaults applied to every Opportunity built via
   *              `TestFactory.createSObject(new Opportunity(...))`.
   *              `Opportunity_Name_Descriptor__c` is required by an active
   *              VR in dwood_z; setting it here means every existing test
   *              inherits the fix without per-class edits.
   */
  public class OpportunityDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{
        Opportunity.Opportunity_Name_Descriptor__c => 'Test'
      };
    }
  }

  // TODO: Wave B — build User defaults to satisfy active validation rules.
  public class UserDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{};
    }
  }
}
