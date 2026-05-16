# Investigation — Marketing Influence on Lead (and Contact) record pages

**Author:** Iris (Solution Architect)
**Date:** 2026-05-15
**Stakeholder:** David Wood
**Status:** Draft — awaiting David sign-off + Atlas architectural pair on DTO fork (§3, §5)

---

## TL;DR

David called this "easy to accomplish" and he's mostly right. The schema is ready ([`Engagement_Touch__c.Lead__c`](../../force-app/main/default/objects/Engagement_Touch__c/fields/Lead__c.field-meta.xml) + [`.Contact__c`](../../force-app/main/default/objects/Engagement_Touch__c/fields/Contact__c.field-meta.xml) both exist), the [reparent handler](../../force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls) is in place, and identity resolution already writes touches to `Lead__c` pre-conversion. The work is **mostly additive**: new controller methods, new service methods, extended selector, extended LWC `recordContext` enum, new FlexiPage placements, permset FLS additions.

The one real architectural question — and the only thing that needs Atlas's eyes before we ticket this — is **DTO shape**: Lead and Contact panels are single-anchor views, not multi-Contact aggregations. Either we keep `EngagementDTO` and accept that on Lead/Contact pages the list will always be length 1, or we ship a distinct `AnchorEngagementDTO` shape that's honest about the model.

Recommended phasing: **single wave**, ~5-8 days end-to-end, ship Lead and Contact together. The bridge logic (post-conversion continuity on the Contact panel) is the whole point — splitting them dilutes the demo.

---

## 1. Business model — does this make sense?

### What value does engagement on a Lead page add?

Today the panel renders only on Account and Opportunity records. That means:

- **Pre-conversion engagement is invisible.** When marketing ingests a webinar attendee or whitepaper download as a Lead, that touch lives at `Engagement_Touch__c.Lead__c` and never surfaces in the UI. A BDR working that Lead can't see what marketing already knows about them.
- **The "qualify vs. discard" decision is uninformed.** BDRs make qualification calls partly on engagement signal — how many touches, what topics, what assets. Today they have to query reports or trust marketing's hand-off email.
- **Conversion ceremony loses context.** When a Lead is converted, the touches reparent to the Contact (today, via [`LeadEngagementReparentHandler`](../../force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls) on the same transaction). But the BDR's mental model of "this Lead is hot because of A, B, C" never makes it to the next persona because nothing showed them A/B/C on the Lead page.

### What's the difference in user task: Lead page vs. post-conversion Contact page?

| Lead page (pre-conversion)                      | Contact page (post-conversion)                                               |
| ----------------------------------------------- | ---------------------------------------------------------------------------- |
| User: BDR / SDR / inside sales triaging inbound | User: AE / CS owner contextualizing a known person                           |
| Question: "Is this Lead worth pursuing?"        | Question: "What has this person engaged with — across their history?"        |
| Touch volume: typically low (1-10)              | Touch volume: cumulative — pre-conversion + post-conversion                  |
| Anchor: one Lead, one engagement timeline       | Anchor: one Contact, possibly two timelines (Lead-era + Contact-era) blended |

Both are **single-anchor** views — fundamentally different from Account (aggregate multiple Contacts) and Opportunity (aggregate Contacts joined to OCR). That distinction drives the DTO question in §3.

### Are there MI-eligible touches that exist today and are invisible?

Yes. Any touch resolved via [`IdentityResolutionService`](../../force-app/main/default/classes/engagement/IdentityResolutionService.cls) line 163 (matched to a Lead, not a Contact) is currently dark to the sales user. They live in the data — they're queryable via reports, and the retention/decay batches process them — but no record page surfaces them. **This is the strongest argument for Lead-page MI.**

### Personas

- **BDR / SDR** — primary user of Lead-page engagement. Triage, qualify, work cadence.
- **Inside Sales** — secondary; depends on org motion. At Zelis, inside-sales-on-Lead is plausible for the Provider segment.
- **AE** — primary user of Contact-page engagement (post-conversion).
- **CS / Account Manager** — secondary on Contact page; mostly cares about the Account aggregate.

Permset implication: View tier needs to be assigned to both BDR PSGs and AE/CS PSGs — likely already in flight per the current `Persona - IE Sales` / `Persona - Marketing User` PSG composition list in the View permset comment block.

---

## 2. Conceptual model — Lead vs. Contact as anchor

### Today's aggregation pattern

| Scope                  | Filter                                        | Group-by                            | Display                                 |
| ---------------------- | --------------------------------------------- | ----------------------------------- | --------------------------------------- |
| Account                | `Account__c = :id`                            | `Contact__c`                        | N rows (one per engaged Contact)        |
| Opportunity            | `Account__c = oppAcct AND Topic IN oppTopics` | `Contact__c`                        | N rows (Contacts on/off OCR)            |
| **Lead (proposed)**    | `Lead__c = :id`                               | none (anchor is the Lead itself)    | **1 anchor row, expanded asset detail** |
| **Contact (proposed)** | `Contact__c = :id`                            | none (anchor is the Contact itself) | **1 anchor row, expanded asset detail** |

For Lead and Contact, "group by Contact" is meaningless — there's only one. The natural display is:

- Header: anchor identity (name, title, account/lead-source, badges)
- Body: the per-asset breakdown that currently lives nested in `EngagementDTO.assets[]` for the View-All modal

In other words: the **Lead/Contact panel renders what the View-All modal renders today for one Contact**, just inline on the record page rather than as a modal pop-out.

### Post-conversion continuity on the Contact panel

[`LeadEngagementReparentHandler`](../../force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls) already does the right thing — synchronously, in the same transaction as conversion. On the converted Contact, every pre-conversion Lead touch now has `Contact__c = <newContactId>` and `Lead__c = null`. **No blending logic required**: the Contact panel just queries `Engagement_Touch__c WHERE Contact__c = :anchorId` and gets the union of pre-conversion-Lead-era and post-conversion-Contact-era touches.

This is clean. It also means there's no "window where the Contact page shows nothing" — the reparent is part of the conversion transaction, not async (verified by reading the handler).

---

## 3. Technical changes — what we'd actually have to do

### 3.1 Apex

**[`EngagementController`](../../force-app/main/default/classes/engagement/EngagementController.cls)** — add two `@AuraEnabled(cacheable=true)` methods:

```apex
@AuraEnabled(cacheable=true)
public static AnchorEngagementDTO getForContact(Id contactId) { ... }

@AuraEnabled(cacheable=true)
public static AnchorEngagementDTO getForLead(Id leadId) { ... }
```

Return shape: see §3.4 below — the DTO question is the one architectural fork.

**[`EngagementServiceImpl`](../../force-app/main/default/classes/engagement/EngagementServiceImpl.cls)** — add `getForContact(Id)` and `getForLead(Id)`. Most helpers (`buildAssetEngagements`, `displayLabelFor`, `computeMaxOccurredAt`, topic collection) carry over verbatim. The Contact variant joins ACR for the `isAcr` flag using the Contact's primary Account; the Lead variant doesn't need ACR at all.

**[`EngagementTouchesSelector`](../../force-app/main/default/classes/engagement/EngagementTouchesSelector.cls)** — add:

```apex
public static List<Engagement_Touch__c> selectByContactIds(Set<Id> contactIds)
public static List<Engagement_Touch__c> selectByLeadIds(Set<Id> leadIds)
```

Same canonical field shape as `selectByAccountIds`; filter on `Contact__c IN :ids` / `Lead__c IN :ids` respectively, plus the active-and-not-errored predicate.

**`IEngagementService`** — extend the interface with the two new methods (no-op for the mock pattern; just add signatures + update the test mock).

### 3.2 LWC — [`engagementPanel`](../../force-app/main/default/lwc/engagementPanel/engagementPanel.js)

- Extend `recordContext` enum from `Account|Opportunity` to `Account|Opportunity|Contact|Lead`.
- Add two new `@wire` adapters: `getForContact` + `getForLead`, each gated by a reactive param getter that returns null unless `recordContext` matches (preserving the LDS cache pattern already in use).
- Add `isContactScope` / `isLeadScope` getters.
- Conditional render: single-anchor scopes (`isContactScope || isLeadScope`) render the asset-detail view inline (anchor header + flat `assets[]` list). Multi-contact scopes (`isAccountScope || isOpportunityScope`) keep the current Deal Team / Not on Deal Team split.
- `+ Add to Deal Team` button: irrelevant on Contact and Lead pages — there's no Opportunity context. Hide for those scopes.
- `[`engagementPanel.js-meta.xml`](../../force-app/main/default/lwc/engagementPanel/engagementPanel.js-meta.xml)`: extend `<object>` list and `datasource` to include `Contact` and `Lead`.

### 3.3 FlexiPages

**Lead record pages** — likely Zelis-owned (Lead is core platform; Zelis admins manage Lead pages). Treat additively per the [graph-footprint rule](../../../../../.claude/agents/TEAM.md): we contribute the panel as a component to add, we don't replace the FlexiPage. Talk to Atlas about whether to ship our own Lead Record Page that Zelis admins assign, or hand off a Zelis-side change request.

**Contact record pages** — same question. Likely Zelis-owned across multiple record types (Provider Contact, Payer Contact, etc., if they exist). May need multiple FlexiPage placements.

Inventory required: ask Zelis admin team which Lead and Contact RTs exist and which FlexiPages back them. **This is the biggest unknown** — the Apex and LWC work is straightforward; the FlexiPage footprint is potentially long-tail.

### 3.4 DTO shape — the architectural fork (Atlas pair needed)

**Option A — reuse `EngagementDTO`, return List<>**

- Service returns a list of length 1 for Lead/Contact scopes.
- LWC special-cases "if list length == 1 and scope is single-anchor, render asset detail".
- Pro: zero new shape; tests reuse fixtures; Marlowe's doc is shorter.
- Con: lies about the model. `EngagementDTO` was designed for "one row per engaged Contact." On a Lead page the "engaged Contact" is the Lead-as-pseudo-contact and the fields don't all map (no `onOcr`, no `acrRole`, no `accountName` in the same sense). The DTO would be half-populated with nulls — exactly the readability-tax David's calling-card rule warns against.

**Option B — ship `AnchorEngagementDTO` (recommended)**

