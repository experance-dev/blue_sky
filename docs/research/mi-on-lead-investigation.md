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

### 8.3 Architecture questions — for Atlas + the team to plan in the build wave

Technical decisions the team makes once the business answers in §8.2 land.

1. **Email domain field on Account** — does Zelis already have one (a parsed `Website` formula? An explicit `Email_Domain__c`?), or do we ship a new field + populate via Flow / batch on existing Accounts? Audit Zelis Account first.
2. **Domain extraction utility — `extractDomain(email)`** — where lives? `Utilities.cls` (personal lib, off-limits during Zelis work hours per the IP-protection rule) or a new feature-scoped `EngagementDomainMatcher.cls` in the engagement folder. Recommended: feature-scoped.
3. **Performance: SOQL pattern for "all touches matching email-domain X"** — current touches have `Email_At_Touch__c` as raw text; matching `LIKE '%@acme.com'` is a non-indexed scan. Likely need a derived `Email_Domain__c` field on `Engagement_Touch__c` populated at ingestion + indexed for fast filtering.
4. **Auto-ACR creation timing** — synchronous inside `EngagementTouchTriggerHandler`? Async via Platform Event into a queue? Batch on a nightly cycle? Synchronous = freshest but loads the trigger context; async = clean separation, slight lag.
5. **Shadow Account modeling** — new `Shadow_Account__c` SObject (own record, promotable to real Account)? Or virtual — just a domain-level rollup query exposed in the panel without persisting anything? Modeling has audit + share benefits; virtual is simpler.
6. **Reparent handler generalization** — the `LeadEngagementReparentHandler` pattern (sync, same-transaction, FLS-gated, idempotent) is the right template for "shadow domain becomes real Account → reparent shadow touches." Likely a new `ShadowAccountPromotionHandler` modeled on it.
7. **Visibility under OWD-Private** — shadow touches whose Account doesn't exist yet have no parent sharing context. Need a default visibility model: Marketing permset only? Org-wide read for Marketing_Influence_View holders? Owned by integration user? This is a Sage question.
8. **Third DTO shape — `DomainEngagementDTO`?** Multi-contact rollup under a domain anchor; combines the multi-row pattern of `EngagementDTO` with the anchor concept of `AnchorEngagementDTO`. Or extends `AnchorEngagementDTO` with a `nestedContacts[]` collection. **Atlas pair needed** — see fork section below.
9. **LWC scope expansion** — does `engagementPanel` keep growing its `recordContext` enum (`Account|Opportunity|Contact|Lead|Domain`)? Or does the Domain scope want its own LWC (`engagementDomainPanel`) because the render shape is genuinely different? Reasonable case for either.
10. **Identity resolution rules CMDT** — the existing `Touch_Routing_Rule__mdt` framework probably wants a "domain match" rule type alongside the email/name/phone match rules. Extension, not rewrite.

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
