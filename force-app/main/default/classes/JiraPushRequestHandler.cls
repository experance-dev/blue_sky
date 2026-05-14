/**
 * @description TriggerHandler for Jira_Push_Request__e. Platform Event triggers
 *              only fire after insert; we delegate to JiraPushDispatcher which
 *              groups by SObjectType and calls JCFS.
 *
 *              Migrated to the Zelis TriggerHandler framework: a single
 *              `initialise()` entry point branches on trigger context and
 *              delegates to per-phase helpers.
 *
 * @group Jira Integration
 * @author David Wood
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                              |
 * |------------|----------|------------|------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Initial PE trigger handler               |
 * | 2026-05-12 | CSI-7162 | David Wood | Migrate to Zelis TriggerHandler API      |
 */
public with sharing class JiraPushRequestHandler extends TriggerHandler {
  /**
   * @description Framework entry point. Branches on trigger context and
   *              delegates to the relevant hook helper. Platform Events
   *              only fire after insert, so only that path is wired.
   */
  public void initialise() {
    if (Trigger.isAfter && Trigger.isInsert) {
      handleAfterInsert();
    }
  }

  /**
   * @description After-insert hook. Delegates the published events to
   *              JiraPushDispatcher, which groups by SObjectType and
   *              calls the JCFS push API.
   */
  private void handleAfterInsert() {
    JiraPushDispatcher.process(
      (List<Jira_Push_Request__e>) Trigger.new
    );
  }
}
