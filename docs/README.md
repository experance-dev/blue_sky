# Zelis — Documentation Index

This `docs/` tree carries documentation for two in-flight features that ship together on the `feature/engagement-attribution` consolidation branch:

- **Engagement Attribution (MI)** — primary feature on this branch.
- **CSI-7162 Jira Push Notifications** — Apex-only Opportunity → Jira pipeline merged in from `main`.

Jump to the feature you're working on.

---

## Engagement Attribution — Documentation

Engagement Attribution captures HubSpot (and other source-system) marketing-engagement events, resolves them to Salesforce Contacts/Leads/Accounts, routes them into per-Opportunity signals via priority-ordered metadata rules, and surfaces the result as a right-rail panel on the Account and Opportunity record pages. The Apex side is a three-layer Selector / Service / Domain stack with a REST endpoint at `/services/apexrest/engagement/touches/`; the UI side is four LWCs. The build is a 2GP unlocked package shipping out of `force-app/`.

### Reading order

| You are…                    | Read in this order                                                                                                                                                                                                                                                                                                                                      |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A new Apex dev**          | [development/onboarding.md](development/onboarding.md) → [architecture/overview.md](architecture/overview.md) → [development/apex-conventions.md](development/apex-conventions.md) → [development/code-review-checklist.md](development/code-review-checklist.md) → [development/classes/](development/classes/) per-class reference                    |
| **A new admin**             | [users/DEMO.md](users/DEMO.md) (the 4-beat walkthrough) → [architecture/overview.md](architecture/overview.md) → [operations/apex-invocation-runbook.md](operations/apex-invocation-runbook.md) for triage                                                                                                                                              |
| **A new test architect**    | [testing/test-architect-brief.md](testing/test-architect-brief.md) → [testing/test-strategy.md](testing/test-strategy.md) → [testing/test-audit-2026-05-12.md](testing/test-audit-2026-05-12.md) → [testing/test-plan-2026-05-12.md](testing/test-plan-2026-05-12.md)                                                                                   |
| **A new security reviewer** | [architecture/overview.md](architecture/overview.md) → [development/apex-conventions.md](development/apex-conventions.md) (sharing + USER_MODE) → [development/classes/EngagementInboundRest.md](development/classes/EngagementInboundRest.md) → [architecture/PHASE1-HANDOFF.md](architecture/PHASE1-HANDOFF.md) for the historical scope/decision log |

### Top-level entry points

- **Architecture & decisions** — [architecture/overview.md](architecture/overview.md), [architecture/decisions/](architecture/decisions/), [architecture/PHASE1-HANDOFF.md](architecture/PHASE1-HANDOFF.md), [architecture/BRD-Engagement-Attribution.docx](architecture/BRD-Engagement-Attribution.docx), [architecture/Engagement-Attribution-Demo.pptx](architecture/Engagement-Attribution-Demo.pptx).
- **Development** — [development/onboarding.md](development/onboarding.md), [development/apex-conventions.md](development/apex-conventions.md), [development/code-review-checklist.md](development/code-review-checklist.md), [development/classes/](development/classes/) (Apex), `development/components/` (LWC — owned by Lyric), [development/lwc-conventions.md](development/lwc-conventions.md) (Lyric).
- **Operations** — [operations/apex-invocation-runbook.md](operations/apex-invocation-runbook.md). Deploy runbook + scratch-org lifecycle + packaging are owned by Dash.
- **Testing** — [testing/test-strategy.md](testing/test-strategy.md), [testing/test-plan-2026-05-12.md](testing/test-plan-2026-05-12.md), [testing/test-audit-2026-05-12.md](testing/test-audit-2026-05-12.md), [testing/test-architect-brief.md](testing/test-architect-brief.md).
- **Users / demo** — [users/DEMO.md](users/DEMO.md), [users/wireframes/](users/wireframes/).

### Code conventions

