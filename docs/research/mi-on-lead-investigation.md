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

| Capability (Phase)                                     | HubSpot dependency                                                                | Confirmed today?                          |
| ------------------------------------------------------ | --------------------------------------------------------------------------------- | ----------------------------------------- |
| Domain anchoring (§8 Thread 1)                         | `email_domain` field on event, OR derivable from `email`                          | Derivable, no HubSpot change required     |
| Shadow touches (§8 Thread 2)                           | Events delivered even when no SF Contact match exists                             | **Unknown — ASK**                         |
| Auto-ACR on domain match (§8 Thread 3)                 | Originating `email` + `current_company` on the contact record                     | **Unknown — ASK**                         |
| Account-doesn't-exist case (§8 Thread 4)               | Events for unknown companies — does HubSpot send them?                            | **Unknown — ASK**                         |
| Multi-Account same-domain disambiguation (§8 Thread 5) | Per-event `company_id` or `account_external_id` to disambiguate                   | **Unknown — ASK**                         |
| Job-change signal (§9 Thread 1)                        | Lifecycle transition events; `previous_company`, `company_change_date` properties | **Unknown — likely needs enrichment SKU** |
| Cross-domain person identity (§9 Thread 1)             | HubSpot Vid (stable contact ID) included on every event                           | **Unknown — ASK**                         |
| Anchor-reliability decay (future)                      | Channel-reliability score or signal-decay metadata per event                      | **Unknown — ASK**                         |
| Cross-domain person matching (§9)                      | Stable identifier surviving email changes                                         | **Unknown — same as Vid question**        |

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
12. **Sync cadence** — real-time webhooks, scheduled batch (every N minutes), or both?

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
