# Phase 1 — Engagement Attribution — Build Handoff

**Purpose:** Pre-compact handoff. This document captures the full state needed to orchestrate the Phase 1 build after `/compact`. If you (a future agent or future-self) read this, you have enough to proceed.

---

## Context

David is a Salesforce Technical Architect, week 2 in his new role at **Zelis** (US-only, healthcare-payments). He's prototyping in his personal dev hub and will package the result for eventual install into the Zelis work org. He has not yet done discovery with stakeholders — this is a pattern he's implemented before, being shared with the team for evaluation.

**Working repository:** `/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/` (worktree branch `feature/engagement-attribution` off `origin/main` on `experance-dev/blue_sky`).

**Conceptual frame:** OCR (Opportunity Contact Role) reflects sales-curated deal-team membership. It is structurally incomplete as an attribution mechanism — high-intent engagement from CFOs, evaluators, consultants, partners (ACR-related ecosystem actors) doesn't reach attribution because those people aren't on OCR. The pattern captures engagement at event-level granularity, attributes to Accounts and Opportunities via topic + account context (not via OCR), and exposes intelligence to sales so that maintaining OCR becomes a value-add rather than overhead.

---

## Phase 1 scope (what we're building NOW)

**Goal:** A scratch org that boots, deploys this metadata, and shows the Engagement panel on a **United Healthcare** Account and Opportunity. Sales clicks "+ Add to Deal Team," gets a role-picker modal, real `OpportunityContactRole` record is created. Seeded touches populate the panel so the demo looks lived-in. Then bundled as an **Unlocked Package** for transport.

**Scope boundaries:**

- ✅ In: custom objects (5), permission set, EngagementPanel LWC (parameterized for both Account and Opportunity scope), AddToDealTeamModal LWC, AlreadyAddedModal LWC (race protection), EngagementDetailModal LWC (View all), Apex Service+Selectors+Domain, OCR-write Apex (race-protected), happy-path Apex + Jest tests, Zelis-flavored seed data, DEMO.md, scratch-org config, unlocked package config.
- ❌ Out (later phases): HubSpot REST endpoint (Phase 2), identity resolution (Phase 2), Lead-conversion reparenting (Phase 2), Touch_Routing_Rule\_\_mdt + routing strategy (Phase 3), admin Test-a-Touch / Rule Coverage / Error Queue LWCs (Phase 4), signal decay + archival jobs (Phase 4), custom report types (Phase 5), GDPR cascade (Phase 5).

---

## Locked decisions

| Decision                     | Value                                                                                                                   | Rationale                                                   |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Target org                   | Scratch org via David's personal Dev Hub; eventually packaged for Zelis import                                          | Lowest friction; David is connected                         |
| Example account name         | **United Healthcare**                                                                                                   | Realistic Zelis customer                                    |
| Topic matching               | **Real in Phase 1** (not deferred)                                                                                      | David: "demo one [pair of LWCs] done right"                 |
| Scope contexts to demo       | **Both Account and Opportunity** (compact panel + detail modal each)                                                    | Backup slides cover the rest                                |
| Test coverage                | Happy path only                                                                                                         | Cycle speed > exhaustive coverage for Phase 1 demo          |
| OCR-already-added handling   | At-render: no button, render "✓ on team". At-click race: AlreadyAddedModal pops with Yes/No (No default)                | David's explicit refinement                                 |
| Seed data style              | Zelis-industry-flavored; time-progressed buying-motion story                                                            | Tells an arc to an analyst opening the page                 |
| Personal utility classes     | Already in `force-app/main/default/classes/{dml,logging,triggers,general,testing,...}/` from earlier work; reused as-is | Pre-existing in worktree                                    |
| Utility-class collision risk | Flagged for post-Phase-1 conversation with Zelis IT                                                                     | Zelis org likely has its own Logger / TriggerHandler / etc. |
| Build orchestration          | Single orchestrator (Claude main session) + parallel worker agents per story / story-bundle                             | Wave-based pattern proven in prior refactor                 |

---

## Directory structure

