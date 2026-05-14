---
title: CSI-7162 — Production Go-Live Runbook
author: David Wood
audience: Release engineers, Salesforce admins, Jira admins
target-environment: Production
last-updated: 2026-05-14
estimated-duration: 90 minutes (deploy 30 min · config 30 min · smoke 30 min)
maintenance-window: Off-hours preferred; production-safe (no transaction-blocking impact)
---

# CSI-7162 — Production Go-Live Runbook

> **Note:** Run this end-to-end the first time CSI-7162 is deployed to a target org. For subsequent updates, only the **Deploy** section is required. For day-2 operations, see [docs/operations/csi7162-jira-push-runbook.md](../operations/csi7162-jira-push-runbook.md).

## Pre-flight checklist

Confirm **before** the maintenance window starts. Each line item must be green.

- [ ] **Source branch tagged.** Production cut from `main` at tag `csi-7162-prod-YYYYMMDD`. Confirm: `git log --oneline tags/csi-7162-prod-YYYYMMDD -1`.
- [ ] **All Apex tests pass in source.** `sfdx force:apex:test:run -c -r human -w 30` against the staging org. Target: 100% coverage on CSI-7162 classes, org-wide >= 75%.
- [ ] **Atlas code review approved.** See [docs/reviews/atlas-csi7162-code-review-2026-05-12.md](../reviews/atlas-csi7162-code-review-2026-05-12.md).
- [ ] **Pippa test review approved.** See [docs/reviews/pippa-csi7162-test-review-2026-05-12.md](../reviews/pippa-csi7162-test-review-2026-05-12.md).
- [ ] **Sage security pass-through approved.** See [docs/reviews/sage-csi7162-security-passthrough-2026-05-12.md](../reviews/sage-csi7162-security-passthrough-2026-05-12.md).
- [ ] **Appfire JCFS installed in production.** Confirm at Setup -> Installed Packages. Version recorded: `____________`.
- [ ] **JCFS auth healthy.** Jira admin confirms the JCFS package can authenticate to the production Jira project (`CSI`).
- [ ] **Jira project `CSI` exists, issue type `Story` exists.** Jira admin confirms via the Jira project settings.
- [ ] **Production deploy user has permission to deploy Apex + custom metadata.** Typically `System Administrator` or a release-engineer profile with `Modify Metadata` and `Author Apex`.
- [ ] **Backup window confirmed.** Production data export taken within 24 hours.
- [ ] **Stakeholders notified.** Release email to: Sales Ops, Integration Admins, Jira Admins, and on-call.
- [ ] **Rollback path validated** in staging. Re-running the [Rollback procedure](#rollback-procedure) against staging produces a green org.

## Components shipping

| Type | Component |
| --- | --- |
| Apex class | `OpportunityService` |
| Apex class | `OpportunityServiceTest` |
| Apex class | `OpportunityTriggerHandler` |
| Apex class | `OpportunityTriggerHandlerTest` |
| Apex class | `JiraPushService` |
| Apex class | `JiraPushServiceTest` |
| Apex class | `JiraPushRequestHandler` |
| Apex class | `JiraPushRequestHandlerTest` |
| Apex class | `JiraPushDispatcher` |
| Apex class | `JiraPushDispatcherTest` |
| Apex class | `JcfsApiAdapter` |
| Apex class | `JcfsApiAdapterTest` |
| Apex class | `JiraPushTestFixtures` |
| Apex trigger | `OpportunityTrigger` |
| Apex trigger | `JiraPushRequestTrigger` |
| Platform event | `Jira_Push_Request__e` |
| Custom object | `API_Exception_Log__c` (skip if already deployed by another integration) |
| Custom metadata type | `Jira_Push_Object__mdt` |
| Custom metadata record | `Jira_Push_Object.Opportunity` (`Active__c = true`) |
| Custom metadata record | `Jira_Push_Object.Case` (`Active__c = false`) |
| Permset | `CSI_7162_Integration_Admin` |

Manifest of record: [manifest/package-csi-7162.xml](../../manifest/package-csi-7162.xml).

## Deploy steps

### Step 1 — Open release shell

```bash
cd /Users/david/Work/Zelis
git fetch --all --tags
git checkout tags/csi-7162-prod-YYYYMMDD
sfdx force:org:list  # confirm prod alias
```

Confirm the target org alias for production (typically `prod`). If not authed:

```bash
sfdx force:auth:web:login -a prod -r https://login.salesforce.com
```

### Step 2 — Pre-deploy validation (no commit)

```bash
sfdx force:source:deploy \
  -x manifest/package-csi-7162.xml \
  -u prod \
  -l RunSpecifiedTests \
  -r OpportunityServiceTest,OpportunityTriggerHandlerTest,JiraPushServiceTest,JiraPushRequestHandlerTest,JiraPushDispatcherTest,JcfsApiAdapterTest \
  -c \
  -w 60
```

`-c` = check-only. Expected outcome: 100% pass on the named tests. Any failure aborts go-live; investigate before proceeding.

### Step 3 — Deploy

```bash
sfdx force:source:deploy \
  -x manifest/package-csi-7162.xml \
  -u prod \
  -l RunSpecifiedTests \
  -r OpportunityServiceTest,OpportunityTriggerHandlerTest,JiraPushServiceTest,JiraPushRequestHandlerTest,JiraPushDispatcherTest,JcfsApiAdapterTest \
  -w 60
```

Capture the deploy Id (`0Af...`) and result URL. Paste into the release ticket.

### Step 4 — Confirm CMDT records deployed

In production, open Setup -> Custom Metadata Types -> Jira Push Object -> Manage Records. Expect two rows:

| MasterLabel | Active | Jira Project | Jira Issue Type |
| --- | :---: | --- | --- |
| Opportunity | Checked | CSI | Story |
| Case | Unchecked | CSI | Story |

If `Opportunity` row is missing or `Active__c = false`, manually create / edit per the values above before continuing.

## Named credential setup

**CSI-7162 does not require a Named Credential on the Salesforce side.** The Appfire JCFS managed package owns Jira authentication. Verify the JCFS-side auth is healthy:

1. In Salesforce: Setup -> Installed Packages -> Appfire Jira Connector for Salesforce -> **Configure**.
2. Confirm the connected Jira instance shows status `Connected`.
3. If `Not Connected`, the Jira admin re-authenticates per Appfire's [JCFS documentation](https://www.appfire.com/products/connector-for-salesforce-jira/).

> **Note:** If JCFS is not installed in production, deploy proceeds — but every push will land in `API_Exception_Log__c` with `Message__c = 'JCFS rejected record: JCFS managed package not installed'`. Detection signal: one `Logger.error('JCFS managed package is not installed...')` per transaction.

## Jira credentials wiring

All Jira-side credentials live in the Appfire JCFS configuration in Jira:

1. Jira admin opens **Jira -> Apps -> Connector for Salesforce -> Configuration**.
2. Confirm the Salesforce instance URL matches production: `https://<orgname>.my.salesforce.com`.
3. Confirm the OAuth connection status is `Active`.
4. Confirm field mapping for the `CSI` project includes the fields that should be pulled from Salesforce (typically: Account.Name, Opportunity.Name, StageName, Amount, CloseDate).

If field mapping needs to change, the Jira admin owns that — it's not a Salesforce-side change.

## CMDT row population

The deploy ships both rows. If a row needs hand-edit (e.g. to point at a different Jira project for a tenant variant):

1. Setup -> Custom Metadata Types -> Jira Push Object -> Manage Records.
2. Click the row's MasterLabel.
3. Edit `Active__c`, `Jira_Project_Id__c`, or `Jira_Issue_Type__c`.
4. Save.

> **Note:** CMDT cache is per-transaction. New transactions pick up the change immediately; in-flight transactions don't.

## Permset assignment

### Assign `CSI_7162_Integration_Admin` to integration admins

Via UI:

1. Setup -> Permission Sets -> CSI 7162 Integration Admin -> Manage Assignments -> Add Assignments.
2. Select the users (Integration Admins, Tier-2 support, Jira admins).
3. Assign.

Via CLI (recommended for repeatability):

```bash
sfdx force:data:soql:query -u prod -q "SELECT Id, Username FROM User WHERE IsActive = true AND ProfileId IN (SELECT Id FROM Profile WHERE Name IN ('System Administrator', 'Integration Admin'))"
```

Then for each Id:

```bash
sfdx force:user:permset:assign -u prod -n CSI_7162_Integration_Admin -o <UserId>
```

### Verify Automated Process User has JCFS access

The PE trigger runs as the Automated Process User. If JCFS ships a permset (typical), it must be assigned to that user:

1. Setup -> Users -> select **Automated Process** user.
2. Permission Set Assignments -> Add.
3. Assign the JCFS namespace permset (name varies by version; check the Appfire JCFS install guide).

> **Note:** If this is skipped and JCFS requires a permset, you'll see `MISSING_OR_INSUFFICIENT_PERMISSIONS` errors in `API_Exception_Log__c` under `Operation__c = 'JCFS.API.pushUpdatesToJira'`.

## Smoke verification (post-deploy)

Run these in production immediately after deploy. Total time: ~10 minutes.

### Smoke 1 — Active CMDT

```apex
List<Jira_Push_Object__mdt> rows = [
    SELECT MasterLabel, DeveloperName, SObject_API_Name__c,
           Active__c, Jira_Project_Id__c, Jira_Issue_Type__c
    FROM Jira_Push_Object__mdt
    ORDER BY DeveloperName
];
for (Jira_Push_Object__mdt r : rows) {
    System.debug(r.DeveloperName + ' active=' + r.Active__c +
                 ' project=' + r.Jira_Project_Id__c +
                 ' issueType=' + r.Jira_Issue_Type__c);
}
```

Expected: `Opportunity active=true project=CSI issueType=Story` + `Case active=false project=CSI issueType=Story`.

### Smoke 2 — Trigger an insert push

Pick a test Account in production (use one your team owns; **do not** use a customer Account for smoke):

```apex
// Snapshot the error log row count before.
Integer before = [SELECT COUNT() FROM API_Exception_Log__c WHERE API_Name__c = 'JCFS'];

Account a = [SELECT Id FROM Account WHERE Name LIKE 'CSI-7162 Smoke%' LIMIT 1];
Opportunity o = new Opportunity(
    AccountId = a.Id,
    Name = 'CSI-7162 Smoke ' + System.now().getTime(),
    StageName = 'Prospecting',
    CloseDate = Date.today().addDays(30)
);
insert o;

System.debug('Inserted: ' + o.Id);
System.debug('TxnId: ' + System.Request.getCurrent().getRequestId());

Integer after = [SELECT COUNT() FROM API_Exception_Log__c WHERE API_Name__c = 'JCFS'];
System.assertEquals(before, after, 'No new error rows expected');
```

Expected:
- Insert succeeds.
- Debug log shows: `INFO|JiraPushService|publish|Publishing 1 Jira push event(s) for Opportunity (txn xxx)`.
- Debug log shows: `INFO|JiraPushDispatcher|pushOne|JCFS push success for Opportunity 006xxx -> CSI-xxxx` (within a few seconds — PE delivery is async).
- `API_Exception_Log__c` row count unchanged.

### Smoke 3 — Trigger an update push

```apex
Opportunity o = [SELECT Id, StageName FROM Opportunity WHERE Name LIKE 'CSI-7162 Smoke%' ORDER BY CreatedDate DESC LIMIT 1];
update new Opportunity(Id = o.Id, StageName = (o.StageName == 'Prospecting' ? 'Qualification' : 'Prospecting'));
```

Expected: a second PE publish and JCFS success log within seconds.

### Smoke 4 — Non-qualifying field is filtered

```apex
Opportunity o = [SELECT Id, Description FROM Opportunity WHERE Name LIKE 'CSI-7162 Smoke%' ORDER BY CreatedDate DESC LIMIT 1];
update new Opportunity(Id = o.Id, Description = 'unrelated edit ' + DateTime.now());
```

Expected: **no** `Publishing ... Jira push event(s)` debug log line. Description is not in the qualifying-field set.

### Smoke 5 — Inspect Jira

Open Jira -> CSI project. Look for the new issue corresponding to the smoke Opportunity (or the updated stage on the existing issue). Expected within 1-2 minutes (Appfire JCFS sync cadence depends on JCFS configuration).

If the Salesforce-side smoke is clean (logs all green, no `API_Exception_Log__c` rows) but the Jira issue doesn't update, the problem is in the JCFS mapping — coordinate with the Jira admin.

### Smoke 6 — Cleanup

```apex
delete [SELECT Id FROM Opportunity WHERE Name LIKE 'CSI-7162 Smoke%'];
```

## Sign-off

Sign-off captured in the release ticket. Required approvers:

- [ ] **Release engineer** — deploy succeeded, smoke green
- [ ] **Integration admin** — `API_Exception_Log__c` baseline clean
- [ ] **Jira admin** — Jira CSI project receiving updates
- [ ] **David Wood (TA)** — architecture conformance

## Rollback procedure

> **Note:** Most rollback paths are config-only and do not require a deploy. Use the lightest tool that fixes the problem.

### Tier 1 — Pause publish (no deploy, < 1 min)

**Symptom:** Every push failing; need to stop the bleeding.

1. Setup -> Custom Metadata Types -> Jira Push Object -> Manage Records.
2. Edit `Opportunity`.
3. Uncheck `Active__c`.
4. Save.

Effect on next transaction: `JiraPushService.publish` short-circuits with `'Jira push inactive for Opportunity; skipping publish'`. No PEs published, no failure rows.

### Tier 2 — Bypass the trigger (no deploy, < 1 min)

**Symptom:** Need to stop **all** Opportunity-trigger activity for a window (e.g. bulk data load).

Use the `TriggerHandler` framework bypass mechanism:

```apex
TriggerHandler.bypass('OpportunityTriggerHandler');
// ... your DML ...
TriggerHandler.clearBypass('OpportunityTriggerHandler');
```

Or set a per-org bypass flag — see [best-practices/architecture.md](../../best-practices/architecture.md) for the canonical bypass pattern.

### Tier 3 — Hard rollback (deploy required, ~15 min)

**Symptom:** Critical bug discovered post-deploy; need to remove the feature entirely.

```bash
cd /Users/david/Work/Zelis
# Identify the previous tag
git tag --sort=-creatordate | grep csi-7162-prod | head -3

# Check out the previous deploy's tag
git checkout tags/csi-7162-prod-PREVIOUS

# Build destructive change set
cat > /tmp/destructiveChanges.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>OpportunityTrigger</members>
        <members>JiraPushRequestTrigger</members>
        <name>ApexTrigger</name>
    </types>
    <types>
        <members>OpportunityService</members>
        <members>OpportunityTriggerHandler</members>
        <members>JiraPushService</members>
        <members>JiraPushRequestHandler</members>
        <members>JiraPushDispatcher</members>
        <members>JcfsApiAdapter</members>
        <name>ApexClass</name>
    </types>
    <types>
        <members>Jira_Push_Request__e</members>
        <name>CustomObject</name>
    </types>
    <version>62.0</version>
</Package>
EOF

cat > /tmp/package.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <version>62.0</version>
</Package>
EOF

# Deploy destructive change
sfdx force:mdapi:deploy -d /tmp -u prod -w 60
```

> **Note:** Order matters. Triggers must be removed before classes (Salesforce dependency check). Platform event is removed last.

### Replay a dropped push

If pushes failed during a window (e.g. Jira was down):

```apex
Set<Id> oppIds = new Set<Id>();
for (API_Exception_Log__c row : [
    SELECT Source_Record_Id__c
    FROM API_Exception_Log__c
    WHERE API_Name__c = 'JCFS'
    AND Source_Object__c = 'Opportunity'
    AND CreatedDate = LAST_N_HOURS:6
]) {
    oppIds.add((Id) row.Source_Record_Id__c);
}
List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE Id IN :oppIds];
JiraPushService.publishUpdates(opps);
System.debug('Replayed ' + opps.size() + ' Opportunities');
```

For replays > 1k records, split into multiple anonymous Apex runs or wrap in a one-off `Queueable`. The 150,000/hour PE publish limit is org-level and well above realistic replay needs.

## TODO items

- TODO: Confirm specific production org alias name with David Wood. Currently assumed `prod`.
- TODO: Confirm the Jira instance URL for production. The runbook assumes the JCFS package is already pointing at the right one.
- TODO: Confirm whether JCFS ships its own permset in the version installed. If not, this step is a no-op.

## References

- [CSI-7162 Confluence tech doc](../confluence/csi-7162-technical.md)
- [CSI-7162 operations runbook](../operations/csi7162-jira-push-runbook.md)
- [CSI-7162 admin guide](../users/csi7162-jira-push-admin-guide.md)
- [Manifest of record](../../manifest/package-csi-7162.xml)
- [Apex conventions](../../best-practices/apex.md)
- [Architecture conventions](../../best-practices/architecture.md)
