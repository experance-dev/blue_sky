# CSI-7162 — Jira Push Notifications: Operations Runbook

Operations + triage procedures for the Jira-push pipeline. For the architecture, start with [`docs/architecture/csi7162-jira-push-overview.md`](../architecture/csi7162-jira-push-overview.md).

## At-a-glance

| Q                       | A                                                                                                                                                                                                                                                     |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| What fires a push?      | Opportunity insert; Opportunity update where any field in [`JIRA_QUALIFYING_FIELDS`](../../force-app/main/default/classes/OpportunityService.cls) changed.                                                                                            |
| What's pushed to Jira?  | The record Id only. Jira pulls field values back from Salesforce via JCFS mapping.                                                                                                                                                                    |
| Where do failures land? | [`API_Exception_Log__c`](../../force-app/main/default/objects/API_Exception_Log__c/API_Exception_Log__c.object-meta.xml).                                                                                                                             |
| Kill switch?            | `Jira_Push_Object__mdt.Active__c = false` per SObject. Gated on **both** publish and consume sides (Boomer's M1 fix) — flipping it stops events at the bus entry, not just at JCFS dispatch. See [Disable / re-enable](#disable--re-enable-the-push). |
| Retry on failure?       | **None.** Manual replay only — see [Replay a dropped push](#replay-a-dropped-push).                                                                                                                                                                   |

## How to verify a push fired

Use this as a deploy smoke test. Run from anonymous Apex against a sandbox where the change is live:

```apex
// Snapshot the log row count before.
Integer before = [SELECT COUNT() FROM API_Exception_Log__c];

// Touch a qualifying field on a known Oppty.
Opportunity o = [SELECT Id, StageName FROM Opportunity LIMIT 1];
String newStage = (o.StageName == 'Prospecting') ? 'Qualification' : 'Prospecting';
update new Opportunity(Id = o.Id, StageName = newStage);

// Inspect publish-side debug log: look for the JiraPushService.publish breadcrumb.
//   "Publishing 1 Jira push event(s) for Opportunity (txn <reqId>)"
System.debug(LoggingLevel.INFO, 'TxnId: ' + System.Request.getCurrent().getRequestId());

// No new error rows should land.
Integer after = [SELECT COUNT() FROM API_Exception_Log__c];
System.assertEquals(before, after, 'Push should be clean');
```

What "success" looks like:

1. The anonymous-Apex transaction commits without throwing.
2. The debug log contains the `Publishing 1 Jira push event(s) for Opportunity (txn ...)` line from [`JiraPushService.publish`](../../force-app/main/default/classes/JiraPushService.cls).
3. `API_Exception_Log__c` count is unchanged.
4. Jira side: the corresponding Jira issue's Salesforce-mapped fields reflect the new stage within a minute or two (Appfire JCFS sync cadence depends on the JCFS configuration in Jira).

If the `Publishing ...` log line shows but `API_Exception_Log__c` grew by one or more rows: a downstream step failed. Run the [Inspect API_Exception_Log\_\_c](#inspect-api_exception_log__c) query below.

## Inspect `API_Exception_Log__c`

```sql
SELECT
    Name,
    CreatedDate,
    API_Name__c,
    Operation__c,
    Source_Object__c,
    Source_Record_Id__c,
    Transaction_Id__c,
    Exception_Type__c,
    Message__c,
    Stack_Trace__c
FROM API_Exception_Log__c
WHERE API_Name__c = 'JCFS'
AND CreatedDate = LAST_N_HOURS:24
ORDER BY CreatedDate DESC
```

Typical `Operation__c` values for CSI-7162:

| Operation                                    | Meaning                                                                | Most likely cause                                                                                                                                                                                                                                                            |
| -------------------------------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Jira_Push_Request__e.process`               | Malformed `Source_Id__c` on the platform event                         | Bad publisher code (shouldn't happen from `JiraPushService`). `Exception_Type__c` will now be `JiraPushDispatcher.JiraPushDispatcherException` — Boomer's M3 fix routes the typed exception through the logger.                                                              |
| `pushOne`                                    | Unknown SObject API name                                               | A `Jira_Push_Object__mdt` row references an SObject that no longer exists                                                                                                                                                                                                    |
| `pushOne (list construction)`                | `Type.forName('List<' + sobjectName + '>')` failed for the whole batch | Malformed CMDT `SObject_API_Name__c`. Aborts that SObject's batch.                                                                                                                                                                                                           |
| `pushOne (newSObject)`                       | One Id's key prefix didn't match the SObject type                      | Cross-wired CMDT or hand-crafted bad data. Now scoped per-Id (Boomer's M2 fix): one bad Id no longer kills the whole batch — 199 good Ids still ship, the one bad Id gets its own log row.                                                                                   |
| `JCFS.API.pushUpdatesToJira`                 | Whole-batch JCFS exception                                             | Jira down, JCFS auth expired, payload rejected for the whole batch — read `Message__c` + `Stack_Trace__c`                                                                                                                                                                    |
| `JCFS.API.pushUpdatesToJira (per-record)`    | JCFS rejected a single record                                          | New as of Boomer's H3 fix. `Source_Record_Id__c` identifies which record; `Message__c` carries the per-record `errorMessage` from `JcfsPushResult`.                                                                                                                          |
| `EventBus.publish(Jira_Push_Request__e)`     | PE publish failure                                                     | Rare. Org-level platform-event limits, schema mismatch                                                                                                                                                                                                                       |
| `logApiException` (in `Class__c` = `Logger`) | `API_Exception_Log__c` insert itself failed                            | Should be zero — the row is now persisted under `AccessLevel.SYSTEM_MODE` per [ADR-0002](../architecture/decisions/0002-logger-system-mode-for-api-exceptions.md). If you see this, check for required-field misconfiguration or validation rules on `API_Exception_Log__c`. |

### Per-record `JcfsPushResult` shape

When you see rows tagged `Operation__c = 'JCFS.API.pushUpdatesToJira (per-record)'`, the `Message__c` carries the per-record diagnostic. The DTO underneath is [`JiraPushDispatcher.JcfsPushResult`](../../force-app/main/default/classes/JiraPushDispatcher.cls):

| DTO field         | Where it lands in `API_Exception_Log__c`                                                |
| ----------------- | --------------------------------------------------------------------------------------- |
| `recordId`        | `Source_Record_Id__c`                                                                   |
| `success = false` | (implied — only failures get a row)                                                     |
| `errorMessage`    | `Message__c` (prefixed `'JCFS rejected record: '`)                                      |
| `jiraIssueKey`    | (success-only — appears in the `Logger.info` debug line, not in `API_Exception_Log__c`) |

For the success path, look at the org's debug log filtered to `JiraPushDispatcher.pushOne`:

```
INFO|JiraPushDispatcher|pushOne|JCFS push success for Opportunity 006xxx -> CSI-1234
```

## How to manually trigger a push (anonymous Apex)

For triage — bypasses the `OpportunityService` qualifying-field filter so you can isolate "did the publisher work?" from "did the trigger filter work?".

```apex
// Picks an arbitrary Opportunity. Replace with a specific Id for targeted testing.
Opportunity o = [SELECT Id FROM Opportunity LIMIT 1];

Test.startTest(); // not strictly needed; isolates PE delivery in test contexts only
JiraPushService.publishUpdates(new List<Opportunity>{ o });
Test.stopTest();

System.debug('Published. Check API_Exception_Log__c and Jira for ' + o.Id);
```

To bypass the dispatcher's CMDT gate (e.g. you want to test the path with `Active__c = false`):

```apex
JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>{
    'Opportunity' => new Jira_Push_Object__mdt(
        MasterLabel = 'Opportunity',
        DeveloperName = 'Opportunity',
        SObject_API_Name__c = 'Opportunity',
        Active__c = true
    )
};
```

(This is the same hook `JiraPushServiceTest` uses; it's `@TestVisible` so anonymous Apex can read/write it.)

## Disable / re-enable the push

**Per-SObject kill switch** — the supported runtime control. Edit the relevant [`Jira_Push_Object__mdt`](../../force-app/main/default/objects/Jira_Push_Object__mdt/Jira_Push_Object__mdt.object-meta.xml) record:

1. **Setup → Custom Metadata Types → Jira Push Object → Manage records.**
2. Edit `Opportunity` (or `Case`, etc.).
3. Uncheck **Active**.
4. Save.

Effect (now gated on **both** sides as of Boomer's M1 fix):

- **Publish side:** `JiraPushService.publish` calls `isActive(sobjectName)` first. Inactive → debug log `'Jira push inactive for <SObject>; skipping publish'` and **no platform event is published**. No orphan events sit on the bus.
- **Consume side (defense in depth):** if a PE somehow does reach the dispatcher (e.g. from an in-flight transaction that cached the previous `Active__c = true` state), `JiraPushDispatcher.pushOne` re-reads `JiraPushService.getConfig(...)` and bails with `Logger.warn('No active Jira push config for <SObject>; skipping')`. No JCFS call. No error rows.

> Note: the CMDT cache (`JiraPushService.configCache`) is **per-transaction**. New transactions pick up the change immediately; an in-flight transaction in the same execution context won't.

**Whole-trigger bypass** — heavier hammer. Use the `TriggerHandler` framework bypass (see [best-practices/architecture.md](../../best-practices/architecture.md)) to disable `OpportunityTriggerHandler` entirely. Stops the upstream publish; also stops any other Opportunity-trigger work, so use sparingly.

**Hard rollback** — remove [`JcfsApiAdapter.cls`](../../force-app/main/default/classes/JcfsApiAdapter.cls) from the deploy (add to `.forceignore` or omit from the package manifest). `JiraPushDispatcher` falls back to `NoOpJcfsApi`, which only logs a `warn`. Pipeline still runs end-to-end but Jira never gets the call. Useful for staging environments without the JCFS managed package.

## Inspect the Jira-side outcome

CSI-7162 ends at `JCFS.API.pushUpdatesToJira(...)`. Beyond that boundary is owned by Appfire JCFS and the Jira admin:

- **JCFS sync log** — in Jira: **Apps → Connector for Salesforce → Sync history** (path varies by JCFS version). Filter by the `Source_Id__c` from the platform event.
- **Jira issue audit** — open the linked Jira issue; the activity log shows when the SF-pulled fields were applied.
- **Webhook receipts** — Appfire JCFS uses a pull-back model (Jira calls back to Salesforce after our push). If the inbound callback failed, you'll see it in Setup → **Apex Jobs / Apex Logs** as a JCFS-namespaced job.

Coordinate with the Jira admin if the Salesforce-side log shows a clean push but the Jira issue didn't update — at that point the problem is in the JCFS mapping, not in CSI-7162.

## Replay a dropped push

There is **no automatic retry**. To replay manually:

1. **Identify the affected record.** Pull the failed `API_Exception_Log__c` rows (query above) and read `Source_Record_Id__c`.
2. **Re-publish** from anonymous Apex:
   ```apex
   Id targetId = '006xxxxxxxxxxxxxxx'; // from API_Exception_Log__c.Source_Record_Id__c
   String sobjectName = 'Opportunity'; // from API_Exception_Log__c.Source_Object__c
   SObject rec = Database.query(
       'SELECT Id FROM ' + sobjectName + ' WHERE Id = :targetId LIMIT 1'
   );
   JiraPushService.publishUpdates(new List<SObject>{ rec });
   ```
3. **Verify** — re-run the [verify](#how-to-verify-a-push-fired) procedure. Confirm no new `API_Exception_Log__c` row landed for this `Source_Record_Id__c`.
4. **Cleanup** — optionally mark the original `API_Exception_Log__c` row as resolved. The object honors `Do_Not_Delete__c` for retention.

For a **bulk replay** (e.g. Jira was down for an hour and 200 Opps need re-pushing):

```apex
Set<Id> oppIds = new Set<Id>();
for (API_Exception_Log__c row : [
    SELECT Source_Record_Id__c
    FROM API_Exception_Log__c
    WHERE API_Name__c = 'JCFS'
    AND Operation__c = 'JCFS.API.pushUpdatesToJira'
    AND Source_Object__c = 'Opportunity'
    AND CreatedDate = LAST_N_HOURS:6
]) {
    oppIds.add((Id) row.Source_Record_Id__c);
}
List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE Id IN :oppIds];
JiraPushService.publishUpdates(opps);
```

Stay under the per-transaction PE publish limit (currently 150,000 per hour at the org level — well above any realistic replay). For bulk replays >1k records, split into multiple anonymous-Apex runs or wrap in a one-off `Queueable`.

## Configuration / deployment

Required components in the target org:

| Component                        | Path                                                                                                                                                                                                                                                     | Notes                                                                                                                                                                                                                                                                                                                                 |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Platform event                   | [`Jira_Push_Request__e`](../../force-app/main/default/objects/Jira_Push_Request__e/Jira_Push_Request__e.object-meta.xml)                                                                                                                                 | `HighVolume`, `PublishAfterCommit`. Five custom fields (`Source_Object__c`, `Source_Id__c`, `Change_Type__c`, `Event_Timestamp__c`, `Transaction_Id__c`).                                                                                                                                                                             |
| PE trigger                       | [`JiraPushRequestTrigger`](../../force-app/main/default/triggers/JiraPushRequestTrigger.trigger)                                                                                                                                                         | One-liner.                                                                                                                                                                                                                                                                                                                            |
| Custom object                    | [`API_Exception_Log__c`](../../force-app/main/default/objects/API_Exception_Log__c/API_Exception_Log__c.object-meta.xml)                                                                                                                                 | Private sharing, auto-number `AEL-{00000}`. Insert runs `AccessLevel.SYSTEM_MODE` — see [ADR-0002](../architecture/decisions/0002-logger-system-mode-for-api-exceptions.md).                                                                                                                                                          |
| Custom metadata type             | [`Jira_Push_Object__mdt`](../../force-app/main/default/objects/Jira_Push_Object__mdt/Jira_Push_Object__mdt.object-meta.xml)                                                                                                                              | Four fields: `SObject_API_Name__c`, `Active__c`, `Jira_Project_Id__c`, `Jira_Issue_Type__c`.                                                                                                                                                                                                                                          |
| CMDT records                     | [`Jira_Push_Object.Opportunity.md-meta.xml`](../../force-app/main/default/customMetadata/Jira_Push_Object.Opportunity.md-meta.xml), [`Jira_Push_Object.Case.md-meta.xml`](../../force-app/main/default/customMetadata/Jira_Push_Object.Case.md-meta.xml) | Ship with `Active__c = true`, `Jira_Project_Id__c = 'CSI'`, `Jira_Issue_Type__c = 'Story'`.                                                                                                                                                                                                                                           |
| Apex classes                     | `JcfsApiAdapter`, `JiraPushDispatcher`, `JiraPushRequestHandler`, `JiraPushService`, `OpportunityService`, `OpportunityTriggerHandler` (+ test classes inc. `JiraPushTestFixtures`)                                                                      | See [`docs/development/classes/`](../development/classes/).                                                                                                                                                                                                                                                                           |
| Triggers                         | `OpportunityTrigger`, `JiraPushRequestTrigger`                                                                                                                                                                                                           | Both `after insert`-shape triggers.                                                                                                                                                                                                                                                                                                   |
| Appfire JCFS managed package     | (managed)                                                                                                                                                                                                                                                | **Required for production push to reach Jira.** Absent at runtime → `JcfsApiAdapter` emits one `Logger.error('JCFS managed package is not installed...')` per transaction and returns failure `JcfsPushResult`s so every record gets an `API_Exception_Log__c` row. Absent at deploy time → dispatcher's `NoOpJcfsApi` does the same. |
| Named credential / connected app | (managed by Appfire JCFS)                                                                                                                                                                                                                                | Salesforce side does not maintain a Named Credential for Jira — the JCFS package owns the auth. Confirm with the Jira admin that the JCFS connector is healthy before go-live.                                                                                                                                                        |

Manifest: [`manifest/package.xml`](../../manifest/package.xml). The CSI-7162 commit `5b2ae52` (_"add Salesforce package.xml deploy manifest"_) is the source of record.

### Enabling a new SObject

To add a new push target (e.g. `Case`):

1. **Deploy / author the CMDT record:** [`customMetadata/Jira_Push_Object.<SObjectName>.md-meta.xml`](../../force-app/main/default/customMetadata/Jira_Push_Object.Opportunity.md-meta.xml) with:
   - `SObject_API_Name__c` = `'Case'`
   - `Active__c` = `true`
   - `Jira_Project_Id__c` = your Jira project key (e.g. `'CSI'`)
   - `Jira_Issue_Type__c` = your Jira issue type (e.g. `'Story'`)
2. **Author the per-SObject service + trigger handler** (modeled on `OpportunityService` / `OpportunityTriggerHandler`).
3. **Author the trigger** (modeled on [`OpportunityTrigger`](../../force-app/main/default/triggers/OpportunityTrigger.trigger)).
4. **Deploy via [`manifest/package.xml`](../../manifest/package.xml)**.

`JiraPushService` and `JiraPushDispatcher` are SObject-agnostic — they pick up the new SObject from the CMDT cache on the next transaction. No core-framework changes required.

### JCFS-absent troubleshooting

Symptom: every Jira push lands in `API_Exception_Log__c` with `Message__c = 'JCFS rejected record: JCFS managed package not installed'` (NoOp dispatcher fallback) **or** `'JCFS rejected record: JCFS managed package not installed'` originating from the `JcfsApiAdapter` startup check.

Detection signal: search the debug log for the one-time error emitted by [`JcfsApiAdapter.pushUpdates`](../../force-app/main/default/classes/JcfsApiAdapter.cls):

```
ERROR|JcfsApiAdapter|pushUpdates|JCFS managed package is not installed - Jira push integration is silently no-op'd. Install the Appfire JCFS package to enable.
```

This is emitted **once per transaction** when `Type.forName('JCFS', 'API')` returns null. If you see it in production:

1. Confirm via **Setup → Installed Packages** whether the Appfire JCFS package is present.
2. If present but not visible to the running user, check the JCFS-side permset assignment for the Automated Process User (PE trigger context runs as the Automated Process User).
3. If absent, reinstall the package. The pipeline will resume automatically on the next transaction (no deploy needed) — the `jcfsAvailable` static is per-transaction.

**Summary:** First triage step is the `API_Exception_Log__c` query filtered to `API_Name__c = 'JCFS'` and the last 24h; `Operation__c` narrows down which step in the pipeline broke (per-record failures now show as `'JCFS.API.pushUpdatesToJira (per-record)'`). Per-SObject pauses run through `Jira_Push_Object__mdt.Active__c` and fail closed on both the publish and consume sides without a deploy. Adding a new SObject means deploying a `Jira_Push_Object__mdt.<SObject>.md-meta.xml` record (including `Jira_Project_Id__c` + `Jira_Issue_Type__c`) plus the per-SObject service / handler / trigger. There is no automatic retry — failed pushes are replayed manually via `JiraPushService.publishUpdates(...)`. If the JCFS package isn't installed, the one-time `Logger.error('JCFS managed package is not installed...')` is the detection signal. Beyond `JCFS.API.pushUpdatesToJira` the JCFS managed package owns the wire, and the Jira admin owns the mapping.
