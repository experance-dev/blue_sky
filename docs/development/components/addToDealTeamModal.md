# addToDealTeamModal

Role-picker modal. Opened from [`engagementPanel`](./engagementPanel.md) (or from inside [`engagementDetailModal`](./engagementDetailModal.md) via a chained close payload) when the user clicks "+ Add". Collects Role + (on Account scope) Opportunity + Primary flag, then calls [`EngagementController.addToOcrSafe`](../../../force-app/main/default/classes/engagement/EngagementController.cls). Closes with the server's `AddToOcrResult` payload so the host can decide whether to chain into [`alreadyAddedModal`](./alreadyAddedModal.md) on a race-detected response.

Source: [`force-app/main/default/lwc/addToDealTeamModal/`](../../../force-app/main/default/lwc/addToDealTeamModal/) — [`addToDealTeamModal.js`](../../../force-app/main/default/lwc/addToDealTeamModal/addToDealTeamModal.js) · [`addToDealTeamModal.html`](../../../force-app/main/default/lwc/addToDealTeamModal/addToDealTeamModal.html) · [`addToDealTeamModal.css`](../../../force-app/main/default/lwc/addToDealTeamModal/addToDealTeamModal.css) · [`addToDealTeamModal.js-meta.xml`](../../../force-app/main/default/lwc/addToDealTeamModal/addToDealTeamModal.js-meta.xml)

## Orientation

A `lightning/modal` subclass — opened via `AddToDealTeamModal.open({...})`. Not embedded in a template, not exposed in App Builder (`<isExposed>false</isExposed>`). The modal is dumb: it gathers form input, posts to the server, returns the server result verbatim. **`alreadyExists: true` is NOT a failure** — the host treats it as a normal outcome and chains into [`alreadyAddedModal`](./alreadyAddedModal.md).

On Opportunity scope, the opportunity id is passed in and the form skips the Opportunity picker. On Account scope, a `lightning-record-picker` is rendered so the user can choose which Opportunity the contact is being added to.

## Public API

### Properties (passed via `open()`)

| Name            | Type                         | Required                                          | Description                                                                                                    |
| --------------- | ---------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `contactId`     | `Id`                         | yes                                               | The Contact being added.                                                                                       |
| `contactName`   | `String`                     | yes                                               | Display name in the body copy ("Add **<Name>** as a member…").                                                 |
| `opportunityId` | `Id`                         | yes on Opportunity scope; `null` on Account scope | The Opportunity to add the OCR row to. Account scope leaves this `null` and the form prompts the user to pick. |
| `recordContext` | `'Account' \| 'Opportunity'` | yes                                               | Drives whether the Opportunity picker renders.                                                                 |

### Close results

The modal closes with one of two shapes:

| Result      | Payload                          | When                              |
| ----------- | -------------------------------- | --------------------------------- |
| `'cancel'`  | `undefined`                      | User clicked Cancel.              |
| `'success'` | `AddToOcrResult` from the server | Server call returned — see below. |

The `'success'` result wraps the verbatim server response from [`EngagementController.addToOcrSafe`](../../../force-app/main/default/classes/engagement/EngagementController.cls). Shape per [`AddToOcrResult.cls`](../../../force-app/main/default/classes/engagement/AddToOcrResult.cls):

```js
// True insert:
{ success: true, ocrId: '00K...' }

// Race detected — someone else inserted first:
{ alreadyExists: true, addedByUserId, addedByUserName, addedAt, ocrId }
```

The host inspects `payload.alreadyExists` and chains into the appropriate next step. **Both are `result: 'success'`** — the call succeeded, the row exists, we know who put it there.

Error path: the modal catches and sets `errorMessage` inline (rendered with `role="alert"`); it does NOT close on error. The user can correct the form and retry.

### Events

None. As a `LightningModal` subclass, this component returns its outcome via the resolved promise from `open()` — the host does not listen for custom events.

## Wire dependencies

None for reads (no `@wire` adapters). One imperative write:

| Apex method                                                                                                        | Cacheable | Parameters                                      | Fires when                                          |
| ------------------------------------------------------------------------------------------------------------------ | --------- | ----------------------------------------------- | --------------------------------------------------- |
| [`EngagementController.addToOcrSafe`](../../../force-app/main/default/classes/engagement/EngagementController.cls) | no        | `{ contactId, opportunityId, role, isPrimary }` | User clicked "Add to Deal Team" and form validates. |

Server-side race protection lives in [`EngagementServiceImpl.addToOcrSafe`](../../../force-app/main/default/classes/engagement/EngagementServiceImpl.cls) — it re-queries OCR in the same transaction before inserting. If a row already exists, it returns the `alreadyExists` envelope.

## Form fields

