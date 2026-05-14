---
ticket: CSI-7162
title: Implement Push Notification to Jira on Opportunity Change
author: David Wood
project: Salesforce Implementation - OneZelis (CSI)
status: Ready for UAT
---

## Business Rationale

Salesforce Opportunities and the Jira issues tracking implementation work for those Opportunities drift apart whenever the sales team updates a deal. Today, that gap is closed by manual sync actions: somebody opens Jira, opens the Opportunity, and reconciles. That doesn't scale, it's error-prone, and it makes the implementation team's status reports lag the deal by days. We need near-real-time, fire-and-forget propagation of qualifying Opportunity changes into Jira — without the originating sales transaction ever waiting on Jira availability, and with full per-record traceability when something goes wrong.

**Quantified impact:** Estimated 6-10 manual sync touches per Opportunity over its lifecycle. At ~200 Opportunities/quarter under Jira tracking, that's 1,500+ avoidable manual reconciliations per quarter. Eliminating this also removes the data-staleness window (currently 24-72 hours) between Salesforce and Jira.

## User Story

**As a** Salesforce / Jira Integration Administrator
**I want** Salesforce to publish a Platform Event when qualifying Opportunity changes occur, and process that event via an Apex Platform Event trigger that invokes the Jira Connector
**So that** Jira automatically pulls the latest Opportunity data and remains synchronized with Salesforce without manual intervention — and so that the Opportunity save transaction is never blocked by Jira availability.

## Technical Context

**Pattern:** Opportunity Trigger -> Domain Service -> Generic Publisher Service -> Platform Event (`PublishAfterCommit`) -> PE Trigger -> Dispatcher -> JCFS adapter -> Appfire JCFS managed package -> Jira.

**Key classes** (force-app/main/default/classes/):
- `OpportunityTrigger` + `OpportunityTriggerHandler` — bare trigger dispatch.
- `OpportunityService` — domain layer; owns `JIRA_QUALIFYING_FIELDS` and `anyQualifyingFieldChanged` filter.
- `JiraPushService` — SObject-agnostic publisher; transaction-scoped recursion guard; reads CMDT `Active__c` kill switch.
- `JiraPushRequestHandler` + `JiraPushDispatcher` — consumes `Jira_Push_Request__e`; groups Ids by SObject type; gates on CMDT; calls `IJcfsApi.pushUpdates`.
- `JcfsApiAdapter` — thin adapter around `JCFS.API.pushUpdatesToJira`. Falls back to no-op when the managed package is absent.

**Data flow:**
1. Opportunity DML commits in Salesforce.
2. Trigger fires; `OpportunityService` filters on six qualifying fields (StageName, Amount, CloseDate, AccountId, OwnerId, Probability).
3. `JiraPushService.publishUpdates` publishes one `Jira_Push_Request__e` per qualifying record (`PublishAfterCommit` — if the originating transaction rolls back, no event is delivered).
4. PE trigger dispatches; `JiraPushDispatcher` calls `JCFS.API.pushUpdatesToJira(...)` with the typed record list.
5. JCFS notifies Jira; Jira calls back to Salesforce via its own auth (managed by the Appfire package) to pull field values per its mapping.

**Integration points:**
- **Appfire JCFS managed package** — required in production. Salesforce side does not manage the Named Credential; JCFS owns Jira auth.
- **Platform Event `Jira_Push_Request__e`** — `HighVolume`, `PublishAfterCommit`. Fields: `Source_Object__c`, `Source_Id__c`, `Change_Type__c` (`Create`|`Update`), `Event_Timestamp__c`, `Transaction_Id__c`.

**Schema impact:**
- 1 platform event: `Jira_Push_Request__e`.
- 1 custom object: `API_Exception_Log__c` (shared with other integrations).
- 1 custom metadata type: `Jira_Push_Object__mdt` (per-SObject config: `SObject_API_Name__c`, `Active__c`, `Jira_Project_Id__c`, `Jira_Issue_Type__c`).
- 2 CMDT records: `Jira_Push_Object.Opportunity`, `Jira_Push_Object.Case`.

**Key dependencies:** Appfire JCFS (`JCFS.API`) at runtime in production. ADR-0002 (Logger system-mode insert for `API_Exception_Log__c`).

## Acceptance Criteria

**AC-1**: Given an active CMDT row for `Opportunity` (`Active__c = true`), When a user inserts a new Opportunity, Then `Jira_Push_Request__e` is published with `Change_Type__c = 'Create'`, and no row appears in `API_Exception_Log__c`.

**AC-2**: Given an existing Opportunity, When a user updates `StageName` (or any of the other five qualifying fields: `Amount`, `CloseDate`, `AccountId`, `OwnerId`, `Probability`), Then exactly one `Jira_Push_Request__e` is published with `Change_Type__c = 'Update'`.

**AC-3**: Given an existing Opportunity, When a user updates a non-qualifying field (e.g. `Description`), Then no `Jira_Push_Request__e` is published.

