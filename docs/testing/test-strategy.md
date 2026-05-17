# Test Strategy — Engagement Attribution

**Author:** Pippa Codey (Senior Salesforce vArchitect)
**Date:** 2026-05-12
**Audience:** David Wood + future maintainers
**Companion docs:** [`test-audit-2026-05-12.md`](test-audit-2026-05-12.md), [`test-plan-2026-05-12.md`](test-plan-2026-05-12.md)
**Reference:** [`best-practices/apex-tests.md`](../../best-practices/apex-tests.md), [`best-practices/architecture.md`](../../best-practices/architecture.md), [`best-practices/lwc.md`](../../best-practices/lwc.md)

---

## 1. Test pyramid for this codebase

```
                  ┌────────────────────────┐
                  │   e2e (manual)         │   1-2 demo flows
                  │   Phase 4 admin LWCs   │   (DEMO.md beat list)
                  └────────────────────────┘
              ┌──────────────────────────────────┐
              │  Integration / Functional Apex   │   ~30% of tests
              │  Real DML, real triggers fire,   │   (router, batches,
              │  permset assigned, USER_MODE     │    erasure, inbound REST,
              │  enforced.                       │    admin controller)
              └──────────────────────────────────┘
        ┌────────────────────────────────────────────┐
        │   Unit Apex                                │   ~50% of tests
        │   Single class, fakes/stubs for collabs,   │   (service impl with
        │   no trigger side-effects when avoidable.  │    real DML; selectors;
        │                                            │    domain class)
        └────────────────────────────────────────────┘
   ┌────────────────────────────────────────────────────┐
   │   Jest LWC                                         │   ~20% of tests
   │   Component-level: render assertions, event       │   (panel, modals,
   │   dispatch, wire-adapter emission, Apex mocked.   │    admin LWCs)
   └────────────────────────────────────────────────────┘
```

**Boundary policy:**

- **Unit Apex** — A test class isolates one production class. Collaborators that touch DML (DMLManager, Loggers) are exercised end-to-end because they're project-wide dependencies; collaborators that are themselves under test (selectors when testing a service) get stubbed via the Apex Stub API.
- **Integration Apex** — Triggers fire. Permset assignment matters. Tests run under `System.runAs(testUser)` so USER_MODE rules apply.
- **Jest** — DOM rendering + events + wire emission. Apex calls are virtual-mocked. `lightning/modal` is mocked via a shared file in `force-app/test/jest-mocks/lightning/modal.js`.
- **No e2e in this engagement.** Manual demo verification per `DEMO.md` is the surrogate.

**Async rule:** Every batch / future / queueable / scheduler test wraps the kick-off in `Test.startTest()` / `Test.stopTest()`. The post-stop state is the assertion target.

---

## 2. Fixture strategy

### Goal

One canonical seeded world. Twenty test classes consume the same `@TestSetup` helper. No more drift. Negative-path tests still hand-build their own fixtures inline — the helper is for the happy-path baseline.

### Public surface — `force-app/main/default/classes/testing/EngagementTestFixtures.cls`

