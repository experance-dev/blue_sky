# `JcfsApiAdapter`

## Orientation

[`JcfsApiAdapter`](../../../force-app/main/default/classes/JcfsApiAdapter.cls) is the **only** class in the framework that compile-references the Appfire JCFS managed-package namespace. It implements [`JiraPushDispatcher.IJcfsApi`](JiraPushDispatcher.md). Isolating the JCFS dependency to a single file means scratch orgs (or any environment without the JCFS package installed) can add this one file to `.forceignore` (or omit it from the deploy) and the rest of the framework still compiles. The dispatcher resolves to a `NoOpJcfsApi` fallback when this class is absent.

## Public API

### `pushUpdates(List<SObject> records)`

```apex
public List<JiraPushDispatcher.JcfsPushResult> pushUpdates(List<SObject> records)
```

- **Params:** `records` — a concretely-typed `List<SObject>` (e.g. `List<Opportunity>`). Construction is the dispatcher's responsibility, not this class's.
- **Returns:** `List<JiraPushDispatcher.JcfsPushResult>` — one DTO per input record. Boomer's H3 fix changed the seam from `void` so the dispatcher can log per-record outcomes. The underlying `JCFS.API.pushUpdatesToJira` is itself `void`, so this adapter synthesizes a uniform `success = true` result for every record when the callout returns cleanly; per-record JCFS rejections (today) only surface as a thrown exception from the entire batch. When JCFS itself is absent (see startup check below), the returned list is **all-failure** so every record gets an `API_Exception_Log__c` row.
- **Throws:** whatever `JCFS.API.pushUpdatesToJira` throws — caught upstream by [`JiraPushDispatcher.pushOne`](JiraPushDispatcher.md) and logged to `API_Exception_Log__c`. This class itself does not catch the callout.

The second argument to `pushUpdatesToJira` is an empty `List<SObject>` — JCFS uses it for delete notifications, which CSI-7162 does not push.

### Startup check (`jcfsAvailable` cache)

```apex
@TestVisible private static Boolean jcfsAvailable;     // null until probed
@TestVisible private static Boolean absenceLogged = false;
```

First call to `pushUpdates(...)` per transaction probes `Type.forName('JCFS', 'API')`:

- **Present:** `jcfsAvailable = true`; the real callout runs; every record gets a `success = true` result.
- **Absent:** `jcfsAvailable = false`; **one** `Logger.error('JCFS managed package is not installed - Jira push integration is silently no-op\'d. Install the Appfire JCFS package to enable.', ...)` is emitted (guarded by `absenceLogged` so subsequent calls in the same transaction are silent); every record gets a `success = false` result with `errorMessage = 'JCFS managed package not installed'`, which the dispatcher then converts to one `API_Exception_Log__c` row per record.

This handles the runtime-uninstall case (package removed from the org but `JcfsApiAdapter` still deployed). The deploy-time-absent case (adapter class itself missing) falls through to the dispatcher's in-class `NoOpJcfsApi` via `Type.forName('JcfsApiAdapter')` — see [`JiraPushDispatcher.resolveDefaultAdapter`](JiraPushDispatcher.md).

## Side effects

- **Outbound callout** to Jira via the JCFS managed package (when present). JCFS performs its own HTTP semantics; this class is a thin wrapper.
- **No DML.** **No SOQL.**
- **One-time `Logger.error`** when the JCFS package is absent at runtime. Guarded so subsequent calls in the same transaction don't spam the log.

## Dependencies

- Appfire **JCFS managed package** — specifically `JCFS.API.pushUpdatesToJira(List<SObject>, List<SObject>)`. If the package is not installed in the target org, this class will fail to compile and the deploy must omit it (via `.forceignore` or manifest exclusion). The dispatcher's `Type.forName` lookup will then fall through to `NoOpJcfsApi`.
- Implements [`JiraPushDispatcher.IJcfsApi`](JiraPushDispatcher.md).

## Permission model

The JCFS managed package owns its own permset(s) (typically `JCFS_User` or similar). The Salesforce-side caller — the Automated Process User in the PE-trigger context — needs whatever access JCFS requires. Coordinate with whoever owns the JCFS install in the target org.

## Known limitations

- **Compile-coupled to JCFS.** The whole point of this class is to be the **only** file that is. Do not add other JCFS references anywhere else; the carve-out only works if this remains the single chokepoint.
- **No payload customization.** Jira's own connector mapping decides which fields it pulls back from Salesforce. To shape what Jira receives, edit the **Jira-side** mapping in Appfire, not this class.
- **Hard-coded empty delete list.** If a future story needs to push deletions, the signature can take a second list; for now CSI-7162 does not.
- **Synthetic success results.** The underlying `JCFS.API.pushUpdatesToJira` is `void`, so when the callout returns cleanly this adapter stamps `success = true` on every input record uniformly. Genuine per-record JCFS rejections only surface as a thrown exception from the entire batch — i.e. an all-or-nothing failure mode. If/when JCFS exposes per-record results, widen this method to pass them through.
- **NoOp-fallback failure results are test-locked.** When `jcfsAvailable = false` every record gets a failure result with a fixed diagnostic message (`'JCFS managed package not installed'`). [`JiraPushDispatcherTest`](../../../force-app/main/default/classes/JiraPushDispatcherTest.cls) asserts on the message string indirectly via the per-record `API_Exception_Log__c.Message__c` content — changing the message will break those assertions.

## Carve-out / deployment note

The class header documents the carve-out explicitly:

> _"The ONLY place in the framework that compile-references the Appfire JCFS managed-package namespace. Isolating it in its own file lets scratch orgs without the package add this file to `.forceignore` (or omit it from the deploy) so the rest of the framework compiles unchanged. When the package is absent, JiraPushDispatcher falls back to a no-op adapter via `Type.forName` resolution."_

Treat this file as a first-class deployment toggle, not a hidden dependency. See [the runbook](../../operations/csi7162-jira-push-runbook.md#configuration--deployment) for the practical implications.

## Related

- Dispatcher: [`JiraPushDispatcher`](JiraPushDispatcher.md) (which holds the `IJcfsApi` seam and the `NoOpJcfsApi` fallback)
- Tests: exercised indirectly via [`JiraPushDispatcherTest.testProcessUsesNoOpFallbackWhenAdapterNotDeployed`](../../../force-app/main/default/classes/JiraPushDispatcherTest.cls) (covers the absence case) and `testResolveDefaultAdapterReturnsAdapterWhenClassDeployed` (covers the presence case).
- Ticket: [CSI-7162](https://experance.atlassian.net/browse/CSI-7162)
