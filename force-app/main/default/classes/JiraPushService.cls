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
 *              Recursion guard: a per-transaction Set keyed by
 *              SObjectName + Id + ChangeType prevents the same record from
 *              being requested twice for the same change-type in one Apex
 *              transaction. Insert-then-Update in the same transaction is
 *              allowed because the key includes ChangeType.
 *
 *              CMDT (Jira_Push_Object__mdt) gates publishes at this layer
 *              (kill-switch failures-closed at publish time so disabled
 *              SObjects don't leak phantom events) AND on the consume side
 *              in JiraPushDispatcher (belt + braces).
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                              |
 * |------------|----------|------------|------------------------------------------|
 * | 2026-05-12 | CSI-7162 | David Wood | Wire Opportunity to Jira-push integration via Platform Events          |
 */
public with sharing class JiraPushService {
  private static final String CLASS_NAME = 'JiraPushService';
  public static final String CHANGE_INSERT = 'Create';
  public static final String CHANGE_UPDATE = 'Update';

  // Same-transaction recursion guard. Key = SObjectName + ':' + Id + ':' + ChangeType.
  // ChangeType is part of the key so an insert-then-update in the same transaction
  // produces two events (one Create, one Update); only same-record, same-change-type
  // re-fires are suppressed.
  @TestVisible
  private static Set<String> alreadyPublished = new Set<String>();

  // Per-transaction CMDT cache (used by isActive + getConfig).
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

    // ─── Step 1: capture batch-level metadata ─────────────────────────────────
    // All records must share an SObject type (caller guarantees this by
    // passing a homogeneous trigger list).
    String sobjectName = records[0].getSObjectType().getDescribe().getName();
    String txnId = System.Request.getCurrent().getRequestId();
    Datetime nowUtc = Datetime.now();

    // ─── Step 2: CMDT kill-switch (publish-side gate) ─────────────────────────
    // Fails closed at the publish site so flipping Active__c = false stops
    // events from entering the bus at all (avoids orphan PE backlog when the
    // flag is later re-enabled). Dispatcher still re-checks on consume.
    if (!isActive(sobjectName)) {
      Logger.debug(
        'Jira push inactive for ' + sobjectName + '; skipping publish',
        CLASS_NAME,
        'publish'
      );
      return;
    }

    // ─── Step 3: build one platform event per record ──────────────────────────
    // Filters: records without an Id are skipped silently; records already
    // published in this transaction for this change-type are suppressed.
    List<Jira_Push_Request__e> events = new List<Jira_Push_Request__e>();
    for (SObject rec : records) {
      if (rec.Id == null) {
        continue;
      }
      String guardKey = sobjectName + ':' + rec.Id + ':' + changeType;
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

    // ─── Step 4: log batch summary ────────────────────────────────────────────
    // First line of triage when someone asks "why didn't Jira get the update?".
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

    // ─── Step 5: publish all events ───────────────────────────────────────────
    // PublishAfterCommit on the PE means delivery happens only if the
    // originating DML commits, so a rolled-back save can never leak a phantom
    // Jira sync.
    List<Database.SaveResult> results = eventPublisher.publish(events);

    // ─── Step 6: any per-event publish failures log to API_Exception_Log__c ──
    // Failures never propagate back to the originating transaction.
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
   * @description Returns true when CMDT for this SObject exists and Active__c=true.
   *              Used at both publish (here) and consume (dispatcher) sites.
   * @param sobjectName SObject API name to gate on.
   * @return True if the integration is active for this SObject.
   */
  public static Boolean isActive(String sobjectName) {
    Jira_Push_Object__mdt cfg = getConfig(sobjectName);
    return cfg != null && cfg.Active__c == true;
  }

  /**
   * @description Returns the CMDT config for an SObject (used by the
   *              dispatcher's Active__c kill-switch and by Jira-side
   *              routing fields). Cached per-transaction; honors
   *              configCacheOverride in tests.
   * @param sobjectName SObject API name to look up.
   * @return CMDT row for this SObject, or null if no row exists.
   */
  public static Jira_Push_Object__mdt getConfig(String sobjectName) {
    if (configCacheOverride != null) {
      return configCacheOverride.get(sobjectName);
    }
    if (configCache == null) {
      configCache = new Map<String, Jira_Push_Object__mdt>();
      for (Jira_Push_Object__mdt row : [
        SELECT
          SObject_API_Name__c,
          Active__c,
          Jira_Project_Id__c,
          Jira_Issue_Type__c
        FROM Jira_Push_Object__mdt
        WITH USER_MODE
      ]) {
        configCache.put(row.SObject_API_Name__c, row);
      }
    }
    return configCache.get(sobjectName);
  }

  /**
   * @description Resets every per-transaction static the service maintains
   *              (recursion guard, CMDT cache, override hook). Canonical
   *              test-cleanup point so test classes don't have to know
   *              the names of the individual @TestVisible statics.
   */
  @TestVisible
  private static void resetTransientState() {
    alreadyPublished = new Set<String>();
    configCache = null;
    configCacheOverride = null;
  }

  /**
   * @description Custom exception type for JiraPushService errors. Currently
   *              unused (publish doesn't throw) but declared so any future
   *              throw site has the right base hierarchy in place.
   */
  public class JiraPushServiceException extends UtilitiesModuleException {
  }
}
