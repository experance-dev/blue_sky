# engagementDetailModal — Jest test design

## Component contract

- Extends `LightningModal`. `@api`: `engagements[]`, `recordContext`, `recordName`, `opportunityId`, `accountId`.
- Group-by toggle (`person` | `campaign`); switching resets `expandedRowKeys` + `focusedContactId`.
- Row click toggles expansion; expansion focuses timeline (person mode only).
- Timeline: piecewise vertical scale (0-6w in top half, 6w-1y in bottom half, >1y clamps).
- 100-dot timeline cap, sorted most-recent-first.
- Asset rows render `lightning-formatted-date-time` for firstAt/lastAt.
- Dismiss row → optimistic local remove + Apex `dismissContact` + toast.
- Add-to-team button → closes with `{result:'add-to-team', payload:{contactId, contactName}}`.

## Scenarios (24)

### Render — person mode (default)

1. `rendersStatsStripWithRollupsTotalEngaged` — totalEngaged = engagements.length.
2. `rendersStatsStripTotalTouches` — sum of touchCount across DTOs.
3. `rendersStatsStripNotOnDealTeam` — count of !onOcr.
4. `rendersStatsStripTopTopic` — most-touched topic by sum of touchCount across DTOs.
5. `topTopicTruncatedAt20Chars` — long topic name → `…` suffix.
6. `topTopicShowsEmDashWhenNoTopics` — engagements without topics → '—'.
7. `rendersAllPersonRows` — one `.engagement-row` per engagement.
8. `personRowsRenderInProvidedOrder` — order preserved.
9. `personRowTouchCountBadgeReflectsDto` — '4 touches', '3 touches', etc.
10. `personRowOnOcrShowsCheckmarkBadge` — Jane (onOcr=true) has '✓ on team' badge.
11. `personRowConsultantBadge` — Marcus (isConsultant=true) shows 'Consultant'.
12. `personRowAcrBadgeWhenAcrButNotConsultant` — DTO with `isAcr=true, isConsultant=false` → 'ACR' badge.
13. `personRowHotlinkAndTooltip` — `<a>` has `/lightning/r/Contact/.../view`, target=\_top, title with summaryTooltip lines.

### Add button

14. `addButtonAbsentForOcrMembers` — Jane row has no `.add-to-team-btn`.
15. `addButtonPresentForNonOcrMembers` — Sarah + Marcus.
16. `addToTeamClickClosesWithCorrectPayload` — spy `element.close`, verify call shape.

### Group-by switch

17. `groupBySwitchesToCampaign` — radio change → `.engagement-row` count = unique campaigns; no Add buttons; no Dismiss buttons.
18. `groupBySwitchClearsExpansionAndFocus` — expand a row, switch group, verify no expanded rows, no timeline focus.
19. `campaignGroupAggregatesCountAcrossPeople` — campaign with same asset on 2 people → count = sum.

### Expansion

20. `clickingRowTogglesExpansionAndShowsAssets` — first row click → asset list visible, 2 assets for Sarah. Click again → collapses.
21. `keyboardEnterAndSpaceToggleRow` — focus row, press Enter / Space → expansion toggles. preventDefault called.

### Timeline focus

22. `clickingPersonRowFocusesTimelineToThatContact` — Jane's row → 1 dot, tooltip contains 'Jane Smith'.
23. `collapsingFocusedRowRestoresAllDots` — re-click → baseline restored.
24. `focusedContactInTitleLabel` — title reads "Jane Smith's buying motion".
25. `timelineDotPositionTopForFreshTouches` — touch with lastAt = now → style top: 0%.
26. `timelineDotPositionBottomForOlderThanYear` — touch 13mo ago → top: 100%.
27. `timelineCapsAt100Dots` — 150 synthetic assets → exactly 100 dots, most-recent kept.
28. `timelineSkipsAssetsWithNullLastAt` — dot count excludes nulls.
29. `groupBySwitchClearsFocus` — focus a row in person mode → switch to campaign → no focus.

### Dismiss

30. `dismissRowOptimisticRemovalAndApex` — Apex resolved → dismissContact called with {contactId, opportunityId, accountId:null}; row removed; success toast fired.
31. `dismissRowErrorPath` — Apex rejected with body.message → error toast fired; row NOT removed.
32. `dismissRowAccountScope` — recordContext=Account → opportunityId=null, accountId passed.

### Close button

33. `closeButtonClosesWithClosedResult` — footer Close → close({result:'closed'}).

### Record link

34. `rendersRecordHotlinkWhenOpportunityIdPresent` — anchor → `/lightning/r/Opportunity/{id}/view`.
35. `rendersAccountHotlinkWhenAccountIdPresent` — opp empty + account set → `/lightning/r/Account/{id}/view`.
36. `rendersNoRecordLinkWhenBothIdsAbsent` — neither id → no `[data-test="record-link"]`.

### Empty

37. `rendersGracefullyOnEmptyEngagements` — engagements=[] → 0 rows, stats show 0/0, top topic '—'.

## Coverage target ≥95%

Specifically need to exercise:

- `timeAgoToPercent` piecewise math (covered indirectly by timeline tests #25, #26).
- `computeBadges` all three branches (onOcr, consultant, acr).
- `buildSummaryTooltip` all branches (touches singular vs plural, topics empty, lastTouchAt nullable, onOcr branches, consultant vs acr).
- `dismissContact` both success + error paths.

## Constraints

- Use the global `lightning/modal` mock — drop the per-file modal mock.
- `ShowToastEvent` is fired — capture via `document.body.addEventListener('lightning__showtoast', handler)`.
- Date math (`Date.now()`) — for deterministic timeline tests, freeze with `jest.useFakeTimers().setSystemTime(...)`.
