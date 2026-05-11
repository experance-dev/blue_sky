/**
 * @description LOCAL DEVELOPMENT STUB for the Appfire Connector for Salesforce
 *              & Jira (`JCFS` managed-package namespace). Exists ONLY so this
 *              worktree compiles and tests run without the managed package
 *              installed.
 *
 *              DO NOT DEPLOY TO ANY ORG WHERE THE REAL JCFS PACKAGE IS
 *              INSTALLED. A local top-level `JCFS` class shadows the managed
 *              namespace and will silently no-op all real Jira pushes.
 *
 *              Recommended: add this class to `.forceignore` before pushing
 *              to a packaged-org sandbox or production. Production code in
 *              JiraPushDispatcher already routes through an IJcfsApi seam, so
 *              tests don't depend on this stub being called.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                              |
 * |------------|----------|------------|------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Local dev stub - DO NOT deploy with JCFS |
 */
public with sharing class JCFS {
  public class API {
    /**
     * @description Mirrors the managed-package signature of
     *              `JCFS.API.pushUpdatesToJira(List<SObject>, List<SObject>)`.
     *              Logs the call so you can see what would have been pushed
     *              in local testing.
     * @param newObjects Concretely-typed SObject list to "push" to Jira.
     * @param oldObjects Currently unused by the real connector.
     */
    public static void pushUpdatesToJira(
      List<SObject> newObjects,
      List<SObject> oldObjects
    ) {
      Integer count = newObjects == null ? 0 : newObjects.size();
      String typeRender = newObjects == null
        ? 'null'
        : String.valueOf(newObjects).substringBefore(':');
      Logger.debug(
        '[JCFS STUB] pushUpdatesToJira called with ' +
          count +
          ' record(s); list type=' +
          typeRender,
        'JCFS.API',
        'pushUpdatesToJira'
      );
    }
  }
}
