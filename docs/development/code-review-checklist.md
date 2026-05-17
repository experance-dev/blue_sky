# Code Review Checklist

What reviewers look for on an Apex PR. Use it as a self-check before opening the PR and as a scoring rubric during review.

Full review flow + reviewer table is in [.claude/agents/TEAM.md §PR review discipline](/Users/david/Work/Zelis/.claude/agents/TEAM.md). This page is the line-by-line checklist.

## Sharing & access

- [ ] Every class declares `with sharing` (or, with documented justification, `inherited sharing`). No implicit defaults.
- [ ] Every SOQL carries `WITH USER_MODE`. No exceptions in production code; test-only fakes may use `WITH SYSTEM_MODE` if justified in a comment.
- [ ] Every DML uses [`DMLManager`](../../force-app/main/default/classes/dml/DMLManager.cls) `xxxAsUser` overloads — or, where DMLManager has no overload (upsert-by-external-id), `Database.xxx(records, ..., AccessLevel.USER_MODE)` with a tracking comment.
- [ ] No bare `insert` / `update` / `delete` / `upsert` statements in production code.
- [ ] Permission-set changes are paired with a Sage review request (BLOCKING per [TEAM.md](/Users/david/Work/Zelis/.claude/agents/TEAM.md)).

## Bulkification

- [ ] No SOQL inside a `for` loop.
- [ ] No DML inside a `for` loop.
- [ ] Service methods accept collection types (`List<...>`, `Set<Id>`, `Map<...>`) — not single-record signatures — wherever bulk invocation is possible.
- [ ] Trigger handlers operate over `Trigger.new` / `Trigger.newMap` as collections, not via `Trigger.new[0]`.
- [ ] Per-record loops use hash-map lookups (`Map.get(key)`) instead of nested `for` over an inner list.

## ApexDoc & class authoring

- [ ] Class header has `@description`, `@group`, `@author`, `@since`. `@last` appended when modifying an existing class.
- [ ] Method-level ApexDoc on public methods with `@param` / `@return` / `@throws` as warranted.
- [ ] Method names are CamelCase; no underscores except in field API names.
- [ ] Class-level constants are `private static final` and `UPPER_SNAKE_CASE`.
- [ ] Apex complexity < 8/method, < 45/class. PMD warns; split if over.
- [ ] No `System.debug` in production paths. Use [`Logger.info` / `Logger.warn` / `Logger.error`](../../force-app/main/default/classes/logging/Logger.cls).

## Exception handling

- [ ] Every `catch` logs via `Logger.error(msg, className, methodName)` or `Logger.logException(e, className, methodName)`.
- [ ] Service-layer catches rethrow a module-typed exception (e.g. [`EngagementException`](../../force-app/main/default/classes/engagement/EngagementException.cls)), not the raw `Exception` / `DmlException`.
- [ ] Controller-layer catches rethrow `AuraHandledException` with a sanitized, user-facing message — never `e.getMessage()` directly.
- [ ] No empty catch blocks. If swallowing intentionally, `Logger.info` the reason.
- [ ] Custom labels for any string surfaced to the UI (toast text, panel messages, modal copy).

## Test coverage (devs file gaps with Pippa; they do not write the tests themselves)

- [ ] Net new public method ships with a coverage ticket filed against Pippa.
- [ ] Existing test class (if any) still compiles + passes.
- [ ] No silent coverage drop — if your change removes a path, the corresponding test asserts the new behaviour. Coordinate with Pippa.
- [ ] No org-data dependencies. Tests should run on a fresh scratch org with seed-data on or off.

## Security findings (Sage's eyes)

- [ ] No `without sharing` in production paths unless documented as a Sage-approved exception.
- [ ] No `System.runAs` outside `@IsTest`.
- [ ] No injection of unsanitized user input into dynamic SOQL (`String.escapeSingleQuotes`).
- [ ] No PII leaked via `Logger` calls (the log is read by support; emails / phone numbers don't belong there).
- [ ] Hard-delete flows (the [`EngagementErasureService`](../../force-app/main/default/classes/engagement/EngagementErasureService.cls) pattern) follow each DML with `Database.emptyRecycleBin(...)` — CCPA / HIPAA compliance.
- [ ] New REST resources: caller authentication is documented; the endpoint relies on standard Salesforce session auth (no custom auth code).

## DTO / contract integrity

- [ ] LWC-facing `@AuraEnabled` methods return the documented DTO shape — adding fields is safe; removing/renaming requires a coordinated LWC PR.
- [ ] Read-only methods are `@AuraEnabled(cacheable=true)`; write methods are `@AuraEnabled`.
- [ ] REST endpoint envelope matches the spec (`InboundPayload` / `InboundResult` for [`EngagementInboundRest`](../../force-app/main/default/classes/engagement/EngagementInboundRest.cls)) — wire-level changes require a Phase-2 partner notification.
- [ ] DTO inner classes are `global` only when they cross the REST boundary; otherwise `public`.

## Layering (per [ADR 0001](../architecture/decisions/0001-three-layer-selector-service-controller.md))

- [ ] No SOQL in Service classes — Selectors only. (Inline SOQL in a Service that crosses a layer is a signal the query belongs in a Selector.)
- [ ] No DML in Selector classes.
- [ ] No business logic in Controllers — they wrap a single Service call.
- [ ] Trigger handlers delegate to a Service; they do not contain the rule logic themselves.

## Pre-flight before opening the PR

1. `npm run lint` clean.
2. `npm run prettier` clean.
3. `sf project deploy validate --target-org <your-scratch>` succeeds.
4. `sf apex run test --test-level RunLocalTests --target-org <your-scratch> --code-coverage` passes with org coverage ≥75% (Salesforce hard floor; project target is ≥85%).
5. PR description follows the [TEAM.md PR template](/Users/david/Work/Zelis/.claude/agents/TEAM.md) — summary, reviewer tier, test plan, security impact, deploy plan.
6. `/review-pr` invoked on the PR to fire the [pr-review-toolkit](/Users/david/.claude/plugins/cache/claude-plugins-official/pr-review-toolkit/) agents.

## Reviewer sign-off format

Per [TEAM.md §Sign-off format](/Users/david/Work/Zelis/.claude/agents/TEAM.md):

```
— Boomer: APPROVE (Apex side clean; one nit on Logger.error message style)
— Sage: APPROVE 🟦 (low-severity finding documented inline; not a blocker)
— Atlas: APPROVE — ship it
```

Any reviewer can flag **🟥 BLOCK** (Sage's veto) or **REQUEST_CHANGES**. PRs do not merge with an open block.

---

**Summary:** sharing + `WITH USER_MODE` on every SOQL + `DMLManager` for every DML are the floor — anything missing those is auto-block. Bulkification, ApexDoc, layered code structure, sanitized errors over the LWC boundary, and PII-free Logger calls are the recurring catches. Devs file coverage gaps with Pippa; they do not write their own tests.
