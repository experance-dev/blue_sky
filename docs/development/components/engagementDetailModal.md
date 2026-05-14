# engagementDetailModal

The full-screen **"View all"** modal. Opened from [`engagementPanel`](./engagementPanel.md) when the user clicks the **View all** button. Receives the pre-fetched engagement list as a prop — does NOT call Apex for reads — and renders a stats strip, the engagement list (group-by Person or Campaign), and a vertical buying-motion timeline. Writes (dismiss) are imperative.

Source: [`force-app/main/default/lwc/engagementDetailModal/`](../../../force-app/main/default/lwc/engagementDetailModal/) — [`engagementDetailModal.js`](../../../force-app/main/default/lwc/engagementDetailModal/engagementDetailModal.js) · [`engagementDetailModal.html`](../../../force-app/main/default/lwc/engagementDetailModal/engagementDetailModal.html) · [`engagementDetailModal.css`](../../../force-app/main/default/lwc/engagementDetailModal/engagementDetailModal.css) · [`engagementDetailModal.js-meta.xml`](../../../force-app/main/default/lwc/engagementDetailModal/engagementDetailModal.js-meta.xml)

## Orientation

A `lightning/modal` subclass — opened via `EngagementDetailModal.open({...})`, not embedded in a template. The host owns the data; the modal owns the presentation. This means the modal never goes stale relative to the host (the host re-fetches and re-opens) but also means the modal cannot single-handedly refresh — actions that need server-side state (Add to Team, Dismiss) close the modal with a payload OR mutate local state optimistically.

Two-column body: main engagement list on the left (2/3 width), vertical buying-motion timeline on the right (1/3 width). The stats strip across the top is a four-tile roll-up: Total Engaged, Total Touches, Top Topic, Buying-Committee Gap.

Clicking a person row in Group-by-Person mode **focuses the timeline** to just that contact's touches — see [`toggleRow`](../../../force-app/main/default/lwc/engagementDetailModal/engagementDetailModal.js) and [`get timelineDots`](../../../force-app/main/default/lwc/engagementDetailModal/engagementDetailModal.js). Collapsing the row clears focus.

## Public API

This is a `LightningModal` subclass — there is no `<c-engagement-detail-modal>` markup. The host opens it via the static `open()` method inherited from `LightningModal`.

### Properties (passed via `open()`)

| Name            | Type                         | Required                                 | Description                                                                                                              |
| --------------- | ---------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `engagements`   | `List<EngagementDTO>`        | yes                                      | Pre-fetched list. Shape per [`EngagementDTO.cls`](../../../force-app/main/default/classes/engagement/EngagementDTO.cls). |
| `recordContext` | `'Account' \| 'Opportunity'` | yes                                      | Drives the dismiss path (account-scoped vs opp-scoped).                                                                  |
| `recordName`    | `String`                     | no                                       | Header display name (e.g. `'United Healthcare'`). Appended to the modal label.                                           |
| `opportunityId` | `Id`                         | yes if `recordContext === 'Opportunity'` | Used for record hotlink and dismiss scope.                                                                               |
| `accountId`     | `Id`                         | yes if `recordContext === 'Account'`     | Used for record hotlink and dismiss scope.                                                                               |

### Close results

| Result          | Payload                      | When                                                                                                                               |
| --------------- | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `'closed'`      | `undefined`                  | User closed the modal without action.                                                                                              |
| `'add-to-team'` | `{ contactId, contactName }` | User clicked "+ Add" on a person row inside the modal. The host should chain into [`addToDealTeamModal`](./addToDealTeamModal.md). |

The modal does NOT close on dismiss — dismiss mutates local state and lets the user continue exploring.

### Wire dependencies

None for reads. One imperative write:

| Apex method                                                                                                          | Cacheable | Parameters                                | Fires when                                                                                                                                                              |
| -------------------------------------------------------------------------------------------------------------------- | --------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`EngagementController.dismissContact`](../../../force-app/main/default/classes/engagement/EngagementController.cls) | no        | `{ contactId, opportunityId, accountId }` | User clicked the per-row `×` button. On success, the row is filtered out of `engagements` locally; the host panel picks up the persisted dismissal on its next refresh. |

## Group-by modes

| Mode             | Source                                             | Per row                                                                                                                                                                     |
| ---------------- | -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Person (default) | One row per `EngagementDTO`                        | Avatar, name + title, touch count, badges (`✓ on team`, `Consultant`, `ACR`), "+ Add" if not on OCR, `×` dismiss. Expanding shows per-asset breakdown.                      |
| Campaign         | Roll-up of `assets[].campaignName` across all DTOs | Campaign label, people-count + asset-count sublabel, total touches, expandable asset list with the person's name on each asset. No "+ Add" / dismiss at the campaign level. |

The toggle is a [`lightning-radio-group`](../../../force-app/main/default/lwc/engagementDetailModal/engagementDetailModal.html) with `type="button"` and `variant="label-hidden"` — renders as a SLDS segmented pill.

## Buying-motion timeline

