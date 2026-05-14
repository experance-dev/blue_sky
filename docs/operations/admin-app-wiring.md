# Admin App Wiring Runbook

How the **Engagement Admin Console** is wired into a Salesforce org so that admins can actually reach Test-a-Touch, Rule Coverage, and Error Queue. Source of truth for the wiring lives in `force-app/main/default/`; this runbook explains what each file does, the inventory you should expect to see in a freshly-deployed org, and the Playwright smoke playbook to verify the wiring.

Deploy / scratch-org-lifecycle is owned by Dash. Permset assignments are reviewed by Sage Cloudy. This runbook is owned by Otto.

## TL;DR — what makes the admin console reachable

Four metadata files. All required:

| File                                                                                                                                                                                                                                                                                                                                                                   | Role                                                                                                                                                                                                                                    |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`lwc/engagementTestATouch`](../../force-app/main/default/lwc/engagementTestATouch/engagementTestATouch.js-meta.xml), [`lwc/engagementRuleCoverage`](../../force-app/main/default/lwc/engagementRuleCoverage/engagementRuleCoverage.js-meta.xml), [`lwc/engagementErrorQueue`](../../force-app/main/default/lwc/engagementErrorQueue/engagementErrorQueue.js-meta.xml) | The three admin LWCs. Each has `isExposed=true` and `lightning__AppPage`+`lightning__HomePage` targets.                                                                                                                                 |
| [`flexipages/Engagement_Admin_Console.flexipage-meta.xml`](../../force-app/main/default/flexipages/Engagement_Admin_Console.flexipage-meta.xml)                                                                                                                                                                                                                        | AppPage FlexiPage that hosts all three LWCs in its `main` region. Auto-activated on deploy.                                                                                                                                             |
| [`tabs/Engagement_Admin_Console.tab-meta.xml`](../../force-app/main/default/tabs/Engagement_Admin_Console.tab-meta.xml)                                                                                                                                                                                                                                                | CustomTab pointing at the FlexiPage above. Motif `Custom52: Bell`. Label `Engagement Admin`.                                                                                                                                            |
| [`applications/Engagement_Admin.app-meta.xml`](../../force-app/main/default/applications/Engagement_Admin.app-meta.xml)                                                                                                                                                                                                                                                | CustomApplication that includes the tab in its nav. Without this, the tab has no app home and is unreachable from the App Launcher.                                                                                                     |
| [`permissionsets/Engagement_Attribution_User.permissionset-meta.xml`](../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml)                                                                                                                                                                                                  | Grants tab visibility (`tabSettings` → `Engagement_Admin_Console` → Visible) plus class access for the controllers the LWCs call. Single permset for both end-users and admins — there is no separate "Engagement Admin" permset today. |

End-user wiring (record pages) lives in two more FlexiPages, but they're standard "active for app + record-type" Lightning record pages with no extra plumbing needed:

| File                                                                                                                                                                | Role                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| [`flexipages/Account_Engagement_Record_Page.flexipage-meta.xml`](../../force-app/main/default/flexipages/Account_Engagement_Record_Page.flexipage-meta.xml)         | Account record page with `engagementPanel` in the right rail.     |
| [`flexipages/Opportunity_Engagement_Record_Page.flexipage-meta.xml`](../../force-app/main/default/flexipages/Opportunity_Engagement_Record_Page.flexipage-meta.xml) | Opportunity record page with `engagementPanel` in the right rail. |

## Common gap: tab without a home

The bug that triggered this runbook (2026-05-12, `engagementDev` scratch). Source had the FlexiPage, the Tab, and the permset but **no CustomApplication**. The tab existed but had no parent app, so:

- App Launcher did not surface a "MI Admin" / "Engagement" experience.
- Standard Sales / Service apps' nav menus did not include the tab.
- The page was only reachable by direct URL — not real wiring.

Fix: author [`applications/Engagement_Admin.app-meta.xml`](../../force-app/main/default/applications/Engagement_Admin.app-meta.xml) and deploy. The XML is intentionally minimal:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<CustomApplication xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Engagement Admin</label>
    <navType>Standard</navType>
    <uiType>Lightning</uiType>
    <formFactors>Large</formFactors>
    <tabs>Engagement_Admin_Console</tabs>
    <!-- ...brand + nav-personalization flags... -->
