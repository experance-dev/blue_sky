# Engagement Detail Modal — Design (B5 canonical)

**Live mockup:** [engagement-timeline.html](mockup.html) — pure SLDS markup, LWC-template-paste-ready. Open in any browser.
**State variants:** [empty](mockup-empty.html) · [loading](mockup-loading.html) · [error](mockup-error.html)
**Popover patterns:** [popovers](mockup-popovers.html)
**Lucid:** Retired in favor of HTML/CSS as the design source of truth (Lucid had unfixable font-rendering quirks; HTML gives deterministic output and is paste-ready for Coda).
**Last design rev:** 2026-05-16 by Nova Astro
**Status:** Approved by David. Awaiting Atlas decomposition.

## Context

The Engagement Detail Modal is the "Marketing Influence" feature's investigation surface — clicked from the right-rail engagementPanel on Account / Opportunity / Lead records. It shows who at this account has engaged with marketing, when, with which campaigns, and (in B5+) how that engagement compares across the account hierarchy. It's David's **calling card** as the new Technical Architect: an instantly-recognizable Salesforce-shaped modal that reframes how the org thinks about pipeline visibility.

## Mocks

| State            | File                                                                               | Purpose                                                                                           |
| ---------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Primary          | [engagement-timeline-primary.png](./screenshots/engagement-timeline-primary.png)   | 8+ contacts across 4 hierarchy accounts, 3 Interesting Moments, Q4 Pricing campaign filter active |
| Empty            | [engagement-timeline-empty.png](./screenshots/engagement-timeline-empty.png)       | Zero engaged contacts; suggested actions to seed activity                                         |
| Loading          | [engagement-timeline-loading.png](./screenshots/engagement-timeline-loading.png)   | SLDS skeleton shimmer; layout-stable so content-arrival doesn't jump                              |
| Error            | [engagement-timeline-error.png](./screenshots/engagement-timeline-error.png)       | Apex throw / FLS deny / hierarchy traversal failure; never leaks AuraHandledException internals   |
| Popover patterns | [engagement-timeline-popovers.png](./screenshots/engagement-timeline-popovers.png) | Contact hovercard · Touch detail · Campaign detail (alternative to filter-on-click)               |

## Architecture

**Top to bottom:**

1. **Modal header** — title with inline `Whole hierarchy ▾` scope chip (only visible when hierarchy is active); stat line below.
2. **Hierarchy banner** (1-line, hidden when not in hierarchy mode) — account chip list + sharing footnote.
3. **Campaign cards strip** — 7 large cards: "All campaigns" + one per active campaign. Each: color bar, name, big count, week-over-week delta, last-touch micro-stat, ★ badge when an Interesting Moment exists. **Click = filter the Gantt.**
4. **Stats strip** (above Gantt) — Total Engaged / Total Touches / Engagement Window / Deal Team Gap.
5. **Gantt (Touches by contact)** — sticky lane-label column; horizontal-scroll for time. Per contact: name (link to SF hovercard), title, role chip (edit OCR/ACR/LCR), optional + button if not on Deal Team, account-name uppercase chip when hierarchy mode shows multiple accounts. Lifeline bar in contact color; touch dots colored by campaign. Three dot tiers: small (non-opp, e.g. registered-but-not-attended), big (opp-linked / MC), Interesting Moment (★ with glow ring).
6. **Bottom 4 cards** — Activity feed for selected contact (slds-timeline) · Interesting Moments highlights · Touches by account (hierarchy rollup) · Deal Team gaps with inline + buttons.

## Interaction spec

