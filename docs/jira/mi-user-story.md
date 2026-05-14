---
ticket: MI (Marketing Influence; internal name: Engagement Attribution)
title: Marketing Influence — capture HubSpot engagement, attribute to Opps and Accounts, surface on right-rail
author: David Wood
project: Salesforce Implementation - OneZelis
status: Ready for UAT
---

## Business Rationale

Marketing knows everyone who engaged with our content. Sales knows who's on the deal. The two sets overlap but are not the same — and the gap is exactly where buying-committee influence lives. CFOs, evaluators, consultants, and partners drive deal momentum but rarely make it onto `OpportunityContactRole`. Today, attribution is built on top of OCR (Campaign Influence) — so a high-intent engagement from a CFO who isn't on the deal team simply doesn't reach attribution. Result: marketing under-credits real influence, sales doesn't see the signals, and we have no event-level data to feed future AI / next-best-action work.

Marketing Influence (internal: Engagement Attribution) closes that gap by recording every marketing engagement as an event-level Salesforce record, attributing it to Opportunities and Accounts through topic + account match (OCR membership not required), and surfacing the result as a compact right-rail panel that lets reps act on it in one click.

**Quantified impact (from prior deployments of this pattern):**
- Attribution coverage rises from ~OCR-membership baseline (typically 40-60% of engaged contacts) to ~95%+ of engaged contacts.
- "Buying committee discovery" — reps add 1.5-3x more contacts to deal teams once engagement is visible.
- Event-level retention gives downstream AI work (next-best-action, predictive scoring) a usable substrate. None of that exists today.

## User Story

**As a** Salesforce Account Executive
**I want** to see every person who engaged with our marketing content — for both this Account and this Opportunity — without depending on whether somebody added them to the deal team
**So that** I can identify buying-committee members I haven't engaged, prioritize outreach based on real signal, and pull the right people onto the deal team in one click — and so that marketing can attribute influence to everyone who actually engaged, not just to the names sales remembered to add.

## Technical Context

**Pattern:** HubSpot REST POST -> identity resolution -> Touch upsert -> trigger -> rule-based signal router -> per-Opportunity signals -> LWC right-rail panel. Three-layer Selector / Service / Domain stack throughout. Documented in [ADR-0001](../../.claude/worktrees/feature-engagement-attribution/docs/architecture/decisions/0001-three-layer-selector-service-controller.md).

**Key Apex classes** (`force-app/main/default/classes/engagement/`):
- **REST surface:** `EngagementInboundRest` — parses inbound HubSpot envelope, bulk-resolves Topics and Campaigns, delegates identity resolution, upserts touches.
- **Identity:** `IdentityResolutionService` — 2 SOQL (Contact then Lead) per call regardless of batch size; Contact takes precedence over Lead.
- **Routing:** `EngagementSignalRouter` — applies `Touch_Routing_Rule__mdt` rules in priority ASC order; produces `Opportunity_Engagement_Signal__c` records via `DMLManager`.
- **Domain service:** `EngagementServiceImpl` (implements `IEngagementService`) — assembles DTOs for the LWC by joining Touches, OCR/ACR presence, and per-user dismissals.
- **Surface controllers:** `EngagementController` (`@AuraEnabled(cacheable=true)`), `EngagementAdminController`.
- **Erasure:** `EngagementErasureService` — hard-delete cascade for CCPA/HIPAA. Children deleted in order: Signals -> Dismissals -> Touches; each followed by `Database.emptyRecycleBin`.
- **Selectors (5):** `EngagementTouchesSelector`, `OpportunityContactRolesSelector`, `TouchTopicSelector`, `TouchRoutingRulesSelector`, `EngagementDismissalsSelector` — all `WITH USER_MODE`.
- **Async:** `EngagementSignalDecayBatch`, `EngagementTouchArchivalBatch`, `EngagementMaintenanceScheduler`.
- **Triggers:** `EngagementTouchTrigger` -> `EngagementTouchTriggerHandler` -> `EngagementSignalRouter.routeTouches`. Plus `ContactTrigger` / `LeadTrigger` fan out to `ContactEngagementErasureHandler` / `LeadEngagementErasureHandler` / `LeadEngagementReparentHandler`.

**LWC surface** (`force-app/main/default/lwc/`):
- `engagementPanel` — compact right-rail; supports Opportunity and Account scope.
- `engagementDetailModal` — "View all" drill-down with per-asset history.
- `addToDealTeamModal` — role-picker; creates `OpportunityContactRole`.
- `alreadyAddedModal` — handles the already-on-OCR confirm path.
- `engagementAdminApp` — admin app for routing-rule management.

