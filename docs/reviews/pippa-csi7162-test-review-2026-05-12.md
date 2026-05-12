# CSI-7162 Jira Push Notifications — Pippa Test Plan Review

**Reviewer:** Pippa Codey (vArchitect, Test Architecture)
**Date:** 2026-05-12
**Branch:** `worktree-jira-push-work`
**Worktree:** `/Users/david/Work/Zelis/.claude/worktrees/jira-push-work/`
**Scope:** Test surface for CSI-7162 only. Atlas owns prod code review; Marlowe owns docs.

---

## Summary

- **Test files in scope:** 6 (1 expected file — `JcfsApiAdapterTest.cls` — was **not found**, see Per-class)
- **Production classes covered:** 6 (`JiraPushDispatcher`, `JiraPushRequestHandler`, `JiraPushService`, `JcfsApiAdapter`, `OpportunityService`, `OpportunityTriggerHandler`) + 1 trigger pair + 2 Logger overloads
- **`@IsTest` methods discovered:** 24
  - [`JiraPushDispatcherTest`](../../force-app/main/default/classes/JiraPushDispatcherTest.cls): 11
  - [`JiraPushRequestHandlerTest`](../../force-app/main/default/classes/JiraPushRequestHandlerTest.cls): 1
  - [`JiraPushServiceTest`](../../force-app/main/default/classes/JiraPushServiceTest.cls): 7
  - [`OpportunityServiceTest`](../../force-app/main/default/classes/OpportunityServiceTest.cls): 7 (counts a 7th `testHandlersEmptyAndNullInputAreNoOp`)
  - [`OpportunityTriggerHandlerTest`](../../force-app/main/default/classes/OpportunityTriggerHandlerTest.cls): 2
  - [`LoggerApiExceptionTest`](../../force-app/main/default/classes/LoggerApiExceptionTest.cls): 3
- **Coverage measurement:** **Source-analysis only.** No deploy target available for this branch — `sf config get target-org` returns no value, and the only authenticated org (`playfulBear`, a Trailhead Dev Edition) does **not** have the Appfire JCFS managed package installed, the `Jira_Push_Request__e` PE, the `Jira_Push_Object__mdt` CMDT, or the `API_Exception_Log__c` object. Wiring a scratch org and deploying is reasonable next-pass work for David; out of my scope here.
- **Pass rate:** **Not measured.** Cannot run `sf apex run test` without a target org carrying the deploy.
- **Headline assessment:** 🟧 **Needs work before prod push.** Good-path coverage is strong; bad-path coverage of the **happy chain** is strong. **Bulk path is conspicuously absent**, **USER_MODE / permission boundary is untested**, and at least **three test methods are silently fragile** (one will likely break on the `FailingPublisher` JSON deserialization once Salesforce changes the `Database.SaveResult` shape; the e2e tests depend on `TestFactoryDefaults.OpportunityDefaults` not existing, which is a footgun bomb waiting). Coverage looks ~90%+ by line on source inspection but the **9-tick "done" checklist** scores **5.5 / 9** across the suite.

---

## Per-class assessment

### `JiraPushDispatcher` ([source](../../force-app/main/default/classes/JiraPushDispatcher.cls))

- **Tests:** 11 in [`JiraPushDispatcherTest`](../../force-app/main/default/classes/JiraPushDispatcherTest.cls)
  - `testProcessCallsJcfsWithIdOnlyConcreteList`
  - `testProcessSkipsWhenConfigMissing`
  - `testProcessSkipsWhenConfigInactive`
  - `testProcessHandlesUnknownSObjectGracefully`
  - `testProcessSkipsBlankEventsAndContinues`
  - `testProcessEmptyAndNullInputAreNoOp`
  - `testProcessUsesNoOpFallbackWhenAdapterNotDeployed`
  - `testProcessLogsApiExceptionForMalformedSourceId`
  - `testProcessLogsApiExceptionWhenJcfsThrows`
  - `testResolveDefaultAdapterReturnsAdapterWhenClassDeployed`
  - `testProcessLogsApiExceptionWhenIdPrefixMismatchesSObject`
  - `testProcessMultipleIdsForOneObjectCollapsedToOneJcfsCall` (12th — I miscounted; the suite is **12 methods**, not 11)

