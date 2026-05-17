# engagementTestATouch — Jest test design

## Component contract

- Imperative-only (no wires).
- Form state in `@track form`. Result + error are `@track`.
- Form fields: email (required), topicExternalCode, touchType (combobox), persona (combobox), intentLevel (combobox), assetName.
- Submit button disabled when `isSubmitting` OR `!form.email`.
- Submit calls `testTouch({input: this.form})`.
- Success → render result panel (replaces form), fire toast (variant by resolutionStatus).
- Error → render `[data-test="form-error"]`, fire error toast.
- Reset button → restore empty form, clear result + error.
- Signal rows: each has confidenceLabel, confidenceStyle (clamped 0..100), opportunityUrl.
- Status badge classes: Resolved→success, Ambiguous→warning, NoMatch→error, else→base.

## Scenarios (22)

### Initial form render

1. `rendersAllFormFields` — email, topic, touchType, persona, intent, asset, submit, reset (no — reset only when result).
2. `submitButtonDisabledWhenEmailEmpty` — initial state → button.disabled=true.
3. `submitButtonEnabledOnceEmailEntered` — type email → disabled=false.
4. `touchTypeOptionsList` — 5 options matching TOUCH_TYPES.
5. `personaOptionsList` — 5 options matching PERSONAS.
6. `intentOptionsList` — 3 options.

### Form field interaction

7. `handleFieldChangeUpdatesFormState` — change email, then topic → both reflected in subsequent Apex call.
8. `handleFieldChangeIgnoresElementsWithoutDataField` — fire change on a non-data-field element → no state mutation, no crash.

### Submit — happy path Resolved

9. `submitCallsApexWithFormPayload` — set email, submit → testTouch called with `{input:{email, ...defaults}}`.
10. `submitWhileEmptyEmailIsNoOp` — submit form without email → testTouch NOT called.
11. `submitSetsIsSubmittingDuringApex` — before resolve, button disabled (proxy via `submitDisabled` getter; assertion: button.disabled=true mid-flight, false after resolve).
12. `successFiresToastVariantSuccessForResolved` — `resolutionStatus:'Resolved'` → toast variant=success.
13. `successFiresToastVariantInfoForNonResolved` — `resolutionStatus:'NoMatch'` → toast variant=info.

### Result panel render

14. `resultPanelReplacesFormOnSuccess` — after success, `[data-test="form"]` gone, `[data-test="result-panel"]` present.
15. `statusBadgeClassByResolutionStatus` — Resolved→success class; Ambiguous→warning; NoMatch→error.
16. `resultPanelShowsContactLinkWhenContactIdSet` — contactId present → `[data-test="contact-link"]` with href `/lightning/r/Contact/{id}/view`.
17. `resultPanelOmitsContactLinkWhenContactIdNull` — `contactId=null` → no contact link.
18. `resultPanelShowsAccountLinkWhenAccountIdSet` — analog.
19. `signalCountPluralization` — 0→'0 signals'; 1→'1 signal'; 2→'2 signals'.
20. `signalsListRendersAllRows` — signals[].length=2 → 2 `[data-test="signal-row"]`.
21. `signalRowConfidenceClampedTo100ForOverflow` — confidence=150 → style width:100%.
22. `signalRowConfidenceClampedTo0ForNegative` — confidence=-5 → style width:0%.
23. `signalRowConfidenceNullDefaultsTo0Percent` — confidence undefined → confidenceLabel '0%'.
24. `messagesListRendersWhenPresent` — messages=['x','y'] → `[data-test="messages"]` with 2 li.
25. `messagesAbsentWhenEmptyOrMissing` — messages=[] OR undefined → no `[data-test="messages"]`.

### Reset

26. `resetButtonClearsResultAndShowsForm` — click reset → form visible, result panel gone.
27. `resetClearsFormFieldsToEmptyDefaults` — type into email, submit, reset → form.email back to ''. Verified by Apex call shape if user re-submits.

### Error path

28. `errorPathRendersFormErrorMessage` — Apex rejected with body.message → `[data-test="form-error"]` shows it.
29. `errorPathUsesFallbackMessageWhenNoBody` — Apex rejected bare → 'Unable to run the test.'
30. `errorPathFiresErrorToast` — toast variant=error.
31. `errorPathDoesNotShowResultPanel` — error → form remains; result panel NOT shown.

## Coverage target ≥95%

Edge case attention:

- `contactUrl` / `accountUrl` getter null branches.
- `statusBadgeClass` default branch.
- `signalRows` empty + non-array result.
- `messages` empty + non-array result.
- `submitDisabled` both arms.
- Clamping math in confidenceStyle.

## Fixture

- Helper `setEmail(element, value)` to wire the email field.
- `resolvedResultFixture()` returning a representative success payload.
