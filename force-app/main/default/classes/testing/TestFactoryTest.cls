/**
 * @description Exercises every public entry point on `TestFactory`, including
 *              the reflection-driven defaults lookup, the caller-overrides-
 *              defaults precedence rule, the bulk `createSObjectList` clone
 *              behaviour, and the fake-id generator. Inserts are deliberately
 *              limited to records whose Wave A defaults are empty, so the
 *              tests confirm the wiring of the factory itself without
 *              depending on validation-rule-passing field values; Wave B will
 *              extend coverage as each defaults class is filled in.
 * @group Testing
 * @author David Wood
 * @since May 2026
 * @last May 2026 — initial port into Zelis engagement-attribution worktree
 */
@IsTest
private class TestFactoryTest {
  @IsTest
  static void createSObjectAppliesDefaultsByConvention() {
    Account templated = (Account) TestFactory.createSObject(new Account());

    // Wave A skeleton: AccountDefaults returns an empty map, so the resolved
    // record carries no defaulted fields — but it is non-null, proving the
    // reflection lookup succeeded without throwing.
    Assert.areNotEqual(
      null,
      templated,
      'createSObject should resolve the AccountDefaults inner class.'
    );
  }

  @IsTest
  static void createSObjectRespectsCallerSuppliedValues() {
    Account preset = new Account(Name = 'Caller Wins', BillingState = 'NY');

    Account result = (Account) TestFactory.createSObject(preset);

    Assert.areEqual(
      'Caller Wins',
      result.Name,
      'Caller-supplied Name must not be overwritten by defaults.'
    );
    Assert.areEqual(
      'NY',
      result.BillingState,
      'Caller-supplied BillingState must not be overwritten by defaults.'
    );
  }

  @IsTest
  static void createSObjectByExplicitClassNameSucceeds() {
    Account result = (Account) TestFactory.createSObject(
      new Account(Name = 'Explicit'),
      'TestFactoryDefaults.AccountDefaults'
    );

    Assert.areEqual(
      'Explicit',
      result.Name,
      'Explicit defaults class must apply.'
    );
  }

  @IsTest
  static void createSObjectByInvalidClassNameThrows() {
    Boolean threw = false;
    try {
      TestFactory.createSObject(
        new Account(),
        'TestFactoryDefaults.NoSuchDefaults'
      );
    } catch (TestFactory.TestFactoryException e) {
      threw = true;
      Assert.isTrue(
        e.getMessage().contains('Invalid defaults class'),
        'Exception message should name the offending class.'
      );
    }
    Assert.isTrue(
      threw,
      'Unresolvable defaults class must raise TestFactoryException.'
    );
  }

  @IsTest
  static void createSObjectListBuildsRequestedSize() {
    List<Account> built = (List<Account>) TestFactory.createSObjectList(
      new Account(Name = 'Bulk'),
      5
    );

    Assert.areEqual(
      5,
      built.size(),
      'createSObjectList must build the requested count.'
    );
    Assert.areEqual(
      'Bulk 0',
      built[0].Name,
      'First clone should carry index-zero name uniquifier.'
    );
    Assert.areEqual(
      'Bulk 4',
      built[4].Name,
      'Last clone should carry index-four name uniquifier.'
    );
  }

  @IsTest
  static void createSObjectListUsesNameFieldMapForContacts() {
    List<Contact> built = (List<Contact>) TestFactory.createSObjectList(
      new Contact(LastName = 'Cohort'),
      3
    );

    Assert.areEqual(
      3,
      built.size(),
      'createSObjectList should honour the requested size.'
    );
    Assert.areEqual(
      'Cohort 0',
      built[0].LastName,
      'Contact uniquifier should hang off LastName, not Name.'
    );
  }

  @IsTest
  static void createSObjectListExplicitDefaultsClassResolves() {
    List<Opportunity> built = (List<Opportunity>) TestFactory.createSObjectList(
      new Opportunity(Name = 'Pipeline'),
      2,
      'TestFactoryDefaults.OpportunityDefaults'
    );

    Assert.areEqual(
      2,
      built.size(),
      'Explicit-defaults overload should still bulk-clone.'
    );
    Assert.areEqual(
      'Pipeline 0',
      built[0].Name,
      'Bulk clones should still receive the index uniquifier.'
    );
  }

  @IsTest
  static void getFakeIdReturnsKeyPrefixedId() {
    String fake = TestFactory.getFakeId(Account.SObjectType);

    // TODO: Wave B/C — investigate getFakeId() length. Docstring claims 18 chars
    // but the implementation produces 15 (3-char key prefix + 12-char padded counter).
    // Confirm whether 15-char ids are sufficient for downstream callers or whether
    // the implementation should extend to a full 18.
    Assert.areEqual(
      15,
      fake.length(),
      'Fake id is currently produced at 15 characters by the implementation.'
    );
    Assert.isTrue(
      fake.startsWith(Account.SObjectType.getDescribe().getKeyPrefix()),
      'Fake id must carry the SObject key prefix.'
    );
  }

  @IsTest
  static void getFakeIdReturnsDistinctValuesPerCall() {
    String first = TestFactory.getFakeId(Account.SObjectType);
    String second = TestFactory.getFakeId(Account.SObjectType);

    Assert.areNotEqual(
      first,
      second,
      'Successive fake ids must differ within a test run.'
    );
  }

  @IsTest
  static void invalidateSObjectListBlanksNameField() {
    List<Account> built = (List<Account>) TestFactory.createSObjectList(
      new Account(Name = 'Bad'),
      2
    );

    List<SObject> mutated = TestFactory.invalidateSObjectList(built);

    Assert.areEqual(
      '',
      mutated[0].get('Name'),
      'invalidateSObjectList should blank the Name field.'
    );
    Assert.areEqual(
      '',
      mutated[1].get('Name'),
      'invalidateSObjectList should blank every record.'
    );
  }

  @IsTest
  static void getRecordTypesReturnsMap() {
    Map<String, Schema.RecordTypeInfo> infos = TestFactory.getRecordTypes(
      'Account'
    );

    Assert.areNotEqual(
      null,
      infos,
      'getRecordTypes must return a non-null map.'
    );
  }
}
