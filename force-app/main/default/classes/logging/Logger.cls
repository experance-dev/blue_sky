/**
 * @description Centralized logging utility for Salesforce applications.
 *              Provides a simple interface to log messages with varying levels of severity.
 *              Supports logging the originating class and method names.
 *              The `printLogs` flag (driven by Log_Setting__mdt) gates debug-level output;
 *              info/warn/error always write. `logException` captures message + stack trace.
 * @group Logger
 * @since September 2024
 * @author David Wood
 * @last May 2026 — PII scrub (email masking) on Message__c / Stack_Trace__c before persist; CSI-7162: writeApiException uses Database.insert(..., AccessLevel.SYSTEM_MODE) by deliberate policy (see method ApexDoc)
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

  /**
   * @description Persists an API_Exception_Log__c row and mirrors the message
   *              to Logger.error. Endpoint for outbound integration failures
   *              (Jira, Slack, Workday, …) so support can report on what
   *              broke without scavenging debug logs. Self-wraps DML so the
   *              caller never needs a try/catch.
   *
   *              Sharing/permissions: the row is persisted via
   *              `Database.insert(..., AccessLevel.SYSTEM_MODE)` by
   *              deliberate policy decision. An error logger MUST capture
   *              failures regardless of caller perms - if a user without
   *              FLS on Stack_Trace__c (or without CRUD on
   *              API_Exception_Log__c) triggers an exception, we still
   *              need the row written or support loses every error that
   *              user generates. Routing this through
   *              DMLManager.insertAsUser would silently drop those rows;
   *              DMLManager doesn't expose a true SYSTEM_MODE overload
   *              (its insertAsSystem still uses AccessLevel.USER_MODE on
   *              the underlying Database.insert), so we call
   *              Database.insert directly here. This is the documented
   *              "log layer needs elevated DML" exception to the
   *              "all DML through DMLManager" rule in
   *              best-practices/apex.md.
   * @param apiName        Logical API / integration name (e.g. 'JCFS').
   * @param operation      Specific method or step that failed.
   * @param sourceObject   SObject API name the failure was about (nullable).
   * @param sourceRecordId Record Id the failure was about (nullable).
   * @param transactionId  System.Request.getCurrent().getRequestId() (nullable).
   * @param ex             The thrown Apex exception.
   */
  public static void logApiException(
    String apiName,
    String operation,
    String sourceObject,
    Id sourceRecordId,
    String transactionId,
    Exception ex
  ) {
    writeApiException(
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

  /**
   * @description Same endpoint as the Exception overload, but for non-exception
   *              error conditions (invalid payload, missing config, etc.).
   */
  public static void logApiException(
    String apiName,
    String operation,
    String sourceObject,
    Id sourceRecordId,
    String transactionId,
    String message
  ) {
    writeApiException(
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

  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static void writeApiException(
    String apiName,
    String operation,
    String sourceObject,
    Id sourceRecordId,
    String transactionId,
    String message,
    String exceptionType,
    String stackTrace
  ) {
    error(
      '[' + apiName + '/' + operation + '] ' + scrubPii(message),
      'Logger',
      'logApiException'
    );
    try {
      // Direct Database.insert with AccessLevel.SYSTEM_MODE - DMLManager does
      // not expose a true system-mode overload (insertAsSystem still runs the
      // underlying DML at AccessLevel.USER_MODE), and an error logger must
      // capture the row regardless of caller FLS. See class header + method
      // ApexDoc for the policy rationale.
      Database.insert(
        new API_Exception_Log__c(
          API_Name__c = apiName,
          Operation__c = operation,
          Source_Object__c = sourceObject,
          Source_Record_Id__c = sourceRecordId == null
            ? null
            : String.valueOf(sourceRecordId),
          Transaction_Id__c = transactionId,
          Severity__c = 'ERROR',
          Message__c = scrubPii(message),
          Exception_Type__c = exceptionType,
          Stack_Trace__c = scrubPii(stackTrace)
        ),
        AccessLevel.SYSTEM_MODE
      );
    } catch (Exception writeFail) {
      error(
        'Could not persist API_Exception_Log__c: ' + writeFail.getMessage(),
        'Logger',
        'logApiException'
      );
    }
  }

  /**
   * @description Defense-in-depth PII scrub for content destined for
   *              API_Exception_Log__c. Today's call paths persist
   *              Exception.getMessage() / getStackTraceString(), which are
   *              class.method.line — no field values. If a future custom
   *              exception ever embeds a record field (e.g. a Contact email)
   *              in its message, this scrub masks it before it lands in the
   *              diagnostic table. Pattern: local-part of any RFC-5322-ish
   *              email is masked to first-three + ***. Domain preserved for
   *              operational triage. Null-safe.
   * @param input Raw message or stack-trace string (nullable).
   * @return Scrubbed string, or null if input was null.
   */
  @TestVisible
  private static String scrubPii(String input) {
    if (String.isBlank(input)) {
      return input;
    }
    // RFC-5322-ish: localpart includes letters, digits, dots, plus, dashes,
    // underscores. Captures local + @domain; replaces local with
    // first-three + *** when the local part is > 3 chars, else just ***.
    String emailRegex = '([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+\\.[A-Za-z]{2,})';
    Pattern p = Pattern.compile(emailRegex);
    Matcher m = p.matcher(input);
    String out = '';
    Integer last = 0;
    while (m.find()) {
      out += input.substring(last, m.start());
      String local = m.group(1);
      String masked = (local.length() > 3 ? local.substring(0, 3) : '') +
        '***';
      out += masked + '@' + m.group(2);
      last = m.end();
    }
    out += input.substring(last);
    return out;
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
   * @return True if debug output is enabled (driven by Log_Setting__mdt)
   */
  @TestVisible
  private static Boolean printLogs {
    get {
      if (printLogs == null) {
        printLogs = Log_Setting__mdt.getInstance('defaults')
          ?.Print_Debug_Logs__c ?? true;
      }
      return printLogs;
    }
    set;
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
