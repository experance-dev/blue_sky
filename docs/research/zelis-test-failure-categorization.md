# Zelis RunLocalTests Failure Categorization

**As of 2026-05-15** — post-MI engagement, post-Pippa-DMLManagerTest-fix, post-orphan-delete

**Org:** `dwood_z` (Zelis Developer sandbox)
**Last validate baseline:** Test run `707WL0000CnTBpe` — 859 total tests, 90% pass, ~62 real failures (4 CSV-parsing artifacts excluded from the failure list)

Atlas's analysis applying David's Pareto rule ("60% of failures resolve via 5-10 root-cause fixes"). Pre-staged for the Jira workspace David is standing up — each category below maps to one user story that groups its failing tests.

---

## Headline

| Bucket                                              | # Tests | % of total | Effort                                  | Story type          |
| --------------------------------------------------- | ------- | ---------- | --------------------------------------- | ------------------- |
| 1. Portal\_\* parallelism (UNABLE_TO_LOCK_ROW)      | ~30     | **48%**    | One pattern fix applied to ~5 classes   | Test-pattern story  |
| 2. Schema drift — missing custom fields             | ~14     | **22%**    | One schema audit + minimal code updates | Schema-fix story    |
| 3. NO_SINGLE_MAIL_PERMISSION in legacy batch tests  | 3       | 5%         | One mock-not-grant pattern              | Test-pattern story  |
| 4. Aura Handled Exception (Portal Config Items)     | 3       | 5%         | Investigate + likely schema-related fix | Investigation story |
| 5. Assertion drift / class-cast errors              | 6       | 10%        | 6 focused fixes                         | Long-tail story     |
| 6. FIELD_CUSTOM_VALIDATION_EXCEPTION (Portal + Opp) | 3       | 5%         | 3 targeted fixes                        | Long-tail story     |
| 7. Web service callouts in test method              | 1       | 2%         | One mock refactor                       | Long-tail story     |
| 8. Internal Salesforce error (CaseTriggerHandler)   | 1       | 2%         | Investigate — possibly platform flake   | Investigation story |
| 9. SObjectDeepCloneTests null assertion             | 1       | 2%         | One focused fix                         | Long-tail story     |
| **TOTAL**                                           | **~62** | **100%**   |                                         |                     |

**Pareto check:** Buckets 1 + 2 = ~44 tests = **71% of failures via 2 root-cause patterns.** Validates David's rule.

Top 4 buckets (1+2+3+5) = 53 tests = **86% via ~12 distinct fixes.**

---

## Story 1 — Portal\_\* RunLocalTests parallelism (`UNABLE_TO_LOCK_ROW`)

**~30 failures across 5 test classes.** Highest-value story by far.

### Test classes affected

- `Portal_NavigationMenuItemsControllerTest` — 15 methods
- `Portal_CustomSecurityTesting` — 10 methods
- `Portal_ConfigurationItemControllerTest` — 6 of 9 (the other 3 are in Story 4)
- `Portal_CustomReportControllerTest` — 5 methods
- `Portal_RecentActivityControllerTest`, `Portal_BatchRefreshSharingTest`, `Portal_SharingTest` — partial (counts in the long tail)

### Symptom

```
System.DmlException: Insert failed. First exception on row 0;
first error: UNABLE_TO_LOCK_ROW, unable to obtain exclusive access to this record: []
```

### Root cause

RunLocalTests runs tests in parallel by default. The Portal\_\* family shares Account / Contact / User / Case seed rows via `@TestSetup` or via inline DML against the same record IDs. When two tests fire simultaneously, the second's DML hits a row that the first has locked.

### Root-cause fix patterns (one or more, depending on class shape)

1. **`@isTest(IsParallel=false)`** at the class level. Opts the class out of parallel execution. Simplest fix; catches all classes that don't have an architectural reason to be parallel.
2. **Per-method seed isolation.** Move `@TestSetup` work into individual test methods so each method has unique-Name seeds. Slower than `@TestSetup` but eliminates cross-test row sharing.
3. **Randomize unique-key fields.** If the seed uses hardcoded `Name = 'Portal Test Account'`, change to `'Portal Test Account ' + DateTime.now().getTime()`. Avoids parallel-test name collisions.

