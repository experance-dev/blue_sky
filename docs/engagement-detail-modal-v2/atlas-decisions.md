# Atlas decisions — Engagement Detail Modal v2

|             |                                                                                                                      |
| ----------- | -------------------------------------------------------------------------------------------------------------------- |
| **Owner**   | Atlas                                                                                                                |
| **Date**    | 2026-05-16                                                                                                           |
| **Context** | TDD §10 open items resolved before team dispatch. Companion doc to [decomposition-plan.md](./decomposition-plan.md). |
| **Status**  | Atlas-decided / David-punted as noted per row.                                                                       |

This doc closes the seven §10 open items from the [TDD](./TDD.md) so dispatch isn't blocked. Where the decision is mine (architectural), I make it and document the rationale. Where it requires David's business call, I punt it explicitly with a recommendation.

---

## A1 — Approve the seven new Apex classes + existing-class extensions

**Decision:** APPROVED with three corrections.

**Corrections to TDD §3:**

1. **Existing selector is `EngagementTouchesSelector`** (plural), not `EngagementTouchSelector` (singular). New methods extend the existing class; do not invent a singular twin.
2. **Existing schema uses `Occurred_At__c`** as the touch datetime, NOT `Touch_Datetime__c`. The TDD §6 worst-case-sizing table and any query examples must be corrected before dev starts. This is the same field-naming drift that caused the 2026-05-14 smoke-test miss per [feedback-atlas-verifies-before-uat](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_atlas_verifies_before_uat.md) — flag it loudly to every worker.
3. **Existing controller is `EngagementController`**, which already returns `EngagementDTO`. The v2 facade `EngagementDetailController` is a new sibling — not a rename. v1 keeps powering the right-rail panel; v2 powers the new modal. Boomer's first ticket clarifies the boundary in the class header.

**Rationale:** Seven new classes is the right shape — Selector / Service / Domain layering per [best-practices/architecture.md](../../best-practices/architecture.md). One controller-facade keeps the `@AuraEnabled` surface minimal. The `HierarchyScopeResolver` deserves its own class because its sharing surface needs its own test class and its own Sage review.

## A2 — Static-resource `miIllustrations` bundle vs inline-SVG-only

**Decision:** Ship the `miIllustrations` static resource (already in repo) AND inline-SVG-render in the LWC.

**Rationale:** The bundle is already there, costs nothing to keep, and gives admins a path to swap illustrations without an LWC redeploy. The LWC inlines for the SLDS-class theming (stroke / fill classes inherit theme tokens correctly only when inline). Use the static resource as the canonical source-of-truth; the LWC's inline-SVG template imports the same SVG body verbatim. Lyric documents the dual-pattern.

## A3 — Permset ladder naming

**Decision:** USE EXISTING PERMSETS. Do not create a new ladder.

The codebase already has:

- `Additional_Permissions_Marketing_Influence_View`
- `Additional_Permissions_Marketing_Influence_Power_User`
- `Additional_Permissions_Marketing_Influence_Admin`
- `Additional_Permissions_Marketing_Influence_Integration`

These follow the Zelis convention per [feedback-owd-private-permset-architecture](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_owd_private_permset_architecture.md). v2 tickets EXTEND them — adding FLS on the two new fields, adding Apex Class Access on `EngagementDetailController`, adding the new custom permissions. The TDD §5.2 wording "new MI permsets" is wrong; correct it to "extend existing MI permsets."

**Rationale:** Creating a parallel ladder fractures admin assignment and breaks the Zelis Persona PSG composition story. Extend, don't duplicate (same rule that applies internally per [feedback-extend-not-modify-third-party](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_extend_not_modify_third_party.md)).

## A4 — 500-touch cap sufficient for hierarchy?

**Decision:** Keep the 500 cap for v2. Add a `Logger.warn` at 400.

**Rationale:** v1's cap is 500. Hierarchy fan-out is the new pressure, but at the 5-level / 20-children-per-level worst case the design already says "fall back to async batch" — which means the synchronous DTO path will never exceed the 500-touch synchronous budget. If real usage shows the cap clipping engagement at the largest enterprise accounts, we revisit in a follow-up; we don't lift the cap on v2 launch without Sage signing off on the broader DTO-serialization-size implications.

**David-punt:** If David's calling-card demo account is one of the 4+ enterprise hierarchies with >500 touches in a 6-week window, raise this with David before the demo so we can adjust the seeded test data or the cap, but the production default stays 500.

