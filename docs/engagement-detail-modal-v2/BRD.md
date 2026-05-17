# Business Requirements Document (BRD)

# Marketing Influence — Engagement Detail Modal v2

|                   |                                                                                                                                                                                 |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Document type** | Business Requirements Document                                                                                                                                                  |
| **Feature**       | Marketing Influence (MI) — Engagement Detail Modal v2                                                                                                                           |
| **Version**       | 2.0 (extends v1 shipped on `feature/engagement-attribution`)                                                                                                                    |
| **Author**        | David Wood (TA), captured by Nova Astro (UX) and Iris (SA)                                                                                                                      |
| **Date**          | 2026-05-16                                                                                                                                                                      |
| **Status**        | DRAFT — pending Iris approval for delivery acceptance                                                                                                                           |
| **Approvers**     | David Wood · Iris (Solution Architect) · Atlas (Technical Architect) · Sage Cloudy (Security)                                                                                   |
| **Related**       | [TDD-Engagement-Detail-Modal-v2.md](./TDD-Engagement-Detail-Modal-v2.md) · [engagement-timeline.md](design-spec.md) (design) · [future-enhancements.md](future-enhancements.md) |

---

## 1. Executive summary

Sales reps and managers need a high-resolution view of marketing-influence engagement — _who_ at an account has engaged with marketing, _when_, with _which_ campaigns, _how_ it's trending, and crucially _which moments mattered most_. The v1 Engagement Detail Modal (currently shipped) presents the raw data; v2 reshapes it into a calling-card-quality visualization that:

1. Reads the **engagement story at a glance** via a horizontal Gantt with contact-per-lane swim-lanes, campaign-colored dots, and per-contact lifeline bars.
2. **Surfaces high-value moments** ("Interesting Moments") as a third visual tier so reps spot the deal-relevant touches without reading every record.
3. **Rolls up engagement across an account hierarchy** under sharing-respecting permissions, eliminating the "we missed a sibling account's touches" blind spot.
4. **Connects every visible element** — campaign chips, contact names, role chips, dots, badges — to its source record or a custom popover so users never wonder "what does that mean?"

This BRD scopes the business intent. The companion [TDD](./TDD-Engagement-Detail-Modal-v2.md) scopes the technical design.

## 2. Business motivation

| Stakeholder                     | Pain in current state (v1)                                                                                           | Resolved by v2                                                                                   |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| **Account Executive**           | Cannot quickly assess "who's hot vs cooling" — equal-weight dot list buries the deal-relevant signals.               | Gantt + Interesting Moments tier surfaces what matters first.                                    |
| **Sales Manager**               | Pipeline review requires drilling into individual records; can't read the deal's engagement narrative in 60 seconds. | Top-of-modal campaign cards + bottom-row Interesting Moments + Deal Team Gaps roll up the story. |
| **Marketing User**              | Can't verify whether a campaign reached the right contacts at an account hierarchy — modal scope is single-account.  | Hierarchy scope toggle + per-account chip filter + Top Campaigns roll-up.                        |
| **Zelis Marketing Stakeholder** | Asked for Marketo-Sales-Insight-equivalent capability; v1 doesn't hit the bar.                                       | v2 explicitly imports the Interesting Moments concept from MSI; renders in SLDS-native shape.    |
| **Sales Operations**            | Hard to spot Deal Team gaps when engaged contacts exist outside the team.                                            | Dedicated bottom card surfaces gaps with one-click Add-to-Team.                                  |
| **Compliance / Security**       | Hierarchy-scoped queries risk leaking touches from accounts the user shouldn't see.                                  | v2 enforces `WITH USER_MODE` end-to-end; surfaces "N accounts hidden by sharing" footnote.       |

**Strategic outcome:** the modal becomes the **calling-card surface** for David's tenure as TA — a tangible demonstration that the team builds Salesforce-native, enterprise-grade, SLDS-shaped features that are _legible_ to admins and _defensible_ to security.

## 3. Scope

### 3.1 In scope (v2)

1. **New Gantt visualization** replaces the v1 vertical list. Contact-per-lane swim-lanes with campaign-colored touch dots and per-contact lifeline bars.
2. **Three dot tiers**: small (non-opp, e.g. webinar-registered-not-attended), big (opp-linked / Marketo Cloud touch), Interesting Moment (★, configurable rules engine).
3. **Campaign card strip** at the top of the modal — large readable cards per campaign with name, total touch count, week-over-week delta, last-touch micro-stat, and ★ Interesting Moment count badge. Click any card to filter the Gantt.
4. **Interesting Moments concept** — CMDT-driven rules flag specific touches as elevated importance. New schema fields, new bottom card listing them. (See [brief-interesting-moments.md](brief-interesting-moments.md).)
5. **Account hierarchy scope toggle** — compressed inline header chip; three modes (this account / + children / whole hierarchy); sharing-respecting query via `WITH USER_MODE`. (See [brief-account-hierarchy-engagement.md](brief-account-hierarchy-engagement.md).)
6. **Per-contact lane** now surfaces: Name (clickable → SF hovercard via `/lightning/r/<Id>/view`), Title, Role chip (clickable → edit OCR / ACR / LCR\_\_c per parent), source-account name (uppercase tag, when hierarchy mode shows multi-account data), + Add-to-Deal-Team button when contact is not on the team.
7. **Three explicit non-happy-path states**:
   - **Empty**: zero engaged contacts.
   - **Loading**: SLDS skeleton shimmer placeholders matching the eventual layout.
   - **Error**: SLDS-style illustration + correlation ID + retry + scope-down option. Never leaks `AuraHandledException` internals.
