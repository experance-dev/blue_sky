# Engagement Detail Modal — Future Enhancements

**Author:** Nova Astro
**Date:** 2026-05-16
**Status:** Backlog — destination Jira/Confluence (David to load)
**Parent feature:** Marketing Influence / Engagement Detail Modal ([engagement-timeline.md](design-spec.md))

A consolidated list of features and refinements deliberately deferred from the initial B5 scope. Some came up during design conversation, some I had instinct on while building. All are sized so they can be promoted to standalone Jira epics / stories when business priority justifies them.

Each item has: **What** · **Why** · **Sketch of how** · **Effort hint** · **Status / origin.**

---

## Tier 1 — High-value, low-friction (do next quarter)

### F1. Outcome-correlation overlay

**What:** Vertical accent lines on the Gantt at the exact moments the parent Opportunity changed stage (Discovery → Proposal → Negotiation → Closed Won). Each labeled.

**Why:** Directly answers "did marketing influence the deal?" The reader sees the touches in the 2-week window preceding a stage advance and connects cause-effect. Single biggest "show ROI" addition we can make.

**Sketch:** Apex pulls `OpportunityHistory` records inside the same window; LWC overlays them as dotted vertical lines with stage-name labels above the Gantt. Click a line → drill into that history record.

**Effort:** ~3 days Apex + LWC. Low security surface.

**Origin:** Nova proposal during interactive-features discussion (2026-05-16).

### F2. AI engagement narrative ("📖 Story" button)

**What:** Small button at top of modal → opens a popover with a 2-line LLM-generated summary: _"Acme Health's engagement started with Sarah's Spring Webinar registration on Apr 14, accelerated when Riya pulled the Denials Whitepaper Apr 30, and is now Mike-driven around AI Imaging."_

**Why:** Calling-card "wow" moment. Sales rep walks into the call already armed with the buying-story narrative without reading the chart.

**Sketch:** Lightning/Einstein GPT prompt OR Anthropic API via a callout. Prompt: structured JSON of the engagement events → 2-line narrative + 1-line "what's next" suggestion. Caches per-account-per-day to limit API spend.

**Effort:** ~5 days including provider selection, prompt engineering, caching, and a "regenerate" affordance. Sage review for data going to external LLM.

**Origin:** Nova proposal (2026-05-16). David flagged as "calling card wow" tier.

### F3. Future-engagement ghost dots (`+ Future` scale)

**What:** Scheduled-but-not-yet-happened touches (webinar registrations, calendar invites, queued nurture emails) rendered to the right of "Today" on the time axis as dashed-outline / semi-transparent dots.

**Why:** Sales rep sees "Riya is registered for next Tuesday's executive briefing" as a future ghost dot — proactive context, not just historical. Pairs with the `+ Future` scale option already in B5.

**Sketch:** New `Future_Touch__c` (or `Scheduled_Event__c`) source; same DTO contract; dot styling adds `is-future` class. Tooltip explains.

**Effort:** ~3 days. Need to confirm with Iris which "scheduled future" data sources exist (Marketo nurture queue? Salesforce calendar?).

**Origin:** David proposed during scale-control discussion. Listed under `+ Future` button.

### F4. Density toggle (zoom-out collapses to heatmap cells)

**What:** When the user zooms to 1y or wider, individual dots become hard to read. Auto-collapse to weekly heatmap cells (one cell per week per contact, intensity = touch count that week).

**Why:** Same data viz at three zoom levels: individual touches up close, day-aggregated medium, weekly-heatmap far. Lossless across scales.

**Sketch:** `if (scale.windowDays > 90) renderHeatmapCells else renderDots`. Cell color = predominant campaign for the week; intensity = count. Click a cell → drill back to the dot view for that week.

**Effort:** ~4 days. Mostly LWC; no schema change.

**Origin:** Nova proposal during interactive features.

---

## Tier 2 — Persona / accessibility / collaboration

### F5. Marketing User read-only persona variant

**What:** When viewed by a user with `Marketing_Influence_Read_Only` custom permission, hide all edit affordances (no Add-to-Deal-Team, no Edit-Role, no Dismiss). Default group-by switches to "Campaign" instead of "Person."

