# alreadyAddedModal — Jest test design

## Component contract

- Extends `NavigationMixin(LightningModal)`. Public `@api`: `contactName`, `addedByUserName`, `addedAt`, `ocrId`, `opportunityId`.
- "No" rendered first for focus-trap (per US-D3).
- Yes → `NavigationMixin.Navigate({type:'standard__recordPage', attributes:{recordId:ocrId, objectApiName:'OpportunityContactRole', actionName:'view'}})` then `close({result:'navigated'})`.
- No → `close({result:'closed'})`.

## Scenarios (8)

### Render

1. `rendersHeaderAndBodyContent` — header label "Already Added", body contains contactName and addedByUserName.
2. `rendersFormattedDateTime` — `lightning-formatted-date-time` value matches `addedAt`, has formatting attrs.
3. `rendersNoBeforeYesForFocusTrap` — DOM order: data-button="no" appears before data-button="yes".
4. `bothButtonsHaveTitlesForA11y` — `title` attribute set on both buttons.

### Interaction — Yes path

5. `yesClickFiresNavigateWithOcrConfig` — assert getNavigateCalledWith returns expected config.
6. `yesClickClosesModalAfterNavigate` — side-effect: close was invoked (via stub spy if possible; else implicit via no throw).

### Interaction — No path

7. `noClickDoesNotNavigate` — click No → navigation mixin NOT called.
8. `noClickClosesWithClosedResult` — close invoked with `{result:'closed'}` (via spy on stub).

## A11y

- Modal header `label` is set.
- Both buttons have `label` AND `title`.
- Console clean.

## Coverage target

100% — only 2 handlers, both small.

## Infrastructure dependencies

- The global `lightning/modal` mock in `force-app/test/jest-mocks/lightning/modal.js` already exposes `close = jest.fn()` as class field. We can spy on `element.close` directly (the class field IS accessible from outside — unlike a prototype method).
- `lightning/navigation` is provided by sfdx-lwc-jest with `getNavigateCalledWith` helper. **Bug discovered in baseline:** importing `getNavigateCalledWith` from `lightning/navigation` returns undefined in this project. Fix: ensure `lightning/navigation` stub from `@lwc/jest-resolver` is used, or move to local mock. See implementation notes below.

## Implementation notes for the team

- Per-file `jest.mock('lightning/modal', ...)` should be REMOVED in favor of the global moduleNameMapper mock. The global stub exposes `close` as a usable spy.
- For navigation: the sfdx-lwc-jest stub for `lightning/navigation` exposes a default `NavigationMixin` plus a helper `getNavigateCalledWith()` and `getGenerateUrlCalledWith()`. If our version doesn't, override with a local jest-mocks file (per the lightning/modal pattern).
