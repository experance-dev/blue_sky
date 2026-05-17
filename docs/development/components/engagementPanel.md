# engagementPanel

The right-rail **Engagement Intelligence** panel. Renders on Account and Opportunity record pages, lists engaged contacts for the current record, and dispatches the "+ Add to Deal Team" / "View all" / dismiss flows. The headline LWC of the feature — every other LWC in this folder is opened by, or composes with, this one.

Source: [`force-app/main/default/lwc/engagementPanel/`](../../../force-app/main/default/lwc/engagementPanel/) — [`engagementPanel.js`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.js) · [`engagementPanel.html`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.html) · [`engagementPanel.css`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.css) · [`engagementPanel.js-meta.xml`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.js-meta.xml)

## Orientation

Two scopes, one component. `recordContext` is set in App Builder per page: `'Account'` on the Account record page renders a flat list scoped to the account; `'Opportunity'` partitions the list into **Deal Team** (on OCR) and **Engaged — not on Deal Team** (the buying-committee gap). Each row hotlinks to the Contact record (Lightning hovercard auto-attaches), shows touch count + topics + last-touch relative time, and exposes per-scope actions.

Behind the scenes the component declares **two `@wire` adapters** — one per Apex method — but only the wire whose parameter id is non-null actually fires. The inactive scope's `$param` getter returns `null`, which short-circuits the wire and keeps the LDS cache warm.

## Public API

### Properties

| Name            | Type                         | Required                                              | Description                                                                                                                                                                                                                                                                     |
| --------------- | ---------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `recordId`      | `Id`                         | yes (on a record page; auto-injected by the platform) | The Account or Opportunity id this panel is scoped to.                                                                                                                                                                                                                          |
| `recordContext` | `'Account' \| 'Opportunity'` | yes                                                   | Drives which Apex method runs and which rendering branch fires. Defaults to `'Opportunity'`. Set in App Builder via the `recordContext` design property — see [`engagementPanel.js-meta.xml`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.js-meta.xml). |
| `recordName`    | `String`                     | no                                                    | Display name used in the EngagementDetailModal header (e.g. `'United Healthcare'`).                                                                                                                                                                                             |

### Methods

| Name        | Returns         | Description                                                                                                                                  |
| ----------- | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `refresh()` | `Promise<void>` | Re-fires the active wire via `refreshApex`. Call after a host-orchestrated write to surface new data. Fires a `refresh` event on completion. |

### Events

| Event           | Detail                                        | When                                                                                                                                        |
| --------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `addtodealteam` | `{ contactId, name, currentRole, isPrimary }` | User clicked "+ Add" on a row. Fired BEFORE the modal opens — listen for it if you need to observe intent independent of the modal outcome. |
| `viewall`       | `{ recordId, recordContext }`                 | User clicked "View all". Fired BEFORE [`engagementDetailModal`](./engagementDetailModal.md) opens.                                          |
| `refresh`       | `{}`                                          | The panel re-loaded its data (after a successful add or `@api refresh()` call).                                                             |

All three events are `bubbles: true, composed: true` so they cross the shadow boundary cleanly.

## Wire dependencies

| Apex method                                                                                                             | Cacheable       | Parameters                                | Fires when                           |
| ----------------------------------------------------------------------------------------------------------------------- | --------------- | ----------------------------------------- | ------------------------------------ |
| [`EngagementController.getForOpportunity`](../../../force-app/main/default/classes/engagement/EngagementController.cls) | yes             | `{ opportunityId }`                       | `recordContext === 'Opportunity'`    |
| [`EngagementController.getForAccount`](../../../force-app/main/default/classes/engagement/EngagementController.cls)     | yes             | `{ accountId }`                           | `recordContext === 'Account'`        |
| [`EngagementController.dismissContact`](../../../force-app/main/default/classes/engagement/EngagementController.cls)    | no (imperative) | `{ contactId, opportunityId, accountId }` | User clicked the per-row `×` button. |

Both wires return `List<EngagementDTO>` — see [`EngagementDTO.cls`](../../../force-app/main/default/classes/engagement/EngagementDTO.cls) for the frozen shape. The Opportunity wire partitions the result via the `onOcr` flag on each DTO; the panel rendering layer reads `dealTeam` / `notOnDealTeam` getters off `engagements`.

## Permission gating

Two custom permissions gate this component. Pattern + rationale in [`lwc-visibility-patterns.md`](../lwc-visibility-patterns.md); this section is the engagementPanel-specific cheatsheet.