```apex
public with sharing class EngagementTestFixtures {

    // ─── User provisioning ──────────────────────────────────────────────
    /** Provisions a Standard-licence user with the
     *  Engagement_Attribution_User permset assigned. */
    public static User provisionEngagementUser(String lastName) { ... }

    /** Provisions a Standard-licence user WITHOUT the permset for negative
     *  USER_MODE tests. */
    public static User provisionUnauthorizedUser(String lastName) { ... }

    // ─── World seeding ──────────────────────────────────────────────────
    /** Inserts the canonical UHC world.
     *  Returns a SeededWorld pointer holding all the IDs the tests need. */
    public static SeededWorld seedUhcWorld() { ... }

    /** Same shape as seedUhcWorld() but with `n` extra Contacts and
     *  `n * touchesPerContact` Engagement_Touch__c records — for bulk
     *  governor-limit stress tests. */
    public static SeededWorld seedUhcWorldBulk(Integer contacts, Integer touchesPerContact) { ... }

    // ─── Individual builders (for fine-grained tests) ──────────────────
    public static Account newUhcAccount(String suffix) { ... }
    public static Contact newContact(Id accountId, String first, String last, String email) { ... }
    public static Touch_Topic__c newTopic(String name, String externalCode) { ... }
    public static Opportunity newOpportunity(Id accountId, String name, Id topicId) { ... }
    public static Engagement_Touch__c newTouch(Id accountId, Id contactId, Id topicId, String externalId) { ... }
    public static Engagement_Touch__c newAgedTouch(Id accountId, Id contactId, Id topicId, Integer ageDays) { ... }
    public static OpportunityContactRole newOcr(Id oppId, Id contactId, String role, Boolean isPrimary) { ... }
    public static AccountContactRelation newAcr(Id accountId, Id contactId, Boolean isDirect) { ... }
    public static Engagement_Dismissal__c newDismissal(Id contactId, Id oppId, Id accountId) { ... }
    public static Opportunity_Engagement_Signal__c newSignal(Id touchId, Id oppId, Id contactId, Decimal confidence) { ... }

    // ─── Settings ──────────────────────────────────────────────────────
    /** Inserts an Engagement_Settings__c org-default record with the
     *  given decay window. Idempotent (upserts on null Id). */
    public static void seedSettings(Integer decayDays, Integer activeWindowDays) { ... }

    // ─── Fake IDs (for negative paths) ─────────────────────────────────
    /** Returns a fake Engagement_Touch__c Id via Utilities.getFakeId.
     *  Use for null-input / not-found-id negative tests so the test
     *  doesn't need real DML at all. */
    public static Id fakeTouchId() { ... }
    public static Id fakeContactId() { ... }
    public static Id fakeOpportunityId() { ... }

    // ─── Result type ───────────────────────────────────────────────────
    public class SeededWorld {
        public Id accountId;
        public Id opportunityId;
        public Id networkTopicId;
        public Map<String, Id> contactIdsByLastName;  // 'Johnson'→Sarah, 'Chen'→Mike, 'Patel'→Lisa, 'Davis'→Tom
        public Map<String, Id> topicIdsByCode;        // 'NETMGT', 'PAYINT', 'CLAIMSMOD', 'PROVIDER', 'COMPLIANCE'
        public List<Id> touchIds;
        public Id mikeChenOcrId;                      // seeded OCR member
        public Id lisaPatelAcrId;                     // seeded indirect ACR
    }
}
```

### Defaults baked into `seedUhcWorld()`

| Object                   | Count | Notes                                                                                |
| ------------------------ | ----: | ------------------------------------------------------------------------------------ |
| Account                  |     1 | "United Healthcare Test"                                                             |
| Contact                  |     4 | Sarah Johnson (CFO), Mike Chen (VP Eng), Lisa Patel (consultant), Tom Davis (VP Ops) |
| Touch_Topic\_\_c         |     5 | Network Mgmt, Payment Integrity, Claims Editing, Provider Data, Compliance           |
| Opportunity              |     1 | "Network Pricing Test" — open, linked to Network Mgmt topic                          |
| OpportunityContactRole   |     1 | Mike Chen as Evaluator                                                               |
| AccountContactRelation   |     1 | Lisa Patel (IsDirect=false via Database.update — see note)                           |
| Engagement_Touch\_\_c    |   ~12 | Mixed personas, topics, ages, asset names. One 3-cluster repeat-download on Sarah    |
| Engagement_Settings\_\_c |     1 | `Signal_Decay_Days__c=60`, `Active_Window_Days__c=180`, org default                  |

### `AccountContactRelation.IsDirect` handling

Per the brief: `IsDirect` is not writable on insert. The fixture builds the ACR as direct=true (the Salesforce default), then `Database.update` overrides `IsDirect=false` on the row. Verified pattern in the existing `EngagementServiceImplTest.seedWorld`.

### Composition pattern

- `@TestSetup` calls `EngagementTestFixtures.provisionEngagementUser('MyTestClass')`, then `System.runAs(thatUser) { EngagementTestFixtures.seedUhcWorld(); }`.
- Test methods retrieve the user via `EngagementTestFixtures.getProvisionedUser('MyTestClass')` and re-fetch the seeded IDs via a `SeededWorld pointer = EngagementTestFixtures.lookupWorld();` (queries on Account name).
- Negative-path tests build their own extra fixtures inline.

### What the fixture does NOT do

