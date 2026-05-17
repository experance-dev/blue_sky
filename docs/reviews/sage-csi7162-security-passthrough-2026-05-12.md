# CSI-7162 — Sage Final Security Pass

**Reviewer:** Sage Cloudy (Security Architect)
**Date:** 2026-05-12
**Branch:** `worktree-jira-push-work`
**Worktree:** `/Users/david/Work/Zelis/.claude/worktrees/jira-push-work/`
**Predecessors:** [Atlas code review](atlas-csi7162-code-review-2026-05-12.md) · [Pippa test review](pippa-csi7162-test-review-2026-05-12.md)
**Scope:** Security impact of Boomer's deltas (B1 + 4H + 4M + 5L + Q2). Not architecture. Not coverage.

## Verdict

🟢 **Cleared for transport to Zelis dev org.**

Boomer's deltas land the right calls on every security-relevant axis. The B1 SYSTEM_MODE design call is correct and well-documented; H1 USER_MODE on the CMDT SOQL is policy-defensible (see §H1 below — I'm signing off with one caveat for next pass); H3's per-record result envelope materially strengthens the audit trail; H4's recursion-guard widening to include ChangeType closes a correctness gap that was _also_ a soft audit-completeness gap (a missed Update event is a missed audit event).

No 🟥. No 🟧. One 🟨 (H1 caveat) and one 🟦 follow-up (permset documentation). Ship it.

## Findings reviewed (Boomer's deltas)

### B1 — `Logger.writeApiException` uses `Database.insert(..., AccessLevel.SYSTEM_MODE)`

**File:** [`Logger.cls:276-300`](../../force-app/main/default/classes/logging/Logger.cls)
**Verdict:** ✅ **Concur. Atlas-approved, Sage-approved. Documentation is exemplary.**

**Rationale.** An error logger must run above the caller's perm boundary. Three reasons this is the right call, not a hack:

1. **"Nothing gets swallowed" beats "respect caller FLS on the diagnostic table."** If a Standard User without FLS on `Stack_Trace__c` triggers an exception, USER_MODE silently drops the row and support has no record of the failure. SYSTEM_MODE writes it. The diagnostic table is not customer data — it's operational telemetry about the integration, owned by the platform team. Caller FLS doesn't apply.
2. **`DMLManager` doesn't expose a true system-mode overload.** Boomer's ApexDoc names this correctly. `DMLManager.insertAsSystem` runs the underlying DML at `AccessLevel.USER_MODE`; there is no clean delegation path for "I deliberately want to bypass FLS." Direct `Database.insert(..., AccessLevel.SYSTEM_MODE)` is the only honest expression of intent.
3. **This is the documented exception, not the precedent.** The class header at [`Logger.cls:10`](../../force-app/main/default/classes/logging/Logger.cls) calls it out: _"writeApiException uses Database.insert(..., AccessLevel.SYSTEM_MODE) by deliberate policy."_ The method ApexDoc at [`Logger.cls:159-178`](../../force-app/main/default/classes/logging/Logger.cls) spells out the four-part rationale. Future reviewers reading this code will not mistake it for a `DMLManager` miss.

**Compliance note.** No PII concern — `API_Exception_Log__c` stores `Message__c`, `Stack_Trace__c`, `Source_Record_Id__c` (Id-as-string, not data). Stack traces _could_ contain field values if a `DmlException.getDmlFieldNames()` payload leaks into the message — but the `Logger.logApiException` overloads at [`Logger.cls:226-260`](../../force-app/main/default/classes/logging/Logger.cls) store `Exception.getMessage()` / `getStackTraceString()`, which is class/method/line, not field values. Clean.

