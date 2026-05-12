# CSI-7162 — Jira Push Notifications: Architectural Overview

## What the feature does

When a Salesforce `Opportunity` is **inserted** (any insert) or **updated** with a change to one of six curated fields, the platform publishes a [`Jira_Push_Request__e`](../../force-app/main/default/objects/Jira_Push_Request__e/Jira_Push_Request__e.object-meta.xml) platform event. A trigger on that event invokes the Appfire JCFS managed package, which forwards the record Id(s) to Jira; Jira then **calls back** into Salesforce to pull whatever fields its own mapping requires. The Salesforce side never SOQLs the source record, and the originating DML transaction is not blocked by Jira availability.

## Pipeline

```
+----------------------+    after insert/update     +-----------------------------+
|   Opportunity DML    | -------------------------> |     OpportunityTrigger      |
|  (UI / API / Apex)   |                            |  (force-app/.../triggers/)  |
+----------------------+                            +--------------+--------------+
                                                                   |
                                                                   v
                                              +--------------------------------------+
                                              |     OpportunityTriggerHandler        |
                                              |   extends TriggerHandler             |
                                              |   delegates afterInsert/afterUpdate  |
                                              +--------------------+-----------------+
                                                                   |
                                                                   v
                                              +--------------------------------------+
                                              |        OpportunityService            |
                                              |  handleJiraPushInsert (unfiltered)   |
                                              |  handleJiraPushUpdate (filtered by   |
                                              |     JIRA_QUALIFYING_FIELDS)          |
                                              +--------------------+-----------------+
                                                                   |
                                                                   v
                                              +--------------------------------------+
                                              |           JiraPushService            |
                                              |  publishInserts / publishUpdates     |
                                              |  - recursion guard (txn-scoped)      |
                                              |  - EventBus.publish via IEventPub.   |
                                              +--------------------+-----------------+
                                                                   |
                                                                   |  PublishAfterCommit
                                                                   |  (PE — Jira_Push_Request__e)
                                                                   v
                                              +--------------------------------------+
                                              |     JiraPushRequestTrigger           |
                                              |  on Jira_Push_Request__e             |
                                              |  -> JiraPushRequestHandler           |
                                              +--------------------+-----------------+
                                                                   |
                                                                   v
                                              +--------------------------------------+
                                              |        JiraPushDispatcher            |
                                              |  - group event Ids by SObject type   |
                                              |  - gate on Jira_Push_Object__mdt     |
                                              |    (Active__c kill switch)           |
                                              |  - build typed List<SObject> via     |
                                              |    Type.forName('List<' + name + '>')|
                                              |  - call IJcfsApi.pushUpdates(...)    |
                                              +--------------------+-----------------+
                                                                   |
                                                                   v
                                              +--------------------------------------+
                                              |           JcfsApiAdapter             |
                                              |  thin wrapper around                 |
                                              |  JCFS.API.pushUpdatesToJira(...)     |
                                              +--------------------+-----------------+
                                                                   |
                                                                   v
                                              +--------------------------------------+
                                              |       Atlassian Jira (via JCFS)      |
                                              |  Jira calls back to SFDC to pull     |
                                              |  field values per its mapping        |
                                              +--------------------------------------+
```

## Three-layer pattern

The feature lays out cleanly across the Selector / Service / Domain stack documented in [best-practices/architecture.md](../../best-practices/architecture.md):

| Layer | Class | Responsibility |
| --- | --- | --- |
| **Trigger** | [`OpportunityTrigger`](../../force-app/main/default/triggers/OpportunityTrigger.trigger), [`OpportunityTriggerHandler`](../../force-app/main/default/classes/OpportunityTriggerHandler.cls) | Bare dispatcher. No business logic. Routes phase → service. |
| **Domain service** | [`OpportunityService`](../../force-app/main/default/classes/OpportunityService.cls) | Owns Opportunity-specific decisions: what qualifies as a Jira-relevant change, what to do on insert vs. update. |
| **Generic service** | [`JiraPushService`](../../force-app/main/default/classes/JiraPushService.cls) | SObject-agnostic publisher. Knows about platform events and the recursion guard; knows **nothing** about Opportunity, qualifying fields, or domain rules. |
| **Integration / adapter** | [`JiraPushDispatcher`](../../force-app/main/default/classes/JiraPushDispatcher.cls), [`JcfsApiAdapter`](../../force-app/main/default/classes/JcfsApiAdapter.cls) | Consumes the PE, gates on CMDT, builds a JCFS-compatible typed list, and delegates the actual JCFS API call to the adapter. |
| **Selector** | _(none)_ | Deliberately absent. JCFS pulls field values back from Jira; the Salesforce side never queries the source record. |

## Qualifying fields

The set of fields whose change warrants a Jira sync lives in [`OpportunityService.JIRA_QUALIFYING_FIELDS`](../../force-app/main/default/classes/OpportunityService.cls):

