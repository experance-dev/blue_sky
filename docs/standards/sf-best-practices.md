# Salesforce Best Practices — Standards Team Canon

|              |                                                                                                                                                                                              |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Owner**    | Magnus (Standards Team, CTA-tier)                                                                                                                                                            |
| **Status**   | LIVING DOCUMENT. Seeded 2026-05-16 from the PR #6 (MI / Engagement Attribution) architectural review. Migrates to Confluence Blue Sky space when that workspace stands up.                   |
| **Scope**    | Apex, LWC, Triggers, Async, Sharing, Permsets, REST, Observability, Retention. Platform-level.                                                                                               |
| **Audience** | Dev Team (Atlas / Boomer / Tex / Finn / Coda / Kit / Robin / Pippa / Wren) writes against this doc; QA, Security, and Standards Team review against it.                                      |
| **Related**  | [best-practices/](../../best-practices/) (the seed; this doc supersedes once feature-parity reached) · [TEAM.md](../../.claude/agents/TEAM.md) · [CLIENT.md](../../.claude/agents/CLIENT.md) |

> **How to read this doc.** Each canon entry is a numbered pattern with a one-line rule, a why, and a real reference to a shipped or shipping class. The reference IS the evidence — if the class drifts, the canon entry needs an update. Living doc.

---

## §1 Layering — Selector / Service / Domain

### 1.0 — Reference architecture: Apex Enterprise Patterns (fflib) alignment

**Our layering follows [Apex Enterprise Patterns](https://github.com/apex-enterprise-patterns/fflib-apex-common) (fflib). We do NOT pull in the framework classes.**

| Layer          | fflib base                                      | Our equivalent                                                                                   | Why we diverge                                                                                                                                                                                                                              |
| -------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Selector       | `fflib_SObjectSelector`                         | Hand-rolled static selectors (`EngagementTouchesSelector`)                                       | fflib adds dynamic-SOQL-building + automatic FLS enforcement; we use explicit `WITH USER_MODE` per-method. Less framework, more readable per-query.                                                                                         |
| Service        | `fflib_Application.Service` factory + interface | `IEngagementService` + `@TestVisible setServiceForTest`                                          | fflib factory maps Type → instance app-wide; ours is per-controller injection. Simpler, smaller surface, same DI seam.                                                                                                                      |
| Domain         | `fflib_SObjectDomain`                           | `TriggerHandler` subclasses + service calls (no domain base class)                               | fflib's Domain base auto-wires trigger context + bulk method invariants; the Kevin O'Hara `TriggerHandler` we extend already gives us trigger-context + loop-count + bypass machinery.                                                      |
| DML chokepoint | `fflib_SObjectUnitOfWork`                       | [`DMLManager`](../../force-app/main/default/classes/dml/DMLManager.cls) (PatronManager LLC, MIT) | UnitOfWork batches DML at transaction-commit time; DMLManager wraps each DML call with `xxxAsUser`/`xxxAsSystem` CRUD/FLS enforcement. Different shape, same goal — single chokepoint. Auditing the chokepoint is the load-bearing posture. |
| Mocking        | `fflib_ApexMocks` (Mockito-style)               | [`TestDouble`](../../force-app/main/default/classes/testing/TestDouble.cls) + interface mocks    | ApexMocks is more capable than we use. TestDouble is hand-rolled, smaller, fits our @TestVisible-setter DI pattern exactly.                                                                                                                 |

**The rule.** When you read fflib documentation, mentally map it onto our equivalents — the pattern is the same; the classes aren't. Don't introduce fflib base classes piecemeal; that creates two parallel framework footprints in the same codebase. If a future engagement wants fflib, it's a holistic adoption decision, not a per-feature one.

**Citation discipline.** When someone reads our code and asks "is this fflib?", the answer is: **"We follow the Apex Enterprise Patterns layering with hand-rolled equivalents grounded in our personal-utility library ([`experance-dev/salesforce-utilities`](https://github.com/experance-dev/salesforce-utilities)). The pattern is the same; the framework footprint is smaller."** Point them at this section.

### 1.1 — One controller-facade per LWC entry point; thin try/catch wrappers; zero business logic

**Rule.** The `@AuraEnabled` class delegates to a service via interface; it contains no logic beyond input pass-through and exception-shaping.

**Why.** Tests inject mocks via `@TestVisible setServiceForTest`. The controller is the only `with sharing` surface the LWC binds to, so the security boundary is one class wide.

**Evidence.** [`EngagementController.cls`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementController.cls) delegates every `@AuraEnabled` to `IEngagementService`. [`EngagementServiceImpl.cls`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementServiceImpl.cls) is the production implementation.

### 1.2 — Interface for service contract enables DI without changing production wiring

**Rule.** Every non-trivial service exposes an interface (`I<Name>Service.cls`); the controller depends on the interface; the implementation injects via `@TestVisible` setter.

**Why.** Tests run without DML by stubbing the interface. Production wires once at class-load time (`private static IEngagementService service = new EngagementServiceImpl();`).

**Evidence.** [`IEngagementService.cls`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/IEngagementService.cls) + `EngagementController.setServiceForTest()`.

### 1.2.1 — CMDT access prefers `Type.getInstance()` / `Type.getAll()` over SOQL

**Rule.** Custom Metadata Type access uses the platform Type methods by default — `MyType__mdt.getInstance(devName)` for single-row lookup, `MyType__mdt.getAll()` for the full keyed map. SOQL on CMDT is the EXCEPTION, not the default, and is justified only when:

1. The filter is expensive in Apex (rare — CMDT is platform-cached, in-memory filter on a `getAll().values()` collection is fast for any realistic CMDT size).
2. You need `ORDER BY` semantics that would require building a Comparable wrapper in Apex — and even then, an in-memory `List.sort()` with a comparator (or insertion-sort over `getAll().values()`) is usually simpler.

**Why.** Platform Type methods are **zero-SOQL** — they don't consume the 100-SOQL governor count, they're platform-cached at the metadata layer, and they survive across same-transaction invocations without re-querying. SOQL on CMDT consumes governor count AND triggers PMD's `ApexCRUDViolation` rule (see [§12.3.4](#1234--pmdapexcrudviolation-narrow-waiver-only-when-cmdt-soql-is-genuinely-necessary)).

**Pattern:**

```apex
// Preferred — zero SOQL, platform-cached
Map<String, Touch_Routing_Rule__mdt> rulesByName = Touch_Routing_Rule__mdt.getAll();
List<Touch_Routing_Rule__mdt> active = new List<Touch_Routing_Rule__mdt>();
for (Touch_Routing_Rule__mdt rule : rulesByName.values()) {
    if (rule.Active__c == true) active.add(rule);
}
// in-memory sort by Priority__c ASC — CMDT is small, this is fast

// Exception — only when SOQL is genuinely necessary
[SELECT ... FROM MyType__mdt WHERE ... WITH SYSTEM_MODE]
```

**Evidence — sweep targets in PR #6:**

- [`TouchRoutingRulesSelector.selectActiveOrderedByPriority`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/TouchRoutingRulesSelector.cls) — SOQL with `WHERE Active__c = TRUE ORDER BY Priority__c ASC`. Replace with `Touch_Routing_Rule__mdt.getAll().values()` + in-memory filter + sort.
- [`RecordCleanupContext.getActiveRules`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/RecordCleanupContext.cls) — SOQL with same filter+sort shape. Same fix.
- [`EngagementServiceImpl.loadSourceEventTypeDisplayMap`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementServiceImpl.cls) — dynamic SOQL filter `Field_API_Name__c = :fieldKey` on `Engagement_Picklist_Display__mdt`. Replace with `Engagement_Picklist_Display__mdt.getAll().values()` + in-memory filter.

**Side benefit of the sweep.** §12.3.4 waiver becomes near-moot — PMD only flags CMDT SOQL, and if we don't have CMDT SOQL, there's nothing to suppress.

### 1.3 — Selector classes own ALL SOQL for an SObject; zero business logic; zero DML

**Rule.** Selectors are stateless, bind-variable-only, `WITH USER_MODE` everywhere, return canonical-shape lists. Defensive null/empty short-circuit at method entry. Defensive `LIMIT` cap commensurate with downstream payload budget.

**Why.** Every SOQL for an SObject lives in one place. Easy to audit USER_MODE coverage; easy to add fields to canonical projections; tests mock at the selector boundary.

**Evidence.** [`EngagementTouchesSelector.cls`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementTouchesSelector.cls).

**Open concern.** When two selector methods differ only in WHERE clauses (e.g., topic-filter vs no-filter), prefer a dynamic-SOQL string-builder with bind variables over duplicating a 30-field projection. See `selectByOpportunityWithTopics` lines 113–183 — sweepable in follow-up.

---

## §2 Sharing — `with sharing` + `WITH USER_MODE` + `AccessLevel.USER_MODE`

### 2.1 — Every class touching user data declares `with sharing` explicitly

**Rule.** No implicit defaults. `with sharing`, `without sharing`, or `inherited sharing` — choose one.

**Evidence.** All MI feature classes declare `with sharing`. The one `without sharing` class — [`RecordCleanupBatch.cls`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/RecordCleanupBatch.cls) — documents the elevation reason in its class header.

### 2.2 — Every SOQL uses `WITH USER_MODE` on standard + custom SObjects; `WITH SYSTEM_MODE` on CMDT

**Rule.** Standard / custom SObject SOQL → `WITH USER_MODE` (enforces CRUD/FLS at query site). CMDT SOQL → `WITH SYSTEM_MODE` (CMDT bypasses CRUD/FLS by platform rule; `USER_MODE` is theater + has raised `QueryException` on older API versions).

**Evidence.** [`EngagementServiceImpl.queryAcrsByContact`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementServiceImpl.cls) (USER_MODE). [`RecordCleanupContext.getActiveRules`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/RecordCleanupContext.cls) (SYSTEM_MODE on `Record_Retention_Rule__mdt`).

### 2.3 — All DML through `DMLManager.xxxAsUser` (production) or `xxxAsSystem` (audited elevations only)

**Rule.** Never bare `insert`/`update`/`delete` outside `DMLManager`. The one platform-API exception — `Database.upsert(records, externalIdField, false, AccessLevel.USER_MODE)` for external-id upsert — must be documented inline with a TODO to add the overload to `DMLManager` upstream.

**Evidence.** Every MI write — [`EngagementServiceImpl.addToOcrSafe`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementServiceImpl.cls), [`EngagementSignalRouter.insertSignals`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementSignalRouter.cls) — uses `DMLManager.insertAsUser`. The documented exception is [`EngagementInboundRest.upsertTouches`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementInboundRest.cls) lines 290–298 with inline TODO noting "future DMLManager enhancement."

**Open concern.** [`EngagementServiceImpl.dismissSignal`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementServiceImpl.cls) line 199 uses `Database.update(signal, AccessLevel.USER_MODE)` instead of `DMLManager.updateAsUser`. Not documented inline; should be swept to DMLManager.

### 2.4 — Cross-permset USER_MODE SOQL on feature-gated fields requires `isAccessible()` guard EVERYWHERE the field is queried

**Rule.** When ANY code path issues `WITH USER_MODE` SOQL referencing a custom field that may not be in the running user's FLS (because it's gated by a feature permset), the SOQL raises `QueryException: "No such column"` for users without FLS — USER_MODE _hides the field from the schema_, it doesn't just block reads. Guard with `Schema.sObjectType.X.fields.Y.isAccessible()` at the top of every method that issues such a query.

