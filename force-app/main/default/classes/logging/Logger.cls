/*
 * Copyright (c) 2020-2026 David Wood
 * Licensed under the MIT License — see LICENSE in the repo root.
 * Source: <https://github.com/experance-dev/salesforce-utilities>
 */
/**
 * @description Centralized logging utility for Salesforce applications.
 *              Provides a simple interface to log messages with varying levels of severity.
 *              Supports logging the originating class and method names.
 *              The `printLogs` flag (driven by Log_Setting__mdt when present) gates debug-level
 *              output; info/warn/error always write. `logException` captures message + stack trace.
 *              When Log_Setting__mdt is absent from the org, printLogs defaults to true so
 *              Logger remains usable in scratch / partial orgs without configuration.
 * @group Logger
 * @since September 2024
 * @author David Wood
 * @last May 2026 — unconfigured-org safe defaults for Log_Setting__mdt
 */
public inherited sharing class Logger {
  // ─── Core dispatch ───────────────────────────────────────────────────────────

  /**
   * @param level The logging level (e.g., DEBUG, INFO, WARN, ERROR, FATAL)
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  @TestVisible
  @suppresswarnings('PMD.ExcessiveParameterList')
  private static void log(
    System.LoggingLevel level,
    String message,
    String className,
    String methodName
  ) {
    String logMessage = formatLogMessage(level, message, className, methodName);
    storeLog(level, logMessage);
  }

  /**
   * @param level The logging level (e.g., DEBUG, INFO, WARN, ERROR, FATAL)
   * @param message The message to log
   */
  public static void log(System.LoggingLevel level, String message) {
    log(level, message, null, null);
  }

  // ─── Severity helpers ─────────────────────────────────────────────────────────

  /**
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void info(String message, String className, String methodName) {
    log(System.LoggingLevel.INFO, message, className, methodName);
  }

  /**
   * @param message The message to log
   */
  public static void info(String message) {
    log(System.LoggingLevel.INFO, message);
  }

  /**
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void error(
    String message,
    String className,
    String methodName
  ) {
    log(System.LoggingLevel.ERROR, message, className, methodName);
  }

  /**
   * @param message The message to log
   */
  public static void error(String message) {
    log(System.LoggingLevel.ERROR, message);
  }

  /**
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void warn(String message, String className, String methodName) {
    log(System.LoggingLevel.WARN, message, className, methodName);
  }

  /**
   * @param message The message to log
   */
  public static void warn(String message) {
    log(System.LoggingLevel.WARN, message);
  }

  // ─── Debug helpers (gated by printLogs) ──────────────────────────────────────

  /**
   * @param message The message to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void debug(
    String message,
    String className,
    String methodName
  ) {
    if (printLogs) {
      log(System.LoggingLevel.DEBUG, message, className, methodName);
    }
  }

  /**
   * @param message The message to log
   */
  public static void debug(String message) {
    if (printLogs) {
      log(System.LoggingLevel.DEBUG, message);
    }
  }

  /**
   * @param message The message to log
   * @param objectToParse Object to serialize as pretty JSON alongside the message
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  @suppresswarnings('PMD.ExcessiveParameterList')
  public static void debug(
    String message,
    Object objectToParse,
    String className,
    String methodName
  ) {
    if (printLogs) {
      logDebugWithObject(message, objectToParse, className, methodName);
    }
  }

  // ─── Exception logging ────────────────────────────────────────────────────────

  /**
   * @param e The exception to log
   * @param className The name of the class where the log is generated
   * @param methodName The name of the method where the log is generated
   */
  public static void logException(
    Exception e,
    String className,
    String methodName
  ) {
    if (printLogs) {
      logExceptionInternal(e, className, methodName);
    }
  }

  // ─── Private helpers ──────────────────────────────────────────────────────────

  private static void logDebugWithObject(
    String message,
    Object objectToParse,
    String className,
    String methodName
  ) {
    try {
      String jsonString = JSON.serializePretty(objectToParse);
      log(
        System.LoggingLevel.DEBUG,
        message + '\n' + jsonString,
        className,
        methodName
      );
    } catch (Exception e) {
      log(
        System.LoggingLevel.WARN,
        'Failed to parse object to JSON',
        className,
        methodName
      );
      log(
        System.LoggingLevel.DEBUG,
        message + '\n' + objectToParse,
        className,
        methodName
      );
    }
  }

  private static void logExceptionInternal(
    Exception e,
    String className,
    String methodName
  ) {
    try {
      String message =
        'Exception in ' +
        className +
        '.' +
        methodName +
        ': ' +
        e.getMessage() +
        '\nStackTrace: ' +
        e.getStackTraceString();
      log(System.LoggingLevel.ERROR, message, className, methodName);
    } catch (Exception ex) {
      log(
        System.LoggingLevel.WARN,
        'Failed to log exception',
        className,
        methodName
      );
      log(
        System.LoggingLevel.ERROR,
        'Exception in ' + className + '.' + methodName + ': ' + e.getMessage()
      );
    }
  }

  // ─── Infrastructure ───────────────────────────────────────────────────────────

  /**
   * @description Sentinel set to true when Log_Setting__mdt is not deployed in the
   *              target org. Tests can assert against this to confirm graceful fallback.
   */
  @TestVisible
  private static Boolean logSettingUnconfigured = false;

  /**
   * @return True if debug output is enabled. Reads from Log_Setting__mdt 'defaults' when
   *         present; falls back to true (and flips `logSettingUnconfigured`) when the
   *         CMDT type or record is absent at runtime — so an unconfigured org still logs.
   */
  @TestVisible
  private static Boolean printLogs {
    get {
      if (printLogs == null) {
        printLogs = resolvePrintLogsDefault();
      }
      return printLogs;
    }
    set;
  }

  /**
   * @description Resolves the Print_Debug_Logs__c value via dynamic SOQL so an org missing
   *              the Log_Setting__mdt type or its 'defaults' record never blocks compilation
   *              or execution. Any failure path defaults to true and marks the sentinel.
   * @return True when the CMDT is absent / unreadable, or the configured value otherwise.
   */
  @TestVisible
  private static Boolean resolvePrintLogsDefault() {
    try {
      List<SObject> records = Database.query(
        'SELECT Print_Debug_Logs__c FROM Log_Setting__mdt WHERE DeveloperName = \'defaults\' LIMIT 1'
      );
      if (records.isEmpty()) {
        logSettingUnconfigured = true;
        return true;
      }
      Object raw = records[0].get('Print_Debug_Logs__c');
      return raw == null ? true : (Boolean) raw;
    } catch (Exception ex) {
      logSettingUnconfigured = true;
      return true;
    }
  }

  /**
   * @param level The logging level
   * @param message The message to log
   * @param className The class name
   * @param methodName The method name
   * @return The formatted log message with timestamp and context prefix
   */
  @TestVisible
  @suppresswarnings('PMD.ExcessiveParameterList')
  private static String formatLogMessage(
    System.LoggingLevel level,
    String message,
    String className,
    String methodName
  ) {
    return '[' +
      Datetime.now().format('yyyy-MM-dd HH:mm:ss') +
      '] ' +
      '[' +
      level.name() +
      '] ' +
      (className != null ? '[' + className + ']' : '') +
      (methodName != null ? '[' + methodName + ']' : '') +
      ' ' +
      message;
  }

  @SuppressWarnings('PMD.AvoidDebugStatements')
  @TestVisible
  private static void storeLog(System.LoggingLevel level, String logMessage) {
    System.debug(level, logMessage);
  }
}