**Auxiliary observation.** `API_Exception_Log__c` has `sharingModel=Private` ([object meta:23](../../force-app/main/default/objects/API_Exception_Log__c/API_Exception_Log__c.object-meta.xml#L23)) and no permset grants read access. Combined with SYSTEM_MODE writes, this gives the right shape: **anyone can trip an error → row is written → only admins (View All Data) can read it.** That's the right default for a diagnostic table that may end up holding sensitive operational details.

---

### H1 — `WITH USER_MODE` on CMDT SOQL in `JiraPushService.getConfig`

**File:** [`JiraPushService.cls:201-211`](../../force-app/main/default/classes/JiraPushService.cls)
**Verdict:** 🟨 **MEDIUM caveat — leave as-is for this transport, but file follow-up.**

**The trade-off.** CMDT reads bypass CRUD/FLS by platform rule, so `WITH USER_MODE` here is _semantically_ policy-theater — it can't change what the query returns. Pippa flagged that in a scratch org as a Standard User, `WITH USER_MODE` on CMDT _can_ raise `QueryException` in edge cases (it has historically — though Salesforce closed most of these in API 60+). The semantically-correct annotation for CMDT is `WITH SYSTEM_MODE`.

**Why I'm signing off on USER_MODE anyway.** Three reasons:

1. **It conforms to `best-practices/apex.md`** ("every SOQL has `WITH USER_MODE` … no exceptions in production code"). The rule is right; the CMDT carve-out exists but isn't yet codified. Leaving the policy-theater annotation in place is defensible and the rule-conformance argument is strong.
2. **Pippa's `QueryException` concern is API-version-dependent.** This codebase is API 64.0 (per `sfdx-project.json` defaults); the historical USER_MODE-on-CMDT edge cases were API 58-60. I have not reproduced the failure on 64.0.
3. **`JiraPushService` is `with sharing`**, the calling user has authenticated and reached an Opportunity trigger, and the org has the CMDT records deployed. The realistic failure mode is "test in a scratch org without the CMDT records" → returns empty map → `getConfig()` returns null → kill-switch fails closed. That's the right behavior, not a regression.

**Follow-up to log (not blocking).** When `best-practices/apex.md` next gets a revision pass, add an explicit CMDT carve-out: _"`WITH SYSTEM_MODE` is acceptable on Custom Metadata Type queries since CMDT reads bypass CRUD/FLS by platform rule."_ That converts the policy-theater into a semantic-truth annotation. Until then, USER_MODE here is the correct conforming choice. **Sage's recommendation: file as a docs ticket for Marlowe / best-practices owner; no code change in this PR.**

---

### H2 — New CMDT fields `Jira_Project_Id__c` and `Jira_Issue_Type__c` on `Jira_Push_Object__mdt`

**Files:**

- [`Jira_Project_Id__c.field-meta.xml`](../../force-app/main/default/objects/Jira_Push_Object__mdt/fields/Jira_Project_Id__c.field-meta.xml)
- [`Jira_Issue_Type__c.field-meta.xml`](../../force-app/main/default/objects/Jira_Push_Object__mdt/fields/Jira_Issue_Type__c.field-meta.xml)
- [`Jira_Push_Object.Opportunity.md-meta.xml`](../../force-app/main/default/customMetadata/Jira_Push_Object.Opportunity.md-meta.xml)
- [`Jira_Push_Object.Case.md-meta.xml`](../../force-app/main/default/customMetadata/Jira_Push_Object.Case.md-meta.xml)

**Verdict:** ✅ **Confirm. No sensitivity concern. Values are routing identifiers, not secrets.**

**Rationale.** "CSI" (Jira project key) and "Story" (Jira issue type) are operational configuration, not credentials. CMDT storage is the right home for them — version-controlled, admin-editable without a deploy, per-SObject routing.

**Compliance note.** Jira project keys are typically discoverable from the Jira side anyway (any user with Jira access can see project keys). Storing them in CMDT does not expand the disclosure surface. Issue type names ("Story", "Bug") are even less sensitive.

**Field config check.** Both fields are `Text(40)`, `fieldManageability=DeveloperControlled`, `required=false`. DeveloperControlled is the right choice for routing config — it means admin-edits are tracked through deploy, not free-text in production. Clean.

---

### H3 — `IJcfsApi.pushUpdates` returns `List<JcfsPushResult>` with per-record success/failure

**Files:**

- [`JiraPushDispatcher.cls:28-50`](../../force-app/main/default/classes/JiraPushDispatcher.cls) (`JcfsPushResult` DTO)
- [`JiraPushDispatcher.cls:54-58`](../../force-app/main/default/classes/JiraPushDispatcher.cls) (`IJcfsApi` interface)
- [`JiraPushDispatcher.cls:298-336`](../../force-app/main/default/classes/JiraPushDispatcher.cls) (per-record result handling)
- [`JcfsApiAdapter.cls:60-103`](../../force-app/main/default/classes/JcfsApiAdapter.cls) (adapter result synthesis)

**Verdict:** ✅ **Acknowledge. Material improvement to audit trail.**

**Why this matters from a security/compliance lens.** A `void` JCFS contract is an audit black hole — if Jira accepts 199 records and rejects 1 (e.g., permission denied on a Jira project, or rate-limit on one issue), the old code logged nothing about the rejected record. With `List<JcfsPushResult>`:

- **Success path** lands a `Logger.info` line per record at [`JiraPushDispatcher.cls:312-322`](../../force-app/main/default/classes/JiraPushDispatcher.cls), optionally including the Jira issue key. That's a one-to-one audit trail "Salesforce Opportunity X → Jira issue Y" — exactly what support needs for an external-system reconciliation.
- **Failure path** lands a row in `API_Exception_Log__c` per record via `Logger.logApiException` at [`JiraPushDispatcher.cls:324-332`](../../force-app/main/default/classes/JiraPushDispatcher.cls) with the JCFS rejection message. Support can now replay just the failed records.

**No PII concern.** `JcfsPushResult.recordId` is a Salesforce Id (Id-as-Id), `jiraIssueKey` is an external system identifier ("CSI-1234"), `errorMessage` is JCFS's rejection string. None of these are customer data; all are operational identifiers.

**Defensive observation, not blocking.** The adapter at [`JcfsApiAdapter.cls:95-100`](../../force-app/main/default/classes/JcfsApiAdapter.cls) synthesizes a uniform `success=true` for every record because `JCFS.API.pushUpdatesToJira` is declared void. If JCFS ever exposes a per-record result API in a future managed-package version, this is the point to wire it in. ApexDoc at [`JcfsApiAdapter.cls:36-50`](../../force-app/main/default/classes/JcfsApiAdapter.cls) calls this out explicitly — clean documentation of the current contract limit.

---

### H4 — Recursion guard key now `SObjectName:Id:ChangeType`

**File:** [`JiraPushService.cls:42-46, 117-120`](../../force-app/main/default/classes/JiraPushService.cls)
**Verdict:** ✅ **Acknowledge. No security concern; correctness improvement helps audit completeness as a side-effect.**

**Why this is also (mildly) an audit win.** Under the previous key (`SObjectName:Id`), an insert-then-update in the same transaction suppressed the update event silently. From an audit lens, that's a missed audit row — Jira got a "Created" notification but never the "Updated" follow-up, and support has no record of why. The new key makes Create and Update independent — both events fire, both audit rows exist, and Jira sees the full lifecycle. **No exposure either way; just better audit completeness.**

---

### M1 — Kill-switch CMDT now gated on publish side too

**File:** [`JiraPushService.cls:96-108`](../../force-app/main/default/classes/JiraPushService.cls), new `isActive(sobjectName)` at [`JiraPushService.cls:184-188`](../../force-app/main/default/classes/JiraPushService.cls)
**Verdict:** ✅ **Acknowledge. Audit completeness win.**

**Rationale.** Failing closed at _both_ publish and consume sites is the right shape: an admin who flips `Active__c = false` immediately stops events entering the bus (no phantom backlog), and the consume side still re-checks in case the flag flipped mid-batch. Defense-in-depth on the kill-switch is good operational hygiene; it also means the audit picture is coherent — when admin flips the switch, the absence of new `Jira_Push_Request__e` events is the observable signal that the switch is working, not a delayed "we processed and dropped them" trail.

---

### M3 — `JiraPushDispatcherException` thrown for malformed `Source_Id__c`, extends `UtilitiesModuleException`

**Files:**

- [`JiraPushDispatcher.cls:181-198`](../../force-app/main/default/classes/JiraPushDispatcher.cls) (typed throw + catch)
- [`JiraPushDispatcher.cls:344-351`](../../force-app/main/default/classes/JiraPushDispatcher.cls) (exception declaration extending `UtilitiesModuleException`)

**Verdict:** ✅ **Acknowledge. Typed exception flow improves audit traceability.**

**Rationale.** Throwing a named typed exception (instead of passing a string into `Logger.logApiException`) puts the exception **type name** into `API_Exception_Log__c.Exception_Type__c`, which makes "show me every malformed-Id event in the last 7 days" a clean SOQL filter rather than a `LIKE '%Invalid Source_Id%'` string match. Better for downstream reporting, better for audit queries. Extending `UtilitiesModuleException` also gives the module-wide catch hierarchy the right shape — anyone catching `UtilitiesModuleException` will see this one too.

---

### Q2 — JCFS startup check with `Type.forName('JCFS', 'API')`

**File:** [`JcfsApiAdapter.cls:73-93`](../../force-app/main/default/classes/JcfsApiAdapter.cls)
**Verdict:** ✅ **Confirm spec compliance. Logs at `Logger.error` level on first absent-package detection; subsequent calls silent.**

**Rationale.** The implementation at [`JcfsApiAdapter.cls:77-82`](../../force-app/main/default/classes/JcfsApiAdapter.cls) is exactly the Q2 contract:

1. **First call:** probes `Type.forName('JCFS', 'API')`, caches result in `jcfsAvailable`.
2. **If absent:** emits `Logger.error('JCFS managed package is not installed - Jira push integration is silently no-op\'d. Install the Appfire JCFS package to enable.')` once, sets `absenceLogged = true`, and returns one failure `JcfsPushResult` per input record so the dispatcher still logs per-record audit rows.
3. **Subsequent calls (same transaction):** the `absenceLogged` guard prevents log spam; the per-record failure results still flow through.

This is the documented "one-time warn, then silent no-op" pattern. **Confirmed.**

**Auxiliary observation.** Using `Logger.error` (not `Logger.warn`) for the first detection is the right severity choice — a missing JCFS managed package means the entire integration is silently broken, which is an operational red flag, not a yellow one. Anyone monitoring the debug log for ERROR-level events will see this; anyone watching only WARN-and-below might miss it. Correct severity.

---

### API_Exception_Log\_\_c permset gap (Pippa's flag)

**Verdict:** ✅ **Concur with Atlas's preference for Option B — SYSTEM_MODE on `writeApiException` is sufficient. No permset needed.**

**Pippa's flag.** Integration user / Standard User can't write to `API_Exception_Log__c` because no permset grants FLS on the fields. Confirmed: `grep -r "API_Exception_Log__c" force-app/main/default/permissionsets/` returns zero hits, and the object's `sharingModel=Private` with no permset means default-deny across the board.

**Two options on the table:**

- **Option A:** Add a `Jira_Push_Integration` permset granting CRUD+FLS on `API_Exception_Log__c`, assigned to the integration user.
- **Option B:** Accept SYSTEM_MODE on `writeApiException` as sufficient (no permset needed; the diagnostic write runs above caller perms).

**Sage's call: Option B.** Three reasons:

1. **SYSTEM_MODE is already there** (Boomer's B1 delta). Option A adds a permset that becomes redundant the moment SYSTEM_MODE is in place — anyone who hits the error logger writes the row whether they have the permset or not.
2. **Fewer permsets = fewer attack surfaces.** Every permset is a maintenance liability — Sage reviews them for creep (objectPermissions, fieldPermissions, classAccesses, viewAllRecords). A permset that grants `Create` on `API_Exception_Log__c` to "the integration user" today becomes "what's the integration user, and does it also need this in 6 months when we add Slack notifications?" Sage's preference: **don't add permsets that SYSTEM_MODE makes redundant.**
3. **Operational simplicity.** No permset → no assignment step in release notes → no "we deployed the code but forgot to assign the permset" failure mode. Boomer's design choice eliminates an entire operational risk class.

**Read access is a separate question.** Standard Users still can't _read_ `API_Exception_Log__c` rows. That's correct default-deny — only admins (View All Data, or an explicit "API_Exception_Log_Reader" permset granted to support) should see error logs because stack traces may contain operational details. If/when support tooling needs read access, **that** is when a permset gets added — narrowly scoped, read-only, assigned only to the support persona. Sage will review that permset when it's proposed; it is **out of scope for this PR.**

---

## Open security findings (not in this PR)

These were surfaced during this review pass but do not block CSI-7162. Capture as follow-up tickets when David has cycles.

1. **`best-practices/apex.md` CMDT carve-out.** Add an explicit "CMDT queries can use `WITH SYSTEM_MODE` since CMDT bypasses CRUD/FLS" note so the H1 USER_MODE annotation isn't perpetual policy-theater. **Owner:** Marlowe (docs) or whoever owns `best-practices/apex.md`. **Severity:** 🟦 LOW.

2. **`API_Exception_Log__c` read-access permset.** No permset grants read today; admins (View All Data) are the only readers. When support needs visibility, propose a narrow read-only permset for the support persona only. Sage will review then. **Severity:** 🟦 LOW (deferred until a real reader persona is identified).

3. **`Stack_Trace__c` content audit.** Long-form text field, populated by `Exception.getStackTraceString()`. Apex stack traces include class.method.line, not field values, so PII risk is low — but if a custom exception's `getMessage()` ever embeds record field data (a future code change), it lands here. **Mitigation today:** `Logger.logApiException` overloads accept either an `Exception` or a `String message`, and both paths persist to `Message__c`/`Stack_Trace__c` with no field-content scrubbing. If a future integration logs a Contact email in an error message, it lands in this table. **Recommendation:** when the support-reader permset is proposed (item 2), add a field-level scrub pass on `Logger.logApiException` to mask common PII patterns. **Severity:** 🟦 LOW (deferred; no current code path leaks PII into Logger).

4. **No subject-erasure cascade on `API_Exception_Log__c`.** If a Contact is erased under CCPA "Delete My Data", `API_Exception_Log__c` rows referencing that Contact's Id (via `Source_Record_Id__c`) are orphaned, not cleaned up. The field is Text (not Lookup), so the standard cascade machinery can't find them. **Mitigation today:** `Source_Record_Id__c` stores an Id string, not customer data, so the orphan row is operational telemetry referencing a no-longer-existent record. Not a CCPA violation per se — but the LogCleanupContext CMDT (mentioned in the object description) should grow a rule for `API_Exception_Log__c` if it doesn't have one. **Severity:** 🟦 LOW (deferred; not a CSI-7162 regression — this is the table's design, not Boomer's change).

5. **Test class `LoggerApiExceptionTest` exercises the SYSTEM_MODE path implicitly.** Pippa flagged that the `writeApiException` failure catch (Logger.cls lines 275-281 in her review, now lines 298-303 after Boomer's delta) is uncovered. With SYSTEM_MODE in place, inducing a DML failure requires a different attack vector (e.g., oversized `Message__c` text). When Pippa adds the bulk/failure-path tests she scoped, this branch should get coverage. **Severity:** 🟨 MEDIUM (Pippa's lane, not Sage's).

---

## Sign-off

Cleared. Boomer's deltas are tight on every security-relevant axis — the SYSTEM_MODE design call on `writeApiException` is the right one and is documented exactly as I'd want it documented (class header + method ApexDoc + inline comment at the call site, three layers deep so no future reviewer mistakes it for a `DMLManager` miss); H3's per-record result envelope materially upgrades the audit trail; H4's ChangeType-keyed recursion guard closes a soft audit-completeness gap; Q2's `Logger.error` severity choice on the JCFS-absence path is correct. The permset gap is a non-issue once SYSTEM_MODE is in place — Atlas's Option B preference is the right call.

No `WITH USER_MODE` violations in scope. No `AuraHandledException` leakage (no LWC surface in this PR). No bare DML in production code paths (B1 was the last one, and it's now an explicit, documented policy exception). No PII in debug logs. No subject-erasure cascade gaps that are this PR's responsibility.

Ship it to the Zelis dev org.

— Sage
