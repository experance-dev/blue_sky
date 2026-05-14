# CSI-7162 Jira Push Notifications — Atlas Code Review

**Branch:** `worktree-jira-push-work` (10 commits ahead of `origin/feature/jira-push-notifications`)
**Reviewed:** 2026-05-12
**Reviewer:** Atlas (TA, code-review lane)
**Scope:** Production Apex only. Tests reviewed for context; Pippa owns critique. Docs out of scope; Marlowe owns.

## Summary

**What it does.** Adds a fire-and-forget Jira sync framework for Salesforce records. On qualifying after-insert/after-update of [`Opportunity`](../../force-app/main/default/triggers/OpportunityTrigger.trigger), [`OpportunityService.handleJiraPush*`](../../force-app/main/default/classes/OpportunityService.cls) filters records on a curated `JIRA_QUALIFYING_FIELDS` set and hands them to [`JiraPushService.publishInserts/publishUpdates`](../../force-app/main/default/classes/JiraPushService.cls), which fans out one `Jira_Push_Request__e` platform event per record. The PE trigger [`JiraPushRequestTrigger`](../../force-app/main/default/triggers/JiraPushRequestTrigger.trigger) → [`JiraPushRequestHandler`](../../force-app/main/default/classes/JiraPushRequestHandler.cls) → [`JiraPushDispatcher.process`](../../force-app/main/default/classes/JiraPushDispatcher.cls) groups events by source object, reflectively materializes a concretely-typed list of empty records (Id only), and hands it to JCFS via the [`JcfsApiAdapter`](../../force-app/main/default/classes/JcfsApiAdapter.cls) seam. JCFS forwards to Jira; Jira pulls fields back. An admin kill-switch lives in `Jira_Push_Object__mdt`; failures land in `API_Exception_Log__c`.

**Architecture verdict.** Solid bones. The Selector/Service/Domain layering is consistent with `best-practices/architecture.md`; the PublishAfterCommit + per-Id reflection pattern is the right shape for the JCFS contract; the `IJcfsApi` + `IEventPublisher` seams give clean test isolation. **Ship-ready after the BLOCK items below are addressed.** Most of the issues are either policy-conformance gaps (USER_MODE, DML routing) or minor robustness/idempotency tightening. None are fundamental redesigns.

**Headline risk.** The dispatcher is one-shot and silent on JCFS-callout failures past the catch. If Jira is down or JCFS rate-limits, you get an `API_Exception_Log__c` row and nothing else — no retry, no DLQ, no replay. For an at-most-once "notify Jira when an Opp changes" semantic that's defensible; just be sure the support runbook (Marlowe's lane) makes the manual replay path explicit, because the platform-event subscriber will not redeliver after the trigger's catch swallows the exception.

## Findings

### 🟥 BLOCK

**B1. `Logger.writeApiException` uses bare `insert`, not `DMLManager.insertAsUser`.** [`Logger.cls:262`](../../force-app/main/default/classes/logging/Logger.cls). This file was modified by this feature (commit `ca0d4c2` "Fold ApiExceptionEndpoint into Logger.logApiException"), and every failure path in [`JiraPushService.cls:169`](../../force-app/main/default/classes/JiraPushService.cls) and [`JiraPushDispatcher.cls:102,154,184,204`](../../force-app/main/default/classes/JiraPushDispatcher.cls) routes through it. Per `best-practices/apex.md`, all DML routes through `DMLManager.xxxAsUser`. This is the central exception-persistence endpoint for the entire feature; it can't be the one place we skip the rule. **Fix:** swap `insert new API_Exception_Log__c(...)` for `DMLManager.insertAsUser(new List<API_Exception_Log__c>{...})` (or `Database.insert(rec, AccessLevel.SYSTEM_MODE)` if the policy decision is that diagnostic logging should run in system mode regardless of caller perms — but make that call explicitly and document it in the method header). The existing `catch (Exception writeFail)` block already swallows the failure cleanly, so the swap is safe.

### 🟧 HIGH

**H1. `JiraPushService.getConfig` SOQL lacks `WITH USER_MODE`.** [`JiraPushService.cls:192-195`](../../force-app/main/default/classes/JiraPushService.cls). Custom Metadata is generally readable, but `best-practices/apex.md` mandates `WITH USER_MODE` on every SOQL on API 60+. CMDT reads under `USER_MODE` succeed for any authenticated user, so the fix is a one-line annotation with no behavioral risk. Make it conform.