```
force-app/main/default/
├── classes/
│   ├── dml/                    [existing utility — used as-is]
│   ├── email/                  [existing utility]
│   ├── general/                [existing utility — UtilitiesModuleException base lives here]
│   ├── logging/                [existing utility — Logger lives here]
│   ├── picklists/              [existing utility]
│   ├── pricing/                [existing utility]
│   ├── rest/                   [existing utility]
│   ├── strings/                [existing utility]
│   ├── testing/                [existing utility — TestFactory, HttpCalloutMockFactory]
│   ├── triggers/               [existing utility — TriggerHandler]
│   └── engagement/             [NEW — Phase 1 code]
│       ├── EngagementController.cls
│       ├── IEngagementService.cls
│       ├── EngagementServiceImpl.cls
│       ├── EngagementTouchesSelector.cls
│       ├── OpportunityContactRolesSelector.cls
│       ├── TouchTopicSelector.cls
│       ├── EngagementTouches.cls (Domain)
│       ├── EngagementDTO.cls
│       ├── EngagementException.cls (extends UtilitiesModuleException)
│       └── *Test.cls (happy path)
├── lwc/
│   ├── engagementPanel/
│   ├── addToDealTeamModal/
│   ├── alreadyAddedModal/
│   └── engagementDetailModal/
├── objects/
│   ├── Engagement_Touch__c/
│   ├── Touch_Topic__c/
│   ├── Opportunity_Engagement_Signal__c/
│   ├── Engagement_Settings__c/
│   └── (Lookups added to standard Opportunity, Account, Contact)
├── permissionsets/
│   └── Engagement_Attribution_User.permissionset-meta.xml
├── flexipages/
│   ├── Opportunity_Engagement.flexipage-meta.xml
│   └── Account_Engagement.flexipage-meta.xml
└── ... (existing standard config preserved)

config/
├── project-scratch-def.json
└── (existing config)

scripts/apex/
└── seed-engagement-data.apex

docs/
├── BRD-Engagement-Attribution.docx       [DONE — phase column + traceability]
├── Engagement-Attribution-Demo.pptx      [DONE — 5+1 main slides; +4 backup slides being appended]
├── PHASE1-HANDOFF.md                     [this file]
├── DEMO.md                               [to be created during Phase 1]
└── wireframes/                            [SLDS reference HTMLs]
    ├── sales-console-opportunity.html
    └── sales-console-account.html
```

---

## Object schema (the contract — freeze before deploying)

### `Engagement_Touch__c` (OWD Private)

| Field                   | Type                                                         | Notes                                     |
| ----------------------- | ------------------------------------------------------------ | ----------------------------------------- |
| External_Id\_\_c        | Text 80 — unique, external id                                | Idempotency key                           |
| Source_System\_\_c      | Picklist (HubSpot, Manual, …)                                |                                           |
| Source_Event_Type\_\_c  | Picklist (Download, Form, Webinar, Page View, Event)         |                                           |
| Source_Event_Id\_\_c    | Text 80                                                      | Original HubSpot event id                 |
| Occurred_At\_\_c        | DateTime                                                     |                                           |
| Ingested_At\_\_c        | DateTime                                                     | DEFAULT NOW                               |
| Email_At_Touch\_\_c     | Email, indexed                                               | Identity-resolution key                   |
| Lead\_\_c               | Lookup(Lead)                                                 | nullable                                  |
| Contact\_\_c            | Lookup(Contact)                                              | nullable                                  |
| Account\_\_c            | Lookup(Account)                                              | Denormalized from Contact for query speed |
| Topic\_\_c              | Lookup(Touch_Topic\_\_c)                                     |                                           |
| Campaign\_\_c           | Lookup(Campaign)                                             | nullable                                  |
| Asset_Name\_\_c         | Text 255                                                     |                                           |
| Asset_Url\_\_c          | URL                                                          |                                           |
| Touch_Type\_\_c         | Picklist (Download, Form, Webinar, Page, Event)              | Normalized                                |
| Touch_Subtype\_\_c      | Text 80                                                      | Free-form                                 |
| Persona\_\_c            | Picklist (Executive, Finance, Technical, Operational, Other) |                                           |
| Intent_Level\_\_c       | Picklist (Low, Medium, High)                                 | Computed                                  |
| Resolution_Status\_\_c  | Picklist (Resolved, Pending, Ambiguous, NoMatch)             |                                           |
| Processing_Status\_\_c  | Picklist (New, Processed, Error, Ignored)                    |                                           |
| Processing_Message\_\_c | LongTextArea                                                 |                                           |
| Is_Active\_\_c          | Checkbox (default true)                                      | Archive flag                              |
| Archived_At\_\_c        | DateTime                                                     | nullable                                  |

