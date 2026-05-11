/**
 * @description Publishes Jira_Push_Request__e platform events for records that
 *              the caller (a domain service) has already determined warrant a
 *              Jira sync. Generic across SObject types - the service does NOT
 *              evaluate field changes or any domain criteria; callers own that.
 *
 *              Decoupling note: events publish with PublishAfterCommit, so the
 *              originating record's DML is never blocked or rolled back by
 *              Jira availability or by the JCFS callout downstream.
 *
 *              Recursion guard: a per-transaction Set keyed by SObjectName + Id
 *              prevents the same record from being requested twice in one Apex
 *              transaction.
 *
 *              CMDT (Jira_Push_Object__mdt) is consulted by the dispatcher on
 *              the consume side only; this class does not gate publishes on it.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                              |
 * |------------|----------|------------|------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Initial implementation                   |
 */
public with sharing class JiraPushService {
  private static final String CLASS_NAME = 'JiraPushService';
  public static final String CHANGE_INSERT = 'Create';
  public static final String CHANGE_UPDATE = 'Update';

  // TODO: confirm with the Jira team before go-live.
  // Currently unused by JCFS.API.pushUpdatesToJira (Jira's connector mapping
  // owns the project/issue-type routing on the Jira side). Wired here for the
  // follow-on work that auto-creates Jira issues from Salesforce via
  // JCFS.API.pushTopicToJira, which requires both values.
  public static final String JIRA_PROJECT_ID = 'CSI';
  public static final String JIRA_ISSUE_TYPE = 'Story';

  // Same-transaction recursion guard. Key = SObjectName + ':' + Id.
  @TestVisible
  private static Set<String> alreadyPublished = new Set<String>();

  // Per-transaction CMDT cache (used by JiraPushDispatcher for Active__c check).
  @TestVisible
  private static Map<String, Jira_Push_Object__mdt> configCache;

  @TestVisible
  private static Map<String, Jira_Push_Object__mdt> configCacheOverride;

  /**
   * @description Test seam wrapping EventBus.publish so unit tests can
   *              inject hand-crafted Database.SaveResult lists (including
   *              failure cases) without actually publishing platform events.
   */
  public interface IEventPublisher {
    List<Database.SaveResult> publish(List<SObject> events);
  }

  @TestVisible
  private static IEventPublisher eventPublisher = new EventBusPublisher();

  private class EventBusPublisher implements IEventPublisher {
    public List<Database.SaveResult> publish(List<SObject> events) {
      return EventBus.publish(events);
    }
  }

  /**
   * @description Publish Jira push events for newly-inserted records.
   * @param records Records the caller has determined warrant a Jira push.
   */
  public static void publishInserts(List<SObject> records) {
    publish(records, CHANGE_INSERT);
  }

  /**
   * @description Publish Jira push events for updated records.
   * @param records Records the caller has determined warrant a Jira push.
   */
  public static void publishUpdates(List<SObject> records) {
    publish(records, CHANGE_UPDATE);
  }

  @TestVisible
  private static void publish(List<SObject> records, String changeType) {
    if (records == null || records.isEmpty()) {
      return;
    }

    /**
     *
     * Step 1: capture metadata that applies to every event in this batch.
     * All records must share an SObject type (caller guarantees this by
     * passing a homogeneous trigger list).
     *
     */
    String sobjectName = records[0].getSObjectType().getDescribe().getName();
    String txnId = System.Request.getCurrent().getRequestId();
    Datetime nowUtc = Datetime.now();

    /**
     *
     * Step 2: build one platform event per record. Two filters apply:
     *  - records without an Id (not yet inserted) are skipped silently
     *  - records already published in this transaction are suppressed by
     *    the recursion guard so the same record can't double-publish
     *    when downstream Apex re-fires the trigger.
     *
     */
    List<Jira_Push_Request__e> events = new List<Jira_Push_Request__e>();
    for (SObject rec : records) {
      if (rec.Id == null) {
        continue;
      }
      String guardKey = sobjectName + ':' + rec.Id;
      if (alreadyPublished.contains(guardKey)) {
        continue;
      }
      alreadyPublished.add(guardKey);
      events.add(
        new Jira_Push_Request__e(
          Source_Object__c = sobjectName,
          Source_Id__c = String.valueOf(rec.Id),
          Change_Type__c = changeType,
          Event_Timestamp__c = nowUtc,
          Transaction_Id__c = txnId
        )
      );
    }

    if (events.isEmpty()) {
      return;
    }

    /**
     *
     * Step 3: log the batch summary - first line of triage when someone
     * asks "why didn't Jira get the update?".
     *
     */
    Logger.debug(
      'Publishing ' +
        events.size() +
        ' Jira push event(s) for ' +
        sobjectName +
        ' (txn ' +
        txnId +
        ')',
      CLASS_NAME,
      'publish'
    );

    /**
     *
     * Step 4: publish all events at once. PublishAfterCommit on the PE
     * means delivery happens only if the originating DML commits, so a
     * rolled-back Opportunity save can never leak a phantom Jira sync.
     *
     */
    List<Database.SaveResult> results = eventPublisher.publish(events);

    /**
     *
     * Step 5: any publish failures land in API_Exception_Log__c + debug
     * log; they don't propagate back to the originating transaction.
     *
     */
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        Logger.logApiException(
          'JCFS',
          'EventBus.publish(Jira_Push_Request__e)',
          sobjectName,
          (Id) events[i].Source_Id__c,
          txnId,
          'EventBus.publish failed: ' + results[i].getErrors()
        );
      }
    }
  }

  /**
   * @description Returns the CMDT config for an SObject (used by the
   *              dispatcher's Active__c kill-switch check). Cached
   *              per-transaction; honors configCacheOverride in tests.
   */
  public static Jira_Push_Object__mdt getConfig(String sobjectName) {
    if (configCacheOverride != null) {
      return configCacheOverride.get(sobjectName);
    }
    if (configCache == null) {
      configCache = new Map<String, Jira_Push_Object__mdt>();
      for (Jira_Push_Object__mdt row : [
        SELECT SObject_API_Name__c, Active__c
        FROM Jira_Push_Object__mdt
      ]) {
        configCache.put(row.SObject_API_Name__c, row);
      }
    }
    return configCache.get(sobjectName);
  }
}
