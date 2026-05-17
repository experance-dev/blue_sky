# `JiraPushService`

## Orientation

[`JiraPushService`](../../../force-app/main/default/classes/JiraPushService.cls) is the generic, SObject-agnostic publisher for `Jira_Push_Request__e` platform events. Domain services (currently [`OpportunityService`](OpportunityService.md), in the future others) call it with a homogeneous record list. The service does **not** evaluate field changes or any domain criteria — callers own that. Its job is "publish the events, suppress dupes within the transaction, log failures."

## Public API

### `CHANGE_INSERT`, `CHANGE_UPDATE`

```apex
public static final String CHANGE_INSERT = 'Create';
public static final String CHANGE_UPDATE = 'Update';
```

The two values stamped onto the platform event's `Change_Type__c` field. Exposed so callers and tests can reference them by name rather than by string literal.

### Jira routing → CMDT (no longer constants)

The previously hardcoded `JIRA_PROJECT_ID = 'CSI'` and `JIRA_ISSUE_TYPE = 'Story'` constants are **gone** as of Boomer's H2 fix (see [Atlas's review](../../reviews/atlas-csi7162-code-review-2026-05-12.md#h2-hard-coded-jira_project_id--jira_issue_type-constants-in-production-apex)). Project key + issue type now live on [`Jira_Push_Object__mdt`](../../../force-app/main/default/objects/Jira_Push_Object__mdt/Jira_Push_Object__mdt.object-meta.xml) as **`Jira_Project_Id__c`** and **`Jira_Issue_Type__c`**, read by `getConfig` and surfaced per-SObject. Example: [`Jira_Push_Object.Opportunity.md-meta.xml`](../../../force-app/main/default/customMetadata/Jira_Push_Object.Opportunity.md-meta.xml) ships `CSI` / `Story`.

### `isActive(String sobjectName)`

```apex
public static Boolean isActive(String sobjectName)
```

- **Params:** `sobjectName` — API name of the candidate SObject (e.g. `'Opportunity'`).
- **Returns:** `true` when a `Jira_Push_Object__mdt` row exists for the SObject and `Active__c = true`.
- **Behavior:** Reads through `getConfig` (cached). Called from `publish(...)` to fail-closed at the bus entry — flipping `Active__c = false` now stops events from being published in the first place, rather than letting them sit on the bus until the dispatcher drops them (Atlas M1 / Boomer's M1 fix). The dispatcher still re-checks on the consume side (belt + braces).

### `publishInserts(List<SObject> records)`

- **Signature:** `public static void publishInserts(List<SObject> records)`
- **Params:** `records` — homogeneous SObject list that the caller has determined warrants a Jira push.
- **Returns:** `void`.
- **Behavior:** Routes to the private `publish(records, CHANGE_INSERT)`.

### `publishUpdates(List<SObject> records)`

- **Signature:** `public static void publishUpdates(List<SObject> records)`
- **Params:** `records` — homogeneous SObject list that the caller has determined warrants a Jira push.
- **Returns:** `void`.
- **Behavior:** Routes to the private `publish(records, CHANGE_UPDATE)`.

### `getConfig(String sobjectName)`

- **Signature:** `public static Jira_Push_Object__mdt getConfig(String sobjectName)`
- **Params:** `sobjectName` — e.g. `'Opportunity'`.
- **Returns:** the matching [`Jira_Push_Object__mdt`](../../../force-app/main/default/objects/Jira_Push_Object__mdt/Jira_Push_Object__mdt.object-meta.xml) row, or `null` if none configured. The returned row carries `SObject_API_Name__c`, `Active__c`, `Jira_Project_Id__c`, `Jira_Issue_Type__c`.
- **Behavior:** Reads all `Jira_Push_Object__mdt` rows once per transaction into a static `Map<String, Jira_Push_Object__mdt>`. SOQL runs `WITH USER_MODE` per [`best-practices/apex.md`](../../../best-practices/apex.md) (Atlas H1 / Boomer's H1 fix). Honors `configCacheOverride` for tests. Called by `isActive` (this class) and by [`JiraPushDispatcher.pushOne`](JiraPushDispatcher.md) to gate dispatch on `Active__c`.

### `publish(List<SObject> records, String changeType)` _(TestVisible private)_

The shared implementation. Six-step flow:

1. Capture batch metadata (SObject name from `records[0]`, transaction Id from `System.Request.getCurrent().getRequestId()`, `Datetime.now()` UTC).
2. **CMDT kill-switch gate.** Call `isActive(sobjectName)`. Inactive → `Logger.debug('Jira push inactive for ...; skipping publish')` and return. Stops events from entering the bus when an admin disables the SObject (Atlas M1 / Boomer's M1 fix).
3. Iterate `records`; skip records without an Id (not yet inserted); suppress duplicates via the recursion guard. **Guard key is now `SObjectName + ':' + Id + ':' + ChangeType`** so Insert-then-Update on the same record in the same transaction produces both events (Atlas H4 / Boomer's H4 fix).
4. Emit a single `Logger.debug` line summarizing the batch (first triage breadcrumb).
5. `eventPublisher.publish(events)` — wraps `EventBus.publish(...)` through the `IEventPublisher` seam.
6. Walk the `Database.SaveResult` list; any `!isSuccess()` row goes to `Logger.logApiException('JCFS', 'EventBus.publish(Jira_Push_Request__e)', sobjectName, sourceId, txnId, errorString)`.

### `IEventPublisher` interface

```apex
public interface IEventPublisher {
  List<Database.SaveResult> publish(List<SObject> events);
}
```

Test seam wrapping `EventBus.publish`. Production wiring is the internal `EventBusPublisher` class; [`JiraPushServiceTest`](../../../force-app/main/default/classes/JiraPushServiceTest.cls) swaps in a `FailingPublisher` that fabricates failure `SaveResult`s to exercise the logging branch.

### `resetTransientState()` _(TestVisible private)_

```apex
@TestVisible
private static void resetTransientState()
```

Canonical reset helper for the class's per-transaction static state. Clears:

- `alreadyPublished` (recursion guard set)
- `configCache` (CMDT cache)
- `configCacheOverride` (CMDT override map)

Used by [`JiraPushTestFixtures.silenceFramework`](../../../force-app/main/default/classes/JiraPushTestFixtures.cls) so tests don't have to know the names of the individual statics. **Does not reset `eventPublisher`** — that's an instance-of-interface seam and tests that swap it (e.g. `JiraPushServiceTest`'s `FailingPublisher` case) own their own cleanup. The omission is deliberate: resetting `eventPublisher` here would silently undo any stub a calling test had already wired in.

## Side effects

- **Publishes** `Jira_Push_Request__e` platform events (`PublishAfterCommit` — events only deliver if the originating DML commits).
- **Writes** `API_Exception_Log__c` rows via `Logger.logApiException(...)` when `EventBus.publish` returns failure SaveResults.
- **Writes debug logs** via `Logger.debug(...)` (one batch summary per `publish` call).
- **Updates** the static `alreadyPublished` set (per-transaction recursion guard).
- **Reads** all `Jira_Push_Object__mdt` rows on first call to `getConfig(...)` (one SOQL per transaction, cached thereafter).

## Dependencies

- [`Jira_Push_Request__e`](../../../force-app/main/default/objects/Jira_Push_Request__e/Jira_Push_Request__e.object-meta.xml) — the platform event.
- [`Jira_Push_Object__mdt`](../../../force-app/main/default/objects/Jira_Push_Object__mdt/Jira_Push_Object__mdt.object-meta.xml) — read by `getConfig` for dispatcher gating.
- [`API_Exception_Log__c`](../../../force-app/main/default/objects/API_Exception_Log__c/API_Exception_Log__c.object-meta.xml) — written via `Logger`.
- [`Logger`](../../../force-app/main/default/classes/logging/Logger.cls) — `debug`, `logApiException`.
- `EventBus` system class.

## Permission model

`with sharing`. The running user implicitly needs whatever permissions allow them to edit the originating record (the trigger context); platform event publish itself elevates per Salesforce PE semantics. **No explicit permset needed** for the publish path. For an admin to manually inspect logs, they need read access to `API_Exception_Log__c` (currently `Private` sharing — see the object metadata).

## Known limitations

- **Recursion guard is transaction-scoped only.** A second transaction targeting the same record publishes another event. Cross-transaction dedup is Jira's problem.
- **Records without an Id are silently skipped.** This is by design (you can't push something that hasn't been inserted yet), but a caller passing pre-insert records gets no feedback.
- **First-record SObject type wins — heterogeneous lists mis-classify silently.** `publish` reads `records[0].getSObjectType()` and stamps it on every event in the batch. Passing a mixed list (e.g. `List<SObject>` with both Opportunities and Cases) would mislabel every event after the first as the first record's type, and the dispatcher would then attempt to cast their Ids against the wrong `SObjectType` and log them all to `API_Exception_Log__c`. The trigger-handler call path never hits this because `Trigger.new` is always homogeneous, but a hand-rolled caller can. **REDESIGN flagged for follow-up:** either group by `getSObjectType()` inside `publish` and emit per-type batches, or `Assert` homogeneity on entry and fail loud. Tracked separately; not blocking CSI-7162.
- **`resetTransientState()` does not reset `eventPublisher`.** See the helper's docs above — by design, but worth knowing when test cleanup looks incomplete.

## Related

- Caller: [`OpportunityService`](OpportunityService.md) (and future per-SObject services)
- Consumer: [`JiraPushDispatcher`](JiraPushDispatcher.md) (via the `JiraPushRequestTrigger` PE trigger)
- Tests: [`JiraPushServiceTest`](../../../force-app/main/default/classes/JiraPushServiceTest.cls)
- Shared test fixtures: [`JiraPushTestFixtures`](../../../force-app/main/default/classes/JiraPushTestFixtures.cls) — `silenceFramework`, `activeConfig`, `bulkOpportunities` etc. Pippa's consolidation of the previously-duplicated per-test silencing helpers.
- E2E test: [`OpportunityTriggerHandlerTest`](../../../force-app/main/default/classes/OpportunityTriggerHandlerTest.cls)
- Decision: [ADR-0002 — Logger.writeApiException uses SYSTEM_MODE](../../architecture/decisions/0002-logger-system-mode-for-api-exceptions.md)
- Ticket: [CSI-7162](https://experance.atlassian.net/browse/CSI-7162)
