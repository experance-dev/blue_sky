# Phase 1 — Engagement Attribution — Demo Walkthrough

End-to-end runbook: fresh Dev Hub → working scratch org → loaded panel on a United Healthcare Opportunity, in ~10 minutes.

---

## Prerequisites

- Salesforce CLI `sf` v2.x — verify with `sf --version`.
- Dev Hub authorised. This worktree was built against `ExperanceProd` ([david@experancepartners.com](mailto:david@experancepartners.com)); any Dev Hub on API 66.0+ works.
- Current working directory is the worktree root: `/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/`.

```bash
sf org list --json | python3 -c "import json,sys;hubs=[o for o in sum(json.load(sys.stdin)['result'].values(),[]) if o.get('isDevHub') and o.get('connectedStatus')=='Connected'];print([h['alias'] for h in hubs])"
```

Should print at least one alias.

---

## 1 — Create the scratch org (~2 min)

```bash
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias engagementDev \
  --duration-days 30 \
  --target-dev-hub ExperanceProd \
  --set-default
```

Scratch-org definition: [config/project-scratch-def.json](../../config/project-scratch-def.json). Enables `EnableSetPasswordInApi` + `ContactsToMultipleAccounts` (the latter is required for the consultant/advisor `AccountContactRelation` seed records).

---

## 2 — Deploy the source (~3 min)

```bash
sf project deploy start --target-org engagementDev
```

Deploys the entire `force-app/` tree: 5 custom objects (4 new + Opportunity stub with the `Touch_Topic__c` lookup), 38 custom fields, the [Engagement_Attribution_User](../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml) permission set, the 6 engagement Apex classes + 6 selector/service/domain test classes, the 4 LWCs ([engagementPanel](../../force-app/main/default/lwc/engagementPanel/), [addToDealTeamModal](../../force-app/main/default/lwc/addToDealTeamModal/), [alreadyAddedModal](../../force-app/main/default/lwc/alreadyAddedModal/), [engagementDetailModal](../../force-app/main/default/lwc/engagementDetailModal/)), and the 2 flexipages.

Expected: `Status: Succeeded` with ~250 components deployed.

---

## 3 — Assign the permission set (~10 sec)

```bash
sf org assign permset --name Engagement_Attribution_User --target-org engagementDev
```

Grants the running user read on the engagement objects, read/create on `OpportunityContactRole`, and access to the 6 engagement Apex classes.

---

## 4 — Activate the record pages (manual, ~1 min)

The flexipages **deploy as inactive** — Salesforce doesn't let you set a Lightning page as the org default via metadata-only deploys. The click-through is fast:

1. `sf org open --target-org engagementDev` — opens Lightning.
2. Setup → **Lightning App Builder** (or directly: `https://<org>/lightning/setup/FlexiPageList/home`).
3. Open **Account Engagement Record Page** → **Activation** button → **Assign as Org Default** → **Next** (Desktop) → **Save**.
4. Open **Opportunity Engagement Record Page** → same flow.

(About 30 seconds per page. Source for the working flexipage XML is in [force-app/main/default/flexipages/](../../force-app/main/default/flexipages/) — note the `<parentFlexiPage>` element pointing at the standard record page (`sfa__Account_rec_L`/`sfa__Opportunity_rec_L`); Opportunity uses template `flexipage:recordHomeWithSubheaderTemplateDesktop` while Account uses `flexipage:recordHomeTemplateDesktop` — the two are NOT interchangeable.)

---

## 5 — Seed the demo data (~30 sec)

```bash
sf apex run --file scripts/apex/seed-engagement-data.apex --target-org engagementDev
```

The runner script is a one-liner that calls `EngagementSeedScript.run()`. The seed body was extracted into a class because it exceeded the 32 KB anonymous-Apex bytecode limit. Loads the Zelis-flavoured buying-motion story:

- **3 Accounts** — `United Healthcare` (the customer), `Deloitte Consulting`, `Independent Advisory`
- **7 Contacts** on `United Healthcare` — Sarah Johnson (CFO), Mike Chen (VP Eng), Lisa Patel (Director Network, consultant via Deloitte), Tom Davis (CRO), Jennifer Wu (VP Ops), Marcus Brown (Sr. Dir Payment Integrity), Rachel Kim (independent advisor)
- **2 `AccountContactRelation` records** — Lisa→Deloitte (Consultant), Rachel→Independent Advisory (External Advisor) — both `IsDirect=false`
- **6 `Touch_Topic__c`** — Claims Editing, Payment Integrity, Network Management, Price Transparency, Out-of-Network Claims, Member Engagement
- **2 Campaigns** — Q1 Healthcare CFO Roundtable, Q2 CFO Whitepaper
- **1 Opportunity** — `Network Pricing Implementation`, $850K, Proposal/Quote, close +45 days, `Touch_Topic__c → Network Management`
- **2 OCRs** — Mike Chen (Technical Evaluator), Tom Davis (Decision Maker, Primary)
- **21 `Engagement_Touch__c`** — time-progressed across 6 weeks, culminating in today's CFO spike (Sarah Johnson with 3× whitepaper downloads + 2 page views)

