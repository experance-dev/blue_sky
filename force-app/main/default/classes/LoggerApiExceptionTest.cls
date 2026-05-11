/**
 * @description Tests for Logger.logApiException - both overloads insert a
 *              row into API_Exception_Log__c and mirror to Logger.error.
 *
 * @group Logger
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                  |
 * |------------|----------|------------|----------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Coverage for new Logger.logApiException APIs |
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
    Logger.logApiException('JCFS', 'op', 'Opportunity', null, null, (Exception) null);
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM API_Exception_Log__c]);
  }
}