**H2. Hard-coded `JIRA_PROJECT_ID` / `JIRA_ISSUE_TYPE` constants in production Apex.** [`JiraPushService.cls:35-36`](../../force-app/main/default/classes/JiraPushService.cls). The TODO already concedes these are "unused by `JCFS.API.pushUpdatesToJira`" today, but they're being preserved as wiring for the follow-on `pushTopicToJira` flow. Two problems with where they are: (a) they're not used by anything in this PR, so they're dead code that confuses readers — either delete them now and re-add when the follow-on lands, or (b) move them onto `Jira_Push_Object__mdt` (`Project_Key__c`, `Issue_Type__c`) so the per-SObject routing isn't pinned to "Opportunity → CSI/Story" forever. CMDT placement is the right answer because the framework is explicitly multi-SObject (the metadata file ships `Jira_Push_Object.Case.md-meta.xml` too). **Recommendation:** delete the constants in this PR; add the CMDT fields when the auto-create work lands.

**H3. `JiraPushDispatcher.pushOne` ignores `JCFS.API` callout failures past the local catch.** [`JiraPushDispatcher.cls:201-212`](../../force-app/main/default/classes/JiraPushDispatcher.cls). The catch logs to `API_Exception_Log__c` and returns — fine for at-most-once — but if JCFS returns a partial-success / per-record result envelope (some Ids accepted, some rejected), this code can't see it. We're driving JCFS through an `IJcfsApi.pushUpdates(List<SObject>) : void` contract that throws away whatever JCFS actually returned. Before go-live, confirm with the Jira team whether `pushUpdatesToJira` returns a result object on the JCFS managed-package side; if it does, widen the seam to `IJcfsApi.pushUpdates(List<SObject>) : List<JcfsResult>` and log per-record failures. If it truly is `void`, document that fact in the [`JcfsApiAdapter.cls`](../../force-app/main/default/classes/JcfsApiAdapter.cls) header so the next reviewer knows we asked the question.

**H4. Static-cache recursion guard leaks across DML cycles.** [`JiraPushService.cls:40,114-118`](../../force-app/main/default/classes/JiraPushService.cls). The `alreadyPublished` Set is by `SObjectName:Id`. In a single transaction where an Opportunity is **inserted then updated** (a common pattern — trigger-set defaults, after-update workflow rollups, before-update field updates), the insert publishes, the update is suppressed by the guard, and we lose a legitimate change-type=Update signal. The guard is documented as preventing the same record from publishing "twice in one transaction" — which is right for the same change-type, but wrong for Insert-then-Update. **Recommendation:** key the guard on `SObjectName:Id:ChangeType` so insert vs. update are tracked separately. One-line fix; no design change.

### 🟨 MEDIUM

**M1. `OpportunityService.handleJiraPushInsert` publishes every newly-created Opp regardless of CMDT.** [`OpportunityService.cls:38-43`](../../force-app/main/default/classes/OpportunityService.cls). The `Jira_Push_Object__mdt.Active__c` kill-switch is checked by the dispatcher on the consume side, _after_ the PE has already been published. That's not wrong — failing closed at consume-time is the safer place — but it means flipping the kill-switch leaves orphan `Jira_Push_Request__e` events sitting in the bus until they're consumed and quietly dropped. That's a confusing operational picture ("admin disabled Jira sync but I still see events flowing"). **Recommendation:** add a `JiraPushService.isActive(sobjectName)` check at the publish site too, so the CMDT gate works at both ends. Low-cost, makes the admin model coherent.

**M2. `JiraPushDispatcher` swallows `SObjectException` from `newSObject(recId)` with a generic catch.** [`JiraPushDispatcher.cls:178-193`](../../force-app/main/default/classes/JiraPushDispatcher.cls). A single bad Id (e.g., one that doesn't match the SObject's key prefix) currently aborts the **entire SObject's batch** because the catch is outside the for loop. If JCFS gets called with 199 valid Ids and 1 garbage Id, all 200 are dropped. **Recommendation:** wrap the per-Id `typed.add(sot.newSObject(recId))` inside the loop in its own try/catch, log the bad one, continue. Same pattern as the per-event validation at lines 99-111.

