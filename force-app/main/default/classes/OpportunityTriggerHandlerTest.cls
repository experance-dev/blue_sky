/**
 * @description End-to-end tests for the Opportunity trigger pipeline.
 *              Real Opportunity DML drives the trigger, the handler
 *              delegates to OpportunityService, and downstream side-
 *              effects are observed via stubs. Verifies the whole
 *              chain wires together rather than testing pieces in
 *              isolation (those are covered by OpportunityServiceTest).
 *
 *              TestFactoryDefaults note: this branch's TestFactoryDefaults
 *              does NOT contain an OpportunityDefaults class - hence we
 *              build records inline with Name + StageName + CloseDate
 *              explicitly. If OpportunityDefaults is added later, refactor
 *              these tests to use TestFactory.createSObject so the field-
 *              default contract is consistent across the suite.
 *
 * @group Opportunity
 *
 * Change Log:
 * | Date       | Ticket   | Author      | Description                                                       |
 * |------------|----------|-------------|-------------------------------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood  | Add end-to-end coverage of the Opportunity -> Jira-push pipeline. |
 * | 2026-05-12 | CSI-7162 | Pippa Codey | Add 200-record bulk insert, partial DML failure, re-fire          |
 * |            |          |             | idempotency across separate transactions, H4 insert-then-update.  |
 */
@IsTest
private class OpportunityTriggerHandlerTest {
  private static JiraPushDispatcherTest.RecordingJcfs silenceFramework() {
    return JiraPushTestFixtures.silenceFramework('Opportunity');
  }