### Acceptance criteria

- All 5 test classes pass under `sf project deploy validate --test-level RunLocalTests`
- Same classes still pass under `sf apex run test --class-names X` (single-class runs unchanged)
- Coverage on `Portal_*` controller production classes maintained (no test methods deleted to silence failures)

### Estimate

1-2 days for Pippa+Wren. Worst case 3 days if classes turn out to need #2 (per-method-seed) which is more code.

---

## Story 2 — Schema drift: missing custom fields

**~14 failures across 7 test classes.** Highest-leverage technical-debt story.

### Test classes affected (grouped by field gone-missing)

**`Task.Expiration_Date__c` missing:**

- `ProviderEnrollmentTasksTest.testNoSale` (1)
- `ScheduleExpiredTieredPricingTasksTest.ScheduleExpiredTieredPricingTasks` (1)

**`Quote.Quote_Version__c` missing:**

- `RCA_CloneQuotesActionTest.testcloneQuote` (1)

**`API_Log__c.Exception__c` missing:**

- `ScheduleResyncInteractionsServiceTest.testExecute` (1)

**`Account.Account_Vertical__c` restricted picklist drift:**

- `ers_DatatableControllerTest` × 6 methods (`setup`, `test`, `testGetIconName`, `testGetNameUniqueField`, `testMultiCurrency`, `testUnknownFieldException`)
- `ers_QueryNRecordsTest.test` (1)

### Symptom (representative)

```
System.QueryException: No such column 'Expiration_Date__c' on entity 'Task'.
  If you are attempting to use a custom field, be sure to append the '__c'
  after the custom field name.
```

```
System.DmlException: Insert failed. First exception on row 0;
first error: INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST,
bad value for restricted picklist field: None: [Account_Vertical__c]
```

### Root cause

Fields referenced by production classes + tests existed at one point in dwood_z but were either removed, renamed, or had their FLS/picklist-values changed. The production code AND its tests both reference the missing field — this is end-to-end drift, not just test bit-rot.

### Root-cause fix paths

Three options per field, decided per-field by the original-author team:

1. **Restore the field** — if it was accidentally removed and is still semantically needed
2. **Update the consumer code + tests** to reference the field name/structure that DOES exist (rename or new picklist values)
3. **Delete the consumer code + tests** if the feature is gone

This is a schema audit + targeted code-update wave. Not a single-pattern fix; ~4 distinct schema decisions.

### Acceptance criteria

- For each missing field: a written decision (restored / replaced / feature deleted)
- All tests in the affected classes pass
- No silent test-deletion to mask the schema decision

### Estimate

2-3 days IF the schema decisions are quick. Could be 5+ if any of the fields are entangled with other systems (e.g., reports, dashboards, integrations).

### Stakeholder coordination needed

Whoever owned the original feature for each gone-missing field needs to weigh in on which option (1/2/3). The git-blame on the production-class line that references the field is the starting point.

---

## Story 3 — `NO_SINGLE_MAIL_PERMISSION` in legacy batch tests

**3 failures.** Highest-discipline-value story (codifies the no-real-emails pattern).

### Test classes affected

- `AcctTeamHistoryDeletionBatchTest.execute_Failure`
- `AssociateNewProviderBatchTest.executeBatch_multipleParentsFound_expectEmailSent`
- `AssociateNewProviderBatchTest.executeBatch_parentChildAssociationExists_expectAssociation`

### Symptom

```
System.EmailException: SendEmail failed. First exception on row 0;
first error: NO_SINGLE_MAIL_PERMISSION,
Single email is not enabled for your organization or profile.
```

### Root cause

The production batch class calls `Messaging.sendEmail(...)`. The test runs it under a user that lacks Send-Email permission OR under an org that has Single Email Limits exceeded. Either way: real-email-from-test is the anti-pattern.

### Root-cause fix pattern

Apply [[feedback-no-real-emails-from-tests]] Pattern 3 (IEmailDispatcher seam):

1. Production batch class declares `@TestVisible private static IEmailDispatcher dispatcher = new RealEmailDispatcher();`
2. Tests inject a stub dispatcher that captures the `Messaging.SingleEmailMessage`
3. Test assertions inspect the captured message's shape, not the dispatch outcome
4. NEVER grant the Send-Email permission