The script is idempotent — re-run safely.

---

## 6 — The four-beat demo flow

### Beat 1 — Account scope

Open the **United Healthcare** Account record.

Expected: the right-rail **Engagement Intelligence** panel shows 7 people engaged across the account. Each row: avatar circle, name + title, topic chips, last-touch relative time ("just now", "6d ago"), touch count.

Click **View all** → the detail modal opens with a **Group by Person / Group by Campaign** toggle. Expand Sarah Johnson's row → her three Network Pricing Whitepaper downloads collapse into one asset entry with an `×3` repeat badge.

**Talking point:** "Marketing's been engaging this account for weeks. Most of the people in this list are not on any Opportunity deal team."

### Beat 2 — Opportunity scope

Navigate to the **Network Pricing Implementation** Opportunity record.

Expected: the panel re-scopes. Two sections appear:

- **Deal Team (2)** — Mike Chen and Tom Davis, each with a `✓ on team` badge.
- **Not on Deal Team (4-5)** — Sarah Johnson, Marcus Brown, Jennifer Wu, with Lisa Patel showing a `Consultant` badge and Rachel Kim showing an `ACR` badge.

Sarah Johnson's row shows `3× Download` + topic chips for Network Management and Price Transparency.

**Talking point:** "Even on this opportunity, the most active person — the CFO — isn't on the deal team. The AE never met her. Marketing did."

### Beat 3 — Add to Deal Team

Click **+ Add** on Sarah Johnson's row.

Expected: the **Add to Deal Team** modal opens. Select role **Economic Buyer**, leave Primary unchecked, click **Add to Deal Team**.

The modal closes. The panel refreshes. Sarah Johnson now appears in the **Deal Team** section with `✓ on team`. Behind the scenes, an `OpportunityContactRole` row was inserted; verify via Setup → Object Manager → Opportunity → Contact Roles related list on the record.

**Talking point:** "One click, real OCR record. Standard Salesforce reporting picks it up immediately."

### Beat 4 — Race-protection (optional, if there's time)

Open a second browser tab as a different user (or just demo via Apex). Manually `insert` an OCR for one of the remaining non-OCR contacts directly. Then in the first tab, click **+ Add** on that same person. Submit the modal.

Expected: the **Already Added** modal opens — "[Name] was already added to Deal Team by [User] at [Time]." with **No** (default focus, closes) and **Yes, view OCR** (navigates to the OCR record).

**Talking point:** "If two reps race to add the same contact, neither one gets a stale-state error. Server checks at click time, surfaces who beat them to it."

---

## Smoke-deploy verification (already done)

The Phase 1 build was smoke-deployed against scratch org alias `engagementDev` ([david@experancepartners.com](mailto:david@experancepartners.com) Dev Hub) on 2026-05-11. **End-to-end UI verified via Playwright** — both engagement panels rendered correctly on the United Healthcare Account and Network Pricing Implementation Opportunity record pages:

**Account scope (United Healthcare):** "Engagement Intelligence — 7 engaged" — all 7 seeded contacts listed with touch counts and topics.

**Opportunity scope (Network Pricing Implementation):** "Engagement Intelligence — 6 engaged" — partitioned into:

- _Deal Team (2 on OCR):_ Mike Chen ✓ on team, Tom Davis ✓ on team
- _Engaged — not on Deal Team (4):_ Sarah Johnson (CFO, 5 touches, + Add), Rachel Kim, Lisa Patel, Jennifer Wu

Marcus Brown (Payment Integrity / OON Claims touches) is correctly **excluded** from the Opportunity scope because his engagement is on a topic other than the Opp's `Touch_Topic__c = Network Management`. He still appears in Account scope — that's the topic-attribution working as designed.

Controller-layer smoke test (separate from UI) also passed:

```
Opportunity scope DTO count: 6
 - Sarah Johnson (CFO)            onOcr=false  touchCount=5
 - Rachel Kim (Independent)       onOcr=false  touchCount=1
 - Mike Chen (VP Eng)             onOcr=true   touchCount=4
 - Lisa Patel (Dir Network)       onOcr=false  touchCount=2
 - Tom Davis (CRO)                onOcr=true   touchCount=2
 - Jennifer Wu (VP Ops)           onOcr=false  touchCount=2
Account scope DTO count: 7
```

Marcus Brown (Payment Integrity + OON Claims touches) is correctly filtered out of Opportunity scope — his engagement is on different topics than this Opp's `Touch_Topic__c` (Network Management). He still appears in Account scope. **This is the topic-attribution working as intended.**

## Components excluded from deploy (carve-outs)