**Why:** Marketing stakeholder uses the same modal to verify campaign reach. They shouldn't see edit buttons that won't work for them.

**Sketch:** Component Visibility rules + Apex permission checks. Toggle scope-default per custom-perm. Bonus: a small "Read-only view" indicator at top.

**Effort:** ~1 day. Permset work + LWC conditional rendering.

**Origin:** Nova flagged during OWD-Private permset planning. Tied to existing permset architecture.

### F6. Multi-contact compare mode (Shift-click)

**What:** Shift-click two contact lanes → both stay highlighted while all others dim. Tap a third → cycles oldest selection out.

**Why:** "Do Sarah and Mike engage with the same campaigns?" reads cleanly when two lanes are pinned vs trying to remember.

**Sketch:** Selection state goes from single ID to `Set<Id>` (max 4). Visual: each pinned contact gets a numbered chip "1 / 2 / 3" so you can tell them apart.

**Effort:** ~2 days. Pure LWC state.

**Origin:** Nova proposal.

### F7. Pin-contact-to-top (sticky favorites)

**What:** Pin a contact's lane to always appear at the top of the Gantt for this user. Persists across sessions.

**Why:** Account exec mentally has 1-2 "anchor" contacts they always check. Make that surfaceable, not just memory.

**Sketch:** `Engagement_Pinned__c` junction object keyed on User + Contact. Selector + UI.

**Effort:** ~2 days.

**Origin:** Nova proposal.

### F8. Onboarding coachmarks (first-use)

**What:** First time a user opens the modal, show 3-4 coachmark callouts explaining the Gantt, the campaign cards, the scope toggle. Dismissable.

**Why:** The viz is novel. Without orientation, sales reps may not get the first-touch / last-touch lifeline idea.

**Sketch:** Lightning Walkthroughs API OR a homegrown coachmark component with localStorage "seen" flag.

**Effort:** ~2 days.

**Origin:** Nova proposal (best practice).

---

## Tier 3 — Operational + analytics

### F9. Drag-to-zoom time window

**What:** Click-drag a horizontal selection across the time axis → zoom the Gantt to that range. Pinch-to-zoom on touch devices.

**Why:** Faster than clicking scale buttons when the user wants "the 3 weeks around the proposal stage change."

**Sketch:** Mouse-down on time-axis sets start; mouse-up sets end; updates scale state.

**Effort:** ~2 days.

**Origin:** Nova proposal.

### F10. Export current view

**What:** Top-right action: "Export → PNG / CSV / PDF". Captures current filter state + selected contact + scope.

**Why:** Analyst workflows. Pasting into a QBR deck without rebuilding.

**Sketch:** PNG via `html2canvas` or server-side render. CSV via DTO → flat rows. PDF via headless Chrome (Apex callout to a render service, OR client-side print-stylesheet).

**Effort:** ~3 days; the PDF render is the long pole.

**Origin:** Nova proposal.

### F11. Send-to-Marketing-Cloud quick action

**What:** Select contacts in the bottom Deal Team Gap card → "Send to Marketing Cloud journey…" → choose a journey → bulk-enroll.

**Why:** Closes the loop. Rep notices the gap, fills it via campaign, all from one modal.

**Sketch:** Quick action button → modal with journey picker (lazy-loaded from MC). POST to MC REST API on submit. Audit log entry.

**Effort:** ~5 days. Cross-cloud auth + audit trail. Sage review.

**Origin:** Nova proposal.

### F12. Filter chips by activity type (email/event/task/web)

**What:** Above the Gantt: small chip row "📧 Email · 🎤 Event · ✅ Task · 🌐 Web". Click to filter the Gantt to only that type. Stacks with campaign filter.

**Why:** "Show me only the in-person event touches" is a common question that's hard to answer from the visualization today.

**Sketch:** Multi-select chips. Touch dots have a `data-type` attribute; CSS dims non-matching when filter is on.

**Effort:** ~1 day.

