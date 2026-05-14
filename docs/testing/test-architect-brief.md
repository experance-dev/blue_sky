# Salesforce Test Architect — Engagement Attribution Test Suite

## Your role

You are a senior Salesforce test architect. This is a code-review + test-strategy engagement on an in-progress feature. Your job:

1. Audit the current Apex + LWC test suite
2. Identify gaps (coverage, missing scenarios, brittle tests, anti-patterns)
3. Design and implement a complete, durable test suite that gets the codebase to production-deployable state (≥80% org-wide coverage, zero failures, deterministic, bulkified, USER_MODE-enforced)
4. Hand back an all-green pass with a strategy doc

You report to **David Wood**, Zelis Salesforce Technical Architect (20+ years, 8 certs). Skip foundational Salesforce/SFDX/Apex explanations. He's a senior peer.

---

## Where everything lives

**Worktree:** `/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/`

SFDX project on branch `feature/engagement-attribution`. Scratch org alias `engagementDev` is live (Dev Hub: `ExperanceProd` / `david@experancepartners.com`) with seeded United Healthcare demo data.

**Read in this order to orient (the only docs you need before designing):**

1. `docs/PHASE1-HANDOFF.md` — architecture, scope phases, object schema, DTO contract
2. `docs/DEMO.md` — what works end-to-end, the 4-beat demo flow, deploy/seed runbook
3. `best-practices/apex.md` — `with sharing`, `WITH USER_MODE`, DML via `DMLManager`, errors via `Logger`
4. `best-practices/apex-tests.md` — **canonical test conventions** — `Assert.*` not `System.assertEquals`, CamelCase test names (no underscores), `@TestSetup`, `Utilities.getFakeId` for negative paths, `System.runAs`
5. `best-practices/lwc.md` — Jest patterns, wire adapters, Apex mocking
6. `best-practices/architecture.md` — Selector/Service/Domain layering, Trigger framework, bulkification rules, SOQL safety, custom-metadata over custom-settings

---

## The feature in one paragraph

Engagement Attribution surfaces buying-committee engagement on Account + Opportunity record pages. Touches arrive from HubSpot via inbound REST → identity resolution matches Contact/Lead by email → CMT-driven routing rules generate `Opportunity_Engagement_Signal__c` records → a Lightning panel renders engaged people grouped by Deal-Team membership. Sales reps can `+ Add` non-OCR contacts to OCR with race protection, dismiss noise, view a vertical buying-motion timeline. Admins have Test-a-Touch / Rule Coverage / Error Queue LWCs. Weekly batches decay signals and archive old touches. Contact/Lead delete cascades the erasure for CCPA/GDPR.

---

## What's been built — phase by phase

### Phase 1 — Core panel + service layer

**Objects:** `Engagement_Touch__c` (23 fields), `Touch_Topic__c`, `Opportunity_Engagement_Signal__c`, `Engagement_Settings__c` (Hierarchy CS), `Engagement_Dismissal__c`, `Log_Setting__mdt` (CMT for Logger).
Plus extensions: `Opportunity.Touch_Topic__c` lookup.

**Apex (all in `force-app/main/default/classes/engagement/`):**

- `EngagementController` (LWC-facing, 4 `@AuraEnabled` methods)
- `IEngagementService` / `EngagementServiceImpl` (~588 lines; getForOpportunity, getForAccount, addToOcrSafe with race-protected re-check, dismissContact, dismissSignal)
- Selectors: `EngagementTouchesSelector`, `OpportunityContactRolesSelector`, `TouchTopicSelector`, `EngagementDismissalsSelector`
- Domain: `EngagementTouches` (skeleton)
- DTOs: `EngagementDTO` (with nested `AssetEngagement`), `AddToOcrResult`
- Exception: `EngagementException extends UtilitiesModuleException`
- Seed runner: `EngagementSeedScript` (called from `scripts/apex/seed-engagement-data.apex`)

**LWCs (all in `force-app/main/default/lwc/`):**

- `engagementPanel` (right-rail; both Account + Opportunity scope via `recordContext` prop)
- `addToDealTeamModal` (extends LightningModal)
- `alreadyAddedModal` (extends LightningModal; race-state confirm)
- `engagementDetailModal` (extends LightningModal; stats strip + vertical buying-motion timeline + per-row dismiss + click-to-focus)

