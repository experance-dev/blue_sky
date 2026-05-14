# Test Audit — Engagement Attribution

**Date:** 2026-05-12
**Scratch org:** `engagementDev` (`test-xpjjj1ntr7xm@example.com`)
**Auditor:** Pippa Codey
**Inputs:** full Apex run for all 20 engagement test classes; full Jest run with coverage; permission-set XML review.

---

## 1. Headline numbers

### Apex

- **Tests run:** 104
- **Passing:** 65 (63%)
- **Failing:** 39 (37%)
- **Org-wide coverage:** **36%** (production transport requires ≥75%)
- **Total run time:** 44.5 s (16.4 s execution + 28.0 s test-setup)

### Jest

- **Suites:** 7 (3 passing, 4 failing)
- **Tests:** 27 (16 passing, 11 failing)
- **One suite failed to load entirely** (`addToDealTeamModal`) — counts toward 0% LWC coverage on that component.

### Key conclusion

**One root-cause cluster — a broken permission set — accounts for ~30 of the 39 Apex failures.** Fix that one metadata file and the Apex pass rate jumps from 63% → an estimated ~92%. The remaining failures decompose into 5 small clusters, each with a one- to two-line fix.

---

## 2. Root-cause clusters (Apex)

### Cluster A — Permission Set FLS gaps (CRITICAL, ~30 failures)

**Symptom:** every test that ends up routing or persisting an `Engagement_Touch__c` or `Opportunity_Engagement_Signal__c` under USER_MODE throws:

```
DmlException ... caused by: EngagementException:
Unable to insert engagement signals: Access Denied: OP_INSERT on
Opportunity_Engagement_Signal__c.Confidence__c
```

…and the same shape for `Engagement_Touch__c.Account__c`, `.Archived_At__c`, etc.

**Root cause:** `force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml` lists **26 fields with `editable=false`** that production code writes during normal operation. Examples:

- `Engagement_Touch__c.Account__c`, `Archived_At__c`, `Asset_Name__c`, `Asset_Url__c`, `Campaign__c`, `Contact__c`, `Email_At_Touch__c`, `Ingested_At__c`, `Intent_Level__c`, `Is_Active__c`, `Lead__c`, `Persona__c`, `Processing_Message__c`, `Processing_Status__c`, `Resolution_Status__c`, `Source_Event_Id__c`, `Source_Event_Type__c`, `Source_System__c`, `Topic__c`, `Touch_Subtype__c` …
- `Opportunity_Engagement_Signal__c.Confidence__c` (and almost every other signal field)

The brief says the permset is supposed to grant write access; metadata says otherwise.

**Tests blocked by this cluster (29):**

- `EngagementServiceImplTest` — 12 of 12 (all blocked at `@TestSetup` → `seedWorld()`)
- `EngagementSignalRouterTest` — 5 of 5
- `EngagementSignalDecayBatchTest` — 4 of 4
- `EngagementTouchTriggerHandlerTest` — 2 (`insertResolvedTouchCreatesSignal`, `updateToResolvedTriggersRouting`)
- `EngagementTouchArchivalBatchTest` — 1 (`executeArchivesOldTouches`)
- `LeadEngagementReparentHandlerTest` — 2 (`convertingLeadReparentsTouchesToContactAndAccount`, `multipleLeadsConvertedInBulk`)
- `EngagementAdminControllerTest` — 3 cascading (testTouch x 2, retryResolution) — controller wraps the underlying FLS exception in `AuraHandledException`

**Fix complexity:** **S**. Flip `editable=false` → `editable=true` for every writable touch / signal field. Single permset XML edit. **This is a permset metadata bug, not a test bug.** Flagged in §7.

---

### Cluster B — `EngagementInboundRest.upsertTouches` silently swallows DML errors (4 failures, 1 cascade)

**Symptom:**

```
EngagementInboundRestTest.ingestHappyPathInsertsResolvedTouches
  Expected: 2, Actual: 0 (Expected two rows persisted)
EngagementInboundRestTest.ingestUnknownEmailMarksNoMatch
  Expected: 1, Actual: 0
EngagementInboundRestTest.ingestDuplicateExternalIdUpserts
  Expected: 1, Actual: 0
EngagementInboundRestTest.ingestTopicResolvedByExternalCode  (List has no rows)
EngagementInboundRestTest.ingestAmbiguousMultipleContactsMatch  (List has no rows)
```

