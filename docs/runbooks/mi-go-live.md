---
title: Marketing Influence (MI) — Production Go-Live Runbook
author: David Wood
audience: Release engineers, Salesforce admins, HubSpot admins, Marketing Ops
target-environment: Production
last-updated: 2026-05-14
estimated-duration: 3 hours (deploy 45 min · config 60 min · HubSpot wiring 30 min · smoke 45 min)
maintenance-window: Off-hours strongly preferred; LWC re-render impact on rep sessions
---

# Marketing Influence (MI) — Production Go-Live Runbook

> **Note:** MI is the customer-facing name for the Engagement Attribution feature. Internal/code names use `Engagement_*`; user-facing artifacts use "Marketing Influence." For day-2 operations, see [operations/apex-invocation-runbook.md](../../.claude/worktrees/feature-engagement-attribution/docs/operations/apex-invocation-runbook.md). For demo flow, see [DEMO.md](../../.claude/worktrees/feature-engagement-attribution/docs/users/DEMO.md).

## Pre-flight checklist

Confirm **before** the maintenance window starts. Each line item must be green.

- [ ] **Source branch tagged.** Production cut from `feature/engagement-attribution` at tag `mi-prod-YYYYMMDD`. Confirm: `git log --oneline tags/mi-prod-YYYYMMDD -1`.
- [ ] **All Apex tests pass in staging.** `sfdx force:apex:test:run -c -r human -w 30`. Target: 100% coverage on Engagement classes, org-wide >= 75%. Execution time recorded: `_____` (per [test quality metric](../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_test_quality_metrics.md)).
- [ ] **All LWC Jest tests pass.** `npx jest --coverage`.
- [ ] **BRD approved.** [BRD-Engagement-Attribution.docx](../../.claude/worktrees/feature-engagement-attribution/docs/architecture/BRD-Engagement-Attribution.docx) — stakeholder sign-off in the doc.
- [ ] **MI demo deck reviewed.** [Marketing-Influence-Demo.pptx](../../.claude/worktrees/feature-engagement-attribution/docs/architecture/Marketing-Influence-Demo.pptx) walked through with execs.
- [ ] **HubSpot integration user created in production.** Username: `mi-integration@<orgname>.com` (or your org's convention). License: Salesforce Platform or Salesforce. Verify the user can log in.
- [ ] **HubSpot side credentials ready.** HubSpot Operations has the production Integration User credentials configured in the HubSpot workflow / outbound action.
- [ ] **Production data export taken** within 24 hours.
- [ ] **Stakeholders notified.** Release email to: Sales (all AEs), Marketing Ops, Sales Ops, Support.
- [ ] **Rollback path validated** in staging.

## Components shipping

### Apex (engagement/)

- Selectors (5): `EngagementTouchesSelector`, `OpportunityContactRolesSelector`, `TouchTopicSelector`, `TouchRoutingRulesSelector`, `EngagementDismissalsSelector`
- Services: `EngagementServiceImpl` (implements `IEngagementService`), `EngagementSignalRouter`, `IdentityResolutionService`, `EngagementErasureService`
- Surface: `EngagementController`, `EngagementAdminController`, `EngagementInboundRest`
- DTOs: `EngagementDTO`, `AddToOcrResult`
- Triggers + handlers: `EngagementTouchTrigger`, `EngagementTouchTriggerHandler`, `ContactEngagementErasureHandler`, `LeadEngagementErasureHandler`, `LeadEngagementReparentHandler`
- Async: `EngagementSignalDecayBatch`, `EngagementTouchArchivalBatch`, `EngagementMaintenanceScheduler`
- Domain skeleton: `EngagementTouches`
- Filters: `KeepIfAccountHasOpenOpportunity`, `KeepIfContactIsOnOpenOpportunityTeam`
- Exception: `EngagementException`
- All `*Test` classes

### Schema

- Custom objects: `Engagement_Touch__c`, `Opportunity_Engagement_Signal__c`, `Engagement_Dismissal__c`, `Touch_Topic__c`
- Custom fields on `Opportunity`, `Account`, `Lead`
- Custom metadata type: `Touch_Routing_Rule__mdt`
- Custom metadata records: 5 default routing rules (`OCR_Direct`, `ACR_Direct`, `Domain_Match`, `Consultant_Influence`, `Account_Topic_Default`)
- Custom setting: `Engagement_Settings__c` (hierarchy)

### LWC

- `engagementPanel`, `engagementDetailModal`, `addToDealTeamModal`, `alreadyAddedModal`, `engagementAdminApp`

### Permsets

- `Engagement_Attribution_User` (end-user), `Engagement_Attribution_Admin` (admin overlay)

> **TODO:** No dedicated CSI-7162 / MI integration permset exists in source today. The HubSpot integration user's ApexREST + object access flows through the user's profile (or `Engagement_Attribution_Admin` as a stop-gap). If we want a least-privilege `Engagement_Attribution_Integration` permset, that's a separate ticket.

### Lightning App Builder pages

- `Opportunity_Record_Page_MI`
- `Account_Record_Page_MI`
- `MI_Admin_App`

Manifest of record: [manifest/package.xml](../../manifest/package.xml) (engagement section).

## Deploy steps

### Step 1 — Open release shell

```bash
cd /Users/david/Work/Zelis
git fetch --all --tags
git checkout tags/mi-prod-YYYYMMDD
sfdx force:org:list  # confirm prod alias
```

If not authed:

```bash
sfdx force:auth:web:login -a prod -r https://login.salesforce.com
```

### Step 2 — Pre-deploy validation (check-only)

```bash
sfdx force:source:deploy \
  -x manifest/package.xml \
  -u prod \
  -l RunSpecifiedTests \
  -r EngagementInboundRestTest,IdentityResolutionServiceTest,EngagementSignalRouterTest,EngagementServiceImplTest,EngagementControllerTest,EngagementErasureServiceTest,LeadEngagementReparentHandlerTest,EngagementTouchArchivalBatchTest,EngagementSignalDecayBatchTest,EngagementTouchTriggerHandlerTest,EngagementMaintenanceSchedulerTest \
  -c \
  -w 90
```

Expected: 100% pass on the named tests. Any failure aborts go-live.

### Step 3 — Deploy schema first (one-shot)

```bash
sfdx force:source:deploy \
  -x manifest/package.xml \
  -u prod \
  -l RunSpecifiedTests \
  -r EngagementInboundRestTest,IdentityResolutionServiceTest,EngagementSignalRouterTest,EngagementServiceImplTest,EngagementControllerTest,EngagementErasureServiceTest,LeadEngagementReparentHandlerTest,EngagementTouchArchivalBatchTest,EngagementSignalDecayBatchTest,EngagementTouchTriggerHandlerTest,EngagementMaintenanceSchedulerTest \
  -w 90
```

Capture the deploy Id (`0Af...`).

### Step 4 — Confirm custom-object FLS

Open Setup -> Object Manager -> `Engagement_Touch__c` -> Field-Level Security. Confirm fields are visible to the `Engagement_Attribution_User` and `Engagement_Attribution_Admin` permsets per the deploy.

Repeat for `Opportunity_Engagement_Signal__c`, `Engagement_Dismissal__c`, `Touch_Topic__c`.

### Step 5 — Schedule maintenance scheduler

After deploy, the `EngagementMaintenanceScheduler` is **not** automatically scheduled. Run once from anonymous Apex to start the weekly cadence:

```apex
EngagementMaintenanceScheduler.scheduleWeekly();
```

Verify in Setup -> Apex -> Scheduled Apex. Expect a row named `Engagement Maintenance` running weekly (Sundays 02:00 by default — adjust per ops preference).

## Named credential setup

**MI does not require an outbound Named Credential.** MI is one-way ingest from HubSpot to Salesforce. Inbound auth is via Salesforce session for the Integration User (covered in the [HubSpot wiring](#hubspot-wiring) section below).

> **Note:** If a future story adds a HubSpot callback, that will introduce a Named Credential. Today, none is needed.

## HubSpot wiring

This is the load-bearing config step. Coordinate with HubSpot Operations.

### Step 1 — Confirm the Integration User credentials in HubSpot

In HubSpot:

1. Open the production HubSpot instance.
2. Navigate to **Settings -> Integrations -> Connected Apps -> Salesforce** (or to the custom HubSpot Workflow that holds the SF outbound action — depends on your HubSpot side wiring).
3. Confirm the Salesforce credentials in use are for the production Integration User (`mi-integration@<orgname>.com`).
4. If new credentials are needed: HubSpot Ops generates a Salesforce session token for the Integration User via OAuth and stores it in HubSpot.

### Step 2 — Configure the outbound webhook / workflow

In HubSpot, the workflow (or webhook) that emits engagement events to Salesforce must point at:

```
POST https://<orgname>.my.salesforce.com/services/apexrest/engagement/touches/
Authorization: Bearer <Integration User session token>
Content-Type: application/json
```

Body (per event):

```json
{
  "events": [
    {
      "external_id": "<HubSpot unique event id>",
      "email": "<contact email>",
      "occurred_at": "2026-05-14T12:34:56Z",
      "topic_external_code": "<matches Touch_Topic__c.External_Code__c>",
      "touch_type": "WHITEPAPER_DOWNLOAD | FORM_FILL | WEBINAR | EMAIL_CLICK | ...",
      "campaign_name": "<matches Campaign.Name in SFDC>",
      "intent_level": 0-100,
      "raw_payload": "<optional JSON blob>"
    }
  ]
}
```

> **Note:** Send batches of up to 200 events per POST for best performance. The endpoint handles single events, but batching reduces governor-limit pressure.

### Step 3 — Confirm Touch Topics align with HubSpot

Each `topic_external_code` HubSpot sends **must** exist in `Touch_Topic__c.External_Code__c`. If HubSpot emits a code with no matching topic, the touch ingests but `Touch_Topic__c` is null on the resulting `Engagement_Touch__c`.

Verify the mapping with Marketing Ops:

```apex
List<Touch_Topic__c> topics = [SELECT External_Code__c, Name, Active__c FROM Touch_Topic__c WHERE Active__c = true ORDER BY External_Code__c];
for (Touch_Topic__c t : topics) {
    System.debug(t.External_Code__c + ' -> ' + t.Name);
}
```

Cross-reference with HubSpot's topic taxonomy. Add missing rows via Setup -> Object Manager -> Touch Topic -> New, or deploy as part of the next release.

### Step 4 — Send a test event (HubSpot side)

HubSpot Operations triggers a test event for a known internal email (e.g. yours):

```bash
curl -X POST 'https://<orgname>.my.salesforce.com/services/apexrest/engagement/touches/' \
  -H 'Authorization: Bearer <session token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "events": [{
      "external_id": "hs-smoke-001",
      "email": "your.email@<orgname>.com",
      "occurred_at": "2026-05-14T12:00:00Z",
      "topic_external_code": "PRICING",
      "touch_type": "WHITEPAPER_DOWNLOAD",
      "campaign_name": "MI Smoke",
      "intent_level": 75
    }]
  }'
```

Expected response: `{"success": true, "processed": 1, "results": [{"external_id": "hs-smoke-001", "resolution_status": "Resolved"}]}`.

## CMDT row population

Five `Touch_Routing_Rule__mdt` records ship by default. Verify they deployed:

```apex
List<Touch_Routing_Rule__mdt> rules = [
    SELECT DeveloperName, Priority__c, Match_Path__c, Active__c, Default_Confidence__c
    FROM Touch_Routing_Rule__mdt
    ORDER BY Priority__c
];
for (Touch_Routing_Rule__mdt r : rules) {
    System.debug(r.Priority__c + ': ' + r.DeveloperName + ' (' + r.Match_Path__c + ', conf=' + r.Default_Confidence__c + ', active=' + r.Active__c + ')');
}
```

Expected output:

```
10: OCR_Direct (OCR, conf=100, active=true)
20: ACR_Direct (ACR, conf=80, active=true)
30: Domain_Match (Domain, conf=70, active=true)
40: Consultant_Influence (Consultant, conf=65, active=true)
50: Account_Topic_Default (Account, conf=60, active=true)
```

If a rule needs editing: Setup -> Custom Metadata Types -> Touch Routing Rule -> Manage Records.

## Custom setting population

Set the `Engagement_Settings__c` org default:

1. Setup -> Custom Settings -> Engagement Settings -> Manage.
2. Click **New** under "Default Organization Level Value" (if absent).
3. Set:
   - `Active_Window_Days__c` = `180`
   - `Signal_Decay_Days__c` = `90`
   - `Confidence_Threshold__c` = `40`
4. Save.

Or via anonymous Apex:

```apex
Engagement_Settings__c s = Engagement_Settings__c.getOrgDefaults();
if (s.Id == null) {
    s = new Engagement_Settings__c();
}
s.Active_Window_Days__c = 180;
s.Signal_Decay_Days__c = 90;
s.Confidence_Threshold__c = 40;
upsert s;
```

## Permset assignment

### Step 1 — Grant inbound REST access to the HubSpot integration user

The integration user that runs the inbound REST callouts needs ApexREST + write access to `Engagement_Touch__c`. Until a dedicated integration permset exists, assign `Engagement_Attribution_Admin` to the dedicated integration user as a stop-gap:

```bash
sfdx force:user:permset:assign -u prod -n Engagement_Attribution_Admin -o mi-integration@<orgname>.com
```

> **Note:** Only assign to the dedicated integration user. Do **not** assign `Engagement_Attribution_Admin` to humans as a side effect of this step — they should be assigned via Step 3 instead.
>
> **TODO:** See the [Permsets](#permsets) note above re: shipping an `Engagement_Attribution_Integration` permset in a future release.

### Step 2 — Assign `Engagement_Attribution_User` to the sales team

```bash
sfdx force:data:soql:query -u prod -q "SELECT Id, Username FROM User WHERE IsActive = true AND ProfileId IN (SELECT Id FROM Profile WHERE Name IN ('Sales User', 'Sales Manager', 'Account Executive'))" -r csv > /tmp/sales-users.csv

# Manual loop or use a single call:
sfdx force:user:permset:assign -u prod -n Engagement_Attribution_User -o <comma-separated-usernames>
```

### Step 3 — Assign `Engagement_Attribution_User` to Marketing Ops team

Per the sales-team pattern above, scoped to Marketing Operations users.

### Step 4 — Assign `Engagement_Attribution_Admin` to feature owners

Per the sales-team pattern above, scoped to David Wood + designated support tier.

## Lightning App Builder activation

The deploy ships record pages but doesn't activate them. Activate per object:

1. Setup -> Object Manager -> Opportunity -> Lightning Record Pages -> `Opportunity_Record_Page_MI` -> **Activation**.
2. Select **Org Default** -> Assign as Org Default -> Desktop and Phone.
3. Save.
4. Repeat for `Account_Record_Page_MI` on Account.

> **Note:** If you want a phased rollout (some users see MI, some don't), assign by App / Record Type / Profile instead of Org Default. Coordinate with Sales Ops.

## Smoke verification (post-deploy)

Total time: ~30 minutes.

### Smoke 1 — Send a HubSpot-shaped POST

Use the curl from [HubSpot wiring Step 4](#step-4--send-a-test-event-hubspot-side) above. Confirm `200` response with `processed: 1`.

### Smoke 2 — Touch record exists, identity-resolved

```apex
Engagement_Touch__c t = [
    SELECT Id, External_Id__c, Email__c, Resolution_Status__c,
           Contact__c, Lead__c, Account__c, Touch_Topic__c
    FROM Engagement_Touch__c
    WHERE External_Id__c = 'hs-smoke-001'
    LIMIT 1
];
System.debug(t);
```

Expected: `Resolution_Status__c = 'Resolved'`; one of `Contact__c` or `Lead__c` populated; `Account__c` populated; `Touch_Topic__c` populated (because `PRICING` mapped to a real `Touch_Topic__c.External_Code__c`).

### Smoke 3 — Signal produced

```apex
List<Opportunity_Engagement_Signal__c> sigs = [
    SELECT Id, Opportunity__c, Match_Path__c, Confidence__c, Routing_Rule__c
    FROM Opportunity_Engagement_Signal__c
    WHERE Engagement_Touch__r.External_Id__c = 'hs-smoke-001'
];
System.debug('Produced ' + sigs.size() + ' signal(s)');
for (Opportunity_Engagement_Signal__c s : sigs) {
    System.debug(s);
}
```

Expected: at least one signal (if there's an open Opp on the Account with a matching topic). Zero if there's no open Opp — that's fine, the routing rules require an Opp.

### Smoke 4 — LWC panel renders

Open an Opportunity record page in Lightning. Confirm:

- The `engagementPanel` LWC is visible on the right rail.
- It shows "Deal Team" + "Not on Deal Team" sections (Opp scope).
- Sorted by `lastTouchAt DESC`.
- `+ Add` button appears on "Not on Deal Team" rows.

### Smoke 5 — Add to deal team flow

1. On the Opportunity page, click `+ Add` on a "Not on Deal Team" row.
2. The `addToDealTeamModal` opens with a role picker.
3. Select a role (e.g. `Influencer`) and click Add.
4. Modal closes; the panel re-renders; the contact now appears under "Deal Team" with the `on team` indicator.

Verify in SOQL:

```apex
List<OpportunityContactRole> ocr = [
    SELECT Id, OpportunityId, ContactId, Role
    FROM OpportunityContactRole
    WHERE OpportunityId = '<smoke opp id>'
    ORDER BY CreatedDate DESC
];
System.debug(ocr);
```

### Smoke 6 — Account scope

Open the Account record page for the smoke account. Confirm `engagementPanel` renders in Account scope — a single flat list, no Deal Team grouping.

### Smoke 7 — Erasure cascade (dry run)

> **Note:** This is destructive. Run only against a smoke Contact, **never** a production Contact.

```apex
Contact c = [SELECT Id FROM Contact WHERE Email = 'mi-smoke-erasure@example.com' LIMIT 1];
Integer beforeTouches = [SELECT COUNT() FROM Engagement_Touch__c WHERE Contact__c = :c.Id];
Integer beforeSignals = [SELECT COUNT() FROM Opportunity_Engagement_Signal__c WHERE Engagement_Touch__r.Contact__c = :c.Id];
System.debug('Before: ' + beforeTouches + ' touches, ' + beforeSignals + ' signals');

delete c;

Integer afterTouches = [SELECT COUNT() FROM Engagement_Touch__c];
Integer afterSignals = [SELECT COUNT() FROM Opportunity_Engagement_Signal__c WHERE Engagement_Touch__r.Contact__c = :c.Id ALL ROWS];
System.debug('After: zero is expected -> ' + afterTouches + ' touches, ' + afterSignals + ' signals');
```

Expected: zero residual rows for that Contact's children. Recycle bin emptied.

### Smoke 8 — Cleanup smoke data

```apex
delete [SELECT Id FROM Engagement_Touch__c WHERE External_Id__c LIKE 'hs-smoke-%'];
```

## Sign-off

Sign-off captured in the release ticket:

- [ ] **Release engineer** — deploy succeeded, smoke green
- [ ] **HubSpot Ops** — outbound workflow firing, response codes clean
- [ ] **Marketing Ops** — topic taxonomy aligned, routing rules sensible
- [ ] **Sales Ops** — LWC panel visible, sales users assigned permset
- [ ] **David Wood (TA)** — architecture conformance, three-layer pattern intact

## Rollback procedure

### Tier 1 — Pause inbound REST (no deploy, < 1 min)

**Symptom:** Bad data flooding in; need to stop ingestion.

Remove the stop-gap `Engagement_Attribution_Admin` permset from the HubSpot integration user:

```bash
sfdx force:data:soql:query -u prod -q "SELECT Id FROM PermissionSetAssignment WHERE Assignee.Username = 'mi-integration@<orgname>.com' AND PermissionSet.Name = 'Engagement_Attribution_Admin'"
# Then delete the returned Id:
sfdx force:data:record:delete -u prod -s PermissionSetAssignment -i <id>
```

Effect: subsequent HubSpot POSTs receive `401 Unauthorized`. HubSpot Ops will see the failure in their workflow logs.

### Tier 2 — Pause routing (no deploy, < 1 min)

**Symptom:** Touches ingest fine but routing is wrong.

Set every `Touch_Routing_Rule__mdt.Active__c = false`:

1. Setup -> Custom Metadata Types -> Touch Routing Rule -> Manage Records.
2. For each row, edit -> uncheck `Active__c` -> Save.

Or use the `TriggerHandler` bypass on `EngagementTouchTriggerHandler` (lighter touch — touches still ingest, no new signals produced).

### Tier 3 — Hide LWC panel (no deploy, < 5 min)

**Symptom:** UI-side issue; need to remove the panel from sales view while keeping the backend running.

1. Setup -> Object Manager -> Opportunity -> Lightning Record Pages -> `Opportunity_Record_Page_MI` -> **Edit**.
2. Remove the `engagementPanel` component from the right rail.
3. Save & activate.
4. Repeat for `Account_Record_Page_MI`.

Backend continues to process. UI is gone.

### Tier 4 — Hard rollback (deploy required, ~45 min)

**Symptom:** Critical bug; need to remove the feature entirely.

```bash
cd /Users/david/Work/Zelis
git checkout tags/mi-prod-PREVIOUS  # or the last clean tag

# Build destructive change set (engagement section)
# Order matters: scheduler -> batches -> triggers -> LWC -> Apex classes -> CMDT -> custom objects
cat > /tmp/destructiveChanges.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>EngagementTouchTrigger</members>
        <name>ApexTrigger</name>
    </types>
    <types>
        <members>EngagementController</members>
        <members>EngagementAdminController</members>
        <members>EngagementInboundRest</members>
        <members>EngagementServiceImpl</members>
        <members>EngagementSignalRouter</members>
        <members>IdentityResolutionService</members>
        <members>EngagementErasureService</members>
        <members>EngagementTouchTriggerHandler</members>
        <members>ContactEngagementErasureHandler</members>
        <members>LeadEngagementErasureHandler</members>
        <members>LeadEngagementReparentHandler</members>
        <members>EngagementSignalDecayBatch</members>
        <members>EngagementTouchArchivalBatch</members>
        <members>EngagementMaintenanceScheduler</members>
        <name>ApexClass</name>
    </types>
    <types>
        <members>engagementPanel</members>
        <members>engagementDetailModal</members>
        <members>addToDealTeamModal</members>
        <members>alreadyAddedModal</members>
        <members>engagementAdminApp</members>
        <name>LightningComponentBundle</name>
    </types>
    <types>
        <members>Engagement_Touch__c</members>
        <members>Opportunity_Engagement_Signal__c</members>
        <members>Engagement_Dismissal__c</members>
        <members>Touch_Topic__c</members>
        <name>CustomObject</name>
    </types>
    <version>62.0</version>
</Package>
EOF

# Abort the scheduled job first
# (anonymous Apex)
# System.abortJob([SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Engagement Maintenance%' LIMIT 1].Id);

sfdx force:mdapi:deploy -d /tmp -u prod -w 90
```

> **Note:** Destructive deploys preserve data only if the custom objects' rows are first exported. For a true rollback with data preserved, export `Engagement_Touch__c`, `Opportunity_Engagement_Signal__c`, and `Engagement_Dismissal__c` rows via Data Loader before destruction.

## TODO items

- TODO: Confirm production Salesforce org alias (currently assumed `prod`).
- TODO: Confirm the HubSpot side credential storage mechanism in production. Runbook assumes session-token-in-workflow. If HubSpot Ops uses HubSpot's native SFDC integration instead, the auth path differs.
- TODO: Confirm the org's production Salesforce URL pattern (`<orgname>.my.salesforce.com` vs. `<orgname>.lightning.force.com`). REST endpoint format unchanged either way.
- TODO: Confirm whether the production Integration User is reused across other Marlowe-doc'd integrations (CSI-7162 also has an Integration User — verify with Sage).
- TODO: Confirm the production Touch Topic taxonomy is loaded (10-30 rows is typical). If not, ship a one-time Data Loader CSV.

## References

- [MI Confluence tech doc](../confluence/mi-technical.md)
- [MI user story](../jira/mi-user-story.md)
- [Architecture overview](../../.claude/worktrees/feature-engagement-attribution/docs/architecture/overview.md)
- [Demo flow + admin guide](../../.claude/worktrees/feature-engagement-attribution/docs/users/DEMO.md)
- [BRD (Word)](../../.claude/worktrees/feature-engagement-attribution/docs/architecture/BRD-Engagement-Attribution.docx)
- [Operations — apex invocation runbook](../../.claude/worktrees/feature-engagement-attribution/docs/operations/apex-invocation-runbook.md)
- [Admin app wiring](../../.claude/worktrees/feature-engagement-attribution/docs/operations/admin-app-wiring.md)
- [ADR-0001 — three-layer pattern](../../.claude/worktrees/feature-engagement-attribution/docs/architecture/decisions/0001-three-layer-selector-service-controller.md)
- [Apex conventions](../../best-practices/apex.md)
- [LWC conventions](../../best-practices/lwc.md)