### `Touch_Topic__c` (OWD Public Read/Write)

| Field              | Type                     | Notes        |
| ------------------ | ------------------------ | ------------ |
| Topic_Name\_\_c    | Text 80                  |              |
| Parent_Topic\_\_c  | Lookup(Touch_Topic\_\_c) | hierarchical |
| External_Code\_\_c | Text 40, unique          |              |

Seed Topics (Zelis-flavored): Claims Editing, Payment Integrity, Network Management, Price Transparency, Out-of-Network Claims, Member Engagement.

### `Opportunity_Engagement_Signal__c` (OWD Controlled by Parent — Opportunity)

| Field                 | Type                                             | Notes                            |
| --------------------- | ------------------------------------------------ | -------------------------------- |
| Opportunity\_\_c      | Master-Detail(Opportunity)                       |                                  |
| Engagement_Touch\_\_c | Lookup(Engagement_Touch\_\_c)                    |                                  |
| Contact\_\_c          | Lookup(Contact)                                  |                                  |
| Topic\_\_c            | Lookup(Touch_Topic\_\_c)                         |                                  |
| Confidence\_\_c       | Number(3,0)                                      | 0–100; Phase 1 set to 50 default |
| Match_Path\_\_c       | Picklist (OCR, ACR, Account, Domain, Consultant) |                                  |
| Dismissed\_\_c        | Checkbox                                         |                                  |
| Dismissed_Reason\_\_c | Text                                             |                                  |

### `Engagement_Settings__c` (Hierarchy Custom Setting)

- Active_Window_Days\_\_c (Number, default 180)
- Confidence_Threshold\_\_c (Number, default 40)
- Signal_Decay_Days\_\_c (Number, default 90)

---

## Apex DTO contract (LWC ↔ Apex frozen shape)

```apex
public class EngagementDTO {
  public Id contactId;
  public String name;
  public String title; // Contact.Title
  public String accountName; // Contact.Account.Name
  public Boolean onOcr; // true if person is on OCR for this opp (only meaningful in Opp scope)
  public String ocrRole; // OpportunityContactRole.Role if onOcr
  public Boolean isAcr;
  public String acrRole; // AccountContactRelation.Roles
  public Boolean isConsultant; // isAcr AND AccountContactRelation.IsDirect=false
  public List<String> topics; // distinct Touch_Topic Names this person engaged with
  public Integer touchCount;
  public DateTime lastTouchAt;
  public List<AssetEngagement> assets; // per-asset breakdown for expand-detail

  public class AssetEngagement {
    public String assetName;
    public String touchType;
    public Integer count; // repeat count
    public DateTime firstAt;
    public DateTime lastAt;
    public String campaignName;
  }
}
```

`EngagementController` methods:

- `@AuraEnabled(cacheable=true) static List<EngagementDTO> getForOpportunity(Id opportunityId)` — returns list partitioned by `onOcr` flag in the DTO.
- `@AuraEnabled(cacheable=true) static List<EngagementDTO> getForAccount(Id accountId)` — flat list scoped to account.
- `@AuraEnabled static AddToOcrResult addToOcrSafe(Id contactId, Id opportunityId, String role, Boolean isPrimary)` — returns `{success:true, ocrId}` OR `{alreadyExists:true, addedByUserId, addedByUserName, addedAt, ocrId}`. Race protection: re-check OCR existence inside the SAME Apex transaction before inserting.
- `@AuraEnabled static void dismissSignal(Id signalId, String reason)` — Phase 1 stub; signal-creation happens in Phase 3 but the dismiss action shape stays consistent.

---

## User stories (the build plan)

Wave A — Foundation (parallel, ~3 workers):

