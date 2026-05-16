# Engagement Detail Modal v2 — Documentation

All artifacts for the Marketing Influence Engagement Detail Modal v2 feature. Consolidated single folder per David's organization standard.

## Reading order

| Order | File                                                                             | Audience                                       | Why read                                                                                                                                      |
| ----- | -------------------------------------------------------------------------------- | ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | [BRD.md](./BRD.md)                                                               | David · Iris · Atlas · Sage · stakeholders     | Business intent, personas, acceptance criteria, open spec questions. The "what and why."                                                      |
| 2     | [TDD.md](./TDD.md)                                                               | Atlas · Boomer · Coda · Sage · Pippa           | Technical design, schema, Apex classes, LWC component breakdown, permset architecture, performance plan, test strategy. The "how it's built." |
| 3     | [design-spec.md](./design-spec.md)                                               | Nova · Coda · Lyric · Pippa                    | Visual + interaction spec — every click target, every state, every copy string. SLDS tokens used. Accessibility.                              |
| 4     | [mockup.html](./mockup.html)                                                     | All — **open in browser**                      | The canonical visual mockup. Paste-into-LWC-template ready. State variants in adjacent files.                                                 |
| 5     | [brief-interesting-moments.md](./brief-interesting-moments.md)                   | Atlas (decompose) · Iris (open Qs)             | Feature 1 — Marketo-lineage Interesting Moments. Ship first.                                                                                  |
| 6     | [brief-account-hierarchy-engagement.md](./brief-account-hierarchy-engagement.md) | Atlas (decompose) · **Sage (BLOCKING review)** | Feature 2 — hierarchy-scoped engagement roll-up under sharing rules. Ship second.                                                             |
| 7     | [Atlas-Dispatch.md](./Atlas-Dispatch.md)                                         | David (to fire)                                | Ready-to-paste prompt that dispatches Atlas to decompose this feature for his team.                                                           |
| 8     | [future-enhancements.md](./future-enhancements.md)                               | Backlog                                        | 18 deferred ideas across 5 tiers. Destination Jira / Confluence.                                                                              |
| 9     | [nova-handoff-2026-05-16.md](./nova-handoff-2026-05-16.md)                       | Next-session Nova                              | Cold-start resume doc. Patterns, decisions, what's pending.                                                                                   |

## State mockups (visual variants of mockup.html)

| File                                           | State                                                                                                 |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| [mockup.html](./mockup.html)                   | Primary (happy path — 8+ contacts, 3 ★ Interesting Moments, hierarchy mode, Q4 Pricing filter active) |
| [mockup-empty.html](./mockup-empty.html)       | Empty — zero engaged contacts at this account                                                         |
| [mockup-loading.html](./mockup-loading.html)   | Loading — SLDS skeleton shimmer                                                                       |
| [mockup-error.html](./mockup-error.html)       | Error — Apex throw / FLS deny / hierarchy traversal failure                                           |
| [mockup-popovers.html](./mockup-popovers.html) | Three popover patterns — contact hovercard · touch detail · campaign detail                           |

Rendered PNGs in [./screenshots/](./screenshots/).

## Static-resource SVG illustrations

NOT in this folder — they ship as production metadata:

- [../../force-app/main/default/staticresources/miIllustrations/](../../force-app/main/default/staticresources/miIllustrations/) — SLDS canonical Desert + NoConnection SVGs
- Visual preview: [../../force-app/main/default/staticresources/miIllustrations/preview.html](../../force-app/main/default/staticresources/miIllustrations/preview.html)

## Status

**Design phase: CLOSED. Awaiting Atlas dispatch.**

Fire Atlas via [Atlas-Dispatch.md](./Atlas-Dispatch.md) — paste the prompt body into `Agent({ subagent_type: 'atlas', prompt: <body> })`.

— Nova Astro, 2026-05-16