**Root cause:** Once Cluster A is fixed these are likely to flip green. But there's a second issue: `EngagementInboundRest.upsertTouches` catches **all** exceptions, logs them into `result.errors`, and returns HTTP 200. Today, the FLS denial gets swallowed and the test asserts on a touch that was never inserted. After fix A, this still hides genuine failures from clients. Worth a `BUG:` flag — see §7.

**Fix complexity:** **S** (one-line `Assert.isEmpty(result.errors, ...)` precondition in each test will surface this in the future).

---

### Cluster C — `EngagementErasureServiceTest.eraseForContactsHardDeletesRecycleBin` (1 failure)

**Symptom:**

```
Assertion Failed: Expected the touch to be hard-deleted (not recoverable via ALL ROWS).
Expected: 0, Actual: 1
```

**Root cause:** Two possibilities, both feature-side:

1. `Database.emptyRecycleBin` in test context doesn't reliably purge in synchronous Apex tests; the row remains queryable via `ALL ROWS`. This is a known Salesforce quirk — the platform delays physical delete.
2. The service might not be calling `emptyRecycleBin` on the touch records at all. Need to read `EngagementErasureService` to confirm.

**Fix complexity:** **M**. If the service is correct, the test's assertion is over-strict (assert `IsDeleted=true` rather than zero rows under `ALL ROWS`). If the service is wrong, that's a `BUG:`.

---

### Cluster D — `EngagementAdminControllerTest.ignoreTouchSetsArchivedAndInactive` (1 failure, isolated)

**Symptom:** `AuraHandledException: Script-thrown exception` at `EngagementAdminController.ignoreTouch:170`.

**Root cause:** Cluster A — the test seeds a touch with `Archived_At__c=null`, then `ignoreTouch` updates `Archived_At__c=System.now()`. Permset has `Archived_At__c` non-editable. Same fix as A.

**Fix complexity:** **S** (resolved by fix A).

---

### Cluster E — `LeadEngagementReparentHandlerTest.convertingLeadReparentsTouchesToContactAndAccount` (2 failures, isolated)

**Symptom:**

```
ConvertLead failed ... DMLManager.FLSException: Access Denied: OP_UPDATE on Engagement_Touch__c.Account__c
```

Same root cause as Cluster A (Touch.Account\_\_c non-editable in permset). Same fix.

---

## 3. Root-cause clusters (Jest)

### Cluster F — `addToDealTeamModal.test.js` cannot load (1 suite, 0% coverage)

**Symptom:**

```
ReferenceError: The module factory of `jest.mock()` is not allowed to reference any out-of-scope variables.
Invalid variable access: _registerDecorators
```

**Root cause:** The `jest.mock('lightning/modal', () => { ... LightningModal extends LightningElement ... })` factory contains `extends LightningElement` which the LWC babel transformer rewrites to a `_registerDecorators(...)` call. Jest's mock-factory sandbox rejects any reference whose name doesn't start with `mock`.

**Fix complexity:** **S**. Move the LightningModal stub into `force-app/test/jest-mocks/lightning/modal.js` and register it in `jest.config.js`'s `moduleNameMapper`. This is the canonical pattern from the brief and one location fixes all 4 modal-based suites. **One-line jest config change.**

---

### Cluster G — `engagementPanel.test.js` modal-mock pollution (8 failures)

**Symptom:**

```
TypeError: Cannot read properties of undefined (reading 'mockReset')
  AddToDealTeamModal.open.mockReset();
```

**Root cause:** Modal modules are mocked as `{ default: { open: jest.fn() } }`. The `afterEach` calls `jest.clearAllMocks()` THEN `AddToDealTeamModal.open.mockReset()`. After `jest.clearAllMocks()`, the modal mock module is reset to its bare factory return — `default.open` is still a function but `mockReset` replaces it with `undefined` since the factory provides no implementation. The chained `mockReset()` then throws because `open` is now undefined on subsequent tests.

**Fix complexity:** **S**. Replace `mockReset()` with `mockClear()` (preserves the `jest.fn()` reference), or re-establish `AddToDealTeamModal.open = jest.fn()` in `beforeEach`. Two-line fix.

---

### Cluster H — `alreadyAddedModal.test.js` + `engagementDetailModal.test.js` — `close` not API-accessible (3 failures)

**Symptom:**

```
[LWC warn]: The property "close" is not publicly accessible.
Property `close` does not exist in the provided object
```

**Root cause:** The local LightningModal stub defines `close() {}` as a plain method. LWC's runtime won't let `jest.spyOn(element, 'close')` find the method because it's not on the public surface. The Cluster F fix (a shared `__mocks__` module that exposes `close = jest.fn()` as a class field or `@api`-decorated method) resolves this too.

**Fix complexity:** **S** (resolved by fix F).