**FlexiPages:** `Account_Engagement_Record_Page`, `Opportunity_Engagement_Record_Page` (parent: `sfa__Account_rec_L` / `sfa__Opportunity_rec_L` — different templates).

### Phase 2 — Inbound ingestion

- `EngagementInboundRest` (`@RestResource(urlMapping='/engagement/touches/*')`, `global with sharing`, HTTP POST, upsert by `External_Id__c`, returns `InboundResult` with counts)
- `IdentityResolutionService` (bulk email match → Contact, fallback Lead; case-insensitive; ambiguous detection)
- `LeadEngagementReparentHandler` (after Lead.IsConverted flips false→true, reparents touches Lead → Contact + Account)
- `LeadTrigger` (after update + before delete)

### Phase 3 — Routing intelligence

- `Touch_Routing_Rule__mdt` (10 fields: Priority, Active, Match_Path, Require_Same_Account, Require_Topic_Match, Persona_Filter, Touch_Type_Filter, Min_Intent_Level, Confidence, Description) + **5 seeded rules** (`OCR_Exact_Match`@95, `ACR_Same_Account_Topic_Match`@80, `Account_Topic_Executive`@75, `Account_Match_High_Intent`@70, `Account_Topic_Default`@60)
- `EngagementSignalRouter` (6-query bulkified algorithm, idempotent dedup, priority cascade)
- `TouchRoutingRulesSelector`
- `EngagementTouchTriggerHandler` (after-insert + after-update; routes when Resolution_Status becomes 'Resolved')
- `EngagementTouchTrigger`

### Phase 4 — Admin tools + maintenance

**LWCs:** `engagementTestATouch`, `engagementRuleCoverage`, `engagementErrorQueue`
**Apex:**

- `EngagementAdminController` (5 `@AuraEnabled` methods)
- `EngagementSignalDecayBatch` (linear decay, floors at 0; reads `Engagement_Settings__c.Signal_Decay_Days__c`)
- `EngagementTouchArchivalBatch` (archives touches > `Active_Window_Days__c` old)
- `EngagementMaintenanceScheduler` (weekly cron submits both batches)

### Phase 5 — Subject erasure + reports

**Apex:**

- `EngagementErasureService` (`eraseForContacts(Set<Id>)`, `eraseForLeads(Set<Id>)`; hard-delete via `Database.emptyRecycleBin`)
- `ContactEngagementErasureHandler` (before-delete on Contact)
- `LeadEngagementErasureHandler` (before-delete on Lead, in extended `LeadTrigger`)
- `ContactTrigger`

**Reports:** 5 reports + 3 custom report types in `force-app/main/default/reports/Engagement_Attribution/` and `reportTypes/`. Currently `.forceignore`d — XML field-path syntax issues; reports need Report Builder touch-up. Out of scope for this engagement unless you want to take them on as a stretch goal.

### Personal utilities (DO NOT MODIFY)

Under `force-app/main/default/classes/`:

- `dml/DMLManager.cls` — bulk DML helpers (`insertAsUser`, `updateAsUser`, `deleteAsUser`)
- `logging/Logger.cls` — depends on `Log_Setting__mdt` (default record: `defaults`, `Print_Debug_Logs__c=true`)
- `triggers/TriggerHandler.cls` — base class with `afterInsert()`, `afterUpdate()`, `beforeDelete()` etc. override hooks
- `general/Utilities.cls` — includes `Utilities.getFakeId(SObjectType)`, `Utilities.generateRandomCounter()`, `Utilities.generateUUID()`
- `testing/TestFactory.cls` — `createSObject(sObj)` auto-discovers `TestFactoryDefaults.{Object}Defaults` inner classes
- `testing/TestFactoryDefaults.cls` — generic edition (Stowers-specific defaults stripped); has `AccountDefaults`, `ContactDefaults`, `OpportunityDefaults`, `UserDefaults`, `OpportunityLineItemDefaults`, `CampaignDefaults`, `CaseDefaults`, `LeadDefaults`. `TEST_USER_PERMISSION = 'Engagement_Attribution_User'`
- `testing/TestFactoryRig.cls` — generic edition stub. Empty by design.

