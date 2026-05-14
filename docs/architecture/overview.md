# Engagement Attribution — Architecture Overview

The current, applied architecture reference. Replaces [PHASE1-HANDOFF.md](PHASE1-HANDOFF.md) as the primary architectural read; PHASE1-HANDOFF stays as historical context for the build orchestration.

## What this feature does

Engagement Attribution captures HubSpot (and other source-system) marketing-engagement events, resolves them to Salesforce Contacts / Leads / Accounts, routes them into per-Opportunity signals via priority-ordered metadata rules, and surfaces the result as a right-rail panel on the Account and Opportunity record pages. The structural problem it solves: `OpportunityContactRole` is sales-curated and incomplete — high-intent engagement from CFOs, evaluators, consultants, partners doesn't reach attribution because those people aren't on OCR. This feature attributes via topic + account context (not via OCR), then makes maintaining OCR a value-add for sales rather than overhead.

## Architecture diagram

```
┌─────────────┐     POST /services/apexrest/      ┌────────────────────────┐
│  HubSpot    │ ──> engagement/touches/      ──>  │ EngagementInboundRest  │
│  (or other) │     {events:[...]}                │  - parse, validate     │
└─────────────┘                                   │  - bulk Topic+Campaign │
                                                  │  - delegate identity   │
                                                  │  - upsert touches      │
                                                  └─────────┬──────────────┘
                                                            │
                                                            v
                                         ┌──────────────────────────────────┐
                                         │  IdentityResolutionService       │
                                         │  - Contact precedence over Lead  │
                                         │  - 2 SOQL regardless of batch    │
                                         │  - mutates touches in place      │
                                         └──────────────────┬───────────────┘
                                                            │
                                                            v
                                          ┌─────────────────────────────────┐
                                          │  Engagement_Touch__c (upsert)   │
                                          │  External_Id__c is the key      │
                                          └─────────────────┬───────────────┘
                                                            │ trigger: after insert/update
                                                            v
                              ┌─────────────────────────────────────────────────┐
                              │  EngagementTouchTrigger →                       │
                              │  EngagementTouchTriggerHandler →                │
                              │  EngagementSignalRouter.routeTouches(...)       │
                              │  - apply Touch_Routing_Rule__mdt (priority ASC) │
                              │  - one signal per (touch, opp, match path)      │
                              │  - 6 SOQL regardless of batch                   │
                              └─────────────────────────┬───────────────────────┘
                                                        │
                                                        v
                                  ┌────────────────────────────────────────────┐
                                  │  Opportunity_Engagement_Signal__c (insert) │
                                  └────────────────────────┬───────────────────┘
                                                           │ aggregated by
                                                           v
                                  ┌────────────────────────────────────────────┐
                                  │  EngagementController.getForOpportunity()  │
                                  │      / getForAccount() / addToOcrSafe()    │
                                  │  delegates to EngagementServiceImpl        │
                                  └────────────────────────┬───────────────────┘
                                                           │ @AuraEnabled DTOs
                                                           v
                                  ┌────────────────────────────────────────────┐
                                  │  engagementPanel  / engagementDetailModal  │
                                  │  addToDealTeamModal / alreadyAddedModal    │
                                  └────────────────────────────────────────────┘

  ────  Side cascades  ────────────────────────────────────────────────────────

  Lead conversion        →  LeadTrigger → LeadEngagementReparentHandler
                            (after update — repoints Lead__c touches to
                             ConvertedContactId / ConvertedAccountId)

  Contact/Lead delete    →  ContactTrigger / LeadTrigger
                         →  ContactEngagementErasureHandler / LeadEngagementErasureHandler
                         →  EngagementErasureService.eraseForContacts(...) / .eraseForLeads(...)
                            (before delete — hard-deletes signals, dismissals,
                             touches; empties Recycle Bin)

  Weekly maintenance     →  EngagementMaintenanceScheduler
                         →  EngagementSignalDecayBatch  + EngagementTouchArchivalBatch
                            (decays signal confidence, archives stale touches)
```