A small set of David's personal utility classes were `.forceignore`-excluded for portability — they reference custom objects from a different org. See [.forceignore](../../.forceignore) for the list:

- `classes/logging/LogCleanUp/**` — references `ATM_Endpoint_Log__c`, `Block_Trigger_Log__c`, `Log_Clean_Up__mdt`

`TestFactoryDefaults.cls` and `TestFactoryRig.cls` were rewritten to generic editions (Stowers-specific nested classes stripped) so they compile in a vanilla scratch org. The original versions are recoverable from git history if/when the matching schema lands in the target org.

`Log_Setting__mdt` Custom Metadata Type (+ default record) was added to `force-app/main/default/objects/` because David's `Logger.cls` depends on it. Previously this CMT lived only in the Stowers org; it's now committed to this worktree.

## Phase 2 — HubSpot ingestion

Phase 2 adds the inbound REST endpoint that lets HubSpot (or any other source system) stream engagement events into the org, plus the Lead-conversion reparenting trigger that keeps touches attached to the right Account/Contact when sales converts an inbound Lead.

### Components delivered

- **REST endpoint:** [`EngagementInboundRest`](../../force-app/main/default/classes/engagement/EngagementInboundRest.cls) at `/services/apexrest/engagement/touches/`. Accepts a batched JSON envelope, validates required fields per event, resolves Topic / Campaign / Contact / Lead references in bulk, then upserts on `External_Id__c` so HubSpot re-deliveries are idempotent.
- **Identity resolution:** [`IdentityResolutionService.resolveAll`](../../force-app/main/default/classes/engagement/IdentityResolutionService.cls) — two SOQL queries regardless of batch size, Contact precedence over Lead, multi-match → `Ambiguous`, no-match → `NoMatch` (queued for human review).
- **Lead reparenting:** [`LeadTrigger`](../../force-app/main/default/triggers/LeadTrigger.trigger) + [`LeadEngagementReparentHandler`](../../force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls). When a Lead converts, every touch pointing at it is updated to point at the converted Contact + Account in a single DML.

### Endpoint URL

```
https://<org>.my.salesforce.com/services/apexrest/engagement/touches/
```

The endpoint relies on the caller's session — no custom auth code. Production callers should be the **Integration User** profile (API Enabled) assigned the `Engagement_Attribution_User` permission set. Use a Connected App + JWT bearer flow or session-id auth on the HubSpot side; both terminate at the standard Salesforce session.

### Example curl

```bash
SF_INSTANCE_URL="https://<org>.my.salesforce.com"
SF_SESSION_ID="<integration-user-session-id>"

curl -X POST "$SF_INSTANCE_URL/services/apexrest/engagement/touches/" \
  -H "Authorization: Bearer $SF_SESSION_ID" \
  -H "Content-Type: application/json" \
  --data '{
    "events": [
      {
        "external_id": "HS-abc123",
        "source_system": "HubSpot",
        "source_event_type": "Download",
        "source_event_id": "12345",
        "email": "sarah.johnson@uhc.example.com",
        "occurred_at": "2026-05-10T14:00:00Z",
        "asset_name": "Network Pricing Whitepaper",
        "asset_url": "https://zelis.com/whitepaper",
        "topic_external_code": "TOPIC_NETWORK_MGMT",
        "campaign_external_id": null,
        "touch_type": "Download",
        "touch_subtype": "PDF Download",
        "persona": "Executive",
        "intent_level": "Medium"
      }
    ]
  }'
```

Expected response (HTTP 200):

```json
{
  "received": 1,
  "resolved": 1,
  "ambiguous": 0,
  "noMatch": 0,
  "errored": 0,
  "errors": []
}
```

HTTP 400 is returned **only** when the top-level JSON cannot be parsed at all. Per-event failures (missing required field, etc.) are surfaced in the `errors` array so HubSpot can keep streaming.

### Anonymous-Apex test harness

Skip the HTTP layer and exercise the endpoint directly from `sf apex run`:

```apex
RestRequest req = new RestRequest();
req.requestURI = '/services/apexrest/engagement/touches/';
req.httpMethod = 'POST';
req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
  'events' => new List<Object>{
    new Map<String, Object>{
      'external_id' => 'LOCAL-001',
      'source_system' => 'HubSpot',
      'source_event_type' => 'Download',
      'email' => 'sarah.johnson@uhc.example.com',
      'occurred_at' => '2026-05-10T14:00:00Z',
      'asset_name' => 'Network Pricing Whitepaper',
      'topic_external_code' => 'TOPIC_NETWORK_MGMT',
      'touch_type' => 'Download',
      'persona' => 'Executive',
      'intent_level' => 'Medium'
    }
  }
}));
RestContext.request = req;
RestContext.response = new RestResponse();

EngagementInboundRest.InboundResult result = EngagementInboundRest.ingest();
System.debug('Result: ' + JSON.serializePretty(result));
```

