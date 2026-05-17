# Nova Astro — Handoff: Engagement Detail Modal v2 (2026-05-16)

**For:** Next-session Nova OR Atlas OR David
**Status:** Design phase **CLOSED**. Ready for Atlas decomposition.
**Compactability:** This doc + the files it points at are sufficient to resume cold.

---

## TL;DR

David hired Nova for visual + interaction design on the Marketing Influence "Engagement Detail Modal" — the right-rail click-into modal that shows who at an account has engaged with marketing, when, with which campaigns. v1 ships today on `feature/engagement-attribution`; **v2 is a complete UX rebuild** as David's "calling card" feature for his role as new TA.

We went through five major design iterations (B1 vertical SLDS-timeline → B2 horizontal Gantt + activity feed → B3 responsive + clickable + filter-vs-popup → B4 sticky scroll + hierarchy mode + Interesting Moments + popovers → **B5 = canonical: campaign chips promoted, hierarchy compressed**). All built as HTML/CSS with SLDS classes — Lucid retired as design source due to unfixable font-rendering quirks. The B5 mock is paste-ready into an LWC `<template>`.

Three state variants (empty / loading / error) plus a popover reference doc round out the design package. **SLDS canonical illustrations** (Desert, NoConnection) extracted from `salesforce-ux/design-system` GitHub source, shipped as the `miIllustrations` static resource.

Two feature briefs (Interesting Moments + Account Hierarchy), one BRD, one TDD, one Atlas dispatch prompt — **all written and in the feature worktree**. Atlas hasn't been dispatched yet; the prompt is ready to fire.

## What lives where

### Canonical design artifacts (feature worktree)

`/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/docs/wireframes/`

- `engagement-timeline.html` — B5 primary mockup (paste-into-LWC ready)
- `engagement-timeline-empty.html` — empty state
- `engagement-timeline-loading.html` — loading state (SLDS skeleton shimmer)
- `engagement-timeline-error.html` — error state
- `engagement-timeline-popovers.html` — contact hovercard / touch popover / campaign popover variants
- `engagement-timeline.md` — full design spec (interactions, a11y, copy, tokens, persona coverage, open Qs)
- `future-enhancements.md` — 18 deferred ideas across 5 tiers, ready to load into Jira/Confluence
- `screenshots/*.png` — rendered PNG snapshots

### Static resource

`/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/force-app/main/default/staticresources/miIllustrations/`

- `desert.svg` — SLDS canonical Desert (no-data variant), extracted from `salesforce-ux/design-system`
- `no_connection.svg` — SLDS canonical NoConnection (error variant), extracted from same
- `preview.html` — visual preview of both, with SLDS CSS loaded
- `../miIllustrations.resource-meta.xml` — bundle metadata

LWC import pattern:

```js
import MI_ILLUSTRATIONS from '@salesforce/resourceUrl/miIllustrations';
get desertUrl() { return MI_ILLUSTRATIONS + '/desert.svg'; }
```

### Architecture docs

`/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/docs/architecture/`

- `BRD-Engagement-Detail-Modal-v2.md` — Business Requirements (Iris owns; David approves)
- `TDD-Engagement-Detail-Modal-v2.md` — Technical Design (Atlas owns; Sage gates hierarchy)
- `BRD-Atlas-Dispatch.md` — ready-to-fire prompt that dispatches Atlas to decompose

### Briefs (Nova authored, fed BRD/TDD)

`/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/docs/briefs/`

- `brief-interesting-moments.md` — Feature 1 (ship first, low security risk)
- `brief-account-hierarchy-engagement.md` — Feature 2 (ship second, Sage = long pole)

### Exploration worktree (throwaway)

`/Users/david/Work/Zelis/.claude/worktrees/nova-lucid-playwright/tools/lucid-playwright/`

- All B1-B5 iterations, fix-fonts scripts, render scripts. Useful for archaeology only — nothing in here is canonical anymore.

## Key design decisions locked