- Insert `Touch_Routing_Rule__mdt` — they're CMT and deploy-bound. Tests assert against the 5 deployed rules.
- Insert `Log_Setting__mdt` — same reason; the `defaults` record is deployed.
- Run `EngagementSignalRouter` — that's intentional. Tests that need signals call the router explicitly.

---

## 3. Mocking strategy

### Apex — Stub API (`System.Test.createStub`)

For unit tests of `EngagementServiceImpl` and `EngagementAdminController` where we want to assert behavior **without** running the real selectors or routers:

- **`IEngagementService`** — already exists. `EngagementControllerTest` already uses this pattern (mocks the service so the controller is unit-tested in isolation). Continue.
- **Add `ITouchRoutingRulesSelector`** — to enable per-test rule permutations (REDESIGN-1 in the audit). Either: (a) extract an interface, OR (b) add a `@TestVisible static List<Touch_Routing_Rule__mdt> rulesOverride` static the production code falls back through. Option (b) is less invasive — recommend (b) for this engagement and surface (a) as a follow-up.

**Pattern:**

```apex
Test.createStub(IEngagementService.class, new MyServiceMock(...));
EngagementController.service = mockInstance;
```

### Jest — three layers

**Layer 1 — `lightning/modal` base class** (one file, fixes 4 suites):

`force-app/test/jest-mocks/lightning/modal.js`:

```javascript
const { LightningElement, api } = require("lwc");

class LightningModal extends LightningElement {
  @api size;
  @api label;
  close = jest.fn();

  static open(props) {
    // Return a thenable that test code can replace via
    // `LightningModal.open = jest.fn().mockResolvedValue(...)` when needed.
    return Promise.resolve({ result: "closed" });
  }
}

module.exports = LightningModal;
module.exports.default = LightningModal;
```

Register in `jest.config.js`:

```javascript
moduleNameMapper: {
    '^lightning/modal$': '<rootDir>/force-app/test/jest-mocks/lightning/modal.js'
}
```

This means **no `jest.mock('lightning/modal', ...)`** is needed in any individual test file. The mock is global. Resolves Clusters F and H from the audit.

**Layer 2 — Apex imports** — virtual module mocks per file:

```javascript
jest.mock(
  "@salesforce/apex/EngagementController.getForOpportunity",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
```

This pattern is already in use and correct. No change.

**Layer 3 — Sibling LWCs** (e.g. `c/addToDealTeamModal` inside `engagementPanel.test.js`):

```javascript
jest.mock(
  "c/addToDealTeamModal",
  () => ({
    default: { open: jest.fn().mockResolvedValue({ result: "closed" }) }
  }),
  { virtual: true }
);
```

Provide a default `mockResolvedValue` in the factory itself so `mockClear()` in `afterEach` doesn't wipe behavior. Replace `mockReset()` calls with `mockClear()` — resolves Cluster G.

### Boundary

- **Don't mock DMLManager, Logger, Utilities, TriggerHandler.** These are project-wide utilities and form the basement of the test architecture. Tests run end-to-end through them.
- **Do mock selectors** when testing services in isolation (where the selector itself has its own test class).
- **Don't mock `Touch_Routing_Rule__mdt` reads in the router test** — let the deployed CMT records drive the test (one round of real-world coverage). DO add the `@TestVisible rulesOverride` static so other tests can pin rule sets when needed.

---

## 4. Naming conventions reaffirmed

Per [`best-practices/apex-tests.md`](../../best-practices/apex-tests.md):

- **CamelCase. No underscores.** `actionThenExpectedOutcome` pattern.
- Action-first, outcome-second:
  - `executeDecaysSignalsOlderThanThreshold` ✓
  - `getForOpportunityReturnsDtoPerEngagedContact` ✓
  - `routeTouchesFiresOcrRuleWhenContactOnOpp` ✓
- Negative paths get suffixes:
  - `addToOcrSafeNullInputThrowsEngagementException` ✓
  - `dismissContactValidationThrowsWhenBothScopesProvided` ✓
- Bulk paths get suffixes:
  - `routeTouchesHandles200TouchesInOneTransaction`
  - `resolveAllBulkProcessesWithoutExceedingSoqlLimit`
- USER_MODE / permission paths:
  - `getForOpportunityWithoutPermsetReturnsEmpty`
  - `routeTouchesWithoutPermsetThrowsExpectedException`

`Assert.*` only — never `System.assertEquals`. Every assertion carries a descriptive message.

