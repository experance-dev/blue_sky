# Brief: Interesting Moments — elevated touch flagging

**Author:** Nova Astro (design) for David Wood
**Date:** 2026-05-16
**Recipient:** Atlas (TA) for decomposition
**Status:** Awaiting Atlas routing

## Context

While researching Marketo Sales Insight (at a Zelis Marketing Stakeholder's reference), the strongest pattern worth importing is **Interesting Moments** — Marketo's mechanism for flagging _certain_ touches as elevated importance vs. routine engagement. A demo request, an executive briefing attendance, or a pricing-page visit reads as a different signal than yet another newsletter open. Sales reps reading the Engagement Detail Modal need that distinction surfaced visually, not buried in equal-weight dots.

The B3 design already has two dot sizes (big = opp-linked / MC, small = non-opp). **Interesting Moment becomes a third tier above big** — a "this matters more than the others" callout.

## Business motivation

- **Sales reps:** glance at the Gantt → spot the high-value moments without reading every dot. The "wow" interaction for the calling-card demo.
- **Marketing:** decide what counts as Interesting. Configurable per Zelis without code change → CMDT-driven.
- **Cross-tool credibility:** stakeholder familiar with Marketo recognizes the concept instantly. Calling-card lineage.

## Scope (in)

1. **Data model:** add `Is_Interesting_Moment__c` boolean + `Interesting_Moment_Reason__c` short text (the rule that flagged it) on `Engagement_Touch__c`. Indexed for filtering.
2. **Rules engine:** new CMDT `Interesting_Moment_Rule__mdt` keyed on touch attributes (campaign id, asset id, touch type, score threshold, contact role). Evaluated by a trigger handler on touch insert/update. Bulk-safe per [best-practices/architecture.md](../../best-practices/architecture.md).
3. **Backfill:** one-time batch to re-evaluate existing touches against current rules. Re-runnable.
4. **UI in B3:** Interesting Moments render as a third dot variant — same campaign color but with a ★-style icon overlay (utility:star or utility:moments). Also: a new "Interesting Moments" mini-card in the bottom tile row OR appended to the activity-feed card with a filter chip ("Show Interesting Moments only").
5. **DTO:** extend `EngagementDTO` to surface the new fields. Lyric/Marlowe doc updates.
6. **Permset:** existing MI permsets gain FLS on the two new fields. View tier sees them; Power User / Admin can write the rules CMDT.

## Scope (out — explicit)

- No new "Mark this as Interesting" UI action this phase — rules-driven only. (Manual flag = potential Phase 2.)
- No notification when an Interesting Moment lands. (Could be a Phase 2 platform-event hook to Sales Engagement.)

## Open questions for Iris

1. **Who configures the rules?** Marketing Admin (Mira)? Sales Ops? Both?
2. **Initial rule set** — what touches qualify on Day 1? Suggested seed: demo request form-fill, pricing page CTA click, executive briefing attendance, content download where asset is flagged "High-Value." Iris confirms with Zelis Marketing.
3. **Cardinality** — how many Interesting Moments do we expect per Account in a typical 6-week window? Affects UI density (one per touch vs. one per moment-group).
4. **Override semantics** — if a rule changes retroactively, do existing touches re-flag? (We do via the re-run batch, but Iris owns the policy.)

## Schema / architecture implications for Atlas

- Trigger surface: `Engagement_Touch__c` insert/update — handler `EngagementTouchTriggerHandler` already exists; extend it. Selector layer query for active rules cached per-transaction.
- CMDT: `Interesting_Moment_Rule__mdt` with fields for each rule input. Use the existing CMDT pattern from the codebase.
- Batch: schedulable nightly OR runnable on-demand for backfill / rule-change recompute.
- Test: Pippa's team writes red tests first per [TEAM.md](../../.claude/agents/TEAM.md) workflow.

## Permission / security (for Sage)

- Two new FLS fields → all three MI permsets need read on `Is_Interesting_Moment__c` and `Interesting_Moment_Reason__c`. Admin permset gains write on `Interesting_Moment_Rule__mdt`.
- CMDT records are metadata; existing CMDT deploy hygiene applies.
- No PII implications on the two new fields themselves; the touch they describe is already governed.

## UI implications for Nova / Coda

- Third dot variant: pin a ⭐ icon overlay on the campaign-colored dot, or use a unique dot shape (squircle).
- Filter chip strip above the Gantt: existing campaign chips already filter; add an "★ Interesting only" toggle alongside.
- Activity feed: Interesting Moments get a distinct left-rail color stripe + ★ icon next to the title.
- I'll mock B3-IM as the v8 once the data model is decided.

## Effort estimate (ballpark)

- Apex (handler + selector + service + CMDT support): ~3 days
- Backfill batch: ~1 day
- DTO + LWC extension: ~1 day (Coda)
- Tests: ~2 days (Pippa's team)
- Docs + permset updates: ~0.5 day
- Mocks (B3-IM): ~0.5 day (Nova)
- **Total: ~1 sprint, including security review**

## Definition of Done

1. CMDT seeded with the Iris-approved initial rules.
2. Trigger flags new touches against the rules; backfill processed historical touches.
3. B3-IM mock approved by David.
4. LWC renders Interesting Moments visually distinct; filter chip works.
5. Permset updates deployed; FLS verified by Sage.
6. Pippa-approved tests at ≥95% coverage on the new code.
7. Marlowe (Apex) + Lyric (LWC) docs updated.
8. Atlas signs off; Iris signs delivery acceptance.

---

## Atlas dispatch prompt (ready to copy / fire)

```
Brief at docs/briefs/brief-interesting-moments.md. David approved.

Take it, decompose into tickets, route per TEAM.md:
1. Iris: open ticket for the open questions (rule ownership, initial rule set,
   cardinality, override semantics) — needs answers before dev starts.
2. Boomer: schema design (Engagement_Touch__c fields + CMDT + trigger
   handler extension + selector caching).
3. Pippa: test design covering rule evaluation + backfill + bulk path.
4. Nova: B3-IM mock with the third dot variant + filter chip once data
   model is locked.
5. Sage: permset FLS review for the two new fields.

Verify nothing in this brief conflicts with existing CSI-7162 or the
current MI feature branch. Report decomposition plan back before
dispatching workers.
```
