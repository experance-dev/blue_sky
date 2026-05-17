# Atlas Dispatch Prompt — Engagement Detail Modal v2

**Purpose:** ready-to-fire prompt that David (or any orchestrator) can use to dispatch Atlas to decompose this feature and route his team. Spawn Atlas via the `Agent` tool with `subagent_type: 'atlas'` and paste the prompt body below.

---

## Prompt body

```
David has approved the Engagement Detail Modal v2 feature. All the artifacts
you need are ready in docs/. Your job: decompose this into tickets, route to
your team per TEAM.md, verify nothing breaks the in-flight CSI-7162 or
existing MI v1 work, and report a decomposition plan back BEFORE dispatching
workers.

READ FIRST — in this order:

1. docs/architecture/BRD-Engagement-Detail-Modal-v2.md
   Business intent, personas, acceptance criteria, open questions for Iris,
   constraints (OWD-Private permsets, no-real-emails-tests, etc.).

2. docs/architecture/TDD-Engagement-Detail-Modal-v2.md
   Technical design — component map, data model (2 new fields + 1 new CMDT),
   7 new Apex classes, LWC sub-component breakdown, permset ladder,
   performance plan, test strategy, deployment sequencing.
   Section 10 has the open items requiring YOUR decisions before dispatch.
   Section 11 is the suggested routing order.

3. docs/wireframes/engagement-timeline.md
   Nova's design spec — interaction patterns, accessibility, copy strings,
   SLDS tokens used. Mocks live next to it.

4. docs/wireframes/engagement-timeline.html
   The canonical visual mockup. Open in a browser to see what we're building.
   State variants: -empty.html, -loading.html, -error.html. Popover patterns:
   -popovers.html.

5. docs/briefs/brief-interesting-moments.md
   Feature-1 (ship first — lower risk, no sharing surface).

6. docs/briefs/brief-account-hierarchy-engagement.md
   Feature-2 (ship second — Sage's review is the LONG POLE, loop her in
   DURING DESIGN not just code review).

7. docs/wireframes/future-enhancements.md
   18 items deferred. Not v2 scope but useful for understanding what we
   said NO to.

8. force-app/main/default/staticresources/miIllustrations/
   Standard-SLDS canonical illustrations (Desert, NoConnection). Ship as a
   static-resource bundle. Preview at .../miIllustrations/preview.html.

VERIFY BEFORE DISPATCH:

- Nothing in this design conflicts with CSI-7162 utility-class merges.
- Existing engagementDetailModal LWC + EngagementDTO + Engagement_Touch__c
  schema are the starting points; we EXTEND, never duplicate.
- Permset architecture follows the OWD-Private model per the memory
  feedback file (Additional Permissions - <Feature> <Tier> naming).
- No personal-lib (Utilities.cls, DMLManager, Logger, TestFactory*) edits;
  all new helpers in feature-scoped classes.
- All Apex class headers attribute @author David Wood.
- Tests follow TDD (red first via Pippa); ≥95% coverage; no real emails;
  no test cheating.
- Hold all deploys to dwood_z until David explicitly clears (per memory).

DECOMPOSITION TASKS:

A) Resolve TDD §10 open items — pick a path on each. If anything needs
   David's call, write a tight summary in docs/architecture/atlas-decisions.md
   and ping him with the specific question.

B) Decompose §11's routing into Jira tickets. Each ticket needs:
   - One-paragraph context (drawing from BRD section)
   - Test-assertable ACs (drawing from BRD §4)
   - Pointers to design + brief + memory rules
   - Effort estimate (drawing from briefs)
   - Assignee suggestion (per TEAM.md)

C) Sequencing plan:
   - Interesting Moments BEFORE Account Hierarchy (per briefs).
   - Inside each feature: Iris-spec → Pippa-red-tests → Boomer-Apex →
     Coda-LWC → Sage-review → Wren-smoke → Marlowe/Lyric-docs →
     Dash-deploy → Iris-acceptance.

D) Identify any work that can run in PARALLEL (per memory rule on
   parallel-first dispatch). For example: while Boomer writes Apex,
   Coda can start the static-resource integration; while Sage reviews
   the hierarchy resolver, Wren can prep Playwright fixtures.

E) Flag any RISK Nova or Iris haven't surfaced — e.g.:
   - LWC custom-property cascade inside lightning-modal shadow boundary
     (will the per-contact color tokens work?)
   - SLDS illustration SVG rendering inside shadow DOM
   - Hierarchy-resolver SOQL governor limits at scale

DELIVERABLE BACK TO DAVID:

A single document at docs/architecture/decomposition-plan-v2.md containing:
1. Open items resolved (with rationale) or open items punted to David.
2. The Jira ticket list (one section per ticket, ready to bulk-create).
3. The sequencing plan with dates if you have signal.
4. The parallel-work plan.
5. The risk register (with Nova / Coda / Sage pinged for input where
   relevant).

Do NOT dispatch any worker until David acknowledges this plan. Atlas
verifies before UAT (per memory) — atlas-verifies-the-plan-before-dispatch is
the same principle applied to design.

GO.
```

---

## Notes for whoever fires this

- **Spawn Atlas as the subagent:** `Agent` tool with `subagent_type: 'atlas'`.
- **Atlas owns the report-back.** He should not fire any worker until David acknowledges his plan.
- **If Atlas pings back with questions for David**, route them to Iris (PO/SA) first — Iris's gate-1 is the upstream blocker per [TEAM.md](../../.claude/agents/TEAM.md).
- **Atlas is the production-code reviewer**, so he's the last gate before merge — that's downstream. This dispatch only triggers the decomposition.