| ID    | Story                                                                                                                                                                                                              | Owner      | Depends on                         |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- | ---------------------------------- |
| US-A1 | Scratch org config: `config/project-scratch-def.json` with sales-cloud features, scratch-org definition file, dev-hub alias scaffolding in `sfdx-project.json`                                                     | one worker | —                                  |
| US-A2 | Custom objects: `Engagement_Touch__c`, `Touch_Topic__c`, `Opportunity_Engagement_Signal__c`, `Engagement_Settings__c` (hierarchy) — all field metadata in `force-app/main/default/objects/`. OWD per schema above. | one worker | —                                  |
| US-A3 | Permission Set: `Engagement_Attribution_User` — Read on Engagement objects, Read/Create on OpportunityContactRole, access to flexipages                                                                            | one worker | depends-on US-A2 completing schema |

Wave B — Selectors + Domain (parallel after A, ~2 workers):

| ID    | Story                                                                                                                                                          |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| US-B1 | `EngagementTouchesSelector` — `selectByAccountId(Set<Id>)`, `selectByOpportunityWithTopic(Id, Set<Id>)`. Tests.                                                |
| US-B2 | `OpportunityContactRolesSelector` — `selectByOpportunityId(Id)`. Tests.                                                                                        |
| US-B3 | `TouchTopicSelector` — `selectAll()`, `selectByOpportunityProduct()` (Phase 1: stub to return all). Tests.                                                     |
| US-B4 | `EngagementTouches` Domain class (skeleton; no triggers yet — Phase 1 has no inbound touches to normalize, but the Domain class exists for Phase 2 readiness). |

Wave C — Service + Controller (serial after B, 1 worker):

| ID    | Story                                                                                                                                                                                                       |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| US-C1 | `IEngagementService` interface + `EngagementServiceImpl`. `getForOpportunity`, `getForAccount`, `addToOcrSafe`, `dismissSignal`. Uses Selectors + UoW. Custom exception extends `UtilitiesModuleException`. |
| US-C2 | `EngagementController` — `@AuraEnabled` wrappers around the Service. Returns DTO.                                                                                                                           |
| US-C3 | `EngagementDTO` + `AddToOcrResult` data classes.                                                                                                                                                            |
| US-C4 | Service + Controller happy-path Apex tests.                                                                                                                                                                 |

Wave D — LWCs (parallel after C, ~4 workers):

| ID    | Story                                                                                                                                                                                                                                                                                                                                                    |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| US-D1 | `engagementPanel` LWC — `recordContext` API (`Account` \| `Opportunity`). Compact panel layout per the SLDS wireframes. Calls `getForOpportunity` or `getForAccount` based on `@api recordContext`. Renders person rows; conditional "+ Add" button (no button when `onOcr`); "✓ on team" pill when on OCR. "View all" link opens EngagementDetailModal. |
| US-D2 | `addToDealTeamModal` LWC — opened from Panel's "+ Add" handler. Role picklist + Primary checkbox. On Opportunity scope: opp known. On Account scope: also shows Opportunity selector. Submits via `addToOcrSafe`. On success: closes; on `alreadyExists`: switches to AlreadyAddedModal flow.                                                            |
| US-D3 | `alreadyAddedModal` LWC — message: "[Name] was already added to Deal Team by [User] at [Time]." Yes (open OCR record in standard UI) / No (close — default focus).                                                                                                                                                                                       |
| US-D4 | `engagementDetailModal` LWC — large modal triggered by "View all". Group-by toggle (Person ↔ Campaign). Expandable per-asset rows with repeat-count badge. Same Add + Dismiss actions inside.                                                                                                                                                            |
| US-D5 | Jest happy-path tests for each LWC.                                                                                                                                                                                                                                                                                                                      |

Wave E — Page configs + seed data (serial after D, 1–2 workers):

| ID    | Story                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| US-E1 | Lightning App Page Flexipage for Opportunity — places `engagementPanel` (recordContext=Opportunity) on the right rail.                                                                                                                                                                                                                                                                                                                               |
| US-E2 | Lightning App Page Flexipage for Account — places `engagementPanel` (recordContext=Account) on the right rail.                                                                                                                                                                                                                                                                                                                                       |
| US-E3 | Seed-data Apex (`scripts/apex/seed-engagement-data.apex`) — Zelis-flavored, time-progressed buying-motion story: 6 weeks ago first touch (VP Ops, Network Management content), through to today's CFO download cluster. 7 contacts, 3 ACRs (incl. Deloitte consultant + independent advisor), 1 open Opportunity ($850K Network Pricing Implementation, Proposal/Quote), 2 OCRs (CRO + VP Eng), 6 Touch_Topic records, ~22 Engagement_Touch records. |
| US-E4 | `DEMO.md` walkthrough: scratch-org create cmd, deploy cmd, seed cmd, the 4-step demo flow.                                                                                                                                                                                                                                                                                                                                                           |

