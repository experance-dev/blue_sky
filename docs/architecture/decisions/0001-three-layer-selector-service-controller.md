# ADR 0001 — Three-layer Selector / Service / Controller pattern

- **Status:** Accepted (2026-05-11)
- **Decision-makers:** Atlas (TA), David Wood (architect)
- **Supersedes:** —

## Context

The Engagement Attribution feature ships Apex code across three distinct concerns:

1. **Data access** — bulkified SOQL against `Engagement_Touch__c`, `OpportunityContactRole`, `AccountContactRelation`, `Touch_Topic__c`, `Touch_Routing_Rule__mdt`, `Engagement_Dismissal__c`, and standard objects.
2. **Business logic** — DTO assembly, race-protected OCR insert, identity resolution, signal routing, GDPR/CCPA erasure cascade, signal-decay arithmetic.
3. **Surface** — LWC-facing `@AuraEnabled` controllers, an inbound REST endpoint, two `before delete` triggers, one `after insert/update` trigger, a scheduled batch entry point.

Without a layering rule, those concerns collide:

- SOQL in the controller blocks Apex unit-testing of business logic without a real org.
- DML in selectors makes "read-only queries" untrue and breaks single-responsibility.
- Trigger handlers writing their own queries duplicate logic the controller also runs.
- LWCs reach past the controller and import service classes directly, so the surface contract drifts.

The project [`best-practices/architecture.md`](../../../best-practices/architecture.md) codifies the Selector / Service / Domain split as the org-wide pattern; this ADR records the team's adoption for the engagement feature and the specific class-level conventions that follow from it.

## Decision

Engagement Attribution Apex is organized into **three layers plus surfaces**:

```
   Surface  (Controller, REST resource, Trigger handler, Batch entry)
      │
      ▼
   Service  (IEngagementService, EngagementSignalRouter,
             IdentityResolutionService, EngagementErasureService,
             EngagementSignalDecayBatch, EngagementTouchArchivalBatch)
      │
      ▼
   Selector (EngagementTouchesSelector, OpportunityContactRolesSelector,
             TouchTopicSelector, TouchRoutingRulesSelector,
             EngagementDismissalsSelector)

   Domain   (EngagementTouches — collaborates with the Service layer
             for in-memory shaping; no DML of its own)
```

**Layer rules:**

1. **Selectors** own SOQL. No DML. No business logic. Bulk-safe — every method accepts a `Set<Id>` or equivalent and returns a `List<SObject>` or `Map<...>`. Every query carries `WITH USER_MODE`. Example: [`EngagementTouchesSelector.selectByOpportunityWithTopics`](../../../force-app/main/default/classes/engagement/EngagementTouchesSelector.cls).
2. **Services** own business rules. They orchestrate Selectors, perform DML through [`DMLManager`](../../../force-app/main/default/classes/dml/DMLManager.cls) with `AccessLevel.USER_MODE`, throw module-typed exceptions (e.g. [`EngagementException`](../../../force-app/main/default/classes/engagement/EngagementException.cls) extends `UtilitiesModuleException`), and log via [`Logger`](../../../force-app/main/default/classes/logging/Logger.cls). LWC-facing services define an interface ([`IEngagementService`](../../../force-app/main/default/classes/engagement/IEngagementService.cls)) so the controller can swap in a stub via `@TestVisible setServiceForTest(...)`.
3. **Domain** classes wrap a `List<SObject>` of one type and expose shaping helpers ([`EngagementTouches`](../../../force-app/main/default/classes/engagement/EngagementTouches.cls)). Domain methods are pure-ish — no DML, no SOQL — and can be invoked from the Service layer to keep the Service slim.
4. **Surfaces** are thin. Controllers wrap one Service call, log exceptions, and rethrow as `AuraHandledException` with a sanitized message. REST resources parse the JSON envelope, delegate to a Service, and return a typed response DTO. Trigger handlers (registered via [`TriggerHandler`](../../../force-app/main/default/classes/triggers/TriggerHandler.cls)) extract context and delegate to a Service. Batches implement `Database.Batchable<SObject>` and delegate per-chunk logic to a Service or Service-equivalent static.

**DTO ownership:** [`EngagementDTO`](../../../force-app/main/default/classes/engagement/EngagementDTO.cls) and [`AddToOcrResult`](../../../force-app/main/default/classes/engagement/AddToOcrResult.cls) are the only types crossing the LWC boundary. They live in the same package as the Service that constructs them; the controller is a pass-through.

**Naming:**

- Selectors → `<ObjectPluralOrFeature>Selector` (e.g. `EngagementTouchesSelector`).
- Service interface → `I<Feature>Service`; implementation → `<Feature>ServiceImpl`. Standalone Service-equivalents (signal router, identity resolver, erasure cascade) use a descriptive class name without the `Impl` suffix.
- Domain → `<ObjectPlural>` (e.g. `EngagementTouches`).
- Custom exception → `<Feature>Exception extends UtilitiesModuleException`.

## Consequences

**What becomes easier:**

- Unit tests substitute mock Selectors / Services for the real implementation. [`EngagementControllerTest`](../../../force-app/main/default/classes/engagement/EngagementControllerTest.cls) injects a stub `IEngagementService` via `setServiceForTest(...)`, so controller-layer assertions don't depend on org data.
- Bulkification is enforced at the Selector boundary — Services receive `List<SObject>` and operate over them in memory, so a single-event REST POST and a 200-event HubSpot batch run the same code path.
- USER_MODE / CRUD-FLS enforcement is local to two layers (Selector queries + Service DML), not scattered through every controller method.
- Trigger handlers stay small. [`EngagementTouchTriggerHandler`](../../../force-app/main/default/classes/engagement/EngagementTouchTriggerHandler.cls) is 60 lines because routing logic lives in [`EngagementSignalRouter`](../../../force-app/main/default/classes/engagement/EngagementSignalRouter.cls).
- Per-class documentation maps cleanly to the layer — [development/classes/](../../development/classes/) is organized by surface; selectors/domain don't need standalone docs (they're trivial wrappers).

**What becomes harder:**

- More classes for the same feature surface area. The Engagement package ships ~25 production Apex classes; a "one big class per feature" approach would ship 6–8.
- New devs need to internalize the layering rule before they can navigate. The fix is [development/onboarding.md](../../development/onboarding.md) and Atlas's PR review.
- A Service that touches three unrelated objects can become a god-class. Mitigation: split by feature, not by object — `EngagementSignalRouter`, `IdentityResolutionService`, `EngagementErasureService` are three separate classes because they answer three separate questions, not because they touch three separate tables.
- Static analysis tooling needs to learn the convention. The complexity budget in [apex.md](../../../best-practices/apex.md) (Apex complexity < 8/method, < 45/class) is the proxy until we add a project-specific PMD rule set.

## Related

- [best-practices/architecture.md](../../../best-practices/architecture.md) — org-wide statement of the pattern.
- [architecture/overview.md](../overview.md) — applied view of the layering against the Engagement feature.
- [development/apex-conventions.md](../../development/apex-conventions.md) — class-authoring rules that follow from the layering.
- [development/classes/](../../development/classes/) — per-class reference for the five most-trafficked surfaces.
