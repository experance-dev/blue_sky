# Apex Conventions

The canonical rules for Apex authoring live in [best-practices/apex.md](../../best-practices/apex.md) — read that first. This page is a pointer + a "things devs trip on" checklist specific to the Engagement Attribution feature.

## Source of truth

| Topic                                                                                                     | Where                                                                                                                                                         |
| --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Class headers + ApexDoc tags (`@description`, `@group`, `@author`, `@since`, `@last`)                     | [best-practices/apex.md §Header](../../best-practices/apex.md#header)                                                                                         |
| Naming (CamelCase, no underscores except `__c`)                                                           | [best-practices/apex.md §Naming](../../best-practices/apex.md#naming)                                                                                         |
| Complexity budget (< 8 / method, < 45 / class)                                                            | [best-practices/apex.md §Complexity budget](../../best-practices/apex.md#complexity-budget)                                                                   |
| DML via [`DMLManager`](../../force-app/main/default/classes/dml/DMLManager.cls)                           | [best-practices/apex.md §DML](../../best-practices/apex.md#dml)                                                                                               |
| Method visibility (`private` by default, `@TestVisible` for tests)                                        | [best-practices/apex.md §Method visibility](../../best-practices/apex.md#method-visibility)                                                                   |
| Error handling via [`Logger`](../../force-app/main/default/classes/logging/Logger.cls) + module exception | [best-practices/apex.md §Error handling](../../best-practices/apex.md#error-handling)                                                                         |
| `with sharing` mandatory                                                                                  | [best-practices/apex.md §Sharing modifier is mandatory](../../best-practices/apex.md#sharing-modifier-is-mandatory)                                           |
| `WITH USER_MODE` / `AccessLevel.USER_MODE`                                                                | [best-practices/apex.md §USER_MODE / SYSTEM_MODE](../../best-practices/apex.md#user_mode--system_mode-on-soql-and-dml)                                        |
| Logger discipline (`Logger.logException` / `info` / `warn`)                                               | [best-practices/apex.md §Logging discipline](../../best-practices/apex.md#logging-discipline)                                                                 |
| Layering (Selector / Service / Domain / Surface)                                                          | [best-practices/architecture.md](../../best-practices/architecture.md), [ADR 0001](../architecture/decisions/0001-three-layer-selector-service-controller.md) |
| Test conventions (`Assert` class, `System.runAs`, `@TestSetup`, fake IDs)                                 | [best-practices/apex-tests.md](../../best-practices/apex-tests.md)                                                                                            |

## Things devs trip on

Concrete patterns that have bitten people on this feature. Each one comes from a real PR comment.

### `WITH USER_MODE` on every SOQL

Every SOQL in production code carries `WITH USER_MODE`. Not optional. The platform enforces CRUD/FLS at the query site, not at the controller boundary — which means a missing `USER_MODE` is a Sage 🟥 BLOCK on PR review.

```apex
// Good
List<Contact> matches = [
  SELECT Id, Email, AccountId
  FROM Contact
  WHERE Email IN :emails
  WITH USER_MODE
];

// Bad — Sage will block
List<Contact> matches = [SELECT Id FROM Contact WHERE Email IN :emails];
```

See [`IdentityResolutionService.queryContactsByEmail`](../../force-app/main/default/classes/engagement/IdentityResolutionService.cls) for a representative example.

### `DMLManager` over raw DML

Never write `insert recs;` or `update recs;`. Use [`DMLManager.insertAsUser` / `updateAsUser` / `upsertAsUser` / `deleteAsUser`](../../force-app/main/default/classes/dml/DMLManager.cls). The `xxxAsUser` overloads delegate to `AccessLevel.USER_MODE` internally — same CRUD/FLS guarantee as `WITH USER_MODE` on SOQL.

```apex
// Good
DMLManager.insertAsUser(ocr);

// Bad
insert ocr;
```

**Known exception:** upsert-by-external-id has no `DMLManager` overload yet. [`EngagementInboundRest.upsertTouches`](../../force-app/main/default/classes/engagement/EngagementInboundRest.cls) drops to `Database.upsert(touches, externalIdField, false, AccessLevel.USER_MODE)` and leaves a tracking comment. Add a `DMLManager.upsertAsUser(records, externalIdField)` overload if you find yourself doing this twice.

### `Logger.error(msg, className, methodName)` in every catch

Every `catch` block logs via [`Logger`](../../force-app/main/default/classes/logging/Logger.cls). The three-argument form (message, class name, method name) is the canonical signature for `Logger.error`; `Logger.logException(e, className, methodName)` is the shorter form when you have the whole exception. No `System.debug` in production paths.

```apex
try {
  DMLManager.insertAsUser(ocr);
} catch (DmlException e) {
  Logger.error(e.getMessage(), 'EngagementServiceImpl', 'addToOcrSafe');
  throw new EngagementException(
    'Failed to add Contact to Deal Team: ' + e.getMessage()
  );
}
```

[`EngagementServiceImpl.addToOcrSafe`](../../force-app/main/default/classes/engagement/EngagementServiceImpl.cls) is the canonical pattern.

### Custom exceptions extend `UtilitiesModuleException`

Every module-level exception extends the project base. [`EngagementException`](../../force-app/main/default/classes/engagement/EngagementException.cls) is one line:

```apex
public class EngagementException extends UtilitiesModuleException {
}
```

Do not throw `System.Exception`, raw `DmlException`, or `IllegalArgumentException` from a Service. Wrap them. The reason: every catch block elsewhere in the codebase pattern-matches on module exceptions; if you throw `DmlException`, a controller will catch it but lose the module context.

### `@AuraEnabled(cacheable=true)` on read-only LWC-facing methods

Read-only controller methods get `cacheable=true`. Write methods get plain `@AuraEnabled`. Mixing them is a bug — `cacheable=true` on a method that performs DML breaks Lightning caching invariants.

```apex
@AuraEnabled(cacheable=true)
public static List<EngagementDTO> getForOpportunity(Id opportunityId) { ... }

@AuraEnabled
public static AddToOcrResult addToOcrSafe(Id contactId, Id opportunityId, String role, Boolean isPrimary) { ... }
```

[`EngagementController`](../../force-app/main/default/classes/engagement/EngagementController.cls) shows the split.

### Bulkify by default — no SOQL/DML in loops

Every Service collects ids up front, queries once, and operates over hash-map lookups. [`EngagementSignalRouter.routeTouches`](../../force-app/main/default/classes/engagement/EngagementSignalRouter.cls) is the reference — six SOQL queries regardless of input size (touches, opportunities, OCR, ACR, existing signals, routing rules). A nested SOQL inside the per-touch loop would die the first time HubSpot streamed a 200-event batch.

Same rule for DML: collect into a `List`, fire once at the end.

```apex
// Good
List<Opportunity_Engagement_Signal__c> toInsert = new List<Opportunity_Engagement_Signal__c>();
for (Engagement_Touch__c t : touches) {
  toInsert.add(buildSignal(t, ...));
}
DMLManager.insertAsUser(toInsert);

// Bad — governor-limit eater
for (Engagement_Touch__c t : touches) {
  DMLManager.insertAsUser(buildSignal(t, ...));
}
```

### Other quick hits

- **`with sharing` on every class.** Even one-off utilities. Sage 🟥 BLOCK otherwise.
- **`@TestVisible` only when a test legitimately needs internal access.** Default to `private`. Don't widen visibility to ease testing — instead, expose the seam via interface injection (e.g. [`EngagementController.setServiceForTest`](../../force-app/main/default/classes/engagement/EngagementController.cls)).
- **DTO field order matches the LWC contract.** [`EngagementDTO`](../../force-app/main/default/classes/engagement/EngagementDTO.cls) field order is read by the panel's HTML template; reordering for "tidiness" can break the wire-getter expectation if a downstream consumer uses positional access.
- **Sanitized error messages over the LWC boundary.** Controllers throw `AuraHandledException` with a friendly string ("Unable to load engagement data for this opportunity.") — they never expose `e.getMessage()` directly. The raw message goes to `Logger.error`; the friendly message goes to the user.

---

**Summary:** [best-practices/apex.md](../../best-practices/apex.md) is the source of truth — start there. The trip-points above (`WITH USER_MODE` on every SOQL, `DMLManager` for DML, `Logger.error` in every catch, exceptions extending `UtilitiesModuleException`, `@AuraEnabled(cacheable=true)` for reads, bulkified Service code) are where PRs get pushed back on this feature specifically.