**M3. No `JiraPushService` custom exception type.** The class header in [`JiraPushService.cls`](../../force-app/main/default/classes/JiraPushService.cls) says nothing throws, and indeed `publish` doesn't — but per `best-practices/apex.md`, processor classes that catch exceptions should declare their own exception type extending the module-level base (`UtilitiesModuleException`). [`JiraPushDispatcher`](../../force-app/main/default/classes/JiraPushDispatcher.cls) declares `JiraPushDispatcherException extends Exception` (line 215) which (a) is never thrown and (b) doesn't extend `UtilitiesModuleException`. Either delete the unused class or wire it up to the base hierarchy. Same call for `JiraPushService` — if you want to keep the option to throw downstream, declare it once.

**M4. `JiraPushDispatcher.pushOne` is `@TestVisible private` but the recursion-guard / config-cache state is `@TestVisible private static` on `JiraPushService`.** Mixed visibility patterns muddy the test boundary. Not wrong, just inconsistent. Pippa will likely want one canonical "test seam location" — recommend keeping all `@TestVisible` injection points on the class they belong to and avoiding cross-class peeking. Currently `JiraPushServiceTest` reaches into `JiraPushDispatcher.jcfs` to mute the consume side — that's a test-design smell pointing at this inconsistency.

### 🟦 LOW

**L1. `JcfsApiAdapter` body lacks ApexDoc on the only public method.** [`JcfsApiAdapter.cls:20`](../../force-app/main/default/classes/JcfsApiAdapter.cls). Per `best-practices/apex.md` method-level ApexDoc is only required when params/returns warrant it; this method takes a `List<SObject>` and returns void, so it's borderline. Given the **second `new List<SObject>()` argument is opaque** (JCFS's "deleted records" slot), a one-line `@param records` + comment on the empty-list call would help the next reader. Cheap.

**L2. `JiraPushDispatcher.NoOpJcfsApi` warn log doesn't include `txnId`.** [`JiraPushDispatcher.cls:60-67`](../../force-app/main/default/classes/JiraPushDispatcher.cls). Every other log line in the framework carries the transaction Id; the no-op fallback doesn't. Minor but matters if production ever silently runs without the adapter for some deployment reason.

**L3. `JiraPushService.publish` step comments use `/** ... \*/` JavaDoc syntax for inline section dividers.** [`JiraPushService.cls:89-95, 100-108, 134-139, 152-158, 161-166`](../../force-app/main/default/classes/JiraPushService.cls). These aren't ApexDoc; they're flow comments. `best-practices/apex.md` says ApexDoc lives in headers only and inline section dividers should be block comments. Same goes for [`JiraPushDispatcher.cls:81-86, 118-122, 130-136, 147-150, 165-172, 195-200`](../../force-app/main/default/classes/JiraPushDispatcher.cls). One commit message in this branch (`278fcf0 convert flow section headers to block-comment style`) suggests this conversion was started — finish it.

**L4. Field-token comparison via `SObject.get(SObjectField)` is supported but inconsistent with the canonical `oldMap.get(o.Id)` pattern.** [`OpportunityService.cls:101-112`](../../force-app/main/default/classes/OpportunityService.cls). Using field-token (`Schema.SObjectField`) keys for `get()` is correct and compile-checked — good. Just confirm with Boomer that Apex normalizes `null` equality the way you expect across all the field types in `JIRA_QUALIFYING_FIELDS` (notably `CloseDate` and `Amount` — Date and Decimal null-handling can surprise). The test plan should cover null-to-value and value-to-null on each.

**L5. `JIRA_PROJECT_ID = 'CSI'` is a hard-coded org-specific value.** [`JiraPushService.cls:35`](../../force-app/main/default/classes/JiraPushService.cls). Already flagged in H2; mentioning here as a config-hygiene concern even if H2 is deferred.

## Architecture observations

**Layering is correct.** Trigger → TriggerHandler → Service is the canonical shape from `best-practices/architecture.md`. The fact that change-detection logic was _moved out_ of `JiraPushService` and into `OpportunityService` (commit `4823248`) is the right call — `JiraPushService` stays generic across SObject types; per-SObject qualifying logic belongs in that SObject's domain service. When `Case` or any other SObject wires in, it'll get its own `CaseService.handleJiraPushUpdate(...)` with its own `JIRA_QUALIFYING_FIELDS`. Good separation.

**Contract integrity.** The `IJcfsApi` / `IEventPublisher` interfaces are the right seams. They're narrow (one method each), they don't leak JCFS types into the rest of the codebase, and the `Type.forName` fallback to `NoOpJcfsApi` is a clean way to keep the framework deployable to scratch orgs that don't have the JCFS managed package. This pattern is worth documenting in `best-practices/architecture.md` as the canonical approach for any future managed-package integration (Marlowe).

