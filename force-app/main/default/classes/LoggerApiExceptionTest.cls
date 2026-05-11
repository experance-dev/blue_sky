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
  static void logApiException_withException_persistsRowAndCapturesType() {
    Account a = (Account) TestFactory.createSObject(new Account(), true);

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
    System.assertEquals(1, rows.size());
    System.assertEquals('JCFS', rows[0].API_Name__c);
    System.assertEquals('JCFS.API.pushUpdatesToJira', rows[0].Operation__c);
    System.assertEquals('Opportunity', rows[0].Source_Object__c);
    System.assertEquals(String.valueOf(a.Id), rows[0].Source_Record_Id__c);
    System.assertEquals('tx-1', rows[0].Transaction_Id__c);
    System.assertEquals('ERROR', rows[0].Severity__c);
    System.assertEquals('boom', rows[0].Message__c);
    System.assertEquals('System.DmlException', rows[0].Exception_Type__c);
    System.assertNotEquals(null, rows[0].Stack_Trace__c);
  }

  @IsTest
  static void logApiException_withStringMessage_persistsRowWithoutExceptionFields() {
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
    System.assertEquals(1, rows.size());
    System.assertEquals('Publish failed', rows[0].Message__c);
    System.assertEquals(null, rows[0].Exception_Type__c);
    System.assertEquals(null, rows[0].Stack_Trace__c);
  }

  @IsTest
  static void logApiException_withNullException_doesNotThrow() {
    Test.startTest();
    Logger.logApiException('JCFS', 'op', 'Opportunity', null, null, (Exception) null);
    Test.stopTest();

    System.assertEquals(1, [SELECT COUNT() FROM API_Exception_Log__c]);
  }
}
