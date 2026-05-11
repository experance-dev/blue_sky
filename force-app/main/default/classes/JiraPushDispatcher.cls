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
 * | 2026-05-11 | CSI-7162 | David Wood | Initial dispatcher with IJcfsApi seam    |
 * | 2026-05-11 | CSI-7162 | David Wood | Drop selector layer; ID-only SObject build |
 * | 2026-05-11 | CSI-7162 | David Wood | Use Logger.logApiException on error paths  |
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
    if (events == null || events.isEmpty()) {
      return;
    }

    Map<String, Set<Id>> idsByObject = new Map<String, Set<Id>>();
    for (Jira_Push_Request__e e : events) {
      if (
        String.isBlank(e.Source_Object__c) ||
        String.isBlank(e.Source_Id__c)
      ) {
        continue;
      }
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

    for (String sobjectName : idsByObject.keySet()) {
      pushOne(sobjectName, idsByObject.get(sobjectName));
    }
  }

  @TestVisible
  private static void pushOne(String sobjectName, Set<Id> ids) {
    Jira_Push_Object__mdt cfg = JiraPushService.getConfig(sobjectName);
    if (cfg == null || cfg.Active__c != true) {
      Logger.warn(
        'No active Jira push config for ' + sobjectName + '; skipping',
        CLASS_NAME,
        'pushOne'
      );
      return;
    }

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