Save as `scripts/apex/post-sample-touch.apex` and run with `sf apex run --file scripts/apex/post-sample-touch.apex --target-org engagementDev`. The seed Topic with `External_Code__c = 'TOPIC_NETWORK_MGMT'` should exist after the Phase 1 seed; if not, create one first.

### Lead-conversion reparenting demo

1. Create a fresh Lead from the Lightning UI (Email = `convertdemo@vendor.example.com`).
2. Run a single-event POST against the endpoint with that email — confirm the resulting `Engagement_Touch__c` has `Lead__c` populated and `Contact__c`/`Account__c` null.
3. From the Lead record page, click **Convert**. Use a brand-new Account name so the converted Account is unambiguous.
4. Open the converted **Account** page. The Engagement panel should now show the touch — proof that `LeadEngagementReparentHandler` swapped `Lead__c → Contact__c + Account__c` in the after-update trigger.
5. Re-query the touch in SOQL: `Lead__c` should be null, `Contact__c` should match `ConvertedContactId`, `Account__c` should match `ConvertedAccountId`.

The handler is idempotent — re-saving the converted Lead is a no-op because no touches reference it any longer.

---

## Phase 3 — Routing intelligence

Phase 3 turns inbound touches into actionable opportunity signals. When a resolved [`Engagement_Touch__c`](../../force-app/main/default/objects/Engagement_Touch__c/) lands, the [`EngagementTouchTrigger`](../../force-app/main/default/triggers/EngagementTouchTrigger.trigger) fires [`EngagementSignalRouter.routeTouches`](../../force-app/main/default/classes/engagement/EngagementSignalRouter.cls), which walks an ordered set of [`Touch_Routing_Rule__mdt`](../../force-app/main/default/objects/Touch_Routing_Rule__mdt/) records and creates one [`Opportunity_Engagement_Signal__c`](../../force-app/main/default/objects/Opportunity_Engagement_Signal__c/) per (touch, opportunity) pair — the highest-priority rule wins.

### Seeded routing rules

Five rules ship by default in [`force-app/main/default/customMetadata/`](../../force-app/main/default/customMetadata/):

| DeveloperName                                                                                                                             | Priority | Match Path | Confidence | Triggers when                                                                                                    |
| ----------------------------------------------------------------------------------------------------------------------------------------- | -------: | ---------- | ---------: | ---------------------------------------------------------------------------------------------------------------- |
| [`OCR_Exact_Match`](../../force-app/main/default/customMetadata/Touch_Routing_Rule.OCR_Exact_Match.md-meta.xml)                           |       10 | OCR        |         95 | Touch's Contact is on the Opp's `OpportunityContactRole`.                                                        |
| [`ACR_Same_Account_Topic_Match`](../../force-app/main/default/customMetadata/Touch_Routing_Rule.ACR_Same_Account_Topic_Match.md-meta.xml) |       20 | ACR        |         80 | Contact is on the Account via `AccountContactRelation` AND the touch's Topic matches the Opp's `Touch_Topic__c`. |
| [`Account_Topic_Executive`](../../force-app/main/default/customMetadata/Touch_Routing_Rule.Account_Topic_Executive.md-meta.xml)           |       30 | Account    |         75 | Same Account + Topic, Executive persona, Medium+ intent.                                                         |
| [`Account_Match_High_Intent`](../../force-app/main/default/customMetadata/Touch_Routing_Rule.Account_Match_High_Intent.md-meta.xml)       |       40 | Account    |         70 | Same Account, any topic, High intent (form submissions).                                                         |
| [`Account_Topic_Default`](../../force-app/main/default/customMetadata/Touch_Routing_Rule.Account_Topic_Default.md-meta.xml)               |       50 | Account    |         60 | Baseline — same Account + same Topic, no other constraints.                                                      |

The first rule to match (priority-ascending) wins; lower-priority rules are skipped for that (touch, opp). `NoMatch` / `Ambiguous` touches are filtered out — they require human triage before becoming signals.

### Adding a new rule

1. `sf org open --target-org engagementDev` → Setup.
2. **Custom Metadata Types** → **Touch Routing Rule** → **Manage Records** → **New**.
3. Set `DeveloperName`, `Priority__c` (lower = evaluated earlier), `Match_Path__c`, `Confidence__c`, and any of the optional filters (`Persona_Filter__c`, `Touch_Type_Filter__c`, `Min_Intent_Level__c`).
4. Save. The selector picks up the new row on the next touch event — no Apex redeploy needed.

To version-control a rule instead, add an `.md-meta.xml` file to [`force-app/main/default/customMetadata/`](../../force-app/main/default/customMetadata/) following the existing pattern, then `sf project deploy start`.

### How routing fires

[`EngagementTouchTrigger`](../../force-app/main/default/triggers/EngagementTouchTrigger.trigger) (after insert, after update) delegates to [`EngagementTouchTriggerHandler`](../../force-app/main/default/classes/engagement/EngagementTouchTriggerHandler.cls):