---

## 5. Coverage targets by tier

| Tier             | Classes                                                                                                                                 |                                          Target |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------: |
| Service layer    | EngagementServiceImpl, IdentityResolutionService, EngagementSignalRouter, EngagementErasureService                                      |                                        **≥90%** |
| Controllers      | EngagementController, EngagementInboundRest, EngagementAdminController                                                                  |                                        **≥90%** |
| Trigger handlers | EngagementTouchTriggerHandler, LeadEngagementReparentHandler, LeadEngagementErasureHandler, ContactEngagementErasureHandler             |                                        **≥90%** |
| Batches          | EngagementSignalDecayBatch, EngagementTouchArchivalBatch                                                                                |                                        **≥90%** |
| Selectors        | EngagementTouchesSelector, OpportunityContactRolesSelector, EngagementDismissalsSelector, TouchTopicSelector, TouchRoutingRulesSelector |                                        **≥85%** |
| Domain           | EngagementTouches                                                                                                                       |                                        **≥85%** |
| Triggers         | ContactTrigger, LeadTrigger, EngagementTouchTrigger                                                                                     |                                        **100%** |
| Scheduler        | EngagementMaintenanceScheduler                                                                                                          |                                        **100%** |
| Exception / DTO  | EngagementException, EngagementDTO, AddToOcrResult                                                                                      |                      none (no executable lines) |
| **Org-wide**     | —                                                                                                                                       | **≥80%** (safety net; **95% is the real goal**) |

### Per-public-method checklist (from Pippa persona)

Every public method in the engagement classes must hit:

- [ ] Good-path test
- [ ] Bad-path test (null / empty / malformed input)
- [ ] Bulk path test (200 records where the method takes a list)
- [ ] Governor-limit assertion at least on service-layer methods
- [ ] USER_MODE permission-denied path (run as user without permset)
- [ ] DML exception path (induce a constraint violation, assert exception type + Logger entry)

`test-plan-2026-05-12.md` enumerates the specific tests per class.

---

## 6. Template — adding tests for a new feature

When a new Engagement feature class lands (e.g. `EngagementNotificationService`):

```apex
/**
 * @description Tests for `EngagementNotificationService`. Covers the contract
 *              for <feature>, including null/empty inputs, bulk, USER_MODE, and
 *              partial-DML-failure scenarios.
 * @group Engagement Attribution
 * @see EngagementNotificationService
 * @author <author>
 * @since <month year>
 */
@IsTest
private class EngagementNotificationServiceTest {
  private static final String CLASS_NAME = 'EngagementNotificationServiceTest';

  @TestSetup
  static void setup() {
    User u = EngagementTestFixtures.provisionEngagementUser('NotifSvcTest');
    System.runAs(u) {
      EngagementTestFixtures.seedUhcWorld();
    }
  }

  // ─── Good path ────────────────────────────────────────────────────────

  @IsTest
  static void notifyOnSignalCreationSendsOneEmailPerSubscriber() {
    System.runAs(testUser()) {
      EngagementTestFixtures.SeededWorld world = EngagementTestFixtures.lookupWorld();
      // arrange — fetch the seeded signal or build one
      // ...
      Test.startTest();
      EngagementNotificationService.notifyForSignals(new Set<Id>{ signalId });
      Test.stopTest();
      // assert — count emails sent via Limits.getEmailInvocations or
      // assert against a captured payload
      Assert.areEqual(
        1,
        Limits.getEmailInvocations(),
        'Expected one email per subscriber.'
      );
    }
  }

  // ─── Null / empty bad paths ───────────────────────────────────────────

  @IsTest
  static void notifyForSignalsNullSetThrowsEngagementException() {
    System.runAs(testUser()) {
      try {
        EngagementNotificationService.notifyForSignals(null);
        Assert.fail('Expected EngagementException for null input.');
      } catch (EngagementException e) {
        Assert.isTrue(
          e.getMessage().containsIgnoreCase('required'),
          'Expected message to identify the missing argument.'
        );
      }
    }
  }

  @IsTest
  static void notifyForSignalsEmptySetIsNoOp() {
    System.runAs(testUser()) {
      Test.startTest();
      EngagementNotificationService.notifyForSignals(new Set<Id>());
      Test.stopTest();
      Assert.areEqual(
        0,
        Limits.getEmailInvocations(),
        'Expected no emails dispatched for empty input.'
      );
    }
  }

  // ─── Bulk ─────────────────────────────────────────────────────────────

  @IsTest
  static void notifyForSignals200RecordsRespectsGovernors() {
    System.runAs(testUser()) {
      EngagementTestFixtures.SeededWorld world = EngagementTestFixtures.seedUhcWorldBulk(
        200,
        1
      );
      Set<Id> signalIds = generateSignalsForBulkWorld(world);
      Test.startTest();
      EngagementNotificationService.notifyForSignals(signalIds);
      Test.stopTest();
      Assert.isTrue(
        Limits.getQueries() < 5,
        'Expected query count to stay bounded under bulk load. Got ' +
        Limits.getQueries()
      );
    }
  }

  // ─── USER_MODE boundary ───────────────────────────────────────────────

  @IsTest
  static void notifyForSignalsWithoutPermsetThrowsExpected() {
    User unauthorized = EngagementTestFixtures.provisionUnauthorizedUser(
      'NotifSvcDenied'
    );
    System.runAs(unauthorized) {
      Id fakeSignalId = EngagementTestFixtures.fakeSignalId();
      try {
        EngagementNotificationService.notifyForSignals(
          new Set<Id>{ fakeSignalId }
        );
        Assert.fail('Expected USER_MODE to block the read.');
      } catch (Exception e) {
        Assert.isTrue(
          e instanceof EngagementException ||
            e instanceof QueryException ||
            e instanceof System.NoAccessException,
          'Expected an access-denied family exception. Got ' + e.getTypeName()
        );
      }
    }
  }

  // ─── DML exception path ───────────────────────────────────────────────

  @IsTest
  static void notifyForSignalsPartialDmlFailureLogsAndContinues() {
    // ...
  }

  private static User testUser() {
    return EngagementTestFixtures.getProvisionedUser('NotifSvcTest');
  }
}
```