These are David's library. Flag bugs, don't fix.

---

## Current test state — be specific

### Apex (Phase 2-5 only; Phase 1 not yet measured in this audit)

Run: `sf apex run test --target-org engagementDev --code-coverage --result-format human --wait 20 --tests <list>`

Result on 2026-05-12:

- **56 tests, 25 failing (45%)**
- **31% org-wide coverage** (production transport requires ≥75%)

Class-coverage map (worst → best):

| Class                                                                                                  | Coverage |
| ------------------------------------------------------------------------------------------------------ | -------- |
| `EngagementSignalDecayBatch`                                                                           | 20%      |
| `EngagementAdminController`                                                                            | 60%      |
| `LeadEngagementReparentHandler`                                                                        | 65%      |
| `LeadEngagementErasureHandler`                                                                         | 67%      |
| `ContactEngagementErasureHandler`                                                                      | 70%      |
| `EngagementInboundRest`                                                                                | 78%      |
| `EngagementErasureService`                                                                             | 79%      |
| `EngagementSignalRouter`                                                                               | 79%      |
| `IdentityResolutionService`                                                                            | 91%      |
| `EngagementTouchTriggerHandler`                                                                        | 92%      |
| `EngagementTouchArchivalBatch`                                                                         | 95%      |
| `LeadTrigger`, `EngagementTouchTrigger`, `EngagementMaintenanceScheduler`, `TouchRoutingRulesSelector` | 100%     |

Phase 1 tests **were** passing during their own deploys but haven't been re-run since Wave G + Phase 2-5 schema additions (notably `Engagement_Dismissal__c` and `Touch_Routing_Rule__mdt`). Verify they're still green.

### Jest (LWC)

Run: `npm install && npm run test:unit`

Result on 2026-05-12:

- **27 tests across 7 suites, 11 failing (41%)**
- **Passing suites:** `engagementTestATouch`, `engagementErrorQueue`, `engagementRuleCoverage`
- **Failing suites:** `engagementPanel`, `engagementDetailModal`, `addToDealTeamModal`, `alreadyAddedModal`

**Root cause clusters:**

- `lightning/modal`: the jest-virtual mock lacks `close()`. Need `__mocks__/lightning/modal.js` providing an `LightningElement` subclass with a `close = jest.fn()` stub. Affects all 4 modal-based LWC suites.
- `c/addToDealTeamModal` mock loses its `open: jest.fn()` after `mockReset()` — likely an `afterEach` resetting all mocks too aggressively. Affects `engagementPanel.test.js`.
- `@lwc/lwc/no-async-operation` lint warning on `setTimeout`-based `flushPromises`. Cosmetic but the lint hook may fail CI.

---

## Known anti-patterns to fix or flag

1. **`AccountContactRelation.IsDirect`** is not writable via SOQL — tests that try to set it throw. Production code paths don't set it; this is purely a test-fixture issue. Multiple tests have been spot-fixed; verify no more sneak through.
2. **`Engagement_Settings__c.getOrgDefaults()`** returns `null` in tests when no record is inserted. Production code uses `?? <default>` fallbacks. Some tests may assume a value is present and break. Decide on a fixture pattern.
3. **Cross-test seed-data drift** — every Phase 2-5 test class has its own `@TestSetup` that builds a slightly different world. Consolidate via a shared `EngagementTestFixtures.cls` helper.
4. **`Database.LeadConvert`** in reparenting tests — converted-status name must match the org's available status. The scratch org's default is typically `'Closed - Converted'`. Verify or query dynamically.
5. **CMT records aren't insertable** in tests. `Touch_Routing_Rule__mdt` is queried as-deployed. If a test needs a controlled rule mix, mock the `TouchRoutingRulesSelector` via the Stub API or refactor the router to accept rules as input.
6. **GDPR cascade requires Engagement_Touch\_\_c delete perm** — permset now has `allowDelete=true, allowEdit=true`. Tests must run under a user with the permset assigned. Most existing tests do; verify.
7. **`AccessLevel.SYSTEM_MODE` slip-in** — `EngagementInboundRest.upsertTouches` uses `Database.upsert(records, externalIdField, false, AccessLevel.USER_MODE)` (correct). `EngagementServiceImplTest.@TestSetup` uses `Database.insert(records, AccessLevel.SYSTEM_MODE)` for seeding (acceptable in tests). Verify no production code has slipped to SYSTEM_MODE.
8. **`AddToDealTeamModal` jest mock** is module-mocked as `{ default: { open: jest.fn() } }` but the `afterEach` `mockReset()` clears the implementation, leaving `open` undefined for the next test.