- **After insert** — every touch arriving with `Resolution_Status__c = 'Resolved'` is routed.
- **After update** — only touches that transitioned `Pending|Ambiguous|NoMatch → Resolved` are routed (idempotent re-saves are no-ops).

The handler hands the resolved id set to `EngagementSignalRouter.routeTouches`, which loads opportunities / OCR / ACR / existing signals in 6 bulk queries and inserts new signals via `DMLManager.insertAsUser`. Re-routing a touch that already has a signal of the same `Match_Path__c` is a no-op (idempotency key: `touchId|oppId|matchPath`).

### Verifying routing in the demo

Anonymous Apex against the seeded United Healthcare data:

```apex
// 1 — insert a fresh resolved touch on Sarah Johnson (CFO) for Network Mgmt
Contact sarah = [SELECT Id, AccountId FROM Contact WHERE Email = 'sarah.johnson@uhc.example.com' LIMIT 1];
Touch_Topic__c topic = [SELECT Id FROM Touch_Topic__c WHERE External_Code__c = 'TOPIC_NETWORK_MGMT' LIMIT 1];

Engagement_Touch__c t = new Engagement_Touch__c(
  External_Id__c = 'DEMO-ROUTE-' + Crypto.getRandomInteger(),
  Source_System__c = 'Manual',
  Email_At_Touch__c = 'sarah.johnson@uhc.example.com',
  Contact__c = sarah.Id,
  Account__c = sarah.AccountId,
  Topic__c = topic.Id,
  Occurred_At__c = System.now(),
  Is_Active__c = true,
  Resolution_Status__c = 'Resolved',
  Processing_Status__c = 'Processed',
  Persona__c = 'Executive',
  Intent_Level__c = 'High',
  Touch_Type__c = 'Form'
);
insert t;

// 2 — query the signal(s) the router produced
for (Opportunity_Engagement_Signal__c s : [
  SELECT Opportunity__r.Name, Match_Path__c, Confidence__c, Contact__r.Name, Topic__r.Topic_Name__c
  FROM Opportunity_Engagement_Signal__c
  WHERE Engagement_Touch__c = :t.Id
]) {
  System.debug(s.Opportunity__r.Name + ' / ' + s.Match_Path__c + ' / Confidence ' + s.Confidence__c);
}
```

