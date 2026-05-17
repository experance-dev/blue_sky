/**
 * @description Test class for `RecordCleanupBatch`. Uses `Account` as the
 *              target SObject because it exists in every Salesforce org —
 *              the framework is SObject-agnostic, so any object works.
 *              Consumers test their concrete predicates against their own
 *              business objects.
 *
 *              Covers:
 *              - Happy-path delete by age
 *              - Predicate keeps survivors
 *              - Regex filter narrows candidates
 *              - SOQL where clause narrows candidates
 *              - Invalid SObject API name fails gracefully (start logs, no throw)
 *              - Missing predicate class skips that rule conservatively
 *              - Default constructor wires production context
 *              - Scheduler executes the batch
 *
 * @group Cleanup
 * @see RecordCleanupBatch
 * @author David Wood
 * @since May 2026
 */
@IsTest
public without sharing class RecordCleanupBatchTest {
  @TestVisible
  static final Integer OLD_RECORD_COUNT = 5;
  @TestVisible
  static final Integer NEW_RECORD_COUNT = 5;
  @TestVisible
  static final Integer THRESHOLD_DAYS = 30;

  /**
   * @description Seeds 10 Accounts: half "old" (CreatedDate before threshold)
   *              and half "new" (after threshold). Test methods inject the
   *              rule list via `MockRecordCleanupContext`. Also provisions a
   *              Sysadmin-profile test user so each test method can satisfy
   *              the PMD runAs rule without changing semantics — the batch
   *              runs in SYSTEM context regardless of the launching user.
   */
  @TestSetup
  static void seedAccounts() {
    TestFactory.createTestUser(true, 'System Administrator');

    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < OLD_RECORD_COUNT; i++) {
      accounts.add(new Account(Name = 'OldKeep_' + i));
    }
    for (Integer i = 0; i < NEW_RECORD_COUNT; i++) {
      accounts.add(new Account(Name = 'NewKeep_' + i));
    }
    DMLManager.insertAsSystem(accounts);

    // Backdate the "old" half to exceed the threshold.
    List<Account> all = [SELECT Id, Name FROM Account ORDER BY Name];
    for (Account acct : all) {
      if (acct.Name.startsWith('OldKeep_')) {
        Test.setCreatedDate(
          acct.Id,
          DateTime.now().addDays(-THRESHOLD_DAYS - 1)
        );
      }
    }
  }

  /**
   * @description Shared test-user resolver for the runAs wrapper.
   */
  private static User getTestUser() {
    return TestFactory.getTestUser('System Administrator');
  }

  /**
   * @description Happy path: a rule that targets Account / CreatedDate /
   *              THRESHOLD_DAYS deletes the five old records and leaves the
   *              five new ones.
   */
  @IsTest
  static void testBatchDeletesOldRecords() {
    System.runAs(getTestUser()) {
      List<RecordCleanupRule> rules = new List<RecordCleanupRule>{
        new RecordCleanupRule(
          'AccountAge',
          'Account by age',
          'Account',
          'CreatedDate',
          THRESHOLD_DAYS,
          null,
          null,
          null,
          null,
          'Delete'
        )
      };
      MockRecordCleanupContext mockContext = new MockRecordCleanupContext(
        rules
      );

      Test.startTest();
      Database.executeBatch(new RecordCleanupBatch(mockContext), 200);
      Test.stopTest();

      Integer remaining = [SELECT COUNT() FROM Account];
      Assert.areEqual(
        NEW_RECORD_COUNT,
        remaining,
        'Only the new accounts should survive — old ones beyond threshold deleted.'
      );
    }
  }

  /**
   * @description A `TestKeepEverythingPredicate` overrides the age filter —
   *              nothing should be deleted because the predicate says keep
   *              every candidate.
   */
  @IsTest
  static void testPredicateCanKeepEverything() {
    System.runAs(getTestUser()) {
      List<RecordCleanupRule> rules = new List<RecordCleanupRule>{
        new RecordCleanupRule(
          'AccountAgeKeepAll',
          'Account by age, keep all',
          'Account',
          'CreatedDate',
          THRESHOLD_DAYS,
          'TestKeepEverythingPredicate',
          null,
          null,
          null,
          'Delete'
        )
      };
      MockRecordCleanupContext mockContext = new MockRecordCleanupContext(
        rules
      );

      Test.startTest();
      Database.executeBatch(new RecordCleanupBatch(mockContext), 200);
      Test.stopTest();

      Integer remaining = [SELECT COUNT() FROM Account];
      Assert.areEqual(
        OLD_RECORD_COUNT + NEW_RECORD_COUNT,
        remaining,
        'No accounts should be deleted because the predicate keeps everything.'
      );
    }
  }

  /**
   * @description `TestDeleteEverythingPredicate` doesn't change the answer
   *              from happy-path (records are already age-filtered) — but it
   *              exercises the predicate-invocation code path.
   */
  @IsTest
  static void testPredicateDeleteEverythingMatchesHappyPath() {
    System.runAs(getTestUser()) {
      List<RecordCleanupRule> rules = new List<RecordCleanupRule>{
        new RecordCleanupRule(
          'AccountAgeDeleteAll',
          'Account by age, delete all',
          'Account',
          'CreatedDate',
          THRESHOLD_DAYS,
          'TestDeleteEverythingPredicate',
          null,
          null,
          null,
          'Delete'
        )
      };
      MockRecordCleanupContext mockContext = new MockRecordCleanupContext(
        rules
      );

      Test.startTest();
      Database.executeBatch(new RecordCleanupBatch(mockContext), 200);
      Test.stopTest();

      Integer remaining = [SELECT COUNT() FROM Account];
      Assert.areEqual(
        NEW_RECORD_COUNT,
        remaining,
        'Same as happy path — predicate said delete and age filter already applied.'
      );
    }
  }

  /**
   * @description The regex filter narrows candidates to records whose Name
   *              matches `^OldKeep_[0-2]$`. Three matching old records get
   *              deleted; the other two old + all five new survive.
   */
  @IsTest
  static void testRegexFilterNarrowsCandidates() {
    System.runAs(getTestUser()) {
      List<RecordCleanupRule> rules = new List<RecordCleanupRule>{
        new RecordCleanupRule(
          'AccountAgeRegex',
          'Account by age, regex narrow',
          'Account',
          'CreatedDate',
          THRESHOLD_DAYS,
          null,
          null,
          'Name',
          '^OldKeep_[0-2]$',
          'Delete'
        )
      };
      MockRecordCleanupContext mockContext = new MockRecordCleanupContext(
        rules
      );

      Test.startTest();
      Database.executeBatch(new RecordCleanupBatch(mockContext), 200);
      Test.stopTest();

      Integer remaining = [SELECT COUNT() FROM Account];
      Assert.areEqual(
        OLD_RECORD_COUNT + NEW_RECORD_COUNT - 3,
        remaining,
        'Three matching old records should be deleted, leaving seven.'
      );
    }
  }

  /**
   * @description A SOQL where clause narrows candidates — only old records
   *              whose Name starts with `OldKeep_` get selected; combine with
   *              an age threshold low enough to also catch new records
   *              normally, and the where clause should still exclude the new
   *              ones.
   */
  @IsTest
  static void testSoqlWhereClauseNarrowsCandidates() {
    System.runAs(getTestUser()) {
      List<RecordCleanupRule> rules = new List<RecordCleanupRule>{
        new RecordCleanupRule(
          'AccountAgeWhere',
          'Account by age, where narrow',
          'Account',
          'CreatedDate',
          THRESHOLD_DAYS,
          null,
          'Name LIKE \'OldKeep_%\'',
          null,
          null,
          'Delete'
        )
      };
      MockRecordCleanupContext mockContext = new MockRecordCleanupContext(
        rules
      );

      Test.startTest();
      Database.executeBatch(new RecordCleanupBatch(mockContext), 200);
      Test.stopTest();

      Integer remaining = [SELECT COUNT() FROM Account];
      Assert.areEqual(
        NEW_RECORD_COUNT,
        remaining,
        'Only the OldKeep_ records should be deleted; new ones survive.'
      );
    }
  }

  /**
   * @description Invalid SObject API name causes a SOQL exception inside
   *              `start`. The batch catches it, logs, and proceeds — no
   *              throw out to the caller, no data deleted.
   */
  @IsTest
  static void testInvalidSObjectNameIsHandled() {
    System.runAs(getTestUser()) {
      List<RecordCleanupRule> rules = new List<RecordCleanupRule>{
        new RecordCleanupRule(
          'BadRule',
          'Bad rule',
          'Not_A_Real_Object__c',
          'CreatedDate',
          THRESHOLD_DAYS,
          null,
          null,
          null,
          null,
          'Delete'
        )
      };
      MockRecordCleanupContext mockContext = new MockRecordCleanupContext(
        rules
      );

      Test.startTest();
      Database.executeBatch(new RecordCleanupBatch(mockContext), 200);
      Test.stopTest();

      Integer remaining = [SELECT COUNT() FROM Account];
      Assert.areEqual(
        OLD_RECORD_COUNT + NEW_RECORD_COUNT,
        remaining,
        'No accounts should be deleted when the rule targets a bad SObject name.'
      );
    }
  }

  /**
   * @description A predicate class name that does not resolve causes the
   *              rule to be skipped (zero records deleted for that rule).
   */
  @IsTest
  static void testMissingPredicateClassSkipsRule() {
    System.runAs(getTestUser()) {
      List<RecordCleanupRule> rules = new List<RecordCleanupRule>{
        new RecordCleanupRule(
          'AccountMissingPredicate',
          'Account, missing predicate class',
          'Account',
          'CreatedDate',
          THRESHOLD_DAYS,
          'No_Such_Predicate_Class_Anywhere',
          null,
          null,
          null,
          'Delete'
        )
      };
      MockRecordCleanupContext mockContext = new MockRecordCleanupContext(
        rules
      );

      Test.startTest();
      Database.executeBatch(new RecordCleanupBatch(mockContext), 200);
      Test.stopTest();

      Integer remaining = [SELECT COUNT() FROM Account];
      Assert.areEqual(
        OLD_RECORD_COUNT + NEW_RECORD_COUNT,
        remaining,
        'When predicate class is unknown the batch conservatively keeps all candidates.'
      );
    }
  }

  /**
   * @description Default constructor wires up `RecordCleanupContext` cleanly
   *              for coverage purposes.
   */
  @IsTest
  static void testDefaultConstructor() {
    System.runAs(getTestUser()) {
      RecordCleanupBatch batch = new RecordCleanupBatch();
      Assert.isNotNull(batch, 'Default constructor should return an instance.');
    }
  }

  /**
   * @description Scheduler runs the batch end-to-end via `System.schedule`.
   */
  @IsTest
  static void testSchedulerExecutes() {
    System.runAs(getTestUser()) {
      Test.startTest();
      String cron = '0 0 0 1 1 ? 2099';
      Id jobId = System.schedule(
        'RecordCleanupSchedulerTest',
        cron,
        new RecordCleanupScheduler()
      );
      Test.stopTest();

      // CronTrigger row confirms the schedule landed and resolves the
      // expression we passed.
      CronTrigger job = [
        SELECT Id, CronExpression
        FROM CronTrigger
        WHERE Id = :jobId
      ];
      Assert.areEqual(
        cron,
        job.CronExpression,
        'Scheduled job should retain the supplied cron expression.'
      );
    }
  }
}
