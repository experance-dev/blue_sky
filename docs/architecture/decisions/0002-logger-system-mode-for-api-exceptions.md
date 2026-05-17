# ADR-0002: `Logger.writeApiException` uses `AccessLevel.SYSTEM_MODE`

## Status

Accepted — 2026-05-12.

## Context

[`Logger.writeApiException`](../../../force-app/main/default/classes/logging/Logger.cls) is the single persistence endpoint for [`API_Exception_Log__c`](../../../force-app/main/default/objects/API_Exception_Log__c/API_Exception_Log__c.object-meta.xml). Every failure path in the CSI-7162 Jira-push framework routes through it ([`JiraPushService.publish`](../../../force-app/main/default/classes/JiraPushService.cls) PE-publish failures; [`JiraPushDispatcher.pushOne`](../../../force-app/main/default/classes/JiraPushDispatcher.cls) malformed Source_Id, unknown SObject, per-Id `newSObject` failure, batch JCFS exception, per-record JCFS rejection), and every future outbound integration (Slack, Workday, etc.) will too.

The original implementation called `insert new API_Exception_Log__c(...)` — a bare DML that bypasses both the [`DMLManager`](../../../force-app/main/default/classes/DMLManager.cls) routing convention in [`best-practices/apex.md`](../../../best-practices/apex.md) and any FLS / CRUD enforcement on the caller. Atlas's [CSI-7162 review (B1)](../../reviews/atlas-csi7162-code-review-2026-05-12.md#-block) flagged this as a BLOCK: every other DML in the codebase routes through `DMLManager`, and we can't have the central error-persistence endpoint be the one place we skip the rule.

The fix had three plausible shapes:

1. Route through `DMLManager.insertAsUser(...)` — the canonical option.
2. Route through `DMLManager.insertAsSystem(...)` — superficially the right answer.
3. Direct `Database.insert(rec, AccessLevel.SYSTEM_MODE)`.

Two operational requirements pinned the decision:

- **A diagnostic log MUST capture failures regardless of caller perms.** If a low-FLS user (no read/write on `Stack_Trace__c`, no CRUD on `API_Exception_Log__c`, no licensed access to the diagnostic table) triggers an integration exception, support still needs the row written — otherwise every error from that user vanishes silently and the log becomes worse than useless. This rules out option 1.
- **`DMLManager.insertAsSystem` is not actually system-mode.** Inspecting [`DMLManager`](../../../force-app/main/default/classes/DMLManager.cls), its `insertAsSystem` overload still routes the underlying `Database.insert` through `AccessLevel.USER_MODE` (a known limitation in our shared DML stack). So option 2 has the same hole as option 1.

That leaves option 3 — a direct, deliberately-scoped `Database.insert` with `AccessLevel.SYSTEM_MODE` — as the only one that meets both requirements. Sage (Security) confirmed this is acceptable for a diagnostic table because no business data flows through it; only metadata about failures.

## Decision

`Logger.writeApiException` persists `API_Exception_Log__c` rows via:

```apex
Database.insert(
    new API_Exception_Log__c(...),
    AccessLevel.SYSTEM_MODE
);
```

The override is **scoped to this one method**. Every other DML in [`Logger`](../../../force-app/main/default/classes/logging/Logger.cls) and every DML elsewhere in the codebase continues to route through `DMLManager.xxxAsUser`. The carve-out is documented in:

- The [`Logger` class header](../../../force-app/main/default/classes/logging/Logger.cls) `@last` note.
- The [`writeApiException` method ApexDoc](../../../force-app/main/default/classes/logging/Logger.cls) sharing/permissions block, which calls out the rationale + links back to this ADR.
- An inline `// Direct Database.insert with AccessLevel.SYSTEM_MODE - ...` comment at the call site.

## Consequences

**Pros:**

- **Errors persist regardless of caller FLS** — the "nothing gets swallowed" property support needs for the integration log to be trustworthy.
- **Simpler than the alternative.** No dedicated integration permset to maintain and assign; no queueable indirection to debug.
- **Failure is still soft.** The insert itself is wrapped in `try/catch`; if even the system-mode insert fails (validation rule, required field misconfig), we drop to `Logger.error` and continue — the originating transaction is never affected.

**Cons:**

- **Bypasses caller FLS** on the `API_Exception_Log__c` insert. Acceptable for a diagnostic table by design; **not** acceptable as a precedent for business data. Anyone tempted to copy this pattern to other DML in the codebase should not.
- **`API_Exception_Log__c` rows may surface field values the caller couldn't otherwise read.** Mitigated by the object's `Private` sharing model (default-deny on rows) and Sage's audit of the field set — only `Source_Record_Id__c` (a stringified Id) is potentially sensitive, and exposure is bounded to users with explicit access to the log object.

**Mitigations:**

- The pattern is scoped to `writeApiException` only. Code review (Atlas) and the conventions doc ([`best-practices/apex.md`](../../../best-practices/apex.md)) treat any other `AccessLevel.SYSTEM_MODE` usage as a finding requiring its own ADR.
- The carve-out is documented in three places (class header, method ApexDoc, inline comment) so a future reader cannot miss it.

## Alternatives considered

| Option                                                        | Why rejected                                                                                                                                                                                                                                                 |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `DMLManager.insertAsUser` + a `Jira_Push_Integration` permset | Permset assignment for the running user is the wrong abstraction — the running user is whoever triggered the failure, not a service identity. We'd need a permset on every user in the org, including future hires. Operational debt without payoff.         |
| `DMLManager.insertAsSystem`                                   | Does not actually run in system mode (still `AccessLevel.USER_MODE` underneath). Would silently re-introduce the original bug.                                                                                                                               |
| `Queueable` wrapper running in system context                 | Async write means errors are reported in a different transaction from the one that failed, breaking the `Transaction_Id__c` correlation. Adds a flush-and-pray failure mode where the queueable itself could fail. Higher complexity for no diagnostic gain. |
| Platform Event (publish-and-forget log row)                   | Inverts the dependency stack — the logger would depend on the PE infrastructure that itself uses the logger. Bootstrap problem.                                                                                                                              |

## Reviewers

| Role              | Reviewer | Decision                                                                                                                                                                                                        |
| ----------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| TA (architecture) | Atlas    | Approved — original B1 finding; this is the resolution.                                                                                                                                                         |
| Security          | Sage     | Approved — `API_Exception_Log__c` is diagnostic, `Private` sharing limits exposure, no business data on the table.                                                                                              |
| Test              | Pippa    | Approved — [`LoggerApiExceptionTest`](../../../force-app/main/default/classes/LoggerApiExceptionTest.cls) asserts row insert succeeds even when caller has no FLS on `Stack_Trace__c`, locking in the property. |

## Related

- Source: [`Logger.writeApiException`](../../../force-app/main/default/classes/logging/Logger.cls)
- Conventions: [`best-practices/apex.md`](../../../best-practices/apex.md) (DMLManager rule + the carve-out)
- Code review: [Atlas's CSI-7162 review — finding B1](../../reviews/atlas-csi7162-code-review-2026-05-12.md#-block)
- Architecture overview: [CSI-7162 Jira push overview](../csi7162-jira-push-overview.md)
- Test: [`LoggerApiExceptionTest`](../../../force-app/main/default/classes/LoggerApiExceptionTest.cls)
- Ticket: [CSI-7162](https://experance.atlassian.net/browse/CSI-7162)