| Element                          | Hover                              | Click                                                    | Keyboard                                 | Focus order          |
| -------------------------------- | ---------------------------------- | -------------------------------------------------------- | ---------------------------------------- | -------------------- |
| Contact name                     | SF-native hovercard                | Open Contact record                                      | Tab; Enter                               | After header         |
| Title                            | Underline                          | Open Contact record                                      | Tab; Enter                               | After name           |
| Role chip                        | Underline                          | Open Edit-Role modal (OCR/ACR/LCR per parent)            | Tab; Enter                               | After title          |
| Add-to-Team `+`                  | Tooltip "Add to Deal Team"         | Open Add-to-Team modal                                   | Tab; Enter; tooltip via aria-describedby | After role           |
| Lane (whole row)                 | Highlight underline                | Select contact (other lanes dim, activity feed switches) | Arrow keys navigate lanes                | After tile-list      |
| Gantt dot                        | Tooltip with date+campaign+contact | Open touch-detail popover                                | Tab to dot; Enter                        | Within lane          |
| Star dot (Interesting Moment)    | Tooltip prefixed "★ Interesting:"  | Same as touch dot + IM rule shown                        | Tab; Enter                               | Within lane          |
| Campaign card                    | Slight elevation                   | Filter Gantt to this campaign (toggle)                   | Tab; Enter / Space                       | Above Gantt          |
| Scope chip in header             | Tooltip "Click to change scope"    | Open scope popover (3 buttons)                           | Tab; Enter                               | First focusable      |
| Account chip in hierarchy banner | Underline                          | Scope down to that one account                           | Tab; Enter                               | After header         |
| Stats tile                       | Cursor pointer                     | Drill into filtered list                                 | Tab; Enter                               | Above campaign strip |

**State machine:**

