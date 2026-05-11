/**
 * @description Publishes Jira_Push_Request__e platform events for any SObject
 *              configured in Jira_Push_Object__mdt. Called from each object's
 *              TriggerHandler.afterInsert / afterUpdate.
 *
 *              Decoupling note: events are published with PublishAfterCommit,
 *              so the originating record's DML is never blocked or rolled back
 *              by Jira availability or by the JCFS callout downstream.
 *
 * @group Jira Integration
 */
public with sharing class JiraPushService {
  private static final String CLASS_NAME = 'JiraPushService';
  private static final String CHANGE_INSERT = 'Create';
  private static final String CHANGE_UPDATE = 'Update';

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

  // Per-transaction CMDT cache. Key = SObject API name.
  @TestVisible
  private static Map<String, Jira_Push_Object__mdt> configCache;

  // Tests inject config without needing CMDT DML.
  @TestVisible
  private static Map<String, Jira_Push_Object__mdt> configCacheOverride;

  /**
   * @description Trigger entry point. Inspects the SObjectType of the first
   *              record, looks up its Jira_Push_Object__mdt config, evaluates
   *              qualifying changes, and publishes one event per qualifying
   *              record.
   * @param newList The Trigger.new list (or the test equivalent).
   * @param oldMap  Trigger.oldMap. Pass null on insert.
   */
  public static void publishIfQualifies(
    List<SObject> newList,
    Map<Id, SObject> oldMap
  ) {
    if (newList == null || newList.isEmpty()) {
      return;
    }

    String sobjectName = newList[0].getSObjectType().getDescribe().getName();
    Jira_Push_Object__mdt cfg = getConfig(sobjectName);
    if (cfg == null || cfg.Active__c != true) {
      return;
    }

    Boolean isInsert = (oldMap == null);
    List<String> qualifyingFields = parseFields(cfg.Qualifying_Fields__c);
    String txnId = System.Request.getCurrent().getRequestId();
    Datetime nowUtc = Datetime.now();

    List<Jira_Push_Request__e> events = new List<Jira_Push_Request__e>();
    for (SObject rec : newList) {
      String guardKey = sobjectName + ':' + rec.Id;
      if (alreadyPublished.contains(guardKey)) {
        continue;
      }
      if (!isInsert && !changedAny(rec, oldMap.get(rec.Id), qualifyingFields)) {
        continue;
      }
      alreadyPublished.add(guardKey);
      events.add(
        new Jira_Push_Request__e(
          Source_Object__c = sobjectName,
          Source_Id__c = String.valueOf(rec.Id),
          Change_Type__c = isInsert ? CHANGE_INSERT : CHANGE_UPDATE,
          Event_Timestamp__c = nowUtc,
          Transaction_Id__c = txnId
        )
      );
    }

    if (events.isEmpty()) {
      return;
    }

    Logger.debug(
      'Publishing ' +
        events.size() +
        ' Jira push event(s) for ' +
        sobjectName +
        ' (txn ' +
        txnId +
        ')',
      CLASS_NAME,
      'publishIfQualifies'
    );

    List<Database.SaveResult> results = EventBus.publish(events);
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        ApiExceptionEndpoint.log(
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
   * @description Returns the CMDT config for an SObject, honoring the test
   *              override map if set. Cached per-transaction. Public so the
   *              dispatcher can share the same cache and override hook.
   */
  public static Jira_Push_Object__mdt getConfig(String sobjectName) {
    if (configCacheOverride != null) {
      return configCacheOverride.get(sobjectName);
    }
    if (configCache == null) {
      configCache = new Map<String, Jira_Push_Object__mdt>();
      for (Jira_Push_Object__mdt row : [
        SELECT SObject_API_Name__c, Qualifying_Fields__c, Active__c
        FROM Jira_Push_Object__mdt
      ]) {
        configCache.put(row.SObject_API_Name__c, row);
      }
    }
    return configCache.get(sobjectName);
  }

  /**
   * @description Parses comma-separated field names, trimming whitespace and
   *              dropping blanks. Returns empty list if the input is null or
   *              blank, which is interpreted by callers as "qualify on every
   *              update".
   */
  @TestVisible
  private static List<String> parseFields(String csv) {
    List<String> out = new List<String>();
    if (String.isBlank(csv)) {
      return out;
    }
    for (String raw : csv.split(',')) {
      String trimmed = raw.trim();
      if (String.isNotBlank(trimmed)) {
        out.add(trimmed);
      }
    }
    return out;
  }

  /**
   * @description Returns true if any field in fields differs between newRec
   *              and oldRec. If fields is empty, returns true (qualify every
   *              update).
   */
  @TestVisible
  private static Boolean changedAny(
    SObject newRec,
    SObject oldRec,
    List<String> fields
  ) {
    if (fields.isEmpty()) {
      return true;
    }
    if (oldRec == null) {
      return true;
    }
    for (String f : fields) {
      if (newRec.get(f) != oldRec.get(f)) {
        return true;
      }
    }
    return false;
  }
}
