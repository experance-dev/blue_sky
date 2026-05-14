/**
 * @description Production implementation of JiraPushDispatcher.IJcfsApi.
 *              The ONLY place in the framework that compile-references
 *              the Appfire JCFS managed-package namespace. Isolating it
 *              in its own file lets scratch orgs without the package add
 *              this file to .forceignore (or omit it from the deploy) so
 *              the rest of the framework compiles unchanged.
 *
 *              When the package is absent at runtime (e.g. removed without
 *              redeploying this class), `jcfsAvailable` falls to false and
 *              every push becomes a logged no-op rather than a hard
 *              NullPointerException - see the startup check below.
 *
 *              When the package is absent at deploy time, JiraPushDispatcher
 *              falls back to its in-class NoOpJcfsApi via Type.forName.
 *
 * @group Jira Integration
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                              |
 * |------------|----------|------------|------------------------------------------|
 * | 2026-05-12 | CSI-7162 | David Wood | Wire Opportunity to Jira-push integration via Platform Events          |
 */
public with sharing class JcfsApiAdapter implements JiraPushDispatcher.IJcfsApi {
  private static final String CLASS_NAME = 'JcfsApiAdapter';

  // One-time JCFS-availability check. Null = not yet probed; true/false =
  // probe result cached for the rest of the transaction.
  @TestVisible
  private static Boolean jcfsAvailable;

  // Set to true on the first absent-package log so subsequent calls don't
  // spam the log with the same warning.
  @TestVisible
  private static Boolean absenceLogged = false;

  /**
   * @description Forwards a list of Id-only SObjects to JCFS for Jira sync.
   *              The second `new List<SObject>()` argument is JCFS's
   *              "deleted records" slot (records to remove from Jira); the
   *              framework doesn't push deletes today so it's always empty.
   *              Returns one JcfsPushResult per input record - JCFS.API
   *              itself is void, so this adapter synthesizes a uniform
   *              success result for every record; per-record failures will
   *              only ever surface as a thrown exception from JCFS.
   * @param records Concretely-typed list of SObjects (one SObject type per
   *                call) with only Id populated; Jira pulls field values
   *                back via its own mapping.
   * @return One JcfsPushResult per record (success=true unless JCFS isn't
   *         installed, in which case all results report the no-op state).
   */
  public List<JiraPushDispatcher.JcfsPushResult> pushUpdates(
    List<SObject> records
  ) {
    List<JiraPushDispatcher.JcfsPushResult> results = new List<JiraPushDispatcher.JcfsPushResult>();
    if (records == null || records.isEmpty()) {
      return results;
    }

    // Startup check: probe JCFS.API once per transaction so a missing
    // managed package no-ops cleanly instead of NPE'ing on the JCFS call.
    if (jcfsAvailable == null) {
      jcfsAvailable = Type.forName('JCFS', 'API') != null;
    }
    if (jcfsAvailable != true) {
      if (!absenceLogged) {
        Logger.error(
          'JCFS managed package is not installed - Jira push integration is silently no-op\'d. Install the Appfire JCFS package to enable.',
          CLASS_NAME,
          'pushUpdates'
        );
        absenceLogged = true;
      }
      for (SObject rec : records) {
        results.add(
          new JiraPushDispatcher.JcfsPushResult(
            rec.Id,
            false,
            'JCFS managed package not installed',
            null
          )
        );
      }
      return results;
    }

    // Real callout. JCFS.API.pushUpdatesToJira is void, so we synthesize a
    // uniform success result for every record. If JCFS throws, the caller
    // (JiraPushDispatcher.pushOne) catches it and logs once for the whole
    // batch.
    JCFS.API.pushUpdatesToJira(records, new List<SObject>());
    for (SObject rec : records) {
      results.add(
        new JiraPushDispatcher.JcfsPushResult(rec.Id, true, null, null)
      );
    }
    return results;
  }
}
