# LWC Conventions

Pointer + 1-page summary. The canonical source is [`best-practices/lwc.md`](../../best-practices/lwc.md) at the repo root — read that first. This page exists to (a) save you a click when you only need the headline rules and (b) capture the gotchas devs trip on after the rules are clear.

For broader architecture (trigger framework, Selector/Service/Domain layering, SOQL safety, async patterns) see [`best-practices/architecture.md`](../../best-practices/architecture.md). For Apex conventions on the controller backing every LWC see [`apex-conventions.md`](./apex-conventions.md) (Marlowe maintains).

## Canon summary

| Topic                | Rule                                                                                                                                                          | Source                                                                                   |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Folder / file naming | `camelCase/`, same camelCase for `.js` / `.html` / `.css` / `.js-meta.xml`, kebab-case `c-my-component` in markup                                             | [`lwc.md §File and folder naming`](../../best-practices/lwc.md#file-and-folder-naming)   |
| Class shape          | PascalCase, `extends LightningElement`. `@api` for public reactive props (camelCase). `@track` only when mutating internal object/array shape.                | [`lwc.md §Class and member naming`](../../best-practices/lwc.md#class-and-member-naming) |
| Wire adapters        | Wrap response in getters so the template never reads `data` / `error` directly. Refresh writes with `refreshApex(this.wired)`, not by re-calling imperative.  | [`lwc.md §Wire adapters`](../../best-practices/lwc.md#wire-adapters)                     |
| Apex from LWC        | Reads: `@AuraEnabled(cacheable=true)`. Writes: `@AuraEnabled`. Never swallow promise rejections — surface to user via toast.                                  | [`lwc.md §Apex from LWC`](../../best-practices/lwc.md#apex-from-lwc)                     |
| User-facing errors   | `lightning/platformShowToastEvent`. Friendly message. Log technical detail Apex-side via [`Logger`](../../force-app/main/default/classes/logging/Logger.cls). | [`lwc.md §Errors and toasts`](../../best-practices/lwc.md#errors-and-toasts)             |
| Platform events      | `lightning/empApi`. Unsubscribe in `disconnectedCallback`.                                                                                                    | [`lwc.md §Platform events`](../../best-practices/lwc.md#platform-events)                 |
| Strings              | Custom Labels via `@salesforce/label/c.<labelName>`. No hardcoded text in templates.                                                                          | [`lwc.md §Custom labels`](../../best-practices/lwc.md#custom-labels)                     |
| A11y                 | Every interactive element labelled (`aria-label` / `<label for>` / visible text). SLDS utility classes for layout.                                            | [`lwc.md §Accessibility`](../../best-practices/lwc.md#accessibility)                     |
| Testing              | Jest. Co-located in `__tests__/`. Mock Apex with `jest.mock('@salesforce/apex/...')`. Test render / events / error states — not internals.                    | [`lwc.md §Testing`](../../best-practices/lwc.md#testing)                                 |
| Performance          | No expensive work in getters. Prefer `lightning-record-form` for single-object CRUD. Lazy-load heavy conditionals.                                            | [`lwc.md §Performance`](../../best-practices/lwc.md#performance)                         |

## Things devs trip on (this codebase)

The rules above are clean. The friction is in how they compose. Eight patterns that recur in code review of this feature:

### 1. Wire-getter pattern when params are reactive

`@wire` re-runs whenever any `$reactive` parameter changes. That's the whole point. But you almost never want to wire directly on `@api recordId` — you want to wire on a **getter that returns the id only when the component is in the right scope**. Otherwise both your wires fire and you waste a server roundtrip on the one you don't need.

See [`engagementPanel.js` lines 84-102](../../force-app/main/default/lwc/engagementPanel/engagementPanel.js) — `opportunityIdParam` and `accountIdParam` resolve to `null` for the inactive scope, which short-circuits the wire. Two wires declared, one ever fires.

### 2. `cacheable=true` on every read

Every read-only `@AuraEnabled` method MUST be `cacheable=true`. The LDS cache is the difference between a snappy panel and a 400ms blink on every navigation. Examples in this codebase: [`EngagementController.getForOpportunity`](../../force-app/main/default/classes/engagement/EngagementController.cls), [`getForAccount`](../../force-app/main/default/classes/engagement/EngagementController.cls).

If you need to invalidate after a write, pass the original wire result handle to `refreshApex` — don't call the imperative variant. See [`engagementPanel.refresh()`](../../force-app/main/default/lwc/engagementPanel/engagementPanel.js).

### 3. Modal flows: `LightningModal.open(...)` and the `{ result, payload }` contract

This codebase uses `lightning/modal` everywhere. The host opens a modal with `await SomeModal.open({...props})` and the modal closes itself with `this.close({ result, payload })`. **There is no event dispatched from a `LightningModal` subclass that the host can receive** — the host listens to the return value of `open()`.

Modal subclasses extend `LightningModal` (not `LightningElement`):

```js
import LightningModal from 'lightning/modal';
export default class FooModal extends LightningModal {
    @api someProp;
    handleSave() { this.close({ result: 'success', payload: {...} }); }
    handleCancel() { this.close({ result: 'cancel' }); }
}
```

Host side:

```js
const result = await FooModal.open({ size: 'small', someProp: 'x' });
if (result?.result === 'success') { ... }
```

See [`addToDealTeamModal.js`](../../force-app/main/default/lwc/addToDealTeamModal/addToDealTeamModal.js) (modal side) and [`engagementPanel.handleAddClick`](../../force-app/main/default/lwc/engagementPanel/engagementPanel.js) (host side) for the canonical pair, including a chained second modal on race detection.

### 4. Shadow DOM walking in Jest tests

`@salesforce/sfdx-lwc-jest` renders into the **synthetic shadow DOM**. `document.querySelector(...)` returns nothing. Always go through the element's own shadow root:

```js
const el = element.shadowRoot.querySelector('[data-test="add-button"]');
```

Nested components also have their own shadow root — walk one level at a time. We use `data-test="..."` selectors for stability; class-based selectors are fragile under SLDS upgrades. See [`engagementPanel.test.js`](../../force-app/main/default/lwc/engagementPanel/__tests__/engagementPanel.test.js) for the pattern.

For modal subclasses, Jest tests instantiate them via `createElement` and assert on the rendered template — `LightningModal.open(...)` is mocked at the import boundary; you don't actually open a real modal in jsdom.

### 5. `js-meta.xml` baseline

Every `*.js-meta.xml` in this codebase has, at minimum:

- `<apiVersion>` — use the project's pinned version (currently `66.0`)
- `<isExposed>` — `true` for placeable components, `false` for modal subclasses and internal helpers
- `<masterLabel>` — what the admin sees in the App Builder palette (when `isExposed=true`)
- `<description>` — one sentence describing what the component does (the admin's hover hint)
- `<targets>` — every page type the component is valid on; pair with `<targetConfigs>` to expose design properties

Modal subclasses (`extends LightningModal`) are NOT placeable — set `<isExposed>false</isExposed>` and skip targets. See [`addToDealTeamModal.js-meta.xml`](../../force-app/main/default/lwc/addToDealTeamModal/addToDealTeamModal.js-meta.xml) vs [`engagementPanel.js-meta.xml`](../../force-app/main/default/lwc/engagementPanel/engagementPanel.js-meta.xml) for the two patterns side by side.

### 6. No inline styles in templates

`<div style="...">` is forbidden. Use the component's own `.css` file. The exception is **computed style values** that genuinely depend on data — e.g. the timeline dot positioning in [`engagementDetailModal.js timelineDots`](../../force-app/main/default/lwc/engagementDetailModal/engagementDetailModal.js) computes `top: <pct>%` in JS and passes the full string through `style={dot.style}`. That's allowed because the value can't be expressed in a class. If you find yourself writing literal style strings into a template, move them to `.css` and use a class.

### 7. Accessibility on every interactive element

Every clickable, focusable, or assistive-tech-relevant element needs at least one of:

- Visible text content (e.g. `<button>Cancel</button>`) — preferred
- `aria-label` for icon-only controls (`<lightning-button-icon alternative-text="Dismiss">`)
- `title` for fallback hover tooltips
- `role` + `tabindex` for non-semantic elements that need to be focusable (e.g. expandable rows in [`engagementDetailModal.html`](../../force-app/main/default/lwc/engagementDetailModal/engagementDetailModal.html))

`<lightning-button-icon>` already requires `alternative-text` — the framework will not let you ship without it. `<lightning-icon>` does NOT enforce it but you should still set it. For purely decorative icons (e.g. avatar role badges), `alternative-text=""` is the explicit "this is decoration" signal screen readers respect.

### 8. Race-protection: server is the source of truth

Any write that could race with another user's write needs server-side re-check inside the same transaction. The LWC pattern is: open a form modal, submit, the server returns `{ success: true, ocrId }` OR `{ alreadyExists: true, addedBy*, ocrId }`. Same shape either way — the host inspects the payload, not the HTTP status.

If `alreadyExists` is true, the host opens a confirmation modal explaining what happened and offering a navigation to the winning record. See the [`addToDealTeamModal` → `alreadyAddedModal` chain in `engagementPanel.handleAddClick`](../../force-app/main/default/lwc/engagementPanel/engagementPanel.js).

The point: **don't treat `alreadyExists` as a failure**. It's a normal outcome. The user gets a clean explanation, not a generic "save failed" toast.

## Related

- [`best-practices/lwc.md`](../../best-practices/lwc.md) — canonical conventions
- [`best-practices/architecture.md`](../../best-practices/architecture.md) — Selector/Service/Domain
- [`docs/development/components/`](./components/) — per-component reference (this team's LWCs)
- [`docs/development/apex-conventions.md`](./apex-conventions.md) — Apex side (Marlowe)

---

_Maintained by Lyric Astro. Sync changes with [`best-practices/lwc.md`](../../best-practices/lwc.md) — that file wins on conflicts; this one explains._