## Three-layer pattern

Codified in [ADR 0001 — three-layer Selector / Service / Controller pattern](decisions/0001-three-layer-selector-service-controller.md).

**Selector** (data access). All SOQL, no DML, no business rules. Every method takes a `Set<Id>` (or equivalent) and returns a `List<SObject>` or `Map<...>`. Every query carries `WITH USER_MODE`. Five selectors ship: [`EngagementTouchesSelector`](../../force-app/main/default/classes/engagement/EngagementTouchesSelector.cls), [`OpportunityContactRolesSelector`](../../force-app/main/default/classes/engagement/OpportunityContactRolesSelector.cls), [`TouchTopicSelector`](../../force-app/main/default/classes/engagement/TouchTopicSelector.cls), [`TouchRoutingRulesSelector`](../../force-app/main/default/classes/engagement/TouchRoutingRulesSelector.cls), [`EngagementDismissalsSelector`](../../force-app/main/default/classes/engagement/EngagementDismissalsSelector.cls).

**Service** (business rules). Orchestrates Selectors, performs DML via [`DMLManager`](../../force-app/main/default/classes/dml/DMLManager.cls) under `AccessLevel.USER_MODE`, throws module-typed exceptions ([`EngagementException`](../../force-app/main/default/classes/engagement/EngagementException.cls)), logs via [`Logger`](../../force-app/main/default/classes/logging/Logger.cls). Per-class refs: [`EngagementServiceImpl`](../development/classes/EngagementServiceImpl.md), [`EngagementSignalRouter`](../development/classes/EngagementSignalRouter.md), [`IdentityResolutionService`](../development/classes/IdentityResolutionService.md), [`EngagementErasureService`](../../force-app/main/default/classes/engagement/EngagementErasureService.cls).

**Domain** (in-memory shaping). Wraps a `List<SObject>` of one type; pure helpers; no DML/SOQL. Currently a skeleton: [`EngagementTouches`](../../force-app/main/default/classes/engagement/EngagementTouches.cls). It earns its place as Phase 2+ moves more aggregation logic out of the Service.

**Surface** (controllers / REST / triggers / batches). Thin. One Service call per method. Per-class refs for the surfaces: [`EngagementController`](../development/classes/EngagementController.md), [`EngagementInboundRest`](../development/classes/EngagementInboundRest.md), trigger handlers under [`force-app/main/default/classes/engagement/`](../../force-app/main/default/classes/engagement/), batches [`EngagementSignalDecayBatch`](../../force-app/main/default/classes/engagement/EngagementSignalDecayBatch.cls) / [`EngagementTouchArchivalBatch`](../../force-app/main/default/classes/engagement/EngagementTouchArchivalBatch.cls).

## Inbound flow walkthrough — end-to-end one event

A single HubSpot whitepaper-download event for `sarah.johnson@uhc.example.com`, traced from wire to UI:

1. **HubSpot POSTs** to `https://<org>.my.salesforce.com/services/apexrest/engagement/touches/` with `{events: [{external_id, email, occurred_at, topic_external_code, ...}]}`. Bearer auth via Integration User session.
2. **[`EngagementInboundRest.ingest`](../development/classes/EngagementInboundRest.md)** parses the envelope, validates required fields (`external_id`, `email`, `occurred_at`), bulk-looks-up `Touch_Topic__c` by `External_Code__c` and `Campaign` by `Name`.
3. **[`IdentityResolutionService.resolveAll`](../development/classes/IdentityResolutionService.md)** runs 2 SOQL (Contact + Lead by email). Sarah is on `Contact`; status → `Resolved`, `Contact__c` and `Account__c` populated.
4. **Upsert** `Engagement_Touch__c` by `External_Id__c`. `with sharing` + `AccessLevel.USER_MODE`. HubSpot retries are idempotent.
5. **[`EngagementTouchTrigger`](../../force-app/main/default/triggers/EngagementTouchTrigger.trigger) fires** on `after insert`. [`EngagementTouchTriggerHandler`](../../force-app/main/default/classes/engagement/EngagementTouchTriggerHandler.cls) extracts ids of Resolved touches and calls [`EngagementSignalRouter.routeTouches`](../development/classes/EngagementSignalRouter.md).
6. **Router loads** open Opps on the Account, OCR / ACR presence maps, existing signal keys, and the priority-ordered rule set (6 SOQL total). Walks each (touch, opp) pair against rules in `Priority__c` ASC order. For Sarah on the Network Pricing Implementation Opp: she's not on OCR; the `Account_Topic_Default` rule wins (priority 50, Account match path, confidence 60).
7. **Inserts** `Opportunity_Engagement_Signal__c` via `DMLManager.insertAsUser`. Idempotent — re-routing creates no duplicates.
8. **User opens the Opp record page.** The [`engagementPanel`](../../force-app/main/default/lwc/engagementPanel/) LWC's `@wire` calls [`EngagementController.getForOpportunity`](../development/classes/EngagementController.md) (cacheable).
9. **[`EngagementServiceImpl.getForOpportunity`](../development/classes/EngagementServiceImpl.md)** resolves the Opp's `Touch_Topic__c`, queries Touches via [`EngagementTouchesSelector.selectByOpportunityWithTopics`](../../force-app/main/default/classes/engagement/EngagementTouchesSelector.cls), joins OCR + ACR + per-user dismissals, assembles DTOs sorted by `lastTouchAt DESC`.
10. **Panel renders.** Sarah's row appears in "Not on Deal Team" with topic chip, touch count, "+ Add" button. Rep clicks **+ Add** → `addToDealTeamModal` → `addToOcrSafe` → `OpportunityContactRole` insert. Next render: Sarah is in "Deal Team" with `✓ on team`.

