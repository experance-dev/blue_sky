# addToDealTeamModal — Jest test design

Locked workflow: Pippa designs → team implements → Pippa reviews → smoke.

## Component contract (from production source)

- Extends `LightningModal`. Public `@api`: `contactId`, `contactName`, `opportunityId`, `recordContext`.
- Internal state: `role`, `isPrimary`, `isSaving`, `errorMessage`.
- Closes with `{result:'cancel'}` or `{result:'success', payload}`.
- Renders an Opportunity record-picker ONLY when `recordContext === 'Account'`.
- Save guard: missing role OR missing opportunityId sets `errorMessage`, no Apex call.
- Apex call: `addToOcrSafe({contactId, opportunityId, role, isPrimary})`.
- alreadyExists=true is still `result:'success'` — caller decides.
- Error path: pulls `e.body.message` or falls back to `'Failed to add. Try again.'`.

## Scenarios (15)

### Render / state

1. `rendersHeaderAndContactName` — header label, contact name appears in body.
2. `rendersRoleOptionsList` — 7 hardcoded role options in combobox.
3. `hidesOpportunityPickerInOpportunityScope` — no `lightning-record-picker` when scope = Opportunity.
4. `showsOpportunityPickerInAccountScope` — picker present, `object-api-name="Opportunity"`, required.
5. `primaryCheckboxDefaultsUnchecked` — initial state.

### Validation (bad path)

6. `requiresRoleBeforeSave` — Save with no role → alert visible, Apex NOT called, alert text matches /required/i.
7. `requiresOpportunityBeforeSave_AccountScope` — Account scope, role set, no oppId picked → alert, no Apex.
8. `clearsErrorOnSubsequentSuccessfulSave` — first save errors, second save succeeds — error cleared.

### Happy path

9. `callsAddToOcrSafeWithExpectedParams` — combobox change + checkbox check → Apex param shape matches.
10. `closesWithSuccessPayloadOnCleanSave` — payload.alreadyExists=false → close({result:'success', payload}).
    _Note: close-call assertions limited by LWC modal stub. Assert Apex was called + isSaving flag transitions._
11. `closesWithSuccessOnAlreadyExistsRace` — Apex returns alreadyExists=true → still result:'success'.

### Bad path / errors

12. `displaysServerErrorMessage` — Apex rejects with `{body:{message:'X'}}` → alert renders 'X'.
13. `displaysFallbackErrorWhenApexRejectsWithNoBody` — Apex rejects bare → 'Failed to add. Try again.'

### Interactions / lifecycle

14. `cancelClickDoesNotCallApex` — Cancel button click → no Apex invocation.
15. `isSavingDisablesSaveButtonDuringApexCall` — save button gets `disabled` while promise pending, re-enabled after.

## A11y / console

- All inputs have associated `label` (`lightning-combobox`, `lightning-input` carry their own).
- Error message renders inside `[role="alert"]`.
- Console-clean assertion: no warnings during full lifecycle.

## Coverage target

≥95% line coverage on `addToDealTeamModal.js`. Watch lines 49 (handlePrimaryToggle), 53 (handleOppChange), 80-82 (catch + finally).

## Fixture conventions

- Helper `buildModal({recordContext='Opportunity'})` mounts element with default Sarah Johnson contact, opp id `006...001`.
- Helper `flushMicrotasks()` for awaiting promise chains.
- `findButton(element, label)` for footer buttons.

## Known constraints (document, don't fight)

- LWC modal close is unspyable (proxy seals non-@api props). Assertions test side effects (Apex args, DOM render) — not the close call itself.