### Acceptance criteria

- All 3 tests pass without ANY user being granted Send-Email permission
- Production batch behavior unchanged
- Pattern is documented in `best-practices/apex-tests.md` (or the standards Confluence page from [[project-test-standards-confluence-writeup]])

### Estimate

0.5-1 day for Pippa+Wren+Boomer (Boomer adds the IEmailDispatcher seam in prod; Pippa/Wren refactor the tests).

---

## Story 4 — Aura Handled Exception in Portal_ConfigurationItemControllerTest

**3 failures.**

### Test methods affected

- `testGetAllRecords` (52ms — fast fail, likely setup-side)
- `testGetByRecordType` (24ms)
- `testGetRecentRecords` (44ms)

### Symptom

```
System.AuraHandledException: Script-thrown exception
```

### Root cause hypothesis

Either:

- (a) The Portal_ConfigurationItem record type referenced doesn't exist in dwood_z (schema drift adjacent)
- (b) The controller throws on a SOQL filter that returns no rows because seed data isn't where the test expects it
- (c) Real production bug in the controller catch-and-rethrow path

Need investigation before fix path is clear.

### Estimate

1 day investigation + 0.5-1 day fix. Could fold into Story 2 if it turns out to be schema drift.

---

## Story 5 — Assertion drift / class-cast errors

**6 failures.** Long-tail story; each test caught a real regression in the production code's contract.

### Test methods affected

- `TaskServiceTest.testStaleTasks`, `testTasksAssignments` — "Expected an instance of ProviderEnrollmentTaskAssignmentsException"
- `ProviderEnrollmentTasksTest.testTasksAssignments` — same pattern
- `StringBuilderTest.testMultiCurrencyFieldListBuilder` — "Field list should be 'Name,Industry,CurrencyIsoCode', actual 'Name,Industry'"
- `StringBuilderTest.testReportBuilder` — CSV format drift
- `CampaignTriggerImplTest.campaignTriggerImpl` — "Industry Event: Expected: 6, Actual: 2"

### Root cause

Each is a focused regression — the production code's behavior changed (assertion drift) OR the test's exception-type cast no longer matches what production throws (class-cast). Production code has drifted from what the test was asserting.

NOT pattern-fixable. Each needs the original-author team's eyes.

### Estimate

3-5 days across all 6 if treated as a single sub-team story; faster if parallel-dispatched across original-author teams.

---

## Story 6 — `FIELD_CUSTOM_VALIDATION_EXCEPTION`

**3 failures.**

### Test methods affected

- `Portal_CustomSecurityTesting.sharingWithAccHierarchy_negativeTest1` — Portal Account VR ("Certain fields on Portal Accounts cannot be modified")
- `ListActionsTest.canGetLookupCollection` — Opportunity `Opportunity_Name_Descriptor__c` required
- `ListActionsTest.cloneRecordTests` — null assertion (related)

### Root cause

Validation rules on Portal Account + Opportunity that the tests don't satisfy. Tests need to seed data that satisfies the VR OR use `runAs(adminWhoCanBypass)` OR disable the VR via the `Process_Automation_Switch__c` pattern.

### Estimate

1 day for 3 targeted fixes.

---

## Story 7 — Web service callout in test method

**1 failure.**

### Test method affected

- `OpportunityServiceTest.testProcessEnrollmentRequestsCompletesWithNoMatchingRecords`

### Symptom

```
Methods defined as TestMethod do not support Web service callouts
```

### Root cause

Production class `OpportunityService` (Zelis legacy, NOT our CSI-7162 `OpportunityService`) makes a real HTTP callout during the test path. Tests can't make real callouts.

### Root-cause fix

Add `HttpCalloutMock` via `Test.setMock(HttpCalloutMock.class, ...)` to inject a stub response.

### Estimate

0.5 day.

---

## Story 8 — Internal Salesforce error (CaseTriggerHandler)

**1 failure.**

### Test method affected

- `CaseTriggerHandlerTest.beforeInsertAfterInsert_expectSuccess`

### Symptom

```
Internal Salesforce Error: 2050913613-225265 (1058606066) (1058606066)
```

### Root cause hypothesis