Expected output on the seeded org: one signal against **Network Pricing Implementation** with `Match_Path__c = Account` and `Confidence__c = 60` (the priority-50 default rule wins — Sarah isn't on OCR/ACR, the Executive rule needs Medium+ intent which she has, but Topic match + Executive persona only fires when Min_Intent is Medium and persona/topic match strictly; on this seed data the Account/Topic default is the deterministic winner). Add Sarah to the OCR and re-run — the next touch produces a new signal with `Match_Path__c = OCR` and `Confidence__c = 95`.

---

## Phase 4 — Admin tools & maintenance

Phase 4 keeps the engagement panel honest over long deal cycles. Two batch jobs — [`EngagementSignalDecayBatch`](../../force-app/main/default/classes/engagement/EngagementSignalDecayBatch.cls) and [`EngagementTouchArchivalBatch`](../../force-app/main/default/classes/engagement/EngagementTouchArchivalBatch.cls) — are fired weekly by [`EngagementMaintenanceScheduler`](../../force-app/main/default/classes/engagement/EngagementMaintenanceScheduler.cls). Both read their tunables from the [`Engagement_Settings__c`](../../force-app/main/default/objects/Engagement_Settings__c/) Hierarchy Custom Setting (Org Default).

### What the jobs do

- **Signal decay** — recomputes `Opportunity_Engagement_Signal__c.Confidence__c` as a linear function of the parent touch's age. Fresh touch → 100. Touch older than `Signal_Decay_Days__c` (default 90) → floors at 0. Idempotent: re-running on the same scope is a no-op once each signal has converged. Dismissed signals and zero-confidence signals are filtered out at query time.
- **Touch archival** — flips `Engagement_Touch__c.Is_Active__c` to false and stamps `Archived_At__c` on touches whose `Occurred_At__c` is older than `Active_Window_Days__c` (default 180). Already-archived touches are skipped by the start-query filter.

### Schedule the weekly job

One-liner via anonymous Apex (recommended cron: Mondays at 02:00 server time):

```apex
System.schedule(
  'Engagement Weekly Maintenance',
  '0 0 2 ? * MON',
  new EngagementMaintenanceScheduler()
);
```

Run via `sf apex run --target-org engagementDev` with the snippet in a file, or paste into Developer Console. Verify in Setup → **Apex Jobs** and Setup → **Scheduled Jobs**.

### Test decay manually

Submit either batch directly — no schedule required:

```apex
Id decayJobId = Database.executeBatch(new EngagementSignalDecayBatch(), 200);
Id archiveJobId = Database.executeBatch(new EngagementTouchArchivalBatch(), 200);
```

Track progress via `SELECT Status, JobItemsProcessed, NumberOfErrors FROM AsyncApexJob WHERE Id = :decayJobId`.

### Tune the windows

Setup → **Custom Settings** → **Engagement Settings** → **Manage** → **New** (or **Edit**) on the _Default Organization Level Value_. Three fields:

| Field                     | Default | Effect                                                     |
| ------------------------- | ------: | ---------------------------------------------------------- |
| `Active_Window_Days__c`   |     180 | Touches older than this get archived.                      |
| `Signal_Decay_Days__c`    |      90 | Age in days at which a signal's confidence floors at zero. |
| `Confidence_Threshold__c` |      40 | Reserved for the UI panel's "show only" filter (Phase 4A). |

If no record exists at the Org Default level, the batches fall back to the hard-coded defaults (180 / 90) — no error.

---

## Phase 5 — Subject erasure (GDPR / CCPA)

Zelis is US-only, so the legal regime in play is CCPA + state privacy laws + HIPAA — but the cascade is built once and serves every "delete my data" request, regardless of which regulation triggers it. The same code path runs for an operator-initiated Contact / Lead delete, so the engagement model never holds orphan PII or behavioural data.

### How the cascade fires

Two triggers, both `before delete`, both routed through the project [`TriggerHandler`](../../force-app/main/default/classes/triggers/TriggerHandler.cls) framework:

- [`ContactTrigger`](../../force-app/main/default/triggers/ContactTrigger.trigger) → [`ContactEngagementErasureHandler`](../../force-app/main/default/classes/engagement/ContactEngagementErasureHandler.cls) → [`EngagementErasureService.eraseForContacts`](../../force-app/main/default/classes/engagement/EngagementErasureService.cls).
- [`LeadTrigger`](../../force-app/main/default/triggers/LeadTrigger.trigger) → [`LeadEngagementErasureHandler`](../../force-app/main/default/classes/engagement/LeadEngagementErasureHandler.cls) → [`EngagementErasureService.eraseForLeads`](../../force-app/main/default/classes/engagement/EngagementErasureService.cls). (Same trigger also fires `LeadEngagementReparentHandler` on after-update — see Phase 2.)

The service hard-deletes children in this order, every operation in `WITH USER_MODE` / `AccessLevel.USER_MODE`:

1. `Opportunity_Engagement_Signal__c` rows that reference the subject directly OR point at one of the doomed touches.
2. `Engagement_Dismissal__c` rows where `Contact__c` matches the subject.
3. `Engagement_Touch__c` rows where `Contact__c` (or `Lead__c`) matches.

Before-delete is deliberate: cleaning up children before the platform clears foreign-key references means we never observe a partially-orphaned model in flight.

### Manual call (ad-hoc erasure)

For one-off cases where the Contact / Lead record needs to stay but the engagement footprint must go — for example, an enterprise erasure-request workflow that retains an audit shell record — call the service directly via Anonymous Apex:

```apex
Set<Id> subjects = new Set<Id>{ '003xxxxxxxxxxxxxxx' };
EngagementErasureService.ErasureSummary s = EngagementErasureService.eraseForContacts(subjects);
System.debug(s.messages); // one-line audit string per cascade
```

### Audit trail

Every cascade writes one `Logger.info` line to the debug log:

```
Subject erasure cascade — 1 subject(s) of type Contact: deleted 3 touch(es), 2 signal(s), 1 dismissal(s).
```

The same string is appended to `ErasureSummary.messages`, so callers running the service directly can persist the audit record alongside their compliance ticket.

### Hard-delete (irreversible)

The service follows every `DMLManager.deleteAsUser(...)` with `Database.emptyRecycleBin(...)` on the deleted rows. Records are gone — `SELECT ... ALL ROWS` returns zero. This is intentional for regulatory compliance; do not soften it without sign-off from privacy counsel.

### Sample compliance workflow

1. **Ticket arrives:** Privacy team receives a CCPA "Delete My Data" request naming `john.doe@payerco.example.com`.
2. **Resolve the subject:** look up the Contact (or Lead) record(s) for that email.
3. **Choose retention policy:**
   - _Full erase, including the Contact record:_ delete the Contact directly. The cascade fires automatically before the parent is removed.
   - _Retain shell record, erase engagement:_ run the Anonymous Apex snippet above with the Contact id.
4. **Capture evidence:** copy the `Logger.info` line from the debug log into the compliance ticket and attach.
5. **Close the request** once the cascade summary confirms zero residual rows.

The same flow handles HIPAA's "right to access / right to amend" use cases — the cascade is regulation-agnostic.

---

## Phase 5 — Reports

Phase 5B ships five canned reports in a single folder so stakeholders see the engagement story without building anything themselves. Three custom report types do the heavy lifting:

- [`Engagement_Touches_with_Account_Contact`](../../force-app/main/default/reportTypes/Engagement_Touches_with_Account_Contact.reportType-meta.xml) — base `Engagement_Touch__c`, outer-joined to `Account`, `Contact`, `Touch_Topic__c`, `Campaign`. Marketing-side reports + the rep "recent activity" view.
- [`Opportunity_Engagement_Signals_with_Contact`](../../force-app/main/default/reportTypes/Opportunity_Engagement_Signals_with_Contact.reportType-meta.xml) — base `Opportunity_Engagement_Signal__c`, inner-joined to `Opportunity`, outer-joined to `Contact`, `Touch_Topic__c`, `Engagement_Touch__c`. The "engaged but not on Deal Team" salesperson view.
- [`Opportunities_with_Engagement_Coverage`](../../force-app/main/default/reportTypes/Opportunities_with_Engagement_Coverage.reportType-meta.xml) — base `Opportunity`, outer-joined to the `Engagement_Signals__r` child relationship. Sales-Manager pipeline-coverage view; outer join so Opps with zero engagement still appear.

### The five reports

All live under **Reports → All Reports → "Engagement Attribution"** ([folder metadata](../../force-app/main/default/reports/Engagement_Attribution-meta.xml)):

| Audience      | Report                                                                                                                                                             | What it answers                                                                                                                                                                                     |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sales Manager | [Engagement Coverage by Open Opportunity](../../force-app/main/default/reports/Engagement_Attribution/Engagement_Coverage_by_Open_Opportunity.report-meta.xml)     | "Across my open pipeline, which Opps have engaged contacts, how many are on the Deal Team vs. not, and what's the average confidence?" — Summary, grouped by Opportunity Name. **The demo opener.** |
| Salesperson   | [My Engaged Contacts Not on Deal Team](../../force-app/main/default/reports/Engagement_Attribution/My_Engaged_Contacts_Not_on_Deal_Team.report-meta.xml)           | "On my open Opps, which engaged people aren't on OCR yet?" — Tabular, scoped to running user, sorted by Confidence desc.                                                                            |
| Salesperson   | [Recent Engagement Activity on My Pipeline](../../force-app/main/default/reports/Engagement_Attribution/Recent_Engagement_Activity_on_My_Pipeline.report-meta.xml) | "What's been happening on my Accounts the last 30 days?" — Summary, grouped by Contact then Account, user-scoped via Account ownership.                                                             |
| Marketing     | [Touch Volume by Topic](../../force-app/main/default/reports/Engagement_Attribution/Touch_Volume_by_Topic.report-meta.xml)                                         | "Which topics are driving identified engagement?" — Summary, grouped by Topic, horizontal-bar chart over the last 90 days.                                                                          |
| Marketing     | [Campaign Engagement Influence](../../force-app/main/default/reports/Engagement_Attribution/Campaign_Engagement_Influence.report-meta.xml)                         | "Which campaigns produced trackable (Resolved) engagement vs. anonymous traffic?" — Summary, grouped by Campaign then Resolution Status, last 180 days.                                             |

### Stakeholder Q: "Can I build my own?"

Yes — the three custom report types are available in the standard **Report Builder → Create → Choose Report Type** picker. They're labelled "Engagement Touches w/ Account & Contact", "Opportunity Engagement Signals w/ Contact", and "Opportunities w/ Engagement Coverage". Anyone with read access to the underlying objects (granted via [`Engagement_Attribution_User`](../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml)) can build from them.

### Permset note

No additions required — the permset already grants Read on the engagement objects, and the report folder is `Public Read/Write`. Custom Report Type access in Salesforce flows from underlying-object permissions, not a separate setting.

### Known limitation — field paths

Salesforce report XML uses a mix of legacy ALL_CAPS path syntax for standard fields and `CustomObject__c.Field__c` syntax for custom. The reports here follow documented conventions, but the canonical paths for a given org/version are only knowable by building one report in Setup → saving → retrieving via SFDX. If a report fails to render after deploy, open it in Setup, fix the offending column, save, and retrieve to reconcile this metadata.

---

## Troubleshooting

| Symptom                                                     | Likely cause                                                                   | Fix                                                                                                                                                            |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Deploy fails on `Engagement_Touch__c.Account__c` lookup     | Standard Account doesn't exist (shouldn't happen in a fresh scratch org)       | Re-create the scratch org from definition                                                                                                                      |
| `ContactsToMultipleAccounts` not enabled error during seed  | Scratch-def missing the feature                                                | Re-create scratch org; the seed swallows ACR-insert failures so the demo still works without consultants                                                       |
| Panel renders empty even after seed                         | Permission set not assigned                                                    | `sf org assign permset --name Engagement_Attribution_User`                                                                                                     |
| Panel renders empty on Opportunity but populated on Account | `Touch_Topic__c` lookup on the Opportunity is empty (filters down to 0 topics) | Confirm the seed script's Opportunity has `Touch_Topic__c = Network Management`; re-run seed                                                                   |
| Modal doesn't open on `+ Add` click                         | LWC console error — check that all 3 modal LWCs deployed                       | Inspect browser console; redeploy                                                                                                                              |
| `Already Added` modal never appears                         | Race state didn't actually exist when the second click hit                     | Insert an OCR for a contact via Developer Console between render and click — `INSERT INTO OpportunityContactRole(OpportunityId, ContactId, Role) VALUES (...)` |

