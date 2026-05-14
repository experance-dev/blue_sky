# engagementRuleCoverage — Jest test design

## Component contract

- `@wire` on `getRuleCoverage` (no params).
- Render states: loading (spinner), error (text), empty (text), populated (datatable).
- Dead-rule banner shown when ANY row.signalsLast30Days === 0.
- Row class for zero-signal rows: `slds-text-color_error slds-text-title_bold dead-rule`.
- `rowClass` cellAttribute drives the datatable styling.
- Read-only — no row actions.

## Scenarios (12)

### Wire states

1. `rendersSpinnerOnLoading` — before emit → spinner visible.
2. `rendersErrorOnWireError` — error → `[data-test="error"]` visible with default fallback message.
3. `rendersCustomErrorMessageFromApexBody` — error has body.message → message shown.
4. `rendersEmptyState` — emit([]) → `[data-test="empty"]` shown, no datatable, no banner.

### Populated render

5. `rendersDatatableWithAllRows` — emit(2 rules) → data.length=2.
6. `rowsHaveKeyFromRuleDeveloperName` — key field matches.
7. `rowsPreserveInputOrder` — order in == order out.

### Dead-rule highlighting

8. `deadRuleBannerHiddenWhenAllRulesHaveSignals` — emit rules with signalsLast30Days≥1 → no banner.
9. `deadRuleBannerShownWhenAnyRuleAtZero` — 1 dead + 2 live → banner visible.
10. `deadRuleBannerCountPluralization` — 1 dead → "1 rule produced…"; 3 dead → "3 rules produced…".
11. `deadRuleRowClassMarksDeadRule` — row with signalsLast30Days=0 → rowClass contains 'dead-rule' AND 'slds-text-color_error'.
12. `liveRuleRowClassIsDefault` — row with signalsLast30Days>0 → rowClass = 'slds-text-color_default'.

### Edge cases

13. `mixedDeadAndLiveRules` — 2 live + 2 dead → deadRuleCount=2, banner says "2 rules", correct rows flagged.

## Coverage target

100% — small component, no row actions.

## Fixture

- Helper `emit(rules)` to feed the wire.
- `RULE_LIVE` and `RULE_DEAD` constants.

## No infrastructure changes needed

This component already passes baseline.