</CustomApplication>
```

Decision: **new dedicated app, not injection into standard Sales**. Reasons:

1. Overwriting `standard__Sales` via metadata means the deploy now owns Zelis's stock Sales app config — risky blast radius for unrelated tab order, utility bar, etc.
2. A dedicated app is the right semantic for an admin console anyway.
3. Easy to remove or rename later without touching anything else.

## Deploy the wiring to a scratch org

```bash
# from the feature worktree
sf project deploy start --target-org engagementDev \
  --source-dir force-app/main/default/applications \
  --source-dir force-app/main/default/tabs \
  --source-dir force-app/main/default/flexipages \
  --source-dir force-app/main/default/lwc
```

Or just deploy the whole package — the order above is what `sf` will resolve automatically:

```bash
sf project deploy start --target-org engagementDev --source-dir force-app
```

## Assign the permset

**Otto does not assign permsets without Sage's loop-in.** When Sage signs off, the command is:

```bash
sf org assign permset --target-org engagementDev --name Engagement_Attribution_User
```

Verify after assignment:

```bash
sf data query --target-org engagementDev \
  --query "SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name = 'Engagement_Attribution_User'"
```

In a fresh scratch org the scratch admin user is normally already assigned via the `users` config. Confirm before re-assigning.

## Inventory you should see in a freshly-deployed org

```bash
# FlexiPages
sf org list metadata --target-org engagementDev --metadata-type FlexiPage --json \
  | sed -n '/^{/,$p' | python3 -c "import sys,json; print('\n'.join(sorted(r['fullName'] for r in json.load(sys.stdin)['result'])))"
```

Expected (engagement-related rows only):

- `Account_Engagement_Record_Page`
- `Engagement_Admin_Console`
- `Opportunity_Engagement_Record_Page`

```bash
sf org list metadata --target-org engagementDev --metadata-type CustomTab --json \
  | sed -n '/^{/,$p' | python3 -c "import sys,json; print('\n'.join(sorted(r['fullName'] for r in json.load(sys.stdin)['result'])))"
```

Expected (engagement-related): `Engagement_Admin_Console`.

```bash
sf org list metadata --target-org engagementDev --metadata-type CustomApplication --json \
  | sed -n '/^{/,$p' | python3 -c "import sys,json; print('\n'.join(sorted(r['fullName'] for r in json.load(sys.stdin)['result'])))"