| Field                | Type                                                      | Required                 | Notes                                                                                                                                                                                                                                                                                                           |
| -------------------- | --------------------------------------------------------- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Opportunity          | `lightning-record-picker` (object-api-name=`Opportunity`) | yes (Account scope only) | Hidden on Opportunity scope — the parent already provided `opportunityId`.                                                                                                                                                                                                                                      |
| Role                 | `lightning-combobox`                                      | yes                      | Frozen options: Decision Maker, Economic Buyer, Technical Evaluator, Champion, Influencer, Business User, Other. See [`ROLE_OPTIONS`](../../../force-app/main/default/lwc/addToDealTeamModal/addToDealTeamModal.js).                                                                                            |
| Make primary contact | `lightning-input type="checkbox"`                         | no                       | Maps to `OpportunityContactRole.IsPrimary`. Salesforce permits only one Primary per Opportunity — setting this on a contact when another is Primary un-flags the prior Primary (standard platform behavior, flagged as a Phase 1.5 polish item in [`PHASE1-HANDOFF.md`](../../architecture/PHASE1-HANDOFF.md)). |

Client-side validation: Role AND Opportunity must both be set. If not, the modal renders an inline error message and stays open — no server call fires.

## Parent integration

Opened by [`engagementPanel.handleAddClick`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.js) and by the chained close-handler in [`engagementPanel.handleViewAll`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.js) when the detail modal returns `result: 'add-to-team'`:

```js
import AddToDealTeamModal from "c/addToDealTeamModal";
import AlreadyAddedModal from "c/alreadyAddedModal";

const result = await AddToDealTeamModal.open({
  size: "small",
  contactId,
  contactName,
  opportunityId, // null on Account scope — modal renders its own picker
  recordContext
});

if (result?.result === "success" && result.payload) {
  if (result.payload.alreadyExists) {
    // Race — chain into the confirmation modal.
    await AlreadyAddedModal.open({
      size: "small",
      contactName,
      addedByUserName: result.payload.addedByUserName,
      addedAt: result.payload.addedAt,
      ocrId: result.payload.ocrId,
      opportunityId
    });
  } else {
    await this.refresh();
  }
}
```

`size: 'small'` is the canonical width for the role-picker form. The body is short; medium adds unnecessary whitespace.

## Accessibility

- All form fields are real `lightning-*` controls — labels, error states, and keyboard navigation come for free.
- Required state on Role / Opportunity surfaces as `required` on the underlying inputs; submit without filling them fails client-side with the inline error banner (`role="alert"`).
- Error message uses `role="alert"` so screen readers announce it on the failure path.
- Save button disables (`disabled={isSaving}`) while the server call is in flight — prevents double-submit and signals state visually.
- Cancel and Save are real `lightning-button` elements — Esc on the modal also closes per `LightningModal` default behavior.

Keyboard map: standard form Tab order — Opportunity picker (if shown) → Role → Make primary → Cancel → Save.

## Known limitations

- **Primary checkbox doesn't warn about un-flagging.** If the Opportunity already has a Primary OCR and the user ticks "Make primary," the standard platform behavior silently demotes the prior Primary. The modal doesn't surface that. Phase 1.5 candidate — see [`PHASE1-HANDOFF.md §Open questions`](../../architecture/PHASE1-HANDOFF.md#open-questions--not-yet-decided).
- **No optimistic UI.** The modal stays open through the network roundtrip — `isSaving` disables the button but the user has no progress indicator beyond that. Acceptable for a sub-second call; revisit if latency complaints land.
- **Role options are hardcoded.** Frozen array in JS — not driven from the OCR `Role` picklist metadata. Intentional for Phase 1 (the standard `Role` picklist isn't reliably present across orgs); revisit when the package is installed in a target org that has its own list.

## Tests

- Jest: [`addToDealTeamModal.test.js`](../../../force-app/main/default/lwc/addToDealTeamModal/__tests__/addToDealTeamModal.test.js) — covers form validation, save success, save with `alreadyExists` (host responsibility verified upstream), cancel, Account-scope picker render.
- Apex backing the write: [`EngagementControllerTest.cls`](../../../force-app/main/default/classes/engagement/EngagementControllerTest.cls), [`EngagementServiceImplTest.cls`](../../../force-app/main/default/classes/engagement/EngagementServiceImplTest.cls).

## Related

- Parent / host: [`engagementPanel`](./engagementPanel.md)
- Chained on race: [`alreadyAddedModal`](./alreadyAddedModal.md)
- Apex: [`EngagementController.addToOcrSafe`](../../../force-app/main/default/classes/engagement/EngagementController.cls), [`AddToOcrResult.cls`](../../../force-app/main/default/classes/engagement/AddToOcrResult.cls), [`EngagementServiceImpl.cls`](../../../force-app/main/default/classes/engagement/EngagementServiceImpl.cls)
- Conventions: [`docs/development/lwc-conventions.md`](../lwc-conventions.md)
- User-facing: [`docs/users/sales-rep-guide.md`](../../users/sales-rep-guide.md)
