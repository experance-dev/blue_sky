/**
 * @description Instantiates every inner-class defaults shape registered in
 *              `TestFactoryDefaults` and exercises its `getFieldDefaults()`
 *              entry point. In the Wave A skeleton each shape returns an
 *              empty map; the test confirms that every class is reachable
 *              through reflection and that the interface contract holds.
 *              Wave B will extend each assertion as the defaults are filled
 *              in to satisfy active validation rules in the target org.
 * @group Testing
 * @author David Wood
 * @since May 2026
 * @last May 2026 — initial port into Zelis engagement-attribution worktree
 */
@IsTest
private class TestFactoryDefaultsTest {
  @IsTest
  static void accountDefaultsResolveAndExposeFieldMap() {
    TestFactoryDefaults.AccountDefaults defaults = new TestFactoryDefaults.AccountDefaults();
    Map<Schema.SObjectField, Object> fields = defaults.getFieldDefaults();

    Assert.areNotEqual(
      null,
      fields,
      'AccountDefaults must return a non-null field map.'
    );
  }

  @IsTest
  static void contactDefaultsResolveAndExposeFieldMap() {
    TestFactoryDefaults.ContactDefaults defaults = new TestFactoryDefaults.ContactDefaults();
    Map<Schema.SObjectField, Object> fields = defaults.getFieldDefaults();

    Assert.areNotEqual(
      null,
      fields,
      'ContactDefaults must return a non-null field map.'
    );
  }

  @IsTest
  static void opportunityDefaultsResolveAndExposeFieldMap() {
    TestFactoryDefaults.OpportunityDefaults defaults = new TestFactoryDefaults.OpportunityDefaults();
    Map<Schema.SObjectField, Object> fields = defaults.getFieldDefaults();

    Assert.areNotEqual(
      null,
      fields,
      'OpportunityDefaults must return a non-null field map.'
    );
  }

  @IsTest
  static void userDefaultsResolveAndExposeFieldMap() {
    TestFactoryDefaults.UserDefaults defaults = new TestFactoryDefaults.UserDefaults();
    Map<Schema.SObjectField, Object> fields = defaults.getFieldDefaults();

    Assert.areNotEqual(
      null,
      fields,
      'UserDefaults must return a non-null field map.'
    );
  }
}
