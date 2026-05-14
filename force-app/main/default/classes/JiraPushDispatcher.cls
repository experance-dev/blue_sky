/**
 * @description Consumes Jira_Push_Request__e events: groups by Source_Object__c,
 *              constructs a concretely-typed SObject list with only the Ids
 *              populated, and hands it to JCFS.API.pushUpdatesToJira. JCFS
 *              forwards the notification to Jira, which calls back into
 *              Salesforce to pull whatever fields its mapping requires - so
 *              we never SELECT here.
 *
 *              JCFS constraints honored:
 *              - Must run in trigger context (PE trigger satisfies this).
 *              - Must NOT be invoked from @future (PE triggers aren't).
 *              - Parameter list must have concrete runtime type
 *                (e.g. List<Opportunity>), achieved via
 *                Type.forName('List<' + sobjectName + '>').
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                              |
 * |------------|----------|------------|------------------------------------------|
 * | 2026-05-12 | CSI-7162 | David Wood | Wire Opportunity to Jira-push integration via Platform Events          |
 */
public with sharing class JiraPushDispatcher {
  private static final String CLASS_NAME = 'JiraPushDispatcher';
  private static final String API_NAME = 'JCFS';

  /**
   * @description Per-record result returned by IJcfsApi.pushUpdates. Allows
   *              the caller to log per-record success / failure instead of
   *              losing the per-record outcome behind a void contract.
   */
  public class JcfsPushResult {
    public Id recordId;
    public Boolean success;
    public String errorMessage;
    public String jiraIssueKey;

    public JcfsPushResult() {
    }

    public JcfsPushResult(
      Id recordId,
      Boolean success,
      String errorMessage,
      String jiraIssueKey
    ) {
      this.recordId = recordId;
      this.success = success;
      this.errorMessage = errorMessage;
      this.jiraIssueKey = jiraIssueKey;
    }
  }

  /**
   * @description Test seam: production routes through JcfsApiAdapter; tests
   *              swap in a stub to verify wiring without invoking JCFS.
   *              Returns one JcfsPushResult per input record so the caller
   *              can log per-record success/failure (Jira issue key on
   *              success, error message on failure).
   */
  public interface IJcfsApi {
    List<JcfsPushResult> pushUpdates(List<SObject> records);
  }

  @TestVisible
  private static String adapterClassName = 'JcfsApiAdapter';

  @TestVisible
  private static IJcfsApi jcfs = resolveDefaultAdapter();

  /**
   * @description Picks the production JcfsApiAdapter via Type.forName when
   *              it's deployed, otherwise falls back to a logging no-op.
   *              This keeps the JCFS.API reference compartmentalized to
   *              JcfsApiAdapter.cls so scratch orgs without the managed
   *              package can still compile and run tests. Class name is
   *              @TestVisible so tests can point at a stub.
   */
  @TestVisible
  private static IJcfsApi resolveDefaultAdapter() {
    Type adapterType = Type.forName(adapterClassName);
    if (adapterType != null) {
      return (IJcfsApi) adapterType.newInstance();
    }
    return new NoOpJcfsApi();
  }

  /**
   * @description Canonical test-mute seam. Swaps the dispatcher's IJcfsApi
   *              for the in-class NoOpJcfsApi so tests can run the full
   *              publish->trigger->dispatcher pipeline without touching
   *              JCFS, then assert against per-record results via the
   *              returned stub. Co-located here so every test class
   *              mutes the consume side the same way (canonical seam,
   *              instead of cross-class field peeking).
   * @return The noop stub now wired in as the dispatcher's IJcfsApi.
   */
  @TestVisible
  private static IJcfsApi muteForTest() {
    NoOpJcfsApi stub = new NoOpJcfsApi();
    jcfs = stub;
    return stub;
  }

  /**
   * @description Fallback when JcfsApiAdapter isn't deployed (e.g. JCFS-less
   *              scratch org). Emits a WARN-level summary line + returns one
   *              failure result per record so every record gets a row in
   *              API_Exception_Log__c. This makes "Jira was not called"
   *              visible in support reporting even when the integration is
   *              silently disabled (e.g. a missed deploy after a sandbox
   *              refresh wipes the JcfsApiAdapter class).
   */
  private class NoOpJcfsApi implements IJcfsApi {
    public List<JcfsPushResult> pushUpdates(List<SObject> records) {
      String txnId = System.Request.getCurrent().getRequestId();
      Logger.warn(
        'JcfsApiAdapter not deployed - skipping JCFS push of ' +
          (records == null ? 0 : records.size()) +
          ' record(s) (txn ' +
          txnId +
          ')',
        CLASS_NAME,
        'NoOpJcfsApi.pushUpdates'
      );
      List<JcfsPushResult> results = new List<JcfsPushResult>();
      if (records == null) {
        return results;
      }
      // One failure result per record - dispatcher's per-record result
      // loop will then write one API_Exception_Log__c row per record so
      // the "Jira not actually called" state is visible in support reports.
      for (SObject rec : records) {
        results.add(
          new JcfsPushResult(
            rec.Id,
            false,
            'JcfsApiAdapter not deployed',
            null
          )
        );
      }
      return results;
    }
  }

  /**
   * @description Trigger entry point. Bulk-safe across mixed SObject types
   *              in the same event batch.
   * @param events Trigger.new from JiraPushRequestTrigger.
   */
  public static void process(List<Jira_Push_Request__e> events) {
    // Bail out early on empty/null batches - nothing to dispatch.
    if (events == null || events.isEmpty()) {
      return;
    }

    // ─── Step 1: group event Ids by Source_Object__c ──────────────────────────
    // One JCFS call per SObject type, no matter how many records came in.
    Map<String, Set<Id>> idsByObject = new Map<String, Set<Id>>();
    for (Jira_Push_Request__e e : events) {
      // Skip malformed events (empty source) but keep processing the rest.
      if (
        String.isBlank(e.Source_Object__c) ||
        String.isBlank(e.Source_Id__c)
      ) {
        continue;
      }
      // Validate the Id cast. Anything that isn't a real 15/18-char Id
      // gets logged to API_Exception_Log__c and skipped.
      Id recId;
      try {
        recId = (Id) e.Source_Id__c;
      } catch (System.StringException ex) {
        try {
          throw new JiraPushDispatcherException(
            'Invalid Source_Id__c: ' + e.Source_Id__c
          );
        } catch (JiraPushDispatcherException jex) {
          Logger.logApiException(
            API_NAME,
            'Jira_Push_Request__e.process',
            e.Source_Object__c,
            null,
            e.Transaction_Id__c,
            jex
          );
        }
        continue;
      }
      if (!idsByObject.containsKey(e.Source_Object__c)) {
        idsByObject.put(e.Source_Object__c, new Set<Id>());
      }
      idsByObject.get(e.Source_Object__c).add(recId);
    }

    // ─── Step 2: dispatch each SObject's Id set in a single JCFS call ─────────
    for (String sobjectName : idsByObject.keySet()) {
      pushOne(sobjectName, idsByObject.get(sobjectName));
    }
  }

  @TestVisible
  private static void pushOne(String sobjectName, Set<Id> ids) {
    String txnId = System.Request.getCurrent().getRequestId();

    // ─── Step 1: gate on CMDT ─────────────────────────────────────────────────
    // Admins can flip Active__c to suspend Jira sync per SObject without a
    // deploy. Missing or inactive -> skip quietly.
    Jira_Push_Object__mdt cfg = JiraPushService.getConfig(sobjectName);
    if (cfg == null || cfg.Active__c != true) {
      Logger.warn(
        'No active Jira push config for ' + sobjectName + '; skipping',
        CLASS_NAME,
        'pushOne'
      );
      return;
    }

    // ─── Step 2: resolve the SObjectType so we can mint empty records by Id ──
    Schema.SObjectType sot = Schema.getGlobalDescribe().get(sobjectName);
    if (sot == null) {
      Logger.logApiException(
        API_NAME,
        'pushOne',
        sobjectName,
        null,
        txnId,
        'Unknown SObject type: ' + sobjectName
      );
      return;
    }

    // ─── Step 3: build a concretely-typed list of empty records ──────────────
    // (e.g. List<Opportunity>) via reflection and populate each entry with
    // just its Id. JCFS inspects the runtime list type and requires it match
    // the SObject - a generic List<SObject> is rejected. Jira pulls field
    // values back from Salesforce after the push, so we don't populate
    // anything else.
    //
    // Per-Id try/catch lives inside the loop so a single malformed Id logs
    // and is skipped rather than aborting the whole batch.
    List<SObject> typed;
    try {
      Type listType = Type.forName('List<' + sobjectName + '>');
      typed = (List<SObject>) listType.newInstance();
    } catch (Exception ex) {
      Logger.logApiException(
        API_NAME,
        'pushOne (list construction)',
        sobjectName,
        null,
        txnId,
        ex
      );
      return;
    }
    for (Id recId : ids) {
      try {
        // newSObject throws SObjectException when recId's key prefix
        // doesn't match sot - caught here so 199 good Ids still ship even
        // when 1 garbage Id sneaks in.
        typed.add(sot.newSObject(recId));
      } catch (Exception ex) {
        Logger.logApiException(
          API_NAME,
          'pushOne (newSObject)',
          sobjectName,
          recId,
          txnId,
          ex
        );
        // continue - don't let one bad Id sink the rest of the batch.
      }
    }
    if (typed.isEmpty()) {
      return;
    }

    // ─── Step 4: hand the typed list to JCFS ─────────────────────────────────
    // The IJcfsApi seam wraps the real JCFS.API.pushUpdatesToJira so tests
    // can stub it. Per-record results are logged below.
    List<JcfsPushResult> results;
    try {
      results = jcfs.pushUpdates(typed);
    } catch (Exception ex) {
      Logger.logApiException(
        API_NAME,
        'JCFS.API.pushUpdatesToJira',
        sobjectName,
        null,
        txnId,
        ex
      );
      return;
    }

    // ─── Step 5: per-record result logging ────────────────────────────────────
    // Successes go to debug (low-noise audit trail); failures go to
    // Logger.error + API_Exception_Log__c via Logger.logApiException so
    // support can replay them.
    if (results == null) {
      return;
    }
    for (JcfsPushResult r : results) {
      if (r == null) {
        continue;
      }
      if (r.success == true) {
        Logger.info(
          'JCFS push success for ' +
            sobjectName +
            ' ' +
            r.recordId +
            (String.isBlank(r.jiraIssueKey)
              ? ''
              : ' -> ' + r.jiraIssueKey),
          CLASS_NAME,
          'pushOne'
        );
      } else {
        Logger.logApiException(
          API_NAME,
          'JCFS.API.pushUpdatesToJira (per-record)',
          sobjectName,
          r.recordId,
          txnId,
          'JCFS rejected record: ' + r.errorMessage
        );
      }
    }
  }

  /**
   * @description Custom exception for dispatcher-level errors. Extends
   *              UtilitiesModuleException so it shares the module-wide
   *              catch point. Used to flag malformed Source_Id__c values
   *              for Logger.logApiException ingestion.
   */
  public class JiraPushDispatcherException extends UtilitiesModuleException {
  }
}
