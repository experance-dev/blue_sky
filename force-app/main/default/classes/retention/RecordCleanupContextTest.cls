/**
 * @description Test class for `RecordCleanupContext` — verifies CMDT reads
 *              return the active rules in stable order.
 *
 *              Because the test depends on whatever `Record_Retention_Rule__mdt`
 *              rows happen to exist in the test org, it asserts only on
 *              shape — not specific developer names — to stay portable across
 *              orgs.
 *
 * @group Cleanup
 * @see RecordCleanupContext
 * @author David Wood
 * @since May 2026
 */
@IsTest
public without sharing class RecordCleanupContextTest {
  /**
   * @description Calling `getActiveRules` on the real context returns a list
   *              (possibly empty) without throwing. Every entry is a fully-
   *              populated `RecordCleanupRule`.
   */
  @IsTest
  static void testGetActiveRulesReturnsList() {
    Test.startTest();
    RecordCleanupContext context = new RecordCleanupContext();
    List<RecordCleanupRule> rules = context.getActiveRules();
    Test.stopTest();

    Assert.isNotNull(
      rules,
      'Expected getActiveRules to return a list, not null.'
    );

    for (RecordCleanupRule rule : rules) {
      Assert.isNotNull(
        rule.developerName,
        'Every rule should carry a developer name.'
      );
      Assert.isNotNull(
        rule.sobjectApiName,
        'Every rule should carry an SObject API name.'
      );
      Assert.isNotNull(
        rule.ageThresholdDays,
        'Every rule should carry an age threshold (number of days).'
      );
    }
  }

  /**
   * @description `RecordCleanupRule.fromMetadata` populates every property
   *              from a CMDT row and defaults `ageFieldApiName` to
   *              `CreatedDate` when blank.
   */
  @IsTest
  static void testRuleFromMetadataDefaultsAgeField() {
    Record_Retention_Rule__mdt row = new Record_Retention_Rule__mdt(
      DeveloperName = 'TestRule',
      Label = 'Test Rule',
      SObject_API_Name__c = 'Account',
      Age_Field_API_Name__c = null,
      Age_Threshold_Days__c = 30,
      Action__c = 'Delete',
      Active__c = true
    );

    RecordCleanupRule rule = RecordCleanupRule.fromMetadata(row);

    Assert.areEqual(
      RecordCleanupRule.DEFAULT_AGE_FIELD,
      rule.ageFieldApiName,
      'Blank age field should default to CreatedDate.'
    );
    Assert.areEqual(30, rule.ageThresholdDays, 'Threshold should map cleanly.');
    Assert.areEqual('Account', rule.sobjectApiName, 'SObject should map.');
    Assert.areEqual('Delete', rule.action, 'Action should map.');
    Assert.isFalse(rule.hasPredicate(), 'No predicate configured.');
    Assert.isFalse(rule.hasRegexFilter(), 'No regex configured.');
  }

  /**
   * @description `hasPredicate` and `hasRegexFilter` correctly reflect the
   *              presence of optional fields.
   */
  @IsTest
  static void testRulePredicateAndRegexFlags() {
    RecordCleanupRule withPredicate = new RecordCleanupRule(
      'R',
      'R',
      'Account',
      'CreatedDate',
      10,
      'TestKeepEverythingPredicate',
      null,
      null,
      null,
      'Delete'
    );
    Assert.isTrue(
      withPredicate.hasPredicate(),
      'Predicate flag should be set.'
    );
    Assert.isFalse(
      withPredicate.hasRegexFilter(),
      'Regex flag should not be set.'
    );

    RecordCleanupRule withRegex = new RecordCleanupRule(
      'R',
      'R',
      'Account',
      'CreatedDate',
      10,
      null,
      null,
      'Name',
      '^Test.*',
      'Delete'
    );
    Assert.isFalse(
      withRegex.hasPredicate(),
      'Predicate flag should not be set.'
    );
    Assert.isTrue(withRegex.hasRegexFilter(), 'Regex flag should be set.');
  }
}
