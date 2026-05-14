# `EngagementController`

[`force-app/main/default/classes/engagement/EngagementController.cls`](../../../force-app/main/default/classes/engagement/EngagementController.cls)

## Orientation

The Aura/LWC-facing controller for the engagement panel and its modals. Every method is a thin try/catch wrapper around a single [`IEngagementService`](../../../force-app/main/default/classes/engagement/IEngagementService.cls) call: log the exception via [`Logger`](../../../force-app/main/default/classes/logging/Logger.cls), rethrow as `AuraHandledException` with a sanitized user-facing message. No business logic; no SOQL/DML at this layer. Service injection via the `@TestVisible` setter lets tests substitute a stub `IEngagementService` without spinning up the full Service implementation.

Consumed by the four LWCs in [`force-app/main/default/lwc/`](../../../force-app/main/default/lwc/) — [`engagementPanel`](../../../force-app/main/default/lwc/engagementPanel/), [`addToDealTeamModal`](../../../force-app/main/default/lwc/addToDealTeamModal/), [`alreadyAddedModal`](../../../force-app/main/default/lwc/alreadyAddedModal/), [`engagementDetailModal`](../../../force-app/main/default/lwc/engagementDetailModal/).

## Public API

| Method                                                                                          | Params                                                             | Returns                                                                                   | Throws (over the wire)                                                          |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `getForOpportunity(Id opportunityId)` — `@AuraEnabled(cacheable=true)`                          | `opportunityId`                                                    | `List<EngagementDTO>`                                                                     | `AuraHandledException` — "Unable to load engagement data for this opportunity." |
| `getForAccount(Id accountId)` — `@AuraEnabled(cacheable=true)`                                  | `accountId`                                                        | `List<EngagementDTO>`                                                                     | `AuraHandledException` — "Unable to load engagement data for this account."     |
| `addToOcrSafe(Id contactId, Id opportunityId, String role, Boolean isPrimary)` — `@AuraEnabled` | `contactId`, `opportunityId`, `role`, `isPrimary`                  | [`AddToOcrResult`](../../../force-app/main/default/classes/engagement/AddToOcrResult.cls) | `AuraHandledException` — "Unable to add the contact to the deal team."          |
| `dismissSignal(Id signalId, String reason)` — `@AuraEnabled`                                    | `signalId`, `reason`                                               | `void`                                                                                    | `AuraHandledException` — "Unable to dismiss the signal."                        |
| `dismissContact(Id contactId, Id opportunityId, Id accountId)` — `@AuraEnabled`                 | `contactId`, exactly one of `opportunityId` / `accountId` non-null | `void`                                                                                    | `AuraHandledException` — "Unable to dismiss this contact. Try again."           |

### Return shapes

- `EngagementDTO` is defined in [`EngagementDTO.cls`](../../../force-app/main/default/classes/engagement/EngagementDTO.cls). DTO field order matches the LWC template binding — see [development/apex-conventions.md §DTO field order](../apex-conventions.md#other-quick-hits).
- `AddToOcrResult` captures either the success path (`success=true`, `ocrId`, `role`, `isPrimary`) or the race-detection path (`alreadyExists=true`, `ocrId`, `addedByUserId`, `addedByUserName`, `addedAt`, `role`, `isPrimary`).

### Caching semantics

`getForOpportunity` and `getForAccount` are `cacheable=true` — Lightning caches results per-args until cache invalidation. The LWC must call `refreshApex(...)` after `addToOcrSafe` / `dismissContact` to bust the cache; do not rely on natural expiry.

## Side effects

- **No DML in the controller.** Every write is delegated to the Service.
- **Every catch logs.** `Logger.error(e.getMessage(), 'EngagementController', '<methodName>')` runs on the standard project [`Logger`](../../../force-app/main/default/classes/logging/Logger.cls) sink. PII (email, phone) must not appear in `e.getMessage()` — if you find it does, sanitize at the Service layer before throwing.
- **Sanitized error contract.** The thrown `AuraHandledException` message is fixed per-method and contains no internal context. The detailed message goes to the log only.

## Dependencies

| Direction      | What                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Depends on     | [`IEngagementService`](../../../force-app/main/default/classes/engagement/IEngagementService.cls) (default impl: [`EngagementServiceImpl`](../../../force-app/main/default/classes/engagement/EngagementServiceImpl.cls)), [`EngagementDTO`](../../../force-app/main/default/classes/engagement/EngagementDTO.cls), [`AddToOcrResult`](../../../force-app/main/default/classes/engagement/AddToOcrResult.cls), [`Logger`](../../../force-app/main/default/classes/logging/Logger.cls) |
| Depended on by | The four engagement LWCs ([`engagementPanel`](../../../force-app/main/default/lwc/engagementPanel/), [`addToDealTeamModal`](../../../force-app/main/default/lwc/addToDealTeamModal/), [`alreadyAddedModal`](../../../force-app/main/default/lwc/alreadyAddedModal/), [`engagementDetailModal`](../../../force-app/main/default/lwc/engagementDetailModal/))                                                                                                                           |

## Permission model

Callers need the [`Engagement_Attribution_User`](../../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml) permission set, which grants:

- Apex class access to `EngagementController`.
- Read on `Engagement_Touch__c`, `Touch_Topic__c`, `Opportunity_Engagement_Signal__c`, `Engagement_Dismissal__c`.
- Read + Create on `OpportunityContactRole` (required for `addToOcrSafe`).

`with sharing` on the class + `WITH USER_MODE` on the underlying SOQL in the Service means the running user's record visibility governs which engagement data they see. A user without read on a given Account sees the touches on their own Opportunities only.

## Test-only injection

```apex
@TestVisible
private static void setServiceForTest(IEngagementService mockService);
```

Tests stub `IEngagementService` and call this setter to swap the default `EngagementServiceImpl` for a mock. See [`EngagementControllerTest`](../../../force-app/main/default/classes/engagement/EngagementControllerTest.cls) for the canonical pattern.

## Related

- Service: [`EngagementServiceImpl`](EngagementServiceImpl.md).
- Tests: [`EngagementControllerTest`](../../../force-app/main/default/classes/engagement/EngagementControllerTest.cls).
- LWC consumers: [`engagementPanel`](../../../force-app/main/default/lwc/engagementPanel/), [`addToDealTeamModal`](../../../force-app/main/default/lwc/addToDealTeamModal/), [`alreadyAddedModal`](../../../force-app/main/default/lwc/alreadyAddedModal/), [`engagementDetailModal`](../../../force-app/main/default/lwc/engagementDetailModal/) (LWC docs maintained by Lyric).
- Permset: [`Engagement_Attribution_User`](../../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml).
- ADR: [0001 — three-layer pattern](../../architecture/decisions/0001-three-layer-selector-service-controller.md).