**"We ran USER_MODE, we're done" is the wrong mental model.** The guard is REQUIRED, not optional. Applies to triggers (Lead, Contact, Account before-delete and after-update), cascade services called from triggers, batches that re-process records, and any other code path a non-feature-permsetted user might cause to fire.

**Why.** Unrelated personas must never have their core SObject operations (Lead delete, Lead convert, Contact delete) broken because they happen to lack FLS on a feature's custom lookup. The guard short-circuits cleanly — there's nothing for that user to process in their user-mode view, so the path is correctly a no-op.

**Rule of thumb:** if a class can be invoked under any persona's transaction (any trigger handler, any cascade service called from a trigger, any inbound REST endpoint a non-feature user might trigger indirectly), and it issues `WITH USER_MODE` SOQL on a feature-gated field, the guard is REQUIRED. Grep for the field's API name across the codebase when canonizing a new feature-gated field; every USER_MODE site needs the guard.

**Reference implementations (5 sites, all guards in place at PR #6 HEAD `46c2763`).**

| #   | Site                                                                                                                                                                                                  | Field guarded                                 | Triggered from                |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- | ----------------------------- |
| 1   | [`LeadEngagementReparentHandler.reparentTouches`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls#L75) line 75     | `Engagement_Touch__c.Lead__c`                 | Lead after-update (convert)   |
| 2   | [`EngagementErasureService.collectTouchIdsForContacts`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementErasureService.cls#L201) line 201  | `Engagement_Touch__c.Contact__c`              | Contact before-delete cascade |
| 3   | [`EngagementErasureService.deleteSignalsForContacts`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementErasureService.cls#L225) line 225    | `Opportunity_Engagement_Signal__c.Contact__c` | Contact before-delete cascade |
| 4   | [`EngagementErasureService.deleteDismissalsForContacts`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementErasureService.cls#L252) line 252 | `Engagement_Dismissal__c.Contact__c`          | Contact before-delete cascade |
| 5   | [`EngagementErasureService.collectTouchIdsForLeads`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementErasureService.cls#L283) line 283     | `Engagement_Touch__c.Lead__c`                 | Lead before-delete cascade    |

Pattern shape across all five: describe → `isAccessible()` short-circuit (return empty `Set<Id>` or no-op) → `WITH USER_MODE` SOQL. Use the [`LeadEngagementReparentHandler` site (lines 67–76)](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls#L67) as the comment-block template — it explains the USER_MODE-hides-FLS-blocked-fields mechanism for the next reader. Bug-class sweep at [`magnus-pr6-bug-class-sweep.txt`](../../.claude/projects/-Users-david-Work-Zelis/team-status/magnus-pr6-bug-class-sweep.txt) confirms 0 other unguarded sites in the MI codebase.

**Defense-in-depth candidates (not bugs today; flagged for caller-drift immunity).** [`EngagementDismissalsSelector.cls:44`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementDismissalsSelector.cls#L44) and [`:78`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementDismissalsSelector.cls#L78) query `Engagement_Dismissal__c.Contact__c` under USER_MODE; callers today are MI-Lightning-gated by component-visibility, so the bug doesn't fire. A future caller from a non-MI context (REST, batch, foreign trigger) would surface the same failure. Adding the guard is two lines per site.

### 2.6 — Per-user state requires OWD `Private` — never `ReadWrite` + application-layer filter

**Rule.** When an SObject stores **per-user state** (per-user dismissals, per-user preferences, per-user UI state), OWD MUST be `Private`. Sharing rules + role-hierarchy widen access where business requires; the default keeps each user's rows visible only to that user. **Never** rely on an application-layer `WHERE CreatedById = UserInfo.getUserId()` filter as the sole boundary.

**Why.** Application-layer filters are one selector method away from being dropped — by accident, in a refactor, by a future feature reusing the same SObject. If the boundary is the platform's sharing model, Salesforce enforces it for every SOQL forever. If the boundary is the application, the application becomes a single point of failure for cross-user data disclosure.

**Evidence.**

- ❌ [`Engagement_Dismissal__c.object-meta.xml`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/objects/Engagement_Dismissal__c/Engagement_Dismissal__c.object-meta.xml) — currently `<sharingModel>ReadWrite</sharingModel>` + `<externalSharingModel>ReadWrite</externalSharingModel>`. The [`EngagementDismissalsSelector`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementDismissalsSelector.cls) filter `CreatedById = UserInfo.getUserId()` holds the boundary alone. Sweep target — change OWD to `Private`; the selector filter becomes a self-documenting `with sharing` no-op; Admin moderation use case stays via `viewAllRecords`/`modifyAllRecords` on the Admin permset. Caught by Sage on PR #6.

### 2.5 — Defense-in-depth permission gating: FlexiPage + LWC custom-permission + Apex Class Access

**Rule.** Three layers protect every feature-gated LWC:

1. **FlexiPage Component Visibility** — `$Permission.<CustomPermission> == true` on the placement. Hides the panel for non-permissioned users at the App Builder layer.
2. **LWC `@salesforce/customPermission/<name>` import** — `=== true` strict check inside the component. Even if FlexiPage misconfigures, the LWC self-gates.
3. **Apex Class Access on the permset** — controls who can invoke the `@AuraEnabled` controller. Even if both UI layers leak, the Apex layer rejects.

**Evidence.** [`engagementPanel.js`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/lwc/engagementPanel/engagementPanel.js) lines 33–34 + 113–119 + comment lines 107–112. [`Additional_Permissions_Marketing_Influence_View.permissionset-meta.xml`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/permissionsets/Additional_Permissions_Marketing_Influence_View.permissionset-meta.xml) grants Apex Class Access on `EngagementController`.

---

## §3 Observability — Exception Handling + Logger Discipline

### 3.0 — Rethrown exception messages MUST use `e.getTypeName()`, NEVER `e.getStackTraceString()`

**Rule.** When a catch block rethrows a wrapped exception, the user-facing message MUST surface only:

- A sanitized human sentence
- `e.getTypeName()` (the exception class name — operator hint, no internal detail)
- The transaction request ID via `System.Request.getCurrent().getRequestId()`

**NEVER concatenate `e.getStackTraceString()` into the rethrown exception message.** The stack trace leaks class names + line numbers + internal topology to whoever surfaces the exception — Lightning UI toast, Setup "Delete failed" page, REST response body, anywhere downstream. The stack belongs in `Logger_Log__c` via `Logger.logException`, not in the user-facing rethrow.

**Why.** Salesforce surfaces uncaught/rethrown exception messages directly to operators. A user attempting to delete a record can read class names, line numbers, and method signatures from a "Delete failed" toast — that's a reconnaissance surface, not just an ugliness issue.

**Evidence.**

- ✅ [`OpportunityTriggerHandler`](../../force-app/main/default/classes/OpportunityTriggerHandler.cls) all 4 catch blocks — type name + txn ID, no stack.
- ❌ [`EngagementErasureService.eraseForContacts`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementErasureService.cls) lines 81–85, [`eraseForLeads`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementErasureService.cls) lines 113–117 — concatenate `e.getStackTraceString()` into rethrow message. Caught by Sage on PR #6. Sweep target.
- ❌ Batches ([`EngagementSignalDecayBatch.persist`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementSignalDecayBatch.cls) line 178, [`EngagementTouchArchivalBatch.persist`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementTouchArchivalBatch.cls) line 102) — same pattern, lower exposure but same sweep.

### 3.1 — Catch-and-rethrow: `Logger.logException(e, ...)` (NEVER `Logger.error(e.getMessage(), ...)`)

**Rule.** Every catch boundary that needs server-side observability uses:

```apex
} catch (Exception e) {
    Logger.logException(e, '<ClassName>', '<methodName>');
    throw new <ModuleException>('<sanitized user message>. ' +
        e.getTypeName() + ' [txn:' + System.Request.getCurrent().getRequestId() + ']');
}
```

**Why.** `Logger.logException` captures full exception (type, message, stack trace, transaction context) to the `Logger_Log__c` record. `Logger.error(e.getMessage(), ...)` drops the stack trace — diagnostically opaque.

**The user-facing message gets ONLY:**

- A sanitized human sentence ("Opportunity Update failed. Contact your Administrator.")
- The exception **type name** (operator hint without leaking internal detail)
- The **transaction request ID** via `System.Request.getCurrent().getRequestId()` — lets the operator query `Logger_Log__c WHERE Transaction_Id__c = ':txnId'` to retrieve the full record.

**NEVER leak:**

- `e.getMessage()` (may contain field names, record IDs, query text)
- `e.getStackTraceString()` (leaks class names + line numbers)
- Internal SOQL or business-rule detail

**Evidence — gold standard.** [`OpportunityTriggerHandler.cls`](../../force-app/main/default/classes/OpportunityTriggerHandler.cls) all four catch blocks (handleBeforeInsert / handleBeforeUpdate / handleAfterInsert / handleAfterUpdate). This is THE canonical pattern.

**Sweep needed.** [`EngagementController`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementController.cls) (5 sites), [`EngagementServiceImpl`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementServiceImpl.cls) (6 sites), [`LeadEngagementReparentHandler`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls) (1 site), [`EngagementInboundRest`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementInboundRest.cls) (multiple) still use `Logger.error(e.getMessage(), ...)` + correlation-ID-less rethrow.

### 3.2 — AuraHandledException MUST carry a correlation ID; NEVER raw exception text

**Rule.** Aura/LWC-facing exceptions follow the same pattern as §3.1, but the rethrow is `AuraHandledException`:

```apex
throw new AuraHandledException('Unable to load engagement data. Error ID: ' +
    System.Request.getCurrent().getRequestId());
```

**Why.** The toast / inline-error the rep sees should be operator-actionable: "give me Error ID X" → admin queries the Logger_Log\_\_c row → full diagnostic. Today's MI code surfaces `'Unable to load engagement data for this opportunity.'` with no correlation — the operator has no thread to pull.

**Evidence.** [`OpportunityTriggerHandler`](../../force-app/main/default/classes/OpportunityTriggerHandler.cls) shipped this pattern. The MI controller layer must adopt it.

### 3.4 — Admin / moderation actions MUST emit a `Logger.info` audit-trail entry

**Rule.** When an admin or moderator-tier user mutates state through a controller (Ignore, Retry, Test, manual approval, force-process), the success path emits a `Logger.info` row capturing **actor + action + targetId + reason/payload + timestamp**. Audit trails are an artifact, not a side-effect — compliance posture demands they exist whether or not a regulator is asking today.

**Why.** When an admin "Ignores" a stuck touch, "Retries" a failed resolution, or "Tests" a synthesized record, the system MUST be able to answer "who did that and when" without git-archaeology. The pattern mirrors GDPR cascade audit (which we already get right at [`EngagementErasureService.logSummary`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementErasureService.cls) line 234).

**Pattern:**

```apex
DMLManager.updateAsUser(touches);
Logger.info(
    UserInfo.getUserName() + ' ignored touch ' + touchId + ' reason=' + reason,
    CLASS_NAME, 'ignoreTouch');
```

**Evidence.**

- ✅ [`EngagementErasureService.logSummary`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementErasureService.cls) line 234 — subject erasure audit gets this right.
- ❌ [`EngagementAdminController.ignoreTouch`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementAdminController.cls) lines 265–287, [`retryResolution`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementAdminController.cls) lines 233–255, [`testTouch`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementAdminController.cls) lines 52–75 — missing audit trail on the success path. Caught by Sage on PR #6.

### 3.5 — `Trigger_Exception_Log__c` is the natural next step (David's next ticket)

**Rule.** §3.1 is the manual application of the pattern. The institutional pattern is:

1. A dedicated SObject (`Trigger_Exception_Log__c`) to persist trigger exceptions with full context (class, method, txn ID, record ID, full exception, recoverable-or-not flag).
2. A `Logger.logTriggerException(e, className, methodName, sObjectType, recordIds)` helper that writes the row.
3. A retention rule via [`Record_Retention_Rule__mdt`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/objects/Record_Retention_Rule__mdt/) — the framework shipped in this PR — that ages out the log rows.
4. A `Trigger_Exception_Viewer` permset for ops triage.

The work is scoped in [project_trigger_error_logging.md](../../.claude/projects/-Users-david-Work-Zelis/memory/project_trigger_error_logging.md).

---

## §4 Trigger Framework

### 4.1 — One trigger per SObject; trigger body is one line

**Rule.** The trigger body delegates to `TriggerHandler.initialiseHandler(MyHandler.class)`. No business logic, no SOQL, no DML in the trigger. The handler extends `TriggerHandler` and overrides `initialise()`, branching on `Trigger.isBefore/isAfter/isInsert/...`.

**Why.** The framework's loop-count, bypass, and order-of-execution discipline is centralized. Handlers and services are independently testable without firing a trigger.

**Evidence.** [`EngagementTouchTrigger.trigger`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/triggers/EngagementTouchTrigger.trigger), [`ContactTrigger.trigger`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/triggers/ContactTrigger.trigger).

### 4.2 — Multiple distinct concerns on the same SObject: register multiple handlers in the trigger

**Rule.** When a single SObject needs distinct concerns (e.g., Lead = reparent-on-convert AND erasure-cascade-on-delete), the trigger body calls `TriggerHandler.initialiseHandler` once per handler. The handlers self-gate on `Trigger.isAfter && Trigger.isUpdate` vs `Trigger.isBefore && Trigger.isDelete`.

**Evidence.** [`LeadTrigger.trigger`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/triggers/LeadTrigger.trigger). Both handlers are safe to instantiate on every fire because the framework dispatches based on context.

### 4.3 — Idempotency at multiple layers; defense in depth

**Rule.** Trigger handler filters down to the records that actually need work (e.g., status transitioned to `Resolved`). The downstream service ALSO enforces idempotency (e.g., the router skips signals that already exist). Re-firing the trigger or replaying a Platform Event is a safe no-op.

**Why.** Triggers fire on every DML — including unrelated field updates, workflow updates, recursion. The handler-level filter is a perf win; the service-level idempotency is the correctness boundary.

**Evidence.** [`EngagementTouchTriggerHandler.handleAfterUpdate`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementTouchTriggerHandler.cls) filters to the `Resolved` transition (perf). [`EngagementSignalRouter.queryExistingSignalKeys`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementSignalRouter.cls) deduplicates against existing signals (correctness).

### 4.4 — Bulkified by default; SOQL outside loops; map-based lookups

**Rule.** Every public service method takes a `Set<Id>` or `List<>`. SOQL is hoisted to the top; results are indexed into a `Map` for O(1) per-record lookup. No SOQL inside a `for` loop. Period.

**Evidence.** [`EngagementSignalRouter.routeTouches`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementSignalRouter.cls): 6 SOQL queries up-front (touches, opportunities, OCR, ACR, consultants, existing signals), then O(n × rules) hash-map lookups for the per-touch evaluation.

---

## §5 Async Patterns

### 5.1 — Choose the right async tool

| Tool                | When                                                                                                                   | Example                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Queueable**       | Default async. Chainable. State via class fields.                                                                      | (No MI example yet — Stream-5 will use this for the JiraPush retry chain.)                                                                                                                                                                                                                                                                                                                                                                                                                       |
| **Batchable**       | >50K records, or multi-SObject scope iteration. `Database.Stateful` for cross-execute counters.                        | [`EngagementSignalDecayBatch.cls`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementSignalDecayBatch.cls), [`EngagementTouchArchivalBatch.cls`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementTouchArchivalBatch.cls), [`RecordCleanupBatch.cls`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/RecordCleanupBatch.cls) |
| **Schedulable**     | Cron entry only. Wraps Queueable/Batchable. ZERO business logic.                                                       | [`EngagementMaintenanceScheduler.cls`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementMaintenanceScheduler.cls), [`RecordCleanupScheduler.cls`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/RecordCleanupScheduler.cls)                                                                                                                                                          |
| **Platform Events** | Fire-and-forget cross-system signals; consumer subscribed via `lightning/empApi` (LWC) or after-insert trigger (Apex). | [`Jira_Push_Request__e`](../../force-app/main/default/objects/Jira_Push_Request__e/) (CSI-7162).                                                                                                                                                                                                                                                                                                                                                                                                 |

### 5.2 — Batches re-processing aging data must filter converged-state records in `start()`

**Rule.** A batch that recomputes a value (signal decay, archival, retention) must filter out records that have already converged so re-runs over an aged dataset do no work.

**Why.** The job runs weekly. Re-running over 90% records that are already at-state is wasted DML + governor pressure. Idempotency = "running again is a no-op."

**Evidence.** [`EngagementSignalDecayBatch.start`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementSignalDecayBatch.cls) filters `Confidence__c > 0` (skips already-zero signals). [`EngagementTouchArchivalBatch.start`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementTouchArchivalBatch.cls) filters `Is_Active__c = TRUE` (skips already-archived).

### 5.3 — Mixed-SObject batch chunks: group by `SObjectType` before DML; per-type try/catch

**Rule.** Generic frameworks that process multiple SObject types in one chunk must call `record.getSObjectType()`, group into a `Map<SObjectType, List<SObject>>`, and issue one DML per type wrapped in its own try/catch — so one type's failure doesn't poison the chunk.

**Evidence.** [`RecordCleanupBatch.execute`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/RecordCleanupBatch.cls) lines 110–135.

### 5.4 — Sync trigger-time SOQL fan-out is acceptable when each query is bulkified + bounded

**Rule.** A trigger handler can call a service that issues 5–7 SOQL queries against bind-variable sets — provided the queries are pure-function over inputs, bounded by governor headroom, and there are no callouts in the path. Async (Queueable / Platform Event) is the right answer ONLY when the synchronous path would breach governor, hold external resources, or block UI responsiveness.

**Evidence.** [`EngagementSignalRouter.routeTouches`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementSignalRouter.cls) — 6 SOQL queries on every Engagement_Touch\_\_c after-insert/update batch. Documented choice; revisit if telemetry shows budget pressure (per the same rationale used for the EDM-v2 `InterestingMomentEvaluator`).

---

## §6 REST / Inbound Integration

### 6.1 — `@RestResource` classes inherit `with sharing` and run as the calling user

**Rule.** Inbound REST classes declare `global with sharing`. The session user (typically the Integration User) governs sharing. Document the assumed caller identity in the class header AND ensure the corresponding permset grants Apex Class Access.

**Evidence.** [`EngagementInboundRest`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementInboundRest.cls) lines 11–14 + 22–26. [`Additional_Permissions_Marketing_Influence_Integration`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/permissionsets/Additional_Permissions_Marketing_Influence_Integration.permissionset-meta.xml) is the Integration User's permset.

### 6.2 — Idempotent external-id upsert + partial-batch validation

**Rule.** REST endpoints accepting batched events use `External_Id__c`-keyed upsert so re-deliveries are idempotent. Per-event validation failures populate an `errors[]` array in the response; HTTP 200 means "we accept the batch; here's what we couldn't process."

**Evidence.** [`EngagementInboundRest.upsertTouches`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementInboundRest.cls) lines 287–304.

### 6.3 — Catastrophic upsert failure MUST set HTTP 5xx so the upstream retries

**Rule.** When `Database.upsert` itself throws (vs per-event validation rejection), the catch must set `RestContext.response.statusCode = 500` so the upstream caller (HubSpot, Marketo, generic webhook source) retries per its idempotency contract. Returning HTTP 200 with a populated `errors[]` is correct ONLY for partial-batch validation failures, NEVER for total upsert blowout.

**Why.** Webhook providers ACK on HTTP 2xx and stop retrying. If all events in a batch fail upsert and we return 200, the data is lost.

**Evidence.** [`EngagementInboundRest.upsertTouches`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementInboundRest.cls) lines 299–303 currently returns 200 + errors-array on catastrophic catch. **Open sweep item — coordinate with Sage/Argus on the fix.**

### 6.4 — Managed-package outbound integrations: field-mapping inventory is a PHI-perimeter artifact

**Rule.** When the outbound payload from Salesforce to an external system is shaped by a managed-package field-mapping configured outside our code (Appfire JCFS for Jira sync, Workday connectors, Slack connectors, et al.), the mapping itself is a load-bearing perimeter control — equal in importance to the trigger filter or the platform-event payload shape we author. Every such integration ships with a documented mapping inventory committed under [`docs/standards/integrations/<integration>-mapping.md`](integrations/), reviewed at PHI-perimeter cadence (quarterly minimum; per major mapping change otherwise).

**Why.** Per [CLIENT.md](../../.claude/agents/CLIENT.md), Zelis-as-engagement is engineered OUT of the PHI perimeter. The CSI-7162 Jira-push design publishes a Platform Event for every qualifying Opportunity insert/update; the PE payload itself carries metadata only (Id, Change_Type, Event_Timestamp, Transaction_Id) — no record-field content. JCFS pulls field values server-side via its managed-package field-mapping. **That mapping is now a load-bearing control between every Opportunity in dwood_z and Jira.** If a future mapping change broadens the pull to a PHI-adjacent field (Account healthcare context, Contact details on a payer account), every Opp leaks it. The mapping inventory makes the perimeter explicit.

**Inventory shape (minimum).** One row per (source SObject + field) → (target Jira project + field), with:

- Source field API name + label
- Target system + field name
- Direction (out / in / bidirectional)
- PHI sensitivity classification (`none` / `low` / `medium` / `high` / `PHI-adjacent`)
- Last reviewed date + reviewer

**Reference.** [Sage's PR #5 security review](https://github.com/experance-dev/blue_sky/pull/5) flagged this. Inventory authoring is queued for Helix Genie (data architect, Standards Team) + Tally (out-of-team review at quarterly cadence). First instance: JCFS Jira-push mapping for CSI-7162.

---

## §7 Retention / Cleanup

### 7.1 — Logs are just another record; SObject-agnostic retention is the canonical pattern

**Rule.** Retention is driven by a CMDT-configurable rule engine, not by per-SObject schedulable classes. One framework deletes log records, audit records, business records — same engine.

**Evidence.** [`RecordCleanupBatch`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/RecordCleanupBatch.cls) + [`Record_Retention_Rule__mdt`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/objects/Record_Retention_Rule__mdt/) — class header line 14–18 makes the design intent explicit.

### 7.2 — `without sharing` + `xxxAsSystem` is the canonical retention-framework elevation; document the boundary

**Rule.** Scheduled retention must remove records regardless of the running user's CRUD/FLS. The framework class declares `without sharing`, calls `DMLManager.deleteAsSystem`, and documents the elevation in the class header. The framework class itself must NOT expose `@AuraEnabled` — the elevation never crosses into LWC-accessible territory.

**Evidence.** [`RecordCleanupBatch`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/RecordCleanupBatch.cls) class header lines 20–24. No `@AuraEnabled` methods in the class.

### 7.3 — Predicate-driven retention: positive framing, fail closed on error

**Rule.** Retention predicates implement `IRecordRetentionPredicate.shouldKeep(SObject)` — positive framing avoids the double-negative trap in CMDT rule names (`KeepIfAccountHasOpenOpportunity` reads better than `RejectIfAccountHasOpenOpportunityPredicate`). The framework calls `shouldKeep` once per candidate. On any error (class not found, predicate throws), the framework MUST return `true` (keep). Deleting on error is unrecoverable; keeping on error is a missed cleanup that runs again tomorrow.

**Evidence.** [`IRecordRetentionPredicate`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/IRecordRetentionPredicate.cls). [`RecordCleanupBatch.applyPredicate`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/RecordCleanupBatch.cls) lines 258–295.

### 7.4 — Dynamic SOQL from CMDT field values does NOT require `escapeSingleQuotes`

**Rule.** CMDT is not user input. Admin authoring CMDT is a trusted role; SQL injection from a CMDT row is a privileged-admin compromise, not a user-supplied attack. `Database.queryWithBinds` with the CMDT field value is the right pattern; document the trust boundary in the class header.

**Evidence.** [`RecordCleanupBatch.buildCandidateQuery`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/RecordCleanupBatch.cls) lines 190–211 — composes from `rule.sobjectApiName` and `rule.soqlWhereClause`, both CMDT-sourced.

---

## §8 GDPR / Subject-Erasure Cascade

### 8.1 — Subject erasure: hard-delete + `Database.emptyRecycleBin` in the same transaction

**Rule.** Compliance requires PII and behavioural data be irrecoverable. Soft-delete leaves data in the recycle bin for 15 days — a recovery window that violates CCPA / GDPR. Every subject-erasure DML pairs with `Database.emptyRecycleBin(records)` in the same method.

**Evidence.** [`EngagementErasureService`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementErasureService.cls) — every `DMLManager.deleteAsUser` is immediately followed by `Database.emptyRecycleBin`.

### 8.2 — Cascade fires from before-delete trigger; rethrow on failure to abort parent delete

**Rule.** The cascade handler runs in `before delete` so dependent records are cleaned up before the platform clears foreign-key references. On cascade failure, rethrow the exception to abort the parent delete — a silent partial cascade is a compliance gap (residual data tied to an "erased" subject).

**Evidence.** [`ContactEngagementErasureHandler`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/ContactEngagementErasureHandler.cls) lines 64–76 — the catch comment is the canonical explanation.

---

## §9 LWC Patterns

### 9.1 — Wire-getter pattern: template never reads `data` / `error` directly

**Rule.** Capture the wire result in a `wiredFoo` property; expose `get foo()`, `get error()`, `get isLoading()` getters that the template binds to. Refresh via `refreshApex(this.wiredFoo)` after writes.

**Evidence.** [`engagementPanel.js`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/lwc/engagementPanel/engagementPanel.js) lines 80–145.

### 9.2 — Multi-context LWC: one `@wire` per context with reactive null-out

**Rule.** When an LWC supports multiple SObject contexts (Account / Opportunity / Lead), declare one `@wire` per context with reactive `$paramId` getters that resolve to `null` for the non-active scope. The platform short-circuits a wire when its reactive param is null — `cacheable=true` semantics are preserved.

**Evidence.** [`engagementPanel.js`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/lwc/engagementPanel/engagementPanel.js) lines 86–103 — `$opportunityIdParam` / `$accountIdParam`.

### 9.3 — Custom-permission check: `=== true` strict-equals tolerates jest-mock-undefined

**Rule.** `@salesforce/customPermission/<name>` resolves to `true` when granted, `undefined` otherwise. Use `=== true` strict comparison so the unmocked-jest-import case is correctly treated as "no permission."

**Evidence.** [`engagementPanel.js`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/lwc/engagementPanel/engagementPanel.js) lines 113–119.

---

## §10 Test Infrastructure

### 10.0 — Every test class has an ApexDoc header pointing at the class under test

**Rule.** Every `@isTest` class carries an ApexDoc header with `@description` + `@group` + **`@see`** (the class(es) under test) + `@author David Wood` + `@since` + `@last`. The `@see` is non-negotiable — it's what lets a reader (human or AI) scan headers and map test → production code without grepping.

**Pattern:**

```apex
/**
 * @description Tests for `EngagementSignalRouter` — covers per-touch rule
 *              matching, idempotency, and bulk routing under USER_MODE.
 * @group Engagement Attribution
 * @see EngagementSignalRouter
 * @author David Wood
 * @since May 2026
 * @last 2026-05-16 — initial coverage for v1 routing rules.
 */
@isTest
private class EngagementSignalRouterTest { ... }
```

When a test class covers multiple production classes, list each on its own `@see` line. The rendered ApexDoc table then shows the full test↔code map at a glance.

### 10.1 — Personal-lib classes are read-only during Zelis work hours; license-header edits OK

**Rule.** Per [feedback-ip-protection-no-personal-lib-edits](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_ip_protection_no_personal_lib_edits.md): `Utilities.cls`, `UtilitiesHelper.cls`, `Logger.cls`, `DMLManager.cls`, `TestFactory*.cls` are NOT modified during Zelis hours. Two exceptions: (a) adding the MIT license header + source pointer is IP-establishing, not IP-degrading — always allowed; (b) DECONTAMINATING a personal-lib test class (removing Zelis-specific workarounds, switching to portable patterns) is moving in the IP-protective direction — allowed and encouraged.

**Evidence.** PR #6: license headers added to [`Utilities.cls`](../../force-app/main/default/classes/general/Utilities.cls), [`Logger.cls`](../../force-app/main/default/classes/logging/Logger.cls). [`DMLManagerTest.cls`](../../force-app/main/default/classes/dml/DMLManagerTest.cls) rewritten to use TestFactory pattern (decontamination — removes Zelis VR workarounds).

### 10.2 — Portable TestFactory pattern: org-specific VRs satisfied via `TestFactoryDefaults`, never inline

**Rule.** Test classes that ship in shared libraries (`DMLManagerTest`, `UtilitiesTest`, `LoggerTest`) construct records via `TestFactory.createSObject(record, doInsert)`. Org-specific validation-rule satisfaction lives in the consuming org's `TestFactoryDefaults`. The same test source must compile + pass in both the canonical library scratch org AND any consuming org.

**Evidence.**

- [`DMLManagerTest.cls`](../../force-app/main/default/classes/dml/DMLManagerTest.cls) header lines 25–43. Tracked future work: [project_salesforce_utilities_portable_testfactory.md](../../.claude/projects/-Users-david-Work-Zelis/memory/project_salesforce_utilities_portable_testfactory.md).
- [`TestFactoryDefaults.disableValidationRules`](../../force-app/main/default/classes/testing/TestFactoryDefaults.cls) lines 140–167 — reference-grade. Single-move neutralization (56 of 63 rules), portable dynamic dispatch, per-site WHY comments on the 7 ungated outliers. Sourced from [Tally's PR #5 audit](https://github.com/experance-dev/blue_sky/pull/5).

### 10.3 — `@TestSetup` MIXED_DML discipline: setup DML wrapped in `System.runAs(adminUser)`

**Rule.** User, PermissionSet, ObjectPermissions, PermissionSetAssignment are setup objects — DML on them inside `@TestSetup` must run under `System.runAs(adminUser)`. Non-setup DML inside `@TestSetup` runs under `System.runAs(runningUser)`. The two boundaries keep the MIXED_DML rule satisfied regardless of what platform flags or consumer-org triggers do.

**Evidence.** [`DMLManagerTest.cls`](../../force-app/main/default/classes/dml/DMLManagerTest.cls) header explains the pattern.

### 10.4 — Synthetic test-data emails use the `@example.invalid` reserved TLD (RFC 2606)

**Rule.** Every email address generated in `@IsTest` factories, fixtures, or @TestSetup uses the `.invalid` TLD reserved by [RFC 2606](https://datatracker.ietf.org/doc/html/rfc2606#section-2) — typically `<prefix>-<unique>@example.invalid`. Never `@gmail.com`, never `@<companydomain>.com`, never any TLD that could ever resolve to a real mailbox.

**Why.** `.invalid` is the IETF-reserved TLD that cannot resolve to a real mailbox by DNS construction. If a production code path ever escapes its mock seam during a test run — directly via `Messaging.sendEmail`, indirectly via a workflow/flow/trigger that sends email — the address fails delivery at the resolver, never at a real user's inbox. Paired with [feedback-no-real-emails-from-tests](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_no_real_emails_from_tests.md), this is the belt-and-suspenders boundary: the test code should NEVER dispatch, AND if it did, the address can't reach anyone.

**Pattern:**

```apex
// Good
String email = 'mi-test-' + String.valueOf(Crypto.getRandomInteger()) + '@example.invalid';

// Bad — these CAN resolve to real mailboxes
String email = 'test@example.com';       // example.com is reserved but DOES resolve
String email = 'test@gmail.com';         // real domain
String email = 'test@zelis.com';         // CONFUSED-REAL-DOMAIN — never put a company domain in test data
```

**Evidence.** [`TestFactoryDefaults`](../../force-app/main/default/classes/testing/TestFactoryDefaults.cls) per-SObject defaults seed Email values as `mi-test-XXXXXX@example.invalid`. Sourced from [Sage's PR #5 security review](https://github.com/experance-dev/blue_sky/pull/5).

---

## §11 Headers + Attribution

### 11.1 — `@author David Wood` only in shipped Salesforce code

**Rule.** Every shipped Apex class header, every LWC `@author` line, attributes to `David Wood`. Standards Team personas (Magnus, Vista, Helix, Tally, Quill, Beacon) NEVER appear in shipped Salesforce artifacts. They write Confluence, Jira comments, and standards docs — not class headers. Per [feedback-sf-attribution](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_sf_attribution.md).

### 11.2 — `@last` change-log: one line per FEATURE, not per modification

**Rule.** The `@last` entry in a class header is the audit trail of WHAT the class does now, not the git log. One line per feature ship. Commit messages are the per-modification record. Per [feedback-change-log-discipline](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_change_log_discipline.md).

### 11.3 — Every public method has ApexDoc; every `@api` LWC method has jsdoc; private methods only when one of four criteria fires

**Rule for public surface.** All `public`, `global`, `@AuraEnabled`, `virtual`, and `abstract` Apex methods carry ApexDoc on their declaration. All LWC `@api` properties and methods carry jsdoc on their declaration. Non-negotiable.

**Rule for private methods.** Default is NO ApexDoc — well-named identifiers carry the meaning, the class header carries the WHY, and mechanical docblock bloat ages code badly. Document a private method only when **at least one of these four criteria applies:**

1. **The method encodes a business rule as a predicate.** The signature says `Boolean isDismissed(...)`; the BUSINESS rule (the dismissal logic itself — "newer touch makes them reappear") needs to be in the docblock or it's locked inside the body. Example: [`EngagementServiceImpl.isDismissed`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementServiceImpl.cls), [`EngagementSignalRouter.meetsIntent`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementSignalRouter.cls).
2. **The method manages cached state.** The caching contract (per-transaction, per-class, lazy-load, invalidation) isn't visible from the signature. Example: [`EngagementServiceImpl.loadSourceEventTypeDisplayMap`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementServiceImpl.cls) — the existing docblock there is exactly right.
3. **The method has non-obvious side effects.** Mutates the input list, writes to a shared map, increments a stateful counter — anything beyond "input → return value." Document what gets mutated. Example: `applyProcessingStatus(List<Engagement_Touch__c>)` mutates the input touches' `Processing_Status__c`.
4. **The method has a subtle ordering or idempotency contract.** Must be called before/after another method, must be invoked once-per-transaction, depends on call-order, short-circuits on prior state. Example: `assembleDTOs` depends on the touches list being pre-grouped.

**The tiebreaker.** When you're unsure whether one of the four criteria applies, lean toward documenting. The cost of an extra docblock is bloat; the cost of NOT documenting is opaque code for future maintainers AND for the AI agents (Cursor / Copilot / our own subagents) that read this codebase as context to reason about it. Per [CLIENT.md](../../.claude/agents/CLIENT.md), we're an AI-augmented delivery shop — agent-readable code is a positive externality worth a slightly softer bar.

**What still does NOT need ApexDoc.** Pure-function transforms with self-documenting names (`collectContactIds`, `groupTouchesByContact`, `assetGroupingKey`), one-line wrappers, trivial accessors. The body IS the documentation; the name IS the contract.

**ApexDoc minimum per public method:**

```apex
/**
 * @description One-sentence purpose statement (the contract this method honors).
 * @param paramName Description of what each parameter means + any constraint.
 * @return Description of the return shape + any null-or-empty semantics.
 * @throws ExceptionType Conditions under which this method throws (named exception types only).
 */
public static SomeReturn someMethod(SomeParam paramName) { ... }
```

If a method has no params and a `void` return, the `@description` line is enough — drop `@param`/`@return`.

**jsdoc minimum per `@api` declaration:**

```js
/**
 * @api
 * @description One-sentence purpose / contract of this public property or method.
 * @type {string}  // for properties
 * @param {string} paramName Description of param.
 * @returns {Promise<Result>} Description of return.
 */
@api recordId;
```

For LWC events dispatched on the public surface, jsdoc the dispatch site with `@fires eventName { detail shape }` so consumers know the contract.

**Evidence.**

- ✅ [`EngagementController`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementController.cls) — every `@AuraEnabled` method has full ApexDoc with `@param` / `@return` / `@throws`.
- ✅ [`engagementPanel.js`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/lwc/engagementPanel/engagementPanel.js) class-level jsdoc explains the wire pattern + event contract. Lines 21–24 enumerate dispatched events with their detail shape.
- ✅ [`EngagementServiceImpl.loadSourceEventTypeDisplayMap`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementServiceImpl.cls) — private method with docblock because criterion #2 (cached state) applies. Exactly right.
- ❌ Sweep targets — PR #6 baseline has 269 `pmd:ApexDoc` findings; per §12.3.1 the project-wide waiver is narrowed; the public-method subset is sweep work. Private-method subset is triaged against the four criteria above — most stay undocumented (the names + signatures carry it), a minority gain docblocks.

**Why.** The standards bar Zelis architects (and future maintainers) read against is: **anyone picking up this code cold can read the public surface as a contract.** ApexDoc on the class header is the WHY; ApexDoc on the public method is the per-method contract. Both are required.

**ApexDoc minimum per public method:**

```apex
/**
 * @description One-sentence purpose statement (the contract this method honors).
 * @param paramName Description of what each parameter means + any constraint.
 * @return Description of the return shape + any null-or-empty semantics.
 * @throws ExceptionType Conditions under which this method throws (named exception types only).
 */
public static SomeReturn someMethod(SomeParam paramName) { ... }
```

If a method has no params and a `void` return, the `@description` line is enough — drop `@param`/`@return`.

**jsdoc minimum per `@api` declaration:**

```js
/**
 * @api
 * @description One-sentence purpose / contract of this public property or method.
 * @type {string}  // for properties
 * @param {string} paramName Description of param.
 * @returns {Promise<Result>} Description of return.
 */
@api recordId;
```

For LWC events dispatched on the public surface, jsdoc the dispatch site with `@fires eventName { detail shape }` so consumers know the contract.

**Evidence.**

- ✅ [`EngagementController`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementController.cls) — every `@AuraEnabled` method has full ApexDoc with `@param` / `@return` / `@throws`.
- ✅ [`engagementPanel.js`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/lwc/engagementPanel/engagementPanel.js) class-level jsdoc explains the wire pattern + event contract. Lines 21–24 enumerate dispatched events with their detail shape.
- ❌ Sweep targets — PR #6 baseline has 269 `pmd:ApexDoc` findings; per §12.3.1 the project-wide waiver is narrowed; the public-method subset is sweep work.

---

---

## §12 Static Analyzer Gate — SPOTLESS Threshold

Per [feedback-static-analyzer-gate](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_static_analyzer_gate.md).

### 12.1 — `sf code-analyzer run` is a merge gate; severity threshold is SPOTLESS

**Rule.** [`@salesforce/code-analyzer`](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/overview) v5 runs on every PR. The rule engines bundled (PMD, ESLint, RetireJS, CPD, Salesforce Graph Engine DFA) catch the class of issue human review systematically misses.

| Severity            | Pre-commit        | CI              | Owner action                                                        |
| ------------------- | ----------------- | --------------- | ------------------------------------------------------------------- |
| **sev1 (Critical)** | 🟥 BLOCKS         | 🟥 BLOCKS       | Author fixes before commit / re-requesting review                   |
| **sev2 (High)**     | 🟥 BLOCKS         | 🟥 BLOCKS       | Author fixes; pre-commit catches local                              |
| **sev3 (Medium)**   | 🟥 BLOCKS         | 🟥 BLOCKS       | Author fixes; pre-commit catches local                              |
| **sev4 (Low)**      | 🟦 passes (speed) | 🟥 BLOCKS       | Author fixes before PR merge; CI is the gate                        |
| **sev5 (Info)**     | passes            | passes (logged) | Surfaced if pattern (40+ instances → standards-doc entry or waiver) |

Zelis runs the analyzer in their deployment pipeline. Our code must be spotless or it bounces at their gate.

### 12.2 — Three run-sites

1. **Developer pre-PR (local).** Author runs before opening; HIGH must be clean before the PR opens.
2. **CI gate on push (load-bearing).** GitHub Actions runs on every push to `feature/*`, `develop`, `UAT`, `main`. Report posts as PR comment for Magnus + Sage + Atlas. Workflow at [`.github/workflows/code-analyzer.yml`](../../.github/workflows/code-analyzer.yml) — Dash Earnie owns the YAML.
3. **Tally's weekly sweep (drift).** Tally Saasy runs the analyzer org-wide weekly; new MEDIUMs, LOW-pattern growth, DFA findings get triaged. Sweep summary lands in [`docs/standards/code-reviews/<date>-analyzer-sweep.md`](code-reviews/).

Reports live at `reports/scanner-<context>.{html,json}` — gitignored (regenerable). Tally's summary doc is committed.

### 12.3 — Waivers are NARROW and SIGNED by Magnus; default is "fix, not waive"

**Rule.** When a finding is genuinely a false positive for our codebase, Magnus signs the waiver and the canonical reason lands HERE. Suppression scope is narrow (file-level or rule-level, never blanket).

**Three current Magnus-signed waivers — canonized from PR #6 review (2026-05-16):**

#### 12.3.1 — `pmd:ApexDoc` NARROW WAIVER — private + internal helpers only

**Revoked 2026-05-16:** the prior project-wide suppression was too broad. **Every public method (and global, and @AuraEnabled) MUST have ApexDoc.** See [§11.3](#113--every-public-method-has-apexdoc-every-api-lwc-method-has-jsdoc) for the positive canon.

**Current scope of the waiver:** `private static` helpers and trivially-named accessors only. Method-level ApexDoc on `private static String collectContactIds(List<Engagement_Touch__c>)` adds nothing the signature doesn't say; suppression there is fine. Every other method visibility tier (public, global, @AuraEnabled, virtual, abstract) — **PMD's flag is correct; document the method.**

**How to apply the narrow waiver.** Inline `@SuppressWarnings('PMD.ApexDoc')` on a `private static` helper method when the signature is genuinely self-documenting. Don't blanket-suppress at the class level.

#### 12.3.2 — `pmd:EagerlyLoadedDescribeSObjectResult` SUPPRESSED for schema-describe-guard pattern

**Why.** PMD flags `Schema.SObjectType.X.getDescribe().fields.getMap()` as eagerly-loading describe metadata. Our canonical cross-permset trigger guard pattern ([§2.4](#24--cross-permset-triggers-must-isaccessible-guard-fields-before-user_mode-soql)) REQUIRES the describe call — it's the only way to test `isAccessible()` before issuing USER_MODE SOQL on a feature-gated field a non-permissioned user might lack FLS for.

**Scope.** Methods that follow the canonical pattern: describe call → `isAccessible()` short-circuit → USER_MODE SOQL.

**Reference implementations:** [`LeadEngagementReparentHandler.reparentTouches`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls) lines 65–77, [`EngagementServiceImpl.loadSourceEventTypeDisplayMap`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementServiceImpl.cls) lines 553–595, [`EngagementSignalRouter.queryConsultantContactIds`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementSignalRouter.cls) lines 193–222.

#### 12.3.3 — `pmd:FieldNamingConventions` SUPPRESSED for `SCREAMING_SNAKE_CASE` constants

**Why.** PMD's `FieldNamingConventions` rule expects all instance/class fields to follow camelCase. Project convention is **`SCREAMING_SNAKE_CASE` for `private static final` constants** (`CLASS_NAME`, `PATH_OCR`, `STATUS_RESOLVED`, `MAX_VISIBLE_TOPICS`). This is the standard Apex idiom for compile-time constants and matches what every reference codebase ships.

**Scope.** `private static final` constants only. Instance fields and parameters still follow camelCase.

#### 12.3.4 — `pmd:ApexCRUDViolation` NARROW WAIVER — only when CMDT SOQL is genuinely necessary

**Revoked-broad-scope 2026-05-16:** the project default is now [§1.2.1](#121--cmdt-access-prefers-typegetinstance--typegetall-over-soql) — use `Type.getInstance()` / `Type.getAll()` instead of CMDT SOQL. With the Type methods, there is no SOQL for PMD to flag, so this waiver applies only to the edge case where SOQL is still required.

**Current scope of the waiver:** Apex methods where filtering/sorting CMDT is genuinely cheaper as SOQL than as in-memory operations against `getAll().values()`. Document the necessity inline. The SOQL itself must use `WITH SYSTEM_MODE` explicitly (CMDT bypasses CRUD/FLS by platform rule; `WITH USER_MODE` is theater on `__mdt`).

**Sweep direction:** the three current SOQL-on-CMDT sites listed in [§1.2.1](#121--cmdt-access-prefers-typegetinstance--typegetall-over-soql) are sweep targets — convert to `getAll()` patterns. The waiver doesn't apply once they're converted.

#### 12.3.5 — Personal-lib `@IsTest` infrastructure waivers — narrow + signed

**Why.** Test-infrastructure classes from David's personal [`salesforce-utilities`](https://github.com/experance-dev/salesforce-utilities) library (`TestFactory.cls`, `TestFactoryDefaults.cls`, `TestFactoryRig.cls`, `UtilitiesHelperTest.cls`) sometimes carry analyzer findings that are intentional for `@IsTest` infrastructure: bare DML to seed fixtures, non-`USER_MODE` SOQL on standard objects (Profile, User) during test setup, `EagerlyLoadedDescribeSObjectResult` from `Schema.getGlobalDescribe()` in dynamic-dispatch helpers. Fixing these in the Zelis repo violates [§10.1](#101--personal-lib-classes-are-read-only-during-zelis-work-hours-license-header-edits-ok) (personal-lib is read-only during Zelis hours); the fix belongs upstream.

**Scope.** Findings inside `force-app/main/default/classes/testing/` AND on classes that bear the salesforce-utilities license header. Rules covered:

- `pmd:EagerlyLoadedDescribeSObjectResult` on dynamic-dispatch helpers (e.g., `TestFactoryDefaults` lines 285 / 317 / 355).
- `pmd:ApexCRUDViolation` on bare `upsert`/`update` of test-fixture records (e.g., `TestFactoryDefaults.disableValidationRules` line 167).
- Non-USER_MODE SOQL on standard objects (`Profile`, `User`) used to resolve `@TestSetup` identity (e.g., `UserDefaults.getFieldDefaults` lines 429–434).

**NOT in scope:** Zelis-owned test classes (`force-app/main/default/classes/engagement/` test files, etc.). Those carry the standard `@IsTest` patterns AND the project's USER_MODE/DMLManager discipline. The waiver is for upstream-owned infrastructure only.

**How to apply.** Inline `@SuppressWarnings('PMD.<RuleName>')` on the specific method, with a one-line WHY comment citing this section: `// PMD waiver per §12.3.5: personal-lib @IsTest infrastructure; fix belongs upstream in salesforce-utilities`.

**Reference.** [Tally's PR #5 audit](https://github.com/experance-dev/blue_sky/pull/5) called out the two `TestFactoryDefaults` analyzer hits and recommended this narrow path over a class-wide waiver. [Dash's scanner baseline](https://github.com/experance-dev/blue_sky/pull/5) confirmed the three `EagerlyLoadedDescribeSObjectResult` hits fall in the same scope.

#### 12.3.6 — `pmd:CyclomaticComplexity` / `pmd:CognitiveComplexity` NARROW WAIVER — facade-pattern classes

**Why.** Per-method complexity budgets ([`<8 cyclomatic per method, <45 per class`](#1132--every-public-method-has-apexdoc-every-api-lwc-method-has-jsdoc), per [best-practices/apex.md](../../best-practices/apex.md)) are the real shape signal. Facade classes — `@AuraEnabled` LWC controllers exposing many narrow operations, `@RestResource` endpoints routing multiple HTTP verbs, service implementations aggregating per-operation delegations to selectors + DTO assemblers — legitimately accumulate **class-level** CC above 45 while every method remains under the per-method budget. The class total reflects breadth-of-public-surface, not depth-of-logic. Refactoring just to satisfy PMD by extracting `*Helper` classes fragments the facade's natural surface and hides where the public contract lives.

**Scope.** Classes that satisfy ALL three:

1. **Public surface is many narrow operations** — `@AuraEnabled`, `@HttpPost`/`@HttpGet`/etc., or service-interface methods, each ≤ 8 CC.
2. **No single method violates the per-method budget** — class total is the only finding; per-method are clean.
3. **Decomposition would create a parallel-class pattern without architectural justification** — the alternative is N `*OperationHandler` classes for a facade that's already the right shape.

**Reference implementations (post-PR #6 fixes):**

- [`EngagementInboundRest`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementInboundRest.cls) — `@RestResource` aggregating ingestion + acknowledgment flows; each method narrow.
- [`EngagementServiceImpl`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementServiceImpl.cls) — service-facade orchestrating selector + DML + DTO assembly across all engagement operations.

**Conditional waiver — `EngagementAdminController` (REVOKED when decomposition ticket ships).** [`EngagementAdminController.cls`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementAdminController.cls) currently carries class CC=124 (2.75× the budget) because it aggregates four distinct concerns: Test-a-Touch, Rule Coverage, Error Queue, Routing-Rule CRUD. Per [PR #6 review §B.3](https://github.com/experance-dev/blue_sky/pull/6), this is real architectural debt — the right shape is per-concern sub-controllers (`EngagementAdminRulesController`, `EngagementAdminTestTouchController`, `EngagementAdminErrorQueueController`). The §12.3.6 waiver covers this class TEMPORARILY until the decomposition ticket lands. **Once the decomposition ticket ships, the suppression on the original `EngagementAdminController` is REVOKED** — the new sub-controllers each fit the per-method + per-class budget without needing the waiver.

**How to apply.** Class-level `@SuppressWarnings('PMD.CyclomaticComplexity,PMD.CognitiveComplexity')` with a one-line WHY comment: `// PMD waiver per §12.3.6: facade aggregates N narrow @AuraEnabled operations; per-method budgets satisfied`. The comment makes the suppression auditable at the class header without needing to grep the standards doc.

#### 12.3.7 — `pmd:CyclomaticComplexity` NARROW WAIVER — framework-extension lifecycle-hook classes

**Why.** Framework classes whose job is **lifecycle-hook orchestration** (priming caches, applying defaults, dispatching to predicates, decorating records pre-/post-DML) accumulate class-level CC as they grow lifecycle hooks. Each hook is a single small method; the class total reflects breadth-of-extension-points, not depth-of-logic. Extracting hooks into separate classes defeats the framework's contract — consumers expect a single class to dispatch all lifecycle phases.

**Scope.** Framework classes (in `force-app/main/default/classes/retention/`, `force-app/main/default/classes/triggers/`, or similar framework-shaped directories) where:

1. **Each public method is a lifecycle hook** (`primeBulkCache`, `applyDefaults`, `validate`, `decorate`, `dispatch`, etc.).
2. **Per-method CC is under budget** — the only finding is class total.
3. **The dispatch shape is the framework's contract** — splitting hooks across classes would break consumer extension points.

**Reference implementation (post-PR #6 fix).** [`RecordCleanupBatch`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/retention/RecordCleanupBatch.cls) at CC=48 after Boomer's [§1.2.1 framework extension](https://github.com/experance-dev/blue_sky/pull/6) (the `primeBulkCache` lifecycle hook added to support CMDT `getAll()` semantics across the rule-evaluation pass). The base CC was already at the boundary; the extension pushed it fractionally over. The hook is the right shape; the CC growth reflects framework breadth.

**Carve-out — NEW framework classes default to NO waiver.** §12.3.7 applies only to **existing framework classes** that grow lifecycle hooks past 45 CC because of legitimate extension. New framework classes shipping for the first time should design hook dispatch to keep CC under budget from day one — typically by splitting per-phase concerns across multiple lifecycle interfaces the consumer composes. The waiver is for the established-framework-grows-feature case, NOT a free pass for new framework authoring.

**How to apply.** Class-level `@SuppressWarnings('PMD.CyclomaticComplexity')` with: `// PMD waiver per §12.3.7: framework dispatches N lifecycle hooks; per-method budgets satisfied`.

#### 12.3.8 — NO ANALYZER BASELINE FILE; SPOTLESS bar is enforced at every gate

**Rule.** No baseline file (`scanner-baseline.json`, `.code-analyzer-baseline.yml`, or any equivalent that records "these findings are pre-accepted; only new findings block") is permitted in this repository. The §12.1 SPOTLESS bar means **zero findings at the configured severity threshold** at every gate site (pre-commit, CI, Tally's weekly sweep). The analyzer's `--severity-threshold` flag and the inline `@SuppressWarnings`-per-§12.3.N pattern are the **only** mechanisms that suppress a finding.

**Why a baseline is rejected — not just "we didn't ship one yet":**

1. **A baseline is retroactive ratification.** Per [`feedback_no_waivers`](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_no_waivers.md), there is no fuckup-forgiveness mechanism in the canon. A baseline file is exactly that: an opaque snapshot of "findings we are willing to accept today because we already shipped them." The inline-waiver path (§12.3.1–.7) is the only sanctioned exception, and it is **pre-emptive** (named scope + Magnus-signed canon entry + cited at the call site).
2. **A baseline is invisible to authors.** Inline `@SuppressWarnings('PMD.<Rule>') // §12.3.N: <reason>` is greppable, code-review-visible, and forces the author to name the rule and the rationale. A baseline file is a JSON blob the author of new code never reads. Drift is silent.
3. **A baseline drifts the gate.** Once a baseline exists, the operative threshold is "no NEW findings" — which is strictly weaker than SPOTLESS. Zelis's deployment pipeline (the downstream consumer per [`feedback_static_analyzer_gate`](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_static_analyzer_gate.md)) does not honor our baseline; they run the analyzer fresh against their threshold. A baseline lets us pass our CI and then bounce at theirs.
4. **The 269-finding `pmd:ApexDoc` overhang is sweep work, not baseline material.** Per [§12.3.1](#1231--pmdapexdoc-narrow-waiver--private--internal-helpers-only), the project-wide ApexDoc suppression was REVOKED and the path is now sweep-toward-spotless. That sweep is documented work with owners and PRs, not a permanent acceptance.

**What this rules out concretely:**

- `sf code-analyzer run --baseline-file <path>` (any future analyzer flag that loads a baseline)
- A checked-in `reports/scanner-baseline.{json,yml}` artifact referenced by CI
- A workflow step that diffs `current-findings` against `baseline-findings` and only blocks on the delta
- Any CMDT / Custom Setting / config record that toggles "ignore pre-existing"

**What is still allowed (and how to apply it):**

- Inline `@SuppressWarnings('PMD.<RuleName>')` with a one-line WHY comment citing the §12.3.N section that justifies the suppression. This is the source-grepable, code-review-visible mechanism.
- `--severity-threshold` tuning per gate site (pre-commit at 3, CI at 4, info logged at 5) — that's gate-shape, not a baseline.
- New waiver sections under §12.3.N for genuinely-canonical exceptions, surfaced pre-emptively per §12.4 (NEVER retroactively per [`feedback_no_waivers`](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_no_waivers.md)).

**Implication for [`.github/workflows/code-analyzer.yml`](../../.github/workflows/code-analyzer.yml) ([PR #8](https://github.com/experance-dev/blue_sky/pull/8)).** The workflow MUST NOT introduce a baseline-file step or any "compare against previous run" semantics. It runs the analyzer fresh at threshold 4 on every push and PR; it blocks on every sev1–sev4 finding regardless of whether the same finding existed in a prior run. PR #8 conforms; this section is the canon that keeps it that way.

**Reference.** PMD itself ships a baseline feature ([`pmd analyze --baseline-file`](https://docs.pmd-code.org/latest/pmd_userdocs_cli_reference.html)); we deliberately do not adopt it. Salesforce Code Analyzer v5 has no first-class baseline flag as of the v5.x release, but the question would still be settled by this section if one shipped tomorrow.

### 12.4 — Future waivers MUST land here BEFORE the PR merges

**Rule.** A new waiver isn't valid until it's documented in §12.3.N with: rule name + scope + WHY + reference implementations. PR description points at the new §12.3.N entry. Magnus signs by approving the standards-doc edit.

If Magnus won't sign the waiver, the finding is real — fix the code.

### 12.5 — Shell-scripting discipline for analyzer-invoking scripts

**Rule.** Every shell script that invokes `sf code-analyzer run` (or any tool whose exit code drives a merge gate) MUST start with `set -o pipefail` (or `set -eo pipefail` for the full belt-and-braces). When the analyzer output is piped (`| tail`, `| grep`, `| jq`), POSIX-shell `$?` captures the LAST command's exit code — the analyzer's real exit code is silently lost and any downstream `[ $STATUS -ne 0 ] && exit $STATUS` block becomes unreachable. **The gate fires but never gates.**

**Why this is load-bearing.** Without this rule, every analyzer-threshold setting in [§12.1](#121--sf-code-analyzer-run-is-a-merge-gate-severity-threshold-is-spotless) is theater. Atlas can set `--severity-threshold 3`, Magnus can canonize waivers, Tally can sweep weekly — none of it matters if the shell wrapper returns 0 every time because `tail -12` exits 0.

**Companion rule — `--target` accepts repeatable flags, not comma-joined values.** `sf code-analyzer run --target` expects `-t <path>` repeated, NOT comma-joined paths. A comma-joined string produces a literal filename containing commas, which matches no file on disk; the analyzer scans ZERO files and returns 0. Combined with the missing `pipefail`, the gate is doubly silent.

**Pattern:**

```bash
#!/usr/bin/env sh
set -o pipefail   # critical — pipeline exit codes propagate

# Build the repeatable --target flags; one -t per file
TARGET_ARGS=""
for f in $STAGED_APEX; do
    TARGET_ARGS="$TARGET_ARGS --target $f"
done

sf code-analyzer run \
    --workspace force-app/main/default \
    $TARGET_ARGS \
    --severity-threshold 3 \
    --output-file "reports/scanner-pre-commit-$(git rev-parse --short HEAD).json"
STATUS=$?

# Display only — DO NOT use the pipe's $? as the gate signal
sf code-analyzer run ... | tail -12 || true

[ $STATUS -ne 0 ] && exit $STATUS
```

**Applies to ALL gate scripts.** This rule covers `.husky/pre-commit` shell hooks AND [`.github/workflows/code-analyzer.yml`](../../.github/workflows/code-analyzer.yml) once Dash wires it AND any future bash/sh-shaped gate. The defect class is shell-portable; canonize the rule once, catch it everywhere.

**Evidence.**

- ✅ [`.husky/pre-commit`](../../.husky/pre-commit) at [`9879ca8`](https://github.com/experance-dev/blue_sky/pull/7/commits/9879ca8) — reference implementation. Routes analyzer stdout to a file, reads it with `tail` AFTER capturing `$STATUS`; structurally cannot mask the gate signal. Validated end-to-end by RED/GREEN/negative test plan.
- ⏳ [`.github/workflows/code-analyzer.yml`](../../.github/workflows/code-analyzer.yml) — not yet written. Dash gets this canon up-front when he writes it.

**Companion canon — every gate ships with a PR-body-documented test plan that proves it gates.** PR #7's test plan ("stage a HIGH violation, attempt commit → should block") would have caught both bugs at author-time. Gate scripts are exactly the class of code where "I think it works" without a documented red-test is a recurring failure mode. The test plan is the gate's own gate.

---

## §13 Test Canon Discipline — Full-Suite Run + Known-Failures Canon

Per [feedback-test-canon-discipline](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_test_canon_discipline.md).

### 13.1 — Every PR runs the full Apex + Jest suite; never `RunSpecifiedTests`

**Rule.** CI runs:

```bash
sf apex run test --target-org <ci-target> \
  --test-level RunLocalTests --wait 60 --result-format human
npx sfdx-lwc-jest
```

Always full suite. Never `RunSpecifiedTests`. A PR that runs only its own tests hides regressions in untouched code.

### 13.2 — Pre-existing failures live in [`docs/testing/known-failures-canon.md`](../testing/known-failures-canon.md); CI compares actuals against canon

**Rule.** Pippa Codey + Verity Hootie own the canon. Format:

| Column       | Required                                                                                                               |
| ------------ | ---------------------------------------------------------------------------------------------------------------------- |
| Test class   | always                                                                                                                 |
| Method       | always                                                                                                                 |
| Severity     | one of: `UNABLE_TO_LOCK_ROW`, `MIXED_DML`, `NO_SINGLE_MAIL_PERMISSION`, `FIELD_NOT_FOUND`, `ASSERTION_FAILED`, `OTHER` |
| Why it fails | one-sentence cause                                                                                                     |
| Owner        | `Zelis-legacy` / `our-feature` / `blocked`                                                                             |
| Tracker      | BSKY-XXX or `none`                                                                                                     |
| Expected fix | sprint reference or `indefinite` with rationale                                                                        |

CI comparison logic:

| Outcome                   | Gate                                                            |
| ------------------------- | --------------------------------------------------------------- |
| Fail not in canon         | 🟥 BLOCK — new regression                                       |
| Fail in canon             | 🟦 passes — acknowledged drift                                  |
| Canonized test now PASSES | 🟧 flag — canon needs pruning; PR description must note removal |
| All pass + canon empty    | 🟢 release-ready (the goal)                                     |

### 13.3 — Adding to the canon requires Atlas sign-off

**Rule.** A failure becoming "known" is a deliberate concession. Three steps:

1. Categorize root cause per [feedback-zelis-quality-gates](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_zelis_quality_gates.md) Pareto pattern.
2. Pippa or Verity opens a BSKY ticket for the underlying fix.
3. Atlas signs off — verifies the failure is legit, not a hidden bug being papered over.

Then the row lands with all 6 columns filled. No half-canon entries.

### 13.4 — Pareto categorize before canonizing a wall of failures

**Rule.** When a baseline-load drops ~64 failing tests at once (the 2026-05-15 MI scenario), categorize before triage. Read 1-2 failure messages per class → group into 6-10 buckets → identify 2-3 patterns closing >60% → write per-pattern BSKY stories → canonize each failure pointing at its pattern story. Long-tail (1-2 per class, no shared pattern) gets individual canon entries.

Never hand a dev 64 failing tests. Hand them 3 pattern-tickets + a canon entry per failure.

---

## §14 Team Async Comms — Artifact-Relay is the Canonical Channel

Per [`COMMS.md`](../../.claude/agents/COMMS.md). Team agents communicate by appending **addressed, dated, sectioned notes inside the artifacts they share** — briefs, dispatch files, design docs, status trackers. Files ARE the channel; no side-channel tooling.

### 14.1 — Mechanism honesty: next-invocation re-read, not live file-watch

**Rule.** The artifact-relay pattern's perceived "same-turn" speed is the product of (a) a file edit + (b) the next agent invocation re-reading the artifact on bootstrap. There is no live file-watch daemon, no push notification, no event subscription. See [`COMMS.md:109`](../../.claude/agents/COMMS.md#L109) for the empirical observation that codified the mechanism.

**Why this matters for design.** Workflows that assume push-style delivery (e.g., "Vista edits → Nova reacts immediately") only work when Nova is invoked _after_ the edit. A note appended to an idle agent's artifact does not reach them until they're next dispatched. Design async hand-offs around invocation cadence, not file-watch.

### 14.2 — Section header, address, date, sign-off

**Rule.** Every cross-agent note carries: H2/H3 header (your name + topic + date) → body addressed to target by name → specific (not generic) content → sign-off with name + status emoji from [`COMMS.md`](../../.claude/agents/COMMS.md). Three-artifact update beats one-artifact update for team-wide visibility — the canonical status tracker (Queue table, sign-off table) gets the same edit as the target's brief.

### 14.3 — Anti-patterns

- Burying notes in unrelated sections (un-discoverable in long files).
- Un-addressed comments ("needs review" without naming the reviewer).
- Undated notes (age badly).
- Generic praise ("looks great") — teaches nothing.
- Single-artifact updates when the work crossed boundaries.

---

## Living-doc protocol

- New canon entries land here as their pattern is shipped (or canonized retroactively when an existing pattern is recognized as worth elevating).
- Each entry MUST reference a real shipped class. If the class drifts, the entry needs an update — Tally's review cadence catches drift.
- Open sweep items (places where the canon is established but not yet swept) are tracked inline. Atlas owns the sweep tickets.
- This doc supersedes [best-practices/](../../best-practices/) once feature-parity is reached. Until then, both coexist; the new doc is the source of truth; the old doc is the seed.
- Every substantive change lands as a row in the change log below — date, author, sections affected, one-line rationale. Reviewers (David, Tally, Atlas) read the change log first to spot drift fast.

---

## Change log

| Date       | Author                                                   | Sections                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Rationale                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ---------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 2026-05-16 | Magnus                                                   | Doc created. §1–§11 seeded from PR #6 architectural review. §1.1 Selector/Service/Domain layering · §1.2 DI seam · §1.3 selector pattern · §2 sharing strategy · §3 observability (Logger.logException + AuraHandledException correlation-ID) · §4 trigger framework · §5 async patterns · §6 REST · §7 retention framework · §8 GDPR cascade · §9 LWC patterns · §10 test infrastructure · §11 attribution + change-log discipline. 14 canon entries, every entry references a real shipped class in PR #6. | Magnus's first review under the Standards Team model. Standards doc is the spine every future PR cites.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| 2026-05-16 | Magnus                                                   | §12 (static analyzer gate) · §13 (test canon discipline) · §12.3.1–4 (four Magnus-signed waivers)                                                                                                                                                                                                                                                                                                                                                                                                            | Folded new memory rules [feedback-static-analyzer-gate](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_static_analyzer_gate.md) and [feedback-test-canon-discipline](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_test_canon_discipline.md). SPOTLESS threshold + waiver protocol established.                                                                                                                                                                                                                                                                                                                                   |
| 2026-05-16 | Magnus                                                   | §2.4 sharpened · §2.6 new (OWD Private for per-user state) · §3.0 new (stack-trace rethrow anti-pattern) · §3.4 new (admin audit trail)                                                                                                                                                                                                                                                                                                                                                                      | Sage's PR #6 security review caught a §2.4 canon violation at a SECOND site I missed ([`EngagementErasureService.collectTouchIdsForLeads`](../../.claude/worktrees/feature-engagement-attribution/force-app/main/default/classes/engagement/EngagementErasureService.cls)). Standards doc updated to make the canon harder to miss next time. Sage's four standards items folded in.                                                                                                                                                                                                                                                                               |
| 2026-05-16 | Magnus                                                   | §1.0 NEW (fflib alignment) · §1.2.1 NEW (CMDT prefer getAll/getInstance over SOQL) · §11.3 NEW (ApexDoc on every public method + jsdoc on every @api) · §12.3.1 NARROWED (was project-wide; now private-helpers-only) · §12.3.4 NARROWED (CMDT SOQL is exception not default)                                                                                                                                                                                                                                | David's four directives: (1) public methods must be documented; (2) CMDT belongs on `Type.getAll()` not SOQL; (3) position fflib in the doc responsibly; (4) add a change log. fflib alignment section makes our pattern-vs-framework choice explicit; CMDT shift converts §12.3.4 waiver into an edge-case-only narrow scope.                                                                                                                                                                                                                                                                                                                                     |
| 2026-05-16 | Magnus                                                   | §12.3.6 NEW (facade-pattern CC waiver — scoped to `EngagementInboundRest`, `EngagementServiceImpl`; CONDITIONAL on `EngagementAdminController` until the decomposition ticket ships, then REVOKED) · §12.3.7 NEW (framework-extension lifecycle-hook CC waiver — scoped to `RecordCleanupBatch` post Boomer's `primeBulkCache` extension; carve-out: NEW frameworks default to no waiver)                                                                                                                    | Atlas dispatch: facade aggregation accumulates class CC legitimately when per-method budgets hold. `EngagementAdminController` gets the waiver TEMPORARILY because its decomposition is real architectural debt; the waiver REVOKES when the decomposition ships. §12.3.7 separates framework-extension CC from facade CC — different rationale, easier to grep.                                                                                                                                                                                                                                                                                                   |
| 2026-05-16 | Magnus                                                   | §11.3 EXPANDED (four-criteria test for private-method ApexDoc + AI-context tiebreaker)                                                                                                                                                                                                                                                                                                                                                                                                                       | Refining the private-method rule from "MAY when non-obvious" (vague) to four explicit criteria — predicates encoding business rules, cached state, non-obvious side effects, subtle ordering/idempotency contracts. Sweep workers get an unambiguous bar; AI agents reading the codebase as context get richer per-method WHY where it matters most.                                                                                                                                                                                                                                                                                                               |
| 2026-05-16 | Magnus (canon sourced from Tally)                        | §12.5 NEW (shell-scripting discipline for analyzer-invoking scripts)                                                                                                                                                                                                                                                                                                                                                                                                                                         | [Tally's PR #7 audit](https://github.com/experance-dev/blue_sky/pull/7#issuecomment-4467640199) caught two stacking bugs in `.husky/pre-commit` that made the SPOTLESS gate a silent no-op: (1) `STATUS=$?` after `\| tail -12` captures `tail`'s exit code without `set -o pipefail`; (2) `--target "$STAGED_APEX"` passes comma-joined paths to a repeatable-flag arg. Canon entry covers both the pipefail rule and the repeatable-flag arg shape, plus a companion rule that every gate ships with a PR-body-documented test plan proving it gates. Applies prospectively to Dash's GitHub Actions YAML.                                                       |
| 2026-05-16 | Magnus                                                   | §10.0 NEW (test class ApexDoc header with `@see` to class under test)                                                                                                                                                                                                                                                                                                                                                                                                                                        | David's directive: scanning a test class's header should tell you what it tests without grepping. `@see` is the load-bearing tag — multi-class tests get one `@see` per target.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| 2026-05-16 | Magnus                                                   | §14 NEW (team async-comms canonical channel — artifact-relay pattern with mechanism honesty per [`COMMS.md:109`](../../.claude/agents/COMMS.md#L109): next-invocation re-read, not live file-watch)                                                                                                                                                                                                                                                                                                          | Folds Vista's COMMS.md protocol into the standards canon now that the mechanism-honesty correction has landed. Three sub-rules: §14.1 mechanism honesty (no push, no daemon — workflow design must account for invocation cadence), §14.2 header/address/date/sign-off shape, §14.3 anti-patterns.                                                                                                                                                                                                                                                                                                                                                                 |
| 2026-05-16 | Magnus                                                   | §2.4 — old ✅/❌ evidence pair replaced with a 5-row "Reference implementations" table citing every cross-permset USER_MODE guard site in the MI codebase: `LeadEngagementReparentHandler:75` + `EngagementErasureService:201/225/252/283`. Added defense-in-depth callout for the two unguarded MI-Lightning-gated `EngagementDismissalsSelector` sites (44/78).                                                                                                                                            | Post-PR-#6 sweep result. Sage's CRITICAL closed Lead-cascade guard #5; #2/#3/#4 closed Contact-cascade triplet earlier in PR #6; #1 is the original canonical site. Future agents adding a new feature-gated field now have a one-grep canonical example list instead of having to reconstruct the pattern. Bug-class sweep evidence: [`magnus-pr6-bug-class-sweep.txt`](../../.claude/projects/-Users-david-Work-Zelis/team-status/magnus-pr6-bug-class-sweep.txt).                                                                                                                                                                                               |
| 2026-05-16 | Dash (validation)                                        | §12.5 — validated end-to-end                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | [Dash's PR #7 fix](https://github.com/experance-dev/blue_sky/pull/7/commits/9879ca8) closed Tally's hard blocks (`set -eo pipefail`, repeatable `--target` via heredoc loop) + soft blocks (`reports/` gitignored, redundant `lint-staged` wrapper dropped, dead husky v8 bootstrap removed). RED/GREEN/negative test plan ran end-to-end: synthetic SOQL-in-loop staged → analyzer exit 3 → commit blocked; clean class staged → commit landed; hook-only stage → analyzer skipped → commit landed. This is the §12.5 companion-canon (PR-body test plan that proves the gate gates) demonstrated. The canon caught a failure mode within hours of being written. |
| 2026-05-16 | Magnus (canon sourced from Tally + Sage + Dash on PR #5) | §6.4 NEW (managed-package outbound field-mapping inventory as PHI-perimeter artifact) · §10.2 evidence row for `TestFactoryDefaults.disableValidationRules` · §10.4 NEW (`@example.invalid` reserved TLD for synthetic test emails) · §12.3.5 NEW (narrow waiver for personal-lib `@IsTest` infrastructure analyzer findings)                                                                                                                                                                                | Tally's PR #5 audit flagged `disableValidationRules` as reference-grade for §10.2 + identified two analyzer hits in `TestFactoryDefaults` needing waiver shape. Sage's PR #5 security review proposed the JCFS-mapping-inventory canon (PHI-perimeter discipline) + the `.invalid` TLD rule. Dash's PR #5 scanner baseline surfaced three `EagerlyLoadedDescribeSObjectResult` hits scoped to the same personal-lib carve-out. §12.3.5 is the narrow signed waiver that captures all three without broadening to project-wide.                                                                                                                                     |

— Magnus
