# Apex Invocation Runbook

How to manually invoke each major Apex entry point — for triage, demo prep, ad-hoc support, or recovering from a partial failure. All commands target a scratch org (default alias `engagementDev` in this worktree).

Deploy / scratch-org-lifecycle / packaging are owned by Dash; see his runbooks at [operations/deploy-runbook.md](deploy-runbook.md), [operations/scratch-org-lifecycle.md](scratch-org-lifecycle.md), [operations/packaging.md](packaging.md) (when they land).

## Prerequisites

- Salesforce CLI `sf` v2.x.
- A working scratch org. Spin one up via [users/DEMO.md §1–4](../users/DEMO.md). Default alias: `engagementDev`.
- The [`Engagement_Attribution_User`](../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml) permission set assigned to your running user.

In every command below, substitute `engagementDev` with your scratch-org alias if different.

## Seed the demo data

The single command that lights up the entire 4-beat demo. Idempotent — re-run safely:

```bash
sf apex run --file scripts/apex/seed-engagement-data.apex --target-org engagementDev
```

The runner is a one-liner that calls `EngagementSeedScript.run()`. Full inventory of what it loads (3 Accounts, 7 Contacts, 21 touches, etc.) is in [users/DEMO.md §5 — Seed the demo data](../users/DEMO.md#5--seed-the-demo-data-30-sec).

Verify the seed populated:

```bash
sf data query --query "SELECT COUNT() FROM Engagement_Touch__c" --target-org engagementDev
```

Expected: 21 (or higher if you've manually inserted touches since).

## Manually invoke the REST endpoint

Skip the HTTP / curl ceremony and exercise [`EngagementInboundRest.ingest`](../development/classes/EngagementInboundRest.md) directly via anonymous Apex. Useful for triage when HubSpot is unavailable or you want to test a specific payload shape.

Save as `scripts/apex/post-sample-touch.apex`:

```apex
RestRequest req = new RestRequest();
req.requestURI = '/services/apexrest/engagement/touches/';
req.httpMethod = 'POST';
req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
  'events' => new List<Object>{
    new Map<String, Object>{
      'external_id' => 'LOCAL-' + Crypto.getRandomInteger(),
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

Run:

```bash
sf apex run --file scripts/apex/post-sample-touch.apex --target-org engagementDev
```

Expected debug output:

```
Result: {
  "received" : 1,
  "resolved" : 1,
  "ambiguous" : 0,
  "noMatch" : 0,
  "errored" : 0,
  "errors" : [ ]
}
```

If `noMatch=1`, the seed Topic with `External_Code__c = 'TOPIC_NETWORK_MGMT'` likely isn't present — re-run the seed script first. See [users/DEMO.md §Phase 2 — HubSpot ingestion](../users/DEMO.md#phase-2--hubspot-ingestion) for the full live-curl flow with bearer auth.

## Manually call `EngagementSignalRouter`

Normally fired by [`EngagementTouchTrigger`](../../force-app/main/default/triggers/EngagementTouchTrigger.trigger) on resolved-touch insert/update. Invoke directly for re-routing or routing-rule validation. Idempotent — existing signals are skipped.

Anonymous Apex:

```apex
// Route every resolved touch on a specific Account (e.g. United Healthcare)
Set<Id> touchIds = new Map<Id, Engagement_Touch__c>([
  SELECT Id
  FROM Engagement_Touch__c
  WHERE Account__r.Name = 'United Healthcare'
    AND Resolution_Status__c = 'Resolved'
]).keySet();

EngagementSignalRouter.routeTouches(touchIds);

System.debug('Routed ' + touchIds.size() + ' touch(es).');
```

Or for a single touch (the most-common triage path):

```apex
Id touchId = '<paste-touch-id>';
EngagementSignalRouter.routeTouches(new Set<Id>{ touchId });
```

Verify signals were produced:

```bash
sf data query \
  --query "SELECT Engagement_Touch__c, Opportunity__r.Name, Match_Path__c, Confidence__c FROM Opportunity_Engagement_Signal__c WHERE Engagement_Touch__c = '<touch-id>'" \
  --target-org engagementDev
```

Full Phase-3 routing demo flow with seeded data: [users/DEMO.md §Verifying routing in the demo](../users/DEMO.md#verifying-routing-in-the-demo). Per-class reference: [`EngagementSignalRouter`](../development/classes/EngagementSignalRouter.md).

## Manually call `EngagementErasureService`

For a CCPA / HIPAA "delete my data" request that needs to retain the Contact record (audit shell) but wipe the engagement footprint. The same service is called automatically by [`ContactEngagementErasureHandler`](../../force-app/main/default/classes/engagement/ContactEngagementErasureHandler.cls) on Contact delete, and [`LeadEngagementErasureHandler`](../../force-app/main/default/classes/engagement/LeadEngagementErasureHandler.cls) on Lead delete.

Hard-delete (irreversible — emptied from Recycle Bin). Per privacy counsel sign-off; do not soften.

```apex
// Erase engagement footprint for a Contact (Contact record itself remains)
Set<Id> subjects = new Set<Id>{ '<contact-id-here>' };
EngagementErasureService.ErasureSummary summary = EngagementErasureService.eraseForContacts(subjects);

for (String msg : summary.messages) {
  System.debug(msg);
}
```

Lead variant:

```apex
Set<Id> subjects = new Set<Id>{ '<lead-id-here>' };
EngagementErasureService.ErasureSummary summary = EngagementErasureService.eraseForLeads(subjects);

for (String msg : summary.messages) {
  System.debug(msg);
}
```

Expected debug output (one line per cascade):

```
Subject erasure cascade — 1 subject(s) of type Contact: deleted 3 touch(es), 2 signal(s), 1 dismissal(s).
```

The same line is appended to `Logger.info` for the compliance audit trail. Copy it to the privacy ticket. Full compliance workflow: [users/DEMO.md §Sample compliance workflow](../users/DEMO.md#sample-compliance-workflow).

## Schedule `EngagementMaintenanceScheduler`

The weekly maintenance job that fires [`EngagementSignalDecayBatch`](../../force-app/main/default/classes/engagement/EngagementSignalDecayBatch.cls) and [`EngagementTouchArchivalBatch`](../../force-app/main/default/classes/engagement/EngagementTouchArchivalBatch.cls). Schedule via `System.schedule`:

```apex
System.schedule(
  'Engagement Weekly Maintenance',
  '0 0 2 ? * MON',
  new EngagementMaintenanceScheduler()
);
```

Recommended cron: Mondays at 02:00 server time. Save the snippet to `scripts/apex/schedule-maintenance.apex` and run:

```bash
sf apex run --file scripts/apex/schedule-maintenance.apex --target-org engagementDev
```

Verify in Setup → **Scheduled Jobs**, or query:

```bash
sf data query \
  --query "SELECT CronJobDetail.Name, NextFireTime, State FROM CronTrigger WHERE CronJobDetail.Name = 'Engagement Weekly Maintenance'" \
  --target-org engagementDev
```

To run the batches one-off without scheduling:

```apex
Id decayJobId = Database.executeBatch(new EngagementSignalDecayBatch(), 200);
Id archiveJobId = Database.executeBatch(new EngagementTouchArchivalBatch(), 200);
System.debug('Decay job: ' + decayJobId);
System.debug('Archive job: ' + archiveJobId);
```

Track:

```bash
sf data query \
  --query "SELECT Id, Status, JobItemsProcessed, NumberOfErrors FROM AsyncApexJob WHERE Id IN ('<decayJobId>','<archiveJobId>')" \
  --target-org engagementDev
```

Tunables (`Active_Window_Days__c`, `Signal_Decay_Days__c`, `Confidence_Threshold__c`) live on the `Engagement_Settings__c` Hierarchy Custom Setting Org Default — see [users/DEMO.md §Tune the windows](../users/DEMO.md#tune-the-windows).

## Inspect Logger output

Every Service / Controller / Router writes to the standard project [`Logger`](../../force-app/main/default/classes/logging/Logger.cls). Two ways to inspect:

### Debug logs (immediate)

```bash
# Enable a debug log for your running user
sf apex tail log --target-org engagementDev --color
```

In another shell, fire the Apex you want to trace. The tail prints `Logger.info` / `Logger.warn` / `Logger.error` lines as they arrive.

### Stored log records (post-hoc)

The project Logger persists to a `Log__c` or equivalent custom object (depending on the [`Log_Setting__mdt`](../../force-app/main/default/objects/Log_Setting__mdt/) record). Query recent entries:

```bash
sf data query \
  --query "SELECT CreatedDate, Class_Name__c, Method_Name__c, Severity__c, Message__c FROM Log__c WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC LIMIT 50" \
  --target-org engagementDev
```

Adjust the field/object names if the org has been re-skinned. The [`LogCleanupScheduler`](../../force-app/main/default/classes/logging/LogCleanUp/LogCleanupScheduler.cls) keeps the log table from accumulating — confirm it's scheduled in Setup → **Scheduled Jobs**.

## Service-layer test invocations

For controller-bypass triage — invoking [`EngagementServiceImpl`](../development/classes/EngagementServiceImpl.md) directly:

```apex
// Mimic an LWC call to getForOpportunity
Id oppId = [SELECT Id FROM Opportunity WHERE Name = 'Network Pricing Implementation' LIMIT 1].Id;
IEngagementService svc = new EngagementServiceImpl();
List<EngagementDTO> dtos = svc.getForOpportunity(oppId);
System.debug('DTO count: ' + dtos.size());
for (EngagementDTO d : dtos) {
  System.debug(d.name + ' (' + d.title + ') onOcr=' + d.onOcr + ' touchCount=' + d.touchCount);
}
```

The exact same output shape is reproduced in the smoke-deploy verification log in [users/DEMO.md §Smoke-deploy verification](../users/DEMO.md#smoke-deploy-verification-already-done) — use it as the expected-output reference.

---

**Summary:** every major Apex entry point — REST ingest, signal router, erasure cascade, maintenance batches, Service layer — has a documented anonymous-Apex invocation snippet here. Save the snippets to `scripts/apex/` if you find yourself running them repeatedly. Logger output lives in the org's `Log__c` table; `sf apex tail log` is the fastest live-trace path.