## A5 — Rule-evaluation timing: sync trigger vs async Platform Event

**Decision:** **Sync trigger** for v2. Async Platform Event deferred to a future enhancement IF telemetry shows trigger budget pressure.

**Rationale:** Per [best-practices/architecture.md](../../best-practices/architecture.md) — sync is the simpler, more debuggable default. `InterestingMomentEvaluator` is a pure function with cached-per-transaction rule list; the projected 75 touches × 20 rules = 1500 iterations is well under any governor. Async adds a Platform Event surface, a subscriber class, an at-least-once-delivery semantics question, and a "user-visible flag arrives N seconds late" UX hit. None of those are worth paying without evidence we'd benefit. Boomer's ticket includes `Logger.metric` traces on the evaluator so we have the data to revisit.

## A6 — Confirm `Logger.cls` permset access for callers

**Decision:** Confirmed. Logger is shipped via CSI-7162 utility merge per the post-merge baseline; every Apex caller has access by virtue of being in the same managed-context. No permset action required for the controller's `Logger.error` calls. Sage validates that `Logger_Log__c` itself has the right OWD + admin-only read access in her standing security review — that's separate from MI v2.

## A7 — Approve the dispatch order in TDD §11

**Decision:** APPROVED with one adjustment.

**Adjustment:** Move **Iris (open Qs resolution)** and **Sage (early design loop-in for hierarchy)** ahead of Pippa. Tests can't go red against ACs that aren't yet locked, and Sage's hierarchy security review needs to shape the resolver's design — not be applied as a stamp afterward.

Revised dispatch order:

1. **Iris** resolves BRD §7 open questions (gate-1 spec lock for both features).
2. **Sage** consults on Hierarchy architectural shape during Feature-2 design (parallel to Feature-1 dev).
3. **Pippa** writes red tests against the locked ACs.
4. **Boomer** writes Apex; **Coda** writes LWC (parallel where they don't share contract).
5. **Wren** smoke-tests; **Marlowe / Lyric** docs.
6. **Dash** deploys (held until David clears per [feedback-hold-deploys-default](../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_hold_deploys_default.md)).
7. **Iris** gate-2 delivery acceptance.

---

## Items punted to David (3)

These need David's business or calling-card-strategy call. I have recommendations but don't unilaterally decide.

### D1 — BRD §7.1 Empty-state behavior

**Question:** When zero engaged contacts at this account, does the modal still open (showing the empty state per [mockup-empty.html](./mockup-empty.html)), or does the right-rail panel suppress the click-through entirely?

**Atlas recommendation:** Modal opens. The empty state is part of the calling-card story — it tells the rep "here's what would show up if engagement existed" and seeds the next action. Suppressing the click is friction; users wonder if the feature is broken.

### D2 — BRD §7.2 Default hierarchy scope on parent accounts

**Question:** When invoked on an account that has child accounts, default to "This account only" or "+ Children"?

**Atlas recommendation:** **This account only.** The hierarchy mode is opt-in by design — that's the whole "rep decides when hierarchy matters" sales-judgment story from the brief. Auto-expanding silently includes touches the rep didn't ask for and inflates the engagement story. Make hierarchy a deliberate one-click toggle.

### D3 — BRD §7.3 Default contact lane sort order

**Question:** First-touch ascending (engagement-builds), last-touch descending (recency), or touch-count descending (heaviest first)?

**Atlas recommendation:** **Touch-count descending.** The first-read question is "who's most engaged?" Heaviest first answers that in one glance. Recency-sort buries reps who engaged early and are now ghosted; first-touch-ascending is a story for a coaching session, not a pre-call scan. Touch-count descending is also the most legible in screenshots — calling-card friendly.

---

## Schema-naming-drift correction (do this before any ticket goes out)

The TDD has `Touch_Datetime__c` in three places (§3.2 query example, §6 worst-case sizing) — the actual field is `Occurred_At__c`. Marlowe corrects the TDD as a pre-ticket cleanup task (5 minutes); Iris reviews tickets against the corrected TDD only.

This is the same gap that caused the 2026-05-14 smoke-test failure. Atlas verifies field names against actual schema in `dwood_z` (or `force-app/main/default/objects/Engagement_Touch__c/fields/`) before signing off on any ticket that mentions a field.

---

— Atlas, 2026-05-16
