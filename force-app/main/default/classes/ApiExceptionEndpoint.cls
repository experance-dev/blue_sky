/**
 * @description Inserts an API_Exception_Log__c row and mirrors the same
 *              message to Logger.error. Wraps its own DML so callers never
 *              need to try/catch.
 *
 * @group Logger
 */
public with sharing class ApiExceptionEndpoint {
  private static final String CLASS_NAME = 'ApiExceptionEndpoint';

  public static void log(
    String apiName,
    String operation,
    String sourceObject,
    Id sourceRecordId,
    String transactionId,
    Exception ex
  ) {
    log(
      apiName,
      operation,
      sourceObject,
      sourceRecordId,
      transactionId,
      ex == null ? null : ex.getMessage(),
      ex == null ? null : ex.getTypeName(),
      ex == null ? null : ex.getStackTraceString()
    );
  }

  public static void log(
    String apiName,
    String operation,
    String sourceObject,
    Id sourceRecordId,
    String transactionId,
    String message
  ) {
    log(
      apiName,
      operation,
      sourceObject,
      sourceRecordId,
      transactionId,
      message,
      null,
      null
    );
  }

  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static void log(
    String apiName,
    String operation,
    String sourceObject,
    Id sourceRecordId,
    String transactionId,
    String message,
    String exceptionType,
    String stackTrace
  ) {
    Logger.error(
      '[' + apiName + '/' + operation + '] ' + message,
      CLASS_NAME,
      'log'
    );
    try {
      insert new API_Exception_Log__c(
        API_Name__c = apiName,
        Operation__c = operation,
        Source_Object__c = sourceObject,
        Source_Record_Id__c = sourceRecordId == null
          ? null
          : String.valueOf(sourceRecordId),
        Transaction_Id__c = transactionId,
        Severity__c = 'ERROR',
        Message__c = message,
        Exception_Type__c = exceptionType,
        Stack_Trace__c = stackTrace
      );
    } catch (Exception writeFail) {
      Logger.error(
        'Could not persist API_Exception_Log__c: ' + writeFail.getMessage(),
        CLASS_NAME,
        'log'
      );
    }
  }
}