8. **Scale control**: 6w / 3mo / 6mo / 1yr / + Future buttons. Selection remembered per-user-per-SObject (Lead / Contact / Account / Opportunity).
9. **Responsive layout**: full reflow at sales-console-narrow and mobile breakpoints. Sticky lane labels during horizontal scroll.
10. **Every visible element clickable**: 14 click targets inventoried in the design spec; each opens either a SF record, a custom popover, or a modal.
11. **Permset additions**: new `MI_View / Power_User / Admin` permsets get FLS on the new fields and component-visibility on the new UI elements (OWD-Private enforcement, per [feedback-owd-private-permset-architecture](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_owd_private_permset_architecture.md) guidance).
12. **Static-resource bundle** `miIllustrations` for empty + error illustrations (SLDS-style line-art SVGs, in repo).

### 3.2 Explicitly out of scope (v2 — see [future-enhancements.md](future-enhancements.md))

- AI-generated engagement narrative ("📖 Story" button)
- Outcome-correlation overlay (stage-change accent lines on the Gantt)
- Future-engagement ghost dots (the `+ Future` button is rendered but inactive until source data is identified)
- Multi-contact pin / compare mode
- Density-toggle heatmap-cells at zoom-out
- Marketing User read-only persona variant beyond the OWD-Private permset gate
- Manual "Mark as Interesting" UI action (rules-only in v2)
- Marketing Cloud journey enrollment quick action
- Outbound notification on Interesting Moment landing

### 3.3 Dependencies / assumptions

- v1 modal infrastructure (`engagementDetailModal` LWC, `EngagementDTO`, `Engagement_Touch__c` SObject) exists on `feature/engagement-attribution`.
- CSI-7162 utility-class merges are complete; the team is operating on the post-merge baseline.
- Marketo touches sync into `Engagement_Touch__c` via Platform Events (existing pipeline; no v2 change).
- OWD-Private permset architecture (per memory) is the enforced sharing model.

## 4. Personas + acceptance criteria

### 4.1 Account Executive / Account Manager (primary persona)

> _"I'm prepping for a discovery call with Acme Health. I need to know what marketing has done with them, who's hot, and what conversation hook each contact has."_

| AC#   | Acceptance criterion                                                                                                                                          |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AE-1  | I can open the Engagement Detail Modal from the right-rail panel on an Account, Contact, Lead, or Opportunity.                                                |
| AE-2  | I see, within 3 seconds of opening, which campaigns are most active at the account (top 7 cards, sorted by recency or volume).                                |
| AE-3  | I can identify each engaged contact's role (Decision Maker / Influencer / Champion / Tech Buyer / Economic Buyer) without leaving the modal.                  |
| AE-4  | I can click any contact's name and see the standard Salesforce hovercard for that contact.                                                                    |
| AE-5  | I can see at a glance which contacts have engaged with marketing but are NOT on the Deal Team, and add them with one click.                                   |
| AE-6  | I can identify any "Interesting Moment" (★) within the engagement — high-value touches like demo requests, executive briefing attendance, pricing CTA clicks. |
| AE-7  | I can filter the Gantt to a single campaign by clicking its card; all other dots dim to ≤15% opacity.                                                         |
| AE-8  | I can change the time scale (6w / 3mo / 6mo / 1yr); my selection is remembered next time I open the modal on this same record type.                           |
| AE-9  | If the account has children or a parent in the account hierarchy, I can scope the modal to include touches from related accounts.                             |
| AE-10 | I see a footnote when accounts in the hierarchy are excluded from my view due to sharing.                                                                     |
| AE-11 | If there's no engagement data, I see a friendly empty state explaining why and suggesting next actions.                                                       |
| AE-12 | If the data fails to load, I see a clear error message with a retry button — never raw exception text.                                                        |

### 4.2 Sales Manager

> _"I have 12 pipeline opportunities to review tomorrow. I need to scan each one's engagement health in under 30 seconds."_

| AC#  | Acceptance criterion                                                                                                                          |
| ---- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| SM-1 | I see headline counts (engaged / touches / window / gap) prominently at the top of the modal.                                                 |
| SM-2 | I can identify "stalled" engagement at a glance (contacts with `lastTouch > 7d AND firstTouch < 30d`) — visually flagged via a warning badge. |
| SM-3 | I can see the "Interesting Moments" summary in a dedicated card without filtering.                                                            |
| SM-4 | I can see which campaigns are driving the engagement (top campaigns card / strip).                                                            |
| SM-5 | I can identify Deal Team gaps and verify someone is taking action on them.                                                                    |

