# CSI-7162 — Hand-copy manifest

All paths relative to `force-app/main/default/`. Each `.cls` and `.trigger` needs its `*-meta.xml` sibling alongside.

## A. CSI-7162 framework — production Apex

| File                                    | Purpose                                                   |
| --------------------------------------- | --------------------------------------------------------- |
| `classes/JiraPushService.cls`           | Publish-side service; builds and emits PEs                |
| `classes/JiraPushDispatcher.cls`        | Consume-side; groups events, calls JCFS                   |
| `classes/JiraPushRequestHandler.cls`    | PE trigger handler                                        |
| `classes/JcfsApiAdapter.cls`            | **Real JCFS call** — only file that references `JCFS.API` |
| `classes/OpportunityService.cls`        | Domain decisions (qualifying fields)                      |
| `classes/OpportunityTriggerHandler.cls` | Opportunity trigger handler                               |

## B. CSI-7162 framework — triggers

| File                                      | Purpose                            |
| ----------------------------------------- | ---------------------------------- |
| `triggers/JiraPushRequestTrigger.trigger` | After-insert on the platform event |
| `triggers/OpportunityTrigger.trigger`     | After-insert/update on Opportunity |

## C. CSI-7162 framework — tests

| File                                        |
| ------------------------------------------- |
| `classes/JiraPushServiceTest.cls`           |
| `classes/JiraPushDispatcherTest.cls`        |
| `classes/JiraPushRequestHandlerTest.cls`    |
| `classes/OpportunityServiceTest.cls`        |
| `classes/OpportunityTriggerHandlerTest.cls` |
| `classes/LoggerApiExceptionTest.cls`        |

## D. CSI-7162 metadata

| Path                                                                                      | Type                                          |
| ----------------------------------------------------------------------------------------- | --------------------------------------------- |
| `objects/Jira_Push_Request__e/` — object + 5 fields                                       | Platform Event                                |
| `objects/Jira_Push_Object__mdt/` — object + 2 fields (`SObject_API_Name__c`, `Active__c`) | Custom Metadata Type                          |
| `customMetadata/Jira_Push_Object.Opportunity.md-meta.xml`                                 | CMDT record                                   |
| `customMetadata/Jira_Push_Object.Case.md-meta.xml`                                        | CMDT record (drop if not onboarding Case yet) |
| `objects/API_Exception_Log__c/` — object + 10 fields                                      | Custom Object                                 |

## E. Utility dependencies (work org has none of these — bring them all)

| File                                                               | Notes                                                                                                                                                             |
| ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `classes/logging/Logger.cls`                                       | Includes the new `logApiException` methods.                                                                                                                       |
| `classes/logging/LoggerTest.cls`                                   | Existing Logger tests.                                                                                                                                            |
| `classes/triggers/TriggerHandler.cls`                              | Base class extended by `JiraPushRequestHandler` and `OpportunityTriggerHandler`.                                                                                  |
| `classes/triggers/TriggerHandlerTest.cls`                          |                                                                                                                                                                   |
| `classes/testing/TestFactory.cls`                                  | Tests use `createSObject` + `getFakeId`.                                                                                                                          |
| `classes/testing/TestFactoryDefaults.cls`                          | **Stub in this repo.** At work, populate with Zelis-specific `OpportunityDefaults`, `AccountDefaults`, etc. — see `FieldDefaults` interface in `TestFactory.cls`. |
| `objects/Log_Setting__mdt/` — object + `Print_Debug_Logs__c` field | Logger reads this.                                                                                                                                                |
| `customMetadata/Log_Setting.defaults.md-meta.xml`                  | Single record.                                                                                                                                                    |

## F. DO NOT copy

- `classes/testing/TestFactoryRig.cls` — empty stub here, not useful at work
- `CSI-7162.xml` — the Jira ticket dump in repo root
- Anything in `classes/pricing/`, `classes/dml/`, `classes/email/`, `classes/general/`, `classes/picklists/`, `classes/rest/`, `classes/strings/`, `classes/logging/LogCleanUp/` — Stowers-specific or unrelated to CSI-7162
- `.forceignore`, `config/project-scratch-def.json`, `sfdx-project.json` — dev-environment files

## File counts

| Category                                   |   Files |
| ------------------------------------------ | ------: |
| Apex production (`.cls` + `.cls-meta.xml`) |      12 |
| Apex triggers (`.trigger` + `-meta.xml`)   |       4 |
| Apex tests (`.cls` + `.cls-meta.xml`)      |      12 |
| CSI-7162 metadata XML                      |      22 |
| Utility deps                               |      15 |
| **Total**                                  | **~65** |

## Order of operations at work

1. Deploy **metadata first** (platform event, CMDTs, custom object, CMDT records) — Apex won't compile without these.
2. Deploy **utility Apex** (`Logger`, `TriggerHandler`, `TestFactory`, `TestFactoryDefaults`).
3. Deploy **CSI-7162 production Apex** (services, dispatcher, handlers, adapter).
4. Deploy **triggers**.
5. Deploy **tests**.
6. Populate `TestFactoryDefaults` with Zelis-specific inner `*Defaults` classes — needed for tests to pass under your org's validation rules.
7. Confirm `JIRA_PROJECT_ID` / `JIRA_ISSUE_TYPE` constants in `JiraPushService.cls` with the Jira team (currently placeholder `CSI` / `Story`). Unused by `pushUpdatesToJira` today; wired for the future `pushTopicToJira` (auto-create-Jira-issue) work.

## Known follow-ups in the work org

1. `JiraPushDispatcherTest.testProcessUsesNoOpFallbackWhenAdapterNotDeployed` will fail at work because `JcfsApiAdapter` IS deployed there. Override `JiraPushDispatcher.jcfs = new JiraPushDispatcherTest.RecordingJcfs();` at the top of that test to neutralize, or delete the test (the NoOp fallback only matters in stub-environments).
2. Sandbox smoke test with a real linked Jira issue + managed JCFS package before prod.