- New DTO: `anchorId`, `anchorType` (`'Contact'|'Lead'`), `name`, `title`, `accountName` (Contact only), `leadStatus` (Lead only), `topics[]`, `touchCount`, `lastTouchAt`, `assets[]` (reuse the existing `AssetEngagement` inner class via static import or duplicate the inner class — Atlas's call).
- Service returns one `AnchorEngagementDTO` (singular, not list).
- Pro: honest shape; readable; LWC template-binding stays clean.
- Con: new DTO class + meta; LWC has two render paths (list-of-dtos for Account/Opp, single-dto for Contact/Lead); Marlowe documents the divergence.

**Iris recommendation: Option B.** David's calling-card rule + the readable-not-dense principle favor an honest distinct shape over a half-populated reuse. The LWC divergence isn't large — both paths use the same `AssetEngagement` rendering primitives. Atlas: confirm or counter.

### 3.5 Permsets

All four MI permsets ([View](../../force-app/main/default/permissionsets/Additional_Permissions_Marketing_Influence_View.permissionset-meta.xml), Power User, Admin, Integration) need:

- **Class access:** none new — `EngagementController` already in the View permset; adding methods doesn't change the access grant.
- **FLS:** confirm Contact reads are NOT in the View permset today (they aren't — only `Contact.Title` and `Contact.Is_Consultant__c`). Standard `Contact.Name` and `Contact.Account.Name` read via standard profile FLS; no permset change needed there. For Lead, add `Lead.Name`, `Lead.Status`, `Lead.Company`, `Lead.Title` to the View permset.
- **Custom permission gating:** the FlexiPage Component Visibility rule (`Marketing_Influence_View`) carries over verbatim — same gate, different sObject host page.

Minor permset change, low risk.

### 3.6 Tests (Pippa's team)

Per the [persona-path-coverage](../../../../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_persona_path_coverage.md) rule:

- `EngagementServiceImpl_getForContactAcrossPersonas` — happy and bad path for: View user, Power User, Admin, no-permset user, integration user.
- `EngagementServiceImpl_getForLeadAcrossPersonas` — same persona matrix.
- `EngagementTouchesSelectorTest` — add coverage for `selectByContactIds` and `selectByLeadIds`.
- `LeadEngagementReparentHandlerTest` — already exists; verify the after-conversion Contact-panel query path is tested end-to-end (Lead → convert → query getForContact → asserts pre-conversion touch appears).

### 3.7 Demo data

[`PersonaTestFactory`](../../force-app/main/default/classes/engagement/) likely has Lead seed paths already (Boomer's reparent handler tests use them). Demo seed script needs:

- A pre-conversion Lead with 5-8 touches across 2-3 topics, attached to a recognizable demo account context.
- A post-conversion Contact (converted from a different Lead) with mixed pre/post-conversion touches to show the blend on the Contact panel.

---

## 4. The Lead-conversion bridge — questions answered

| Question                                 | Answer (from code)                                                                                                                                                                                                                                                                               |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Sync or async reparent?                  | **Sync, same transaction.** [`LeadEngagementReparentHandler.reparentTouches`](../../force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls#L65) runs in the after-update trigger context.                                                                                   |
| Window where Contact page shows nothing? | **No.** Same-transaction reparent means the moment the user lands on the new Contact page, `Contact__c` points correctly.                                                                                                                                                                        |
| Conversion rollback?                     | If the conversion transaction rolls back, the touch updates roll back with it (single-transaction atomicity). Touches re-anchor to `Lead__c` automatically.                                                                                                                                      |
| Lead reverted post-conversion?           | Salesforce doesn't natively support Lead un-conversion. If admin manually creates a Lead and re-links, it's a new Lead Id and the touches are orphaned. Out of scope for this work; flag as known gap.                                                                                           |
| Multi-Lead-merge-into-one-Contact?       | Lead conversion supports it (matching contact). Each just-converted Lead fires the after-update trigger; the handler processes each Lead's touches → reparents to whichever `ConvertedContactId` is on the Lead record. All converge on the same Contact. **Should work cleanly; needs a test.** |
| Person Account conversion?               | Lead.ConvertedAccountId points to the Person Account record. The Account**c reparent path works. Contact**c also gets set. **Should work; needs a test in orgs where Person Accounts are enabled.** Zelis: confirm whether PA is on.                                                             |

The reparent handler is **the bridge** that makes Contact-panel continuity work — and it's already in place and FLS-gated as of Boomer's earlier commit today ([`fix(lead-conversion): FLS-gate Engagement_Touch__c.Lead__c in handler`](../../../../../.claude/worktrees/feature-engagement-attribution)). No new bridge logic required.

---

## 5. Risks / open questions

### 5.1 Volume

Leads outnumber Contacts in most orgs by 5-20x. Marketing Influence ingestion writes one touch per engagement event. Worst case: a hot lead with 50 webinar attendances + email opens.

- Selector caps at 5000 rows (good defensive default).
- Single-anchor query (`WHERE Lead__c = :id`) is highly selective and indexed-friendly (lookup fields are auto-indexed in SF). Should perform well even on outlier Leads.
- Aggregation is in-memory; with the cap, max 5000 records to group → cheap.
- **Concern**: cacheable=true wire + frequent navigation between Leads → LDS cache size. Likely fine but worth monitoring after rollout.

### 5.2 Lead RT variation

If Zelis has Provider Lead, Payer Lead, etc. record types with distinct FlexiPages, each needs the panel placement.

**Action required**: ask Zelis admin team for the Lead RT inventory before we ticket. Same for Contact RTs.

### 5.3 OWD-Private + Lead sharing

Salesforce defaults: Lead OWD is typically `Public Read/Write` unless an org has tightened it. Zelis is OWD Private on the major objects we care about. **Need to confirm Lead OWD at Zelis.** If Leads are also Private, the same considerations apply (touches inherit visibility via the Contact/Lead lookup; users only see touches where they can also see the parent record under USER_MODE).

### 5.4 The "anchor reliability" question

David's framing called Contact "the anchor." From a model perspective:

- A Lead-anchored touch that converted to a Contact is now a Contact-anchored touch (reparented).
- A Lead-anchored touch that **never converted** is a signal that didn't pay off. Should it appear on the Lead panel? **Yes** — the BDR is the user, and they need that signal to make the qualify/discard call.
- Should never-converted Lead touches roll up to anything else? **No** — they're invisible to AE/CS because the Lead never became a Contact, and that's correct.

No aggregation-weighting change required. The model is honest as-is.

### 5.5 "AccountName" on a Lead

Leads have `Company` (a freeform string), not `AccountId` (a real FK). On a Lead panel, the equivalent display field is `Lead.Company`. The `AnchorEngagementDTO` should call it `accountName` (consistent surface name) but the service populates it from `Lead.Company` for the Lead scope and `Contact.Account.Name` for the Contact scope.

---

## 6. Recommended approach + effort estimate

### Single wave (recommended)

Ship Lead and Contact together. The bridge logic (post-conversion continuity) is the **whole point** of doing this work — splitting it across phases sacrifices the demo narrative and creates a half-shipped feature in production for a week.

| Stream                                                                             | Owner                                  | Days                                       |
| ---------------------------------------------------------------------------------- | -------------------------------------- | ------------------------------------------ |
| Apex: controller methods + service methods + selector additions + interface update | Boomer                                 | 1.5-2                                      |
| Apex tests: persona-path coverage for both new methods                             | Pippa                                  | 1.5-2                                      |
| LWC: recordContext extension, single-anchor render path, meta-xml updates          | Coda                                   | 1-1.5                                      |
| LWC Jest: single-anchor render coverage                                            | Pippa (next wave per OOS)              | —                                          |
| FlexiPage placements: Lead Record Page(s), Contact Record Page(s)                  | Admin team / our additive contribution | 0.5-1                                      |
| Permset FLS additions (Lead fields)                                                | Admin team / Sage review               | 0.25                                       |
| Demo seed data                                                                     | Wren                                   | 0.5                                        |
| End-to-end walkthrough + Atlas verify                                              | Atlas                                  | 0.5                                        |
| **Total**                                                                          |                                        | **~6-8 days elapsed, parallel-dispatched** |

### Alternative phasing (only if business case forces it)

- Phase 1: Lead-only — ship the Lead panel first; defer Contact. ~3-4 days. Use case: BDR-led pilot before AE rollout.
- Phase 2: Contact panel — ~2-3 days additional, mostly LWC + FlexiPage.

**Iris recommendation: single wave.** The Lead-only-first phasing only makes sense if Zelis is doing a BDR-isolated pilot. If David's framing is "we need this for the engagement model to be complete," ship both.

---

## 7. Out of scope (named explicitly)

- LWC Jest persona coverage for the new contexts (Pippa, next wave)
- Performance optimization beyond initial bulkification + 5000-row cap (next wave if volume becomes a concern)
- Permset assignment to Persona PSGs at Zelis (admin handoff per the PSG composition pattern)
- Confluence tech doc (separate Marlowe deliverable post spec-approval)
- Lead un-conversion / reverted-Lead orphan touches (no SF native support; document as known gap)
- Touch ingestion changes — `IdentityResolutionService` already writes `Lead__c` correctly
- Engagement Detail modal extension — modal is already capable of single-anchor render; verify no changes needed once Atlas pairs on DTO shape
- Signal dismissal UX on Lead/Contact scopes — Phase 3 work; not part of this ticket

---

## Open decisions for David (numbered, action-required)

1. **DTO shape — Option A or Option B?** Iris recommends Option B (`AnchorEngagementDTO`). Architectural call; Atlas needs to weigh in. Confirm direction before we ticket.
2. **Single wave or phased?** Iris recommends single wave. If BDR-pilot motivation drives Phase-1-only, say so now and we'll split the ticket.
3. **Lead OWD at Zelis** — Private or Public? If Private, no new logic; if Public, confirm the permset model still gates correctly.
4. **Lead and Contact record-type inventory** — how many RTs per object, and which FlexiPages back them? This is the biggest scope-bounding question.
5. **Person Accounts enabled at Zelis?** If yes, conversion-to-PA path needs explicit test coverage.
6. **Hide `+ Add to Deal Team` on Lead/Contact scopes** — confirm. There's no Opportunity context on those pages, so the action makes no sense. Iris's read: hide it. David: confirm.
7. **Should Lead-anchored never-converted touches appear in any rollup?** Iris's read: no — they stay Lead-visible only. Confirm.

---

## Atlas-side architectural fork (flagged per Iris/Atlas handoff discipline)

**§3.4 DTO shape** is the only fork that needs Atlas before David sign-off. The recommended approach (Option B — `AnchorEngagementDTO`) keeps the model honest and the LWC clean, but introduces a parallel DTO and a second render path. Atlas may have opinions on:

- Whether to nest `AssetEngagement` under the new DTO or share it
- Whether the service should return `AnchorEngagementDTO` (singular) or `List<AnchorEngagementDTO>` (always length 1) — singular is cleaner but breaks the symmetry with `getForAccount` / `getForOpportunity` return shape
- Whether to refactor existing `EngagementDTO` to extend a common base, or leave them as parallel-but-distinct shapes

Atlas: please weigh in and reply on the ticket (or directly here as a follow-up). Once the DTO call is made, this investigation moves to a ticket (`MI-LEAD-CONTACT-PANEL-001` or similar) and we dispatch.

— Iris

---

## 8. Domain-based attribution — expansion considerations

**Status:** Captured for the record. **Not Phase 1/2/3 of the Lead+Contact panel work.** This is a follow-on feature ticket. Goal of this section: get the threads on paper while the model is fresh, so the basic Lead/Contact MI work leaves clean extension hooks (notably: the recommended `AnchorEngagementDTO` shouldn't preclude a future `DomainEngagementDTO`).

David's framing (paraphrased, tick-bite brain fog acknowledged but thinking sharp): broaden the Lead panel from single-point-of-contact to **all marketing touches from a given email domain**. Capture shadow engagement — anything from `@company.com` rolls up against the right anchor, even when no individual Lead or Contact has been resolved yet. Auto-promote that shadow signal into structured ACRs when the domain matches an Account. Then the hard bit: what happens when the Account doesn't exist? What happens when multiple Accounts share a domain?

### 8.1 Five conceptual threads

**Thread 1 — Email domain as a soft anchor.** Today every `Engagement_Touch__c` row anchors via FK (`Contact__c` / `Lead__c` / `Account__c` / `Opportunity__c`). The expansion adds an aggregation key alongside the FKs: the **email domain** extracted from `Email_At_Touch__c`. A touch with `joe@acme.com` is now claimable by any record that knows about `@acme.com` — the Lead whose `Email` ends in that domain, the Account whose website / explicit `Email_Domain__c` matches, the Opportunity rolled up from that Account. The FK is the hard anchor; the domain is the soft anchor for "this signal probably belongs here."

**Thread 2 — Shadow touches.** Touches arriving from `@acme.com` where identity resolution found no matching Lead or Contact. Today those probably land in the Error Queue or get dropped at ingestion. With domain anchoring they accumulate against the domain itself and surface on the matching Account/Lead panel as **"uncontacted engagement from this company"** — a section above (or alongside) the named-Contact engagement list. BDR sees: "Acme had 47 touches this month from people we haven't talked to yet." That's a different shape of insight than "Joe at Acme opened 4 emails."

**Thread 3 — Auto-ACR creation on domain match.** When `joe@acme.com` arrives and Acme Account exists with a matching domain: pipeline auto-creates a Contact on Acme (or an `AccountContactRelation` to Acme if a `joe@acme.com` Contact already exists under a different primary Account). The shadow signal gets lifted into structured CRM data the moment there's confidence it belongs. This is the "promote shadow → structured" step.

**Thread 4 — Account-doesn't-exist case.** Touches accumulate against the domain in an intermediate state — call it a **Shadow Account** (modeled or virtual; §8b decides). Marketing sees domains warming up before Sales gets involved. When a deal lead picks up the trail, "Create Account from domain" is a one-click action that materializes the SF Account and reparents the shadow touches to it. Same `LeadEngagementReparentHandler` pattern, generalized.

**Thread 5 — Multi-Account same-domain ambiguity.** The hard one. Real cases the model has to handle:

- **Generic free-mail domains** (`@gmail.com`, `@yahoo.com`, `@outlook.com`, `@hotmail.com`) — should be blocklisted from domain-matching entirely. Touches from these emails fall back to FK-only attribution.
- **Subsidiary companies sharing a parent domain** — Acme Holdings → Acme East, Acme West, Acme International. All carry `@acme.com` business cards. The domain is ambiguous between three SF Accounts.
- **M&A consolidations** — domain pre-dates an SF Account merge. Touches anchored to the survivor Account; old-domain touches from acquired-company emails need to flow to the survivor.
- **Agency contacts** — `@bigagency.com` employees writing on behalf of several different Accounts (a marketing-agency consultant working with three Zelis customers). Domain matches the agency, not the customer.
- **Solo consultants** — `@gmail.com` while consulting for multiple Accounts. Same problem, harder because no identifying domain at all.

Disambiguation strategies to consider:

- **Most-recent-active-Opp rank** — when multiple Accounts match the domain, prefer the Account with the freshest open Opportunity.
- **Manual reviewer queue** — ambiguous domains park in an admin queue for human disposition.
- **Generic-domain blocklist (CMDT-driven)** — admin-maintained, ships with a sane default (the major free-mail domains).
- **Domain-CAN-map-to-multiple-Accounts** — accept the ambiguity, show the same shadow touches on all matching Account panels with a "shared domain" badge so the user knows what they're looking at.
- **Domain-on-Contact wins** — if a real Contact already exists with that email on a specific Account, treat that as ground truth for that email and let the domain rollup ignore it.

### 8.2 Stakeholder questions — for David to take to Marketing Ops / BDR / Sales Enablement leadership

These are business-judgment calls, not architecture. The answers shape what we even build.

1. **Is shadow engagement valuable to surface, or noise?** When a BDR sees "Acme had 47 touches this month from people we haven't talked to" — does that change their day, or do they tune it out? If they tune it out, this whole expansion may not be worth building.
2. **When auto-ACR creates a Contact, who owns it?** Marketing user? Account Owner inherited? Round-robin? Held as Unassigned until a human triages? Each answer implies different SLA and sharing setup.
3. **Generic free-email-domain blocklist — who maintains it?** Default ship-with set (gmail/yahoo/outlook/hotmail/icloud/protonmail/aol) plus admin-overridable CMDT seems right; Marketing Ops should confirm coverage.
4. **Multi-Account same-domain — which subsidiary wins, or do we show under all?** Marketing's call. Tied to how Zelis structures Account hierarchies (Parent + child Accounts? Flat with no parent?).
5. **Shadow Account concept — visible to Sales, or Marketing-only until promoted?** Two camps: "Sales should see early signal" vs "noise pollutes the funnel until qualified." Marketing leadership picks.
6. **Shadow-touch SLA — how stale before they expire?** 90 days? 6 months? Aligns with the existing `EngagementSignalDecayBatch` / `EngagementTouchArchivalBatch` retention policy David already specced (1yr no-open-opp delete, 1.5yr not-on-OCR delete).
7. **Auto-promotion threshold — does the system auto-create the Contact on first touch, or wait for N touches before promoting shadow → structured?** Threshold model would prevent one-off rando emails from polluting Accounts.
8. **Promotion notification — does Marketing want to know when a shadow domain crosses the threshold and becomes an attached Contact?** Probably yes for high-value Accounts; chatter post or queue or report subscription.
9. **Acceptable SF-data-staleness window** — added per the HubSpot Journal architectural update (§12). HubSpot's Webhooks Journal is a pull model: SF schedules a job to poll HubSpot's journal API on a cadence. Marketing Ops needs to set the tolerance for "Acme had 15 touches in the last hour but Sales doesn't see them yet." 5 min vs 15 vs 60 vs hourly drives the schedule cadence and the callout-volume budget. Recommended default: **15 minutes** unless a real Sales workflow demands tighter.

### 8.3 Architecture questions — for Atlas + the team to plan in the build wave

Technical decisions the team makes once the business answers in §8.2 land.

**Revised 2026-05-15 to reflect the HubSpot [Webhooks Journal](https://developers.hubspot.com/docs/api-reference/latest/webhooks-journal/guide) pull pattern** (see §12 for the architectural-update rationale). The original push-webhook questions (public Apex REST endpoint exposure, HubSpot signature validation) no longer apply and have been dropped.

1. **Subscription configuration** — created via the `/webhooks-journal/subscriptions/2026-03` endpoint. Which CRM event types do we subscribe to? Recommended starting set: `contact.creation`, `contact.propertyChange`, `contact.deletion`, plus the marketing engagement event types HubSpot exposes. Per-subscription decisions: which `propertyName` filters (e.g., `company` for job changes; `email` for cross-domain identity).
2. **Scheduled-job poll cadence** — how often does the SF scheduled job hit `GET /webhooks-journal/journal/2026-03/{offset}`? Trade-off: lower interval = fresher SF data + more callouts; higher interval = leaner ops but Sales sees stale signals. Iris read: **15 min default**, configurable via Custom Metadata or Custom Setting. Confirms against the §8.2 Q9 staleness tolerance.
3. **Offset persistence** — where does SF store `currentOffset` (UUID returned by each Journal poll, e.g. `0197f5c0-4d9b-7932-83ec-06d56430c359`)? Options: (a) **Custom Setting** (`Engagement_Settings__c.Journal_Offset__c`) — fastest, no SObject ceremony, fine for one journal; (b) **new `Integration_Journal_Cursor__c` SObject** — supports tracking multiple journals (Contact, Lead, Company, Deal) independently; supports audit history. **Atlas pair** — see §8.5 fork additions. Iris read: SObject. Single Custom Setting row paints us into a corner the moment we want Company or Deal journals.
4. **Failure handling mid-batch** — when the per-contact callback to `GET /crm/objects/2026-03/contacts/{id}` fails partway through a journal page, do we (a) skip the failing record and log + advance offset; (b) requeue the offset for the next poll; (c) abort the batch and leave offset unchanged for retry? Default recommended: **(a) skip + log into the existing Error Queue, advance offset.** The 3-day journal retention window means a transient failure auto-replays via the next poll; an offset-stuck pattern means we miss everything new behind it.
5. **Snapshot baseline for initial backfill** — HubSpot's `/webhooks-journal/snapshots/2026-03` provides point-in-time CRM-object exports. For the initial Phase 4 backfill (load every existing HubSpot Contact into MI baseline), do we use a snapshot or iterate the live Contacts API? Snapshots are async + bulk-friendly; the live API is rate-limited per-call. Recommended: **snapshot for initial backfill; journal for ongoing**.
6. **OAuth scope grants** — 5 webhook-journal scopes required: `developer.webhooks_journal.read`, `developer.webhooks_journal.subscriptions.read`, `developer.webhooks_journal.subscriptions.write`, `developer.webhooks_journal.snapshots.read`, `developer.webhooks_journal.snapshots.write`. Plus object-specific reads (e.g., `crm.objects.contacts.read`). Pre-approved in the Zelis HubSpot portal? See §10.4 Q new-2.
7. **Email domain field on Account** — does Zelis already have one (a parsed `Website` formula? An explicit `Email_Domain__c`?), or do we ship a new field + populate via Flow / batch on existing Accounts? Audit Zelis Account first.
8. **Domain extraction utility — `extractDomain(email)`** — where lives? `Utilities.cls` (personal lib, off-limits during Zelis work hours per the IP-protection rule) or a new feature-scoped `EngagementDomainMatcher.cls` in the engagement folder. Recommended: feature-scoped.
9. **Performance: SOQL pattern for "all touches matching email-domain X"** — current touches have `Email_At_Touch__c` as raw text; matching `LIKE '%@acme.com'` is a non-indexed scan. Likely need a derived `Email_Domain__c` field on `Engagement_Touch__c` populated at ingestion + indexed for fast filtering.
10. **Auto-ACR creation timing** — synchronous inside `EngagementTouchTriggerHandler` (post-Journal-write)? Async via Platform Event into a queue? Batch on a nightly cycle? Synchronous = freshest but loads the trigger context; async = clean separation, slight lag. With pull-not-push, sync within the Journal-poll scheduled job is also viable since latency is already cadence-bounded.
11. **Shadow Account modeling** — new `Shadow_Account__c` SObject (own record, promotable to real Account)? Or virtual — just a domain-level rollup query exposed in the panel without persisting anything? Modeling has audit + share benefits; virtual is simpler.
12. **Reparent handler generalization** — the `LeadEngagementReparentHandler` pattern (sync, same-transaction, FLS-gated, idempotent) is the right template for "shadow domain becomes real Account → reparent shadow touches." Likely a new `ShadowAccountPromotionHandler` modeled on it.
13. **Visibility under OWD-Private** — shadow touches whose Account doesn't exist yet have no parent sharing context. Need a default visibility model: Marketing permset only? Org-wide read for Marketing_Influence_View holders? Owned by integration user? This is a Sage question.
14. **Third DTO shape — `DomainEngagementDTO`?** Multi-contact rollup under a domain anchor; combines the multi-row pattern of `EngagementDTO` with the anchor concept of `AnchorEngagementDTO`. Or extends `AnchorEngagementDTO` with a `nestedContacts[]` collection. **Atlas pair needed** — see §8.5 fork.
15. **LWC scope expansion** — does `engagementPanel` keep growing its `recordContext` enum (`Account|Opportunity|Contact|Lead|Domain`)? Or does the Domain scope want its own LWC (`engagementDomainPanel`) because the render shape is genuinely different? Reasonable case for either.
16. **Identity resolution rules CMDT** — the existing `Touch_Routing_Rule__mdt` framework probably wants a "domain match" rule type alongside the email/name/phone match rules. Extension, not rewrite.

**Dropped from the original §8.3 list** (push pattern only; no longer applicable under Journal pull):

- ~~Public Apex REST endpoint exposure for HubSpot push~~ — outbound-only callouts under Journal pull
- ~~HubSpot signature validation on inbound webhooks~~ — no inbound webhooks; SF authenticates outbound via Named Credential + OAuth

### 8.4 Phasing — how this relates to the basic Lead+Contact panel

This expansion is **explicitly not Phase 1.** The basic Lead/Contact MI panel from §§1-7 ships first as the next ticket. This domain-attribution expansion is **Phase 4** (or its own dedicated feature line). Naming it now keeps it out of the Phase 1 scope discussion.

The one thing Phase 1 must do to make Phase 4 cheap: ensure the recommended `AnchorEngagementDTO` shape leaves room for a future `DomainEngagementDTO` without forcing a rewrite. Concretely — keep `AssetEngagement` as a standalone reusable inner class (or top-level class), not nested-private inside `AnchorEngagementDTO`. Both Phase 1 and Phase 4 DTOs then share the per-asset breakdown primitive cleanly.

### 8.5 Architectural fork added by this expansion

**§8.3 Q8 — third DTO shape (`DomainEngagementDTO`).** This is Atlas territory. The Domain scope is genuinely a third pattern, not a variant of the existing two:

- `EngagementDTO` (today) — multi-row, one per engaged Contact, scoped to Account or Opportunity
- `AnchorEngagementDTO` (recommended for Phase 1) — single-row, one anchor (Contact or Lead), with per-asset breakdown
- `DomainEngagementDTO` (Phase 4) — multi-row aggregation under a domain anchor, possibly mixing known-Contacts + shadow-touches in the same render, with an explicit "promote to structured" affordance

Atlas to weigh in (when Phase 4 reaches planning, not now): is this three distinct shapes living side by side, or does it call for a common abstract base (`EngagementResult` with subclasses) that all three implement? My read: keep them parallel and distinct — calling-card readability beats inheritance cleverness — but Atlas may see further than I do on extension cost.

— Iris

---

## 9. Job-change signal detection

**Status:** Captured for the record. Same scope as §8 — **not Phase 1.** Likely Phase 5 or its own dedicated feature line, building on the domain-attribution foundation from §8 (you need stable cross-domain person identity before you can reliably detect a job change). Captured now so the model leaves room for it.

The use case: Joe Patel works at Acme Corp (`joe.patel@acme.com`). MI sees touches under Acme via Joe's Contact. Six months later Joe moves to Globex Corp (`joe.patel@globex.com`). The MI panel on the OLD Acme account still shows Joe's old engagement. Joe's NEW Globex engagement lands one of three ways:

- **(a)** Fresh Contact under Globex Account — Joe-as-two-people in CRM. Most common today.
- **(b)** Lead under Globex — Joe-as-new-prospect. Common when HubSpot doesn't recognize Joe across domains.
- **(c)** Update to Joe's existing Contact (AccountId → Globex) — Joe-followed-to-his-new-job. Rare today; requires HubSpot cross-domain identity.

What MI should signal: **"Joe is at a different company now."** This is a high-value signal for both sides:

- **Acme Account Owner** — the champion is gone; in-flight deal may be at risk; pipeline review.
- **Globex Account Owner / BDR** — warm intro available; Joe was already a customer at Acme; fast-track outreach.

### 9.1 Five conceptual threads

**Thread 1 — Signal sources for job changes.** Where does MI learn that Joe moved? Candidate sources, ranked by reliability:

- **HubSpot lifecycle data** — if HubSpot syncs LinkedIn or Clearbit enrichment, it captures `current_company` transitions. HubSpot's contact properties may carry `previous_company`, `previous_title`, `company_change_date`. Highest reliability if Zelis pays for the enrichment SKU.
- **Email-domain change on inbound touch** — Joe was `joe.patel@acme.com` for two years of touches; suddenly a touch arrives as `joe.patel@globex.com` with the same first+last name. Heuristic match → probable job change. Medium reliability — name collisions exist.
- **Manual update by a sales rep** — rep edits Contact.AccountId on Joe's Contact and notes the old employer. Highest reliability but human-dependent.
- **HubSpot Vid persistence** — if HubSpot maintains a stable identifier across email changes for the same person, the inbound touch arrives with the same Vid but a new email/domain → unambiguous signal.
- **Out-of-band sources** — LinkedIn Sales Navigator alerts, news mentions, internal references. Out of scope for MI ingestion; manual capture only.

**Thread 2 — Display patterns.**

- **OLD Account panel** — Joe's row shows a "Left company [date] → now at Globex" badge; row optionally strikes-through; engagement history remains visible (it happened, it counts for Acme's attribution). Sort priority demotes.
- **NEW Account / Contact panel** — "Previously engaged at Acme as [role]" attribution chip; on hover, the historical Acme engagement summary. BDR sees: "this person is warm — here's what they engaged with before."
- **Contact panel** — job-change timeline event slotted into the asset-detail view. Same date-sorted feed; a different event-type icon.
- **Notification surface** — Chatter mention, Bell notification, or Task creation depending on §9.2 Q5.

**Thread 3 — Data model.** Three modeling options:

- **(A) New SObject `Contact_Employment_History__c`** — child of Contact with `Previous_Account__c`, `Start_Date__c`, `End_Date__c`, `Title_At_Time__c`. Full history; supports multi-hop ("Joe was at Acme, then Globex, now Initech"). Cleanest model; highest build cost.
- **(B) Two fields on Contact (`Previous_Account__c` lookup + `Previous_Account_Through__c` date)** — only the most recent prior employer. Loses history beyond one hop. Cheapest to ship; sufficient for the dominant use case.
- **(C) HubSpot owns the history, SF displays latest only** — Contact has `Current_Employer__c` (today's Account) + a "View employment history" callout that opens HubSpot. Lowest SF data footprint; depends on HubSpot integration robustness.

Iris recommendation: **(A) `Contact_Employment_History__c`**. The model is honest, supports the multi-hop reality (people change jobs more than once), and feeds cleanly into both Acme-Account-panel ("Joe was here from X to Y") and Globex-panel ("previously at Acme") rendering. Atlas pair on the storage cost / share model tradeoff — see §9.4 fork.

**Thread 4 — HubSpot data contract.** Critical input. The question David needs answered by the customer (data steward at Zelis):

- What does HubSpot push on a detected job change? A custom property change event? A lifecycle transition?
- Does HubSpot carry `previous_company`, `previous_title`, `company_change_date` as standard or enrichment-tier properties?
- Is there a Vid-style stable identifier that survives email changes? (HubSpot's `vid` / contact ID is supposed to.)
- Does Zelis license the enrichment SKU that powers job-change detection in HubSpot? If no — Thread 1's first bullet drops off.

This is §10 material; captured here as the cross-link.

**Thread 5 — Sales-action implications.** When MI detects a job change, what does the system DO besides display a badge?

- **Notify OLD Account Owner** — Chatter post, email digest, Bell notification, or a Task. "Joe Patel left Acme on [date] — review open opportunities for champion risk."
- **Notify NEW Account Owner** — same channels. "Joe Patel joined Globex on [date] — previously engaged 23 times at Acme. Warm intro available."
- **Auto-create artifact** — a Task on the OLD Opportunity (risk review)? A Lead or Opportunity on Globex if no Account-Owner yet exists? Or just surface and let the human decide?
- **Pipeline implications** — does an Open Opportunity at Acme with Joe as primary OCR get flagged as "champion risk"? Does Joe's OCR auto-flag with a "former employee" status?

Strong opinion: **surface + notify, do NOT auto-create artifacts.** Auto-creation pollutes pipeline reporting and removes the human judgment call. Let the rep decide whether the signal is worth a Task / Opp / Lead. Sales leadership may override but that's the default position.

### 9.2 Stakeholder questions — for David's customer / Marketing Ops / BDR / Sales Enablement leadership

1. **Job-change signal value — does Sales actually act on it, or is it noise?** Particularly on the OLD-Account side: when a champion leaves, does the AE ACTUALLY review the deal, or does the rep already know via direct relationship and the badge is redundant?
2. **Notification model** — Chatter / Bell / email / Task / nothing? Same setting org-wide, or per-Persona-PSG configurable? Different settings for OLD-Account vs NEW-Account?
3. **Auto-creation appetite** — surface-only, or auto-create Tasks / Leads / Opportunities on detected job changes? Marketing leadership call.
4. **OLD-Account history retention** — when Joe leaves Acme, does Joe's historical engagement on Acme stay visible forever, or hide after N months? (My read: keep visible — it counts for Acme's attribution-to-date even if Joe's gone.)
5. **Champion-risk on Open Opportunities** — when Joe was primary OCR on an Open Opp at Acme and Joe leaves, does the Opp get flagged automatically? Or just the panel badge?
6. **Cross-employer signal aggregation** — should Joe's lifetime touches (across Acme + Globex + future employers) roll up to a Person view somewhere, or stay scoped per-Account-per-job? Probably the latter for normal MI use but Marketing may want a "lifetime engagement" report for ABM.

### 9.3 Architecture questions — for Atlas + the team

1. **Identity resolution rule for cross-domain match** — when a touch arrives with a new email-domain but matches an existing Contact by name + HubSpot Vid, the resolution writes to the EXISTING Contact (updating AccountId? or leaving AccountId and flagging?) — or creates a NEW Contact under the new Account? `IdentityResolutionService` extension; needs a new resolution branch.
2. **Storage model — (A) / (B) / (C) from Thread 3** — Iris recommends (A). Atlas final.
3. **`Contact_Employment_History__c` sharing** — OWD Private inherited from Contact? Or its own sharing model? Visibility for the user viewing the OLD Account vs the NEW Account is asymmetric.
4. **Notification dispatch** — Platform Event with subscribers, or direct Chatter/Task DML in the resolution service? PE preferred for loose coupling.
5. **Trigger or batch detection?** Some job changes detected synchronously on inbound touch (domain-change heuristic); some detected from HubSpot scheduled sync. Two paths converging on the same write?
6. **Reparent semantics on job change** — DO touches reparent like Lead-conversion does, or do they stay anchored to the original Contact + Account (preserving historical truth)? Strong recommend: **stay anchored.** Touches happened at Acme; they belong to Acme historically. Globex sees them via the employment history link, not by reparenting.
7. **Champion-risk flag on Opportunity** — new field on Opportunity? New formula? New `Opportunity_Risk__c` SObject? Out of scope for MI core but the data model has to leave the hook.
8. **HubSpot inbound contract extension** — `EngagementInboundRest.InboundEvent` may need new fields: `hubspot_vid` (stable identifier), `previous_email`, `previous_company`, `company_change_at`. Backwards-compatible additions to `InboundEvent` shouldn't break existing payloads.

### 9.4 Architectural fork added by §9

**Thread 3 — storage model.** Atlas pair when Phase 5 reaches planning. Options A vs B vs C have meaningfully different cost profiles:

- (A) full history SObject — clean model, ~5-8 days to ship the SObject + triggers + LWC display
- (B) two fields on Contact — fast, ~1-2 days, loses multi-hop history
- (C) HubSpot owns it — cheapest, ~0.5 day SF-side, depends on HubSpot integration uptime

Iris recommends (A) for honesty; happy to be overruled by Atlas if extension cost is prohibitive or HubSpot already gives us (C) for free.

— Iris

---

## 10. HubSpot data brief — for David's customer conversation

**Audience:** David, prepping a meeting with the HubSpot data steward at Zelis. **Not for the dev team.**

**Goal:** confirm what data MI receives today, what it needs for the Phase 4 + 5 capabilities, and what gaps Zelis needs to fill on the HubSpot side before the next feature waves are buildable.

### 10.1 Assumption David is operating under

> "Let's assume we are getting the right data from HubSpot."

Translated to specifics: for MI's full vision (Phase 1 shipped + Phase 4 domain attribution + Phase 5 job-change detection) HubSpot must push:

- Every marketing engagement event (open, click, form-fill, webinar attendance, content download) with an `external_id`, `email`, `occurred_at`, asset metadata, and touch typing
- Events for contacts that have NO matching SF Contact / Lead (shadow touches)
- Stable cross-email person identifier (HubSpot Vid or equivalent)
- Enrichment data for current-company / previous-company / lifecycle-stage transitions
- Email-domain or company-domain as a discrete field (not just embedded in the email)

What's **shipped and consumed today** is in §10.2. What's **needed but not yet confirmed** is in §10.3.

### 10.2 Data fields MI consumes today (Phase 1 — already shipped)

Reverse-engineered from [`EngagementInboundRest.cls`](../../force-app/main/default/classes/engagement/EngagementInboundRest.cls). The HubSpot inbound REST receives this JSON shape per event (snake_case, JSON.deserialize maps to `InboundEvent`):

| Inbound JSON key       | SF field on `Engagement_Touch__c` | Required | Notes                                                                                                               |
| ---------------------- | --------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------- |
| `external_id`          | `External_Id__c`                  | **Yes**  | Upsert key; HubSpot must guarantee uniqueness + stability for idempotent re-delivery                                |
| `email`                | `Email_At_Touch__c`               | **Yes**  | Drives identity resolution to Contact/Lead/Account                                                                  |
| `occurred_at`          | `Occurred_At__c`                  | **Yes**  | DateTime; ISO-8601 string                                                                                           |
| `source_system`        | `Source_System__c`                | No       | Expected literal `"HubSpot"`; pickisl/free-text                                                                     |
| `source_event_type`    | `Source_Event_Type__c`            | No       | Raw API value (e.g. `EMAIL_OPEN`, `FORM_SUBMITTED`); mapped to display label via `Engagement_Picklist_Display__mdt` |
| `source_event_id`      | `Source_Event_Id__c`              | No       | HubSpot's native event ID (different from `external_id` — useful for cross-system debugging)                        |
| `asset_name`           | `Asset_Name__c`                   | No       | Human-readable name of the asset (whitepaper title, email subject, etc.)                                            |
| `asset_url`            | `Asset_Url__c`                    | No       | URL to the asset                                                                                                    |
| `topic_external_code`  | resolves to `Topic__c` Id         | No       | Looked up against `Touch_Topic__c.External_Code__c`; missing topic logs a warn, doesn't error                       |
| `campaign_external_id` | resolves to `Campaign__c` Id      | No       | Looked up against `Campaign.Name`; missing campaign silently skipped                                                |
| `touch_type`           | `Touch_Type__c`                   | No       | Phase 1 picklist value                                                                                              |
| `touch_subtype`        | `Touch_Subtype__c`                | No       | Phase 1 secondary discriminator                                                                                     |
| `persona`              | `Persona__c`                      | No       | Buyer persona classification (if HubSpot enriches)                                                                  |
| `intent_level`         | `Intent_Level__c`                 | No       | Intent scoring tier (if HubSpot enriches)                                                                           |

**Identity resolution** runs after parse, in `IdentityResolutionService.resolveAll()`. It writes:

- `Contact__c` — if email matches exactly one active Contact
- `Lead__c` — if email matches exactly one active non-converted Lead
- `Account__c` — derived from the resolved Contact's AccountId
- `Resolution_Status__c` — `Resolved` / `Ambiguous` / `NoMatch`

What David should tell the customer about what's already working: **Phase 1 is live. HubSpot pushes these 14 fields, MI ingests them, identity resolution matches against existing Contacts/Leads, and the panel surfaces engagement on Account and Opportunity record pages today.**

### 10.3 Data MI needs but may not yet receive

Mapped against Phase 4 + 5 capabilities:

| Capability (Phase)                                     | HubSpot dependency                                                                                                                                                                                                 | Confirmed today?                          |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------- |
| Domain anchoring (§8 Thread 1)                         | `email_domain` field on event, OR derivable from `email`                                                                                                                                                           | Derivable, no HubSpot change required     |
| Shadow touches (§8 Thread 2)                           | Events delivered even when no SF Contact match exists                                                                                                                                                              | **Unknown — ASK**                         |
| Auto-ACR on domain match (§8 Thread 3)                 | Originating `email` + `current_company` on the contact record                                                                                                                                                      | **Unknown — ASK**                         |
| Account-doesn't-exist case (§8 Thread 4)               | Events for unknown companies — does HubSpot send them?                                                                                                                                                             | **Unknown — ASK**                         |
| Multi-Account same-domain disambiguation (§8 Thread 5) | Per-event `company_id` or `account_external_id` to disambiguate                                                                                                                                                    | **Unknown — ASK**                         |
| Job-change signal (§9 Thread 1)                        | Detected via the `contact.propertyChange` event on the Webhooks Journal where `propertyName = 'company'`; supplemented by `previous_company` + `company_change_date` enrichment properties on the Contact callback | **Unknown — likely needs enrichment SKU** |
| Cross-domain person identity (§9 Thread 1)             | HubSpot Vid (stable contact ID) included on every event                                                                                                                                                            | **Unknown — ASK**                         |
| Anchor-reliability decay (future)                      | Channel-reliability score or signal-decay metadata per event                                                                                                                                                       | **Unknown — ASK**                         |
| Cross-domain person matching (§9)                      | Stable identifier surviving email changes                                                                                                                                                                          | **Unknown — same as Vid question**        |

The italicized ASKs are the §10.4 question list.

### 10.4 Questions David asks the customer

Numbered, scannable. David walks into the meeting with this list.

1. **Shadow touches** — does HubSpot send engagement events for contacts that have no matching SF Lead/Contact today? If yes, where do they currently land (Error Queue? Dropped?)? If no, can HubSpot be configured to send them?
2. **HubSpot Vid** — what's the Vid format, is it included on every outbound event, and is it persistent across email changes for the same person?
3. **Company / domain** — does each event carry a `company` field, a `company_id`, or `email_domain` as discrete fields? Or only the email, requiring SF-side parsing?
4. **Lifecycle transitions** — does HubSpot detect job changes (via LinkedIn / Clearbit / Zoominfo enrichment), and if so, how is the signal surfaced? Property change webhook? Lifecycle stage event? Custom property `company_change_detected_at`?
5. **Previous-company history** — does HubSpot retain `previous_company` history, and how many transitions back?
6. **Enrichment SKU** — does Zelis have the HubSpot enrichment add-on (LinkedIn / Clearbit / Zoominfo) that powers cross-employer identity? If no — Phase 5 job-change detection has a different cost profile.
7. **Event delivery completeness** — are ALL marketing events sent to MI, or only events tied to qualified/MQL contacts? (This is the difference between MI seeing the full funnel vs the SQL-and-below funnel.)
8. **Free-mail handling** — when HubSpot sees `joe@gmail.com`, does it carry separate enrichment for the person's actual employer (LinkedIn-sourced), or only the literal email domain?
9. **Account / company matching on HubSpot side** — does HubSpot match contacts to Companies internally, and can it send the HubSpot Company ID to SF so we can confirm match accuracy?
10. **Webhooks for property changes** — does HubSpot push property-change events (e.g. `current_company` changed) to MI as a discrete event type, or only roll-up engagement events?
11. **Field-level uniqueness guarantees** — is `external_id` actually unique-and-stable on the HubSpot side? Any history of HubSpot re-emitting the same event with a different external_id after data corrections?
12. **Sync cadence** — real-time webhooks, scheduled batch (every N minutes), or both? (Note: under the Journal pull pattern this becomes "what's our poll cadence" — driven by §8.2 Q9 staleness tolerance.)
13. **Webhooks Journal API availability** — is the Journal API enabled for the Zelis HubSpot portal? The Journal API has tier requirements; some HubSpot tiers don't expose it. If unavailable, we fall back to live CRM API polling (more rate-limited) or HubSpot signing up for a tier that supports it.
14. **OAuth scope grants** — are the 5 Journal scopes (`developer.webhooks_journal.read`, `.subscriptions.read`, `.subscriptions.write`, `.snapshots.read`, `.snapshots.write`) plus object-specific reads (`crm.objects.contacts.read` and any others we need) pre-approved on the Zelis HubSpot app, or do we need to request them?
15. **Journal retention window** — HubSpot's default is 3 days; some enterprise tiers can extend. What's the current window for the Zelis portal? Drives our failure-recovery margin: if a SF poll job is offline for 5 days, we lose the events older than the retention window and need a Snapshot replay to reconcile.

### 10.5 Points David covers in the conversation

The framing David walks in with:

> "Marketing Influence gives Sales visibility into engagement under the Account they're working. Today HubSpot pushes us 14 fields per event and we ingest, resolve, and display engagement on Account and Opportunity pages in real time.
>
> Our next two feature waves expand this: (1) **domain attribution** — recognize touches from `@acme.com` even when no individual contact is matched yet, so Sales sees company-level engagement before formal Lead creation; (2) **job-change signal** — when a known contact moves to a new company, both the old Account and the new Account get the right signal: champion-risk on one side, warm-intro on the other.
>
> Both waves depend on data we MAY already be getting from HubSpot — and may not. I have a 12-question checklist of what we need confirmed. Once we know what HubSpot is sending, we'll know which features ship near-term vs which need HubSpot-side configuration changes first."

David adjusts to his voice and slide style — that's a paragraph for him to read, not a slide.

### 10.6 Deliverable status

| Section                 | Filled in from codebase                                                                                                                         | Needs David / customer input                             |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| 10.1 Assumption         | Yes (Iris framing)                                                                                                                              | David confirms                                           |
| 10.2 Today's fields     | **Complete** — reverse-engineered from [`EngagementInboundRest.cls`](../../force-app/main/default/classes/engagement/EngagementInboundRest.cls) | Confirm with David that the as-shipped behaviour matches |
| 10.3 Phase 4+5 needs    | Complete — mapped from §8 / §9 threads                                                                                                          | Customer answers determine which are gaps                |
| 10.4 Customer questions | Complete — 12 questions ready                                                                                                                   | David edits / cuts to fit meeting time                   |
| 10.5 Talking points     | Iris draft — David rewrites in his voice                                                                                                        | David owns                                               |

— Iris

---

## 11. PowerPoint update implications

David's TODO captured: these expansions (§8 domain attribution, §9 job-change signal, §10 HubSpot brief) imply the customer-facing deck (`~/Documents/DWood Show*.pptx` per the slide-voice memory) needs new or revised slides covering (a) **what data MI receives** — the 14 fields from §10.2 framed as the input contract, (b) **what signals MI surfaces** — the panel features by record-page context (Account / Opp / Lead / Contact / Domain in priority order), (c) **how MI behaves when data is missing vs present** — graceful degradation story so the customer understands which features are gated on HubSpot completeness. David owns the deck update; the §10 customer brief feeds the data slides directly, and §9.1 Thread 5 / §8.1 Thread 4 feed the signal-action slides. Customer-facing language stays "Marketing Influence" per the slide-voice memory — not "Engagement Attribution."

— Iris

---

## 12. Architectural update — HubSpot Webhooks Journal (pull) supersedes push model

**Date:** 2026-05-15. **Surfaced by:** David. **Source:** [HubSpot Webhooks Journal API guide](https://developers.hubspot.com/docs/api-reference/latest/webhooks-journal/guide).

The §§8-10 baseline assumed a **push** integration: HubSpot calls a Salesforce-exposed `@RestResource` endpoint per event ([`EngagementInboundRest.cls`](../../force-app/main/default/classes/engagement/EngagementInboundRest.cls), which is what Phase 1 currently ships). The Webhooks Journal supersedes (or supplements) that pattern with a **pull** model: Salesforce schedules a job that polls HubSpot's journal API and walks an offset cursor. Phase 4 ingestion is being re-architected around it.

### 12.1 What changes architecturally

| Dimension          | Old (push)                                                    | New (Journal pull)                                                                                                                        |
| ------------------ | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Trigger            | HubSpot calls our SF Apex REST endpoint on each event         | SF scheduled job polls `GET /webhooks-journal/journal/2026-03/earliest` (then walks via returned `currentOffset`)                         |
| Public surface     | New Apex REST endpoint exposed externally                     | None — outbound-only callout from SF                                                                                                      |
| Replay             | Manual config; lost events re-pushed only if HubSpot re-emits | Automatic — 3-day retention window (default); SF can rewind to any offset within window                                                   |
| Failure recovery   | Push fails silently if SF endpoint is down                    | Self-correcting — next scheduled poll resumes from last persisted offset                                                                  |
| Rate control       | HubSpot's send rate (uncontrolled by SF)                      | SF's poll cadence (we own it)                                                                                                             |
| Auth model         | HubSpot signs requests; SF verifies signature                 | SF authenticates outbound via Named Credential + OAuth (5 webhook-journal scopes + object-specific reads)                                 |
| Object payload     | Full event body posted by HubSpot                             | Journal returns event metadata + object ID; **per-object callback to `GET /crm/objects/2026-03/contacts/{id}`** retrieves the full record |
| Offset format      | N/A                                                           | UUID — e.g. `0197f5c0-4d9b-7932-83ec-06d56430c359`                                                                                        |
| Bulk baseline path | N/A                                                           | Separate `/webhooks-journal/snapshots/2026-03` endpoint for point-in-time CRM exports                                                     |

### 12.2 What stays the same

- Full Contact data still requires a callback (`GET /crm/objects/2026-03/contacts/{id}`) — the journal entries are change metadata + object IDs, not the full record body. The Phase 1 field map in §10.2 still applies; what changes is _how_ SF retrieves those fields, not which fields are consumed.
- Subscription configuration still goes through HubSpot's Subscriptions API (`/webhooks-journal/subscriptions/2026-03`) — original §8.3 Q1 stands, tightened in the revised §8.3.
- DTO architecture from §8.5 (third `DomainEngagementDTO` shape) is unchanged — the data shape isn't sensitive to push-vs-pull at the ingestion boundary.
- Identity resolution (`IdentityResolutionService`) is unchanged; it operates on the resolved `Engagement_Touch__c` rows regardless of how they were ingested.

### 12.3 Phase 1 (today) coexistence

The currently-shipped `EngagementInboundRest` REST endpoint is **NOT being retired in this rev.** Two patterns can legitimately coexist:

- **Push retained** for low-latency / event-driven sources that want to write directly (other internal Zelis systems, future non-HubSpot integrations)
- **Journal pull** for HubSpot specifically, where the offset-driven replay + automatic recovery semantics are worth the cadence trade-off

Decision needed (§12.5 fork): does the team eventually deprecate the push REST endpoint once Journal pull is mature, or keep it as a parallel ingestion path? Recommended: **keep both** — they serve different source-system contracts.

### 12.4 New build streams (when Phase 4 reaches planning)

Concrete deliverables the Journal pattern adds:

| Stream                                                                                                                                  | Owner        | Days                                |
| --------------------------------------------------------------------------------------------------------------------------------------- | ------------ | ----------------------------------- |
| Named Credential + OAuth flow for HubSpot Journal scopes                                                                                | Atlas + Sage | 0.5-1                               |
| `HubSpotJournalPoller.cls` — scheduled Apex job; reads offset, calls journal, walks pages, persists new offset                          | Boomer       | 2-3                                 |
| `HubSpotContactFetcher.cls` — bulkified callback to `GET /crm/objects/2026-03/contacts/{id}` for each journal entry's referenced object | Boomer       | 1-1.5                               |
| Offset persistence (Custom Setting OR new `Integration_Journal_Cursor__c` SObject — see §12.5 fork)                                     | Atlas/Boomer | 0.5-1                               |
| `HubSpotJournalPollerTest.cls` — HttpCalloutMock for journal + contact endpoints; offset-advance / failure / retention-edge cases       | Pippa        | 1.5-2                               |
| Snapshot-baseline batch (initial Phase 4 backfill from `/snapshots`)                                                                    | Boomer       | 1-2                                 |
| Schedule cadence configuration (CMDT or Custom Setting)                                                                                 | Atlas        | 0.25                                |
| **Phase 4 ingestion-layer total**                                                                                                       |              | **~7-10 days, parallel-dispatched** |

This is **in addition to** the §6 Phase 1 estimate, and **in addition to** the §8 / §9 feature build streams. Phase 4 is meaningfully larger than the Phase 1 base because we're re-architecting the ingestion boundary.

### 12.5 Architectural fork added by §12

**Offset state shape — Custom Setting vs SObject.** Atlas decision when Phase 4 reaches planning.

| Option                                      | Pros                                                                                 | Cons                                                                                                                    | Iris read |
| ------------------------------------------- | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- | --------- |
| Custom Setting `Engagement_Settings__c`     | Zero new SObject; single-row hierarchy setting; cached by platform; fast             | Hard to track multiple journals (Contact + Lead + Company + Deal) independently; no audit history of offset progression |           |
| New SObject `Integration_Journal_Cursor__c` | Multi-journal support; audit history of offset advance; standard sharing; reportable | New SObject ceremony; record-level CRUD overhead on each poll                                                           | **Pick**  |

**Why SObject:** the moment Phase 4 grows beyond just the Contact journal — and §10.4 Q9 already hints at HubSpot Company matching, which means a Company journal too — the single-row Custom Setting paints us into a corner. The SObject cost is marginal (one record per journal, updated on each poll), and the audit history of "offset X advanced at time Y" is valuable for debugging stuck-cursor scenarios.

Atlas: confirm or counter when Phase 4 hits planning. The Phase 1 constraint to leave room for this: ensure the eventual journal-poller class isn't tightly coupled to its offset-store implementation (DI / interface seam from day one, per `IEngagementService` pattern).

### 12.6 New questions to push back at David (Journal-pattern-specific)

These questions only arise because of the pull model — they weren't on the table under push:

1. **HubSpot tier confirmation** — does Zelis's HubSpot subscription tier expose the Webhooks Journal API at all? Not all tiers do. If the answer is "no," Phase 4 has a different cost profile (live CRM API polling, more rate-limited, no automatic replay). David needs to ask.
2. **OAuth app provisioning** — who owns the Zelis HubSpot OAuth app? Is there an existing connected app we extend, or do we provision a new one for MI? Sage involvement on auth governance.
3. **Storage of refresh token + secret** — Named Credential with stored-credential type? Or external credential pattern with custom callout adapter? Sage call.
4. **Schedule ownership** — when SF runs a scheduled job hitting HubSpot every 15 min, who is the "running user" for those callouts? Integration user with its own permset (`Engagement_Attribution_User` already exists per the Phase 1 inbound REST header comment) or a dedicated `MI_Integration_Journal_User`?
5. **Production rollout strategy** — when we cut over from "push-only" (Phase 1 today) to "pull + push coexistence" (Phase 4), do we shadow-run both for a window to confirm parity, or hard-cut on a date? Implications for both data hygiene and customer comms.
6. **Customer-facing implications for the deck** — David's PowerPoint update (§11) needs a slide on "how MI gets data from HubSpot" — and the answer changed from push to pull. The slide-rewrite cost is low, but the customer-conversation framing changes: it's now "we pull from HubSpot on a cadence you can configure" rather than "HubSpot pushes to us." That's a different sale.

— Iris

---

## 13. Platform Events — where EDA fits in the MI architecture (and where it doesn't)

**Date:** 2026-05-15. **Surfaced by:** David asking whether Event-Driven Architecture is the right fit for the work in §§8-12. **Atlas's read** (paired): yes for cross-cutting, cross-system, multi-subscriber concerns; **no** for intra-Apex synchronous single-transaction flows.

This section names exactly which MI concerns become Platform Events, which stay direct method calls, and why. The pattern is **already proven in this org** — CSI-7162's [`Jira_Push_Request__e`](../../force-app/main/default/objects/Jira_Push_Request__e) + [`JiraPushService.cls`](../../force-app/main/default/classes/JiraPushService.cls) + [`JiraPushDispatcher.cls`](../../force-app/main/default/classes/JiraPushDispatcher.cls) + [`Jira_Push_Object__mdt`](../../force-app/main/default/objects/Jira_Push_Object__mdt) ship today. Phase 4 inherits that shape rather than inventing a new one.

### 13.1 Why EDA fits some of this work

Four reasons EDA is the right call for the cross-cutting Phase 4 / Phase 5 concerns:

1. **Decoupling** — the publisher doesn't know or care which subscribers exist. When a touch resolves to a Contact, the publisher fires `Contact_Identified__e` once; subscribers (orphan-touch re-resolver, signal router, auto-ACR creator, panel refresh) react independently. Adding a sixth subscriber doesn't touch the publisher.
2. **Multi-subscriber** — most of the Phase 4 / Phase 5 business signals have N downstream cascades. EDA is the only pattern that scales cleanly past "1-2 hardcoded consumers."
3. **Audit trail** — every published event is logged via the dispatcher pattern; `API_Exception_Log__c` captures failures with the transaction Id. Direct method calls don't leave that trail.
4. **Pattern already proven** — CSI-7162's PE stack is in production. The `alreadyPublished` static Set ([`JiraPushService.cls#L39`](../../force-app/main/default/classes/JiraPushService.cls)), the `PublishAfterCommit` configuration, the dispatcher's group-by-Source_Object bulkification ([`JiraPushDispatcher.cls#L186`](../../force-app/main/default/classes/JiraPushDispatcher.cls)) — these are battle-tested. Phase 4 instantiates them N more times for N more events.

### 13.2 Events to publish

| Event                               | Publishes when                                                                                                                                                         | Subscribers                                                                                                                     | Why EDA                                                                                                     |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `Contact_Identified__e`             | A touch resolves to a Contact (sync, from `IdentityResolutionService`), OR a Contact arrives via HubSpot Journal poll (async)                                          | Orphan-touch re-resolver, signal router, auto-ACR creator, panel refresh                                                        | Multi-consumer; new consumers add without touching publisher                                                |
| `Account_Resolved__e`               | New Account created in SF, OR an orphan touch's domain matches an existing Account                                                                                     | HubSpot Contact backfill (outbound callout), orphan touch re-anchor, account-hierarchy traversal                                | Decouples "Account exists" signal from the N downstream cascades                                            |
| `Person_Job_Change_Detected__e`     | Journal poll detects a `contact.propertyChange` where `propertyName = 'company'` (§12 + §10.3)                                                                         | Old Account champion-loss flag, new Account/Lead creation, warm-intro signal, signal decay on the old side + rebuild on the new | Cross-cutting business signal — multiple consumers (sales notifications, CRM updates, reporting)            |
| `Touch_Ambiguous__e`                | An incoming touch's email-domain matches multiple Accounts (subsidiary / agency / generic-domain edge case from §8.1 Thread 5)                                         | Reviewer queue insert, Account-Hierarchy parent-lookup, CMDT-driven priority resolver                                           | The §8 multi-Account-same-domain disambiguation — naturally async                                           |
| `Lead_Converted__e`                 | Lead conversion fires (today's [`LeadEngagementReparentHandler.handleAfterUpdate`](../../force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls)) | Touch reparent subscriber, signal-fire subscriber, future Phase 4 / Phase 5 subscribers                                         | Cleanly separates the trigger handler from the N reparent/signal concerns — today they're all in one method |
| **existing** `Jira_Push_Request__e` | CSI-7162 — Opp qualifying-field change                                                                                                                                 | [`JiraPushDispatcher`](../../force-app/main/default/classes/JiraPushDispatcher.cls) → JCFS outbound callout                     | Already shipped; reference implementation for the pattern                                                   |

### 13.3 Where EDA is overkill / wrong fit

Atlas's pushback: not everything we're building should be a PE. Naming the cases where EDA is the wrong call:

| Subject                                                                         | Why NOT EDA                                                                                                                                                                           |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| HubSpot Journal poll itself (§12)                                               | It's a scheduled SF batch, not an event publisher. Polling ≠ event-driven; it's pull-mode async. PE would just wrap the poll for no decoupling benefit                                |
| Sync happy-path touch insert + resolution-to-existing-Contact                   | Single-transaction flow with one consumer — PE adds latency + ceremony for zero decoupling value. The existing `IdentityResolutionService.resolveAll(touches)` direct call is correct |
| LWC `refreshApex` wire-getter pattern                                           | Already reactive at the LWC layer; PE round-trip would defeat the `best-practices/lwc.md` wire pattern. Use `refreshApex` after writes; don't fire a PE for "panel needs refresh"     |
| CMDT lookups (`Touch_Routing_Rule__mdt`, future `Domain_Account_Priority__mdt`) | Synchronous Apex against in-memory CMDT cache — millisecond operations. PE wrapping is pure overhead                                                                                  |
| Single-subscriber sync logic                                                    | If only one piece of code reacts to "X happened," call X's method directly. EDA's value is N consumers; with N=1, just call the method                                                |

The test: **"would I add a second subscriber in the next two phases?"** If yes → PE. If no → direct call.

### 13.4 Pattern requirements (lift from CSI-7162)

Every new MI PE follows the CSI-7162 contract. Verified against the actual implementation:

- **Recursion guard** — per-transaction static `Set<String>` keyed by `SObjectName:Id:ChangeType` to prevent re-fire within the same Apex transaction. Reference: `JiraPushService.alreadyPublished` ([line 39](../../force-app/main/default/classes/JiraPushService.cls)); the guard is checked at line 117 and added at line 120 of `JiraPushService`. Phase 4 events instantiate the same pattern per event type.
- **CMDT kill-switch** — Phase 4 introduces `Engagement_Event_Config__mdt` (see §13.5 fork) with an `Active__c` per event type. Failed-closed: events don't publish when `Active__c = false`. Mirrors `Jira_Push_Object__mdt` (one row per Source_Object, `Active__c` + `Source_Field_Set__c`).
- **PublishAfterCommit** — events publish only after the originating DML commits, so rollback doesn't fire phantoms. Configuration is on the PE definition itself; see `Jira_Push_Request__e` for the working example.
- **Per-event audit log** — failed publishes write to `API_Exception_Log__c` with the transaction Id. Reference: `JiraPushService` lines 162-166 wrap `EventBus.publish` and log per-result failures.
- **Dispatcher class per event** — `ContactIdentifiedDispatcher`, `AccountResolvedDispatcher`, `PersonJobChangeDetectedDispatcher`, etc. Each follows the `JiraPushDispatcher` shape: trigger fires → group events by `Source_Object` ([line 186](../../force-app/main/default/classes/JiraPushDispatcher.cls)) → bulk-dispatch with concrete typed lists.
- **DI seam for the publisher** — `JiraPushService` uses an `IEventPublisher` interface (line 58) backed by a `private class EventBusPublisher` (line 60) so tests inject a mock without DML. Every MI EDA service inherits this seam.

### 13.5 Atlas-side architectural forks added by §13

Two new forks. Both pair when Phase 4 reaches planning, not now.

**Fork A — CMDT shape: one CMDT per event type vs unified `Engagement_Event_Config__mdt`.**

| Option                                                           | Pros                                                                                   | Cons                                                  | Iris read |
| ---------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------- | --------- |
| One CMDT per event type (`Contact_Identified_Config__mdt`, etc.) | Each event has its own switches; clean isolation; per-event field schemas              | More CMDT objects to manage; harder admin UI overview |           |
| Unified `Engagement_Event_Config__mdt` (one row per event type)  | Single admin UI; simpler kill-switch overview; mirrors `Jira_Push_Object__mdt` exactly | Cross-event coupling on schema changes                | **Pick**  |

Iris leans unified for admin clarity and pattern-symmetry with `Jira_Push_Object__mdt`. Atlas overrule welcome.

**Fork B — Dispatcher shape: one dispatcher per event vs unified `EngagementEventDispatcher`.**

| Option                                              | Pros                                                                                                                                 | Cons                                                                       | Iris read |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------- | --------- |
| Per-event dispatcher (mirrors `JiraPushDispatcher`) | Fault isolation — one event type failing doesn't poison another; clean test scope; trigger-handler-per-PE pattern is platform-native | More files                                                                 | **Pick**  |
| Unified `EngagementEventDispatcher`                 | Fewer files                                                                                                                          | Single point of failure; harder to scope fault containment; harder to test |           |

Iris leans per-event for fault isolation. Same as CSI-7162's shipped pattern.

### 13.6 Cross-section update — additions to §8.3

The Phase 4 architecture questions in §8.3 should add two EDA-specific questions (not retroactively inserted into §8.3 to keep the commit narrative clean; tracking them here for the ticket-author to fold in):

- **Q17 (EDA)** — which PEs publish as **PUBLIC** platform events (cross-app subscribable, other Zelis features can listen) vs **PRIVATE** (only our MI subscribers)? Public events let other Zelis features react to MI signals (e.g., Marketing Cloud Account Engagement triggers off `Person_Job_Change_Detected__e`); Private keeps the surface tight and reduces governance review burden. **Iris read:** start Private for all, promote to Public per-event as cross-feature consumers are identified.
- **Q18 (EDA)** — Apex subscriber vs Flow subscriber for each PE? Flow is BA-editable and admin-friendly; Apex is testable, bulkified, and easier to version-control. **Iris read:** Apex for everything that touches data integrity (auto-ACR creation, reparent, signal-decay); Flow OK for notification-only subscribers (Chatter post, Bell ping) where bulkification doesn't matter.

### 13.7 Cross-reference to CSI-7162 — pattern continuity

The MI EDA pattern proposed here is the same pattern CSI-7162 already proves in production. [`JiraPushService`](../../force-app/main/default/classes/JiraPushService.cls) + [`JiraPushDispatcher`](../../force-app/main/default/classes/JiraPushDispatcher.cls) + [`Jira_Push_Request__e`](../../force-app/main/default/objects/Jira_Push_Request__e) + [`Jira_Push_Object__mdt`](../../force-app/main/default/objects/Jira_Push_Object__mdt) are the reference implementation. Phase 4 isn't inventing a new architecture — it's instantiating the existing pattern N more times for N more events. That dramatically reduces design risk and lets Boomer's team apply known-good code shapes (the `alreadyPublished` recursion guard, the `IEventPublisher` DI seam, the group-by-Source_Object dispatcher bulkification) without re-deriving them.

The discipline implications for Phase 4: every MI PE pull request gets reviewed against the CSI-7162 reference. Deviations get justified in the PR description. New patterns are not invented mid-build.

— Iris

---

## 14. Auto-OCR for company touches + opt-out impedance queue

**Status:** **Release 1 scope** per David 2026-05-16. Folds into the Phase 1 build, not a follow-on. Customer wants every engaged Contact from a company auto-added to the OCR on that company's Opportunities, with an opt-out path that requires the Sales rep to write a >= 10-character reason and submit to a Sales Operations review queue.

### 14.1 Five conceptual threads

**Thread 1 — Auto-OCR mechanic.** Trigger point: the existing [`EngagementSignalRouter`](../../force-app/main/default/classes/engagement/EngagementSignalRouter.cls) evaluation pass. When a touch routes through an `Account_Match` or `ACR_Same_Account_Topic_Match` rule (existing `Touch_Routing_Rule__mdt` rule types), the routing step ALSO evaluates each open Opportunity on the matched Account and auto-creates an OCR for the engaged Contact if one doesn't already exist. Reuses the [`addToOcrSafe`](../../force-app/main/default/classes/engagement/EngagementServiceImpl.cls) race-protection contract — same re-query-and-insert pattern, just called from the router instead of the LWC.

**Thread 2 — OCR sprawl risk.** A high-engagement deal could end up with 30-50+ OCRs. This is a real downside the customer needs to opt into knowingly. Two mitigations the architecture should leave room for:

- **Confidence-threshold gate** on auto-add (only auto-add if Touch_Routing_Rule's match-confidence is above N). CMDT-driven so admins tune per-rule.
- **Topic-relevance gate** (only auto-add if the touch's Topic is one of the Opp's active topics, mirroring the existing `getForOpportunity` topic filter at [`EngagementServiceImpl#L58`](../../force-app/main/default/classes/engagement/EngagementServiceImpl.cls)). Reduces sprawl by ignoring off-topic touches.

Default behaviour without these gates: auto-add for every Contact that routes against the Opp's Account. Likely too aggressive — recommend shipping with topic-relevance gate ON by default.

**Thread 3 — Opt-out impedance pattern (the modal).** When a Sales rep clicks "Remove from Deal Team" on the engagementPanel:

- Opens new modal `c/removeFromDealTeamModal` (sibling to existing `c/addToDealTeamModal`)
- Requires `Reason__c` Long Text input — VR enforces `LEN(TRIM(Reason__c)) >= 10`
- On submit: creates `OCR_Removal_Request__c` with `Status__c = 'Pending'`, does NOT delete the OCR
- Panel row immediately re-renders with "Removal pending review" badge + reason tooltip
- The rep is unblocked from their workflow (the OCR stays for now, the request is in flight)

This is the **impedance**: not friction-for-friction's-sake, but enough effort to ensure the removal is intentional and reviewable. Sales rep can't drive-by-delete an OCR.

**Thread 4 — Sales Operations approval queue.** New SObject `OCR_Removal_Request__c`:

| Field               | Type                | Notes                                                                                 |
| ------------------- | ------------------- | ------------------------------------------------------------------------------------- |
| `Opportunity__c`    | Lookup(Opportunity) | The Opp the OCR sits on                                                               |
| `Contact__c`        | Lookup(Contact)     | The Contact being proposed for removal                                                |
| `OCR_Id__c`         | Text(18) external   | Snapshot of the OpportunityContactRole Id; preserves the link if the OCR gets deleted |
| `Removed_By__c`     | Lookup(User)        | Defaults to running user                                                              |
| `Reason__c`         | Long Text (255)     | VR: `LEN(TRIM(Reason__c)) >= 10`, NOT(ISBLANK(Reason\_\_c))                           |
| `Status__c`         | Picklist            | Pending / Approved / Denied                                                           |
| `Reviewer__c`       | Lookup(User)        | Ops user who actioned                                                                 |
| `Reviewed_At__c`    | Datetime            | Set on status flip from Pending                                                       |
| `Approval_Notes__c` | Long Text           | Optional Ops note on decision                                                         |
| `Submitted_At__c`   | Datetime            | Defaults to NOW()                                                                     |

**On `Status__c` transition to `Approved`** — trigger handler calls `OpportunityContactRolesSelector.selectById` + DMLManager.deleteAsUser on the snapshotted `OCR_Id__c`.

**On transition to `Denied`** — no DML on OCR (it was never deleted); the panel row reverts to its normal "On Deal Team" rendering. Reason and decision stay logged on the Removal_Request record for audit.

**Thread 5 — Audit + pattern detection.** Every approval/denial logged with reason. Sales Ops runs a report on "OCR removals last 30 days by Sales rep" to spot patterns:

- One rep always removing the same persona (e.g., always removing Legal contacts) — signals either coaching opportunity or that Legal genuinely doesn't belong
- Repeated denials of one rep's requests — coaching signal
- Spike in removals on one Opp — could indicate the auto-add is sprawling on that deal specifically and a CMDT tuning is needed

### 14.2 Stakeholder questions — for Sales Operations leadership

1. **Review SLA** — how fast does Sales Ops commit to reviewing pending removal requests? 24 hours? Same day? End of week? Drives whether we need an "escalation" mechanic for stale Pending requests.
2. **Approved vs Denied policy framing** — what does "Approved" mean in policy terms? "Sales is right, this Contact shouldn't be on the deal team"? Or just "we agree to remove it but not necessarily that Sales's reason was valid"? Same question for Denied. Marketing this internally matters.
3. **Escalation on volume** — if a single Sales rep submits 10+ removals in a week, does that auto-escalate to the rep's manager for coaching? Or stays silent and only surfaces in the periodic report?
4. **Re-add after Denied** — if Ops denies a removal, can the Sales rep re-submit with a new reason? Or is one Denied final until something material changes? Iris read: allow re-submit but the prior Denied stays in audit trail.
5. **Bulk-approve UX** — Sales Ops will likely have a queue page (List View) and approve in batches. Do we need a custom bulk-approve LWC, or is the standard Mass-Action with a quick-action enough? Iris read: standard quick-action is enough for v1.
6. **Notify the Sales rep** when their request is Approved or Denied? Channel (Bell / email / Chatter)? Iris read: yes, Bell notification + optional email per the §15 notification rules.

### 14.3 Architecture questions — for Atlas + team

1. **Auto-OCR creation timing** — synchronous inside `EngagementSignalRouter` (post-routing, same transaction as the touch insert)? Async via Platform Event (`Contact_Identified__e` from §13 already exists)? Iris read: **async via PE**. Auto-OCR is a downstream cascade, not part of the routing-decision atomicity. Reuses `Contact_Identified__e` subscriber pattern from §13.2.
2. **Race protection** — `addToOcrSafe` already handles the "another transaction beat us to it" race. Reuse verbatim from the router subscriber; no new race logic needed.
3. **OCR_Removal_Request queue ownership** — Salesforce Queue or Group? Sales Ops likely wants a Queue (List View, Mass Action). Standard pattern.
4. **OCR_Removal_Request trigger handler** — new `OcrRemovalRequestTriggerHandler` on after-update extending the existing `TriggerHandler` framework; status-flip-to-Approved fires the OCR delete via DMLManager. Mirrors [`LeadEngagementReparentHandler`](../../force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls) shape.
5. **engagementPanel UX state** — the panel needs a new derived state per row: `pendingRemoval` boolean. Decorate path in [`engagementPanel.js#L201`](../../force-app/main/default/lwc/engagementPanel/engagementPanel.js) extends with `pendingRemovalReason` + tooltip rendering. Atlas + Coda coordinate.
6. **Permset additions** — Sales rep needs CREATE on `OCR_Removal_Request__c`; Sales Ops needs CREATE + UPDATE. New permset atom `Additional_Permissions_Marketing_Influence_OCR_Removal_Reviewer` or fold the reviewer perms into the existing `Power_User` tier. Iris read: new atom; reviewer is a distinct persona from Power User.
7. **Reopen-after-delete** — if Ops Approved a removal and the OCR is deleted, but later a new touch routes the same Contact back onto the Account: does auto-OCR re-create it? Two camps: (a) yes, the routing rule is the source of truth and a new touch is a new signal; (b) no, the Removal_Request acts as a permanent block list. Iris read: (a) — but the Removal_Request stays in audit so Ops sees the pattern.

### 14.4 Architectural fork added by §14

**Re-add policy after Approved-removal.** Iris recommends (a) — let the routing rule re-add if a new touch matches; the prior Removal_Request stays as audit. Atlas pair: confirm or counter. The alternative (b — permanent block list keyed on Contact+Opportunity) creates a different kind of complexity (block-list maintenance, stale-block-list cleanup) that may not be worth it.

---

## 15. Rules-engine-driven notifications + new-contact workflow

**Status:** **Release 1 scope** per David 2026-05-16. Folds into the Phase 1 build. David's framing: notifications on top events (job changes, new contacts, etc.) should be **rules-engine-driven and generic**, not bespoke per event type. New contacts are special because they drive a simple workflow.

### 15.1 Five conceptual threads

**Thread 1 — Notification as a rule-engine-fired action.** Extend the existing `Touch_Routing_Rule__mdt` (or add a sibling `Notification_Rule__mdt`) with action fields:

| Field                            | Type     | Purpose                                                                                                |
| -------------------------------- | -------- | ------------------------------------------------------------------------------------------------------ |
| `Fire_Notification__c`           | Boolean  | When true, a rule match produces a notification in addition to (or instead of) a routing signal        |
| `Notification_Recipient_Type__c` | Picklist | Account_Owner / Opp_Owner / Marketing_Ops / Custom_Queue / Submitting_User                             |
| `Notification_Template__c`       | Text(80) | Reference to a `Notification_Template__c` row (templated subject + body with merge fields)             |
| `Notification_Priority__c`       | Picklist | Low / Normal / High — drives the channel mix (High → email + Bell; Normal → Bell; Low → digest only)   |
| `Notification_Channels__c`       | Multi-pl | In_App / Chatter / Email / Slack / Mobile_Push — defaults from Priority but can be overridden per rule |

Iris recommendation: **sibling `Notification_Rule__mdt`** CMDT, not extension of `Touch_Routing_Rule__mdt`. Routing and notification are different concerns; CMDT-row reuse buys nothing if the field set diverges.

**Thread 2 — Delivery channels.**

- **Salesforce In-App Notification** (bell icon) — `Messaging.CustomNotificationType` API; cheapest, fastest, default for Normal priority
- **Chatter @mention** — `FeedItem` insert; good for collaboration handoffs ("AE → SDR, take a look at Joe")
- **Email** — only for High priority; **respect the no-real-emails-from-tests memory** — production email path goes through `buildXEmail()` step that returns the message without dispatch; tests assert on shape; never grant Single-Email permission to test users
- **Slack** — if Zelis has Salesforce-for-Slack; Platform Event subscriber bridge if so
- **Mobile push** — Salesforce Mobile App; piggy-backs on In-App Notification config

**Thread 3 — New-contact workflow.** When a touch arrives, IDs a brand-new Contact (auto-created via Phase 4 domain-attribution work from §8), and the new Contact matches a "Welcome Workflow Eligible" rule:

- Bell notification to Account Owner: "New Contact identified at Acme Corp — Joe Patel, Director of Procurement. Engaged 3 times in last 7 days."
- Auto-create Task assigned to Account Owner: "Reach out to Joe Patel — see Engagement panel for context"
- Surface in engagementPanel with a "New" badge (decorate path in [`engagementPanel.js#L201`](../../force-app/main/default/lwc/engagementPanel/engagementPanel.js))
- Optionally fire Chatter post in the Account record's feed

The "Welcome Workflow Eligible" rule is itself a `Notification_Rule__mdt` row with `Trigger_Event__c = 'Contact_Created_From_Domain'` + an Apex predicate (`HasMinimumEngagementCount` returning true at 3+ touches in 7 days).

**Thread 4 — Generic, not bespoke.** David's intent: the notification system needs to be GENERIC + extensible. New event types add a new rule + a new template, NOT new code. The CMDT pattern + the EDA subscriber pattern from §13 are the two extension points; the Apex code is generic — `NotificationRuleEvaluator` evaluates the rule set on each subscribed event, builds the `Messaging.CustomNotificationType` payload, and dispatches.

**Thread 5 — Pattern alignment with §13 EDA.** Notifications subscribe to the existing PE inventory from §13.2:

| PE                              | NotificationRule eval triggers when                                | Example rule                                                                                  |
| ------------------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| `Contact_Identified__e`         | New Contact created from domain match                              | Notify Account Owner — "New Contact at Acme: Joe Patel"                                       |
| `Person_Job_Change_Detected__e` | Journal poll detects `contact.propertyChange` propertyName=company | Notify OLD Account Owner ("champion gone"), NEW Account Owner ("warm intro available")        |
| `Account_Resolved__e`           | Domain-shadow Account materializes to real Account                 | Notify Marketing Ops — "Shadow domain @acme.com promoted to Acme Corp Account"                |
| `Touch_Ambiguous__e`            | Multi-Account same-domain ambiguity                                | Notify the Custom_Queue (`Marketing Ops Review`) — "Domain @bigagency.com matches 3 Accounts" |
| `Lead_Converted__e`             | Lead conversion                                                    | Notify Lead's previous Owner + new Opp Owner                                                  |

### 15.2 Stakeholder questions — for Sales / Marketing Ops / BDR leadership

1. **Channel preference per Persona** — does the IE Sales user want Bell-only, while Marketing Ops wants Bell + email digest? Per-Persona-PSG default channels, with per-user override? Iris read: yes, per-Persona defaults overridable per user.
2. **Recipient policy for unowned Accounts** — if an Account has no Owner (Owner = integration user), who gets the notification? Marketing Ops queue? Round-robin to sales-rep-on-call? Skip entirely?
3. **Snooze / mute rules** — can users mute notifications from a specific Account or for a window? Standard Bell-notification mute pattern works; confirm it's enough.
4. **Notification fatigue threshold** — if Acme generates 30 notifications in a day (heavy engagement spike), do we batch into a digest, or send every one? Iris read: per-rule batching threshold (CMDT field); default batch-after-5-in-1-hour.
5. **Escalation paths** — when a High-priority notification is unread for 24 hours, does it escalate (manager Bell ping)? Or just stay unread? Iris read: escalation is overkill for v1; revisit in v2.
6. **Off-hours behaviour** — Bell notifications fire instantly. Should they suppress / batch during nights and weekends? Iris read: respect user's Salesforce notification preferences; don't reinvent.

### 15.3 Architecture questions — for Atlas + team

1. **CMDT shape — sibling Notification_Rule**mdt or field-extension of Touch_Routing_Rule**mdt?** Iris recommends sibling.
2. **Template SObject** — `Notification_Template__mdt` (CMDT) or `Notification_Template__c` (regular SObject, admin-editable)? CMDT is deploy-only-edit; SObject is admin-runtime-edit. Customer likely wants runtime edit → SObject.
3. **NotificationRuleEvaluator class** — new feature-scoped Apex; subscribes to the §13 PE inventory; evaluates `Notification_Rule__mdt` rows; calls `Messaging.CustomNotificationType.sendNotification()` (Bell), `EmailService.buildAndQueue()` (Email), `ChatterPostService.post()` (Chatter). Same per-channel-dispatcher seam pattern as §13's `IEventPublisher`.
4. **Email path** — explicitly named: production path goes through `EngagementNotificationEmail.buildEmail(recipient, templateRow, mergeFields)` returning `Messaging.SingleEmailMessage`, with a thin `dispatch()` wrapper. Tests assert on shape of returned message. Per the no-real-emails memory.
5. **In-App Notification setup** — `CustomNotificationType` metadata records (e.g., `MI_Standard_Notification`, `MI_High_Priority_Notification`) deployed with the feature. Confirm Zelis sandboxes / prod don't already have a notification-type cap (org limit 50; usually not a problem but verify).
6. **Slack integration scope** — IF Zelis has Salesforce-for-Slack, an additional Platform Event subscriber bridges; otherwise out of scope for v1. David confirms.
7. **Task auto-creation pattern for new-contact workflow** — DMLManager.insertAsUser on a `Task` record. Owner = Account Owner. Subject + Description from `Notification_Template__c` merge fields. Standard pattern; no fork.

### 15.4 Architectural fork added by §15

**Template storage — CMDT vs SObject.** Iris recommends `Notification_Template__c` (SObject, admin-editable at runtime). CMDT requires a deploy for every template edit; customers don't tolerate that for notification text. Atlas confirms.

---

## 16. Draft-mode automations + propose-then-confirm pattern

**Status:** **Release 1 scope** per David 2026-05-16. Cross-cutting infrastructure — not bound to one feature. Customer needs the option to flag certain MI automations as "draft mode" — the system proposes an action, durably records the proposal, and a reviewer approves or denies before the action executes.

### 16.1 Conceptual model

**Thread 1 — `MI_Automation_Proposal__c` SObject.** Every MI automation that's customer-flagged-as-draft-mode creates a proposal record before acting:

| Field                 | Type           | Notes                                                                                                                    |
| --------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `Type__c`             | Picklist       | OCR_Auto_Add / Contact_Auto_Create / Account_Auto_Match / Job_Change_Update / ACR_Auto_Create / Shadow_Account_Promotion |
| `Source_Object__c`    | Text(80)       | The SObject that triggered the proposal (e.g., `Engagement_Touch__c`)                                                    |
| `Source_Record_Id__c` | Text(18)       | The triggering record's Id                                                                                               |
| `Proposed_Action__c`  | Long Text JSON | Serialized payload the action would execute if approved (target SObject, fields, values)                                 |
| `Status__c`           | Picklist       | Pending / Approved / Denied / Auto-Approved / Expired                                                                    |
| `Reviewer__c`         | Lookup(User)   | Set on review                                                                                                            |
| `Reviewed_At__c`      | Datetime       | Set on review                                                                                                            |
| `Approval_Notes__c`   | Long Text      | Optional reviewer note                                                                                                   |
| `Submitted_At__c`     | Datetime       | Default NOW()                                                                                                            |
| `Expires_At__c`       | Datetime       | Auto-Expired if not reviewed by this date; configurable per Type                                                         |
| `Confidence_Score__c` | Number         | The triggering rule's match-confidence; feeds auto-approve evaluation                                                    |

**Thread 2 — Per-automation draft-mode CMDT.** New `MI_Automation_Setting__mdt`:

| Field                    | Type      | Notes                                                                                                                       |
| ------------------------ | --------- | --------------------------------------------------------------------------------------------------------------------------- |
| `Automation_Type__c`     | Picklist  | Same picklist as Proposal.Type\_\_c                                                                                         |
| `Draft_Mode__c`          | Boolean   | When true → creates a Proposal; when false → executes directly                                                              |
| `Auto_Approve_If__c`     | Text(255) | Optional Apex predicate class name; if predicate returns true, auto-approve without manual review (e.g., `Confidence > 90`) |
| `Reviewer_Queue__c`      | Text(80)  | Queue Developer Name for the review queue                                                                                   |
| `Default_Expiry_Days__c` | Number    | Default expiry window in days (e.g., 7 — drop proposal if not reviewed in 7 days)                                           |
| `Active__c`              | Boolean   | Kill-switch per automation type                                                                                             |

**Thread 3 — Audit trail durability.** David explicitly said "remember each of those." Every proposal — Approved, Denied, Auto-Approved, Expired — is durable. Reports answer:

- "What would have happened if we'd been fully automated?" → COUNT Proposal WHERE Status = Auto-Approved + Approved
- "What did Sales Ops gatekeep?" → COUNT Proposal WHERE Status = Denied
- "What slipped through review?" → COUNT Proposal WHERE Status = Expired

**Thread 4 — Customer-easing slider.** The `Auto_Approve_If__c` predicate is the customer's slider: ship fully manual (no predicate, every proposal reviewed), ease into "auto-approve high-confidence + manual-review low-confidence" (predicate `Confidence >= 90`), eventually flip `Draft_Mode__c = false` per automation type when the customer trusts the system. **The architecture supports the trust journey, not just the endpoint.**

**Thread 5 — Pattern reuse with §14.** `OCR_Removal_Request__c` (§14) is one specific instance of the propose-then-confirm pattern. `MI_Automation_Proposal__c` (§16) is the generic version. **Fork below** — keep separate or unify?

### 16.2 Stakeholder questions

1. **Default Draft_Mode per automation type** — which automations ship Draft-Mode-ON by default, and which ship Draft-Mode-OFF? Iris read: ship ON for everything that creates or modifies a Contact / OCR / Account record; OFF for non-mutating signals (notifications, panel-rendering decisions).
2. **Reviewer assignment per type** — OCR_Auto_Add → Sales Ops queue; Contact_Auto_Create → Marketing Ops queue; Account_Auto_Match → Sales Ops; Shadow_Account_Promotion → Marketing Ops. Customer confirms the matrix.
3. **Expiry policy** — proposal auto-expires at N days unreviewed. Default 7 days. Customer confirms; per-type override via CMDT.
4. **Expired-proposal disposition** — when a proposal expires without review, what happens to the underlying action? (a) action drops, the system never executes it; (b) action auto-executes (assume-Approved); (c) action escalates to a fallback reviewer. Iris read: (a) — silent expiry, log and move on; reviewer-team-not-keeping-up isn't a reason to bypass review.
5. **Bulk-approve UX** — same question as §14.2 Q5. Likely same answer (standard quick-action).
6. **Denial reason required?** — VR requires `Approval_Notes__c` on Denied? Iris read: yes for Denied, optional for Approved.

### 16.3 Architecture questions

1. **Unified-or-separate SObject (the §16.4 fork)** — Atlas decides.
2. **Proposal-creation timing** — proposal record created BEFORE the would-be-action runs. If the automation is wired through an EDA subscriber, the subscriber's first step is "check Draft_Mode for this Type; if true → create Proposal + return; if false → execute directly". Pattern is uniform across all subscriber implementations.
3. **Auto-approve predicate invocation** — dynamic class instantiation. Same pattern as `RecordCleanupRule.Predicate_Apex_Class__c` already in use (see [`Record_Retention_Rule.Engagement_Touch_Old_NoOpenOpp.md-meta.xml`](../../force-app/main/default/customMetadata/Record_Retention_Rule.Engagement_Touch_Old_NoOpenOpp.md-meta.xml) — `Predicate_Apex_Class__c = KeepIfAccountHasOpenOpportunity`).
4. **Proposal-execution on Approved** — trigger handler on `MI_Automation_Proposal__c` after-update; on Status → Approved, deserializes `Proposed_Action__c` JSON and dispatches to the right executor (`OcrAutoAddExecutor`, `ContactAutoCreateExecutor`, etc.). Each executor is a small class with one job; the proposal record carries the JSON payload of args.
5. **Expiry batch** — `MIAutomationProposalExpiryBatch` daily scheduled job; finds Pending proposals past `Expires_At__c`; flips Status to Expired. Standard pattern.
6. **Reviewer permset** — new atom `Additional_Permissions_Marketing_Influence_Automation_Reviewer`. Grants CREATE + UPDATE on `MI_Automation_Proposal__c`; queue membership composes separately.
7. **engagementPanel surface** — when a Contact has a Pending Contact_Auto_Create proposal, the panel could show it with a "Proposed" badge (similar to §14's "Pending removal"). v1 may not need this; v2 surfaces.

### 16.4 Architectural fork added by §16

**SObject shape — `OCR_Removal_Request__c` + `MI_Automation_Proposal__c` separate (§14 + §16 distinct) vs unified `MI_Automation_Proposal__c` with `Type__c = 'OCR_Removal'` as one of the values.**

| Option                                                    | Pros                                                                                                                                          | Cons                                                                                                                                                                                | Iris read |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Separate SObjects (Removal_Request + Automation_Proposal) | Clean per-type schemas; different review semantics; Sales-removes-Ops-approves vs system-proposes-Sales-approves are honestly different flows | More SObjects; more triggers; more permsets                                                                                                                                         | **Pick**  |
| Unified `MI_Automation_Proposal__c` only                  | Fewer SObjects; one report, one queue page, one trigger                                                                                       | Conflates two genuinely different review-direction patterns; field-set bloat (OCR-removal needs Reason >= 10 VR; auto-add doesn't); generic schema obscures the intent of each flow |           |

Iris leans **separate.** The Sales-removes-Ops-approves flow (§14) has VR-on-Reason, a specific Sales-rep-as-submitter UX, and Ops-as-reviewer policy. The system-proposes-Sales-approves flow (§16) has auto-approve predicates, a JSON payload, and a different reviewer matrix. Forcing both into one SObject means the schema serves neither cleanly. Atlas: confirm or counter.

---

## 17. Generalized exception logging + generalized retention framework

**Status:** **Release 1 scope** per David 2026-05-16. Atlas reverses the earlier separate-SObject recommendation for trigger-error logging; we generalize instead. David's question — "we can reuse the API error log, and if we didn't generalize, we need to now, right?" — is correct. We generalize now.

### 17.1 Generalize `API_Exception_Log__c` → `System_Exception_Log__c`

**Why now:** Phase 1's Auto-OCR (§14), Notification Rule evaluator (§15), Proposal-executor (§16), HubSpot Journal poller (§12), and the §13 EDA dispatchers all log failures. Five new error-producing subsystems land in Release 1. Without generalization, we either (a) duplicate per-subsystem log SObjects — five more SObjects, five more triggers, five more retention rules — or (b) cram everything into `API_Exception_Log__c` whose name lies about its purpose.

**Migration story:**

1. Create new SObject `System_Exception_Log__c` with the same field set as `API_Exception_Log__c` + one new field `Log_Source__c` picklist (API / Trigger / Batch / Queueable / Scheduled / Future / Manual / EDA_Subscriber / Notification / Proposal_Executor)
2. **Dual-write window**: existing `Logger.logApiException` writes to BOTH `API_Exception_Log__c` AND `System_Exception_Log__c` (Log_Source = 'API'). New callers write only to `System_Exception_Log__c`. Window length: one release cycle.
3. Migrate any reports / dashboards / integrations pointing at `API_Exception_Log__c` to the new SObject during the window.
4. End of window: deprecate `Logger.logApiException` (still works, no-op write-back-compat), switch to `Logger.logException(source, ...)` as the single entrypoint.
5. Eventually delete `API_Exception_Log__c` (destructive change deploys after the window closes).

**Why new SObject + dual-write rather than rename in place:** rename in place breaks every existing report, dashboard, integration, and external-system reference. Dual-write lets us migrate consumers at their own pace. Two-week window is enough for most consumers; longer-tail integrations get explicit notification.

**Net new Logger surface:**

```apex
// Existing (preserved for back-compat during dual-write window)
Logger.logApiException(ex, className, methodName);

// New unified entrypoint
Logger.logException(LogSource source, Exception ex, String className, String methodName);
Logger.logException(LogSource source, String message, String className, String methodName);

// Convenience wrappers (delegate to logException)
Logger.logTriggerException(...);
Logger.logBatchException(...);
Logger.logQueueableException(...);
Logger.logEdaSubscriberException(...);
```

`LogSource` is an Apex enum mirroring the picklist. Convenience wrappers keep call sites readable.

**Header / comment voice (per the feedback memory):** the renamed/new SObject and its Logger entrypoints get rich header comments explaining the migration window so a developer picking this up cold understands why two log tables briefly exist.

### 17.2 Generalize the retention framework

**Already SObject-agnostic.** The existing [`Record_Retention_Rule__mdt`](../../force-app/main/default/objects/Record_Retention_Rule__mdt/Record_Retention_Rule__mdt.object-meta.xml) supports `SObject_API_Name__c`, `Age_Field_API_Name__c`, `Age_Threshold_Days__c`, `Predicate_Apex_Class__c`, `SOQL_Where_Clause__c`, `Field_Regex_Match__c`, `Action__c`, `Active__c` ([reference rule](../../force-app/main/default/customMetadata/Record_Retention_Rule.Engagement_Touch_Old_NoOpenOpp.md-meta.xml)). The batch framework ([`RecordCleanupBatch`](../../force-app/main/default/classes/retention/RecordCleanupBatch.cls), [`RecordCleanupContext`](../../force-app/main/default/classes/retention/RecordCleanupContext.cls), [`RecordCleanupRule`](../../force-app/main/default/classes/retention/RecordCleanupRule.cls), [`RecordCleanupScheduler`](../../force-app/main/default/classes/retention/RecordCleanupScheduler.cls)) drives off the rule rows. So 80% of the work David's asking for is already done.

**What's still needed** for log-table retention:

1. **Time-based unconditional retention rules** — for logs, the rule shape is simpler: "delete `System_Exception_Log__c` rows older than 90 days, no predicate, no where-clause filter, no regex." Existing rule shape supports this (leave Predicate_Apex_Class**c / SOQL_Where_Clause**c / Field_Regex_Match\_\_c blank); batch's null-tolerance needs verification.
2. **Per-Log_Source\_\_c retention rules** — admins want different retention windows per source. CMDT supports this today via `SOQL_Where_Clause__c = "Log_Source__c = 'API'"` for one rule + `Log_Source__c = 'Trigger'` for another. No schema change required.
3. **Soft-delete option** — current `Action__c` picklist has Delete. Add Soft_Delete value. New field `Soft_Delete_Field__c` (e.g., `Is_Archived__c`) gets set true rather than DML.deleteAsUser. For high-volume logs, soft-delete avoids storage-reclaim cost but keeps records queryable; hard-delete eventually runs on a longer cadence.
4. **Retention-rule priority for conflict resolution** — when two rules target overlapping records (one says "keep 90 days for source=API", another says "keep 30 days for source=Trigger"), most-restrictive-wins is the cleanest default. Add a `Priority__c` Number field for explicit overrides when admins need them. Iris read: ship with most-restrictive-wins default; add `Priority__c` field but only consult it when admins set non-null values.

**Pair with the existing future-ticket** `project-record-cleanup-framework` (memory) — the planned generalization of LogCleanup into a CMDT-driven SObject-agnostic retention framework already targets `salesforce-utilities` open-source. §17.2 adds log-source-specific rule shapes to that scope.

### 17.3 Architecture questions

1. **Migration path — rename SObject in place vs new SObject + dual-write window.** Iris recommends new SObject + dual-write (~2 week window). Rename in place breaks too many consumers.
2. **Retention-rule conflict resolution — most-restrictive default + Priority field for overrides.** Iris read: ship with most-restrictive default; Priority field is dormant unless admins set it.
3. **Soft-delete vs hard-delete per rule.** Per-rule choice via `Action__c` picklist extension. Soft-delete needs the target SObject to have a "soft-deleted" field; logs get `Is_Archived__c` Boolean.
4. **Batch null-tolerance verification** — confirm `RecordCleanupBatch` handles the "no predicate / no where-clause / no regex" rule shape cleanly. If not, one-line fix. Verification task before §17.2 builds.
5. **Logger API back-compat** — `Logger.logApiException` stays as a no-op-equivalent wrapper around `Logger.logException(LogSource.API, ...)` for the migration window. Deprecation comment in header per the change-log memory.

### 17.4 Architectural forks added by §17

**Fork A — migration path.** Iris recommends new SObject + dual-write. Rename-in-place is too disruptive.

**Fork B — retention conflict resolution.** Iris recommends most-restrictive-wins default + `Priority__c` field for explicit overrides. Atlas confirms.

**Fork C — soft-delete field design.** Add Soft_Delete value to `Action__c` + new `Soft_Delete_Field__c` text field on the rule CMDT. Atlas confirms.

---

## Architecture fork inventory (cumulative across the investigation)

Phase-tagged so the team knows when each fork demands a decision.

| Phase   | Section | Fork                                                                              | Iris recommendation                                         |
| ------- | ------- | --------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Phase 1 | §3.4    | DTO shape — reuse `EngagementDTO` half-populated vs new `AnchorEngagementDTO`     | New `AnchorEngagementDTO`                                   |
| Phase 1 | §14.4   | Re-add policy after Approved removal — routing-can-re-add vs permanent-block-list | Routing can re-add; Removal_Request stays as audit          |
| Phase 1 | §15.4   | Notification template storage — CMDT vs SObject                                   | SObject (admin runtime-editable)                            |
| Phase 1 | §16.4   | Proposal SObject — separate (Removal_Request + Automation_Proposal) vs unified    | Separate                                                    |
| Phase 1 | §17.4A  | Log migration path — rename in place vs new SObject + dual-write                  | New SObject + dual-write                                    |
| Phase 1 | §17.4B  | Retention rule conflict resolution                                                | Most-restrictive default + Priority field for overrides     |
| Phase 1 | §17.4C  | Soft-delete vs hard-delete shape                                                  | Per-rule via `Action__c` extension + `Soft_Delete_Field__c` |
| Phase 4 | §8.5    | Third DTO shape — `DomainEngagementDTO` parallel vs common abstract base          | Keep parallel and distinct                                  |
| Phase 4 | §12.5   | Journal offset state — Custom Setting vs SObject                                  | SObject (`Integration_Journal_Cursor__c`)                   |
| Phase 4 | §13.5A  | PE CMDT shape — per-event vs unified                                              | Unified (`Engagement_Event_Config__mdt`)                    |
| Phase 4 | §13.5B  | PE dispatcher shape — per-event vs unified                                        | Per-event (mirrors CSI-7162 `JiraPushDispatcher`)           |
| Phase 5 | §9.4    | Employment history storage — SObject vs 2-fields vs HubSpot-owned                 | New SObject `Contact_Employment_History__c`                 |

**Cumulative count: 12 architectural forks across the investigation. 7 of them now sit in Phase 1.**

— Iris