**Idempotency.** Per-transaction guard exists (`alreadyPublished`) but has the cross-change-type bug noted in **H4**. Cross-transaction idempotency is the JCFS / Jira side's problem and out of our scope — the PE itself carries `Transaction_Id__c` so a downstream consumer could dedupe if needed.

**Cross-cutting concerns.** No collisions with the engagement-attribution feature. No shared classes touched. The only utility classes modified by CSI-7162 are `Logger` (added `logApiException`) and the new `API_Exception_Log__c` SObject — both are general-purpose and will be used by every future integration. That's a feature, not a bug, but **it means Logger and API_Exception_Log are now on the critical path for every integration in this codebase**, and the BLOCK on the bare `insert` (B1) hits all of them.

**Bulkification.** Every method in scope takes a `List<>`. No SOQL or DML inside loops. PE publish is a single batch call. JCFS push is one call per SObject regardless of record count. Clean.

**Recursion guards.** `TriggerHandler` enforces a default loop-count cap via `setMaxLoopCount`/`addToLoopCount`. The Opportunity trigger inherits this. The same-transaction PE recursion guard in `JiraPushService.alreadyPublished` adds a second layer specifically for the publish path (cheap insurance against re-firing the after-update trigger).

## Cross-team handoffs

**Pippa (test plan):**

- Verify there's a test for **insert-then-update in the same transaction** — current code suppresses the update due to **H4**. Either the test asserts the (buggy) suppression and we accept it as known behavior, or H4 is fixed and the test asserts both events fire.
- Verify there's a test for **partial-bad-Id batch** — i.e., a `JiraPushRequest__e` batch where one event has a malformed `Source_Id__c` and the rest are valid. **M2** says the whole batch dies; the test should pin that down so we know if it changes.
- Verify there's a test exercising the **CMDT-inactive** code path on both the publish side (does not exist today — see **M1**) and the consume side (exists in `JiraPushDispatcherTest`).
- Verify there's a test for **null-to-value and value-to-null** on each `JIRA_QUALIFYING_FIELDS` field (see **L4**).
- Verify the **`LoggerApiExceptionTest`** asserts `API_Exception_Log__c` row insert success — it's the persistence endpoint for every failure path in the framework and B1 will change that DML call.

**Marlowe (docs):**

- [`JiraPushDispatcher`](../../force-app/main/default/classes/JiraPushDispatcher.cls) — the reflection-based concretely-typed list trick (`Type.forName('List<' + sobjectName + '>')`) deserves a callout in the integration playbook. It's clever, it's load-bearing, and it'll trip up someone who tries to refactor it to a `List<SObject>`.
- [`JcfsApiAdapter`](../../force-app/main/default/classes/JcfsApiAdapter.cls) — document the scratch-org-without-managed-package fallback pattern. This is a reusable design for any future managed-package integration.
- Operational runbook: **what happens when Jira is down**, and how to manually replay `API_Exception_Log__c` rows. Headline risk in the Summary above — the framework is fire-and-forget at the JCFS callout, so manual replay is the recovery path.
- Document the `Jira_Push_Object__mdt.Active__c` kill-switch — where to find it, what it does, what it doesn't do (e.g., today it doesn't stop publishes; see **M1**).

**Sage (security):**

- **B1** is also a security finding — bare `insert` on `API_Exception_Log__c` bypasses CRUD/FLS. She'll likely call this BLOCK independently.
- Confirm `API_Exception_Log__c.Source_Record_Id__c` (Text, not Lookup) doesn't leak record Ids to users who can read the log but not the source record. The object is `sharingModel=Private` so default-deny on rows, but the stored Id strings are visible to anyone with read access to the log. May or may not be intentional — get her call.
- Confirm CMDT read of `Jira_Push_Object__mdt` is acceptable in user mode (it's CMDT, so yes, but **H1** still wants the explicit `WITH USER_MODE`).

## Sign-off

This is a well-structured framework with clean seams and the right architectural shape. The BLOCK (B1) is a one-line fix in `Logger`; the HIGHs are tightening, not redesigning. **Fix B1, decide on H1-H4 (most can be one-iteration follow-ups if scope is tight), and this ships.** I'd rather see H4 fixed in this PR than later because it's a correctness bug on a common code path — Insert-then-Update in the same transaction is normal trigger flow, not an edge case.

— Atlas
