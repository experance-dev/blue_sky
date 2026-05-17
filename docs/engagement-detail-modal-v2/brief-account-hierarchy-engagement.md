# Brief: Account-Hierarchy Engagement Roll-up

**Author:** Nova Astro (design) for David Wood
**Date:** 2026-05-16
**Recipient:** Atlas (TA) for decomposition
**Status:** Awaiting Atlas routing

## Context

The Engagement Detail Modal today scopes all touch data to the single Account / Opportunity / Lead it's invoked from. That means if a contact at a **sister subsidiary** (e.g., Acme Health > Acme Imaging Centers) engages with a campaign, the parent Account's modal misses it — even though the engagement is materially relevant to the same deal.

Healthcare and large enterprise orgs commonly have multi-level account hierarchies (parent system → regional ops → individual practices). A sales rep looking at "Acme Health Network" doesn't want to silently drop touches that came in on "Acme Imaging — Boston" — those _are_ the engagement story.

David's ask: surface a **toggle / scope selector** so the rep can roll up engagement across the account hierarchy on demand. Default off (current behavior); explicit opt-in expands the scope.

## Business motivation

- **Lossless engagement view:** stop silently dropping cross-account touches that matter to the deal.
- **Sales rep judgment:** rep decides when hierarchy matters (most accounts don't have a hierarchy; some critically do). Toggle gives them control.
- **Calling-card argument:** "we don't lose data because of a query scope choice — we let you see it" is a strong differentiator vs. competitors who hard-code single-account scope.

## Scope (in)

1. **UI toggle** on the Engagement Detail Modal (and the right-rail panel): "Include account hierarchy" checkbox / dropdown. Three modes:
   - **This account only** (default — current behavior)
   - **This account + child accounts** (downward traversal via `ParentId` parent chain — i.e., child rows where this Account is the parent)
   - **Whole hierarchy** (upward + downward — ultimate parent + all descendants)
2. **Apex selector update:** `Engagement_TouchSelector` (or whatever the current selector is named) gains a method that takes a single Account Id + scope enum and returns the touch set across the resolved hierarchy.
3. **Hierarchy traversal:** recursive CTE-style SOQL using `Account.Parent.Parent.Parent.Id` (Salesforce limit: 5 levels via dot-notation; deeper = batch traversal).
4. **Header banner on the modal** when hierarchy mode is on: "Showing engagement across 4 accounts in the Acme Health hierarchy" + a chip list of the included account names, each chip clickable to drill into that one account's view.
5. **Stat strip update:** when hierarchy mode is on, the stats show the hierarchy-wide rollup (e.g., "8 engaged across 4 accounts").
6. **Each Gantt dot tooltip** gains the source account name when hierarchy mode is on.
7. **Permset enforcement:** respect sharing — if the running user doesn't have read access to a sibling account in the hierarchy, that account's touches are excluded from the rollup (silent, with a footnote: "2 accounts in this hierarchy are not visible to you").

## Scope (out — explicit)

- No editing across hierarchy this phase. Add-to-Deal-Team and role edits still scope to the current Opp / Account.
- No automatic "always include hierarchy" preference. Phase 2 could remember per-user-per-record.
- No support for `AccountContactRelation` cross-account contacts as a separate scope — Phase 2 if needed.

## Open questions for Iris

1. **Default mode** — locked to "this account only" Day 1, or smart-default to "include children" when an Account has children? Different mental models; pick one.
2. **How deep is "whole hierarchy"** — ultimate parent + all descendants? Or just direct parent + direct children?
3. **What happens at Opportunity-scoped invocation** — Opp belongs to one Account; do we expand to the Account's hierarchy or stay strict?
4. **Lead invocation** — Leads have no Account hierarchy. Toggle is hidden in that case? Confirmed.
5. **Visual treatment** when hierarchy mode shows touches from a sibling — color-code the dot by source-account, OR keep campaign-color and put the account name in the tooltip only? (Nova preference: tooltip-only; the chart already has too many color dimensions.)

## Schema / architecture implications for Atlas

- No new fields needed. All data already exists (`Engagement_Touch__c` related to `Contact` related to `Account`).
- Selector design: handle 1-5 deep hierarchies with dot-notation; switch to two-pass query for deeper (rare).
- Performance: cap result set at 500 touches per query (existing MI cap); add account-count cap as well.
- Governor limits: with 5-level hierarchy and 20 children per level, worst case = 20^5 accounts. Need a batch-mode fallback OR a strict hierarchy-depth setting in Custom Metadata.
- Caching: scope-resolution (account-id → hierarchy account-id list) is cacheable per transaction.

## Permission / security (for Sage — non-trivial)

- **Sharing-rule respect is critical.** A rep at a regional office should NOT see touches from siblings they don't have access to. The hierarchy traversal must honor `WITH USER_MODE` / `AccessLevel.USER_MODE`.
- **Owner-based sharing:** if the parent Account is owner-shared but a sibling is private, the sibling's touches are silently excluded. Footnote tells the user this happened (with count, not detail).
- **No data leak via stat rollups:** the count in "8 engaged across 4 accounts" must reflect only what the user can actually see.
- Sage-blocking item: this is exactly the class of feature that leaks data when implemented naively.

## UI implications for Nova / Coda

- New SLDS combobox / button-group at the top of the modal: "Scope: This account / + children / Whole hierarchy".
- Banner row showing the hierarchy chip list (each chip clickable to scope down).
- B3 mockup gets a v9 variant showing hierarchy-mode-on.
- "Stalled" and "first touch" flags need clarifying when crossing accounts — does "first touch" mean first at this account or first across the hierarchy? Ties to Iris open-questions.

## Effort estimate (ballpark)

- Apex (selector + hierarchy resolver + USER_MODE enforcement): ~3 days
- Performance / governor-limit testing: ~1 day
- DTO + LWC scope-toggle + banner: ~2 days (Coda + Kit)
- Tests (Pippa, with hierarchy fixtures): ~3 days — non-trivial because of sharing scenarios
- Security review (Sage, BLOCKING): ~1 day
- Docs (Marlowe + Lyric): ~0.5 day
- Mocks (Nova B3-Hierarchy): ~0.5 day
- **Total: ~1.5 sprints. Security review is the long pole.**

## Definition of Done

1. Selector returns hierarchy-scoped touches honoring user-mode sharing.
2. UI toggle works; banner + chip list render correctly.
3. Stats accurately reflect user-visible-data only.
4. Footnote shows when accounts in hierarchy are hidden by sharing.
5. Performance: 1000-touch / 50-account hierarchy completes in <2s.
6. Sage-approved security review (no sharing leak).
7. Pippa-approved test suite covering: no-hierarchy / child-only / full-hierarchy / mixed-sharing-visibility / governor-limit-bulk.
8. B3-Hierarchy mock approved.
9. Marlowe + Lyric docs updated.
10. Iris delivery acceptance.

## Relationship to Interesting Moments brief

These are independent features but **good to ship together** — hierarchy-rollup × Interesting-Moments compounds (most-impactful touches across the entire account family). If Atlas scopes them sequentially, ship Interesting Moments first (lower risk; no sharing surface).

---

## Atlas dispatch prompt (ready to copy / fire)

```
Brief at docs/briefs/brief-account-hierarchy-engagement.md. David approved.

Take it, decompose into tickets, route per TEAM.md:
1. Iris: open ticket for the open questions (default mode, hierarchy depth,
   Opp behavior, Lead behavior, visual treatment) — these are spec calls
   David needs to make with Iris before dev starts.
2. Boomer: selector design for hierarchy traversal under USER_MODE.
   Performance + governor-limit plan.
3. Sage: SECURITY-CRITICAL review of the sharing surface. This brief calls
   her out as the long-pole reviewer; her gate is BLOCKING. Loop her in
   during design, not just code review.
4. Pippa: test design covering hierarchy + mixed-sharing-visibility
   scenarios. Non-trivial fixtures.
5. Nova: B3-Hierarchy mock once scope semantics are locked by Iris.
6. Coda: LWC scope-toggle + hierarchy banner.

Verify nothing in this brief conflicts with the in-flight CSI-7162 OWD-Private
permset model. Hierarchy traversal under OWD-Private deserves explicit Sage
sign-off on the implementation before merge.

Recommend sequencing: Interesting Moments first (brief-interesting-moments.md),
then Account Hierarchy. Both ship before next stakeholder review.

Report decomposition plan back before dispatching workers.
```
