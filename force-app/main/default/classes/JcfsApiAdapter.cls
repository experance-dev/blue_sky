/**
 * @description Production implementation of JiraPushDispatcher.IJcfsApi.
 *              The ONLY place in the framework that compile-references
 *              the Appfire JCFS managed-package namespace. Isolating it
 *              in its own file lets scratch orgs without the package add
 *              this file to .forceignore (or omit it from the deploy) so
 *              the rest of the framework compiles unchanged.
 *
 *              When the package is absent, JiraPushDispatcher falls back
 *              to a no-op adapter via Type.forName resolution.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                              |
 * |------------|----------|------------|------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Initial implementation                   |
 */
public with sharing class JcfsApiAdapter implements JiraPushDispatcher.IJcfsApi {
  public void pushUpdates(List<SObject> records) {
    JCFS.API.pushUpdatesToJira(records, new List<SObject>());
  }
}