Wave F — Package config + smoke deploy (serial, 1 worker):

| ID    | Story                                                                                                                                                                                                                                                             |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| US-F1 | Add Unlocked Package config to `sfdx-project.json` (package alias "EngagementAttribution", `versionNumber: 0.1.0.NEXT`).                                                                                                                                          |
| US-F2 | End-to-end smoke: `sf org create scratch` → `sf project deploy start` → `sf apex run -f scripts/apex/seed-engagement-data.apex` → visual verification that the engagement panel renders on the United Healthcare Opportunity page. Document any failures + fixes. |

---

## Demo walkthrough (the 4-beat flow)

1. **Open United Healthcare Account record** in the scratch org.
   → Engagement panel renders on right rail. 7 people engaged. "View all" → grouped modal shows full per-asset history with multiple-download badges.

2. **Navigate to "Network Pricing Implementation" Opportunity.**
   → Engagement panel scoped to this opp. Deal Team section shows 2 OCR contacts. "Not on Deal Team" section shows the CFO (Sarah Johnson) with the "3× whitepaper" repeat-count badge.

3. **Click "+ Add" on the CFO row.**
   → `addToDealTeamModal` opens. Pick role "Economic Buyer". Submit.
   → OCR record created. Panel refreshes — CFO now in Deal Team section with "✓ on team" pill.

4. **Click "View all" on the Opportunity.**
   → Detail modal. Show the Person ↔ Campaign toggle. Expand a row → per-asset breakdown with type, title, repeat-count, dates.

---

## Open questions / not yet decided

- **Packaging confirmation (#5 from earlier):** assumed Unlocked Package (2GP) source-format → scratch org for Phase 1, package version created from Dev Hub at end of Phase 1. Confirm or correct on resume.
- **OpportunityContactRole "Primary" semantics:** Salesforce allows only one Primary per Opportunity. If David selects "Make primary" but a primary already exists, the standard behavior un-flags the prior primary. The race-protection modal does NOT currently cover this; flagging for Phase 1.5 polish.
- **Touch_Topic ↔ Opportunity association:** Phase 1 plan assumes Opportunity has a `Topic__c` lookup or maps via Product2. Simpler Phase 1 implementation: add a `Touch_Topic__c` lookup field directly on `Opportunity` (one-to-one for Phase 1; many-to-many in Phase 3 via junction).

---

## Inventory at handoff time

| File                                                                                                                      | Status                                                                |
| ------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/docs/BRD-Engagement-Attribution.docx`           | DONE (v0.1 with phase column)                                         |
| `/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/docs/Engagement-Attribution-Demo.pptx`          | DONE (6 slides; 4 backup slides being appended in parallel agent run) |
| `/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/docs/wireframes/sales-console-opportunity.html` | DONE (SLDS)                                                           |
| `/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/docs/wireframes/sales-console-account.html`     | DONE (SLDS)                                                           |
| `/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/docs/PHASE1-HANDOFF.md`                         | THIS FILE                                                             |
| Phase 1 build artifacts                                                                                                   | PENDING — kick off after `/compact`                                   |
| `docs/DEMO.md`                                                                                                            | PENDING — written as part of US-E4                                    |
| `docs/TDD-Engagement-Attribution.docx`                                                                                    | PENDING — written after Phase 1 demo and stakeholder feedback         |

---

## Resume protocol after `/compact`

1. Read this document first.
2. Confirm scratch org dev hub is accessible: `sf org list --target-dev-hub`. If multiple, ask which.
3. Confirm orchestration approach: wave-based, parallel workers per story bundle.
4. Launch Wave A (3 stories in parallel).
5. After Wave A commits, launch Wave B.
6. Proceed through F.
7. End state: scratch org deployed, seed data loaded, panel renders, demo walkthrough verified.

Total wall-clock estimate: ~3–4 hours with the agent team.

---

_Handoff written 2026-05-11. Living document; update as Phase 1 progresses._
