# Engagement Attribution — Documentation

Engagement Attribution captures HubSpot (and other source-system) marketing-engagement events, resolves them to Salesforce Contacts/Leads/Accounts, routes them into per-Opportunity signals via priority-ordered metadata rules, and surfaces the result as a right-rail panel on the Account and Opportunity record pages. The Apex side is a three-layer Selector / Service / Domain stack with a REST endpoint at `/services/apexrest/engagement/touches/`; the UI side is four LWCs. The build is a 2GP unlocked package shipping out of `force-app/`.

## Reading order

| You are…                    | Read in this order                                                                                                                                                                                                                                                                                                                                      |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A new Apex dev**          | [development/onboarding.md](development/onboarding.md) → [architecture/overview.md](architecture/overview.md) → [development/apex-conventions.md](development/apex-conventions.md) → [development/code-review-checklist.md](development/code-review-checklist.md) → [development/classes/](development/classes/) per-class reference                    |
| **A new admin**             | [users/DEMO.md](users/DEMO.md) (the 4-beat walkthrough) → [architecture/overview.md](architecture/overview.md) → [operations/apex-invocation-runbook.md](operations/apex-invocation-runbook.md) for triage                                                                                                                                              |
| **A new test architect**    | [testing/test-architect-brief.md](testing/test-architect-brief.md) → [testing/test-strategy.md](testing/test-strategy.md) → [testing/test-audit-2026-05-12.md](testing/test-audit-2026-05-12.md) → [testing/test-plan-2026-05-12.md](testing/test-plan-2026-05-12.md)                                                                                   |
| **A new security reviewer** | [architecture/overview.md](architecture/overview.md) → [development/apex-conventions.md](development/apex-conventions.md) (sharing + USER_MODE) → [development/classes/EngagementInboundRest.md](development/classes/EngagementInboundRest.md) → [architecture/PHASE1-HANDOFF.md](architecture/PHASE1-HANDOFF.md) for the historical scope/decision log |

## Top-level entry points

- **Architecture & decisions** — [architecture/overview.md](architecture/overview.md), [architecture/decisions/](architecture/decisions/), [architecture/PHASE1-HANDOFF.md](architecture/PHASE1-HANDOFF.md), [architecture/BRD-Engagement-Attribution.docx](architecture/BRD-Engagement-Attribution.docx), [architecture/Engagement-Attribution-Demo.pptx](architecture/Engagement-Attribution-Demo.pptx).
- **Development** — [development/onboarding.md](development/onboarding.md), [development/apex-conventions.md](development/apex-conventions.md), [development/code-review-checklist.md](development/code-review-checklist.md), [development/classes/](development/classes/) (Apex), `development/components/` (LWC — owned by Lyric), [development/lwc-conventions.md](development/lwc-conventions.md) (Lyric).
- **Operations** — [operations/apex-invocation-runbook.md](operations/apex-invocation-runbook.md). Deploy runbook + scratch-org lifecycle + packaging are owned by Dash.
- **Testing** — [testing/test-strategy.md](testing/test-strategy.md), [testing/test-plan-2026-05-12.md](testing/test-plan-2026-05-12.md), [testing/test-audit-2026-05-12.md](testing/test-audit-2026-05-12.md), [testing/test-architect-brief.md](testing/test-architect-brief.md).
- **Users / demo** — [users/DEMO.md](users/DEMO.md), [users/wireframes/](users/wireframes/).

## Code conventions

Code authoring rules live in [best-practices/](../best-practices/) at the repo root — [apex.md](../best-practices/apex.md), [apex-tests.md](../best-practices/apex-tests.md), [lwc.md](../best-practices/lwc.md), [architecture.md](../best-practices/architecture.md). The docs in [development/](development/) summarize and link; they do not duplicate.

## Ownership

| Surface                                                                                                                                              | Owner                     |
| ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| `architecture/`, `development/classes/`, `development/apex-conventions.md`, `operations/apex-invocation-runbook.md`, `users/DEMO.md` (Apex sections) | Marlowe (Apex docs)       |
| `development/components/`, `development/lwc-conventions.md`, `users/DEMO.md` (UI sections)                                                           | Lyric (LWC docs)          |
| `testing/`                                                                                                                                           | Pippa (Sr Test Architect) |
| `operations/deploy-runbook.md`, `operations/scratch-org-lifecycle.md`, `operations/packaging.md`                                                     | Dash (DevOps)             |
| `security/`                                                                                                                                          | Sage (Security Architect) |

See [`.claude/agents/TEAM.md`](/Users/david/Work/Zelis/.claude/agents/TEAM.md) for the full org chart and PR review flow.