Salesforce platform error. Could be transient (re-run the test). Could be a real platform issue with a particular SOQL or trigger pattern that needs Salesforce Support ticket.

### Estimate

Investigation only. If transient, no fix. If persistent, 1-2 days Support escalation + workaround.

---

## Story 9 — SObjectDeepCloneTests null assertion

**1 failure.**

### Test method affected

- `SObjectDeepCloneTests.accountWithContacts` — "Same value: null"

### Root cause

Production `SObjectDeepClone` returns null for one branch of the Account-with-Contacts clone path. Either the production code regressed OR the test's expected-value setup is broken.

### Estimate

0.5 day investigation + targeted fix.

---

## Effort summary

| Story                                | Effort              | Owner                                                  |
| ------------------------------------ | ------------------- | ------------------------------------------------------ |
| 1. Portal\_\* parallelism            | 1-3 days            | Pippa+Wren                                             |
| 2. Schema drift                      | 2-5 days            | Schema-decision stakeholders + Boomer/Tex + Pippa/Wren |
| 3. NO_SINGLE_MAIL_PERMISSION         | 0.5-1 day           | Boomer + Pippa+Wren                                    |
| 4. Aura Handled Exception            | 1.5 days            | Investigation + Boomer or Pippa                        |
| 5. Assertion drift                   | 3-5 days            | Various original-author teams                          |
| 6. FIELD_CUSTOM_VALIDATION_EXCEPTION | 1 day               | Pippa+Wren                                             |
| 7. Web service callout               | 0.5 day             | Pippa+Wren                                             |
| 8. Internal Salesforce error         | TBD (investigation) | Atlas + possible SF Support                            |
| 9. SObjectDeepCloneTests null        | 0.5 day             | Investigation + Pippa/Wren                             |
| **Total elapsed**                    | **10-19 days**      | parallel-dispatched across 3 fronts                    |

If only the top-3 stories ship: ~47 of 62 = **76% closed** in **3.5-9 days**.

---

## Coverage gate (Gate 2)

Once Gate 1 (all tests passing) clears via these stories, measure org-wide coverage via:

```bash
sf apex run test --target-org dwood_z --test-level RunLocalTests --code-coverage --wait 60 --result-format json
```

If org-wide < 95%, identify uncovered classes. The biggest uncovered surface is likely:

- Portal*\* controllers (covered by Story 1 if Portal*\* tests are restored)
- Any prod class with a test class that was deleted in past silence-the-failure cleanups

Pippa's team writes the missing tests in a parallel story track.

---

## Jira workspace mapping

When David's Jira workspace is ready:

- **Epic:** "Zelis Modernization — RunLocalTests Gate 1 Clearance"
  - **Story 1:** Portal\_\* RunLocalTests parallelism remediation
  - **Story 2:** Schema-drift audit + targeted remediation
  - **Story 3:** No-real-emails-from-tests pattern application
  - **Story 4:** Portal_ConfigurationItemController investigation
  - **Story 5:** Assertion-drift long-tail (6 sub-tasks)
  - **Story 6:** FIELD_VALIDATION targeted fixes
  - **Story 7:** Web service callout mock
  - **Story 8:** CaseTriggerHandler platform error investigation
  - **Story 9:** SObjectDeepCloneTests null investigation
- **Epic:** "Zelis Modernization — RunLocalTests Gate 2 (95% Coverage)"
  - Stories TBD after Gate 1 clears + coverage gap is measurable

Each story lists its affected test methods (extracted from `/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/docs/research/zelis-test-failure-categorization.md`) as sub-tasks or in the description.

---

## Atlas's recommended sequencing

1. **Story 1 first** — biggest impact (48% of failures), single pattern fix, low-stakeholder-coordination overhead
2. **Story 3 + 7 next** — fast wins, codify good patterns (no-real-emails, mock-callouts)
3. **Story 2 in parallel** — needs stakeholder decisions per field; runs in calendar parallel to 1+3
4. **Story 5 + 6 + 9** — long-tail, can interleave with Story 2 stakeholder waits
5. **Story 4 + 8** — investigation-driven, lowest priority unless platform-level signal emerges

After Story 1 + 2 + 3 land, re-baseline RunLocalTests. The remaining failures may have shifted (some stories' failures could prove to be downstream of others).