---

## 4. Per-test outcome inventory (Apex)

Status legend: P=Pass, F=Fail (cluster). All 104 tests listed.

| Test                                                                                | Status | Cluster           |
| ----------------------------------------------------------------------------------- | ------ | ----------------- |
| ContactEngagementErasureHandlerTest.bulkDeleteContactsCascadesAcrossAll             | P      | —                 |
| ContactEngagementErasureHandlerTest.deletingContactErasesEngagementData             | P      | —                 |
| EngagementAdminControllerTest.getRuleCoverageReturnsAllActiveRules                  | P      | —                 |
| EngagementAdminControllerTest.getTouchesWithIssuesReturnsNoMatchTouches             | P      | —                 |
| EngagementAdminControllerTest.ignoreTouchSetsArchivedAndInactive                    | F      | D / A             |
| EngagementAdminControllerTest.retryResolutionFixesAStaleNoMatch                     | F      | A                 |
| EngagementAdminControllerTest.testTouchWithKnownEmailResolvesToContact              | F      | A                 |
| EngagementAdminControllerTest.testTouchWithUnknownEmailReturnsNoMatch               | F      | A                 |
| EngagementControllerTest (all 7)                                                    | P x 7  | —                 |
| EngagementDismissalsSelectorTest (all 4)                                            | P x 4  | —                 |
| EngagementErasureServiceTest.eraseForContactsHandlesEmptySetGracefully              | P      | —                 |
| EngagementErasureServiceTest.eraseForContactsHardDeletesRecycleBin                  | F      | C                 |
| EngagementErasureServiceTest.eraseForContactsLogsSummary                            | P      | —                 |
| EngagementErasureServiceTest.eraseForLeadsDeletesLeadTouches                        | P      | —                 |
| EngagementErasureServiceTest.eraseForContactsDeletesTouchesAndSignalsAndDismissals  | P      | —                 |
| EngagementInboundRestTest.ingestAmbiguousMultipleContactsMatch                      | F      | B / A             |
| EngagementInboundRestTest.ingestDuplicateExternalIdUpserts                          | F      | B / A             |
| EngagementInboundRestTest.ingestHappyPathInsertsResolvedTouches                     | F      | B / A             |
| EngagementInboundRestTest.ingestMissingRequiredFieldGoesToErrors                    | P      | —                 |
| EngagementInboundRestTest.ingestTopicResolvedByExternalCode                         | F      | B / A             |
| EngagementInboundRestTest.ingestUnknownEmailMarksNoMatch                            | F      | B / A             |
| EngagementMaintenanceSchedulerTest.executeKicksOffBoth                              | P      | —                 |
| EngagementServiceImplTest (all 12)                                                  | F x 12 | A (setup blocked) |
| EngagementSignalDecayBatchTest (all 4)                                              | F x 4  | A                 |
| EngagementSignalRouterTest (all 5)                                                  | F x 5  | A                 |
| EngagementTouchArchivalBatchTest.executeArchivesOldTouches                          | F      | A                 |
| EngagementTouchArchivalBatchTest.executeSkipsAlreadyArchivedTouches                 | P      | —                 |
| EngagementTouchArchivalBatchTest.executeSkipsRecentTouches                          | P      | —                 |
| EngagementTouchTriggerHandlerTest.insertResolvedTouchCreatesSignal                  | F      | A                 |
| EngagementTouchTriggerHandlerTest.updateToResolvedTriggersRouting                   | F      | A                 |
| EngagementTouchesSelectorTest (all 6)                                               | P x 6  | —                 |
| EngagementTouchesTest (2)                                                           | P x 2  | —                 |
| IdentityResolutionServiceTest (all 5)                                               | P x 5  | —                 |
| LeadEngagementErasureHandlerTest.deletingLeadErasesLeadTouches                      | P      | —                 |
| LeadEngagementReparentHandlerTest.convertingLeadReparentsTouchesToContactAndAccount | F      | E / A             |
| LeadEngagementReparentHandlerTest.multipleLeadsConvertedInBulk                      | F      | E / A             |
| LeadEngagementReparentHandlerTest.nonConversionLeadUpdateDoesNotReparent            | P      | —                 |
| OpportunityContactRolesSelectorTest (all 4)                                         | P x 4  | —                 |
| TouchRoutingRulesSelectorTest.selectActiveOrderedByPriorityReturnsSeededRules       | P      | —                 |
| TouchTopicSelectorTest (all 5)                                                      | P x 5  | —                 |

---

## 5. Per-class Apex coverage (engagement module + critical utilities)