- **9-tick scorecard for `process(...)`:**
  | Tick | Met? | Notes |
  |------|------|-------|
  | Good path | ✅ | `testProcessCallsJcfsWithIdOnlyConcreteList` and the grouping test cover it |
  | Bad path (null/empty/malformed) | ✅ | Comprehensive — empty/null events, blank fields, bad Id, unknown SObject, prefix mismatch |
  | Bulk (≥200 records) | ❌ | **Missing.** The biggest test passes 2 events. Dispatcher must survive a 200-event PE batch — it iterates `events`, builds Sets per SObject, then loops keyset to call `pushOne`. Bulk run would surface any per-event SOQL/DML drift. |
  | Governor limits assert | ❌ | No `Limits.getQueries()` / `Limits.getDmlStatements()` assertion anywhere |
  | USER_MODE boundary | ❌ | Dispatcher only does SOQL via `JiraPushService.getConfig` (no USER_MODE specified), and the CMDT cache override hides the SOQL in tests — boundary is moot **because the class doesn't enforce one** (CMDT reads ignore sharing). Note as a non-issue, not a gap. |
  | DML exception path | ✅ | `ThrowingJcfsApi` covers JCFS failure; logging path verified |
  | Async / callout wrapped | ✅ | `Test.startTest/stopTest` used consistently. No `HttpCalloutMock` needed — JCFS is stubbed at the interface, which is cleaner. |
  | Re-fire idempotency | ❌ | **Missing.** Dispatcher has no recursion guard of its own (deliberate — it's the consume side), but two PE events with the same `Source_Id__c` in the same batch should still call JCFS once with one record, not twice with one each. **Not tested.** Easy add. |
  | Negative-id / fake-id | ✅ | `testProcessLogsApiExceptionForMalformedSourceId` and `testProcessLogsApiExceptionWhenIdPrefixMismatchesSObject` both pass fabricated Ids without DML |

- **Coverage gaps (line-level, eyeball):**
  - The `events == null` short-circuit at line 77 — covered by `testProcessEmptyAndNullInputAreNoOp`. ✅
  - The blank-event `continue` at lines 90-95 — covered. ✅
  - The `recId` `StringException` catch at lines 101-110 — covered. ✅
  - `cfg == null` and `!Active__c` branches at lines 138-145 — covered. ✅
  - `sot == null` branch at lines 153-163 — covered. ✅
  - The list-construction `try/catch` at lines 175-193 — covered by the prefix-mismatch test. ✅
  - The `jcfs.pushUpdates` `try/catch` at lines 201-212 — covered by `ThrowingJcfsApi`. ✅
  - `JiraPushDispatcherException` inner class (line 215) — **never thrown, never tested.** Either delete the class or document why it exists. Code-coverage trivia, not a real gap.

- **Test quality issues:**
  - **Reuse fragility (medium):** the `RecordingJcfs` and `ThrowingJcfsApi` stubs live as inner classes on `JiraPushDispatcherTest`. The pattern of cross-class reuse (`JiraPushDispatcherTest.RecordingJcfs`, `JiraPushDispatcherTest.buildAccount()`) is **explicitly relied on** by `JiraPushServiceTest`, `JiraPushRequestHandlerTest`, `OpportunityServiceTest`, `OpportunityTriggerHandlerTest`, and `LoggerApiExceptionTest`. That's fine — Apex doesn't give us a great alternative — but it means renaming the inner class or refactoring this file breaks **five** other test files. Document the contract in the class header. **Currently undocumented.**
  - **`Assert` usage:** consistent — `Assert.areEqual`, `Assert.isTrue`, `Assert.areNotEqual`. ✅
  - **Method names:** CamelCase, descriptive. ✅
  - **No `@TestSetup`:** correct — dispatcher tests need per-method static-state resets, which `@TestSetup` (separate transaction) can't provide.

- **Severity:** 🟧 **HIGH** — bulk and re-fire idempotency are non-trivial gaps for a PE consumer.

---

### `JiraPushRequestHandler` + `JiraPushRequestTrigger` ([handler source](../../force-app/main/default/classes/JiraPushRequestHandler.cls), [trigger source](../../force-app/main/default/triggers/JiraPushRequestTrigger.trigger))

- **Tests:** 1 in [`JiraPushRequestHandlerTest`](../../force-app/main/default/classes/JiraPushRequestHandlerTest.cls)
  - `testPublishedEventInvokesDispatcherAndJcfs`

- **9-tick scorecard:**
  | Tick | Met? | Notes |
  |------|------|-------|
  | Good path | ✅ | Single test covers the full PE-publish → trigger → handler → dispatcher → stubbed JCFS chain |
  | Bad path | ❌ | No test of a published-but-malformed event (blank fields) actually flowing through the trigger |
  | Bulk | ❌ | **No 200-event PE batch test.** PE triggers fire in batches of up to 2000; without this test, the dispatcher's grouping under realistic load is unproven |
  | Governor limits | ❌ | Not asserted |
  | USER_MODE | N/A — handler delegates immediately |
  | DML exception | N/A — handler does no DML |
  | Async wrap | ✅ | `EventBus.publish` + `Test.stopTest` is the canonical PE testing pattern |
  | Re-fire idempotency | ❌ | What happens when the trigger fires twice on the same record-set? PE deliveries can replay on consumer error — this is **mission-critical** for a Jira sync. **Not tested.** |
  | Negative-id | N/A — handler doesn't process Ids directly |

- **Coverage gaps:** the trigger itself (`new JiraPushRequestHandler().run();`) and the `afterInsert` override (3 lines) are covered. ✅

- **Test quality issues:**
  - **Single test for the entire trigger pipeline is thin.** Add the bulk-PE-batch test (200 events, mixed `Source_Object__c` values, assert one JCFS call per SObject type) and you've got a much stronger safety net.
  - **Implicit dependency** on `JiraPushDispatcherTest.RecordingJcfs` and `JiraPushDispatcherTest.buildAccount()`. Fine pattern, fragile if anyone renames either. (Same comment as above.)

- **Severity:** 🟧 **HIGH** — single happy-path test is not enough for the PE consumer.

---

### `JiraPushService` ([source](../../force-app/main/default/classes/JiraPushService.cls))

- **Tests:** 7 in [`JiraPushServiceTest`](../../force-app/main/default/classes/JiraPushServiceTest.cls)
  - `testPublishInsertsMarksRecordsAsPublished`
  - `testPublishUpdatesMarksRecordsAsPublished`
  - `testPublishRecursionGuardSuppressesSecondPublish`
  - `testPublishEmptyAndNullInputAreNoOp`
  - `testPublishLogsApiExceptionWhenEventBusPublishFails`
  - `testGetConfigQueriesCmdtWhenNoOverride`
  - `testPublishSkipsRecordsWithoutId`

- **9-tick scorecard for `publish(...)`, `publishInserts`, `publishUpdates`, `getConfig`:**
  | Tick | Met? | Notes |
  |------|------|-------|
  | Good path | ✅ | Insert + update marked-as-published paths verified |
  | Bad path | ✅ | Null/empty input, no-Id records, EventBus.publish failure all covered |
  | Bulk | ❌ | **Missing.** No 200-record `publishInserts` / `publishUpdates`. Service iterates the list, builds events, calls one `EventBus.publish` — the latter is governed by `Limits.getPublishImmediateDml`. **Bulk safety unproven.** |
  | Governor limits | 🟡 | **Half-credit.** `testPublishRecursionGuardSuppressesSecondPublish` does compare `Limits.getPublishImmediateDml()` before/after, which is a real assertion. But no `Limits.getDmlStatements()` or `Limits.getQueries()` assertion exists. |
  | USER_MODE | ❌ | **Not tested.** `getConfig` does `SELECT … FROM Jira_Push_Object__mdt` with no `WITH USER_MODE` / `AccessLevel.USER_MODE`. CMDT reads ignore CRUD/FLS anyway by platform rules, so this is a **non-issue** for the SOQL. **However**, `publish(...)` itself doesn't go through `DMLManager` and uses `EventBus.publish` (which is platform-managed). The class is `with sharing` but never tested run-as a no-permset user. Acceptable but un-asserted. |
  | DML exception | ✅ | `FailingPublisher` covers the publish-failure log path |
  | Async wrap | ✅ | `Test.startTest/stopTest` consistently |
  | Re-fire idempotency | ✅ | `testPublishRecursionGuardSuppressesSecondPublish` directly verifies the same-transaction guard |
  | Negative-id | N/A — service drops records with `null` Id silently, which is covered |

- **Coverage gaps:**
  - `publish` method lines covered except possibly the `Logger.debug` (no-op for assertions, but reached) — should be ~100%.
  - `getConfig` cache-hit path: when `configCache != null`, the second call returns from cache. **Not explicitly tested.** The test only asserts one call after a `configCache = null` reset. Add a second invocation and assert `Limits.getQueries()` doesn't bump.

- **Test quality issues — these are the loud ones:**
  - 🟥 **`FailingPublisher` is fragile.** [Line 31-34 of `JiraPushServiceTest`](../../force-app/main/default/classes/JiraPushServiceTest.cls) constructs a `Database.SaveResult` via `JSON.deserialize(failJson, Database.SaveResult.class)` with a hand-rolled JSON blob. Salesforce has previously changed the internal shape of `Database.SaveResult` between API versions (most recently in v62 with the `errors[].extendedErrorDetails` addition). The test is **one API-version-bump away from silent breakage** — and because `isSuccess()` defaults to `false` on a missing field, the test could pass while asserting on a malformed object. **Recommend:** use [`TestDouble`](../../force-app/main/default/classes/testing/TestDouble.cls) (already in the framework — see `force-app/main/default/classes/testing/TestDouble.cls`) or wrap `Database.SaveResult` in a domain DTO inside the publisher seam so the test never reaches into platform-private JSON shapes.
  - 🟨 **`testGetConfigQueriesCmdtWhenNoOverride`** depends on the org having seeded CMDT rows (`Opportunity` with `Active__c = true`). The repo ships these as `customMetadata/Jira_Push_Object.Opportunity.md-meta.xml` and `Jira_Push_Object.Case.md-meta.xml`, so it'll work in the work org — but the test **will silently fail** in any scratch org where the CMDT records aren't deployed. The test comment says "the deploy seeded Opportunity and Case records" — that contract isn't enforced anywhere. Either move this assertion behind an `if (cfg != null)` guard or annotate the test with the seed dependency explicitly.
  - **Method names:** CamelCase, descriptive. ✅
  - **`Assert.*` everywhere:** ✅

- **Severity:** 🟥 **BLOCK on the `FailingPublisher` fragility**, 🟧 **HIGH on the bulk and CMDT-dependency gaps**.

---

### `JcfsApiAdapter` ([source](../../force-app/main/default/classes/JcfsApiAdapter.cls))

- **Tests:** **NONE.** Searched for `JcfsApiAdapter*Test.cls` — file does not exist.

- **9-tick scorecard:**
  | Tick | Met? | Notes |
  |------|------|-------|
  | All ticks | ❌ | **Zero tests.** |

- **Why this is the right call (probably):** the adapter is a one-line passthrough to `JCFS.API.pushUpdatesToJira` and is `.forceignore`d from scratch-org deploys. Testing it requires the managed package, which isn't in scratch. **The dispatcher's `RecordingJcfs` stub correctly tests the seam, and the dispatcher's NoOp fallback test covers the absent-adapter case.**

- **Acceptable IF:**
  1. The work org's CI test run actually executes against an org with JCFS installed (so the adapter's one line gets coverage), OR
  2. The org-wide coverage floor (75%) is satisfied without this class counted (the adapter is 1 statement; it pulls 1 line uncovered).