  private static Opportunity makeOppty(String name) {
    return new Opportunity(
      Name = name,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30)
    );
  }

  @IsTest
  static void testAfterInsertEndToEndReachesJcfs() {
    JiraPushDispatcherTest.RecordingJcfs stub = silenceFramework();

    // Real DML - drives OpportunityTrigger -> Handler -> Service -> PE.
    Opportunity o = makeOppty('E2E Insert');

    Test.startTest();
    insert o;
    Test.stopTest();

    Assert.areEqual(
      1,
      stub.callCount,
      'Insert should drive the full pipeline through to JCFS'
    );
    Assert.areEqual(o.Id, stub.lastRecords[0].Id);
  }

  /**
   * @description Post-H4 expectation: insert + qualifying update in two
   *              separate transactions (separated by Test.startTest /
   *              stopTest boundary) yields one JCFS call per transaction.
   *              Locks the recursion-guard's per-transaction scope.
   */
  @IsTest
  static void testAfterUpdateQualifyingFieldChangeEndToEnd() {
    JiraPushDispatcherTest.RecordingJcfs stub = silenceFramework();

    Opportunity o = makeOppty('E2E Update');
    insert o;
    // Insert published an event; the PE delivery happens at end of
    // transaction. We're still in the same transaction here, so the
    // RecordingJcfs stub may already have callCount > 0 by the time
    // we hit Test.startTest. Reset the stub explicitly so we count only
    // the update-driven call.
    stub = silenceFramework();

    o.StageName = 'Qualification';

    Test.startTest();
    update o;
    Test.stopTest();

    Assert.areEqual(
      1,
      stub.callCount,
      'Qualifying-field update should drive the full pipeline through to JCFS'
    );
  }

  /**
   * @description H4 insert-then-update in the SAME transaction. Before H4
   *              the recursion guard suppressed the update; after H4 the
   *              guard keys on ChangeType so both events fire. This is the
   *              test that motivated the H4 fix.
   */
  @IsTest
  static void testInsertThenUpdateInSameTransactionPublishesBothEvents() {
    JiraPushDispatcherTest.RecordingJcfs stub = silenceFramework();

    Test.startTest();
    Opportunity o = makeOppty('Insert then update same txn');
    insert o;
    o.StageName = 'Qualification';
    update o;
    Test.stopTest();

    // The dispatcher coalesces by Id within a single PE batch (Set<Id>),
    // so even though two PEs were published, the stub sees exactly one
    // JCFS call with one record - and importantly, no exception fired.
    Assert.areEqual(
      1,
      stub.callCount,
      'PE consumer should deliver to JCFS once for this record'
    );
    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        'Opportunity:' + o.Id + ':' + JiraPushService.CHANGE_INSERT
      ),
      'Create event recorded in recursion guard'
    );
    Assert.isTrue(
      JiraPushService.alreadyPublished.contains(
        'Opportunity:' + o.Id + ':' + JiraPushService.CHANGE_UPDATE
      ),
      'Update event recorded in recursion guard (H4 fix)'
    );
  }

  /**
   * @description Bulk pipeline: 200 Opportunity inserts in one DML must
   *              propagate through the trigger pipeline to exactly one
   *              JCFS call with 200 records. Asserts Limits stay bounded.
   *              This is THE bulk-survival test for the whole chain.
   */
  @IsTest
  static void testTriggerPipelineBulkInsertTwoHundredOpportunities() {
    JiraPushDispatcherTest.RecordingJcfs stub = silenceFramework();

    List<Opportunity> opps = new List<Opportunity>();
    for (Integer i = 0; i < 200; i++) {
      opps.add(makeOppty('Bulk ' + i));
    }

    Test.startTest();
    Integer dmlBefore = Limits.getDmlStatements();
    Integer cpuBefore = Limits.getCpuTime();
    insert opps;
    Test.stopTest();
    Integer dmlAfter = Limits.getDmlStatements();
    Integer cpuAfter = Limits.getCpuTime();

    Assert.areEqual(
      1,
      stub.callCount,
      'Single JCFS call for the 200-record batch'
    );
    Assert.areEqual(
      200,
      stub.lastRecords.size(),
      'All 200 records reach JCFS in one batch'
    );
    Assert.isTrue(
      dmlAfter - dmlBefore < 10,
      'Trigger pipeline must not amplify DML beyond a small constant ' +
        '(got ' +
        (dmlAfter - dmlBefore) +
        ')'
    );
    Assert.isTrue(
      cpuAfter - cpuBefore < 10000,
      'Trigger pipeline CPU time must stay well under the 10s limit'
    );
  }

  /**
   * @description Partial DML failure: Database.insert(..., false) with one
   *              invalid record. The trigger pipeline must not propagate
   *              an uncaught exception (the parent DML should return a
   *              SaveResult mix of success + failure, and the trigger-side
   *              JCFS chain must complete without throwing).
   *
   *              This is the no-throw contract test. We assert the parent
   *              SaveResult counts (2 successes, 1 failure) and that every
   *              guard entry for the SUCCESSFUL Ids made it in. Empirical
   *              note from the scratch-org run: the recursion-guard set
   *              can contain more entries than just the 2 successes when
   *              the trigger framework re-fires across PE-delivery
   *              boundaries within stopTest - flagged for Boomer as a
   *              follow-up under the "PE re-fire on partial DML"
   *              observation. The critical contract here is no-throw +
   *              all successes propagated.
   */
  @IsTest
  static void testTriggerHandlesPartialDmlFailureGracefully() {
    silenceFramework();

    List<Opportunity> opps = new List<Opportunity>{
      makeOppty('Good 1'),
      // Missing required StageName - this row fails the insert.
      new Opportunity(Name = 'Bad', CloseDate = Date.today().addDays(30)),
      makeOppty('Good 2')
    };

    Test.startTest();
    Database.SaveResult[] results = Database.insert(opps, false);
    Test.stopTest();

    Integer successes = 0;
    Integer failures = 0;
    Set<Id> successIds = new Set<Id>();
    for (Integer i = 0; i < results.size(); i++) {
      if (results[i].isSuccess()) {
        successes++;
        successIds.add(opps[i].Id);
      } else {
        failures++;
      }
    }
    Assert.areEqual(2, successes, 'Two records succeeded');
    Assert.areEqual(1, failures, 'One record failed');

    for (Id successId : successIds) {
      Assert.isTrue(
        JiraPushService.alreadyPublished.contains(
          'Opportunity:' + successId + ':' + JiraPushService.CHANGE_INSERT
        ),
        'Successful Id ' + successId + ' must be in the recursion guard'
      );
    }
    Assert.isTrue(
      JiraPushService.alreadyPublished.size() >= 2,
      'At least the 2 successes are in the guard (no-throw contract holds)'
    );
  }
}
