# `JiraPushDispatcher`

## Orientation

[`JiraPushDispatcher`](../../../force-app/main/default/classes/JiraPushDispatcher.cls) consumes the `Jira_Push_Request__e` platform-event batch and hands it to Appfire JCFS. It groups events by `Source_Object__c` (one JCFS call per SObject type per batch), gates on the `Jira_Push_Object__mdt` `Active__c` kill switch, constructs a **concretely-typed** `SObject` list (e.g. `List<Opportunity>`) that JCFS will accept, and dispatches via the `IJcfsApi` seam. Catches every downstream exception and writes to `API_Exception_Log__c` — failures never escape.

## Public API

### `IJcfsApi` interface

```apex
public interface IJcfsApi {
    List<JcfsPushResult> pushUpdates(List<SObject> records);
}
```

The seam that isolates the JCFS managed-package call. As of Boomer's H3 fix (see [Atlas's review](../../reviews/atlas-csi7162-code-review-2026-05-12.md#h3-jirapushdispatcherpushone-ignores-jcfsapi-callout-failures-past-the-local-catch)) the return type is `List<JcfsPushResult>` instead of `void` — implementations supply one DTO per input record so the dispatcher can log per-record success / failure individually. Production binding is [`JcfsApiAdapter`](JcfsApiAdapter.md); the absence-fallback is the private inner `NoOpJcfsApi`. Tests bind a stub (e.g. `JiraPushDispatcherTest.RecordingJcfs`).

### `JcfsPushResult` _(public inner DTO)_

```apex
public class JcfsPushResult {
    public Id recordId;
    public Boolean success;
    public String errorMessage;
    public String jiraIssueKey;
}
```

Per-record result envelope returned by `IJcfsApi.pushUpdates`:

| Field | Populated when | Notes |
| --- | --- | --- |
| `recordId` | Always | The Salesforce record Id JCFS attempted to push. |
| `success` | Always | `true` on success, `false` on per-record rejection or no-op fallback. |
| `errorMessage` | Failures only | Routed into `Logger.logApiException` → `API_Exception_Log__c.Message__c`. |
| `jiraIssueKey` | Optional, success path | The created/updated Jira issue key (e.g. `CSI-1234`) when JCFS supplies it. Appears in the success debug log line. |

Construct via the no-arg or four-arg constructor.

### `process(List<Jira_Push_Request__e> events)`

- **Signature:** `public static void process(List<Jira_Push_Request__e> events)`
- **Params:** `events` — `Trigger.new` from `JiraPushRequestTrigger`.
- **Returns:** `void`.
- **Throws:** nothing under normal operation. All exceptions are caught and logged.
- **Behavior:** Two-step flow:
  1. Build `Map<String, Set<Id>> idsByObject` from the event batch. Events with blank `Source_Object__c`/`Source_Id__c` are skipped silently. Events whose `Source_Id__c` cannot be cast to `Id` are wrapped in a thrown-then-caught `JiraPushDispatcherException` and routed to `Logger.logApiException('JCFS', 'Jira_Push_Request__e.process', ...)` so the failure carries a real exception type + stack trace into `API_Exception_Log__c.Exception_Type__c`. Skipped per-event; processing continues for the remaining events.
  2. For each SObject key, call `pushOne(sobjectName, ids)`.

### `pushOne(String sobjectName, Set<Id> ids)` _(TestVisible private)_

- **Signature:** `private static void pushOne(String sobjectName, Set<Id> ids)`
- **Returns:** `void`.
- **Behavior:** Five-step flow:
  1. **Gate on CMDT.** `JiraPushService.getConfig(sobjectName)`; bail with `Logger.warn` if missing or `Active__c != true`. (Belt-and-braces — `JiraPushService.publish` now also fails closed on `isActive`, so a kill-switched SObject usually won't even reach here.)
  2. **Resolve SObjectType.** `Schema.getGlobalDescribe().get(sobjectName)`; bail with `Logger.logApiException` if unknown.
  3. **Build typed list.** `Type.forName('List<' + sobjectName + '>').newInstance()`, then `sot.newSObject(recId)` per Id. Each `newSObject` call is wrapped in its **own** per-Id try/catch inside the loop (Atlas M2 / Boomer's M2 fix) — an Id whose key prefix doesn't match `sot` is logged and skipped, the rest of the batch ships. List-construction failure (outer `Type.forName`) is its own catch and aborts the batch with a single log line.
  4. **Call JCFS.** `results = jcfs.pushUpdates(typed)`. Wrapped in try/catch — anything thrown by JCFS is logged at batch level and swallowed.
  5. **Per-record result fan-out.** Walk `results`:
     - `r.success == true` → `Logger.info('JCFS push success for <SObject> <Id> -> <jiraIssueKey>', ...)`. Low-noise audit trail for the happy path.
     - `r.success == false` → `Logger.logApiException('JCFS', 'JCFS.API.pushUpdatesToJira (per-record)', sobjectName, r.recordId, txnId, 'JCFS rejected record: ' + r.errorMessage)`. One `API_Exception_Log__c` row per rejected record so support can replay them individually.

### `resolveDefaultAdapter()` _(TestVisible private)_

- **Signature:** `private static IJcfsApi resolveDefaultAdapter()`
- **Returns:** an `IJcfsApi` — either an instance of the class named in the (`@TestVisible`) `adapterClassName` field (default `'JcfsApiAdapter'`) or the private `NoOpJcfsApi` if `Type.forName` resolves to `null`. Picks production behavior when JCFS-adjacent code is deployed; safe fallback when it isn't.

### `muteForTest()` _(TestVisible private)_

```apex
@TestVisible
private static IJcfsApi muteForTest()
```

Canonical seam intended to swap `jcfs` for a fresh `NoOpJcfsApi` stub from a single co-located helper (so test classes don't peek at `JiraPushDispatcher.jcfs` directly). **Currently dead code.** [`JiraPushTestFixtures.silenceFramework`](../../../force-app/main/default/classes/JiraPushTestFixtures.cls) wires its own `RecordingJcfs` straight into `JiraPushDispatcher.jcfs` rather than going through this helper, so `muteForTest` is the dispatcher's 89% → 100% coverage gap. Pippa's call to leave it: a direct test for it would be tautological (assert the helper does what its one-line body says). Either route `JiraPushTestFixtures` through it or delete it; tracked as a low-priority follow-up.

### Static fields

| Field | Type | Notes |
| --- | --- | --- |
| `adapterClassName` | `String` (`@TestVisible`) | Defaults to `'JcfsApiAdapter'`. Set by tests to point at a stub class. |
| `jcfs` | `IJcfsApi` (`@TestVisible`) | Resolved at class-load time. Tests overwrite directly to stub via [`JiraPushTestFixtures.silenceFramework`](../../../force-app/main/default/classes/JiraPushTestFixtures.cls). |

### `JiraPushDispatcherException` _(public inner)_

```apex
public class JiraPushDispatcherException extends UtilitiesModuleException {}
```

Now actually thrown (Atlas M3 / Boomer's M3 fix) — and now extends [`UtilitiesModuleException`](../../../force-app/main/default/classes/UtilitiesModuleException.cls) instead of `Exception` so module-level catch handlers can recognize it. **Throw site:** [`process(...)`](../../../force-app/main/default/classes/JiraPushDispatcher.cls) when an event's `Source_Id__c` can't be cast to `Id`. The throw is immediately followed by a catch inside the same method that hands the exception (with its real `Exception_Type__c` and stack trace) to `Logger.logApiException(...)` — so the malformed-Source_Id__c failure path now writes a typed `API_Exception_Log__c` row rather than a generic string-message row.

## Side effects

- **Calls** `JCFS.API.pushUpdatesToJira(records, new List<SObject>())` via the `IJcfsApi` seam — this is the outbound integration call that hands record Ids to Jira.
- **Reads** the CMDT cache via `JiraPushService.getConfig` (SOQL happens once per transaction on first read).
- **Writes** `API_Exception_Log__c` rows on: malformed `Source_Id__c`, unknown SObject API name, Id-prefix/SObject-type mismatch, JCFS-side exception.
- **Writes debug logs** via `Logger.warn(...)` when the CMDT is missing or inactive, and when the no-op fallback fires.

## Dependencies

- [`JcfsApiAdapter`](JcfsApiAdapter.md) — production `IJcfsApi` binding.
- [`JiraPushService.getConfig`](JiraPushService.md) — CMDT lookup.
- [`Jira_Push_Object__mdt`](../../../force-app/main/default/objects/Jira_Push_Object__mdt/Jira_Push_Object__mdt.object-meta.xml) — kill-switch CMDT.
- [`Jira_Push_Request__e`](../../../force-app/main/default/objects/Jira_Push_Request__e/Jira_Push_Request__e.object-meta.xml) — input.
- [`API_Exception_Log__c`](../../../force-app/main/default/objects/API_Exception_Log__c/API_Exception_Log__c.object-meta.xml) — error log.
- [`Logger`](../../../force-app/main/default/classes/logging/Logger.cls).
- Appfire JCFS managed package (only via `JcfsApiAdapter` — direct reference is **deliberately** absent from this class).

## Permission model

`with sharing`, but runs as the Automated Process User in the PE-trigger context (see [`JiraPushRequestHandler` permission model](JiraPushRequestHandler.md#permission-model)). No explicit permset entries required.

## Known limitations

- **JCFS-list typing is reflective.** `Type.forName('List<' + sobjectName + '>')` requires the value to be a valid Apex type at runtime. CMDT-driven SObject names that don't compile to a real type are caught and logged, but the failure mode is "silent skip + one log row" rather than a hard error.
- **No retry.** A failed JCFS call (batch-level exception) or per-record JCFS rejection writes one log row each and moves on. Replay is manual — see [the runbook](../../operations/csi7162-jira-push-runbook.md#replay-a-dropped-push).
- **No-op fallback masks deployment errors.** If `JcfsApiAdapter` is genuinely missing at deploy time, the dispatcher resolves to the in-class `NoOpJcfsApi`. That fallback now returns one **failure** `JcfsPushResult` per record (with `errorMessage = 'JcfsApiAdapter not deployed'`), so every record gets an `API_Exception_Log__c` row — the "Jira not actually called" state is visible in support reports instead of silent. Test-locked via [`JiraPushDispatcherTest.testProcessUsesNoOpFallbackWhenAdapterNotDeployed`](../../../force-app/main/default/classes/JiraPushDispatcherTest.cls).
- **`muteForTest()` is dead code.** See the helper's docs above. 89% coverage gap by design until a test routes through it or the helper is deleted.
- **Recursion guard is upstream.** This class has no deduping of its own. If the same record Id arrives twice in the same PE batch (e.g. two qualifying updates in the same transaction), JCFS receives both — though the `JiraPushService.alreadyPublished` guard prevents that from happening in normal operation (now keyed by change-type as well, so an Insert + Update on the same record in one transaction will legitimately produce both events).

## Related

- PE trigger: [`JiraPushRequestTrigger`](../../../force-app/main/default/triggers/JiraPushRequestTrigger.trigger)
- PE handler: [`JiraPushRequestHandler`](JiraPushRequestHandler.md)
- Adapter: [`JcfsApiAdapter`](JcfsApiAdapter.md)
- Upstream publisher: [`JiraPushService`](JiraPushService.md)
- Tests: [`JiraPushDispatcherTest`](../../../force-app/main/default/classes/JiraPushDispatcherTest.cls)
- Ticket: [CSI-7162](https://experance.atlassian.net/browse/CSI-7162)