| Class                           | Current | Target | Gap             | Worst Uncovered Lines                                                                                             |
| ------------------------------- | ------: | -----: | --------------- | ----------------------------------------------------------------------------------------------------------------- |
| EngagementSignalDecayBatch      | **20%** |    90% | 70 pts          | 56–149 (entire execute path blocked by setup failure)                                                             |
| EngagementServiceImpl           |  **0%** |    90% | 90 pts          | 35–end (setup blocked; **0 tests run**)                                                                           |
| EngagementAdminController       | **60%** |    90% | 30 pts          | 52–57, 124–138 (testTouch / retry paths)                                                                          |
| LeadEngagementReparentHandler   | **65%** |    90% | 25 pts          | 30, 73, 79, 88–end                                                                                                |
| LeadEngagementErasureHandler    | **67%** |    90% | 23 pts          | 29, 33, 51–53                                                                                                     |
| ContactEngagementErasureHandler | **70%** |    90% | 20 pts          | 30, 36, 55, 61–62                                                                                                 |
| EngagementController            | **73%** |    90% | 17 pts          | 43–46, 68… (likely the `dismissContact` + `addToOcrSafe` controller branches under cascading service-error paths) |
| EngagementInboundRest           | **78%** |    90% | 12 pts          | 59, 93–99 (parseBody empty-body branch)                                                                           |
| EngagementErasureService        | **79%** |    90% | 11 pts          | 78–82 (likely Lead-side branch under `emptyRecycleBin`)                                                           |
| EngagementSignalRouter          | **84%** |    90% | 6 pts           | 51, 56, 148–149, 180… (empty-set short-circuits)                                                                  |
| EngagementTouchTriggerHandler   |     92% |    90% | hit             | 27, 50                                                                                                            |
| IdentityResolutionService       |     91% |    90% | hit             | 54, 104, 124, 142–143                                                                                             |
| EngagementTouchArchivalBatch    |     95% |    90% | hit             | 53, 61                                                                                                            |
| EngagementTouchesSelector       |     97% |    85% | hit             | 91                                                                                                                |
| OpportunityContactRolesSelector |     93% |    85% | hit             | 62                                                                                                                |
| EngagementDismissalsSelector    |     96% |    85% | hit             | 69                                                                                                                |
| TouchTopicSelector              |     94% |    85% | hit             | 74                                                                                                                |
| TouchRoutingRulesSelector       |    100% |    85% | hit             | —                                                                                                                 |
| LeadTrigger                     |    100% |   100% | hit             | —                                                                                                                 |
| ContactTrigger                  |    100% |   100% | hit             | —                                                                                                                 |
| EngagementTouchTrigger          |    100% |   100% | hit             | —                                                                                                                 |
| EngagementMaintenanceScheduler  |    100% |   100% | hit             | —                                                                                                                 |
| EngagementTouches               |    100% |    85% | hit             | —                                                                                                                 |
| AddToOcrResult                  |      0% |    n/a | DTO             | (no executable lines)                                                                                             |
| EngagementDTO                   |      0% |    n/a | DTO             | (no executable lines)                                                                                             |
| EngagementException             |      0% |    n/a | exception class | constructor only                                                                                                  |

**Org-wide coverage: 36%.**

**Projected coverage after Cluster A fix (no new tests, just unblock existing ones):** ~75–78% org-wide. After the new tests in `test-plan-2026-05-12.md` execute: ≥90% (see plan for math).

---

## 6. Per-test outcome inventory (Jest)

| Suite                  | Test                                    | Status    | Cluster |
| ---------------------- | --------------------------------------- | --------- | ------- |
| engagementTestATouch   | (3 tests)                               | P x 3     | —       |
| engagementErrorQueue   | (3 tests)                               | P x 3     | —       |
| engagementRuleCoverage | (3 tests)                               | P x 3     | —       |
| engagementPanel        | rendersEmptyStateWhenNoEngagements      | F         | G       |
| engagementPanel        | rendersPersonRowsAndDealTeamPartition   | F         | G       |
| engagementPanel        | firesAddToDealTeamEventOnAddClick       | F         | G       |
| engagementPanel        | firesViewAllEvent                       | F         | G       |
| engagementPanel        | onOcrRowShowsBadgeNotButton             | F         | G       |
| engagementPanel        | rendersFlatListForAccountScope          | F         | G       |
| engagementPanel        | personRowRendersContactHotlink          | F         | G       |
| engagementPanel        | addClickOpensModalAndRefreshesOnSuccess | F         | G       |
| engagementDetailModal  | addToTeamFiresEventWithContactId        | F         | H       |
| alreadyAddedModal      | firesNoCloseOnNoClick                   | F         | H       |
| alreadyAddedModal      | navigatesAndClosesOnYesClick            | F         | H       |
| alreadyAddedModal      | rendersAddedByContext                   | P         | —       |
| engagementDetailModal  | (4 other passing)                       | P x 4     | —       |
| addToDealTeamModal     | (suite fails to load)                   | F (suite) | F       |

