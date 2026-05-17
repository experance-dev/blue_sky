# Sales Rep Guide — Engagement Intelligence Panel

The Engagement Intelligence panel sits on the right rail of every Account and Opportunity record page. It shows you **which people from this Account have been engaging with Zelis content** — even people who aren't on the Opportunity Deal Team yet. This guide covers what you'll see, how to read it, and the four actions you can take from it.

If you'd rather see the panel in action with a walkthrough, see [`DEMO.md`](./DEMO.md).

## What the panel shows

Open any Account or Opportunity record page. The panel appears top-right under the header.

**Header line:** `Engagement Intelligence — N engaged`. `N` is the count of distinct Contacts with at least one engagement touch in scope.

**On an Opportunity record**, the list partitions into two sections:

- **Deal Team — N on OCR** — Contacts who are already on the Opportunity's Contact Roles. Each row carries a green `✓ on team` pill.
- **Engaged — not on Deal Team · N** — Contacts who've engaged with content **relevant to this Opportunity's topic** but aren't on the Deal Team yet. This is the buying-committee gap — the people Marketing has but the AE hasn't met.

**On an Account record**, the list is flat — `People Engaged · N` — every Contact with any engagement on the account, regardless of which Opportunity.

## Anatomy of a row

Each row has:

| Element                                                  | What it tells you                                                                                                                                                                                      |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Avatar circle** with initials                          | Visual anchor. Color-coded for ACR contacts: blue tint for `Consultant` (e.g. Deloitte), gray for any other external ACR (e.g. an independent advisor).                                                |
| **Name (hotlink)** + title                               | Click → opens the Contact record. Hover for ~1 second → Lightning hovercard with their full record. Hover briefly → multi-line summary tooltip (touch count, topics, last-touch date, OCR/ACR status). |
| **Touch summary**                                        | `N touches · 6d ago` — total touch count and the relative time of the most recent.                                                                                                                     |
| **Topic chips**                                          | The top two topics this person has engaged with. `+ N more` if more than two.                                                                                                                          |
| **`✓ on team` pill** (Deal Team only)                    | They're on this Opp's OCR.                                                                                                                                                                             |
| **`Consultant` / `ACR` badge**                           | They're not a direct Account contact — they're attached via `AccountContactRelation`. Treat as ecosystem influence, not insider.                                                                       |
| **`+ Add` button** (Opportunity scope, not-on-team only) | Add them to the Deal Team. See below.                                                                                                                                                                  |
| **`×` dismiss button**                                   | Hide this person from your view until a new touch arrives. See below.                                                                                                                                  |

## Interpreting Deal Team vs Engaged — not on Deal Team

This is the headline. The `Engaged — not on Deal Team` section is what the panel exists for.

**Read it like this:** "Marketing has been talking to these people. The AE hasn't put them on the Deal Team. Either the AE doesn't know about them yet, OR they're not actually relevant to this deal."

Most of the time it's the first one. The CFO downloads a whitepaper, never books a meeting, never lands on OCR — but she's the one who'll sign off on the $850K decision. The panel surfaces her so the AE can decide whether to bring her in.

The list is **already filtered by topic** — only people who engaged with content relevant to this Opportunity's Topic show up on the Opportunity panel. So if Marcus Brown engaged with Payment Integrity content but the Opp is on Network Management, you won't see him on the Opportunity panel. You will see him on the Account panel.

## Action 1 — Add to Deal Team (`+ Add`)

Click `+ Add` on any row in `Engaged — not on Deal Team`.

A modal opens (`Add to Deal Team`):

1. **Role** (required) — pick from Decision Maker, Economic Buyer, Technical Evaluator, Champion, Influencer, Business User, Other.
2. **Make primary contact** (optional) — tick to set this person as the Opportunity's Primary OCR. Salesforce permits only one Primary per Opp — ticking this on a contact when another is Primary silently demotes the prior Primary.
3. **Opportunity** picker — appears only on the Account panel (the Opp panel already knows which Opp). Pick which Opp to add this person to.

Click **Add to Deal Team**. The modal closes. The panel refreshes. The contact moves from `Engaged — not on Deal Team` into `Deal Team` with the green `✓ on team` pill.

Behind the scenes a real `OpportunityContactRole` row is created — standard Salesforce reporting picks it up immediately.