Vertical axis, today at the top, past at the bottom. Piecewise scale — see [`timeAgoToPercent`](../../../force-app/main/default/lwc/engagementDetailModal/engagementDetailModal.js):

| Range                | Slice of axis  | Granularity                |
| -------------------- | -------------- | -------------------------- |
| 0 → 6 weeks ago      | 0% → 50%       | weekly (the "recent" half) |
| 6 weeks → 1 year ago | 50% → 100%     | monthly                    |
| > 1 year ago         | clamps at 100% | —                          |

Each dot represents one **asset bucket** (one row of `EngagementDTO.assets[]`), positioned by `lastAt`. Persona drives color via the `PERSONA_COLOR` map; missing persona falls back to gray (`'Other'`). Capped at 100 dots — sorted most-recent-first, so the cap favors the freshest activity. Assets with no `lastAt` are skipped (we have no defensible position).

When the user expands a person row in Group-by-Person mode, the timeline filters to just that contact's touches and the header changes from `"Buying motion (all)"` to `"<Name>'s buying motion"`. Collapsing the row or switching to Group-by-Campaign clears focus.

## Stats strip

Four tiles, all computed from `engagements`:

| Tile                     | Source                                                                                                                                                |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Total Engaged**        | `engagements.length`                                                                                                                                  |
| **Total Touches**        | `sum(engagements[].touchCount)`                                                                                                                       |
| **Top Topic**            | argmax across `topics[]` weighted by each contact's `touchCount`. Truncated to 20 chars with `…` if longer. Falls back to `'—'` when nothing engaged. |
| **Buying-Committee Gap** | `engagements.filter(e => !e.onOcr).length`                                                                                                            |

## Parent integration

Opened by [`engagementPanel.handleViewAll`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.js):

```js
import EngagementDetailModal from "c/engagementDetailModal";

const result = await EngagementDetailModal.open({
  size: "medium",
  engagements: this.engagements,
  recordContext: this.recordContext,
  recordName: this.recordName || "",
  opportunityId: this.isOpportunityScope ? this.recordId : null,
  accountId: this.isAccountScope ? this.recordId : null
});

if (result?.result === "add-to-team" && result.payload) {
  // chain into c/addToDealTeamModal with result.payload.contactId / contactName
}
```

`size: 'medium'` is the canonical width for this modal — the two-column layout collapses awkwardly under `small`.

## Accessibility

- Each expandable row has `role="button"`, `tabindex="0"`, `aria-expanded={isExpanded}`. Enter and Space both toggle — see [`handleRowKeyDown`](../../../force-app/main/default/lwc/engagementDetailModal/engagementDetailModal.js).
- Top-topic value carries a `title` attribute with the un-truncated text — screen readers and hover both reveal the full topic name.
- Record hotlink (`Open <RecordName> →`) has a multi-line `title` summary; Lightning hovercard auto-attaches because the href matches `/lightning/r/.../view`.
- Dismiss button is `<lightning-button-icon alternative-text="Dismiss">` — keyboard-activatable with explicit alt text.
- Toast on dismiss success/error uses `lightning/platformShowToastEvent` — announced by assistive tech as a live region.

Keyboard map:

- `Tab` walks: group-by toggle → record link → first row → first row's "+ Add" / dismiss → next row.
- `Enter` / `Space` on a row: expand/collapse + focus timeline to that contact.

## Known limitations

- **Reads are stale once opened.** The host hands in `engagements` at open time. If a new touch lands while the modal is open, the user won't see it until they close and re-open. Acceptable — the modal is an exploration surface, not a live feed.
- **Dismiss optimism is one-way.** Local filter removes the row immediately. If the server call fails, the toast surfaces the error but we don't restore the row. The host's next refresh will (correctly) bring the contact back. Net effect: the user briefly sees the row gone, then it reappears with the failure toast. Documented; not a bug.
- **Campaign roll-up doesn't preserve per-asset ordering by date.** Assets within a campaign group render in the order they were emitted by the contact loop, not by `lastAt`. Phase 1.5 candidate.
- **Timeline cap of 100 dots is silent.** No "+ N more" affordance. At 100 dots the chart is already busy — this is acceptable for Phase 1 but worth surfacing if Sales reports missing touches.

## Tests

- Jest: [`engagementDetailModal.test.js`](../../../force-app/main/default/lwc/engagementDetailModal/__tests__/engagementDetailModal.test.js) — covers group-by switch, expand-collapse, timeline focus, dismiss optimistic update, add-to-team close payload.

## Related

- Parent / host: [`engagementPanel`](./engagementPanel.md)
- Chained modal on "+ Add": [`addToDealTeamModal`](./addToDealTeamModal.md)
- Apex: [`EngagementController.dismissContact`](../../../force-app/main/default/classes/engagement/EngagementController.cls), [`EngagementDTO.cls`](../../../force-app/main/default/classes/engagement/EngagementDTO.cls)
- Conventions: [`docs/development/lwc-conventions.md`](../lwc-conventions.md)
- User-facing: [`docs/users/sales-rep-guide.md`](../../users/sales-rep-guide.md)