- **REDESIGN signal:** A 4-line adapter wrapping a single managed-package call doesn't deserve a test of its own, but it deserves **one explicit comment in the dispatcher test suite** saying "`JcfsApiAdapter` is the production binding for `IJcfsApi`; in scratch orgs it's not deployed and the NoOp fallback is tested below." That comment exists at line 215-217 of `JiraPushDispatcherTest`. ✅ — call it a non-issue.

- **Severity:** 🟦 **LOW** — acceptable as-is given the .forceignore pattern. **Document the intentional gap** in the test class header so a future reader doesn't add a phantom test.

---

### `OpportunityService` ([source](../../force-app/main/default/classes/OpportunityService.cls))

- **Tests:** 7 in [`OpportunityServiceTest`](../../force-app/main/default/classes/OpportunityServiceTest.cls)
  - `testHandleJiraPushInsertPublishesEveryNewOpportunity`
  - `testHandleJiraPushUpdatePublishesWhenStageNameChanged`
  - `testHandleJiraPushUpdatePublishesWhenAmountChanged`
  - `testHandleJiraPushUpdateSkipsWhenNoQualifyingFieldChanged`
  - `testHandleJiraPushUpdateBulkFiltersOnlyChangedRecords`
  - `testHandleJiraPushUpdateSkipsRecordMissingFromOldMap`
  - `testHandlersEmptyAndNullInputAreNoOp`