Code authoring rules live in [best-practices/](../best-practices/) at the repo root — [apex.md](../best-practices/apex.md), [apex-tests.md](../best-practices/apex-tests.md), [lwc.md](../best-practices/lwc.md), [architecture.md](../best-practices/architecture.md). The docs in [development/](development/) summarize and link; they do not duplicate.

### Ownership

| Surface                                                                                                                                              | Owner                     |
| ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| `architecture/`, `development/classes/`, `development/apex-conventions.md`, `operations/apex-invocation-runbook.md`, `users/DEMO.md` (Apex sections) | Marlowe (Apex docs)       |
| `development/components/`, `development/lwc-conventions.md`, `users/DEMO.md` (UI sections)                                                           | Lyric (LWC docs)          |
| `testing/`                                                                                                                                           | Pippa (Sr Test Architect) |
| `operations/deploy-runbook.md`, `operations/scratch-org-lifecycle.md`, `operations/packaging.md`                                                     | Dash (DevOps)             |
| `security/`                                                                                                                                          | Sage (Security Architect) |

See [`.claude/agents/TEAM.md`](/Users/david/Work/Zelis/.claude/agents/TEAM.md) for the full org chart and PR review flow.

---

## CSI-7162 Jira Push Notifications — Documentation

CSI-7162 wires Salesforce Opportunity inserts/updates through a platform-event-decoupled pipeline into Atlassian Jira, via the Appfire JCFS managed package. Qualifying-field changes on an `Opportunity` publish a `Jira_Push_Request__e` platform event; a trigger on the PE invokes `JCFS.API.pushUpdatesToJira(...)`, and Jira pulls field values back from Salesforce per its mapping. This feature ships as Apex only — no LWC surface.

### Reading order

| You are…                | Read in this order                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A new Apex dev**      | [architecture/csi7162-jira-push-overview.md](architecture/csi7162-jira-push-overview.md) → [development/classes/OpportunityTrigger.md](development/classes/OpportunityTrigger.md) → [development/classes/OpportunityTriggerHandler.md](development/classes/OpportunityTriggerHandler.md) → [development/classes/OpportunityService.md](development/classes/OpportunityService.md) → [development/classes/JiraPushService.md](development/classes/JiraPushService.md) → [development/classes/JiraPushDispatcher.md](development/classes/JiraPushDispatcher.md) → [development/classes/JcfsApiAdapter.md](development/classes/JcfsApiAdapter.md) |
| **A new admin**         | [users/csi7162-jira-push-admin-guide.md](users/csi7162-jira-push-admin-guide.md) → [operations/csi7162-jira-push-runbook.md](operations/csi7162-jira-push-runbook.md)                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **On-call / triage**    | [operations/csi7162-jira-push-runbook.md](operations/csi7162-jira-push-runbook.md) → [architecture/csi7162-jira-push-overview.md](architecture/csi7162-jira-push-overview.md) (failure model section)                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **PR reviewer (Atlas)** | [architecture/csi7162-jira-push-overview.md](architecture/csi7162-jira-push-overview.md) → [development/classes/](development/classes/) per-class → [reviews/](reviews/) (Atlas/Pippa's review notes)                                                                                                                                                                                                                                                                                                                                                                                                                                          |

### Top-level entry points

- **Architecture** — [architecture/csi7162-jira-push-overview.md](architecture/csi7162-jira-push-overview.md)
- **Apex class reference** — [development/classes/](development/classes/)
- **Operations / runbook** — [operations/csi7162-jira-push-runbook.md](operations/csi7162-jira-push-runbook.md)
- **Admin guide** — [users/csi7162-jira-push-admin-guide.md](users/csi7162-jira-push-admin-guide.md)
- **Review notes** — [reviews/](reviews/) (owned by Atlas + Pippa)

### Jira ticket

[CSI-7162](https://experance.atlassian.net/browse/CSI-7162) — Jira Push Notifications.
