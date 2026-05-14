# LWC Visibility Patterns — Permset Gating in OWD Private

Canonical pattern for permset-gated LWCs on this codebase. Audience: the next dev placing a Lightning component on a record page in an OWD-Private org. Read [`lwc-conventions.md`](./lwc-conventions.md) first for the conventions baseline; this page is the visibility-gating delta.

The worked example is [`c:engagementPanel`](./components/engagementPanel.md). Every step below cites the live source it landed in at commit [`1c2be54`](../../).

## Why this matters

Zelis is [OWD Private](../../best-practices/architecture.md). Every UI surface that displays business data has to gate visibility through a permset. The naive failure mode — ship the LWC and trust profile FLS — leaks UI to users without a business reason to see it AND fails the inverse case where the right user can't access. Both happen. Both are Definition-of-Done misses.

We gate twice:

1. **FlexiPage Component Visibility** hides the component entirely from users without the View custom permission. They never see the panel exists.
2. **Intra-LWC gating** hides individual action elements from View-tier users (read-only). Power Users keep the buttons.

The two layers are independent on purpose. If a FlexiPage rule is edited away in production by mistake, the LWC's outer `lwc:if` still hides the panel. Defense-in-depth.

## The pattern, step by step

### Step 1 — Ship two custom permissions per feature

For each feature with two access tiers, ship a `<Feature>_View` and a `<Feature>_Power_User` custom permission:

- **`<Feature>_View`** — granted by every permset tier that should see the feature (including read-only tiers).
- **`<Feature>_Power_User`** — granted by Power User + Admin tiers only. Gates write / action elements.

Marketing Influence example:

- [`Marketing_Influence_View.customPermission-meta.xml`](../../force-app/main/default/customPermissions/Marketing_Influence_View.customPermission-meta.xml)
- [`Marketing_Influence_Power_User.customPermission-meta.xml`](../../force-app/main/default/customPermissions/Marketing_Influence_Power_User.customPermission-meta.xml)

Granted by the MI permset tier ladder — see [`docs/runbooks/mi-go-live.md`](../runbooks/mi-go-live.md) for the assignment table.

### Step 2 — Import the perms into the LWC

Use the `@salesforce/customPermission/<DeveloperName>` scoped import. It resolves to `true` when the running user holds the perm, and `undefined` otherwise.

```js
import hasViewPerm from "@salesforce/customPermission/Marketing_Influence_View";
import hasPowerUserPerm from "@salesforce/customPermission/Marketing_Influence_Power_User";

get canViewPanel() {
  return hasViewPerm === true;
}

get canActOnPanel() {
  return hasPowerUserPerm === true;
}
```

**Use `=== true` strict equality.** The import is `undefined` when the perm isn't granted, and in unmocked jest runs the import is also `undefined`. A loose `!!hasViewPerm` works in production but breaks down in tests where you mock one perm but forget the other — strict equality forces every test to declare its perm posture explicitly.

Live source: [`engagementPanel.js` lines 33–34, 113–119](../../force-app/main/default/lwc/engagementPanel/engagementPanel.js).

### Step 3 — Gate the template

Wrap the entire visible surface in `canViewPanel`. Wrap action elements (buttons, link triggers) in `canActOnPanel`:

```html
<template>
  <template lwc:if="{canViewPanel}">
    <article class="slds-card">
      <!-- header + read-only data: always visible to View tier -->
      <template lwc:if="{canActOnPanel}">
        <!-- View all, Add to Deal Team, Dismiss live in here -->
      </template>
    </article>
  </template>
</template>
```

Live source: [`engagementPanel.html` lines 2, 33, 155, 234, 336](../../force-app/main/default/lwc/engagementPanel/engagementPanel.html).

What View-tier users see in the panel: contact rows, avatars, touch counts, topic chips, last-touch relative timestamps, and the on-team badge. What they don't see: the **View all** header button, per-row **+ Add** buttons, and the **Dismiss** `×` icon. Same data shape, no actionable affordances.

### Step 4 — Gate the FlexiPage placement

For every placement of the LWC on a Lightning Record Page, add a `visibilityRule` to the `<componentInstance>`:

```xml
<componentInstance>
    <componentInstanceProperties>
        <name>recordContext</name>
        <value>Account</value>
    </componentInstanceProperties>
    <componentName>c:engagementPanel</componentName>
    <identifier>c_engagementPanel</identifier>
    <visibilityRule>
        <criteria>
            <leftValue
      >{!$Permission.CustomPermission.Marketing_Influence_View}</leftValue>
            <operator>EQUAL</operator>
            <rightValue>true</rightValue>
        </criteria>
    </visibilityRule>
</componentInstance>
```

**The `$Permission.CustomPermission.<DeveloperName>` form is FlexiPage-specific.** Bare `$Permission.<DeveloperName>` works in Visualforce and Flow formula expressions but is silently rejected by FlexiPage Component Visibility — the deploy passes and the rule never evaluates. Atlas debugged this the hard way during MI deploy validation; if you see "component always visible regardless of permset" check the formula prefix first.

Live source — the five FlexiPages currently carrying `c:engagementPanel`:

- [`Opportunity_Engagement_Record_Page.flexipage-meta.xml`](../../force-app/main/default/flexipages/Opportunity_Engagement_Record_Page.flexipage-meta.xml) — MI-owned
- [`Account_Engagement_Record_Page.flexipage-meta.xml`](../../force-app/main/default/flexipages/Account_Engagement_Record_Page.flexipage-meta.xml) — MI-owned
- [`Account_Record_Page_Provider.flexipage-meta.xml`](../../force-app/main/default/flexipages/Account_Record_Page_Provider.flexipage-meta.xml) — Zelis-owned, contributed additively
- [`PE_Payer_Record_Page.flexipage-meta.xml`](../../force-app/main/default/flexipages/PE_Payer_Record_Page.flexipage-meta.xml) — Zelis-owned, contributed additively
- [`PE_Provider_Account_Record_Page.flexipage-meta.xml`](../../force-app/main/default/flexipages/PE_Provider_Account_Record_Page.flexipage-meta.xml) — Zelis-owned, contributed additively

The 3 Zelis-owned pages are noted in [`docs/runbooks/mi-go-live.md`](../runbooks/mi-go-live.md) as MI's additive contribution. Future edits to those pages need to preserve our `componentInstance` block or the panel disappears from those record pages.

### Step 5 — Mock both perms in every Jest test file

`@salesforce/customPermission/<name>` is a virtual module that resolves at module load. You can't toggle it mid-suite. Mock it at the top of every test file, for both perms, with explicit values:

```js
jest.mock(
  "@salesforce/customPermission/Marketing_Influence_View",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Marketing_Influence_Power_User",
  () => ({ default: true }),
  { virtual: true }
);
```

For multi-tier coverage, **one test file per perm combination**. `jest.isolateModules` doesn't help — re-importing the LWC collides with LWC Jest's process-global custom-element registry. Cleaner to split files.

The engagementPanel suite ships three files:

| File                                                                                                                                | View  | Power User | Asserts                                                          |
| ----------------------------------------------------------------------------------------------------------------------------------- | ----- | ---------- | ---------------------------------------------------------------- |
| [`engagementPanel.test.js`](../../force-app/main/default/lwc/engagementPanel/__tests__/engagementPanel.test.js)                     | true  | true       | Full Power-User render — every action button present + wired.    |
| [`engagementPanel.perm-view.test.js`](../../force-app/main/default/lwc/engagementPanel/__tests__/engagementPanel.perm-view.test.js) | true  | false      | Read-only render — rows + chips present, action buttons absent.  |
| [`engagementPanel.perm-none.test.js`](../../force-app/main/default/lwc/engagementPanel/__tests__/engagementPanel.perm-none.test.js) | false | false      | Outer `lwc:if` blocks the entire `<article>` — nothing rendered. |

This is the canonical persona-path coverage shape for a permset-gated LWC: good-path AND bad-path for every tier that touches the component.

## Visibility matrix

What each user tier sees on a record page that carries `c:engagementPanel`:

| User tier                                | FlexiPage renders panel? | Outer `lwc:if` allows render? | Action buttons visible? | Net result                                       |
| ---------------------------------------- | ------------------------ | ----------------------------- | ----------------------- | ------------------------------------------------ |
| No MI permset                            | no                       | n/a                           | n/a                     | Panel absent from page entirely.                 |
| `Permset_Marketing_Influence_View`       | yes                      | yes                           | no                      | Read-only panel — contact rows + chips + badges. |
| `Permset_Marketing_Influence_Power_User` | yes                      | yes                           | yes                     | Full panel — View all, + Add, Dismiss available. |
| `Permset_Marketing_Influence_Admin`      | yes                      | yes                           | yes                     | Same as Power User.                              |

Tier assignment via Persona PSGs is in [`docs/runbooks/mi-go-live.md`](../runbooks/mi-go-live.md).

## Common mistakes

1. **Bare `$Permission.<name>` in the FlexiPage formula.** Silently rejected. Use `$Permission.CustomPermission.<DeveloperName>`.
2. **`!!hasViewPerm` instead of `hasViewPerm === true`.** Works in production, hides test mistakes where a sibling perm is unmocked and resolves to `undefined`.
3. **Skipping the outer `lwc:if`.** Defense-in-depth matters when a deploy edits FlexiPage XML without re-validating the visibility rule.
4. **Only mocking the View perm in tests.** Power-User-gated DOM queries silently return `null` and tests pass by mistake. Mock both perms, always.
5. **One test file with `jest.resetModules`.** Doesn't work with LWC's custom-element registry. One file per perm combination.

## Related

- [`feedback_owd_private_permset_architecture`](../../) — architectural source for the OWD-Private permset ladder.
- [`lwc-conventions.md`](./lwc-conventions.md) — broader LWC conventions on this codebase.
- [`components/engagementPanel.md`](./components/engagementPanel.md) — the worked example.
- [`docs/runbooks/mi-go-live.md`](../runbooks/mi-go-live.md) — permset assignment tables + Zelis FlexiPage contribution notes.

---

_Maintained by Lyric Astro. Source of truth: live FlexiPage XML, LWC JS, and Jest specs in this repo. Update this file when the pattern changes — not when a single feature changes._