End-to-end time on a fresh scratch org: < 1 second from POST to panel-ready (excluding the user's browser refresh).

## Erasure flow walkthrough — CCPA / HIPAA "delete my data"

Zelis is US-only; the regimes in play are CCPA + state privacy + HIPAA. The same cascade handles all three:

1. **Privacy team gets the request** for `john.doe@payerco.example.com`. They resolve to the Salesforce Contact or Lead.
2. **Operator deletes** the Contact (or Lead) record — standard Lightning UI delete, or anonymous Apex `delete c;`.
3. **[`ContactTrigger`](../../force-app/main/default/triggers/ContactTrigger.trigger) fires `before delete`.** Routed through the project [`TriggerHandler`](../../force-app/main/default/classes/triggers/TriggerHandler.cls) framework to [`ContactEngagementErasureHandler`](../../force-app/main/default/classes/engagement/ContactEngagementErasureHandler.cls).
4. **Handler calls [`EngagementErasureService.eraseForContacts`](../../force-app/main/default/classes/engagement/EngagementErasureService.cls)** with the set of doomed Contact Ids.
5. **Service hard-deletes children in order:** `Opportunity_Engagement_Signal__c` → `Engagement_Dismissal__c` → `Engagement_Touch__c`. Every operation in `WITH USER_MODE` / `AccessLevel.USER_MODE`. Each DML is followed by `Database.emptyRecycleBin(...)` — records are gone, not soft-deleted. `SELECT ... ALL ROWS` returns zero.
6. **Audit trail:** one `Logger.info` line per cascade, copied to `ErasureSummary.messages`:

   ```
   Subject erasure cascade — 1 subject(s) of type Contact: deleted 3 touch(es), 2 signal(s), 1 dismissal(s).
   ```

   Compliance copies the line into the ticket.

7. **Parent Contact is then deleted by the platform.** The before-delete ordering ensures no orphan child records exist mid-flight.

For "retain the Contact shell, erase engagement only" — the alternate compliance path — call `EngagementErasureService.eraseForContacts({contactId})` directly via anonymous Apex. See [operations/apex-invocation-runbook.md §Manually call EngagementErasureService](../operations/apex-invocation-runbook.md). Hard-delete is intentional and irreversible; do not soften without privacy-counsel sign-off.

## Key extension points

The feature is designed to evolve without redeploys for the common cases. Three extension points:

### `Touch_Routing_Rule__mdt`

The routing rule set is a Custom Metadata Type. Add a rule via Setup → Custom Metadata Types → Touch Routing Rule → Manage Records → New, or version-control via `force-app/main/default/customMetadata/Touch_Routing_Rule.<DeveloperName>.md-meta.xml`. [`TouchRoutingRulesSelector.selectActiveOrderedByPriority`](../../force-app/main/default/classes/engagement/TouchRoutingRulesSelector.cls) picks up the new row on the next touch event — no Apex redeploy.

Five rules ship by default — see [users/DEMO.md §Seeded routing rules](../users/DEMO.md#seeded-routing-rules). Constraints supported per rule: `Require_Same_Account__c`, `Require_Topic_Match__c`, `Persona_Filter__c`, `Touch_Type_Filter__c`, `Min_Intent_Level__c`, `Match_Path__c` (one of `OCR` / `ACR` / `Account` / `Domain` / `Consultant`).

### `Engagement_Settings__c`

Hierarchy Custom Setting. Org Default record drives the maintenance batch tunables:

| Field                     | Default | Effect                                                     |
| ------------------------- | ------: | ---------------------------------------------------------- |
| `Active_Window_Days__c`   |     180 | Touches older than this get archived.                      |
| `Signal_Decay_Days__c`    |      90 | Age at which a signal's confidence floors at zero.         |
| `Confidence_Threshold__c` |      40 | Reserved for the UI panel's "show only" filter (Phase 4A). |

Edit via Setup → Custom Settings → Engagement Settings → Manage → Default Organization Level Value. No deploy required.

### DTO + REST envelope

`EngagementDTO` and the `InboundPayload` / `InboundResult` REST DTOs are versionable extension points — adding a field is safe (older LWC / older HubSpot integrations ignore the field). Removing or renaming is a breaking change; coordinate with the LWC team (Coda / Kit / Robin) and the HubSpot integration owner.

---

## History + companion reads

- [PHASE1-HANDOFF.md](PHASE1-HANDOFF.md) — the pre-build orchestration plan. Records the wave-based build sequence, scope boundaries per phase, and the open questions captured during initial scoping. Frozen as historical context; do not edit.
- [BRD-Engagement-Attribution.docx](BRD-Engagement-Attribution.docx) — Business Requirements Document (Word). Phase column + traceability matrix. Updated only when stakeholder requirements change.
- [Engagement-Attribution-Demo.pptx](Engagement-Attribution-Demo.pptx) — exec demo deck (5+1 main, 4 backup).
- [decisions/](decisions/) — ADR log. Start at [0001](decisions/0001-three-layer-selector-service-controller.md) and append as architectural choices are made.
- [users/DEMO.md](../users/DEMO.md) — the 4-beat walkthrough, end-to-end runbook, Phase 2/3/4/5 demo flows.

---

**Summary:** HubSpot → REST → identity-resolve → upsert touch → trigger router → signal → controller DTO → LWC panel is the inbound spine; before-delete triggers fan a hard-delete cascade through `EngagementErasureService` for CCPA / HIPAA. The three-layer Selector / Service / Domain pattern ([ADR 0001](decisions/0001-three-layer-selector-service-controller.md)) keeps SOQL, business rules, and surfaces separable. Routing rules and tunables are externalized to `Touch_Routing_Rule__mdt` and `Engagement_Settings__c` so admins can adapt the feature without an Apex redeploy.