---

## Your charter — deliverables

### A. Test fixture consolidation

`force-app/main/default/classes/testing/EngagementTestFixtures.cls` — a single helper that builds the canonical seeded world (1 Account, N Contacts, 1 Opportunity, K Topics, M Engagement_Touches with mixed personas/intent levels/topics, optional ACRs, optional OCRs). Every Phase 1-5 test class calls into it from `@TestSetup`. Parameterize for stress tests (200+ records).

### B. Per-class coverage targets

| Tier                 | Classes                                                                                                                                 | Target                    |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| Service layer        | `EngagementServiceImpl`, `IdentityResolutionService`, `EngagementSignalRouter`, `EngagementErasureService`, `EngagementAdminController` | ≥90%                      |
| Trigger handlers     | `EngagementTouchTriggerHandler`, `LeadEngagementReparentHandler`, `LeadEngagementErasureHandler`, `ContactEngagementErasureHandler`     | ≥90%                      |
| Batches              | `EngagementSignalDecayBatch`, `EngagementTouchArchivalBatch`                                                                            | ≥90%                      |
| Selectors            | All four                                                                                                                                | ≥85%                      |
| Triggers + scheduler | All                                                                                                                                     | 100% (most already there) |
| Controllers          | `EngagementController`, `EngagementInboundRest`                                                                                         | ≥90%                      |
| **Org-wide**         | —                                                                                                                                       | **≥80%**                  |

### C. Negative-path coverage (per `best-practices/apex-tests.md`)

Every public method needs at least:

- A null-input test (returns gracefully or throws expected exception)
- A governor-limit test where applicable (bulk insert 200 records)
- A USER_MODE permission-denial test where the security boundary matters (run as a user without the permset; assert the right exception or graceful empty return)

### D. Bulkification stress tests

- `IdentityResolutionService.resolveAll(List<Engagement_Touch__c>)` — pass 200 touches, assert ≤2 SOQL queries (Contact + Lead).
- `EngagementSignalRouter.routeTouches(Set<Id>)` — pass 200 touch ids, assert SOQL count ≤8.
- `EngagementErasureService.eraseForContacts(Set<Id>)` — pass 50 Contact ids each with 4 touches + 2 dismissals + 1 signal; assert single DML per child object.
- `EngagementInboundRest.ingest()` — POST 200 events; assert response counts match.

### E. LightningModal jest mock + LWC fixes

`force-app/test/jest-mocks/lightning/modal.js` (or wherever `lwc-jest` looks first):

```javascript
import { LightningElement, api } from "lwc";
export default class LightningModal extends LightningElement {
  @api size;
  close = jest.fn();
  static open(props) {
    return Promise.resolve({ result: "closed" });
  }
}
```

Register it in `jest.config.js` under `moduleNameMapper`. This single change should unblock 9+ failing LWC tests.

Fix the `c/addToDealTeamModal` cross-test mock pollution — switch from `mockReset()` to `mockClear()` (clears call history, preserves implementation), or re-establish the implementation in `beforeEach`.

### F. Strategy doc

`docs/test-strategy.md` covering:

1. Test pyramid for this codebase (unit / integration / end-to-end)
2. Fixture pattern (`EngagementTestFixtures` + per-test overrides)
3. Mocking strategy (Stub API for service layers, virtual modules for LWC Apex calls, `__mocks__/` for SF base components)
4. Naming conventions (CamelCase, no underscores, `<action><outcome>`)
5. How to add tests for a new feature (template)
6. CI hook (Husky pre-commit already runs lint/prettier; should we add a Jest gate?)

