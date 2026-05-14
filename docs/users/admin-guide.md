# Admin Guide

This guide covers the **UI-side** admin work for Engagement Attribution — placing the sales-facing panel on Account and Opportunity record pages, and dropping the three admin LWCs onto an App Page. Server-side admin (permission set assignment, custom settings, batch scheduling) is covered by Marlowe in the same file under separate sections.

For the end-to-end deploy + activate + seed walkthrough see [`DEMO.md`](./DEMO.md) §1–§5.

## Place the Engagement Panel on a record page

The Phase 1 build ships pre-configured flexipages for both record types:

- [`Opportunity_Engagement_Record_Page.flexipage-meta.xml`](../../force-app/main/default/flexipages/Opportunity_Engagement_Record_Page.flexipage-meta.xml)
- [`Account_Engagement_Record_Page.flexipage-meta.xml`](../../force-app/main/default/flexipages/Account_Engagement_Record_Page.flexipage-meta.xml)

These deploy as **inactive** — Salesforce doesn't let you set a Lightning page as the org default via metadata-only deploys. The activation is a 30-second click-through per page:

1. `sf org open --target-org <yourOrg>` — opens Lightning.
2. Setup → **Lightning App Builder** (or directly: `https://<org>/lightning/setup/FlexiPageList/home`).
3. Open **Opportunity Engagement Record Page** → **Activation…** → **Assign as Org Default** → **Next** (Desktop) → **Save**.
4. Repeat for **Account Engagement Record Page**.

Both flexipages place [`engagementPanel`](../development/components/engagementPanel.md) on the right rail with the correct `recordContext` design property set per record type (`Opportunity` on the Opportunity page, `Account` on the Account page).

### Placing the panel on a custom flexipage

If you're not using the shipped flexipages — or you want to add the panel to a different record page — the steps in App Builder:

1. Open the target Lightning Record Page in App Builder.
2. Drag **Engagement Panel** from the **Custom** section of the components palette to the right-rail region.
3. In the right-side properties panel, set **Record context** to `Account` or `Opportunity` to match the page's object.
4. Save → Activation… → assign as org default (or app-specific, or per-profile).

**Important:** The `recordContext` property MUST match the page's object. If you place the panel with `recordContext=Account` on an Opportunity page, the panel will issue an `Account` Apex call with an Opportunity id and render empty. The panel doesn't validate this — App Builder is the right surface to enforce it.

### Confirming it renders

After activation, open any Account or Opportunity record. The panel should appear top-right under the header with the heading **Engagement Intelligence — N engaged** (where N may be zero if no touches have arrived yet). If the panel is blank or absent:

- **Panel doesn't appear at all** → flexipage isn't the assigned org default. Re-check Activation in App Builder.
- **Panel renders the "No engagement activity yet" empty state** → expected when no touches exist. Seed via [`DEMO.md §5`](./DEMO.md) or wait for inbound HubSpot events (Phase 2).
- **Panel renders the red error banner** → check the [`Engagement_Attribution_User`](../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml) permission set is assigned to the running user; the panel can't read its objects without it.

The visual smoke test is documented in [`DEMO.md §Smoke-deploy verification`](./DEMO.md#smoke-deploy-verification-already-done) — both panels rendered correctly against the United Healthcare seed in the Phase 1 build.

## Place the admin LWCs on an App Page

Three admin LWCs ship for the routing-rules monitoring surface — all flagged `<isExposed>true</isExposed>` on `lightning__AppPage` and `lightning__HomePage` targets:

| Component                                                                                                              | Source                  | What it does                                                                                       |
| ---------------------------------------------------------------------------------------------------------------------- | ----------------------- | -------------------------------------------------------------------------------------------------- |
| [`engagementTestATouch`](../../force-app/main/default/lwc/engagementTestATouch/engagementTestATouch.js-meta.xml)       | `Test-a-Touch (Admin)`  | Synthesize a test engagement touch and observe how identity resolution + routing react.            |
| [`engagementRuleCoverage`](../../force-app/main/default/lwc/engagementRuleCoverage/engagementRuleCoverage.js-meta.xml) | `Rule Coverage (Admin)` | Lists routing rules and the signals they produced in the last 30 days, highlighting dead rules.    |
| [`engagementErrorQueue`](../../force-app/main/default/lwc/engagementErrorQueue/engagementErrorQueue.js-meta.xml)       | `Error Queue (Admin)`   | Surfaces problem touches (`NoMatch` / `Ambiguous` / `Error`) with inline retry and ignore actions. |

The pre-configured admin flexipage is [`Engagement_Admin_Console.flexipage-meta.xml`](../../force-app/main/default/flexipages/Engagement_Admin_Console.flexipage-meta.xml) — all three components stacked in a single region on a default App Home template.

### Wiring up a Lightning App tab

The flexipage deploys but doesn't appear in the navigation by default. To expose it as a tab:

1. Setup → **App Manager** → choose the Lightning App you want to host the admin console in (or **New Lightning App** for a dedicated one).
2. **Navigation Items** → add a custom **Engagement Admin** tab that points at the `Engagement Admin Console` flexipage.
3. **User Profiles** → assign to admin profiles only. The three components carry no record-level sharing — they're admin-only tooling.
4. Save the app, then assign it to the admin profile if it's not already.

Open the app, navigate to the new tab, confirm all three LWCs render. Test-a-Touch should accept input; Rule Coverage should list the 5 seeded routing rules; Error Queue should show whatever resolution-status errors exist (zero on a fresh seed).

### Placing them on a different page

Each component is also valid on a `lightning__HomePage`, so you can drop them into a personal Home Page layout for a power user — or onto a `lightning__AppPage` you build from scratch. The three components are independent of each other; they don't compose, they don't share state. Place any subset.

## Permissions

All four LWCs (the sales panel + three admin components) read through Apex controllers that respect `WITH USER_MODE` / `AccessLevel.USER_MODE` — they need the [`Engagement_Attribution_User`](../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml) permission set on the running user. Without it the panel renders an error banner and the admin LWCs render empty.

Assign via:

```bash
sf org assign permset --name Engagement_Attribution_User --target-org <yourOrg>
```

…or via Setup → Permission Sets → assign by username. The permset's scope is documented in Marlowe's section.

## Summary

- Sales panel: activate the two shipped flexipages in App Builder, or drop `c:engagementPanel` onto your own with `recordContext` matching the record type.
- Admin console: the shipped flexipage already wires the three admin LWCs; expose it as a tab in a Lightning App.
- Permset: assign `Engagement_Attribution_User` to anyone using either surface.

See also: [`docs/users/DEMO.md`](./DEMO.md), [`docs/users/sales-rep-guide.md`](./sales-rep-guide.md), [`docs/development/components/engagementPanel.md`](../development/components/engagementPanel.md).
