/**
 * @description Trigger handler for Lead after-update events. When a Lead
 *              transitions `IsConverted = false → true`, reparents every
 *              `Engagement_Touch__c` previously linked to that Lead so the
 *              touch now points at the converted Contact and Account. The
 *              `Lead__c` lookup is nulled out as part of the same update so
 *              the operation is idempotent — re-firing on an already-converted
 *              Lead is a no-op because no touches reference it any longer.
 *
 *              Extends the project's `TriggerHandler` framework so this handler
 *              participates in the org-wide loop-count and bypass machinery.
 *              All SOQL uses `WITH USER_MODE`, all DML routes through
 *              `DMLManager.updateAsUser` per best-practices/apex.md.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class LeadEngagementReparentHandler extends TriggerHandler {
  private static final String CLASS_NAME = 'LeadEngagementReparentHandler';

  /**
   * @description Framework entry point. Branches on trigger context and
   *              delegates to the relevant hook helper.
   */
  public void initialise() {
    if (Trigger.isAfter && Trigger.isUpdate) {
      handleAfterUpdate();
    }
  }

  /**
   * @description After-update hook. Detects the false→true `IsConverted`
   *              transition and delegates to `reparentTouches` for the
   *              actual data work.
   */
  private void handleAfterUpdate() {
    Map<Id, Lead> oldMap = (Map<Id, Lead>) Trigger.oldMap;
    List<Lead> newList = (List<Lead>) Trigger.new;
    if (newList == null || oldMap == null) {
      return;
    }
    Set<Id> justConvertedLeadIds = collectJustConvertedLeadIds(newList, oldMap);
    if (justConvertedLeadIds.isEmpty()) {
      return;
    }
    reparentTouches(justConvertedLeadIds);
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  private static Set<Id> collectJustConvertedLeadIds(
    List<Lead> newList,
    Map<Id, Lead> oldMap
  ) {
    Set<Id> ids = new Set<Id>();
    for (Lead n : newList) {
      Lead o = oldMap.get(n.Id);
      if (o != null && o.IsConverted == false && n.IsConverted == true) {
        ids.add(n.Id);
      }
    }
    return ids;
  }

  private static void reparentTouches(Set<Id> justConvertedLeadIds) {
    Map<Id, Lead> converted = new Map<Id, Lead>(
      [
        SELECT Id, ConvertedContactId, ConvertedAccountId
        FROM Lead
        WHERE Id IN :justConvertedLeadIds
        WITH USER_MODE
      ]
    );

    List<Engagement_Touch__c> touchesToUpdate = [
      SELECT Id, Lead__c
      FROM Engagement_Touch__c
      WHERE Lead__c IN :justConvertedLeadIds
      WITH USER_MODE
    ];

    if (touchesToUpdate.isEmpty()) {
      return;
    }

    for (Engagement_Touch__c t : touchesToUpdate) {
      Lead l = converted.get(t.Lead__c);
      if (l == null) {
        continue;
      }
      t.Contact__c = l.ConvertedContactId;
      t.Account__c = l.ConvertedAccountId;
      t.Lead__c = null;
    }

    try {
      DMLManager.updateAsUser(touchesToUpdate);
      Logger.info(
        'Reparented ' +
          touchesToUpdate.size() +
          ' touches across ' +
          justConvertedLeadIds.size() +
          ' converted leads.',
        CLASS_NAME,
        'reparentTouches'
      );
    } catch (DmlException e) {
      Logger.error(e.getMessage(), CLASS_NAME, 'reparentTouches');
      throw new EngagementException(
        'Failed to reparent engagement touches after Lead conversion: ' +
        e.getMessage()
      );
    }
  }
}