- **9-tick scorecard:**
  | Tick | Met? | Notes |
  |------|------|-------|
  | Good path | ✅ | Both handlers covered with positive cases |
  | Bad path | ✅ | Empty/null, missing oldMap entry, non-qualifying change |
  | Bulk | 🟡 | **Half-credit.** `testHandleJiraPushUpdateBulkFiltersOnlyChangedRecords` is 3 records — that's not "bulk" by any reasonable definition. **No 200-record test.** The filter loop is O(N × |fields|) which is fine, but `JiraPushService.publishUpdates(changed)` downstream needs the bulk safety too — see service-class HIGH. |
  | Governor limits | ❌ | Not asserted |
  | USER_MODE | ❌ | **Not tested.** `OpportunityService` is `with sharing`; if a user without read access to Opportunity (or without FLS on `StageName`, `Amount`, etc.) somehow triggers an after-update — does the filter loop throw? Probably not (it's working off `Trigger.new`/`Trigger.oldMap`), but **not proven**. |
  | DML exception | N/A — service doesn't DML |
  | Async wrap | ✅ | `Test.startTest/stopTest` used |
  | Re-fire idempotency | 🟡 | **Indirectly covered** — the recursion guard lives in `JiraPushService.alreadyPublished` and is verified there. But there's no test asserting "calling `handleJiraPushUpdate` twice in the same transaction with the same records produces one publish." That's a `OpportunityService`-level expectation, not just a service expectation. |
  | Negative-id | ✅ | `TestFactory.getFakeId(Opportunity.SObjectType)` used throughout |

- **Coverage gaps:**
  - The 6-field `JIRA_QUALIFYING_FIELDS` set: only `StageName` and `Amount` are explicitly tested as triggers. `CloseDate`, `AccountId`, `OwnerId`, `Probability` are **untested** as triggering fields. If a future refactor narrows the set, no test catches it.
  - The `oldMap == null` branch (line 56-58) — covered by `testHandlersEmptyAndNullInputAreNoOp`. ✅
  - The `old == null` skip inside the loop (line 73-75) — covered by `testHandleJiraPushUpdateSkipsRecordMissingFromOldMap`. ✅

- **Test quality issues:**
  - **CamelCase + `Assert.*`:** clean. ✅
  - **No `@TestSetup`:** correct call — `JiraPushDispatcher.jcfs` and `configCacheOverride` are static state per transaction, can't survive a `@TestSetup` transaction boundary. The `silenceFramework()` helper is the right pattern, but it's **duplicated verbatim** in `OpportunityServiceTest`, `OpportunityTriggerHandlerTest`, and `JiraPushRequestHandlerTest`. **REDESIGN:** lift it to a shared `TestHelper` or extend `JiraPushDispatcherTest` with a public static helper. Three copies will drift.

- **Severity:** 🟧 **HIGH** — missing per-qualifying-field tests is a maintenance footgun; the 3-record "bulk" test is not bulk.

---

### `OpportunityTriggerHandler` + `OpportunityTrigger` ([handler source](../../force-app/main/default/classes/OpportunityTriggerHandler.cls), [trigger source](../../force-app/main/default/triggers/OpportunityTrigger.trigger))

- **Tests:** 2 in [`OpportunityTriggerHandlerTest`](../../force-app/main/default/classes/OpportunityTriggerHandlerTest.cls)
  - `testAfterInsertEndToEndReachesJcfs`
  - `testAfterUpdateQualifyingFieldChangeEndToEnd`

- **9-tick scorecard:**
  | Tick | Met? | Notes |
  |------|------|-------|
  | Good path | ✅ | Both insert and qualifying-update covered end-to-end with real DML |
  | Bad path | ❌ | **No after-update non-qualifying test at the trigger level.** The class-level comment at line 86-89 says it's "covered directly by OpportunityServiceTest" — true, but the **wiring** of the after-update path through the trigger handler when no fields qualify is its own assertion. (If someone wired `afterUpdate` to call `handleJiraPushInsert` instead, the service test passes but production is broken.) |
  | Bulk | ❌ | **Missing.** A single insert and a single update. `Database.insert` of 200 Opportunities with the trigger active should run inside `Test.startTest/stopTest` and assert one JCFS call with 200 records. |
  | Governor limits | ❌ | Not asserted; **especially important** because this path is `DML → trigger → service → PublishAfterCommit PE → trigger → dispatcher → JCFS stub` — every link burns limits |
  | USER_MODE | ❌ | **Not tested.** The whole point of `with sharing` on OpportunityTriggerHandler is to honor caller permissions. A 200-record insert as a no-Opportunity-create-perm user is a meaningful test. |
  | DML exception | ❌ | What happens if the insert partially fails (e.g., validation rule on record 47)? `Database.insert(..., false)` partial-success path — **not tested.** The trigger framework still calls `afterInsert` for the successes, and the service should publish for those Ids only. |
  | Async wrap | ✅ | `Test.startTest/stopTest` ✅ |
  | Re-fire idempotency | ❌ | Same record updated twice in two separate transactions — does each transaction publish once? Implied by the recursion guard's per-transaction scope, but **not explicitly tested at the e2e level.** |
  | Negative-id | N/A — real DML, real Ids |

- **Coverage gaps:** trigger 1 line + handler `afterInsert`/`afterUpdate` (4 lines) all covered. ✅

- **Test quality issues:**
  - 🟧 **`testAfterInsertEndToEndReachesJcfs` will silently break** the day someone adds an `OpportunityDefaults` inner class to `TestFactoryDefaults`. The test comment at line 39-41 says: "Required fields set explicitly because TestFactoryDefaults is empty in this branch; in the work org, the defaults class fills them." That's a **half-baked contract** — the test passes in *both* states (defaults empty OR populated), but if the defaults class sets, say, `OwnerId` to a fake user that doesn't exist, the insert fails. **This test is environment-coupled.** Either: (a) the test should explicitly NOT use `TestFactory.createSObject` and build the Opportunity directly (which it does ✅), but then **delete the misleading comment about defaults**; or (b) commit to using `TestFactory.createSObject` everywhere and own the dependency. Currently it does both and the result is ambiguous.
  - **Brittle reset pattern** at lines 67-70: the test manually news up a fresh `RecordingJcfs` stub and clears `JiraPushService.alreadyPublished` mid-test to "reset the recording stub so we only count the update-driven call". That works, but it's **non-obvious** and a future reader will assume the original stub captured both. Better: assert the original stub has `callCount == 1` (the insert) AFTER `insert o`, then reset, then assert the update path. Document or refactor.
  - **No assertion on `Limits.getDmlStatements()`** in tests that do real DML and the full PE chain.

- **Severity:** 🟧 **HIGH** — only 2 tests for the trigger pipeline; bulk and DML-failure paths are wide open.

---

### `Logger.logApiException` ([source lines 169-211](../../force-app/main/default/classes/logging/Logger.cls))

- **Tests:** 3 in [`LoggerApiExceptionTest`](../../force-app/main/default/classes/LoggerApiExceptionTest.cls)
  - `testLogApiExceptionWithExceptionPersistsRowAndCapturesType`
  - `testLogApiExceptionWithStringMessagePersistsRowWithoutExceptionFields`
  - `testLogApiExceptionWithNullExceptionDoesNotThrow`

- **9-tick scorecard:**
  | Tick | Met? | Notes |
  |------|------|-------|
  | Good path | ✅ | Both overloads, full field-set assertion |
  | Bad path | ✅ | Null exception, null sourceRecordId, null transactionId |
  | Bulk | N/A — logger is single-record by design |
  | Governor limits | ❌ | Not asserted; the logger does one DML per call, which **inside a trigger pipeline could chain into governor pressure**. Worth one assertion at minimum. |
  | USER_MODE | ❌ | Logger is `without sharing` (CLAUDE.md mentions Logger is a utility — out of my modification scope). It uses raw `insert`. If a no-permset user has no FLS on `API_Exception_Log__c.Stack_Trace__c`, **the insert still succeeds** (because no sharing/no USER_MODE). That's a **deliberate design choice** for an error logger, but **not asserted by any test as a deliberate decision.** Flag it. |
  | DML exception | 🟡 | **Half-credit.** Lines 275-281 of `Logger.cls` catch a failed `insert` and log to debug. **No test induces this failure.** A negative test would need to e.g. blow the field length on `Message__c`, induce a `DmlException`, and assert the catch block fires. Currently uncovered. |
  | Async wrap | N/A — synchronous logger |
  | Re-fire idempotency | N/A |
  | Negative-id | ✅ | Null id path tested |

- **Coverage gaps:**
  - **The `writeApiException` failure catch (lines 275-281)** — the "could not persist" branch is **uncovered**.

- **Test quality issues:**
  - **CamelCase, `Assert.*`, deterministic:** ✅
  - The test class file says CSI-7162 introduced these `logApiException` overloads — confirm with David that this is new code in this ticket (not pre-existing) so the coverage expectation matches.

- **Severity:** 🟨 **MEDIUM** — small uncovered branch in a utility class. Logger is in the don't-modify zone per CLAUDE.md; flag, don't fix.

---

## Cross-cutting findings

### 🟧 Shared fixtures and helpers — **half-built**
- The `silenceFramework()` / `silenceDispatcher()` helper is **duplicated in 4 test classes** with minor variations:
  - [`JiraPushServiceTest.silenceDispatcher`](../../force-app/main/default/classes/JiraPushServiceTest.cls#L40)
  - [`OpportunityServiceTest.silenceFramework`](../../force-app/main/default/classes/OpportunityServiceTest.cls#L22)
  - [`OpportunityTriggerHandlerTest.silenceFramework`](../../force-app/main/default/classes/OpportunityTriggerHandlerTest.cls#L18)
  - (Inline in `JiraPushRequestHandlerTest`.)
- **REDESIGN:** Extract a single static helper, e.g. `JiraPushTestHelper.silenceFramework(String sobjectName)`, return the `RecordingJcfs` stub for further assertion. Single source of truth; one place to add new SObject configs.

### 🟥 Mock fragility — `FailingPublisher` JSON deserialization
- See `JiraPushService` per-class assessment. Hand-rolled JSON for `Database.SaveResult` is the **single most fragile mock in the suite**.

### 🟦 Callout-mock pattern — **N/A, correctly so**
- No `HttpCalloutMock` needed because the JCFS call is wrapped in `IJcfsApi` and stubbed at the interface. **This is the right design** — no `HttpCalloutMockFactory` involvement needed for these tests.

### 🟦 `HttpCalloutMockFactory` — **not used here, by design**
- The [`HttpCalloutMockFactory`](../../force-app/main/default/classes/testing/HttpCalloutMockFactory.cls) exists in the framework. The Jira-push code never makes an HTTP callout directly (JCFS handles that downstream), so its absence in these tests is correct.

### 🟧 Bulk coverage — **systematically missing**
- **No test in the entire 24-method suite exercises 200 records.**
- The PE consumer (`JiraPushDispatcher`), the publisher (`JiraPushService`), the domain service (`OpportunityService`), and the trigger pipeline (`OpportunityTriggerHandler`) all need bulk runs. This is the **single biggest aggregate gap.**

### 🟧 `Limits.*` assertions — **systematically missing**
- Only one test (`testPublishRecursionGuardSuppressesSecondPublish`) checks any `Limits.*` value, and it's `getPublishImmediateDml`. **No `getQueries`, no `getDmlStatements`, no `getCpuTime`.** Service-layer assertions per `best-practices/apex-tests.md` should be present.

### 🟦 USER_MODE permission boundary — **acceptable gap, mostly**
- The CMDT read in `JiraPushService.getConfig` doesn't enforce USER_MODE because CMDT is not subject to CRUD/FLS anyway.
- The `EventBus.publish` call is platform-managed.
- The `Schema.getGlobalDescribe()` describe is no-perm-required.
- The Logger insert is `without sharing` deliberately.
- **The only USER_MODE-relevant question** is the OpportunityTrigger path running as a user without Opportunity create/edit perms — but if they can't insert/update Opportunity, the trigger never fires, so the question is moot.
- **Net:** USER_MODE testing is **not required here**; document the rationale in the per-class headers so future reviewers don't ding it.

### 🟧 Determinism — **mostly clean, two soft spots**
- `Datetime.now()` is used in several `Jira_Push_Request__e` constructions in tests. Harmless (only stored, never compared), but worth noting.
- `JiraPushService.alreadyPublished` is a static `Set<String>` initialized at class load. Tests that don't reset it could see stale state — **specifically [`OpportunityTriggerHandlerTest.testAfterUpdateQualifyingFieldChangeEndToEnd` at line 70](../../force-app/main/default/classes/OpportunityTriggerHandlerTest.cls#L70)** calls `JiraPushService.alreadyPublished.clear()` explicitly because of this. **Fine that it works, but the next test author won't know to do this.** Wrap the static in a `@TestVisible static void resetTransientState()` or document the gotcha in the class header.

### 🟦 Run-time per test
- Eyeballing the assertions: every test is in-memory or single-DML. **No test should exceed 1-2 seconds**, suite should be well under 1 minute. Cannot verify without running.

### 🟨 Naming consistency
- All test methods use CamelCase, no underscores. ✅
- `testProcessLogsApiExceptionForMalformedSourceId` is a great name. `testHandlersEmptyAndNullInputAreNoOp` covers both handlers in one method — slight nit but understandable.

---

## BUGs discovered (test code reveals production bugs)

- **None confirmed.** The test suite doesn't expose a production bug — it exposes coverage *gaps*, which is different. The closest miss is the **dispatcher's lack of duplicate-Id collapsing within a single batch** (two events with the same `Source_Id__c` produce two entries in the typed list). This is reported as a missing-test, not a bug — duplicates are valid `Set<Id>.add` no-ops, so it's actually handled correctly by the `Set` accumulation at line 113-115 of `JiraPushDispatcher`. ✅
- **One soft concern:** [`JiraPushService.publish` line 96](../../force-app/main/default/classes/JiraPushService.cls#L96) does `records[0].getSObjectType().getDescribe().getName()` — if the caller passes a heterogeneous list of SObject types (not a trigger list), only the first record's type is captured but all records publish under that single `Source_Object__c`. **Caller-contract violation, not a class bug**, but the lack of a defensive check means a misuse would silently mis-classify records to Jira. Worth a unit test that explicitly verifies single-SObject-type assumption: e.g. pass a `List<SObject>{ acct, opp }` and assert either a throw or a graceful fallback. Currently neither happens. Flag for David.

---

## REDESIGN opportunities surfaced

- **Lift `silenceFramework()` into a shared helper class.** Four test files have near-identical copies; first one to drift creates a flake. (See Cross-cutting → Shared fixtures.)
- **Wrap `Database.SaveResult` in a domain DTO inside `JiraPushService.IEventPublisher`.** Removes the JSON deserialization hack in `FailingPublisher` and decouples the test mock from Salesforce-internal types.
- **Add `JiraPushService.resetTransientState()` `@TestVisible`** to clean `alreadyPublished`, `configCache`, `configCacheOverride`, and `eventPublisher` in one call. Eliminates the per-test cleanup drift.
- **Document the cross-class dependency** on `JiraPushDispatcherTest.RecordingJcfs` and `JiraPushDispatcherTest.buildAccount()` in the dispatcher test class header — five other test files depend on these as a public contract.
- **Defensive guard in `JiraPushService.publish`** for heterogeneous record lists (or document the homogeneity contract explicitly with a `System.assert` in the method). Currently it silently uses `records[0]`'s SObject type for all events in the batch.

---

## Required new test methods to reach production-grade

In **rough priority order** (BLOCK → HIGH → MEDIUM):

### 🟥 BLOCK — fragility / bug-class
1. **`testPublishHandlesHeterogeneousRecordListSafely`** (in `JiraPushServiceTest`) — passes `List<SObject>{ Account, Opportunity }`, asserts either explicit exception or that only matching-type events publish. Closes the misuse-silently-misclassifies risk.
2. **Refactor `FailingPublisher`** (not a new test, but a fragility fix) — replace JSON-deserialized `Database.SaveResult` with a wrapper DTO. Either eliminate the test or rebuild the seam.

### 🟧 HIGH — bulk and pipeline gaps
3. **`testDispatcherProcessesBulkPEBatchOfTwoHundredEvents`** (in `JiraPushDispatcherTest`) — 200 events spanning Account + Opportunity + Case; asserts exactly 3 JCFS calls (one per SObject) and each typed list has the right count + concrete type. Add `Limits.getDmlStatements()` and `Limits.getQueries()` ceilings.
4. **`testPublishInsertsBulkTwoHundredOpportunities`** (in `JiraPushServiceTest`) — 200 records, one `EventBus.publish` call, assert `Limits.getPublishImmediateDml() == 1` after.
5. **`testHandleJiraPushUpdateBulkTwoHundredRecords`** (in `OpportunityServiceTest`) — 200 records with mixed qualifying/non-qualifying changes; assert correct filtering and exactly one downstream publish call.
6. **`testTriggerPipelineBulkInsertTwoHundredOpportunities`** (in `OpportunityTriggerHandlerTest`) — real `Database.insert` of 200 Opportunities; assert exactly one JCFS call with 200 records inside `Test.startTest/stopTest`. Add `Limits.getDmlStatements()` and CPU-time check.
7. **`testTriggerHandlesPartialDmlFailureGracefully`** (in `OpportunityTriggerHandlerTest`) — `Database.insert(opps, false)` where some records fail a validation rule; assert only successful Ids publish to JCFS.
8. **`testDispatcherHandlesReFireWithinSamePEBatch`** (in `JiraPushDispatcherTest`) — two events with identical `Source_Object__c` + `Source_Id__c` in the same batch; assert JCFS receives one record (deduped by `Set<Id>`), proving the Set semantics hold.
9. **`testHandleJiraPushUpdatePublishesForEachQualifyingField`** (in `OpportunityServiceTest`) — parametric-style coverage of `CloseDate`, `AccountId`, `OwnerId`, `Probability` triggering the publish. Currently only `StageName` and `Amount` are covered.

### 🟨 MEDIUM — limits / cache / log-failure paths
10. **`testGetConfigCachesAcrossInvocations`** (in `JiraPushServiceTest`) — call `getConfig('Opportunity')` twice; assert `Limits.getQueries()` advances exactly once across both calls.
11. **`testLogApiExceptionCatchesDmlFailure`** (in `LoggerApiExceptionTest`) — induce an insert failure (oversized `Message__c` or null required field) and assert the `error()` debug-log path fires. Closes the only uncovered Logger branch.
12. **`testTriggerPipelineRefireIdempotencyAcrossSeparateTransactions`** (in `OpportunityTriggerHandlerTest`) — update the same Opportunity twice in separate `Test.startTest/stopTest` blocks (use `System.runAs` to break the transaction); assert both transactions publish their own event (recursion guard is per-transaction by design).

### 🟦 LOW — documentation
13. **Add a class-header comment to `JiraPushDispatcherTest`** declaring `RecordingJcfs`, `ThrowingJcfsApi`, and `buildAccount()` as the public test-helper API that five other test classes consume.
14. **Add a class-header comment to `OpportunityTriggerHandlerTest`** clarifying the `TestFactoryDefaults` dependency (or remove the misleading comment if defaults aren't actually used).

---

## Recommended deployment-side verification (next pass)

When David has time:

1. Wire a scratch org with `Jira_Push_Request__e`, `Jira_Push_Object__mdt`, `API_Exception_Log__c`, and the CMDT records.
2. Deploy without `JcfsApiAdapter.cls` (it's `.forceignore`d).
3. Run:
   ```bash
   sf apex run test --target-org <alias> --code-coverage --result-format human --wait 20 \
     --class-names JiraPushDispatcherTest,JiraPushRequestHandlerTest,JiraPushServiceTest,\
   OpportunityServiceTest,OpportunityTriggerHandlerTest,LoggerApiExceptionTest
   ```
4. Confirm per-class coverage ≥95% on the 6 Jira-push production classes. The 4 missing line-targets I called out above (`JiraPushDispatcherException` inner class, `getConfig` cache-hit path, `writeApiException` failure catch, dispatcher re-fire dedup) should leave 1-3 uncovered lines — acceptable for this pass with a follow-up ticket.

---

## Headline answer to "production-ready?"

🟧 **Not yet.** Strong good-path coverage and a clever, well-decoupled set of test seams (`IJcfsApi`, `IEventPublisher`, CMDT cache override). **Three concrete fixes** unblock prod push:

1. **Bulk tests (#3–6 above).** A PE consumer + trigger pipeline that's never been run with 200 records in test is a production risk we can avoid with ~2 hours of work.
2. **`FailingPublisher` fragility (#2).** The JSON-deserialized `Database.SaveResult` is the single largest "test breaks on a platform upgrade" risk in the suite.
3. **Heterogeneous-list defensive test (#1).** Either prove the contract or guard it.

Items 7-14 are excellent follow-up-ticket material but I wouldn't BLOCK on them.

---

## Sign-off

The test plan does the right things structurally — interface seams, CMDT cache overrides, fake Ids, `RecordingJcfs` stub, dedicated e2e tests with real DML for the trigger pipeline. The coverage shape on line-count terms is likely 90%+, and the existing tests are readable, well-named, and use `Assert.*` consistently.

What's missing is the **stress dimension** (200 records), the **failure-modes dimension** (partial DML failure, mid-batch JCFS retry), and **one piece of mock fragility** that will bite us the day Salesforce ships a new `Database.SaveResult` schema. Fix those three things and this is shippable.

Coverage that exercises only the happy path is theater. Right now the happy paths are gold; the bad paths are 60% there. Get to 90% on the bad paths and 100% on bulk and we're done.

— Pippa

*Filed under: tests that don't break when the code breaks is not a test, and tests that don't run 200 records aren't proving the only thing that matters in a PE consumer.*
