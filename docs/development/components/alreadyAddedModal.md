# alreadyAddedModal

Race-confirmation modal. Opened by [`engagementPanel`](./engagementPanel.md) (or by the chained handler in `handleViewAll`) when [`addToDealTeamModal`](./addToDealTeamModal.md) closes with payload `{ alreadyExists: true, ... }` — i.e., the server detected that another user added the same Contact to OCR between render and click. The modal explains what happened and offers a navigation to the winning OCR record.

Source: [`force-app/main/default/lwc/alreadyAddedModal/`](../../../force-app/main/default/lwc/alreadyAddedModal/) — [`alreadyAddedModal.js`](../../../force-app/main/default/lwc/alreadyAddedModal/alreadyAddedModal.js) · [`alreadyAddedModal.html`](../../../force-app/main/default/lwc/alreadyAddedModal/alreadyAddedModal.html) · [`alreadyAddedModal.css`](../../../force-app/main/default/lwc/alreadyAddedModal/alreadyAddedModal.css) · [`alreadyAddedModal.js-meta.xml`](../../../force-app/main/default/lwc/alreadyAddedModal/alreadyAddedModal.js-meta.xml)

## Orientation

The simplest LWC in the feature. Two buttons (**No**, **Yes, view OCR**), some `lightning-formatted-date-time`-rendered prose, no Apex calls, no state. Extends `LightningModal` AND mixes in `NavigationMixin` because the **Yes** path navigates to a standard record page.

**Default focus is on No** — per the spec — because the user just clicked "+ Add" and probably doesn't want to be one-Enter-away from leaving the page they're working in. The button order in the template (`No` rendered before `Yes`) drives `LightningModal`'s focus trap.

## Public API

### Properties (passed via `open()`)

| Name              | Type                | Required | Description                                                                                                                                     |
| ----------------- | ------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `contactName`     | `String`            | yes      | Display name in the body copy ("**<Name>** was already added…").                                                                                |
| `addedByUserName` | `String`            | yes      | Display name of the user who won the race.                                                                                                      |
| `addedAt`         | ISO datetime string | yes      | When the winning row was inserted. Rendered with `lightning-formatted-date-time`.                                                               |
| `ocrId`           | `Id`                | yes      | The `OpportunityContactRole` row id. Used by the **Yes, view OCR** path.                                                                        |
| `opportunityId`   | `Id`                | no       | Currently unused inside the modal but kept on the API so callers can pass full context for future surface area (e.g. "back to opp" affordance). |

### Close results

| Result        | Payload     | When                                                                                                                            |
| ------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `'closed'`    | `undefined` | User clicked **No** (the default-focus button).                                                                                 |
| `'navigated'` | `undefined` | User clicked **Yes, view OCR**. Navigation fires before `close()` so the modal is gone by the time the new record page renders. |

## Wire dependencies

None — no Apex from this component. The "navigate" action uses `NavigationMixin`:

```js
this[NavigationMixin.Navigate]({
  type: "standard__recordPage",
  attributes: {
    recordId: this.ocrId,
    objectApiName: "OpportunityContactRole",
    actionName: "view"
  }
});
```

See [`handleYes`](../../../force-app/main/default/lwc/alreadyAddedModal/alreadyAddedModal.js).

## Parent integration

Opened by [`engagementPanel.handleAddClick`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.js) when [`addToDealTeamModal`](./addToDealTeamModal.md) closes with `payload.alreadyExists === true`:

```js
import AlreadyAddedModal from "c/alreadyAddedModal";

await AlreadyAddedModal.open({
  size: "small",
  contactName,
  addedByUserName: result.payload.addedByUserName,
  addedAt: result.payload.addedAt,
  ocrId: result.payload.ocrId,
  opportunityId
});
```

`size: 'small'` is correct — the body is two sentences. The host does not need to inspect the close result because both outcomes (No / Yes) are terminal — there's no chain to continue.

## Accessibility

- **No** is rendered before **Yes** in the template so `LightningModal`'s focus trap puts initial focus on No. This is the spec'd default for a "did you mean to do this?" surface — Enter on first appearance is the safe path.
- Both buttons are real `lightning-button` elements — keyboard-activatable, focusable, with `title` for tooltip and visible text labels.
- Datetime renders via `lightning-formatted-date-time` — the platform handles locale, time-zone, and screen-reader announcement.
- Esc closes the modal per `LightningModal` default behavior — equivalent to clicking No.

Keyboard map: `Tab` cycles No ↔ Yes; `Enter` activates the focused button; `Esc` closes (= No).

## Known limitations

- **Hovercard not auto-attached on the OCR id.** The body copy mentions the OCR row but doesn't render a hotlink with the `/lightning/r/OpportunityContactRole/.../view` href — the user has to click **Yes, view OCR** to navigate. Acceptable: the OCR record isn't usually what the user wants to see (the Opportunity is). If sales requests a hovercard preview, add a small inline link.
- **No "see who added it" affordance.** `addedByUserName` renders as plain text. We don't link to the User record because that's not the usual question. Easy to add if requested.

## Tests

- Jest: [`alreadyAddedModal.test.js`](../../../force-app/main/default/lwc/alreadyAddedModal/__tests__/alreadyAddedModal.test.js) — covers prop rendering, No-closes-with-`'closed'`, Yes-navigates-and-closes-with-`'navigated'`, default focus on No.

## Related

- Parent / host: [`engagementPanel`](./engagementPanel.md)
- Triggering modal: [`addToDealTeamModal`](./addToDealTeamModal.md) (closes with `alreadyExists: true` payload)
- Apex source of the race envelope: [`EngagementServiceImpl.addToOcrSafe`](../../../force-app/main/default/classes/engagement/EngagementServiceImpl.cls), [`AddToOcrResult.cls`](../../../force-app/main/default/classes/engagement/AddToOcrResult.cls)
- Conventions: [`docs/development/lwc-conventions.md`](../lwc-conventions.md)
- Demo beat: [`docs/users/DEMO.md §Beat 4`](../../users/DEMO.md)
