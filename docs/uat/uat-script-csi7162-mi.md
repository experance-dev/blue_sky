---
title: UAT Script — CSI-7162 (Jira Push) + Marketing Influence (MI)
author: David Wood
audience: UAT testers (Sales Ops, Integration Admins, Marketing Ops)
target-environment: UAT sandbox (sandbox refresh from production within the last 7 days)
estimated-duration: 90 minutes (CSI-7162: 30 min · MI: 60 min)
last-updated: 2026-05-14
---

# UAT Script — CSI-7162 + Marketing Influence

> **Note:** Run every step in order. Check the **Pass** or **Fail** box. If a step fails, capture: (a) the action you took, (b) the expected outcome, (c) what actually happened, (d) any screenshots or error messages. File a ticket linking back to this script step (e.g. "UAT step 1.3 failed: ...").

## Tester sign-in

| Field                     | Value                          |
| ------------------------- | ------------------------------ |
| **Tester name**           | **************\_************** |
| **Date**                  | **************\_************** |
| **Environment / sandbox** | **************\_************** |
| **Sandbox refresh date**  | **************\_************** |
| **Outcome (circle one)**  | PASS / PASS WITH ISSUES / FAIL |

## Required setup before UAT begins

The release engineer must complete these **before** the tester starts:

- [ ] Sandbox refreshed from production within the last 7 days.
- [ ] CSI-7162 components deployed per [CSI-7162 go-live runbook §Deploy](../runbooks/csi-7162-go-live.md#deploy-steps).
- [ ] MI components deployed per [MI go-live runbook §Deploy](../runbooks/mi-go-live.md#deploy-steps).
- [ ] Appfire JCFS managed package installed in the sandbox.
- [ ] HubSpot has a sandbox-pointing workflow that can fire a test event on demand.
- [ ] Tester has these permsets assigned: `Engagement_Attribution_User`, `Engagement_Attribution_Admin`. (CSI-7162 has no dedicated integration permset today — system access flows through the integration user that runs the JCFS callouts.)
- [ ] Tester has access to: Salesforce sandbox UI, Salesforce Developer Console (anonymous Apex), Jira sandbox project `CSI`, HubSpot sandbox workflow trigger.
- [ ] One test Account named `UAT - Test Account` exists with one open Opportunity named `UAT - Test Opportunity`, stage `Prospecting`, close date 30 days out.
- [ ] At least one Contact on that Account with email `uat-contact@example.com`.
- [ ] One Lead with email `uat-lead@example.com` on a separate (unconnected) email domain.

---

# Feature 1 — CSI-7162 — Jira Push on Opportunity Change

Tests the Salesforce -> Jira push pipeline. Each test isolates one acceptance criterion.

## Step 1.1 — Insert publishes a Create event

**Pre-state required:**

- `Jira_Push_Object.Opportunity.Active__c = true` in CMDT.
- `API_Exception_Log__c` row count noted: `before = ____`.

**Action:**

1. Open the Sales app -> Opportunities -> **New**.
2. Account = `UAT - Test Account`.
3. Name = `UAT 1.1 ` + today's date.
4. Stage = `Prospecting`.
5. Close Date = 30 days from today.
6. Click **Save**.

**Expected outcome:**

- Opportunity saves successfully (no error toast).
- Open Developer Console -> Logs. In the most recent log, find the line: `INFO|JiraPushService|publish|Publishing 1 Jira push event(s) for Opportunity (txn ...)`.
- Within 1 minute, a new issue appears in Jira sandbox project `CSI` corresponding to this Opportunity.
- `API_Exception_Log__c` row count after = `____`. Should equal `before`.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 1.2 — Update on qualifying field publishes an Update event

**Pre-state required:** The Opportunity from Step 1.1 exists. `API_Exception_Log__c` row count noted: `before = ____`.

**Action:**

1. Open the Opportunity from Step 1.1.
2. Change Stage from `Prospecting` to `Qualification`.
3. Save.

**Expected outcome:**

- Save succeeds.
- Developer Console log shows: `INFO|JiraPushService|publish|Publishing 1 Jira push event(s) for Opportunity (txn ...)`.
- The Jira issue from Step 1.1 updates within 1-2 minutes to reflect the new stage.
- `API_Exception_Log__c` row count after = `____`. Should equal `before`.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 1.3 — Update on non-qualifying field does NOT publish

**Pre-state required:** The Opportunity from Step 1.1 exists.

**Action:**

1. Open the same Opportunity.
2. Edit only the **Description** field (any text — e.g. "UAT 1.3 test").
3. Save.

**Expected outcome:**

- Save succeeds.
- Developer Console log does **not** contain `Publishing ... Jira push event(s)` for this transaction.
- Jira side: no update to the Description field on the Jira issue (Jira's pull mapping doesn't include it, and no event was published).

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 1.4 — Kill switch (CMDT `Active__c = false`) suppresses publish

**Pre-state required:** The Opportunity from Step 1.1 exists.

**Action:**

1. Setup -> Custom Metadata Types -> Jira Push Object -> Manage Records -> click `Opportunity`.
2. Uncheck `Active__c`. Save.
3. Open the test Opportunity.
4. Change Stage to `Proposal/Price Quote`. Save.

**Expected outcome:**

- Save succeeds.
- Developer Console log shows: `INFO|JiraPushService|publish|Jira push inactive for Opportunity; skipping publish`.
- Jira side: no update to the issue.
- `API_Exception_Log__c`: no new row.

**Restore step (required before moving on):**

- Setup -> Custom Metadata Types -> Jira Push Object -> Manage Records -> `Opportunity` -> re-check `Active__c`. Save.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 1.5 — Per-record failure logging

**Pre-state required:** `Jira_Push_Object.Opportunity.Active__c = true`. JCFS is healthy in the sandbox.

> **Note:** This step requires the JCFS admin to temporarily induce a per-record failure (e.g. by mis-mapping one Opportunity in JCFS). If the JCFS admin can't induce a failure on demand, mark this step as "deferred" and verify in production after the next legitimate failure.

**Action:**

1. JCFS admin: mis-configure the Jira mapping for the test Opportunity (e.g. point it at a deleted Jira project).
2. Tester: open the test Opportunity, change Stage. Save.

**Expected outcome:**

- Save succeeds.
- Developer Console log shows the `Publishing ...` line.
- Within 1 minute, an `API_Exception_Log__c` row appears with:
  - `API_Name__c = 'JCFS'`
  - `Operation__c = 'JCFS.API.pushUpdatesToJira (per-record)'`
  - `Source_Record_Id__c` = the Opportunity's Id
  - `Message__c` prefixed `'JCFS rejected record: '`

**Restore step:** JCFS admin re-points the mapping.

- [ ] **PASS**
- [ ] **FAIL**
- [ ] **DEFERRED**

## Step 1.6 — Opportunity save never blocked by Jira availability

**Pre-state required:** The JCFS admin can mark the connector "paused" in JCFS, or disable the connected app temporarily.

> **Note:** If you can't pause JCFS in the sandbox, use the kill switch instead (Step 1.4). The point of this test is "the Salesforce save commits regardless of downstream availability" — both paths verify it.

**Action:**

1. JCFS admin: pause the Jira connector OR disable Jira-side authentication temporarily.
2. Tester: open the test Opportunity. Change Stage to `Closed Won`. Save.

**Expected outcome:**

- Save succeeds within a normal Salesforce response time (< 3 seconds).
- The Salesforce save does **not** stall, time out, or error.
- Developer Console log shows: `Publishing 1 Jira push event(s)...`.
- An `API_Exception_Log__c` row eventually appears with the JCFS-down error.

**Restore step:** JCFS admin re-enables the connector.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## CSI-7162 — Tester comments

---

---

# Feature 2 — Marketing Influence (MI)

Tests the HubSpot -> Salesforce -> right-rail panel pipeline. Each test exercises one or two acceptance criteria.

## Step 2.1 — Inbound REST accepts a valid event

**Pre-state required:**

- Test Contact exists: `uat-contact@example.com` on `UAT - Test Account`.
- `Touch_Topic__c` with `External_Code__c = 'PRICING'` exists and is active.
- HubSpot Ops can fire a test event from their UAT workflow, OR you have an Integration User session token and curl access.

**Action (Option A — via HubSpot):** HubSpot Ops triggers a test event for `uat-contact@example.com` with topic `PRICING`.

**Action (Option B — via curl):**

```bash
curl -X POST 'https://<sandbox>.my.salesforce.com/services/apexrest/engagement/touches/' \
  -H 'Authorization: Bearer <integration user session>' \
  -H 'Content-Type: application/json' \
  -d '{
    "events": [{
      "external_id": "uat-2-1-001",
      "email": "uat-contact@example.com",
      "occurred_at": "2026-05-14T12:00:00Z",
      "topic_external_code": "PRICING",
      "touch_type": "WHITEPAPER_DOWNLOAD",
      "campaign_name": "UAT Campaign",
      "intent_level": 75
    }]
  }'
```

**Expected outcome:**

- HTTP response: `200 OK`.
- Response body: `{"success": true, "processed": 1, "results": [{"external_id": "uat-2-1-001", "resolution_status": "Resolved"}]}`.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 2.2 — Touch is identity-resolved to the Contact

**Pre-state required:** Step 2.1 passed.

**Action:** In Developer Console, run:

```apex
Engagement_Touch__c t = [
    SELECT Id, External_Id__c, Resolution_Status__c, Contact__c, Lead__c, Account__c, Touch_Topic__c
    FROM Engagement_Touch__c
    WHERE External_Id__c = 'uat-2-1-001'
    LIMIT 1
];
System.debug(t);
```

**Expected outcome:**

- `Resolution_Status__c` = `Resolved`.
- `Contact__c` is populated (matches `uat-contact@example.com`'s Contact Id).
- `Lead__c` is null.
- `Account__c` is populated (matches `UAT - Test Account`'s Id).
- `Touch_Topic__c` is populated.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 2.3 — Lead-only match resolves to Lead

**Pre-state required:** Lead exists: `uat-lead@example.com`. No Contact with that email.

**Action:** Send another inbound POST (curl or HubSpot) for `uat-lead@example.com`, `external_id = uat-2-3-001`, topic `PRICING`.

**Expected outcome:** SOQL query against the new Touch shows `Resolution_Status__c = 'Resolved'`, `Lead__c` populated, `Contact__c` null.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 2.4 — Unknown email lands as Pending

**Action:** Send an inbound POST for `nobody-knows-me@example.com`, `external_id = uat-2-4-001`, topic `PRICING`.

**Expected outcome:** Response `200`. Touch row exists with `Resolution_Status__c = 'Pending'`, `Contact__c` and `Lead__c` both null.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 2.5 — Signal is produced for the test Opportunity

**Pre-state required:** Step 2.2 passed; `UAT - Test Opportunity` is open with `Touch_Topic__c = PRICING` (or however the routing rules match).

**Action:** In Developer Console:

```apex
List<Opportunity_Engagement_Signal__c> sigs = [
    SELECT Id, Opportunity__c, Match_Path__c, Confidence__c
    FROM Opportunity_Engagement_Signal__c
    WHERE Engagement_Touch__r.External_Id__c = 'uat-2-1-001'
];
for (Opportunity_Engagement_Signal__c s : sigs) System.debug(s);
```

**Expected outcome:** At least one signal exists pointing at `UAT - Test Opportunity`, with `Match_Path__c` reflecting the rule that matched (most likely `OCR` if the test Contact is on OCR, otherwise `Account` or `ACR`).

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 2.6 — Idempotency on re-routing

**Action:** Send the **same** inbound event again (same `external_id = uat-2-1-001`, same payload). Then re-run the signal SOQL from Step 2.5.

**Expected outcome:**

- Inbound endpoint returns `200`.
- The Touch row is updated (idempotent upsert by `External_Id__c`), not duplicated.
- The signal count is unchanged — no duplicate signals produced.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 2.7 — Right-rail panel renders on Opportunity

**Action:** As a user with the `Engagement_Attribution_User` permset, open `UAT - Test Opportunity` in the Lightning UI.

**Expected outcome:**

- The `engagementPanel` LWC is visible on the right rail.
- It shows two sections: **Deal Team** and **Not on Deal Team**.
- The test Contact (`uat-contact@example.com`) appears in one of them, with a topic chip showing `PRICING`, a touch count of at least 1, and (if in "Not on Deal Team") a `+ Add` button.
- Rows are sorted by most-recent touch first.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 2.8 — Add-to-Deal-Team flow

**Pre-state required:** Step 2.7 passed and the test Contact is in the "Not on Deal Team" section.

**Action:**

1. Click `+ Add` on the test Contact's row.
2. `addToDealTeamModal` opens. Pick a role (e.g. `Influencer`).
3. Click **Add**.

**Expected outcome:**

- The modal closes.
- The panel re-renders within ~1 second.
- The test Contact now appears in the **Deal Team** section, with an `on team` indicator.
- The `+ Add` button is gone for that contact.
- In Salesforce: a new `OpportunityContactRole` row exists for (test Opp, test Contact, Influencer).

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 2.9 — Already-on-OCR confirm path

**Pre-state required:** Step 2.8 passed (Contact is now on OCR).

**Action:**

1. (Conceptually) trigger the "+ Add" path again — e.g. send another touch for the same contact, refresh the panel, and the row may re-appear briefly. OR: use the admin app to force a state where the contact is on OCR and the panel is asked to "add" them again.

> **Note:** In practice this path triggers when the panel and OCR get out of sync. If it's not reproducible in the test flow, mark deferred.

**Expected outcome:** `alreadyAddedModal` opens with a confirmation message — no duplicate OCR row is inserted.

- [ ] **PASS**
- [ ] **FAIL**
- [ ] **DEFERRED**

## Step 2.10 — Account-scope panel

**Action:** Open `UAT - Test Account` in the Lightning UI.

**Expected outcome:**

- `engagementPanel` is visible on the right rail of the Account page.
- Shows a single flat list (no Deal Team grouping).
- Lists all engaged people on the account (Contacts + ACRs + unresolved-Leads matching the account domain).
- Sorted by most-recent touch first.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 2.11 — Per-user dismissal

**Action:**

1. On the Opportunity panel, dismiss one row (look for the dismiss / hide control in the UI).
2. Refresh the page.

**Expected outcome:** The dismissed row no longer appears for **your** user. Log in as another user (admin or a different sales rep) and confirm the row is still visible for them.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 2.12 — Lead conversion repoints touches

**Pre-state required:** The Lead from Step 2.3 (`uat-lead@example.com`) has touches.

**Action:**

1. Open the Lead.
2. Click **Convert**. Convert to a new Contact + Account (use the convert wizard's defaults).
3. After conversion completes, in Developer Console:

```apex
List<Engagement_Touch__c> reparented = [
    SELECT Id, External_Id__c, Contact__c, Lead__c, Account__c
    FROM Engagement_Touch__c
    WHERE External_Id__c = 'uat-2-3-001'
];
for (Engagement_Touch__c t : reparented) System.debug(t);
```

**Expected outcome:** `Lead__c` is now null; `Contact__c` is populated with the newly-converted Contact's Id; `Account__c` updated accordingly.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## Step 2.13 — Erasure cascade (CCPA / HIPAA delete)

**Pre-state required:** A throwaway test Contact `uat-erasure@example.com` exists with at least one touch and one signal.

**Action:**

1. Confirm baseline counts:

```apex
String email = 'uat-erasure@example.com';
Contact c = [SELECT Id FROM Contact WHERE Email = :email LIMIT 1];
System.debug('Touches: ' + [SELECT COUNT() FROM Engagement_Touch__c WHERE Contact__c = :c.Id]);
System.debug('Signals: ' + [SELECT COUNT() FROM Opportunity_Engagement_Signal__c WHERE Engagement_Touch__r.Contact__c = :c.Id]);
```

2. Delete the Contact via the standard Lightning UI **Delete** action.

3. Confirm cascade:

```apex
System.debug('Touches after (ALL ROWS): ' + [SELECT COUNT() FROM Engagement_Touch__c WHERE Contact__c = :c.Id ALL ROWS]);
System.debug('Signals after (ALL ROWS): ' + [SELECT COUNT() FROM Opportunity_Engagement_Signal__c WHERE Engagement_Touch__r.Contact__c = :c.Id ALL ROWS]);
```

**Expected outcome:**

- Contact deletes successfully.
- Touches and Signals related to that Contact are zero — even with `ALL ROWS` (hard deleted, recycle bin emptied).
- Developer Console log contains: `INFO|EngagementErasureService|eraseForContacts|Subject erasure cascade — 1 subject(s) of type Contact: deleted N touch(es), M signal(s), P dismissal(s).`.

- [ ] **PASS**
- [ ] **FAIL** — describe: **********************\_\_\_\_**********************

## MI — Tester comments

---

---

# Final sign-off

| Section                                | Pass count | Fail count | Deferred |
| -------------------------------------- | ---------: | ---------: | -------: |
| CSI-7162 (Steps 1.1 – 1.6)             |     **\_** |     **\_** |   **\_** |
| Marketing Influence (Steps 2.1 – 2.13) |     **\_** |     **\_** |   **\_** |
| **TOTAL**                              |     **\_** |     **\_** |   **\_** |

**Overall recommendation:**

- [ ] **APPROVED for production go-live** — all critical paths pass.
- [ ] **APPROVED WITH ISSUES** — non-blocking failures, list in tester comments above.
- [ ] **NOT APPROVED** — block go-live, fix and re-test.

| Tester signature | ************\_************ | Date | ****\_\_**** |
| ---------------- | -------------------------- | ---- | ------------ |

## References

- [CSI-7162 user story](../jira/csi-7162-user-story.md)
- [CSI-7162 Confluence tech doc](../confluence/csi-7162-technical.md)
- [CSI-7162 go-live runbook](../runbooks/csi-7162-go-live.md)
- [MI user story](../jira/mi-user-story.md)
- [MI Confluence tech doc](../confluence/mi-technical.md)
- [MI go-live runbook](../runbooks/mi-go-live.md)
- [MI demo flow](../../.claude/worktrees/feature-engagement-attribution/docs/users/DEMO.md)
