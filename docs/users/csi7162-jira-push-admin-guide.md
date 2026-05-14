# Jira Push Notifications — Admin Guide

## What this integration does

Whenever an Opportunity is created or meaningfully updated in Salesforce, the matching issue in Jira is refreshed. "Meaningfully updated" means one of these six fields changed:

- **Stage**
- **Amount**
- **Close Date**
- **Account**
- **Owner**
- **Probability**

Edits to other fields (Description, Next Step, custom fields, etc.) do **not** trigger a push. This is deliberate — Jira only mirrors the fields above today, so quiet edits would just be noise.

The Salesforce side pushes only the Opportunity's record Id; Jira pulls back the field values it cares about over its own connector. You should expect the Jira issue to reflect the change within roughly a minute or two of saving the Opportunity (depends on Jira-side sync cadence).

## How to validate the integration is alive

Two-minute smoke test:

1. Open any Opportunity that has a linked Jira issue (your team's Jira admin can tell you which ones).
2. Note the current **Stage**.
3. Edit the **Stage**, save, then immediately set it back to the original value (so you don't disrupt real pipeline data).
4. Wait ~2 minutes, open the linked Jira issue, and look at the activity log. You should see two sync events corresponding to your two changes.

If you don't: open the operations runbook below, or raise it with the on-call Apex dev.

## Where to find logs

Sales asks _"did this Opp sync to Jira?"_:

1. **Setup → Custom Objects → API Exception Log** (object label) or **the App Launcher → API Exception Logs**.
2. Filter for the last 24 hours, `API Name = JCFS`.
3. If you see a row whose **Source Record Id** matches the Opportunity Id in question, that push failed — escalate with the row's **Name** (e.g. `AEL-00042`).
4. If no row, the Salesforce side succeeded. The next step is the Jira side — talk to your Jira admin and ask them to check JCFS sync history for that record Id.

## How to pause the integration

If something downstream is broken and you need to stop sending pushes to Jira:

1. **Setup → Custom Metadata Types → Jira Push Object → Manage records.**
2. Edit **Opportunity** (or whichever SObject you need to pause).
3. Uncheck **Active**, save.

Effect: new Opportunity edits no longer fire pushes to Jira at all — the kill switch is now checked both **before** a platform event is published and **again** before the JCFS callout, so flipping it cleanly stops the pipeline in both directions. (Previously the publish side ran regardless and only the JCFS callout was suppressed.) To re-enable: re-check **Active**, save.

This is the supported pause mechanism. **Do not disable the Opportunity trigger** — that suspends a lot more than just the Jira push.

> **Latency note.** The CMDT cache is per-transaction. Any save that started before you flipped the switch will still complete on the old setting; new saves pick up the change immediately. In practice this is sub-second.

## How to add a new SObject (e.g. Case to Jira)

Today only Opportunity is wired up. Cases ship pre-configured in the CMDT but the per-SObject trigger / service does not exist yet. Enabling a different SObject requires a deploy — the CMDT is one part of three:

1. **CMDT record** ([`Jira_Push_Object__mdt`](../../force-app/main/default/objects/Jira_Push_Object__mdt/Jira_Push_Object__mdt.object-meta.xml)) with `SObject_API_Name__c`, `Active__c`, **`Jira_Project_Id__c`** (the Jira project key, e.g. `CSI`), and **`Jira_Issue_Type__c`** (e.g. `Story`).
2. A per-SObject service class + trigger handler.
3. The trigger itself.

Talk to the Apex team — they own steps 2 + 3. You own step 1 (the CMDT record). See the [operations runbook](../operations/csi7162-jira-push-runbook.md#enabling-a-new-sobject) for the full procedure.

## What you can't do from the UI

These need a developer (and a deploy):

- **Add a new field to the qualifying-fields set.** The list is in Apex (`OpportunityService.JIRA_QUALIFYING_FIELDS`). Adding a field means a code change + tests + deploy.
- **Change what Jira receives.** The Salesforce side only pushes the record Id. The fields Jira pulls back are owned by the **Appfire JCFS connector configuration in Jira**, not Salesforce. Coordinate with your Jira admin.
- **Push a different object** (e.g. Case to Jira). The framework supports it but adding a target needs a per-object service class + trigger handler — talk to the Apex team.

## Further reading

- [Architecture overview](../architecture/csi7162-jira-push-overview.md) — for the full pipeline diagram.
- [Operations runbook](../operations/csi7162-jira-push-runbook.md) — for triage, replay, and configuration reference.
- [CSI-7162 in Jira](https://experance.atlassian.net/browse/CSI-7162).