### 4.3 Marketing User (read-only)

> _"I sent the Q4 Pricing Update campaign to 500 contacts last week. Did it land at our enterprise accounts?"_

| AC#  | Acceptance criterion                                                                                                            |
| ---- | ------------------------------------------------------------------------------------------------------------------------------- |
| MU-1 | I can open the modal in read-only mode (no Add-to-Team button, no Role-edit affordance — gated by `MI_View` custom permission). |
| MU-2 | I can filter to a specific campaign and see which contacts engaged.                                                             |
| MU-3 | I can verify which Interesting Moments my campaigns generated.                                                                  |
| MU-4 | I cannot edit OCR / ACR / LCR records from this modal (enforced via permset).                                                   |

### 4.4 Compliance / Security stakeholder

| AC#   | Acceptance criterion                                                                                                                                                                        |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SEC-1 | All queries run with `WITH USER_MODE` (SOQL) and `AccessLevel.USER_MODE` (DML).                                                                                                             |
| SEC-2 | Hierarchy traversal respects sharing — a user without read access to a sibling account sees NEITHER that account's touches NOR a leak of the account's existence beyond the footnote count. |
| SEC-3 | Apex never returns raw `AuraHandledException.message` to the LWC; error correlation IDs are surfaced for admin escalation.                                                                  |
| SEC-4 | New FLS fields are governed by the MI permset ladder; no profile-default access.                                                                                                            |
| SEC-5 | Component visibility on the LWC respects the `Marketing_Influence_View` custom permission via App Builder rules.                                                                            |
| SEC-6 | Audit log captures Add-to-Deal-Team writes (existing pattern).                                                                                                                              |

## 5. Success metrics

| Metric                                       | Target                                    | How measured                          |
| -------------------------------------------- | ----------------------------------------- | ------------------------------------- |
| Modal open → first meaningful read           | < 3 seconds                               | User testing with 5 reps              |
| Reps adding gaps to Deal Team from the modal | ≥ 40% of opens result in at least one add | Telemetry on Add-to-Team button click |
| Interesting Moments → opp stage advances     | Pos. correlation within 14 days           | Reporting via Opp History join        |
| Sharing-leak incidents reported              | 0                                         | Sage Cloudy compliance review         |
| Modal time-to-render (P95)                   | < 1.5 seconds                             | Apex `Logger` performance traces      |
| Stakeholder review feedback                  | "Salesforce-native, calling-card quality" | David's calling-card demo             |

## 6. Constraints

- **OWD-Private model** is non-negotiable (per [memory](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_owd_private_permset_architecture.md)). Every new field, LWC, and tab gets explicit permset coverage.
- **No real emails from tests** (per [memory](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_no_real_emails_from_tests.md)).
- **No personal-lib edits during work hours** (per [memory](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_ip_protection_no_personal_lib_edits.md)) — utility classes are read-only; new helpers go in feature-scoped classes.
- **TDD process** — Pippa's test team writes red tests against ACs before dev writes production code (per [TEAM.md](../../.claude/agents/TEAM.md) workflow).
- **Atlas verifies before UAT** (per [memory](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_atlas_verifies_before_uat.md)) — every shipped change is verified against the deployed org by Atlas before David sees it.

## 7. Open questions for Iris (gate-1 spec items)

1. **Empty state behavior**: when 0 engaged contacts, does the modal open at all or does the right-rail panel suppress it? Either is defensible.
2. **Default hierarchy scope** on an account that has children: "This account only" or "+ Children"?
3. **Default contact lane sort order**: first-touch ascending (engagement-builds story), last-touch descending (recency), or touch-count descending (heaviest first)?
4. **Interesting Moments rule ownership**: Marketing Admin? Sales Ops? Both?
5. **Initial Interesting Moments rule set** to seed Day 1.
6. **Cardinality expectations** for Interesting Moments in a typical 6-week window — affects UI density.
7. **Future-scale `+ Future` button** — what data sources feed the future view? Marketo nurture queue? Salesforce calendar? Out-of-scope for v2 if no source exists.

These are the spec questions blocking dev start. Iris owns answering them with David / Zelis Marketing stakeholders.

## 8. Approvals

| Role                | Name        | Signature / Date                              |
| ------------------- | ----------- | --------------------------------------------- |
| Sponsor             | David Wood  | _Pending_                                     |
| Solution Architect  | Iris        | _Pending_                                     |
| Technical Architect | Atlas       | _Pending — gates dev start_                   |
| Security Architect  | Sage Cloudy | _Pending — gates hierarchy traversal release_ |

---

**Next step:** Iris's gate-1 spec approval, then the [TDD](./TDD-Engagement-Detail-Modal-v2.md) decomposes the technical design and Atlas dispatches the team.