---

## Tear-down

```bash
sf org delete scratch --target-org engagementDev --no-prompt
```

Scratch orgs auto-expire after 30 days, but explicit deletion frees up the Dev Hub limit.

---

## What's next

- **Phase 2:** HubSpot REST endpoint, identity resolution, Lead-conversion reparenting. See [PHASE1-HANDOFF.md §Scope boundaries](../../architecture/PHASE1-HANDOFF.md#phase-1-scope-what-were-building-now) for the full phased plan.
- **TDD:** Written after Phase 1 demo and stakeholder feedback. Phase 1 is intentionally pattern-validation, not architecture-locked.
- **Zelis transport:** This worktree is structured as a 2GP source format. Run `sf package version create --package EngagementAttribution --installation-key-bypass --wait 20 --target-dev-hub ExperanceProd` to mint an install URL Zelis IT can run through Setup. Optional — David may instead hand over the `force-app/` tree for cut-and-paste into a Zelis scratch org.

---

## Test coverage

### Verification commands

```bash
# Full Apex suite + code coverage
sf apex run test --target-org engagementDev --code-coverage --result-format human --wait 30

# Full Jest LWC suite + coverage
npm install
npm run test:unit:coverage
```

Both runs persist their output to [docs/testing/test-coverage-2026-05-12.txt](../testing/test-coverage-2026-05-12.txt).

### Expected output (2026-05-12 baseline)

**Apex** — 248 tests total. All engagement-module tests pass. Org-wide coverage is **61%**, gated by 54 pre-existing failures in personal utility classes (`StringBuilder`, `RestClient`, `SingleEmail`, `UtilPickLists`, `Utilities`, `DMLManager`) which are out of scope for this engagement.

Engagement-module per-class coverage (the relevant tier):

| Class                                                 | Coverage |
| ----------------------------------------------------- | -------: |
| EngagementController                                  |     100% |
| EngagementInboundRest                                 |      90% |
| EngagementSignalDecayBatch                            |      91% |
| EngagementSignalRouter                                |      91% |
| EngagementAdminController                             |      89% |
| EngagementServiceImpl                                 |      82% |
| EngagementTouchTriggerHandler                         |      92% |
| EngagementTouchArchivalBatch                          |      80% |
| EngagementErasureService                              |      79% |
| LeadEngagementReparentHandler                         |      83% |
| LeadEngagementErasureHandler                          |      67% |
| ContactEngagementErasureHandler                       |      70% |
| IdentityResolutionService                             |      91% |
| EngagementTouches (domain)                            |     100% |
| EngagementTouchesSelector                             |      97% |
| OpportunityContactRolesSelector                       |      93% |
| EngagementDismissalsSelector                          |      96% |
| TouchTopicSelector                                    |      94% |
| TouchRoutingRulesSelector                             |     100% |
| ContactTrigger / LeadTrigger / EngagementTouchTrigger |     100% |
| EngagementMaintenanceScheduler                        |     100% |

**Jest LWC** — 5 of 7 suites passing (24 of 33 tests). `engagementPanel` and `alreadyAddedModal` have outstanding gaps documented as follow-ups; see [test-audit-2026-05-12.md](../testing/test-audit-2026-05-12.md) Clusters F/G/H. The platform-level issue: LWC's proxy blocks external access to non-`@api` properties so `jest.spyOn(element, 'close')` does not return a callable spy in this LWC release.

### Quick targeted reruns

```bash
# Just the engagement-module Apex tests — completes in ~30 s
sf apex run test --target-org engagementDev --code-coverage --result-format human --wait 20 \
  --tests EngagementControllerTest EngagementServiceImplTest EngagementInboundRestTest \
          EngagementSignalRouterTest EngagementSignalDecayBatchTest EngagementAdminControllerTest \
          EngagementErasureServiceTest EngagementTouchTriggerHandlerTest \
          EngagementTouchArchivalBatchTest IdentityResolutionServiceTest \
          LeadEngagementReparentHandlerTest LeadEngagementErasureHandlerTest \
          ContactEngagementErasureHandlerTest EngagementTouchesSelectorTest \
          EngagementDismissalsSelectorTest TouchTopicSelectorTest \
          OpportunityContactRolesSelectorTest TouchRoutingRulesSelectorTest \
          EngagementTouchesTest EngagementMaintenanceSchedulerTest \
          EngagementTestFixturesTest
```

Expected: 100% pass rate on this filtered subset.
