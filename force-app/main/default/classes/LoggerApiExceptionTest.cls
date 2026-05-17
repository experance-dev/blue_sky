/**
 * @description Tests for Logger.logApiException - both overloads insert a
 *              row into API_Exception_Log__c (via DMLManager.insertAsUser
 *              post-B1) and mirror to Logger.error. Includes a regression
 *              test for the catch-block at lines 277-283: when the persist
 *              itself fails, the catch must swallow and Logger.error the
 *              underlying failure rather than propagating.
 *
 * @group Logger
 *
 * Change Log:
 * | Date       | Ticket   | Author      | Description                                  |
 * |------------|----------|-------------|----------------------------------------------|
 * | 2026-05-12 | CSI-7162 | David Wood  | Tests for Logger.logApiException: happy-path persist, catch-block coverage |
 */
@IsTest
private class LoggerApiExceptionTest {
  @IsTest
  static void testLogApiExceptionWithExceptionPersistsRowAndCapturesType() {
    Account a = JiraPushDispatcherTest.buildAccount();

    Test.startTest();
    try {
      throw new DmlException('boom');
    } catch (Exception ex) {
      Logger.logApiException(
        'JCFS',
        'JCFS.API.pushUpdatesToJira',
        'Opportunity',
        a.Id,
        'tx-1',
        ex
      );
    }
    Test.stopTest();

    List<API_Exception_Log__c> rows = [
      SELECT
        API_Name__c,
        Operation__c,
        Source_Object__c,
        Source_Record_Id__c,
        Transaction_Id__c,
        Severity__c,
        Message__c,
        Exception_Type__c,
        Stack_Trace__c
      FROM API_Exception_Log__c
    ];
    Assert.areEqual(1, rows.size());
    Assert.areEqual('JCFS', rows[0].API_Name__c);
    Assert.areEqual('JCFS.API.pushUpdatesToJira', rows[0].Operation__c);
    Assert.areEqual('Opportunity', rows[0].Source_Object__c);
    Assert.areEqual(String.valueOf(a.Id), rows[0].Source_Record_Id__c);
    Assert.areEqual('tx-1', rows[0].Transaction_Id__c);
    Assert.areEqual('ERROR', rows[0].Severity__c);
    Assert.areEqual('boom', rows[0].Message__c);
    Assert.areEqual('System.DmlException', rows[0].Exception_Type__c);
    Assert.areNotEqual(null, rows[0].Stack_Trace__c);
  }

  @IsTest
  static void testLogApiExceptionWithStringMessagePersistsRowWithoutExceptionFields() {
    Test.startTest();
    Logger.logApiException(
      'JCFS',
      'EventBus.publish',
      'Opportunity',
      null,
      'tx-2',
      'Publish failed'
    );
    Test.stopTest();

    List<API_Exception_Log__c> rows = [
      SELECT Message__c, Exception_Type__c, Stack_Trace__c
      FROM API_Exception_Log__c
    ];
    Assert.areEqual(1, rows.size());
    Assert.areEqual('Publish failed', rows[0].Message__c);
    Assert.areEqual(null, rows[0].Exception_Type__c);
    Assert.areEqual(null, rows[0].Stack_Trace__c);
  }

  @IsTest
  static void testLogApiExceptionWithNullExceptionDoesNotThrow() {
    Test.startTest();
    Logger.logApiException(
      'JCFS',
      'op',
      'Opportunity',
      null,
      null,
      (Exception) null
    );
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM API_Exception_Log__c]);
  }

  /**
   * @description Persist-failure catch coverage. Lines 277-283 of Logger.cls
   *              catch any exception from DMLManager.insertAsUser and route
   *              the failure to Logger.error rather than propagating.
   *              We force the persist to fail by sending an API_Name__c
   *              longer than the field's 80-char limit, which trips
   *              STRING_TOO_LONG inside DMLManager.insertAsUser. The whole
   *              call must complete without throwing and produce zero rows
   *              (because the insert itself failed).
   *
   *              This is the only test in the suite that exercises the
   *              "logger-couldn't-log" branch - the safety net that keeps
   *              integration failures from cascading into trigger aborts
   *              just because the API_Exception_Log__c persist hiccupped.
   */
  @IsTest
  static void testLogApiExceptionCatchesPersistFailure() {
    // 81 chars - exceeds API_Name__c Text(80) limit on purpose.
    String oversize = 'X'.repeat(81);
    Integer before = [SELECT COUNT() FROM API_Exception_Log__c];

    Test.startTest();
    // The call must NOT throw - the catch swallows DMLManager's exception.
    Logger.logApiException(
      oversize,
      'op',
      'Opportunity',
      null,
      'tx-persist-fail',
      'force the persist to fail'
    );
    Test.stopTest();

    Integer after = [SELECT COUNT() FROM API_Exception_Log__c];
    Assert.areEqual(
      before,
      after,
      'Persist failure must leave the log unchanged - the catch swallows'
    );
  }

  // ─── PII scrub (follow-up) ──────────────────────────────────────────────────

  @IsTest
  static void testScrubPiiMasksEmailLocalPart() {
    String input = 'Lookup failed for sarah.j@uhc.example.com';
    String scrubbed = Logger.scrubPii(input);
    Assert.areEqual(
      'Lookup failed for sar***@uhc.example.com',
      scrubbed,
      'Local part > 3 chars masks to first-three + ***'
    );
  }

  @IsTest
  static void testScrubPiiHandlesShortLocalPart() {
    String input = 'bob@x.io rejected';
    String scrubbed = Logger.scrubPii(input);
    Assert.areEqual(
      '***@x.io rejected',
      scrubbed,
      'Local part <= 3 chars masks to *** only'
    );
  }

  @IsTest
  static void testScrubPiiHandlesMultipleEmails() {
    String input = 'from alice.smith@a.com to bob.jones@b.com';
    String scrubbed = Logger.scrubPii(input);
    Assert.areEqual('from ali***@a.com to bob***@b.com', scrubbed);
  }

  @IsTest
  static void testScrubPiiNullAndBlankPassThrough() {
    Assert.areEqual(null, Logger.scrubPii(null));
    Assert.areEqual('', Logger.scrubPii(''));
    Assert.areEqual('   ', Logger.scrubPii('   '));
  }

  @IsTest
  static void testScrubPiiPreservesNonEmailContent() {
    String input = 'EngagementSignalRouter.matchPathSatisfied:339 no @ in here';
    String scrubbed = Logger.scrubPii(input);
    Assert.areEqual(input, scrubbed, 'No email pattern leaves input untouched');
  }

  @IsTest
  static void testLogApiExceptionScrubsEmailInPersistedMessage() {
    Test.startTest();
    Logger.logApiException(
      'JCFS',
      'op',
      'Opportunity',
      null,
      'tx-pii',
      'Contact lookup failed for sarah.j@uhc.example.com'
    );
    Test.stopTest();

    List<API_Exception_Log__c> rows = [
      SELECT Message__c
      FROM API_Exception_Log__c
      WHERE Transaction_Id__c = 'tx-pii'
    ];
    Assert.areEqual(1, rows.size());
    Assert.isTrue(
      rows[0].Message__c.contains('sar***@uhc.example.com'),
      'Persisted Message__c must have email masked: ' + rows[0].Message__c
    );
    Assert.isFalse(
      rows[0].Message__c.contains('sarah.j@uhc.example.com'),
      'Raw email must not be persisted to API_Exception_Log__c'
    );
  }
}
