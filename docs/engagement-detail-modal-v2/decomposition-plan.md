# Decomposition Plan — Engagement Detail Modal v2

|                                                            |                                                                                                                                                                                                                         |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Owner**                                                  | Atlas                                                                                                                                                                                                                   |
| **Date**                                                   | 2026-05-16                                                                                                                                                                                                              |
| **Status**                                                 | DRAFT — awaiting David acknowledgement before worker dispatch.                                                                                                                                                          |
| **Inputs**                                                 | [BRD](./BRD.md) · [TDD](./TDD.md) · [design-spec](./design-spec.md) · [brief-IM](./brief-interesting-moments.md) · [brief-hierarchy](./brief-account-hierarchy-engagement.md) · [atlas-decisions](./atlas-decisions.md) |
| **Per [feedback-atlas-verifies-the-plan-before-dispatch]** | No worker dispatched until David acknowledges this plan.                                                                                                                                                                |

---

## 0. Pre-flight verification (Atlas's own checks)

| Check                                                                                         | Result                                                                                                                                                                                                                                                                                                                   |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| CSI-7162 utility-class merges complete on `feature/engagement-attribution`?                   | YES — last 5 commits are CSI-7162 cleanup. We're on the post-merge baseline.                                                                                                                                                                                                                                             |
| v1 modal infra (`engagementDetailModal` LWC, `EngagementDTO`, `Engagement_Touch__c`) present? | YES — verified at [classes/engagement/](../../force-app/main/default/classes/engagement/) and [lwc/engagementDetailModal/](../../force-app/main/default/lwc/engagementDetailModal/).                                                                                                                                     |
| MI permset ladder exists?                                                                     | YES — verified at [permissionsets/Additional_Permissions_Marketing_Influence_View.permissionset-meta.xml](../../force-app/main/default/permissionsets/Additional_Permissions_Marketing_Influence_View.permissionset-meta.xml) (+ Power_User, Admin, Integration). v2 EXTENDS; does not duplicate.                        |
| `miIllustrations` static resource present?                                                    | YES — at [staticresources/miIllustrations/](../../force-app/main/default/staticresources/miIllustrations/).                                                                                                                                                                                                              |
| Schema field is `Occurred_At__c` (not `Touch_Datetime__c`)?                                   | CONFIRMED via [Occurred_At\_\_c.field-meta.xml](../../force-app/main/default/objects/Engagement_Touch__c/fields/Occurred_At__c.field-meta.xml). TDD has the wrong field name in two places — corrected in [atlas-decisions §A1](./atlas-decisions.md#a1--approve-the-seven-new-apex-classes--existing-class-extensions). |
| Existing selector class name?                                                                 | `EngagementTouchesSelector` (plural). TDD wrote singular — fix the TDD before tickets.                                                                                                                                                                                                                                   |
| In-flight conflicts with `mi-on-lead-investigation` (Iris)?                                   | YES — both extend `EngagementDTO`. Risk R1 below.                                                                                                                                                                                                                                                                        |
| Conflict with Stream-5 `Record_Retention_Rule__mdt` / `System_Exception_Log__c`?              | NO — that's backlog, not in flight. Per [project-record-cleanup-framework](../../../../.claude/projects/-Users-david-Work-Zelis/memory/project_record_cleanup_framework.md).                                                                                                                                             |
| Personal-lib edits avoided?                                                                   | Plan respects [feedback-ip-protection-no-personal-lib-edits](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_ip_protection_no_personal_lib_edits.md) — all new helpers go in feature-scoped classes.                                                                                                |
| `@author David Wood` only in shipped headers?                                                 | Per [feedback-sf-attribution](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_sf_attribution.md), enforced in every ticket below.                                                                                                                                                                   |

---

## 1. Open items resolved

See [atlas-decisions.md](./atlas-decisions.md) for full rationale. Summary:

| ID  | Item                                         | Resolution                                                                                                               |
| --- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| A1  | Seven new Apex classes                       | APPROVED with TDD corrections (singular→plural selector, `Occurred_At__c` field name, controller is sibling not rename). |
| A2  | Static-resource vs inline-SVG                | BOTH — static resource as canonical; LWC inlines SVG body for SLDS theming.                                              |
| A3  | Permset ladder naming                        | EXTEND existing `Additional_Permissions_Marketing_Influence_*` — do not create a parallel ladder.                        |
| A4  | 500-touch cap                                | KEEP for v2; add `Logger.warn` at 400; revisit if real usage clips engagement at large accounts.                         |
| A5  | Rule eval timing — sync vs async             | SYNC trigger for v2. Async-via-PE deferred until telemetry shows pressure.                                               |
| A6  | Logger.cls permset                           | CONFIRMED — no action needed; Logger ships with CSI-7162 baseline.                                                       |
| A7  | Dispatch order                               | APPROVED with adjustment: Iris and Sage early-design ahead of Pippa.                                                     |
| D1  | Empty-state modal opens or panel suppresses? | **PUNT to David** — Atlas recommends modal opens.                                                                        |
| D2  | Default hierarchy scope on parent accounts   | **PUNT to David** — Atlas recommends "This account only."                                                                |
| D3  | Default contact lane sort                    | **PUNT to David** — Atlas recommends touch-count descending.                                                             |

David needs to call D1 / D2 / D3 before Iris can lock the gate-1 spec for the LWC tickets.

---

## 2. Jira ticket list (BSKY project)

23 tickets across 2 features + cross-cutting setup. Ready to bulk-create once the Sharp Kai BSKY workspace is provisioned per [brief-sharp-kai-jira-workspace-setup](../briefs/brief-sharp-kai-jira-workspace-setup.md).

**Conventions in every ticket:**

- All Apex headers `@author David Wood` only.
- `with sharing` on every class; `WITH USER_MODE` / `AccessLevel.USER_MODE` everywhere.
- Tests RED-first per [TEAM.md](../../.claude/agents/TEAM.md) workflow.
- ≥95% Apex coverage; 100% on security boundary.
- No real emails; no test cheating; factories satisfy every VR.
- TODO-prefix for any deferred work.
- Hold deploys to `dwood_z` until David clears.

### Component label

All tickets get component `MI / Engagement Attribution` and label `EngagementDetailModalV2`. Feature-1 tickets additionally get `InterestingMoments`; Feature-2 additionally get `AccountHierarchy`.

---

### EPIC: BSKY-100 — Engagement Detail Modal v2 (parent epic)

**Type:** Epic
**Assignee:** Iris Ruth (owner) / Atlas (TA)
**Effort:** Tracking — no direct dev work
**Children:** BSKY-101 → BSKY-123

Parent epic for the v2 rebuild — David's calling-card surface. Contains both features (Interesting Moments + Account Hierarchy) and the cross-cutting tickets. Acceptance = both features delivered, demoed to David, signed off by Iris gate-2.

---

### CROSS-CUTTING (4 tickets)

#### BSKY-101 — Iris resolves BRD §7 + atlas-decisions D1/D2/D3

**Type:** Story
**Assignee:** Iris Ruth (with David)
**Effort:** 0.5 day
**Component:** MI / Engagement Attribution
**Labels:** spec, gate-1

**Context.** Seven open spec questions in [BRD §7](./BRD.md#7-open-questions-for-iris-gate-1-spec-items) and three Atlas-punted items in [atlas-decisions D1–D3](./atlas-decisions.md#items-punted-to-david-3) need Iris-with-David resolution before red tests can be written against ACs. Without this lock, Pippa's tests aren't assertable against signed-off behavior.

**ACs.**

- AC1: All seven BRD §7 questions answered in writing in BRD §7 itself; status changed to "Locked."
- AC2: Atlas's D1/D2/D3 recommendations either accepted or overridden by David, recorded in [atlas-decisions.md](./atlas-decisions.md).
- AC3: Iris signals gate-1 approval in this ticket comments; Atlas confirms in reply.

**Pointers.** [BRD §7](./BRD.md#7-open-questions-for-iris-gate-1-spec-items) · [atlas-decisions D1–D3](./atlas-decisions.md#items-punted-to-david-3)

---

#### BSKY-102 — Marlowe corrects TDD field naming + selector class name

**Type:** Task
**Assignee:** Marlowe Codey
**Effort:** 0.25 day
**Component:** Documentation

**Context.** [TDD](./TDD.md) §3.2 / §6 reference `Touch_Datetime__c` and `EngagementTouchSelector` — both wrong. Actual field is `Occurred_At__c`; actual class is `EngagementTouchesSelector` (plural). This is the same drift that caused 2026-05-14 smoke-test failure per [feedback-atlas-verifies-before-uat](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_atlas_verifies_before_uat.md).

**ACs.**

- AC1: TDD §3.2 example uses `Occurred_At__c DESC` and queries `EngagementTouchesSelector`.
- AC2: TDD §6 worst-case sizing table uses `Occurred_At__c`.
- AC3: Atlas signs off on the corrected TDD before BSKY-101 closes.

**Pointers.** [TDD](./TDD.md) · [Occurred_At\_\_c field meta](../../force-app/main/default/objects/Engagement_Touch__c/fields/Occurred_At__c.field-meta.xml)

---

#### BSKY-103 — Helix Genie schema review on the 2 new fields + CMDT

**Type:** Task
**Assignee:** Helix Genie (Data Architect, Standards Team)
**Effort:** 0.25 day
**Component:** MI / Engagement Attribution
**Labels:** standards, schema-review

**Context.** Per [TEAM.md](../../.claude/agents/TEAM.md), Helix Genie has SObject schema-review veto. Two new fields on `Engagement_Touch__c` and one new CMDT need her sign-off before Boomer writes the field metadata.

**ACs.**

- AC1: Helix reviews [TDD §2.1–2.2](./TDD.md#21-new-fields-on-engagement_touch__c) — field types, indexing, CMDT field shape.
- AC2: Signs off in the ticket or flags concerns to Atlas.

**Pointers.** [TDD §2](./TDD.md#2-data-model)

---

#### BSKY-104 — Nova produces missing state mocks (if any surface during decomposition)

**Type:** Task
**Assignee:** Nova Astro
**Effort:** 0.25 day (likely 0)
**Component:** Design

**Context.** Per [TDD §11](./TDD.md#11-dispatch--ready-for-atlas) step 6 — keep Nova on standby for any state mock not yet covered. Reviewing the package, I don't see a gap; this ticket is open insurance and may close as "not needed."

**ACs.**

- AC1: Atlas reviews mocks against TDD §4.1 component map; flags missing states (if any).
- AC2: Nova produces SVG/HTML; or closes ticket as "all states covered."

---

### FEATURE 1: Interesting Moments — 9 tickets (BSKY-110 → BSKY-118)

#### BSKY-110 — Schema: 2 new fields on Engagement_Touch**c + Interesting_Moment_Rule**mdt

**Type:** Story
**Assignee:** Boomer Codey (Apex schema)
**Effort:** 0.5 day
**Component:** MI / Engagement Attribution
**Labels:** schema, InterestingMoments

**Context.** Per [TDD §2.1–2.2](./TDD.md#2-data-model) and [brief-IM](./brief-interesting-moments.md#schema--architecture-implications-for-atlas) — add `Is_Interesting_Moment__c` (Checkbox, indexed) and `Interesting_Moment_Reason__c` (Text 255) on `Engagement_Touch__c`. Create `Interesting_Moment_Rule__mdt` CMDT with 9 fields per TDD §2.2.

**ACs.**

- AC1: Two new fields deploy clean; field-level history tracking on `Is_Interesting_Moment__c`.
- AC2: CMDT deploys; 3+ seed rule records included (rule set from BSKY-101 Iris-locked answer to BRD §7.5).
- AC3: FLS added to `Additional_Permissions_Marketing_Influence_View` (read), `Power_User` (read), `Admin` (read).
- AC4: CMDT-write permission added to `Admin` permset only via custom permission `Marketing_Influence_Manage_Rules`.

**Pointers.** [TDD §2](./TDD.md#2-data-model) · [brief-IM](./brief-interesting-moments.md) · [feedback-owd-private-permset-architecture](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_owd_private_permset_architecture.md)

---

#### BSKY-111 — RED TESTS: InterestingMomentEvaluator + trigger integration

**Type:** Story
**Assignee:** Pippa Codey → Wren Hootie (test code only per [feedback-test-coders-only-touch-tests](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_test_coders_only_touch_tests.md))
**Effort:** 1.5 days
**Component:** MI / Engagement Attribution
**Labels:** tests, InterestingMoments

**Context.** TDD section [§7.2.3](./TDD.md#72-critical-test-scenarios) lists rule-evaluation scenarios. Pippa designs the test classes; Wren writes the Apex (Wren ONLY edits test code, never production).

**ACs.**

- AC1: `InterestingMomentEvaluatorTest` covers: each rule type fires (campaign / asset / touch-type / score / multi-touch threshold).
- AC2: Multiple rules: priority order respected; first match wins.
- AC3: Inactive rule doesn't fire (Active\_\_c=false short-circuit).
- AC4: Bulk-safe: 200 touches in single trigger run, no SOQL/DML governor breach.
- AC5: Backfill batch test: re-evaluates correctly when rules change.
- AC6: All tests RED at commit time; documented in PR per TDD §7.4.
- AC7: Coverage ≥95% on the evaluator class.
- AC8: No real emails; no test cheating.

**Pointers.** [TDD §7](./TDD.md#7-test-strategy) · [feedback-test-coders-only-touch-tests](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_test_coders_only_touch_tests.md) · [feedback-test-quality-metrics](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_test_quality_metrics.md)

---

#### BSKY-112 — Apex: InterestingMomentEvaluator (pure-function rule engine)

**Type:** Story
**Assignee:** Boomer Codey → Tex Codey
**Effort:** 1.5 days
**Component:** MI / Engagement Attribution
**Labels:** apex, InterestingMoments

**Context.** Per [TDD §3.1](./TDD.md#31-new-classes), `InterestingMomentEvaluator` is a pure function over `(Engagement_Touch__c, List<Interesting_Moment_Rule__mdt>)`. Cached rule list per-transaction. Bulk-safe. Called from the trigger handler.

**ACs.**

- AC1: Class compiles; signature `static Pair<Boolean, String> evaluate(Engagement_Touch__c touch, List<Interesting_Moment_Rule__mdt> activeRules)`.
- AC2: BSKY-111 tests go green.
- AC3: `with sharing`; `@author David Wood`; no `System.debug` (`Logger` only).
- AC4: Performance: 75 touches × 20 rules < 50ms (Logger.metric trace).

**Pointers.** [TDD §3.1](./TDD.md#31-new-classes) · [best-practices/apex.md](../../best-practices/apex.md)

---

#### BSKY-113 — Apex: extend EngagementTouchTriggerHandler with IM evaluation

**Type:** Story
**Assignee:** Boomer Codey
**Effort:** 0.5 day
**Component:** MI / Engagement Attribution
**Labels:** apex, InterestingMoments

**Context.** Per [TDD §3.2](./TDD.md#32-extended-classes) — add `beforeInsert` and `beforeUpdate` handler steps that call `InterestingMomentEvaluator`. Preserve the existing handler structure; don't refactor unrelated logic.

**ACs.**

- AC1: Existing handler tests remain green.
- AC2: New handler steps populate `Is_Interesting_Moment__c` and `Interesting_Moment_Reason__c` per evaluator output.
- AC3: BSKY-111 trigger-integration tests go green.

**Pointers.** [EngagementTouchTriggerHandler.cls](../../force-app/main/default/classes/engagement/EngagementTouchTriggerHandler.cls) · [feedback-extend-not-modify-third-party](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_extend_not_modify_third_party.md)

---

#### BSKY-114 — Apex: InterestingMomentBackfillBatch

**Type:** Story
**Assignee:** Tex Codey (mid-level batch implementation)
**Effort:** 1 day
**Component:** MI / Engagement Attribution
**Labels:** apex, batch, InterestingMoments

**Context.** Per [TDD §3.1](./TDD.md#31-new-classes) — `Database.Batchable<sObject>` re-evaluating historical touches against current rules. Re-runnable. Admin invokes manually after rule changes.

**ACs.**

- AC1: Batch class deploys; `with sharing`; `@author David Wood`.
- AC2: Scope query parameterizable: all touches OR a date-windowed subset.
- AC3: Per-batch `Logger.metric` + final `Logger.info` with counts (touches re-evaluated, flags flipped on, flags flipped off).
- AC4: Pippa-approved test covers: state transitions on rule add / rule deactivate / rule edit.

**Pointers.** [TDD §3.1](./TDD.md#31-new-classes)

---

#### BSKY-115 — LWC: render Interesting Moment dot variant + filter chip

**Type:** Story
**Assignee:** Coda Astro → Kit Astro
**Effort:** 1 day
**Component:** MI / Engagement Attribution
**Labels:** lwc, InterestingMoments

**Context.** Per [design-spec](./design-spec.md#design-tokens--slds-classes-used) — third dot tier with ★ icon overlay. Adds an "★ Interesting only" filter toggle to the campaign-strip filter row.

**ACs.**

- AC1: Touch dots with `Is_Interesting_Moment__c=true` render with the ★ icon (utility:star or utility:moments) — color + size + icon (three signals per [design-spec accessibility](./design-spec.md#accessibility)).
- AC2: Filter toggle dims non-IM touches to 10% opacity when active.
- AC3: Tooltip prefixes "★ Interesting:" and shows the rule's `Display_Name__c`.
- AC4: Jest tests pass; Lyric updates jsdoc.

**Pointers.** [design-spec](./design-spec.md) · [mockup.html](./mockup.html)

---

#### BSKY-116 — Sage security review: IM feature

**Type:** Task
**Assignee:** Sage Cloudy
**Effort:** 0.5 day
**Component:** MI / Engagement Attribution
**Labels:** security, BLOCKING

**Context.** Per [TEAM.md](../../.claude/agents/TEAM.md), Sage reviews all production code AND tests. IM has a smaller security surface than hierarchy but still needs sign-off on: FLS coverage on 2 new fields, CMDT-write permset gating, no AuraHandledException leakage.

**ACs.**

- AC1: FLS audit of new fields against the 3 permset tiers.
- AC2: Custom-perm `Marketing_Influence_Manage_Rules` gating verified.
- AC3: Sage's APPROVE comment on the PR(s) — required before merge.

---

#### BSKY-117 — Wren E2E smoke: IM end-to-end in dwood_z

**Type:** Task
**Assignee:** Wren Hootie
**Effort:** 0.5 day
**Component:** MI / Engagement Attribution
**Labels:** smoke, qa

**Context.** Per [feedback-atlas-verifies-before-uat](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_atlas_verifies_before_uat.md) — Wren writes the smoke; Atlas independently re-verifies before signing off to David.

**ACs.**

- AC1: Insert an `Engagement_Touch__c` matching a seed rule → flag set.
- AC2: Open modal → ★ dot visible in correct lane.
- AC3: Toggle "★ Interesting only" → non-IM dots dim.
- AC4: Atlas verifies with `Tooling API FieldDefinition` query that both new fields exist on the deployed object.

---

#### BSKY-118 — Docs: Marlowe (Apex) + Lyric (LWC) update for IM

**Type:** Task
**Assignee:** Marlowe Codey + Lyric Astro (parallel)
**Effort:** 0.5 day
**Component:** Documentation

**Context.** Per [TEAM.md workflow step 12](../../.claude/agents/TEAM.md#workflow-tdd) — docs ship on the same branch as the code.

**ACs.**

- AC1: ApexDoc on all new classes per [best-practices/apex.md](../../best-practices/apex.md).
- AC2: LWC jsdoc on new sub-components per [best-practices/lwc.md](../../best-practices/lwc.md).
- AC3: `docs/development/classes/InterestingMomentEvaluator.md` and `docs/development/components/miCampaignStrip.md` created.
- AC4: BRD/TDD lineage updated with "Interesting Moments shipped 2026-MM-DD" change-log entry per [feedback-change-log-discipline](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_change_log_discipline.md).

---

### FEATURE 2: Account Hierarchy — 10 tickets (BSKY-120 → BSKY-129)

#### BSKY-120 — Sage early-design consultation on HierarchyScopeResolver

**Type:** Task
**Assignee:** Sage Cloudy (with Atlas + Boomer)
**Effort:** 0.5 day
**Component:** MI / Engagement Attribution
**Labels:** security, design

**Context.** Per [brief-hierarchy "Permission/security"](./brief-account-hierarchy-engagement.md#permission--security-for-sage--non-trivial) — Sage is the LONG POLE. Atlas's adjusted dispatch order (per [atlas-decisions A7](./atlas-decisions.md#a7--approve-the-dispatch-order-in-tdd-11)) loops her in BEFORE Boomer writes Apex, not as a stamp afterward.

**ACs.**

- AC1: Sage reviews TDD §3.3 `HierarchyScopeResolver` design + the WITH USER_MODE traversal strategy.
- AC2: Sage signs off on the test-fixture matrix: parent-shared / sibling-private / 5-level deep / mixed-sharing.
- AC3: Sage's design notes captured in [decomposition-plan.md](./decomposition-plan.md) §risks if any concerns surface.
- AC4: Sage approves the "N accounts hidden by sharing" footnote semantics (count-only, no detail).

**Pointers.** [brief-hierarchy](./brief-account-hierarchy-engagement.md) · [TDD §3.3](./TDD.md#33-method-signatures-key-entries)

---

#### BSKY-121 — RED TESTS: HierarchyScopeResolver + EngagementTouchesSelector window query

**Type:** Story
**Assignee:** Pippa Codey → Wren Hootie
**Effort:** 2.5 days
**Component:** MI / Engagement Attribution
**Labels:** tests, AccountHierarchy

**Context.** Hierarchy testing is non-trivial because of the sharing scenarios per [TDD §7.2.1](./TDD.md#72-critical-test-scenarios). Test fixtures need multi-account hierarchies with mixed sharing rules.

**ACs.**

- AC1: Scope resolver tests cover: this-account / + children / whole hierarchy returns correct ID sets.
- AC2: User without read on a sibling — sibling silently excluded.
- AC3: 5-level depth caps; 6-level invocation falls back to async batch (or rejects per Sage's BSKY-120 call).
- AC4: Bulk: 200 parent records resolved in one transaction, no governor breach.
- AC5: `EngagementTouchesSelector.queryByAccountIdsAndWindow` WITH USER_MODE blocks unreadable records.
- AC6: 500-touch cap + 400-touch warn-log verified.
- AC7: Window math correct at boundary: 42 days = 42×24×60 minutes from `Datetime.now()`.
- AC8: All RED at commit; coverage ≥95%; 100% on USER_MODE boundary.

**Pointers.** [TDD §7](./TDD.md#7-test-strategy) · [feedback-persona-path-coverage](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_persona_path_coverage.md)

---

#### BSKY-122 — Apex: HierarchyScopeResolver + AccountHierarchySelector

**Type:** Story
**Assignee:** Boomer Codey
**Effort:** 2 days
**Component:** MI / Engagement Attribution
**Labels:** apex, AccountHierarchy

**Context.** Per [TDD §3.1 + §3.3](./TDD.md#3-apex-layer) — resolver gives `List<Id>` of accessible account IDs given a parent + scope; selector handles dot-notation traversal (5 levels max).

**ACs.**

- AC1: Resolver signature per TDD §3.3; passes BSKY-121 tests.
- AC2: `WITH USER_MODE` on every SOQL.
- AC3: `MI_Settings__mdt.Max_Hierarchy_Depth__c` honored (default 5).
- AC4: Fallback to two-pass when sibling-count > 200 at any level.
- AC5: `Logger.metric` on resolver entry + exit; per-transaction cache verified.

**Pointers.** [TDD §3.3](./TDD.md#33-method-signatures-key-entries) · [best-practices/architecture.md](../../best-practices/architecture.md)

---

#### BSKY-123 — Apex: extend EngagementTouchesSelector + EngagementDTO

**Type:** Story
**Assignee:** Boomer Codey → Tex Codey
**Effort:** 1 day
**Component:** MI / Engagement Attribution
**Labels:** apex, AccountHierarchy

**Context.** Selector adds `queryByAccountIdsAndWindow(Set<Id> accountIds, Integer windowDays)`. DTO extends with `scopeApplied`, `accountsVisible`, `accountsHiddenBySharing` per [TDD §3.2](./TDD.md#32-extended-classes).

**ACs.**

- AC1: Selector method passes BSKY-121 query tests.
- AC2: `EngagementDTO` shape preserves backward compatibility for v1 callers (existing fields untouched; new fields are optional).
- AC3: `EngagementDetailDTO` extends `EngagementDTO` with v2-only fields per TDD §3.2.
- AC4: Atlas review confirms no breaking change to the in-flight `mi-on-lead-investigation` work (R1).

**Pointers.** [EngagementDTO.cls](../../force-app/main/default/classes/engagement/EngagementDTO.cls) · [research/mi-on-lead-investigation.md](../research/mi-on-lead-investigation.md)

---

#### BSKY-124 — Apex: EngagementDetailController + EngagementDetailService + remaining services

**Type:** Story
**Assignee:** Boomer Codey
**Effort:** 2 days
**Component:** MI / Engagement Attribution
**Labels:** apex, AccountHierarchy, controller

**Context.** Per [TDD §3.1](./TDD.md#31-new-classes) — controller is a thin facade; service orchestrates; rollup calculator + DealTeamGap calculator are sub-services. Includes the AuraHandledException-with-Logger-correlation-ID pattern per [TDD §3.4](./TDD.md#34-permission--sharing-enforcement).

**ACs.**

- AC1: Controller `getEngagementDetail(parentId, scope, windowDays)` returns `EngagementDetailDTO`.
- AC2: Every catch boundary calls `Logger.error` and rethrows `AuraHandledException('Marketing Influence is temporarily unavailable. Error ID: ' + corrId)`.
- AC3: No raw exception text in any AuraHandledException message — Sage to verify.
- AC4: P95 < 1.5s in single-account scope; < 2s in 50-account hierarchy.
- AC5: `EngagementDetailController` Apex Class Access added to all 3 MI permsets.

**Pointers.** [TDD §3](./TDD.md#3-apex-layer)

---

#### BSKY-125 — LWC: miHierarchyScopeChip + hierarchy banner

**Type:** Story
**Assignee:** Coda Astro
**Effort:** 1.5 days
**Component:** MI / Engagement Attribution
**Labels:** lwc, AccountHierarchy

**Context.** Per [design-spec](./design-spec.md#interaction-spec) + [mockup.html](./mockup.html) — inline scope chip in header (3-mode popover); 1-line banner row when hierarchy active showing account-chip list + "N hidden by sharing" footnote.

**ACs.**

- AC1: Scope chip renders only on Account / Opp invocations (not Lead per brief §3.4).
- AC2: Popover shows 3 modes; selecting one emits `scopechange` event to parent.
- AC3: Banner row renders only when scope != THIS_ACCOUNT.
- AC4: Footnote shows ONLY count, never detail (Sage requirement from BSKY-120).
- AC5: Account chip click emits `accountdrilldown` event; modal refetches scoped to single account.
- AC6: Jest tests pass; accessibility AA per [design-spec accessibility](./design-spec.md#accessibility).

**Pointers.** [design-spec interaction-spec](./design-spec.md#interaction-spec) · [mockup.html](./mockup.html)

---

#### BSKY-126 — LWC: miGanttCanvas + miGanttLane + miGanttTimeAxis (sub-components)

**Type:** Story
**Assignee:** Coda Astro + Kit Astro (parallel sub-components)
**Effort:** 3 days
**Component:** MI / Engagement Attribution
**Labels:** lwc, AccountHierarchy, gantt

**Context.** The visual headline component. Per [design-spec §architecture](./design-spec.md#architecture) — sticky lane labels via `position: sticky; left: 0` in a shared horizontal scroll container; sticky time axis at top. CSS custom properties (`--mi-c`, `--camp-c`) for per-contact and per-campaign colors per [design-spec implementation-notes](./design-spec.md#implementation-notes-for-coda).

**ACs.**

- AC1: Renders correct dot count + dot tier (small / big / ★) given DTO.
- AC2: Lane click → emits `contactselect`; other lanes dim to 50%.
- AC3: Dot click → opens touch-detail popover.
- AC4: Time-to-x positioning is `(daysAgo / windowDays) * 100%`; resize is automatic (no pixel-fixed widths).
- AC5: Sticky lane label + sticky time axis verified across breakpoints in [design-spec responsive](./design-spec.md#responsive).
- AC6: CSS custom property cascade works inside `lightning-modal` shadow boundary (per Coda's [design-spec open-question](./design-spec.md#open-questions) — confirm or escalate).
- AC7: Jest tests pass; coverage on event emission.

**Pointers.** [design-spec implementation-notes](./design-spec.md#implementation-notes-for-coda) · [mockup.html](./mockup.html)

---

#### BSKY-127 — LWC: miCampaignStrip + miBottomCards + miStatePresenter

**Type:** Story
**Assignee:** Kit Astro + Robin Astro (parallel)
**Effort:** 2 days
**Component:** MI / Engagement Attribution
**Labels:** lwc, AccountHierarchy

**Context.** Per [TDD §4.1](./TDD.md#41-component-hierarchy) — three composite components: campaign strip (7-card horizontal), bottom 4 cards (activity feed / IM list / touches-by-account / deal-team gaps), state presenter (empty / loading / error switch). State presenter inlines the SLDS Desert + NoConnection SVGs per [atlas-decisions A2](./atlas-decisions.md#a2--static-resource-miillustrations-bundle-vs-inline-svg-only).

**ACs.**

- AC1: Campaign strip: click filters Gantt; "All campaigns" overview card on far left.
- AC2: Bottom cards: each renders correct DTO subset; Deal Team Gaps surfaces inline `+` buttons.
- AC3: State presenter switches loading → data → empty / error correctly.
- AC4: Empty state inlines `desert.svg` body for SLDS theming.
- AC5: Error state shows correlation-ID line; retry button + scope-down option per [mockup-error.html](./mockup-error.html).
- AC6: Loading state honors `prefers-reduced-motion`.
- AC7: Jest tests pass.

**Pointers.** [TDD §4](./TDD.md#4-lwc-layer) · [mockup-empty.html](./mockup-empty.html) · [mockup-error.html](./mockup-error.html)

---

#### BSKY-128 — Sage security review: hierarchy feature (BLOCKING)

**Type:** Task
**Assignee:** Sage Cloudy
**Effort:** 1 day
**Component:** MI / Engagement Attribution
**Labels:** security, BLOCKING, LONG-POLE

**Context.** Per [brief-hierarchy](./brief-account-hierarchy-engagement.md) — Sage's gate is the LONG POLE for this feature. Reviews: every SOQL has WITH USER_MODE; sharing-rule respect for ancestors AND descendants; footnote count accuracy (no leak); AuraHandledException message bodies have no internal text.

**ACs.**

- AC1: All-code security review per [TEAM.md PR review discipline](../../.claude/agents/TEAM.md#pr-review-discipline).
- AC2: Verify sibling-private touches are silently excluded AND not detectable via timing / count drift.
- AC3: AuraHandledException audit — every catch path covered.
- AC4: Sage signs APPROVE on every PR in this feature.

**Pointers.** [brief-hierarchy permission-security](./brief-account-hierarchy-engagement.md#permission--security-for-sage--non-trivial)

---

#### BSKY-129 — Wren E2E smoke + Atlas verification: hierarchy

**Type:** Task
**Assignee:** Wren Hootie + Atlas (independent verification)
**Effort:** 1 day
**Component:** MI / Engagement Attribution
**Labels:** smoke, qa

**Context.** Per [feedback-atlas-verifies-before-uat](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_atlas_verifies_before_uat.md) — Atlas re-runs the smoke independently. Hierarchy is the high-risk feature; this verification is mandatory.

**ACs.**

- AC1: Wren creates a 3-level hierarchy fixture in `dwood_z` (parent + 2 children + 1 sibling-private).
- AC2: Wren as fully-permissioned user: sees all 3+sibling touches with hierarchy mode.
- AC3: Wren as restricted user (no sibling access): sees only 3 accounts' touches; footnote shows "1 account hidden."
- AC4: Atlas runs Playwright against the deployed scratch org, opens the modal at each scope, screenshots.
- AC5: Atlas queries `FieldDefinition` to verify no schema-naming-drift (per `Occurred_At__c` lesson).

---

#### BSKY-130 — Docs: Marlowe (Apex) + Lyric (LWC) for hierarchy

**Type:** Task
**Assignee:** Marlowe Codey + Lyric Astro (parallel)
**Effort:** 0.5 day
**Component:** Documentation

**ACs.** Analogous to BSKY-118.

---

### CROSS-CUTTING (3 more tickets after both features)

#### BSKY-140 — Dash permset deploy + Otto persona-PSG composition guide

**Type:** Task
**Assignee:** Dash Earnie + Otto Cloudy
**Effort:** 0.5 day
**Component:** DevOps

**Context.** Per [TDD §8.3](./TDD.md#83-permset-rollout) + [feedback-owd-private-permset-architecture](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_owd_private_permset_architecture.md). Permsets deploy first; Mira assigns to test users; Otto writes the Manage-Assignments composition doc naming target Persona PSGs.

---

#### BSKY-141 — Iris gate-2 delivery acceptance (both features)

**Type:** Task
**Assignee:** Iris Ruth
**Effort:** 1 day
**Component:** MI / Engagement Attribution
**Labels:** gate-2, acceptance

**Context.** Per [TEAM.md workflow step 14](../../.claude/agents/TEAM.md#workflow-tdd). Iris walks each BRD AC against the live feature in `dwood_z`. Atlas signs the release ticket only after Iris's ✅.

**ACs.** Every BRD §4.1–4.4 AC verified in the deployed org.

---

#### BSKY-142 — Atlas release sign-off

**Type:** Task
**Assignee:** Atlas
**Effort:** 0.25 day
**Component:** MI / Engagement Attribution
**Labels:** release, signoff

**Context.** Per Atlas charter — sign the release ticket attesting that all five lanes are green.

**ACs.** Release v0.X signed: Apex ✓ / LWC ✓ / Tests ✓ / Security ✓ / Docs ✓ / Deploy ✓.

---

## 3. Sequencing plan

### Phase 0 — Gate-1 prep (Day 0–1)

- BSKY-101 (Iris locks spec)
- BSKY-102 (Marlowe corrects TDD)
- BSKY-103 (Helix schema review)

**Cannot dispatch Phase 1 until BSKY-101 closes.**

### Phase 1 — Feature 1: Interesting Moments (Day 1–5)

1. BSKY-110 (Boomer schema) → in parallel with BSKY-111 (Pippa red tests)
2. BSKY-112 / 113 / 114 (Boomer / Tex Apex) — green the tests
3. BSKY-115 (Coda / Kit LWC) — parallel with Apex work
4. BSKY-116 (Sage) → in parallel with BSKY-117 (Wren smoke)
5. BSKY-118 (docs)

**Feature 1 estimate: 5 working days.**

### Phase 2 — Feature 2: Account Hierarchy (Day 5–12)

1. BSKY-120 (Sage early-design consultation) — kicks off Day 5
2. BSKY-121 (Pippa red tests) — parallel with BSKY-122 (Boomer Apex resolver)
3. BSKY-123 / 124 (Boomer extensions + controller)
4. BSKY-125 / 126 / 127 (Coda + Kit + Robin LWC, parallel sub-components)
5. BSKY-128 (Sage BLOCKING) — runs over PR review window, long-pole
6. BSKY-129 (Wren + Atlas smoke)
7. BSKY-130 (docs)

**Feature 2 estimate: 7 working days.**

### Phase 3 — Wrap (Day 12–13)

- BSKY-140 (Dash + Otto permset rollout)
- BSKY-141 (Iris gate-2)
- BSKY-142 (Atlas signoff)

**Total estimate: ~13 working days (~2.5 sprints).**

---

## 4. Parallel-dispatch plan

Per [feedback-lead-verifies-team](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_lead_verifies_team.md) — independent streams ALWAYS dispatch in parallel.

### Day 0–1 parallel:

- Iris (BSKY-101) || Marlowe (BSKY-102) || Helix (BSKY-103) || Nova (BSKY-104 standby)

### Day 1–3 parallel (Feature 1):

- **Stream A (schema):** Boomer (BSKY-110)
- **Stream B (tests):** Pippa designs → Wren writes (BSKY-111) — can start AS SOON AS BSKY-101 closes, in parallel with BSKY-110
- **Stream C (LWC):** Coda starts static-resource integration in `miStatePresenter` while waiting for Apex DTO finalization

### Day 3–5 parallel (Feature 1 finish):

- Boomer + Tex green the tests (BSKY-112/113/114) || Coda + Kit ship LWC (BSKY-115) || Sage starts BSKY-116 as PRs open

### Day 5–7 parallel (Feature 2 design + early dev):

- **Stream A (Sage early-design):** BSKY-120 — Sage + Atlas + Boomer pair on resolver design
- **Stream B (red tests):** Pippa + Wren start hierarchy fixtures (BSKY-121)
- **Stream C (Coda starts UI shell):** Coda builds scope-chip popover + banner skeleton (BSKY-125) — does NOT need Apex done; can mock the DTO

### Day 7–10 parallel (Feature 2 build):

- **Apex stream:** Boomer ships resolver + selector + controller (BSKY-122/123/124) || tests turn green
- **LWC stream:** Coda + Kit + Robin ship sub-components (BSKY-126/127) in parallel
- **Security stream:** Sage code-reviews as PRs open (BSKY-128)

### Day 10–12 parallel (Feature 2 finish):

- Wren writes smoke (BSKY-129) || Atlas re-verifies independently || Marlowe + Lyric docs (BSKY-130)

### Day 12–13:

- Dash permset deploy + Otto comp doc || Iris gate-2 acceptance walkthrough || Atlas signoff

**Total worker-hours saved by parallelism vs. strict sequential:** ~8 working days (sequential would be ~21d; parallel is ~13d).

---

## 5. Risk register

### R1 — `mi-on-lead-investigation` extends EngagementDTO concurrently

**Detected by:** Atlas pre-flight (verified [docs/research/mi-on-lead-investigation.md §3, §5](../research/mi-on-lead-investigation.md))

**Description:** Iris's in-flight Lead-page investigation also extends `EngagementDTO` (or forks to `AnchorEngagementDTO`). v2 adds `campaignRollups`, `interestingMoments`, `dealTeamGaps`, `scopeApplied`, `accountsVisible`, `accountsHiddenBySharing` to the same DTO. If both ship without coordination, the LWC consumers will disagree on shape.

**Mitigation:** Atlas pairs with Iris on the DTO fork question (`AnchorEngagementDTO` vs. extend `EngagementDTO`) BEFORE BSKY-123 (the DTO-extension ticket) opens. Recommendation: extend `EngagementDTO` with optional fields (additive only; v1 callers ignore new fields). If Iris's analysis concludes Lead/Contact need a sibling DTO, the v2 work uses `EngagementDetailDTO extends EngagementDTO` per TDD §3.2 and the two streams stay decoupled.

**Owner:** Atlas

### R2 — LWC custom-property cascade inside lightning-modal shadow boundary

**Detected by:** Nova (called out in [design-spec open-questions](./design-spec.md#open-questions))

**Description:** The design relies on inline `style="--mi-c: ...; --camp-c: ..."` per-row to color contacts and campaigns. Inside `lightning-modal`'s shadow DOM, CSS custom property inheritance is normally fine — but the specifics depend on whether the LWC uses `lightning-modal` (the base mixin) or a custom modal wrapper. Coda needs to verify on Day 1.

**Mitigation:** Coda's first LWC ticket (BSKY-115 or BSKY-125, whichever ships first) includes a CSS-cascade probe — render the mockup HTML inside `lightning-modal`, verify dot colors render correctly. If cascade is broken, fall back to inline `background-color` on each dot (lossier but bulletproof). Escalate to Atlas if neither works.

**Owner:** Coda Astro

### R3 — SLDS illustration SVG rendering inside shadow DOM

**Detected by:** Atlas pre-flight

**Description:** The SLDS canonical illustrations rely on `slds-illustration__stroke-primary` / `__fill-secondary` classes to pick up theme tokens. Inside a shadow-DOM-encapsulated LWC, those global SLDS classes may not penetrate — the SVG renders, but without the SLDS theme colors. Per atlas-decisions A2 we ship BOTH approaches: external URL via static resource (no class theming) + inline SVG (class theming should work because the SLDS sheet is loaded at the root).

**Mitigation:** BSKY-127's miStatePresenter ticket explicitly tests both render paths and locks the one that renders correctly in `dwood_z`. Lyric documents the chosen pattern.

**Owner:** Coda + Lyric

### R4 — Hierarchy-resolver SOQL governor limits at scale

**Detected by:** Atlas (and called out in [brief-hierarchy §schema-architecture](./brief-account-hierarchy-engagement.md#schema--architecture-implications-for-atlas))

**Description:** 5-level hierarchy × 20-children-per-level = 3.2M-account worst case. The TDD says "fall back to async batch" at >200 siblings per level — but Boomer needs to make that fallback actually work, not just say it does. Bulk patterns + governor-limit-aware code.

**Mitigation:** BSKY-121's bulk test (AC4: 200 parents resolved in one transaction) is the canary. Boomer's BSKY-122 includes the fallback path with its own test. Helix Genie's BSKY-103 schema review explicitly comments on the depth-cap CMDT setting.

**Owner:** Boomer + Helix Genie

### R5 — Sage's hierarchy review extends timeline

**Detected by:** Atlas (brief explicitly flags Sage as long-pole)

**Description:** Hierarchy traversal under OWD-Private is exactly the class of feature that leaks data when implemented naively. Sage's review will likely surface at least one finding that requires a re-spin. If it surfaces only in BSKY-128 (post-PR), we burn 2–3 days.

**Mitigation:** BSKY-120 — Sage early-design consultation BEFORE Boomer writes Apex. Atlas's adjusted dispatch order (atlas-decisions A7) builds this in. If Sage spots a design-level issue in BSKY-120, the cost is 0.5d of design rework, not 3d of code rework.

**Owner:** Atlas (dispatches BSKY-120 first), Sage

### R6 — Schema-naming-drift recurrence

**Detected by:** Atlas pre-flight

**Description:** The TDD still has `Touch_Datetime__c` in two places — the same field-name drift that caused the 2026-05-14 smoke-test miss. If a worker reads the TDD instead of the actual field metadata, they'll inherit the bug.

**Mitigation:** BSKY-102 corrects the TDD as the FIRST task in Phase 0. Every ticket below cites the actual `Occurred_At__c.field-meta.xml` path, not the TDD value. Atlas verifies field names against schema before signing off any ticket per [feedback-atlas-verifies-before-uat](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_atlas_verifies_before_uat.md).

**Owner:** Atlas + Marlowe

### R7 — Wren's smoke is a hypothesis, not proof (recurring failure mode)

**Detected by:** Atlas memory ([feedback-atlas-verifies-before-uat](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_atlas_verifies_before_uat.md))

**Description:** Wren's smoke-test reports have caused at least one false-green in this codebase. Atlas signing off on Wren's report without re-verification is the failure mode the rule exists to prevent.

**Mitigation:** Every smoke ticket (BSKY-117, BSKY-129) includes Atlas's independent verification as an AC — query the deployed schema, Playwright the actual page, screenshot it. Not optional.

**Owner:** Atlas

### R8 — Iris hasn't yet locked the empty-state, default-scope, and default-sort decisions (D1/D2/D3)

**Detected by:** Atlas in BRD §7 review

**Description:** Three UX questions with Atlas recommendations but no David call. The LWC tickets (BSKY-115, BSKY-125, BSKY-126, BSKY-127) cannot lock acceptance criteria until these resolve.

**Mitigation:** BSKY-101 (Iris-with-David spec lock) is Phase 0; no LWC dev starts until it closes. Atlas surfaces D1/D2/D3 explicitly to David alongside this plan.

**Owner:** Iris + David

---

## 6. Open questions for David (alongside this plan)

1. **D1** — Modal opens with empty state, or right-rail panel suppresses click? (Atlas recommends: modal opens.)
2. **D2** — Default hierarchy scope on parent accounts: "This account only" or "+ Children"? (Atlas recommends: This account only.)
3. **D3** — Default contact-lane sort: first-touch ASC / last-touch DESC / touch-count DESC? (Atlas recommends: touch-count DESC.)
4. **R1** — Do you want Atlas + Iris to pair on the `EngagementDTO` vs `AnchorEngagementDTO` fork decision NOW, or defer until BSKY-123 opens? (Atlas recommends: now — it's a 30-minute conversation that saves a re-spin.)
5. **Calling-card demo account** — is your calling-card demo account one of the >500-touch hierarchies? If yes, R4 cap may need adjustment.

---

## 7. Dispatch hold

Per the dispatch brief: **NO worker dispatch until David acknowledges this plan.** Atlas waits.

Once David ack's:

1. BSKY-101 to Iris immediately (with D1/D2/D3 for her to take to David in the same session).
2. BSKY-102 to Marlowe immediately (TDD correction is independent of Iris).
3. BSKY-103 to Helix immediately (schema review is independent).
4. BSKY-104 to Nova (standby).

Then Phase 1 dispatches per §3 sequencing.

---

— Atlas, 2026-05-16