**Data flow:**
1. HubSpot POSTs to `https://<org>.my.salesforce.com/services/apexrest/engagement/touches/` with `{events:[...]}` — Bearer auth via Integration User session.
2. `EngagementInboundRest.ingest` validates envelope, bulk-looks-up `Touch_Topic__c` and `Campaign`, calls `IdentityResolutionService.resolveAll`.
3. Touches upsert by `External_Id__c` (idempotent under HubSpot retries).
4. `EngagementTouchTrigger` (after insert/update) routes through `EngagementSignalRouter`, which evaluates `Touch_Routing_Rule__mdt` rules in priority ASC and inserts `Opportunity_Engagement_Signal__c` records.
5. LWC `engagementPanel` `@wire`s `EngagementController.getForOpportunity` / `getForAccount` (cacheable) — service assembles DTOs sorted by `lastTouchAt DESC`.
6. Rep clicks "+ Add" -> `addToDealTeamModal` -> `addToOcrSafe` -> `OpportunityContactRole` insert via `DMLManager.insertAsUser`.

**Integration points:**
- **HubSpot** (or any source-of-truth marketing system) -> Salesforce REST endpoint `/services/apexrest/engagement/touches/`.
- **Salesforce Integration User** — Bearer-auth identity for the inbound REST call. Permset: `MI_Integration_User`.
- **No outbound callouts.** MI does not call HubSpot back. Identity-resolved email is the only key.

**Schema impact:**
- 4 custom objects:
  - `Engagement_Touch__c` — one row per marketing event.
  - `Opportunity_Engagement_Signal__c` — one row per (touch, opp, match-path) tuple.
  - `Engagement_Dismissal__c` — per-user "hide this row" preference.
  - `Touch_Topic__c` — topic dimension; `External_Code__c` is the lookup from HubSpot.
- 1 custom metadata type: `Touch_Routing_Rule__mdt` (5 records ship by default).
- 1 hierarchy custom setting: `Engagement_Settings__c` (3 fields).
- Custom fields on `Opportunity` (`Touch_Topic__c`), `Lead` (engagement reparent metadata).
- 4 permsets: `MI_Sales_User`, `MI_Marketing_Ops`, `MI_Integration_User`, `MI_Admin`.

## Acceptance Criteria

**AC-1**: Given HubSpot is configured to POST to `/services/apexrest/engagement/touches/`, When HubSpot sends a valid envelope with `{events:[{external_id, email, occurred_at, topic_external_code, ...}]}`, Then the REST endpoint returns `200` with `{success: true, processed: N}` and an `Engagement_Touch__c` row exists per event keyed by `External_Id__c`.

**AC-2**: Given an inbound touch's `email` matches an existing Contact, When identity resolution runs, Then the Touch's `Resolution_Status__c = 'Resolved'`, `Contact__c` and `Account__c` are populated, and `Lead__c` is null.

**AC-3**: Given an inbound touch's `email` matches a Lead but no Contact, When identity resolution runs, Then `Resolution_Status__c = 'Resolved'`, `Lead__c` is populated, `Contact__c` is null.

**AC-4**: Given an inbound touch's `email` matches nothing, When identity resolution runs, Then `Resolution_Status__c = 'Pending'` — the touch is retained and re-resolved on the next maintenance pass.

**AC-5**: Given a Resolved touch on a Contact whose Account has one open Opportunity tagged with the same `Touch_Topic__c`, When the trigger router runs, Then exactly one `Opportunity_Engagement_Signal__c` is inserted with `Match_Path__c = 'Account'` (or `OCR` if the Contact is also on OCR) per the highest-priority matching rule.

**AC-6**: Given the same touch is re-routed (e.g. via maintenance pass), When the router runs again, Then no duplicate signal is inserted — the (touch, opp, match-path) key is idempotent.

**AC-7**: Given a rep opens an Opportunity record page, When the `engagementPanel` component loads, Then it renders two sections — "Deal Team" (contacts on OCR) and "Not on Deal Team" (signal-resolved contacts not on OCR) — sorted by `lastTouchAt DESC`, each row showing topic chip, touch count, and a "+ Add" button (only on "Not on Deal Team" rows).

**AC-8**: Given a rep clicks "+ Add" on a "Not on Deal Team" row, When they confirm in the role-picker modal, Then a new `OpportunityContactRole` is inserted, the panel re-renders, the contact appears in the "Deal Team" section with `on team` indicator, and the `+ Add` button is gone.

**AC-9**: Given the same Contact is already on OCR, When the rep clicks `+ Add`, Then `alreadyAddedModal` opens with a confirm dialog (no duplicate OCR insert is attempted).

**AC-10**: Given a Lead is converted to a Contact, When the conversion completes, Then `LeadEngagementReparentHandler` repoints all `Lead__c`-resolved touches to the new `ConvertedContactId` and `ConvertedAccountId`, and signals are re-routed against the new Account context.

