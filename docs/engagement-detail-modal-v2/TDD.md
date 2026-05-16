# Technical Design Document (TDD)

# Marketing Influence — Engagement Detail Modal v2

|                   |                                                                                                                                                                                                                                                                     |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Document type** | Technical Design Document                                                                                                                                                                                                                                           |
| **Feature**       | Marketing Influence — Engagement Detail Modal v2                                                                                                                                                                                                                    |
| **Version**       | 2.0                                                                                                                                                                                                                                                                 |
| **Author**        | Atlas (TA), with contributions from Nova (UX) · Iris (SA)                                                                                                                                                                                                           |
| **Date**          | 2026-05-16                                                                                                                                                                                                                                                          |
| **Status**        | DRAFT — pending Atlas approval to dispatch dev teams                                                                                                                                                                                                                |
| **Approvers**     | Atlas (TA — gates dev start) · Sage Cloudy (Security — gates hierarchy release)                                                                                                                                                                                     |
| **Related**       | [BRD-Engagement-Detail-Modal-v2.md](./BRD-Engagement-Detail-Modal-v2.md) · [engagement-timeline.md](design-spec.md) · [brief-interesting-moments.md](brief-interesting-moments.md) · [brief-account-hierarchy-engagement.md](brief-account-hierarchy-engagement.md) |

---

## 1. Architecture overview

### 1.1 Component map

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                  LWC: engagementDetailModal (existing, extended)             │
│                                                                              │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│   │ scopeChip    │  │ campaign     │  │ ganttCanvas  │  │ bottomCards     │ │
│   │ (header)     │  │ Strip        │  │ (Gantt viz)  │  │ (4 mini-cards)  │ │
│   │ NEW sub-LWC  │  │ NEW sub-LWC  │  │ NEW sub-LWC  │  │ NEW composite   │ │
│   └──────────────┘  └──────────────┘  └──────────────┘  └─────────────────┘ │
│                                                                              │
│   single source of truth in parent: filterCampaignId, selectedContactId,     │
│   scope (enum), windowDays (enum)                                            │
└──────────────────────────────────────────────────────────────────────────────┘
                          │ @AuraEnabled
                          ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│              Apex: EngagementDetailController (NEW @AuraEnabled facade)      │
│                                                                              │
│   getEngagementDetail(parentId, scope, windowDays) → EngagementDetailDTO     │
└──────────────────────────────────────────────────────────────────────────────┘
                          │
       ┌──────────────────┴──────────────────────┐
       ▼                                          ▼
┌─────────────────────────┐         ┌────────────────────────────────────┐
│  EngagementDetailService │         │  HierarchyScopeResolver (NEW)      │
│  (NEW — orchestrator)    │ ──▶──── │  resolveAccountIds(parentId,scope) │
└─────────────────────────┘         └────────────────────────────────────┘
       │
       ├──▶ EngagementTouchSelector.queryForAccountIds(...)    [extends existing selector]
       ├──▶ CampaignRollupCalculator (NEW)
       ├──▶ InterestingMomentEvaluator (NEW — pure function over a touch + active rules)
       └──▶ DealTeamGapCalculator (NEW)
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Custom Object: Engagement_Touch__c (EXISTING — adds 2 fields)               │
│  Custom Metadata: Interesting_Moment_Rule__mdt (NEW)                         │
│  Standard:   Account (with ParentId hierarchy traversal)                     │
│  Standard:   OpportunityContactRole / AccountContactRelation / LCR__c        │
└──────────────────────────────────────────────────────────────────────────────┘

           Async:                                  Async:
           InterestingMomentEvaluatorTrigger        Backfill batch on rule change
           (runs on Engagement_Touch__c insert/update)