```

Expected (engagement-related): `Engagement_Admin` (plus all stock `standard__*` apps).

## Playwright smoke playbook

This is the routine to verify wiring is reachable end-to-end. Replayable against any scratch org with the package deployed.

### Step 1 — Open Setup via frontdoor

```bash
sf org open --target-org engagementDev --path lightning/setup/SetupOneHome/home --url-only --json
```

Take the `result.url`, navigate to it in Playwright. This gives you an authenticated session that bypasses the OAuth dance.

### Step 2 — Verify the Admin Console renders

Navigate directly to the tab:

```text
https://<my-domain>/lightning/n/Engagement_Admin_Console
```

Wait for `Test-a-Touch` text to be visible. Page title should be `Engagement Admin | Salesforce`.

Verify all three LWCs are mounted. Run in browser context (note: LWCs live behind shadow roots, so walk them):

```javascript
function walk(root, out) {
  const all =
    root.querySelectorAll?.(
      "c-engagement-test-a-touch, c-engagement-rule-coverage, c-engagement-error-queue"
    ) || [];
  for (const el of all) {
    out.push({
      tag: el.tagName.toLowerCase(),
      text:
        el.shadowRoot?.textContent?.trim().slice(0, 200) ??
        el.textContent?.trim().slice(0, 200)
    });
  }
  for (const el of root.querySelectorAll?.("*") || []) {
    if (el.shadowRoot) walk(el.shadowRoot, out);
  }
}
const out = [];
walk(document, out);
out;
```

Expected: 3 entries, one per admin LWC, each with non-empty rendered text. Counted-zero outputs (e.g. "0 touches pending review") are _good_ — that's the empty-state rendering, not a failure.

### Step 3 — Check console for errors

```javascript
// no useful direct API; in Playwright use browser_console_messages level=error
```

Filter out CSP errors from `EmpApi.getEmpConfig` — those are platform noise from prior Setup navigations and don't indicate a problem with our LWCs. **Any error referencing `c-engagement-*` is a real defect** — surface to Coda.

### Step 4 — Spot-check the end-user record pages

```text
https://<my-domain>/lightning/r/Account/<accountId>/view
https://<my-domain>/lightning/r/Opportunity/<oppId>/view
```

Use `sf data query --query "SELECT Id FROM Account LIMIT 1"` to grab any seeded record. After seeding via the demo script, the engagementPanel renders with multiple contacts and touch counts.

Verify panel renders:

```javascript
function walk(root, out) {
  const all = root.querySelectorAll?.("c-engagement-panel") || [];
  for (const el of all) {
    out.push(el.shadowRoot?.textContent?.trim().slice(0, 400));
  }
  for (const el of root.querySelectorAll?.("*") || []) {
    if (el.shadowRoot) walk(el.shadowRoot, out);
  }
}
const out = [];
walk(document, out);
out;
```

Expected: 1 entry containing `Engagement Intelligence` and a contact-count summary.

## Triage — common admin-tickets against this wiring

- **"I can't see the Engagement Admin app in the App Launcher."** → Check (a) permset is assigned, (b) profile has app visibility, (c) `Engagement_Admin` CustomApplication is deployed. The Tooling API query `SELECT DeveloperName FROM CustomApplication WHERE DeveloperName = 'Engagement_Admin'` is the fastest existence check.
- **"The Engagement Admin tab is there but the page is blank."** → FlexiPage either failed to deploy or all three LWCs are missing their components. Open Lightning App Builder directly: `/visualEditor/appBuilder.app?pageId=<flexipage-id>` and confirm all three components are present in the `main` region.
- **"Engagement Panel doesn't show on Account / Opportunity."** → The record pages are wired via the two `*_Engagement_Record_Page.flexipage-meta.xml` files. Confirm they are deployed AND that they are assigned as the active page for the relevant app + record-type combination. Standard `Account_Record_Page` / `Opportunity_Record_Page` exist as fallback but do not include `engagementPanel`.
- **"I see CSP errors in the console."** → Almost always Setup-page noise (`EmpApi.getEmpConfig`). Only treat as a real defect if the error message mentions `c-engagement-*` or one of our Apex controller names.

## 2026-05-12 wire-up log — engagementDev scratch

Smoke test results from the original wire-up session, kept here as a known-good baseline:

| Check                                           | Result | Notes                                                                                                                             |
| ----------------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| App `Engagement_Admin` deployed                 | OK     | Deploy id `0AfDP00001YVVT50AP`, component id `02uDP000000dfBHYAY`                                                                 |
| `/lightning/n/Engagement_Admin_Console` renders | OK     | Page title `Engagement Admin                                                                                                      | Salesforce` |
| `engagementTestATouch` rendered                 | OK     | Form fields: Email, Topic external code, Touch type, Persona, Intent level, Asset name                                            |
| `engagementRuleCoverage` rendered               | OK     | Alert: "4 rules produced zero signals in the last 30 days."                                                                       |
| `engagementErrorQueue` rendered                 | OK     | Empty-state: "0 touches pending review · No touches require attention."                                                           |
| Account record page `engagementPanel`           | OK     | "Engagement Intelligence · 7 engaged" with named contacts (Sarah Johnson / Marcus Brown / Rachel Kim / Mike Chen / Lisa Patel)    |
| Opportunity record page `engagementPanel`       | OK     | "Engagement Intelligence · 4 engaged · Deal Team — 3 on OCR · Engaged — not on Deal Team · 1" with named contacts and "+ Add" CTA |
| Browser console errors on Admin Console page    | None   | Only stock CSP warnings on prior Setup navigations                                                                                |
| Browser console errors on record pages          | None   | —                                                                                                                                 |

Captured snapshots: [`2026-05-12-admin-console-rendered.md`](snapshots/2026-05-12-admin-console-rendered.md), [`2026-05-12-account-page-rendered.md`](snapshots/2026-05-12-account-page-rendered.md), [`2026-05-12-opportunity-page-rendered.md`](snapshots/2026-05-12-opportunity-page-rendered.md).