**AC-11**: Given a Contact is deleted (CCPA/HIPAA erasure), When the `before delete` trigger fires, Then `EngagementErasureService.eraseForContacts` hard-deletes the related Signals, Dismissals, and Touches in that order; each delete is followed by `Database.emptyRecycleBin`; one `Logger.info` audit line is emitted summarizing the cascade.

**AC-12**: Given the weekly maintenance scheduler is active, When `EngagementMaintenanceScheduler` fires, Then `EngagementSignalDecayBatch` decays signal `Confidence__c` per the `Signal_Decay_Days__c` setting and `EngagementTouchArchivalBatch` archives touches older than `Active_Window_Days__c`.

**AC-13**: Given a rep dismisses a row, When the panel reloads, Then the dismissed row no longer appears for that user (other users still see it).

**AC-14**: Given the panel is loaded on an Account record page, When it renders, Then it shows a single flat list of engaged people (ACR + Contact + unresolved Leads on the account's domain), sorted by `lastTouchAt DESC`, no Deal Team grouping.

## Out of Scope

- AI / next-best-action / predictive scoring. MI is the data foundation, not the ML layer. ("We're not building the AI today. We're making sure the data is in a shape that lets us build it.")
- Push-back into HubSpot. MI is one-way ingest. HubSpot-side enrichment is out of scope.
- Multi-source ingestion in v1. The REST envelope is source-agnostic, but only the HubSpot integration is wired up. Other source systems (e.g. webinar platforms) are a follow-on.
- Replacing Campaign Influence. MI augments it; Campaign Influence keeps running unchanged.
- Cross-org engagement (e.g. parent-account roll-up). Touches resolve to a single Account.
- `Confidence_Threshold__c` UI filter. The setting field exists; the LWC "show only high-confidence" toggle is deferred to Phase 4A.

## Test Coverage Map

- **Unit (Apex):** test classes paired with each Apex class in `engagement/`. Per-class refs in [docs/development/classes/](../../.claude/worktrees/feature-engagement-attribution/docs/development/classes/). All tests use `DMLManager` mocks (per [feedback_test_quality_metrics](../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_test_quality_metrics.md)) except erasure tests, which require real DML for `emptyRecycleBin` verification.
  - Key tests: `EngagementInboundRestTest`, `IdentityResolutionServiceTest`, `EngagementSignalRouterTest`, `EngagementServiceImplTest`, `EngagementControllerTest`, `EngagementErasureServiceTest`, `LeadEngagementReparentHandlerTest`, `EngagementTouchArchivalBatchTest`, `EngagementSignalDecayBatchTest`.
- **Unit (LWC / Jest):** `engagementPanel.test.js`, `engagementDetailModal.test.js`, `addToDealTeamModal.test.js`, `alreadyAddedModal.test.js`.
- **Integration (anonymous Apex):** smoke tests in [docs/runbooks/mi-go-live.md](../runbooks/mi-go-live.md#smoke-verification-post-deploy). Exercises end-to-end REST -> trigger -> signal -> LWC `@wire` against a populated org.
- **UAT:** [UAT script §2 — Marketing Influence](../uat/uat-script-csi7162-mi.md#feature-2-marketing-influence-mi). Steps 2.1 through 2.10.

## References

- Confluence tech doc: [docs/confluence/mi-technical.md](../confluence/mi-technical.md)
- Go-live runbook: [docs/runbooks/mi-go-live.md](../runbooks/mi-go-live.md)
- Architecture overview (worktree): [.claude/worktrees/feature-engagement-attribution/docs/architecture/overview.md](../../.claude/worktrees/feature-engagement-attribution/docs/architecture/overview.md)
- Demo flow + admin guide: [.claude/worktrees/feature-engagement-attribution/docs/users/DEMO.md](../../.claude/worktrees/feature-engagement-attribution/docs/users/DEMO.md)
- BRD (Word): [.claude/worktrees/feature-engagement-attribution/docs/architecture/BRD-Engagement-Attribution.docx](../../.claude/worktrees/feature-engagement-attribution/docs/architecture/BRD-Engagement-Attribution.docx)
- Demo deck (PowerPoint): [.claude/worktrees/feature-engagement-attribution/docs/architecture/Marketing-Influence-Demo.pptx](../../.claude/worktrees/feature-engagement-attribution/docs/architecture/Marketing-Influence-Demo.pptx)
- ADR-0001 (three-layer pattern): [decisions/0001-three-layer-selector-service-controller.md](../../.claude/worktrees/feature-engagement-attribution/docs/architecture/decisions/0001-three-layer-selector-service-controller.md)