**AC-4**: Given Jira is unavailable, When a user saves a qualifying Opportunity change, Then the Opportunity save commits successfully and is not blocked. The failure is recorded in `API_Exception_Log__c` with `API_Name__c = 'JCFS'` and per-record `Source_Record_Id__c`.

**AC-5**: Given the same transaction triggers the Opportunity update path twice (recursion), When the second pass reaches `JiraPushService`, Then no duplicate platform event is published (transaction-scoped recursion guard keyed by `SObjectName + ':' + Id + ':' + ChangeType`).

**AC-6**: Given an admin flips `Jira_Push_Object.Opportunity.Active__c` to `false`, When a user saves a qualifying Opportunity change in a new transaction, Then `JiraPushService.publish` logs `'Jira push inactive for Opportunity; skipping publish'` and no platform event is published. Re-enabling restores publication on the next transaction.

**AC-7**: Given the Appfire JCFS managed package is not installed in the org, When a `Jira_Push_Request__e` is processed, Then `JcfsApiAdapter` logs one `Logger.error('JCFS managed package is not installed...')` per transaction, and one `API_Exception_Log__c` row per record is written with `Operation__c = 'JCFS.API.pushUpdatesToJira (per-record)'`.

**AC-8**: Given a successful push, When `JCFS.API.pushUpdatesToJira` returns a `JcfsPushResult` carrying a `jiraIssueKey`, Then `JiraPushDispatcher.pushOne` writes a `Logger.info` line of the shape `'JCFS push success for Opportunity 006xxx -> CSI-1234'`.

**AC-9**: Given a JCFS per-record rejection (one record fails in a batch of N), When the batch is processed, Then the failed record gets its own `API_Exception_Log__c` row with `Source_Record_Id__c` set, `Operation__c = 'JCFS.API.pushUpdatesToJira (per-record)'`, and `Message__c` prefixed `'JCFS rejected record: '` — the remaining N-1 records still ship.

**AC-10**: Given every failed push is recorded in `API_Exception_Log__c`, When the integration administrator runs the replay procedure (anonymous Apex per the [runbook](../runbooks/csi-7162-go-live.md#replay-a-dropped-push)), Then the failed records re-publish and reach Jira without producing new failure rows.

## Out of Scope

- Bidirectional sync initiated from Jira. Jira -> Salesforce is owned entirely by the Appfire JCFS package and is not in this story.
- Non-Opportunity SObjects in the initial release. The `Case` CMDT row ships disabled (`Active__c = false`) for a follow-on story; the framework supports it but no `CaseService` / `CaseTriggerHandler` ships here.
- Field-level data mapping inside JCFS. What fields Jira pulls back is configured in the JCFS package, not in this story.
- Automatic retry. There is no retry framework; replay is manual per the runbook.
- Cross-transaction idempotency. Jira's own mapping reconciles repeat pushes against existing issues.

## Test Coverage Map

- **Unit (Apex):**
  - `OpportunityServiceTest` — qualifying-field filter, insert vs. update routing.
  - `OpportunityTriggerHandlerTest` — phase routing, bypass behavior.
  - `JiraPushServiceTest` — recursion guard, CMDT active gate (both sides), PE publish, change-type keying.
  - `JiraPushRequestHandlerTest` — PE delivery dispatch.
  - `JiraPushDispatcherTest` — SObject grouping, typed-list construction, per-record `JcfsPushResult` handling (success + failure), no-op fallback when JCFS absent.
  - `JcfsApiAdapterTest` — startup probe, one-time error log, per-record failure result emission.
- **Integration (Apex):**
  - Smoke-test anonymous Apex in [runbook](../runbooks/csi-7162-go-live.md#smoke-verification-post-deploy) — exercises end-to-end PE publish path in a real sandbox / production org with the JCFS package installed.
- **UAT:**
  - [UAT script §1 — CSI-7162 — Jira Push](../uat/uat-script-csi7162-mi.md#feature-1-csi-7162--jira-push-on-opportunity-change). Steps 1.1 through 1.6.

## References

- Architecture overview: [docs/confluence/csi-7162-technical.md](../confluence/csi-7162-technical.md)
- Go-live runbook: [docs/runbooks/csi-7162-go-live.md](../runbooks/csi-7162-go-live.md)
- Existing operations runbook: [docs/operations/csi7162-jira-push-runbook.md](../operations/csi7162-jira-push-runbook.md)
- Architectural overview (longer form): [docs/architecture/csi7162-jira-push-overview.md](../architecture/csi7162-jira-push-overview.md)
- Atlas code review: [docs/reviews/atlas-csi7162-code-review-2026-05-12.md](../reviews/atlas-csi7162-code-review-2026-05-12.md)
- Pippa test review: [docs/reviews/pippa-csi7162-test-review-2026-05-12.md](../reviews/pippa-csi7162-test-review-2026-05-12.md)
- Sage security pass-through: [docs/reviews/sage-csi7162-security-passthrough-2026-05-12.md](../reviews/sage-csi7162-security-passthrough-2026-05-12.md)
- Original Jira ticket export: [CSI-7162.xml](../../CSI-7162.xml)