**For LWCs**, use this skeleton:

```javascript
import { createElement } from "lwc";
import MyNewComponent from "c/myNewComponent";
import myApex from "@salesforce/apex/MyController.myMethod";

// Apex mock
jest.mock(
  "@salesforce/apex/MyController.myMethod",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// `lightning/modal` is already mocked globally via jest.config.js
// — no per-file mock needed.

describe("c-my-new-component", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("rendersHappyPath", async () => {
    /* ... */
  });
  it("handlesEmptyDataGracefully", async () => {
    /* ... */
  });
  it("handlesApexError", async () => {
    /* ... */
  });
});
```

---

## 7. CI hooks

Husky `precommit` runs `prettier` + `eslint` + `sfdx-lwc-jest --findRelatedTests` per the existing `package.json`. Recommend adding a `prepush` hook that runs:

- `npm run test:unit` (full Jest)
- (Optional, later) `sf apex run test --target-org engagementDev --tests <changed>` for the engagement-feature touched classes

Out of scope for this engagement — flag as a follow-up.

---

## 8. What I'm explicitly NOT changing

- The 5 deployed `Touch_Routing_Rule__mdt` CMT records (out of scope; tests work against the deployed cascade).
- `best-practices/`, `PHASE1-HANDOFF.md`, `BRD-Engagement-Attribution.docx`.
- Personal utility classes under `classes/{dml,logging,general,picklists,strings,rest,email,triggers,testing}/` — `TestFactory.cls` / `TestFactoryDefaults.cls` are intentionally not the engagement-fixture home. `EngagementTestFixtures.cls` lives alongside them under `classes/testing/` but composes them, not replaces them.
- The 5 forceignored reports.

---

**Summary:**

- Test pyramid → ~50% unit Apex, ~30% integration Apex, ~20% Jest LWC, manual e2e via DEMO.md.
- Fixture single source of truth → `EngagementTestFixtures.cls` exposes `SeededWorld` + builders + permset-aware user provisioning.
- Modal mocking → one global `force-app/test/jest-mocks/lightning/modal.js` resolves Clusters F, G, H.
- Coverage targets → services / controllers / batches / trigger handlers ≥90%, selectors ≥85%, org-wide ≥80% (95% target).
- Per-method test contract: good + bad + bulk + USER_MODE + DML-exception paths.

— Pippa
