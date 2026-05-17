# engagementPanel — Jest test design

## Component contract

- `NavigationMixin(LightningElement)`. `@api`: `recordId`, `recordContext`, `recordName`.
- Parallel wires: `getForOpportunity({opportunityId:$opportunityIdParam})`, `getForAccount({accountId:$accountIdParam})`.
- Only the active-context wire fires (the other param resolves null → cacheable short-circuit).
- Partition: `dealTeam` (onOcr=true), `notOnDealTeam` (rest). Section labels include counts.
- "+ Add" → dispatch `addtodealteam` legacy event AND open `AddToDealTeamModal`.
  - On success+!alreadyExists → `refresh()` (refreshApex on active wire + dispatch `refresh` event).
  - On success+alreadyExists → open `AlreadyAddedModal`.
- "View all" → dispatch `viewall` legacy event AND open `EngagementDetailModal`.
  - If modal closes with `{result:'add-to-team', payload}` → chain into AddToDealTeamModal flow.
- Dismiss → `dismissContact({contactId, opportunityId, accountId})` + toast + refresh.
- Decorations: avatar initials, persona-specific avatar class (consultant/acr/default), visible topics (max 2) + hidden count.

## Scenarios (28)

### Render — wire states

1. `rendersSpinnerOnLoading` — before emit → loading spinner visible.
2. `rendersErrorOnWireError` — `getForOpportunity.error()` → error region visible.
3. `rendersEmptyStateWhenNoEngagements` — emit([]) → `[data-test="empty"]`.
4. `accountScopeUsesAccountWire` — recordContext=Account, emit to getForAccount → rows render; getForOpportunity NOT consulted.
5. `opportunityScopeUsesOppWire` — recordContext=Opportunity, emit to getForOpportunity → rows render.

### Render — partition (Opportunity scope)

6. `rendersDealTeamRowsAndNotOnTeamRows` — SARAH+MIKE → 1 deal-team row, 1 not-on-team row.
7. `dealTeamSectionLabelIncludesCount` — "Deal Team — 1 on OCR".
8. `notOnTeamSectionLabelIncludesCount` — "Engaged — not on Deal Team · 1".
9. `countBadgeShowsTotalEngaged` — countBadgeLabel "2 engaged".

### Render — flat list (Account scope)

10. `rendersFlatListForAccountScope` — Account scope → `[data-test="account-row"]` per engagement; no deal-team section label.
11. `accountScopeHidesAddButton` — Account scope → no `[data-test="add-button"]` (showAddButton requires isOpportunityScope).

### Row decorations

12. `rowInitialsForSingleNameContact` — name='Madonna' → 'M'.
13. `rowInitialsForMultiNameContact` — 'Sarah Johnson' → 'SJ'.
14. `rowInitialsForEmptyName` — name=null → '?'.
15. `avatarClassConsultantWinsOverAcr` — isConsultant=true → `av-consultant`.
16. `avatarClassAcrWhenNotConsultant` — isConsultant=false, isAcr=true → `av-acr`.
17. `visibleTopicsCappedAtTwo` — 4 topics → 2 visible + hidden count "+2 more".
18. `noHiddenTopicsBadgeWhenAllFit` — 1 topic → no `+X more`.
19. `touchSummarySingular` — touchCount=1 → '1 touch'; touchCount≠1 → 'N touches'.
20. `contactHotlinkHasTargetTop` — every `[data-test="contact-link"]` carries target="\_top" + href `/lightning/r/Contact/{id}/view`.
21. `onOcrRowShowsBadgeNotButton` — Mike (onOcr=true) renders `[data-test="on-team-badge"]`, NOT `[data-test="add-button"]`.

### Add flow (happy path)

22. `addClickDispatchesLegacyEvent` — click add → `addtodealteam` event dispatched with `{contactId, name, currentRole:null, isPrimary:false}`.
23. `addClickOpensAddModalWithExpectedShape` — opens with `{size, contactId, contactName, opportunityId, recordContext}`.
24. `addSuccessRefreshesPanel` — modal resolves success no-race → spy on `refresh` is called once.
25. `addSuccessRaceOpensAlreadyAddedModal` — modal resolves success+alreadyExists → AlreadyAddedModal.open called with `{contactName, addedByUserName, addedAt, ocrId, opportunityId}`.
26. `addCancelDoesNotRefresh` — modal resolves cancel → refresh not called.
27. `addInAccountScopePassesNullOpportunityId` — Account scope, add click → opportunityId in open args is null.

### View-all flow

28. `viewAllClickDispatchesLegacyEvent` — `viewall` event with `{recordId, recordContext}`.
29. `viewAllOpensDetailModal` — EngagementDetailModal.open called with `{size, engagements, recordContext, recordName, opportunityId}`.
30. `viewAllChainsIntoAddFlowOnAddToTeam` — detail modal resolves `{result:'add-to-team', payload:{contactId, contactName}}` → AddToDealTeamModal.open invoked.
31. `viewAllChainSuccessRaceOpensAlreadyAdded` — chained add result race → AlreadyAddedModal opened.

### Dismiss flow

32. `dismissClickCallsApexAndRefreshes` — dismiss → `dismissContact({contactId, opportunityId, accountId:null})` (Opportunity scope) + success toast + refresh.
33. `dismissAccountScopePassesAccountId` — Account scope → `{contactId, opportunityId:null, accountId}`.
34. `dismissErrorFiresErrorToast` — Apex rejected → error toast variant 'error', refresh NOT called.

### Refresh API

35. `refreshApiTriggersRefreshApexAndDispatch` — call element.refresh() → refreshApex invoked, `refresh` event dispatched.
36. `refreshWithNoActiveWireDispatchesEventOnly` — null activeWire → no refreshApex call, but event still dispatched.

## Coverage target ≥95%

Specifically:

- `buildSummaryTooltip` all branches (covered via row title attrs).
- `isLoading`/`hasError`/`hasData`/`isEmpty` getters.
- All three avatarClass branches.
- All `decorate` branches (showAddButton, showOnTeamBadge, hiddenTopicsLabel, ariaLabel).

## Infrastructure fix required

The current spec's `jest.mock('c/addToDealTeamModal', () => ({default: {open: jest.fn()...}}))` returns the **factory object directly** when imported because sfdx-lwc-jest's c-namespace resolver bypasses ESM `default` interop. Pippa-confirmed via diagnostic.

**Fix:** factories return `{open: jest.fn()...}` at the top level (no `default` wrapper):

```js
jest.mock("c/addToDealTeamModal", () => ({
  open: jest.fn().mockResolvedValue({ result: "closed" })
}));
```

The production import `import AddToDealTeamModal from 'c/addToDealTeamModal'` then resolves `AddToDealTeamModal` to the `{open}` object directly. **Verified working.**