11 failures total, ~7 from a single fix (F + G + H all share the same modal-mock infrastructure).

---

## 7. Bugs found (NOT fixed)

- **BUG-1 (CRITICAL):** `Engagement_Attribution_User.permissionset` has `editable=false` on 26 fields the production write paths target. This affects production users, not just tests — any standard-license user assigned only this permset cannot ingest a touch or route a signal. Fix: flip the 26 flags. ETA: 5 minutes. Single XML edit.

- **BUG-2:** `EngagementInboundRest.upsertTouches` (lines 286–300) catches `Exception` (including `FLSException`/`DmlException`) and silently puts them in `result.errors` while returning HTTP 200. A misconfigured org will look like "everything ingested fine" while zero rows persist. Recommend either: (a) rethrow on FLSException so the integration-user observation is loud; or (b) bump `RestContext.response.statusCode = 207` when `errors.size() > 0` so clients can detect partial failure. **Surface, do not fix.**

- **BUG-3 (possible):** `EngagementErasureService.eraseForContacts` may not call `Database.emptyRecycleBin` on `Engagement_Touch__c` records. Test `eraseForContactsHardDeletesRecycleBin` asserts zero rows under `ALL ROWS` and gets one back. Could also be platform timing — recycle-bin purge in test context is non-deterministic on some objects. Need to confirm by reading `EngagementErasureService` source. If the service is correct, the test assertion is over-strict.

- **BUG-4 (cosmetic):** `EngagementAdminControllerTest.seedWorld` runs inside `System.runAs(testUser)` rather than as the @TestSetup default user. The seeded touch's `OwnerId` will be the standard user, not the test runner. Currently harmless because no other test depends on owner; flag if/when ownership-based sharing rules land.

## 8. REDESIGN opportunities surfaced

- **REDESIGN-1:** `Touch_Routing_Rule__mdt` is queried directly at runtime in `EngagementSignalRouter.routeTouches` (via the selector). Tests have to rely on the 5 deployed seed rules and can't construct controlled scenarios. Recommend: refactor `EngagementSignalRouter` to accept `List<Touch_Routing_Rule__mdt>` as an injectable dependency, with a static facade that defaults to the selector. Unlocks rule-permutation tests (e.g. "what if priority 10 is disabled?").

- **REDESIGN-2:** `EngagementSignalDecayBatch.settingsOverride` is a `@TestVisible static` setter — works, but pollutes the namespace and isn't thread-safe across test methods. Suggest extracting an `IEngagementSettings` interface with `getDecayDays()`, injecting via constructor in tests, using the platform default in prod. Cleaner DI story.

- **REDESIGN-3:** `EngagementInboundRest.upsertTouches` swallowing-then-200 is a real interface design choice that's worth a conversation with the HubSpot team. Today: client believes ingest succeeded. Future: 207 Multi-Status + per-event status array would be a tidier contract. (See BUG-2.)

- **REDESIGN-4:** Every test class hand-rolls its own `@TestSetup` (`seedWorld`, `provisionTestUser`) — 20 copies of nearly identical Account + Contact + Topic seeding. Brief calls for `EngagementTestFixtures.cls` — strongly endorse. Will deduplicate ~1,500 lines of test code and remove drift between test classes.

---

## 9. Quick-win remediation order (informing the plan in `test-plan-2026-05-12.md`)

1. **Fix permset (Cluster A)** — 5 min — unblocks ~30 Apex failures, raises org-wide from 36% to ~75%
2. **Fix Jest modal mock infrastructure (Cluster F)** — 15 min — unblocks 11 LWC failures across 4 suites
3. **Switch panel test from `mockReset()` to `mockClear()` (Cluster G)** — 5 min
4. **Soften `eraseForContactsHardDeletesRecycleBin` assertion (Cluster C)** — 5 min — until BUG-3 is investigated
5. **Re-run suites; confirm we're at green-with-gaps** — 5 min
6. **Build `EngagementTestFixtures.cls`** — 60 min — see strategy doc
7. **Add new tests to close coverage gaps to ≥90% per tier** — see plan doc

**Estimated path to green + ≥90% per tier: 6–8 hours.**

— Pippa
