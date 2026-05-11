/**
 * @description Service layer for Opportunity. Owns the domain-level
 *              decisions about Opportunity behavior - anything that
 *              doesn't belong in the trigger handler or the selector
 *              lives here. The trigger handler delegates each phase
 *              to a method on this class.
 *
 * @group Opportunity
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                                                       |
 * |------------|----------|------------|-----------------------------------------------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Add handleJiraPushInsert / handleJiraPushUpdate to route qualifying Opportunity   |
 * |            |          |            | changes to JiraPushService.                                                       |
 */
public with sharing class OpportunityService {
  // Opportunity fields whose change is worth a Jira sync. Curated for what
  // downstream Jira issue tracking actually mirrors (stage, value, owner,
  // timing). Each entry incurs one platform event per qualifying record;
  // add/remove deliberately. Schema.SObjectField tokens (not String names)
  // so a typo or rename is caught at compile time.
  @TestVisible
  private static final Set<Schema.SObjectField> JIRA_QUALIFYING_FIELDS = new Set<Schema.SObjectField>{
    Opportunity.StageName,
    Opportunity.Amount,
    Opportunity.CloseDate,
    Opportunity.AccountId,
    Opportunity.OwnerId,
    Opportunity.Probability
  };

  /**
   * @description After-insert entry point. Every newly-created Opportunity
   *              gets pushed - the initial sync establishes the Jira link,
   *              so no filter is applied.
   * @param newList Trigger.new from OpportunityTriggerHandler.afterInsert.
   */
  public static void handleJiraPushInsert(List<Opportunity> newList) {
    if (newList == null || newList.isEmpty()) {
      return;
    }
    JiraPushService.publishInserts(newList);
  }

  /**
   * @description After-update entry point. Filters newList down to records
   *              where at least one QUALIFYING_FIELDS field changed, then
   *              delegates the publish.
   * @param newList Trigger.new from OpportunityTriggerHandler.afterUpdate.
   * @param oldMap  Trigger.oldMap from the same trigger.
   */
  public static void handleJiraPushUpdate(
    List<Opportunity> newList,
    Map<Id, Opportunity> oldMap
  ) {
    if (newList == null || newList.isEmpty() || oldMap == null) {
      return;
    }

    /**
     *
     * Step 1: filter newList down to records where at least one Jira-
     * relevant field actually changed. Anything else (Description edits,
     * touch-only updates, etc.) is noise we don't want syncing to Jira.
     *
     */
    List<Opportunity> changed = new List<Opportunity>();
    for (Opportunity o : newList) {
      // oldMap can be missing the record in undelete / programmatic-update
      // edge cases. Skip rather than throw - leaving the record un-synced
      // is safer than aborting the whole batch on one anomaly.
      Opportunity old = oldMap.get(o.Id);
      if (old == null) {
        continue;
      }
      if (anyQualifyingFieldChanged(o, old, JIRA_QUALIFYING_FIELDS)) {
        changed.add(o);
      }
    }

    /**
     *
     * Step 2: hand the filtered records to the generic publisher.
     *
     */
    if (!changed.isEmpty()) {
      JiraPushService.publishUpdates(changed);
    }
  }

  /**
   * @description Returns true if any field in `fields` differs between the
   *              new and old record. Pure function over a record pair and a
   *              field-token set - reusable by any domain service that needs
   *              the same change-detection semantics.
   * @param newRec The post-update record.
   * @param oldRec The pre-update record (from Trigger.oldMap).
   * @param fields Schema.SObjectField tokens to compare. Caller owns this set.
   */
  @TestVisible
  private static Boolean anyQualifyingFieldChanged(
    Opportunity newRec,
    Opportunity oldRec,
    Set<Schema.SObjectField> fields
  ) {
    for (Schema.SObjectField field : fields) {
      if (newRec.get(field) != oldRec.get(field)) {
        return true;
      }
    }
    return false;
  }
}