### G. Audit doc

`docs/test-audit-2026-05-12.md` — your initial pass: every failing test, root cause one-liner, fix complexity (S/M/L).

---

## Latitude & boundaries

**You CAN:**

- Refactor existing test classes freely.
- Add helper classes under `force-app/main/default/classes/testing/`.
- Add `__mocks__` files for Jest.
- Modify production code **only to improve testability** (e.g., extract a static method behind `@TestVisible`, expose a setter for dependency injection, refactor to use a Stub-friendly interface). **Flag every such change in your final report with rationale.**
- Deploy to the scratch org for verification.

**You CANNOT:**

- Push to git (David handles that).
- Modify `best-practices/`, `PHASE1-HANDOFF.md`, BRD, or DEMO.md beyond appending a final "Test coverage" section.
- Touch personal utility classes in `classes/{dml,logging,general,picklists,strings,rest,email,...}/`. Flag bugs in those, don't fix.
- Change feature behavior. If you find a real bug in the feature code, document it; don't silently fix it.

---

## Quality bar (non-negotiable)

- Every individual test runs in <30 seconds
- Full Apex suite runs end-to-end in <5 minutes
- Tests are deterministic — no flaky timing, no random-order dependencies
- No test depends on data outside `@TestSetup` (no implicit reliance on org-wide seed)
- Assertions use the `Assert` class with descriptive messages (`Assert.areEqual(expected, actual, 'Reason this should be true')`)
- Test method names: CamelCase, no underscores, action+outcome (`ingestUnknownEmailMarksNoMatch`, not `test_ingest_no_match` or `testIngestNoMatch1`)
- Every test wraps the method-under-test in `Test.startTest()` / `Test.stopTest()` so async/batches/futures execute deterministically

---

## Process

1. **Audit** — run the current Apex + Jest suites; produce `docs/test-audit-2026-05-12.md` with the failure inventory and root-cause categorization.
2. **Design** — write `docs/test-strategy.md`. Get David's eyes on it before bulk-implementing if anything is ambiguous.
3. **Implement** — refactor + add tests in batches. Re-run after each batch. Watch for regressions in passing tests.
4. **Verify** — run the full suite + capture coverage report. Save the output to `docs/test-coverage-2026-05-12.txt`.
5. **Document** — append `## Test coverage` section to `DEMO.md` with the command + expected output for verification.
6. **Hand back** — final report: pass rate, coverage by class, production-code testability changes (with rationale), open recommendations.

---

## Resources

- **Scratch org:** alias `engagementDev`. Reach with `sf org open --target-org engagementDev`. Username `test-xpjjj1ntr7xm@example.com`.
- **Seed reload:** `sf apex run --file scripts/apex/seed-engagement-data.apex --target-org engagementDev`
- **REST endpoint** for ingestion sanity: `POST https://<scratch-org>/services/apexrest/engagement/touches/`
- **Run tests:** `sf apex run test --target-org engagementDev --code-coverage --result-format human --wait 20`
- **Run Jest:** `npm install && npm run test:unit:coverage`
- **Existing test classes inventory** (16 total, list in §"Current test state"). All under `force-app/main/default/classes/engagement/*Test.cls`.

---

## Open questions for David (capture as you go)

If you hit any of these, raise them; don't decide unilaterally:

1. Should `Touch_Routing_Rule__mdt` be mockable in tests via the Stub API, or do we accept that tests query the deployed CMT records as-is?
2. Should `Engagement_Settings__c` have a hard-coded fallback in code, or should every test insert an org-default record in `@TestSetup`?
3. The scratch-org Lead conversion default status — is `'Closed - Converted'` reliable, or should we query `LeadStatus` dynamically in test setup?
4. Phase 5 reports are forceignored. Out of scope for testing, or take them on as stretch?

---

## When you're done

Hand back to David:

1. **One-line summary** — final pass rate + org-wide coverage %
2. **List of new test files** with one-line description of each
3. **List of refactored existing test files** with one-line note on what changed
4. **List of production-code testability changes** with rationale per change
5. **Open questions** or recommendations for next-pass improvements
6. **The audit doc + strategy doc** (paths)

Go.