| Custom permission                                                                                                                              | Imported as        | Controls                                                                                    |
| ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ | ------------------------------------------------------------------------------------------- |
| [`Marketing_Influence_View`](../../../force-app/main/default/customPermissions/Marketing_Influence_View.customPermission-meta.xml)             | `hasViewPerm`      | `canViewPanel` getter — wraps the entire `<article>`. No perm = panel hidden.               |
| [`Marketing_Influence_Power_User`](../../../force-app/main/default/customPermissions/Marketing_Influence_Power_User.customPermission-meta.xml) | `hasPowerUserPerm` | `canActOnPanel` getter — wraps **View all**, **+ Add**, **Dismiss**. View tier = read-only. |

Both perms use strict `=== true` comparison in the getters — see [`engagementPanel.js` lines 113–119](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.js).

### What each tier sees

| Tier                                             | Panel container | Contact rows + chips + badges | View all | + Add   | Dismiss |
| ------------------------------------------------ | --------------- | ----------------------------- | -------- | ------- | ------- |
| No MI permset                                    | hidden          | hidden                        | hidden   | hidden  | hidden  |
| `Permset_Marketing_Influence_View`               | visible         | visible                       | hidden   | hidden  | hidden  |
| `Permset_Marketing_Influence_Power_User` / Admin | visible         | visible                       | visible  | visible | visible |

### FlexiPage Component Visibility (first line of defense)

In addition to the intra-LWC gating, every FlexiPage that hosts `c:engagementPanel` carries a `visibilityRule` on the `Marketing_Influence_View` custom permission. Users without the View perm don't render the panel at all — defense-in-depth against an edited FlexiPage and a saved bandwidth round-trip on the wires. The five FlexiPages currently carrying the panel:

- [`Opportunity_Engagement_Record_Page`](../../../force-app/main/default/flexipages/Opportunity_Engagement_Record_Page.flexipage-meta.xml) — MI-owned
- [`Account_Engagement_Record_Page`](../../../force-app/main/default/flexipages/Account_Engagement_Record_Page.flexipage-meta.xml) — MI-owned
- [`Account_Record_Page_Provider`](../../../force-app/main/default/flexipages/Account_Record_Page_Provider.flexipage-meta.xml) — Zelis-owned, contributed additively
- [`PE_Payer_Record_Page`](../../../force-app/main/default/flexipages/PE_Payer_Record_Page.flexipage-meta.xml) — Zelis-owned, contributed additively
- [`PE_Provider_Account_Record_Page`](../../../force-app/main/default/flexipages/PE_Provider_Account_Record_Page.flexipage-meta.xml) — Zelis-owned, contributed additively

If you add a sixth FlexiPage, copy the `visibilityRule` block from any of the above — the `$Permission.CustomPermission.Marketing_Influence_View` form is FlexiPage-specific. Details in [`lwc-visibility-patterns.md` Step 4](../lwc-visibility-patterns.md).

### Test files (one per perm combination)

- [`engagementPanel.test.js`](../../../force-app/main/default/lwc/engagementPanel/__tests__/engagementPanel.test.js) — both perms granted (Power User render path).
- [`engagementPanel.perm-view.test.js`](../../../force-app/main/default/lwc/engagementPanel/__tests__/engagementPanel.perm-view.test.js) — View granted, Power User not (read-only render path).
- [`engagementPanel.perm-none.test.js`](../../../force-app/main/default/lwc/engagementPanel/__tests__/engagementPanel.perm-none.test.js) — neither granted (outer `lwc:if` blocks the panel).

## Modal flows

Three modal subclasses are chained from the panel — all opened via `LightningModal.open(...)`, all closed with `{ result, payload }`:

- **[`addToDealTeamModal`](./addToDealTeamModal.md)** — opens on "+ Add" click. Returns `{ result: 'success', payload: <AddToOcrResult> }`, `{ result: 'cancel' }`.
- **[`alreadyAddedModal`](./alreadyAddedModal.md)** — chained if the addToDealTeam payload is `{ alreadyExists: true }`. Returns `{ result: 'closed' }` or `{ result: 'navigated' }`.
- **[`engagementDetailModal`](./engagementDetailModal.md)** — opens on "View all". May return `{ result: 'add-to-team', payload: { contactId, contactName } }`, in which case the panel chains into the addToDealTeam → alreadyAdded flow with the contact from the detail modal.

See [`handleAddClick`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.js) and [`handleViewAll`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.js) for the canonical chain.

## Parent integration

The panel is dropped via App Builder. For the demo flexipages, see [`Opportunity_Engagement_Record_Page.flexipage-meta.xml`](../../../force-app/main/default/flexipages/Opportunity_Engagement_Record_Page.flexipage-meta.xml) and [`Account_Engagement_Record_Page.flexipage-meta.xml`](../../../force-app/main/default/flexipages/Account_Engagement_Record_Page.flexipage-meta.xml). The minimum embed:

```xml
<itemInstances>
    <componentInstance>
        <componentName>c:engagementPanel</componentName>
        <componentInstanceProperties>
            <name>recordContext</name>
            <value>Opportunity</value>
        </componentInstanceProperties>
    </componentInstance>
</itemInstances>
```

`recordId` is auto-injected on a `lightning__RecordPage` target. On a `lightning__AppPage` or `lightning__HomePage` you must wire an `@api recordId` in from a parent. The component's `targets` also include those page types — see [`engagementPanel.js-meta.xml`](../../../force-app/main/default/lwc/engagementPanel/engagementPanel.js-meta.xml).

### Programmatic embed example

```html
<c-engagement-panel
  record-id="{accountId}"
  record-context="Account"
  record-name="{accountName}"
  onaddtodealteam="{handleAddToDealTeam}"
  onviewall="{handleViewAll}"
  onrefresh="{handleRefresh}"
>
</c-engagement-panel>
```

Then call `this.template.querySelector('c-engagement-panel').refresh()` to force a reload from a parent context.

## Accessibility

- Every row's avatar `<span>` has `role="img"` + `aria-label` of the contact name.
- The contact hotlink (`<a>`) carries a multi-line `title` summary (touch count, topics, last-touch date, OCR status, ACR/consultant status) — built by `buildSummaryTooltip(dto)`. Lightning's record hovercard ALSO attaches automatically because the href matches `/lightning/r/.../view`; the `title` is the lightweight fallback for the first ~1s before the hovercard renders.
- "+ Add" and dismiss `×` buttons are real `<button>` / `<lightning-button-icon>` elements — focusable, keyboard-activatable, with `title` for tooltip and `alternative-text` for the icon-only dismiss.
- The error banner uses `role="alert"` so screen readers announce it on the failure path.
- Topic chips render as `<li role="listitem">` inside a `<ul role="list">` — the explicit roles defeat SLDS's `list-style: none` shadowing the implicit listitem role in some screen readers.

Keyboard map: standard Tab order — record link → "+ Add" → dismiss `×` → next row. No custom shortcuts.

## Known limitations

- **Wire fires twice on first render in some Lightning versions.** Both `@wire` adapters initialize before the reactive getter resolves to `null`, producing one wasted server call against the inactive scope. The cost is bounded (single empty query) and the cache keeps it from repeating on re-render.
- **`recordName` is not auto-resolved.** If you want the detail modal header to read "Engagement Intelligence — United Healthcare", a parent has to pass it in. The platform doesn't inject `Name` alongside `recordId`. Phase 1.5 candidate: use `@wire(getRecord, ...)` to pull `Name` automatically.
- **Dismiss is per-user, per-scope.** A contact dismissed on the Opportunity panel still shows on the Account panel. The server records dismissals scoped to the (user, contact, opp-or-account) triple. Re-emerges when a new `Engagement_Touch__c` lands. This is the documented behavior — not a bug — but it surprises people.

## Tests

- Jest: [`engagementPanel.test.js`](../../../force-app/main/default/lwc/engagementPanel/__tests__/engagementPanel.test.js) — covers Opportunity / Account branching, partitioning by `onOcr`, "+ Add" event dispatch, modal open / refresh chain (modal mocked at import).
- Apex backing the wires: [`EngagementControllerTest.cls`](../../../force-app/main/default/classes/engagement/EngagementControllerTest.cls), [`EngagementServiceImplTest.cls`](../../../force-app/main/default/classes/engagement/EngagementServiceImplTest.cls).

## Related

- Apex controller: [`EngagementController.cls`](../../../force-app/main/default/classes/engagement/EngagementController.cls)
- DTO: [`EngagementDTO.cls`](../../../force-app/main/default/classes/engagement/EngagementDTO.cls)
- Modal chain: [`addToDealTeamModal`](./addToDealTeamModal.md) · [`alreadyAddedModal`](./alreadyAddedModal.md) · [`engagementDetailModal`](./engagementDetailModal.md)
- Conventions: [`docs/development/lwc-conventions.md`](../lwc-conventions.md)
- Visibility gating: [`docs/development/lwc-visibility-patterns.md`](../lwc-visibility-patterns.md)
- Demo flow: [`docs/users/DEMO.md`](../../users/DEMO.md)
- User-facing guide: [`docs/users/sales-rep-guide.md`](../../users/sales-rep-guide.md)