### Race condition: "Already Added" modal

If another rep added the same contact between the time your panel rendered and the time you clicked Save, you'll see the **Already Added** modal:

> **Sarah Johnson** was already added to this Deal Team by **Mike Chen** at 11 May 2026 14:32. Would you like to view the OCR record?

Two buttons:

- **No** (default focus, also fires on Enter or Esc) — closes the modal. Your panel will refresh on its own next time you navigate back.
- **Yes, view OCR** — navigates to the OCR record.

No data loss. No error. The race protection is by design — see [`alreadyAddedModal`](../development/components/alreadyAddedModal.md) for the technical detail.

## Action 2 — Dismiss (`×`)

Click the small `×` on the right side of any row.

The row disappears from your view. A toast confirms: `<Name> hidden until a new touch arrives.`

Dismissal is **per-user, per-scope, and not permanent**:

- It's scoped to YOUR view — other reps still see the contact.
- It's scoped to THIS panel — dismissing on the Opportunity panel doesn't affect the Account panel, and vice versa.
- It **automatically clears when a new `Engagement_Touch__c` lands for that contact**. If Sarah Johnson re-engages tomorrow with a new whitepaper download, she reappears.

Use dismiss when a contact is genuinely not relevant (e.g. they were a contractor who left) — not when you're just trying to declutter for the moment. It's not "snooze for 24 hours" — it's "I've seen this and I don't care unless something changes."

## Action 3 — View all

Click **View all** in the panel header. A large modal opens (`Engagement Intelligence — <Account/Opp Name>`).

The modal has three regions:

### Top: Stats strip (4 tiles)

| Tile                     | What                                                    |
| ------------------------ | ------------------------------------------------------- |
| **Total Engaged**        | How many people                                         |
| **Total Touches**        | How many touch events in the last 6 weeks               |
| **Top Topic**            | The most-engaged-with Topic across this scope           |
| **Buying-Committee Gap** | How many of the engaged people are NOT on the Deal Team |

### Left column: Engagement list with Group-by toggle

- **Group by Person** (default) — one row per Contact. Expand a row → per-asset breakdown (which whitepapers, webinars, downloads, etc., with repeat counts and dates).
- **Group by Campaign** — one row per Marketing Campaign. Expand → which assets in that campaign were engaged with, and by whom.

In Person mode, each row has the same `+ Add` and `×` actions as the panel. Clicking **+ Add** here closes the modal and chains into the same Add flow described above.

### Right column: Buying-motion timeline

A vertical timeline, today at the top, past at the bottom. Each colored dot is one asset engagement. The scale is **piecewise**:

- The top half of the timeline is the **last 6 weeks** at weekly granularity — for spotting recent momentum.
- The bottom half compresses **6 weeks → 1 year ago** at monthly granularity.
- Older than 1 year → clamps at the bottom.

Dots are colored by persona: blue Executive, navy Finance, green Technical, orange Operational, gray Other.

**Click a person row in Person mode** → the timeline filters to just that contact and the header changes to `<Name>'s buying motion`. Collapse the row to clear focus.

The timeline caps at 100 dots — sorted most-recent-first — so if a contact has 200+ touches the chart shows the freshest 100.

## Action 4 — Follow the hotlinks

Every contact name in the panel and the detail modal is a hotlink. Three flavors:

- **Click** → Opens the Contact record in the foreground tab.
- **Hover (briefly)** → Multi-line tooltip with touch count, topics, last-touch date, OCR/ACR status, consultant flag.
- **Hover (~1 sec)** → Lightning's standard hovercard with the full Contact record preview.

In the detail modal, the **Open <RecordName> →** link at the top of the body links to the underlying Account or Opportunity record (same hover behavior).

## Summary

- **Deal Team** = on OCR. **Engaged — not on Deal Team** = where the value is.
- **`+ Add`** writes a real OCR row. Race-safe.
- **`×`** hides a contact until a new touch arrives. Per-user.
- **View all** opens the big modal with stats, group-by toggle, timeline.
- **Hotlinks everywhere** — names → Contact, record link → Account/Opportunity.

See also: [`docs/users/DEMO.md`](./DEMO.md) for the 4-beat walkthrough, [`docs/users/admin-guide.md`](./admin-guide.md) if you're placing the panel on a record page.
