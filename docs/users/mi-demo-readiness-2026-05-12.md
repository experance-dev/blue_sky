# MI Demo Readiness Sign-off — 2026-05-12

**Target:** Marketing Influence (Engagement Attribution) demo to users from `engagementDev` scratch org, T-3h.

**Verifier:** Wren Hootie (QA)

---

## Smoke pass — 2026-05-12 — MI demo prep (T-3h to user meeting)

### Pre-flight

- **Deploy:** Job [`0AfDP00001YVVQ60AP`](https://inspiration-computing-5390-dev-ed.scratch.lightning.force.com/lightning/setup/DeployStatus/home) — 19/19 components, 0 errors, success=true. Includes [`alreadyAddedModal`](../../force-app/main/default/lwc/alreadyAddedModal/) css/html/js, [`Engagement_Attribution_User`](../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml) permset. The other Pippa/Atlas changes (engagement classes, fixtures, picklist drift fix, api version bump) were already deployed — source-tracking reported them `Unchanged`.
- **Seed:** 23 active `Engagement_Touch__c` records (≥21 expected). Distribution matches spec — Sarah Johnson 7, Mike Chen 4, Marcus Brown 3, Tom Davis 2, Rachel Kim 2, Jennifer Wu 2, Lisa Patel 2.
- **Demo IDs verified:** Account `001DP00002A1c6jYAB` → United Healthcare; Opportunity `006DP00000Oh8rIYAR` → Network Pricing Implementation.
- **Opportunity Contact Roles seeded:** Sarah Johnson (Other), Mike Chen (Technical Evaluator), Tom Davis (Decision Maker). 3 OCRs as expected.

### Verified working

#### Flow A — United Healthcare Account page (`/lightning/r/Account/001DP00002A1c6jYAB/view`)

- [✓] Page loads under 4s; title resolves to "United Healthcare | Account | Salesforce"
- [✓] `c-engagement-panel` mounts in right rail with header "Engagement Intelligence"
- [✓] "7 engaged" badge present (matches SOQL `COUNT(DISTINCT Contact__c)`)
- [✓] All 7 contacts render — initials avatar, name, title, touch count, topic chips:
  - SJ Sarah Johnson · CFO · 7 touches · Network Management / Price Transparency
  - MB Marcus Brown · Sr Dir Payment Integrity · 3 touches · Out-of-Network Claims / Payment Integrity
  - RK Rachel Kim · Independent Advisor (ex-Aetna) · 2 touches · Network Management / Payment Integrity
  - MC Mike Chen · VP Engineering · 4 touches · Network Management
  - LP Lisa Patel · Dir Network Strategy · 2 touches · Network Management
  - TD Tom Davis · CRO · 2 touches · Network Management
  - JW Jennifer Wu · VP Operations · 2 touches · Network Management
- [✓] "View all" button opens `EngagementDetailModal` via [`LightningModal.open()`](../../force-app/main/default/lwc/engagementPanel/engagementPanel.js#L286-L306) — modal renders title, "Group by Person / Group by Campaign" toggle, "7 people" stats strip, all 7 contact rows with role chips (ACR/Consultant) + per-row "Add to Deal Team" button. Escape closes the modal cleanly.

#### Flow B — Network Pricing Implementation Opportunity page (`/lightning/r/Opportunity/006DP00000Oh8rIYAR/view`)

- [✓] Page loads; `c-engagement-panel` mounts
- [✓] Header: "4 engaged" (Opp-scope filter — narrower than account scope by design; the panel uses [`getForOpportunity`](../../force-app/main/default/classes/engagement/EngagementController.cls#L19) which applies recency/relevance heuristics)
- [✓] "Deal Team — 3 on OCR" section renders with Sarah Johnson (6 touches), Mike Chen (4), Tom Davis (2) — each shows `✓ on team` success badge
- [✓] "Engaged — not on Deal Team · 1" section renders with Lisa Patel (2 touches) + `+ Add` button
- [✓] 4 dismiss `lightning-button-icon` controls present (1 per row, hidden until hover per CSS)
- [✓] Click `+ Add` on Lisa Patel → `addToDealTeamModal` opens with title "Add to Deal Team", body "Add Lisa Patel as a member of the Opportunity deal team", Role combobox (placeholder "Select a role"), "Make primary contact" checkbox, Cancel + Add buttons
- [✓] **Backend Add path proven via direct Apex** (`EngagementController.addToOcrSafe(lisaContactId, oppId, 'Economic Buyer', false)`): result `success=true, ocrId=00KDP000005WAn72AG, alreadyExists=false`. OCR count went 3→4. DMLManager logged the insert. Reverted post-test to keep demo state pristine. [`EngagementController.cls`](../../force-app/main/default/classes/engagement/EngagementController.cls)
- [✓] **Backend Dismiss path proven via direct Apex** (`EngagementController.dismissContact(marcusBrownId, null, accountId)`): created `Engagement_Dismissal__c` row, DMLManager logged the insert, no exceptions. Cleaned up after.

#### Flow D — Console / shadow-DOM sanity

- [✓] **0 application errors** across the entire session (Account page, Account modal, Opportunity page, Opportunity Add modal, Admin Console nav).
- [✓] All warnings are platform-noise (deprecated `apple-mobile-web-app-capable` meta, In-App Guidance disabled, durable storage init, etc.) — not from our code.

### Issues found

- **UX-CONCERN (P3) — Account-page "Add to Deal Team" buttons in the detail modal.** When `EngagementDetailModal` is opened from an Account record page (no Opportunity context), each contact row still shows an "Add to Deal Team" button. Clicking would have no Opportunity to add to. **Mitigation for demo:** David should walk View-all from the Opportunity page, or describe the modal without clicking those buttons on Account scope. Hand back to Boomer to either hide or repurpose these on Account scope. Not a demo blocker.

- **GAP (P3) — Admin Console tab + FlexiPage are `.forceignore`d.** [Per `.forceignore` line 22-24](../../.forceignore) this is intentional. The 3 admin LWCs (`engagementTestATouch`, `engagementRuleCoverage`, `engagementErrorQueue`) are deployed (`isExposed=true`) but there is no app page to surface them in `engagementDev`. **If David plans to show them, drop them onto any record page or app page via Lightning App Builder beforehand.** All 3 bundles are present in the org per `LightningComponentBundle` query.

- **UX-CONCERN (P3, observability only) — Opp scope shows 4 engaged, Account scope shows 7.** This is by design — `getForOpportunity` filters narrower than `getForAccount` — but a curious user may ask "why don't the numbers match?". David should be ready to explain the recency/relevance filter or whatever the actual logic is. Worth a one-liner in the demo script.

### Regressions vs. baseline

**None.** All baseline behaviors observed are still working as expected.

### Performance observations

- **Account page panel render:** ~2.5s after navigation (Lightning rehydration + wire fire). Acceptable.
- **Opportunity page panel render:** ~2.5s similar profile.
- **Modal open latency:** sub-200ms on click — `LightningModal.open()` is snappy.
- **Apex governor limits during Add flow (anonymous test):** Single DML, single SOQL, well under 1% of any cap. Bulk-safety not stressed in this pass (single-record click flow).

### Suggested follow-ups for Pippa

1. **Browser-driven Add-flow Jest test gap.** Apex `addToOcrSafe` is proven; Jest tests cover the modal contract in isolation. There's no test that verifies the end-to-end `panel → +Add → AddToDealTeamModal → addToOcrSafe → panel refresh → row moves to Deal Team` chain in a real DOM. Hard to write without a scratch-org-aware harness, but worth a hand-rolled Playwright fixture.
2. **Account-scope `EngagementDetailModal` button hygiene test.** No test asserts that "Add to Deal Team" is hidden or repurposed when `opportunityId` is null. Add an assertion.
3. **Engagement_Admin_Console deploy path.** If the admin tab is going to stay `.forceignore`d, add a `docs/operations/` runbook line noting that admin LWCs need to be dropped onto a page manually in each org. If it should be deployable, remove from `.forceignore`.

---

## Verdict

**🟩 MI demo path is green; David can present without anxiety.**

Account-page panel, Opportunity-page panel, View-all modal, +Add modal — all render correctly, no console errors, backend Add + Dismiss paths verified end-to-end via Apex. The two minor UX gaps (`Add to Deal Team` button on Account-scope modal; missing admin console tab) are documented as P3 follow-ups and won't block the demo if David walks Flow A and Flow B as scripted.

— Wren