```

### 1.2 Code-organization principles

- Follows existing Selector / Service / Domain pattern (per [best-practices/architecture.md](../../best-practices/architecture.md)).
- All `@AuraEnabled` methods on `EngagementDetailController` only; orchestration lives in `EngagementDetailService`.
- All SOQL via the Selector layer (`EngagementTouchSelector`, new `AccountHierarchySelector`).
- All DML via `DMLManager` with `AccessLevel.USER_MODE`.
- `with sharing` on every class touching user data.
- All Apex headers attribute to **David Wood** only (per [feedback-sf-attribution](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_sf_attribution.md)).
- `Logger.cls` for all error capture (no `System.debug` in non-test code).

## 2. Data model

### 2.1 New fields on `Engagement_Touch__c`

| API Name                       | Type     | Length / Precision | Indexed            | Description                                                                                                                              |
| ------------------------------ | -------- | ------------------ | ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `Is_Interesting_Moment__c`     | Checkbox | n/a                | YES (custom index) | True if the touch matches an active `Interesting_Moment_Rule__mdt`. Indexed because the campaign strip + bottom card query by this flag. |
| `Interesting_Moment_Reason__c` | Text     | 255                | NO                 | The DeveloperName of the rule that flagged the touch. Auditable; displayed in tooltips.                                                  |

Both fields are populated by the `InterestingMomentEvaluator` (called from a Trigger handler).

### 2.2 New Custom Metadata Type: `Interesting_Moment_Rule__mdt`

| API Name                                 | Type      | Length | Description                                                      |
| ---------------------------------------- | --------- | ------ | ---------------------------------------------------------------- |
| `Active__c`                              | Checkbox  | —      | Disable a rule without deleting it.                              |
| `Priority__c`                            | Number    | 3,0    | Order rules are evaluated. Lower wins.                           |
| `Display_Name__c`                        | Text      | 80     | Short label for the reason field.                                |
| `Description__c`                         | Long Text | 1024   | Why this rule exists (auditable).                                |
| `Match_Campaign_Id__c`                   | Text      | 18     | Optional — match touches in this campaign.                       |
| `Match_Asset_Name_Contains__c`           | Text      | 80     | Optional — substring match on the asset name (case-insensitive). |
| `Match_Touch_Type__c`                    | Text      | 40     | Optional — exact match on touch type (e.g., "DEMO_REQUEST").     |
| `Min_Score__c`                           | Number    | 5,0    | Optional — minimum touch score to qualify.                       |
| `Min_Touches_From_Same_Contact_Hours__c` | Number    | 5,0    | Optional — flag if N+ touches from same contact within N hours.  |

Rules are AND-combined; if no match-criteria fields are set, the rule never fires.

### 2.3 No new SObjects

`Engagement_Touch__c` already carries the campaign, contact, asset, score, source, and timestamp fields. We extend, not duplicate. (See [feedback-extend-not-modify-third-party](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_extend_not_modify_third_party.md) — applies internally too.)

## 3. Apex layer

### 3.1 New classes

| Class                            | Type                                 | Responsibility                                                                                                                                                          |
| -------------------------------- | ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `EngagementDetailController`     | `with sharing`, `@AuraEnabled`       | LWC-facing facade. One method: `getEngagementDetail(parentId, scope, windowDays)`. Returns `EngagementDetailDTO` (extends existing `EngagementDTO`). No business logic. |
| `EngagementDetailService`        | `with sharing`                       | Orchestrator. Resolves scope → queries touches → calculates rollups → assembles DTO. Bulkified; one transaction.                                                        |
| `HierarchyScopeResolver`         | `with sharing`                       | Given (Account Id, scope), returns a `List<Id>` of accessible Account Ids. Honors `WITH USER_MODE`. Caps depth at 5 (configurable via `MI_Settings__mdt`).              |
| `AccountHierarchySelector`       | `with sharing`                       | SOQL for Account hierarchy traversal using dot-notation `Account.Parent.Parent.Parent.Id`.                                                                              |
| `CampaignRollupCalculator`       | `with sharing`                       | Computes per-campaign rollup (count, delta vs prev week, lastTouchAt, ★ count). Pure function over `List<Engagement_Touch__c>`.                                         |
| `InterestingMomentEvaluator`     | `with sharing`                       | Evaluates a single touch against active rules. Cached rule list per-transaction. Used by trigger handler + backfill.                                                    |
| `InterestingMomentBackfillBatch` | `with sharing`, `Database.Batchable` | Re-evaluates historical touches when rules change. Re-runnable. Configurable scope.                                                                                     |
| `DealTeamGapCalculator`          | `with sharing`                       | Returns the list of engaged contacts NOT on the parent record's deal team (OCR for Opp, ACR for Account, LCR\_\_c for Lead).                                            |

### 3.2 Extended classes

| Class                           | Change                                                                                                                                                                                                                             |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `EngagementTouchTriggerHandler` | Add a new `beforeInsert` and `beforeUpdate` handler that calls `InterestingMomentEvaluator` to set `Is_Interesting_Moment__c` and `Interesting_Moment_Reason__c`.                                                                  |
| `EngagementTouchSelector`       | Add `queryByAccountIdsAndWindow(Set<Id> accountIds, Integer windowDays)` that respects `WITH USER_MODE`.                                                                                                                           |
| `EngagementDTO`                 | Extend with: `campaignRollups: List<CampaignRollup>`, `interestingMoments: List<InterestingMoment>`, `dealTeamGaps: List<ContactSummary>`, `scopeApplied: String`, `accountsVisible: Integer`, `accountsHiddenBySharing: Integer`. |

### 3.3 Method signatures (key entries)

```apex
public with sharing class EngagementDetailController {
  /**
   * @description Returns engagement detail DTO for the given parent record + scope.
   * @param parentId   The record from which the modal is invoked (Account, Opp, Lead).
   * @param scope      Enum: 'THIS_ACCOUNT' | 'WITH_CHILDREN' | 'WHOLE_HIERARCHY'.
   * @param windowDays Integer: 42 (6w), 90 (3mo), 180 (6mo), 365 (1yr), or -1 (+ future / all).
   * @return EngagementDetailDTO with all rollups + touches.
   * @throws AuraHandledException (with Logger correlation ID; no internal stack).
   */
  @AuraEnabled(cacheable=false)
  public static EngagementDetailDTO getEngagementDetail(
    Id parentId,
    String scope,
    Integer windowDays
  ) {
    /* ... */
  }
}
```

```apex
public with sharing class HierarchyScopeResolver {
  public static List<Id> resolveAccountIds(Id parentId, String scope) {
    // 1. Look up parentId's SObject type
    // 2. If 'THIS_ACCOUNT' (or parent isn't Account) → return [parentId]
    // 3. If 'WITH_CHILDREN' → query [SELECT Id FROM Account WHERE ParentId = :acctId WITH USER_MODE]
    // 4. If 'WHOLE_HIERARCHY' → traverse parent + children + siblings
    //    Cap depth at MI_Settings__mdt.Max_Hierarchy_Depth__c (default 5)
    // 5. Return only Ids the running user can SELECT (WITH USER_MODE handles)
  }
}
```

### 3.4 Permission / sharing enforcement

- **Every SOQL** in this feature includes `WITH USER_MODE`. No exceptions.
- **Every DML** uses `AccessLevel.USER_MODE` (via `DMLManager`).
- **Apex Class Access** added to every permset (`MI_View`, `MI_Power_User`, `MI_Admin`) for the new `@AuraEnabled` controller class.
- **Hierarchy resolver** returns only the account IDs the user can read; the LWC computes "hidden by sharing" count from the difference between request-set-size and resolver-returned-size.
- **AuraHandledException** never carries internal exception text. The controller catches, calls `Logger.error(...)`, captures the Logger record's correlation ID, and throws `new AuraHandledException('Marketing Influence is temporarily unavailable. Error ID: ' + corrId);` (per [feedback](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_owd_private_permset_architecture.md) and Sage's standing guidance).

## 4. LWC layer

### 4.1 Component hierarchy

```
engagementDetailModal (parent, existing — extended)
├── miHierarchyScopeChip (NEW sub-component — inline header chip + popover)
├── miCampaignStrip (NEW sub-component — 7-card horizontal strip)
├── miGanttCanvas (NEW sub-component — Gantt viz)
│   ├── miGanttLane (NEW — one per contact; sticky lane label + dots)
│   └── miGanttTimeAxis (NEW — top scale; sticky-top during scroll)
├── miBottomCards (NEW composite)
│   ├── miActivityFeedCard (NEW — slds-timeline for selected contact)
│   ├── miInterestingMomentsCard (NEW — list of ★ moments)
│   ├── miTouchesByAccountCard (NEW — hierarchy roll-up)
│   └── miDealTeamGapsCard (NEW — gaps with inline + buttons)
└── miStatePresenter (NEW — empty / loading / error switch)
```

### 4.2 State management

Parent `engagementDetailModal` holds the single source of truth:

```js
@track viewState = 'loading';           // 'loading' | 'data' | 'empty' | 'error'
@track scope = 'THIS_ACCOUNT';
@track windowDays = 42;
@track selectedContactId = null;
@track filterCampaignId = null;         // null = all campaigns
@track dto = null;                       // EngagementDetailDTO
@track errorCorrelationId = null;
```

Children receive via `@api` and emit `change` events upward. No two-way data binding.

### 4.3 Static resource: `miIllustrations`

Located at [force-app/main/default/staticresources/miIllustrations/](../../force-app/main/default/staticresources/miIllustrations/). Bundle contains:

- `desert.svg` — SLDS canonical "Desert" (no-data) illustration. Used in the empty state.
- `no_connection.svg` — SLDS canonical "No Connection" (error) illustration. Used in the error state.

Source: extracted from `salesforce-ux/design-system` GitHub repo (`ui/components/illustration/nodata/` and `ui/components/illustration/error/`). They reference SLDS CSS classes (`slds-illustration__stroke-primary`, `slds-illustration__stroke-secondary`, `slds-illustration__fill-secondary`) for color theming — these are applied automatically when SLDS is loaded in the LWC context.

LWC import pattern:

```js
import MI_ILLUSTRATIONS from '@salesforce/resourceUrl/miIllustrations';
// in template:
// <img src={emptyIllustrationUrl} alt="..." class="slds-illustration__svg"/>
get emptyIllustrationUrl() { return MI_ILLUSTRATIONS + '/desert.svg'; }
get errorIllustrationUrl() { return MI_ILLUSTRATIONS + '/no_connection.svg'; }
```

For SLDS-class-aware rendering, the SVG can also be **inlined** into the state component's template (preferred when the LWC needs the stroke/fill classes to inherit theming). See `engagement-timeline-empty.html` mockup for the inline pattern.

### 4.4 Responsive layout

CSS Grid + Flexbox; **no fixed widths.** Modal max-width 1320px. Breakpoints:

- ≥1180px: 7-card campaign strip; 4-card bottom row.
- 920–1180px: campaign strip wraps to 4 cols × 2 rows; bottom row to 2×2.
- 760–920px: lane labels shrink to 220px; title-role line hides; bottom 1×4.
- <760px: campaign strip 2-col; full-screen modal sheet on mobile.

Sticky lane label column via `position: sticky; left: 0` inside a shared horizontal scroll container.

### 4.5 Accessibility

- Modal: `role="dialog" aria-labelledby="modal-title"`. Focus trapped inside.
- Gantt-as-table: `role="table"` with proper row/cell semantics for screen readers.
- All interactive elements have `aria-label` or visible labels. Buttons have `aria-pressed` where toggle-able.
- `aria-live="polite"` region announces filter / selection changes.
- Color is never the only signal: ★ Interesting Moments use icon + color + size; selected lane uses bg + ★ + thicker bar.
- All hover states reachable via keyboard.

## 5. Component visibility / permset architecture

Per [feedback-owd-private-permset-architecture](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_owd_private_permset_architecture.md):

### 5.1 Custom permissions

| Custom Permission                  | Granted to                 | Purpose                                                              |
| ---------------------------------- | -------------------------- | -------------------------------------------------------------------- |
| `Marketing_Influence_View`         | `MI_View` permset (and up) | Gates the LWC visibility via App Builder Component Visibility rules. |
| `Marketing_Influence_Edit_Roles`   | `MI_Power_User` (and up)   | Gates the "Edit OCR/ACR/LCR" affordance (role chip).                 |
| `Marketing_Influence_Manage_Rules` | `MI_Admin` only            | Gates write access to the Interesting Moment Rule CMDT.              |

### 5.2 Permset ladder

| Permset    | Name                                                      | Includes                                                                                                                               |
| ---------- | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| View       | `Additional Permissions - Marketing Influence View`       | Read on `Engagement_Touch__c` + new fields; Apex Class Access to `EngagementDetailController`; `Marketing_Influence_View` custom perm. |
| Power User | `Additional Permissions - Marketing Influence Power User` | View tier + write on OCR/ACR/LCR; `Marketing_Influence_Edit_Roles`.                                                                    |
| Admin      | `Additional Permissions - Marketing Influence Admin`      | Power User tier + CMDT write; `Marketing_Influence_Manage_Rules`.                                                                      |

### 5.3 Component Visibility rule

On the FlexiPage placements of `engagementDetailModal` (and its launcher panel): `$Permission.Marketing_Influence_View == true`. Users without the perm don't see the panel at all.

### 5.4 Tab visibility

If shipping the admin console for Interesting Moments rules: Tab visible on `MI_Admin` only.

## 6. Performance / governor limits

| Path                | Worst-case sizing                                        | Mitigation                                                                                                                                                           |
| ------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Hierarchy traversal | 5 levels × 20 children/level = 20⁵ = 3.2M accounts       | Cap at `MI_Settings__mdt.Max_Hierarchy_Depth__c` (default 5). If sibling-count > 200 at any level, fall back to async batch.                                         |
| Touch query         | 500 touches/account × 100 accounts in hierarchy = 50,000 | Cap result at 500 touches total (already enforced in v1). Order by `Touch_Datetime__c DESC` to keep most-recent. Surface a footnote: "showing most recent 500 of N." |
| Rule evaluation     | 75 touches × 20 active rules = 1,500 iterations          | Pure-function evaluation; cached rule list per-transaction; <50ms in practice.                                                                                       |
| DTO serialization   | 500 touches × ~12 fields = ~75KB JSON                    | Cap at 500; warn at 400 via Logger.                                                                                                                                  |

P95 target: 1.5s modal-render-to-data. Apex `Logger.metric()` traces both selector time and total transaction time.

## 7. Test strategy

Per [TEAM.md](../../.claude/agents/TEAM.md): **TDD — red tests first.** Pippa's team writes the failing tests against the BRD acceptance criteria; Boomer's team writes production code to turn them green.

### 7.1 Apex test coverage targets

- ≥95% line coverage per [feedback-test-quality-metrics](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_test_quality_metrics.md).
- 100% on the security boundary (sharing tests, USER_MODE tests).
- Per-method good-path + bad-path tests (per [feedback-persona-path-coverage](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_persona_path_coverage.md)).

### 7.2 Critical test scenarios

1. **HierarchyScopeResolver**:
   - This account only / + children / whole hierarchy returns the right ID set.
   - User without read access to a sibling sees the sibling excluded silently.
   - 5-level depth caps; deeper hierarchies trigger fallback.
   - Bulk: 200 parent records resolved in one transaction without breach.
2. **EngagementTouchSelector**:
   - `WITH USER_MODE` blocks records the user can't read.
   - 500-touch cap enforced.
   - Window math (windowDays) correct at boundary.
3. **InterestingMomentEvaluator**:
   - Each rule type fires correctly (campaign / asset / touch-type / score / multi-touch threshold).
   - Multiple rules: priority order respected; first match wins.
   - Inactive rule doesn't fire.
   - Backfill batch re-evaluates correctly when rules change.
4. **EngagementDetailController**:
   - Returns DTO for happy path.
   - Throws `AuraHandledException` with correlation ID on internal error.
   - Never returns internal exception text.
   - Empty result returns `viewState = 'empty'` DTO (not null).
5. **Permset enforcement**:
   - `MI_View` user can read but cannot edit roles.
   - `MI_Power_User` can edit roles but cannot manage rules.
   - `MI_Admin` can manage CMDT.
6. **Sharing**:
   - Account-private sibling: touches at the sibling excluded.
   - Footnote count accurate.
   - Aggregate stats (engaged count, touches count) match the visible-only data.

### 7.3 LWC test coverage

Jest tests for each new sub-component:

- `miHierarchyScopeChip` — scope change emits event upward.
- `miCampaignStrip` — click chip emits filter event; "All" chip clears.
- `miGanttCanvas` — renders correct dot count; selecting a contact emits event.
- `miStatePresenter` — switches between loading / data / empty / error correctly.

### 7.4 No real emails / no test cheating

Per [feedback-no-real-emails-from-tests](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_no_real_emails_from_tests.md) and [feedback-calling-card-no-commentary](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_calling_card_no_commentary.md): no `Messaging.sendEmail` in tests; factories satisfy every VR; no shortcuts.

## 8. Deployment plan

### 8.1 Sequencing (recommended by Nova's briefs)

1. **Interesting Moments** ships first (lower risk, no sharing surface). [Brief](brief-interesting-moments.md).
2. **Account Hierarchy** ships second. [Brief](brief-account-hierarchy-engagement.md). **Sage gate is the long pole.**

### 8.2 Each release follows the [TEAM.md workflow](../../.claude/agents/TEAM.md):

1. Iris writes tickets with test-assertable ACs → docs/tickets/.
2. Iris gate-1 spec approval → hands to Atlas.
3. Atlas routes to Pippa → red tests written first.
4. Pippa's red suite back to Atlas → confirms ACs covered.
5. Atlas routes to Boomer (Apex) / Coda (LWC) — they see red tests in place.
6. Dev → green; PR opened → `/review-pr`; Sr review → Atlas review → Sage review (parallel).
7. Wren validates end-to-end in scratch org (smoke + Playwright).
8. Marlowe / Lyric docs updated on same branch.
9. Dash deploys via `sf project deploy start --target-org dwood_z` (held until David clears, per [feedback-hold-deploys-default](../../.claude/projects/-Users-david-Work-Zelis/memory/feedback_hold_deploys_default.md)).
10. Iris runs delivery acceptance.
11. Atlas signs off → release.

### 8.3 Permset rollout

For each feature ship: deploy new permsets first → assign to test users (Mira) → smoke test → broadcast assignment via Manage-Assignments doc in the runbook → Zelis admins compose into Persona PSGs.

## 9. Operational concerns

| Concern                    | Plan                                                                                                                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Error monitoring**       | `Logger.error` on every catch boundary. Daily dashboard query: `SELECT COUNT(Id) FROM Logger_Log__c WHERE Component__c LIKE 'MI%' AND Severity__c = 'ERROR' AND CreatedDate = TODAY`. |
| **Performance monitoring** | `Logger.metric('mi-modal.render-time-ms', ...)` on every controller entry. Alert >2s P95.                                                                                             |
| **Rule changes audit**     | CMDT change history captured in deploy log + Logger entry on rule activation/deactivation.                                                                                            |
| **Backfill triggers**      | Manual: Admin runs `InterestingMomentBackfillBatch` from a dev console action button (gated on `MI_Admin`). Automatic option: nightly schedulable, off by default.                    |
| **Subject-erasure / GDPR** | Touches link to Contacts; when Contact is anonymized (existing cascade), touches FK to the new pseudonymized record stay. No new cascade path. Sage to verify.                        |

## 10. Open items requiring Atlas decisions

- [ ] **Approve the seven new Apex classes** and the existing-class extension plan in §3.
- [ ] **Approve the static-resource pattern** (`miIllustrations` bundle, SLDS canonical SVGs) vs. inline-SVG-only.
- [ ] **Approve the permset ladder names** (per Zelis convention `Additional Permissions - <Feature> <Tier>`).
- [ ] **Confirm 500-touch cap** is sufficient for the hierarchy-rollup case at largest expected accounts. (Iris/David could push to 1000 if Sage-OK.)
- [ ] **Decide rule-evaluation timing** — sync on trigger (faster apparent flag arrival) vs. async via Platform Event (lower trigger surface). Current default: sync.
- [ ] **Confirm `Logger.cls` exposure** in the controller's AuraHandledException flow — Logger is in the org per CSI-7162; just confirm permset access for callers.

## 11. Dispatch — ready for Atlas

After Atlas approves §3–§10, the dispatch order to dev teams:

1. **Iris** → resolve open questions in BRD §7 with David / Zelis Marketing.
2. **Pippa** → test design for both briefs (Interesting Moments + Account Hierarchy).
3. **Sage** → join the design conversation EARLY for Account Hierarchy (her review is BLOCKING and the long pole).
4. **Boomer** → schema design (the 2 fields + the CMDT).
5. **Coda** → LWC component breakdown (sub-component split per §4.1).
6. **Nova** → polish any state mocks Atlas flags as missing once decomposition surfaces gaps.
7. **Dash** → permset deploy plan; scratch-org refresh; `.forceignore` updates.

See the dispatch prompt at [BRD-Atlas-Dispatch.md](./BRD-Atlas-Dispatch.md) for the exact text to fire at Atlas.

---

**Atlas signs here:** `_________________` / Date: `_____________`