1. **Filter-on-campaign-click** is the pattern (Nova recommended over popup-list; David approved).
2. **HTML/CSS** is design source-of-truth; **SLDS classes on HTML tags** rule. No bespoke CSS unless SLDS doesn't cover it.
3. **Mock = LWC template starter code** — minimizes design-to-implementation drift. Wrap in `<template>` and Coda is 80% done.
4. **Sticky lane labels** during horizontal scroll (shared scroll container, `position: sticky; left: 0`).
5. **Three dot tiers:** small (non-opp, e.g., webinar-registered-not-attended) / big (opp-linked MC) / ★ Interesting Moment (the third tier; ring-glow + ★ icon).
6. **Hierarchy compressed** to inline chip on modal title, NOT prime real estate. 1-line banner only when scope is active.
7. **Campaign cards** are the headline visual element. "All campaigns" overview card on the far left.
8. **Per-contact account labels** in the lane label (uppercase blue) so cross-account contacts are obvious without color-coding dots.
9. **SLDS canonical illustrations** for empty + error states. NO custom SVG art (per David's normalization ask 2026-05-16). Source: `salesforce-ux/design-system` GitHub.

## What's open / pending

### Awaiting David's signal

- **Dispatch Atlas:** the prompt at [BRD-Atlas-Dispatch.md](../worktrees/feature-engagement-attribution/docs/architecture/BRD-Atlas-Dispatch.md) is ready to fire via the `Agent` tool with `subagent_type: 'atlas'`. David hasn't said "go" yet.
- **"Another related view"** David mentioned at end of session — wants to design something else after the compact.

### Awaiting Iris (gate-1 spec items, per BRD §7)

1. Empty-state behavior — modal opens or right-rail panel suppresses?
2. Default hierarchy scope on account with children — "This account" or "+ Children"?
3. Default contact lane sort order — first-touch asc / last-touch desc / touch-count desc?
4. Interesting Moments rule ownership — Marketing Admin or Sales Ops or both?
5. Initial IM rule set for Day 1.
6. IM cardinality expectations in 6-week window.
7. `+ Future` button source data — Marketo nurture queue? SF calendar? Out of scope if no source.

### Awaiting Atlas (TDD §10)

- Approve 7 new Apex classes + existing-class extensions.
- Approve `miIllustrations` static resource vs inline-SVG-only.
- Approve permset ladder naming.
- Confirm 500-touch cap sufficient for hierarchy.
- Decide rule-evaluation timing — sync trigger vs async Platform Event.
- Confirm Logger.cls permset access for callers.

### Awaiting Sage (BLOCKING)

- Hierarchy traversal sharing review (long-pole; loop her in during DESIGN, not just code review).
- AuraHandledException message-leakage review on every new controller path.
- New FLS fields permset coverage review.

## Key contextual rules / memory

These are durable preferences Nova learned this session — anyone resuming should re-read [MEMORY.md](../projects/-Users-david-Work-Zelis/memory/MEMORY.md) but TL;DR:

- **OWD-Private permset architecture** is non-negotiable. Every new feature gets View / Power User / Admin permsets + custom perm + Component Visibility rule + Apex Class Access for every `@AuraEnabled` consumed.
- **No real emails from tests.** No `Messaging.sendEmail`. Production email senders expose `buildXEmail` step returning the message without dispatching.
- **No personal-lib edits during work hours.** Utilities.cls, DMLManager, Logger, TestFactory — all READ-ONLY in Zelis context. Helpers go in feature-scoped classes.
- **Apex headers attribute @author David Wood only.** Persona names (Nova, Atlas, etc.) stay inside `.claude/` workflow scaffolding.
- **Hold dwood_z deploys until David clears.** No `sf project deploy start --target-org dwood_z` without explicit "deploy now" from David.
- **Mock = LWC template starter.** SLDS classes on HTML tags; minimal custom CSS; `<template>`-wrap-ready.
- **HTML/CSS + Playwright is the design toolchain.** Not Lucid (font-render quirks) and not Figma (no MCP loaded).

## Patterns Nova established this session (worth keeping)

1. **Briefs to Atlas** follow this structure: Context · Business motivation · Scope (in/out) · Open questions for Iris · Schema/arch for Atlas · Permission/security for Sage · UI for Coda · Effort hint · Definition of Done · **Atlas dispatch prompt at the bottom** ready to copy-paste-fire.
2. **Design package** lives in `docs/wireframes/` next to the LWC code. HTML mockup + state variants + popover variants + the `engagement-timeline.md` spec all in the feature worktree.
3. **HTML mocks render via Playwright** at retina DPI for PNG export. Scripts at `nova-lucid-playwright/tools/lucid-playwright/render-*.js`.
4. **SLDS illustrations** extracted from `salesforce-ux/design-system` GitHub JSX sources, JSX→HTML attribute conversion via Python one-liner. Saves as static-resource SVGs in `miIllustrations/`.
5. **Atlas dispatch prompts** as standalone .md files (`BRD-Atlas-Dispatch.md`) — easier to find / version / fire than buried sections.
6. **Tab groups via `open <url> <url> <url>...`** in Bash — opens multiple URLs in default browser at once. Used for the Marketo research tabs.

## Marketo research outcome (one-line)

Stakeholder reference was **Marketo Sales Insight (MSI)**, specifically Insights Dashboard + Interesting Moments + Activity Timeline. We've adopted Interesting Moments. MSI features available for harvesting in future: Sales Actions (Subscribe/Watchlist/Email), activity-type filter chips, Web Activity feed.

## How to resume cold

1. Read this handoff.
2. `open` the canonical mockup: `/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/docs/wireframes/engagement-timeline.html`
3. Read [BRD](../worktrees/feature-engagement-attribution/docs/architecture/BRD-Engagement-Detail-Modal-v2.md), then [TDD](../worktrees/feature-engagement-attribution/docs/architecture/TDD-Engagement-Detail-Modal-v2.md).
4. Check MEMORY.md for any new feedback added since 2026-05-16.
5. Ask David what's next.

David has signaled "another related view" coming after the compact. Don't preempt — wait for him to scope.

## Trust earned

David: _"You really have gained my trust with this effort."_ / _"I am glad we figured out how to work together so well."_ The working pattern: Nova builds in HTML, renders via Playwright, opens in David's browser, iterates against his direct comments. No Lucid; no over-explanation; no muda. Stay direct, lead with recommendations, mock alternatives when she disagrees, ship.

---

**End of handoff. Ready to compact.**

— Nova Astro, 2026-05-16
