# CSI-7162 Jira Push Notifications — Documentation

CSI-7162 wires Salesforce Opportunity inserts/updates through a platform-event-decoupled pipeline into Atlassian Jira, via the Appfire JCFS managed package. Qualifying-field changes on an `Opportunity` publish a `Jira_Push_Request__e` platform event; a trigger on the PE invokes `JCFS.API.pushUpdatesToJira(...)`, and Jira pulls field values back from Salesforce per its mapping. This feature ships as Apex only — no LWC surface.

## Reading order

| You are… | Read in this order |
| --- | --- |
| **A new Apex dev** | [architecture/csi7162-jira-push-overview.md](architecture/csi7162-jira-push-overview.md) → [development/classes/OpportunityTrigger.md](development/classes/OpportunityTrigger.md) → [development/classes/OpportunityTriggerHandler.md](development/classes/OpportunityTriggerHandler.md) → [development/classes/OpportunityService.md](development/classes/OpportunityService.md) → [development/classes/JiraPushService.md](development/classes/JiraPushService.md) → [development/classes/JiraPushDispatcher.md](development/classes/JiraPushDispatcher.md) → [development/classes/JcfsApiAdapter.md](development/classes/JcfsApiAdapter.md) |
| **A new admin** | [users/csi7162-jira-push-admin-guide.md](users/csi7162-jira-push-admin-guide.md) → [operations/csi7162-jira-push-runbook.md](operations/csi7162-jira-push-runbook.md) |
| **On-call / triage** | [operations/csi7162-jira-push-runbook.md](operations/csi7162-jira-push-runbook.md) → [architecture/csi7162-jira-push-overview.md](architecture/csi7162-jira-push-overview.md) (failure model section) |
| **PR reviewer (Atlas)** | [architecture/csi7162-jira-push-overview.md](architecture/csi7162-jira-push-overview.md) → [development/classes/](development/classes/) per-class → [reviews/](reviews/) (Atlas/Pippa's review notes) |

## Top-level entry points

- **Architecture** — [architecture/csi7162-jira-push-overview.md](architecture/csi7162-jira-push-overview.md)
- **Apex class reference** — [development/classes/](development/classes/)
- **Operations / runbook** — [operations/csi7162-jira-push-runbook.md](operations/csi7162-jira-push-runbook.md)
- **Admin guide** — [users/csi7162-jira-push-admin-guide.md](users/csi7162-jira-push-admin-guide.md)
- **Review notes** — [reviews/](reviews/) (owned by Atlas + Pippa)

## Code conventions

Authoring rules live in [best-practices/](../best-practices/) at the repo root — [apex.md](../best-practices/apex.md), [apex-tests.md](../best-practices/apex-tests.md), [architecture.md](../best-practices/architecture.md). The per-class docs link back to these where conventions are load-bearing (`with sharing`, `WITH USER_MODE`, Logger usage, trigger framework).

## Jira ticket

[CSI-7162](https://experance.atlassian.net/browse/CSI-7162) — Jira Push Notifications.
