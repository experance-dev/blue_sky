# engagementErrorQueue — Jest test design

## Component contract

- `@wire` on `getTouchesWithIssues({limitN:50})`.
- Render states: loading (spinner), error (text), empty (text), populated (datatable).
- Row actions: `retry` → `retryResolution({touchId})`; `ignore` → `ignoreTouch({touchId, reason:'Admin marked as ignored'})`.
- After each action: `refreshApex(this.wiredResult)` + toast (success/info/error).
- Status colors: NoMatch → error, Ambiguous → warning, default → default.
- Count label: pluralization "touch" vs "touches".

## Scenarios (15)

### Wire states

1. `rendersSpinnerOnLoading` — before emit → `lightning-spinner` visible, no table, no error.
2. `rendersErrorOnWireError` — `getTouchesWithIssues.error()` → `[data-test="error"]` visible with message; default message when body absent.
3. `rendersCustomErrorMessageFromApex` — error has body.message → that message shown.
4. `rendersEmptyStateWhenNoTouches` — emit([]) → `[data-test="empty"]` visible, count label "0 touches pending review".
5. `rendersDatatableWhenPopulated` — emit(SAMPLE 2 rows) → table has data.length=2, count "2 touches pending review".
6. `countLabelSingularForOneRow` — emit single row → "1 touch pending review".

### Row rendering

7. `eachRowHasIdFromTouchId` — table row.id == touchId.
8. `statusClassNoMatchIsError` — row with NoMatch → statusClass `slds-text-color_error`.
9. `statusClassAmbiguousIsWarning` — Ambiguous → `slds-text-color_warning`.
10. `statusClassUnknownIsDefault` — fabricate row with `resolutionStatus='Resolved'` → `slds-text-color_default`.

### Retry action — happy path

11. `retryActionCallsApexWithTouchId` — fire rowaction `retry` → retryResolution called with `{touchId}`.
12. `retrySuccessToastFiredForResolvedStatus` — Apex returns `{resolutionStatus:'Resolved'}` → ShowToastEvent fired with variant 'success', title 'Retry complete'.
13. `retryInfoToastForNonResolvedStatus` — `{resolutionStatus:'Ambiguous'}` → variant 'info'.

### Retry action — error path

14. `retryErrorPathFiresErrorToast` — Apex rejected with `{body:{message:'X'}}` → toast variant 'error', title 'Retry failed', message 'X'.
15. `retryErrorPathUsesFallbackMessageWhenNoBody` — rejected with bare error → 'Unable to retry resolution.'

### Ignore action

16. `ignoreActionCallsApexWithReason` — fire rowaction `ignore` → ignoreTouch called with `{touchId, reason:'Admin marked as ignored'}`.
17. `ignoreSuccessToast` — Apex resolves → toast variant 'success', title 'Touch ignored'.
18. `ignoreErrorPath` — Apex rejected with body.message → error toast.
19. `ignoreErrorPathFallbackMessage` — bare error → 'Unable to ignore this touch.'

### Row action — bad path

20. `rowActionWithoutTouchIdIsNoOp` — fire rowaction with row missing touchId → neither Apex called.
21. `rowActionUnknownNameIsNoOp` — fire rowaction `{action:{name:'delete'}, row}` → neither Apex called.

### refreshApex chain

22. `successfulRetryRefreshesWire` — after success, the wire `refreshApex` is triggered (verify via mock of `@salesforce/apex` `refreshApex` import OR by emitting fresh data and seeing UI update — preferred: mock refreshApex).

## Coverage target

≥95%. Focus uncovered branches: `statusClass` default arm, fallback error strings, the `if (!row || !row.touchId) return;` guard.

## Fixture conventions

- `SAMPLE = [NoMatchRow, AmbiguousRow]`.
- Helper `fireRowAction(table, actionName, row)` dispatches the synthetic CustomEvent.
- Mock `@salesforce/apex` to capture `refreshApex` calls:
  ```
  jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn().mockResolvedValue() }), { virtual: true });
  ```

## Toast capture

```
const handler = jest.fn();
document.body.addEventListener('lightning__showtoast', handler);
```