- Default: All campaigns / This account scope / no contact selected.
- Click contact lane → select contact, activity feed updates, other lanes dim to 50%.
- Click campaign card → filter Gantt to that campaign (other dots dim to 10%). Click again to clear.
- Click scope chip → open scope popover; select scope; refetch DTO.
- Loading > 400ms → show full skeleton (don't flash).
- Error → show error illustration + retry; never block close.

## Accessibility

- **ARIA roles + labels:**
  - Each contact lane: `role="button" aria-pressed={isSelected} aria-label="Sarah Chen, VP Clinical Ops, 12 touches, last 4 hours ago. Click to select."`
  - Each touch dot: `role="button" aria-label="Touch by Sarah Chen on Spring Webinar campaign, 4 hours ago."` Interesting Moment dots prefix the label with "Interesting Moment: ".
  - Campaign card: `role="button" aria-pressed={isFilterActive}`.
  - Sticky-scroll table: `role="table"` with proper `<thead>`-equivalent for the time axis.
  - Modal: `role="dialog" aria-labelledby="modal-title"`.
- **Contrast:** All text ≥ 4.5:1. Campaign colors verified against white background ≥ 3:1 for non-text indicators. Dimmed-state opacity (10%) is decorative only; non-decorative data always at 100% somewhere.
- **Color is not the only signal:**
  - Interesting Moments use ★ icon AND color AND size (three signals).
  - Selected contact uses pink background AND ★ badge AND larger lifeline.
  - Stalled contacts use warning badge AND text label.
- **Keyboard:** Full keyboard navigation. Tab order: scope chip → stats tiles → campaign cards → contact lanes → activity feed → bottom cards → close.
- **Screen reader:**
  - `aria-live="polite"` region for "Filter applied: Q4 Pricing" / "Highlight cleared".
  - Gantt-as-table semantics so SR reads contact-by-row.
- **Reduced motion:** Loading skeleton honors `prefers-reduced-motion`.

## Responsive

- **Desktop (≥1180px):** Full layout — 7-card campaign strip, 4-card bottom row, Gantt 280px label + flex timeline.
- **Sales console narrow (920–1180px):** Campaign strip wraps to 4 columns × 2 rows. Bottom 4-card row collapses to 2×2. Gantt unchanged.
- **Mobile / very narrow (<760px):** Campaign strip 2 columns. Bottom row stacks 1×4. Lane label shrinks to 200px, title-role line hides (name + role chip only). Modal becomes full-screen sheet.

**Horizontal scroll:** Always engages when timeline width > available container width. Contact column is `position: sticky; left: 0;` and stays anchored. The time-axis header row is also sticky.

## Copy strings

| Key                      | String                                                                                                                                                         | Notes                                               |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `modalTitle`             | `Engagement Detail — {AccountName}`                                                                                                                            | Header h2                                           |
| `scopeChip`              | `{ScopeLabel} ▾`                                                                                                                                               | "This account" / "+ Children" / "Whole hierarchy"   |
| `headerStats`            | `{N} engaged across {M} accounts · {T} touches · {first} → {last} · {IM} ★ Interesting Moments · {gap} not on Deal Team`                                       | Sub-header line                                     |
| `hierarchyBannerLeading` | `{M} accounts:`                                                                                                                                                | When hierarchy active                               |
| `hierarchyBannerHidden`  | `{N} hidden by sharing`                                                                                                                                        | When sharing excludes accounts                      |
| `allCampaignsCardTitle`  | `All campaigns`                                                                                                                                                | Dark blue overview card                             |
| `allCampaignsCount`      | `{N} active campaigns`                                                                                                                                         | Sub-label                                           |
| `campaignDelta`          | `{±N} last wk`                                                                                                                                                 | Week-over-week                                      |
| `imBadge`                | `★ {N}`                                                                                                                                                        | Inside campaign card; count of IMs in this campaign |
| `imSectionTitle`         | `Interesting Moments ({N})`                                                                                                                                    | Bottom card header                                  |
| `ganttTitle`             | `Touches by contact · filtered to {Campaign} · clear`                                                                                                          | When filter active; "clear" is link                 |
| `roleChip`               | `{Role} ✎`                                                                                                                                                     | Edit affordance                                     |
| `addToTeamTooltip`       | `Add to Deal Team`                                                                                                                                             | + button hover                                      |
| `dismissTooltip`         | `Dismiss (re-appears if a new touch arrives)`                                                                                                                  | × button hover                                      |
| `emptyHeading`           | `No marketing-influence touches yet`                                                                                                                           | Empty state h3                                      |
| `emptyBody`              | `No contacts on this account have engaged with a marketing campaign in the last {windowLabel}.`                                                                | Empty state copy                                    |
| `emptySubBody`           | `Once a contact opens an email, attends a webinar, or interacts with a marketing asset, their activity will appear here automatically.`                        | Empty state copy                                    |
| `loadingNote`            | `Loading engagement data…`                                                                                                                                     | Loading state                                       |
| `errorHeading`           | `Something went wrong loading engagement data`                                                                                                                 | Error state h3                                      |
| `errorBody`              | `We couldn't pull the touch records for {AccountName}. This might be a temporary issue, or you may not have permission to see some of the underlying records.` | Error state copy                                    |
| `errorIdLabel`           | `Error ID: {LoggerCorrelationId}`                                                                                                                              | For admin escalation                                |

## Design tokens + SLDS classes used

| Token / class                                    | Use                                                  |
| ------------------------------------------------ | ---------------------------------------------------- |
| `slds-modal__header / __body / __footer`         | Modal chrome                                         |
| `slds-grid / slds-col / slds-size_X-of-Y`        | Layout primitives                                    |
| `slds-box slds-box_xx-small`                     | Stats tiles + small containers                       |
| `slds-theme_default / _warning`                  | Card background variants                             |
| `slds-text-title_caps`                           | Section headers                                      |
| `slds-text-heading_small / _body_small`          | Heading hierarchy                                    |
| `slds-button slds-button_brand / _neutral`       | Buttons                                              |
| `slds-button-group`                              | Scale-control chooser                                |
| `slds-badge / slds-badge_inverse`                | Touch-count badges                                   |
| `slds-card / __header / __body`                  | Bottom tile containers                               |
| `slds-timeline / __item_email / _event / _task`  | Activity feed                                        |
| `slds-icon-standard-{email,event,task,feed,...}` | Icons (utility + standard sprites)                   |
| `slds-has-dividers_around-space`                 | List rows                                            |
| `slds-text-link`                                 | All clickable text                                   |
| `slds-var-p-around_X / slds-var-m-X`             | SLDS 2.x density-token spacing                       |
| Custom `--mi-c`                                  | Per-contact color (one inline style per row)         |
| Custom `--camp-c`                                | Per-campaign color (one inline style per chip / dot) |

## Implementation notes for Coda

- **DTO shape:** `EngagementDTO` extends to include: campaign-level rollups (count + delta + lastAt + im-count per campaign), account-level rollups (when hierarchy is on), `Is_Interesting_Moment__c` + `Interesting_Moment_Reason__c` on each touch.
- **Apex side:** new selector method for hierarchy-scoped query (`WITH USER_MODE`); new selector for campaign rollups; backfill batch for IM evaluation.
- **State management:** modal LWC holds one source of truth — `filterCampaignId`, `selectedContactId`, `scope` (enum). Children receive via `@api`; emit `change` events upward.
- **CSS custom properties** carry per-contact and per-campaign colors. Set on the lane / dot via inline `style="--mi-c: #...; --camp-c: #..."`. No bespoke classes per contact.
- **Gantt positioning:** time-to-x is `(daysAgo / windowDays) * 100%`. Lane labels and time-axis use `position: sticky`. Avoid pixel-fixed widths; use percentages for time anchoring so resize is automatic.
- **Loading state:** show skeleton after 200ms (avoid flash for fast loads). Replace skeleton in place — never unmount + remount the Gantt.
- **Error state:** use `lightning-formatted-text` for error message; pass Logger correlation ID for admin escalation. Per Sage's guidance, never surface raw `AuraHandledException.message` to the user.

## Persona coverage

- **Account Executive / Account Manager:** primary user. Opens modal during pre-call prep or pipeline review. Filter pattern + Interesting Moments are their first read.
- **Sales Manager:** scans modal during deal review. Reads the bottom tile cards (Interesting Moments, Deal Team gaps, Touches by account).
- **Marketing User (read-only):** verifies campaign reach. Group-by Campaign mode. No Add-to-Deal-Team affordance (hidden via custom permission gate).
- **Bad-path: 0 engaged contacts** → empty state (above). Iris open question: does the modal even open?
- **Bad-path: hierarchy traversal fails / FLS deny** → error state with Logger ID + retry + scope-down option.

## Open questions

- [ ] **David / Iris** — Empty state: does the modal even open when 0 engaged? Or does the right-rail panel suppress it?
- [ ] **David / Iris** — Default scope when invoked on an account with children: "This account only" or "+ Children"?
- [ ] **David / Iris** — Default sort order of contact lanes: first-touch ascending (so engagement "builds"), last-touch descending (recent at top), or touch-count descending (heaviest first)?
- [ ] **Iris** — Persona detail: Marketing User read-only view — confirm OCR/ACR/LCR edit affordance is hidden, but is the touch-detail popover still available?
- [ ] **Sage** — confirm hierarchy traversal under `WITH USER_MODE` honors sharing for descendants AND ancestors equally.
- [ ] **Coda** — confirm CSS custom property cascade works inside `lightning-modal` shadow boundaries (it should; flag if not).

## Related briefs

- [brief-interesting-moments.md](brief-interesting-moments.md) — Schema + UI + rules engine for the ★ tier
- [brief-account-hierarchy-engagement.md](brief-account-hierarchy-engagement.md) — Hierarchy roll-up + sharing-aware scope

## Related future-enhancements

- [future-enhancements.md](future-enhancements.md) — Outcome-correlation overlay, AI engagement summary, compare-contacts mode, ghost-dot futures, density toggle, and more.