```apex
private static final Set<Schema.SObjectField> JIRA_QUALIFYING_FIELDS = new Set<Schema.SObjectField>{
    Opportunity.StageName,
    Opportunity.Amount,
    Opportunity.CloseDate,
    Opportunity.AccountId,
    Opportunity.OwnerId,
    Opportunity.Probability
};
```

These are stored as `Schema.SObjectField` tokens (not String names) so a rename or typo is a **compile-time** error, not a silent runtime mismatch. The change-detection itself is a generic helper, `OpportunityService.anyQualifyingFieldChanged(newRec, oldRec, fields)`, which iterates the token set and compares old vs. new values.

Each token in the set costs **one platform event per qualifying record per transaction** — additions are deliberate.

## Idempotency model

Same-transaction re-publishing of an already-pushed record is suppressed by a transaction-scoped `Set<String>` keyed `SObjectName + ':' + Id + ':' + ChangeType`:

```apex
@TestVisible
private static Set<String> alreadyPublished = new Set<String>();
```

(in [`JiraPushService`](../../force-app/main/default/classes/JiraPushService.cls)). If downstream Apex re-fires the Opportunity trigger inside the same transaction with the **same change-type**, the second publish is a silent no-op. **Insert-then-update in the same transaction** is allowed — the key includes change-type, so a `Create` followed by an `Update` on the same record produces two events (one each). This was the Atlas H4 finding (see [code review](../reviews/atlas-csi7162-code-review-2026-05-12.md#h4-static-cache-recursion-guard-leaks-across-dml-cycles)) and Boomer's [`JiraPushService` change-log entry](../../force-app/main/default/classes/JiraPushService.cls) reflects the fix.

**Cross-transaction** idempotency is **not** the framework's problem — Jira's own mapping reconciles incoming pushes against existing issues.

Re-saving the same Opportunity with **no qualifying-field change** is also a no-op: the after-update filter in `OpportunityService.handleJiraPushUpdate` drops the record before `JiraPushService` ever sees it.

## Failure model

The pipeline is **fire-and-forget** by design:

1. **`Jira_Push_Request__e` is `PublishAfterCommit`** — see the event metadata at [`Jira_Push_Request__e.object-meta.xml`](../../force-app/main/default/objects/Jira_Push_Request__e/Jira_Push_Request__e.object-meta.xml). If the originating Opportunity DML is rolled back, the platform event is never delivered. A successful Opportunity save can never be aborted by Jira-side failure.
2. **PE publish failures** (per-event SaveResult `isSuccess() == false`) are logged to [`API_Exception_Log__c`](../../force-app/main/default/objects/API_Exception_Log__c/API_Exception_Log__c.object-meta.xml) via `Logger.logApiException(...)`. The originating transaction is not impacted.
3. **JCFS per-record results.** The `IJcfsApi.pushUpdates` seam now returns `List<JcfsPushResult>` (one DTO per input record carrying `recordId`, `success`, `errorMessage`, `jiraIssueKey`). [`JiraPushDispatcher.pushOne`](../../force-app/main/default/classes/JiraPushDispatcher.cls) walks the list: successes go to `Logger.info` (low-noise audit trail, includes the Jira issue key when JCFS supplies it); failures route to `Logger.logApiException` so support has per-record visibility instead of one batch-level log row.
4. **JCFS-side exceptions** (thrown from `JCFS.API.pushUpdatesToJira`) are caught in `JiraPushDispatcher.pushOne` and logged to `API_Exception_Log__c`. They do not propagate.
5. **The JCFS managed package is absent at runtime.** Two layers of fallback:
   - **Deploy-time absent** (e.g. `JcfsApiAdapter.cls` not deployed to a scratch org without the package): `JiraPushDispatcher.resolveDefaultAdapter()` falls back to the in-class `NoOpJcfsApi`, which returns one **failure** `JcfsPushResult` per record (so every record gets an `API_Exception_Log__c` row — the "Jira not actually called" state is visible in support reports rather than silent).
   - **Runtime absent** (e.g. package uninstalled but `JcfsApiAdapter` still deployed): the adapter's one-time `Type.forName('JCFS', 'API')` startup check sets `jcfsAvailable = false`, emits a single `Logger.error('JCFS managed package is not installed...')`, and every record gets a failure `JcfsPushResult` thereafter.

**There is no automatic retry**. A push that fails is recorded in `API_Exception_Log__c` and requires manual replay — see the [runbook](../operations/csi7162-jira-push-runbook.md) for the replay procedure.

## Extension points

| To add… | Edit |
| --- | --- |
| **A new qualifying field on `Opportunity`** | Add the `Schema.SObjectField` token to `OpportunityService.JIRA_QUALIFYING_FIELDS`. Add an `OpportunityServiceTest` case mirroring `testHandleJiraPushUpdatePublishesWhenStageNameChanged`. No other class touches the field set. |
| **A new push target SObject** (e.g. `Case`, `Account`) | (1) Add a [`Jira_Push_Object__mdt`](../../force-app/main/default/objects/Jira_Push_Object__mdt/Jira_Push_Object__mdt.object-meta.xml) record with `SObject_API_Name__c` set, `Active__c = true`, and the per-SObject Jira routing in `Jira_Project_Id__c` + `Jira_Issue_Type__c` (e.g. `'CSI'` / `'Story'` for Opportunity) — examples: [`Jira_Push_Object.Opportunity.md-meta.xml`](../../force-app/main/default/customMetadata/Jira_Push_Object.Opportunity.md-meta.xml), [`Jira_Push_Object.Case.md-meta.xml`](../../force-app/main/default/customMetadata/Jira_Push_Object.Case.md-meta.xml). (2) Create a `<SObject>Service.cls` and `<SObject>TriggerHandler.cls` modeled on the Opportunity pair. (3) Create the trigger. `JiraPushService` and `JiraPushDispatcher` are SObject-agnostic and need no changes. |
| **A new payload shape** (e.g. push `RecordType` info) | Adjust the Jira-side mapping in Appfire JCFS. The Salesforce side only pushes Id; the field-by-field payload is owned by JCFS. |
| **A different downstream than Jira** | Swap [`JcfsApiAdapter`](../../force-app/main/default/classes/JcfsApiAdapter.cls) for another implementation of `JiraPushDispatcher.IJcfsApi`. The seam is intentional. |

## Configuration

| Item | Where | Purpose |
| --- | --- | --- |
| Custom metadata: [`Jira_Push_Object__mdt`](../../force-app/main/default/objects/Jira_Push_Object__mdt/Jira_Push_Object__mdt.object-meta.xml) | `customMetadata/Jira_Push_Object.<SObject>.md-meta.xml` | Per-SObject config. Four fields: `SObject_API_Name__c` (which SObject to enable), `Active__c` (kill switch — `false` suspends pushes for that SObject **at both publish and consume sides** without a deploy), `Jira_Project_Id__c` (e.g. `'CSI'`), `Jira_Issue_Type__c` (e.g. `'Story'`). The project / issue-type fields replace the previously hardcoded constants in `JiraPushService` (Atlas H2 / Boomer's H2 fix). They are read by `JiraPushService.getConfig` under `WITH USER_MODE` and surfaced to JCFS for the follow-on `pushTopicToJira` auto-create flow. |
| Platform event: [`Jira_Push_Request__e`](../../force-app/main/default/objects/Jira_Push_Request__e/Jira_Push_Request__e.object-meta.xml) | `objects/Jira_Push_Request__e/` | High-volume, `PublishAfterCommit`. Carries `Source_Object__c`, `Source_Id__c`, `Change_Type__c`, `Event_Timestamp__c`, `Transaction_Id__c`. |
| Custom object: [`API_Exception_Log__c`](../../force-app/main/default/objects/API_Exception_Log__c/API_Exception_Log__c.object-meta.xml) | `objects/API_Exception_Log__c/` | Persistent error log; one row per failed publish / per-record JCFS rejection / JCFS exception. Written by [`Logger.writeApiException`](../../force-app/main/default/classes/logging/Logger.cls) under `AccessLevel.SYSTEM_MODE` — see [ADR-0002](decisions/0002-logger-system-mode-for-api-exceptions.md). |
| Appfire JCFS managed package | Installed in target org | The actual Jira connector. **Required for production**; absence triggers the no-op fallback. [`JcfsApiAdapter`](../../force-app/main/default/classes/JcfsApiAdapter.cls) probes `Type.forName('JCFS', 'API')` once per transaction; missing → one `Logger.error` + per-record failure results, subsequent calls silent. |

**Summary:** Opportunity DML fires a trigger that delegates to `OpportunityService`, which filters on the six-field `JIRA_QUALIFYING_FIELDS` set and asks `JiraPushService` to publish a `PublishAfterCommit` PE. The CMDT `Active__c` flag is now consulted on **both** the publish side (in `JiraPushService.isActive`) and the consume side (in `JiraPushDispatcher.pushOne`) — flipping the kill switch stops events at the bus entry, not just at JCFS dispatch. The PE trigger dispatches to JCFS, which calls back to Salesforce for the actual field values. `IJcfsApi.pushUpdates` returns `List<JcfsPushResult>` so per-record success / failure is logged individually; PE publish + JCFS failures land in `API_Exception_Log__c` (via `Logger.logApiException` → `AccessLevel.SYSTEM_MODE` insert, [ADR-0002](decisions/0002-logger-system-mode-for-api-exceptions.md)) and never propagate to the originating transaction.
