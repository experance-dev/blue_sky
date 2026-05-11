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
 * | 2026-05-11 | CSI-7162 | David Wood | Initial implementation                   |
 */
public with sharing class JiraPushDispatcher {
  private static final String CLASS_NAME = 'JiraPushDispatcher';

  /**
   * @description Test seam: production routes through JcfsApiAdapter; tests
   *              swap in a stub to verify wiring without invoking JCFS.
   */
  public interface IJcfsApi {
    void pushUpdates(List<SObject> records);
  }

  @TestVisible
  private static IJcfsApi jcfs = new JcfsApiAdapter();

  private class JcfsApiAdapter implements IJcfsApi {
    public void pushUpdates(List<SObject> records) {
      JCFS.API.pushUpdatesToJira(records, new List<SObject>());
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

    // Step 1: group event Ids by Source_Object__c so we make exactly one
    // JCFS call per SObject type, no matter how many records came in.
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
        Logger.logApiException(
          'JCFS',
          'Jira_Push_Request__e.process',
          e.Source_Object__c,
          null,
          e.Transaction_Id__c,
          'Invalid Source_Id__c: ' + e.Source_Id__c
        );
        continue;
      }
      if (!idsByObject.containsKey(e.Source_Object__c)) {
        idsByObject.put(e.Source_Object__c, new Set<Id>());
      }
      idsByObject.get(e.Source_Object__c).add(recId);
    }

    // Step 2: dispatch each SObject's Id set in a single JCFS call.
    for (String sobjectName : idsByObject.keySet()) {
      pushOne(sobjectName, idsByObject.get(sobjectName));
    }
  }

  @TestVisible
  private static void pushOne(String sobjectName, Set<Id> ids) {
    // Step 1: gate on CMDT. Admins can flip Active__c to suspend Jira sync
    // per SObject without a deploy. Missing or inactive -> skip quietly.
    Jira_Push_Object__mdt cfg = JiraPushService.getConfig(sobjectName);
    if (cfg == null || cfg.Active__c != true) {
      Logger.warn(
        'No active Jira push config for ' + sobjectName + '; skipping',
        CLASS_NAME,
        'pushOne'
      );
      return;
    }

    // Step 2: resolve the SObjectType so we can mint empty records by Id.
    Schema.SObjectType sot = Schema.getGlobalDescribe().get(sobjectName);
    if (sot == null) {
      Logger.logApiException(
        'JCFS',
        'pushOne',
        sobjectName,
        null,
        null,
        'Unknown SObject type: ' + sobjectName
      );
      return;
    }

    // Step 3: build a *concretely-typed* list (e.g. List<Opportunity>) via
    // reflection and populate each entry with just its Id. JCFS inspects
    // the runtime list type and requires it match the SObject - a generic
    // List<SObject> is rejected. Jira pulls field values back from
    // Salesforce after the push, so we don't need to populate anything else.
    List<SObject> typed;
    try {
      Type listType = Type.forName('List<' + sobjectName + '>');
      if (listType == null) {
        throw new JiraPushDispatcherException(
          'Could not resolve List type for ' + sobjectName
        );
      }
      typed = (List<SObject>) listType.newInstance();
      for (Id recId : ids) {
        typed.add(sot.newSObject(recId));
      }
    } catch (Exception ex) {
      Logger.logApiException(
        'JCFS',
        'pushOne (list construction)',
        sobjectName,
        null,
        null,
        ex
      );
      return;
    }

    // Step 4: hand the typed list to JCFS. The IJcfsApi seam wraps the
    // real JCFS.API.pushUpdatesToJira so tests can stub it.
    try {
      jcfs.pushUpdates(typed);
    } catch (Exception ex) {
      Logger.logApiException(
        'JCFS',
        'JCFS.API.pushUpdatesToJira',
        sobjectName,
        null,
        null,
        ex
      );
    }
  }

  public class JiraPushDispatcherException extends Exception {
  }
}