**Origin:** Marketo MSI parity ([Marketo Sales Insight](https://experienceleague.adobe.com/en/docs/marketo/using/product-docs/marketo-sales-insight/msi-for-salesforce/features/insights-dashboard-feature-overview) has this).

### F13. Engagement score sparkline per contact

**What:** Inside the contact lane label, a small sparkline (last 6 weeks of daily engagement score) next to the count badge.

**Why:** Trend at a glance: "Sarah's score is climbing; Alex's is flat-lining."

**Sketch:** New `Engagement_Score_Daily__c` (or rollup from existing touches). Lightning charting kit or inline SVG sparkline.

**Effort:** ~3 days.

**Origin:** Nova proposal.

---

## Tier 4 — Speculative / requires research

### F14. Predictive next-best-action

**What:** "Riya's engagement pattern suggests she's ready for a demo invite" prompt next to the contact, based on a model trained on prior engagement → opp-progression correlation.

**Why:** Predictive guidance becomes the calling-card upgrade. Aspirational.

**Sketch:** Einstein Discovery model OR Anthropic prompt OR rule engine. Needs Iris on whether this is in-scope for MI or belongs to a different team.

**Effort:** Unknown. Multi-sprint. Needs data-science partnership.

**Origin:** Nova proposal.

### F15. Cross-account contact roll-up (Account Contact Relations)

**What:** When a contact at one account has an Account Contact Relation to a sibling account, the modal shows their cross-account engagement, not just the primary account's.

**Why:** Modern enterprise account contacts often work across multiple subsidiaries. Treating each Contact↔Account relationship independently misses pattern.

**Sketch:** Query `AccountContactRelation` in addition to direct Contact.AccountId. Lane label badges "Also at: Acme Imaging" when the contact spans accounts.

**Effort:** ~3 days, but complicates Hierarchy brief — best deferred until Hierarchy ships.

**Origin:** Nova realized during hierarchy brief writing.

### F16. Marketing-influence attribution percentage

**What:** Per Opportunity, show "Marketing influenced 64% of this deal's pipeline movement" — a derived stat from the touches × stage-change correlations.

**Why:** Direct answer to the CFO question "did marketing matter?" Pairs with F1 (outcome correlation).

**Sketch:** Apex roll-up calculating attribution weights using a configurable model (first-touch / last-touch / linear / W-shaped / etc.). Configurable via CMDT. Display in modal header + on Opp record page.

**Effort:** ~7 days. Math + configurability + multi-touch attribution model. Sage on PII.

**Origin:** Calling-card stakeholder request anticipated.

---

## Tier 5 — Documentation / dev experience

### F17. Storybook for the modal LWC

**What:** Set up Storybook (or LWR equivalent) for the Engagement Detail Modal + its child components, with stories for each state (loaded / empty / loading / error / hierarchy-on / IM-filter-on, etc.).

**Why:** Coda + Kit + Robin can iterate visually without going through scratch-org deploys. Designers (Nova) can review without Salesforce login.

**Sketch:** Storybook config in the repo OR a static-site renderer; each state from the wireframes folder becomes a story.

**Effort:** ~3 days setup + ongoing maintenance.

**Origin:** Nova thinking about how to maintain design / dev parity long-term.

### F18. Visual-regression CI

**What:** Playwright + percy.io (or homegrown) snapshot diff on PR. Catch unintended visual changes before merge.

**Why:** Calling-card design quality drifts without active maintenance. CI catches it.

**Sketch:** Per-PR: render the 5 state HTMLs to PNG → diff against baseline → flag changes for review.

**Effort:** ~2 days setup. Ongoing baseline maintenance.

**Origin:** Nova proposal.

---

## How to use this list

When Atlas / Iris are scoping the next phase:

1. **Tier 1** items are the highest expected-value-per-effort. They're the next-quarter candidates.
2. **Tier 2** depends on persona feedback from the first calling-card demo. Wait for that to inform priority.
3. **Tier 3 / 4** are platform-level investments — pair them with the team's broader roadmap, not just MI.
4. **Tier 5** is dev-experience — quarter-it whenever Atlas / Pippa flag they're spending too long on visual review cycles.

Each tier can be its own Jira epic. Each item should turn into one or more stories with the same fields the briefs use (Context · Scope in/out · Open questions · Schema / arch · Security · UI · Effort · Definition of Done).

— Nova
