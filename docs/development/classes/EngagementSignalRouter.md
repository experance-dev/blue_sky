# `EngagementSignalRouter`

[`force-app/main/default/classes/engagement/EngagementSignalRouter.cls`](../../../force-app/main/default/classes/engagement/EngagementSignalRouter.cls)

## Orientation

Phase 3 routing intelligence. Turns resolved [`Engagement_Touch__c`](../../../force-app/main/default/objects/Engagement_Touch__c/) records into [`Opportunity_Engagement_Signal__c`](../../../force-app/main/default/objects/Opportunity_Engagement_Signal__c/) records by walking the priority-ordered [`Touch_Routing_Rule__mdt`](../../../force-app/main/default/objects/Touch_Routing_Rule__mdt/) set. One signal per (touch, opportunity) — the highest-priority rule that matches wins.

Invoked from [`EngagementTouchTriggerHandler`](../../../force-app/main/default/classes/engagement/EngagementTouchTriggerHandler.cls) on `after insert` (every newly resolved touch) and `after update` (transitions to `Resolved`). Six SOQL queries regardless of input size, hash-map lookups in inner loops, idempotent across re-routing — re-firing the trigger creates no duplicates.

## Public API

| Method                                             | Params                                                      | Returns                                  | Throws                                                                                                             |
| -------------------------------------------------- | ----------------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `routeTouches(Set<Id> touchIds)` — `public static` | `touchIds` — touches to route (null / empty short-circuits) | `void` (signals inserted as side effect) | [`EngagementException`](../../../force-app/main/default/classes/engagement/EngagementException.cls) on DML failure |

That is the entire public surface. All other methods are private helpers. The trigger handler is the only production caller; the anonymous-Apex test harness in [operations/apex-invocation-runbook.md §Manually call EngagementSignalRouter](../../operations/apex-invocation-runbook.md) is the ad-hoc invocation path.

### Filtering rules

- Only `Resolution_Status__c = Resolved` touches are routed. `NoMatch` and `Ambiguous` touches are filtered out at the start query — they require human triage before becoming signals.
- Only open Opportunities on the touch's Account are candidate destinations (`IsClosed = FALSE`).
- For each (touch, opp) pair, rules are evaluated in `Priority__c` ASC order. The first match wins; lower-priority rules are skipped.

### Rule structure (Touch_Routing_Rule\_\_mdt)

A rule matches when **all** specified constraints pass:

| Constraint                | Behaviour                                                                                                                                                                                                        |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Require_Same_Account__c` | If true, touch's Account must equal Opp's Account.                                                                                                                                                               |
| `Require_Topic_Match__c`  | If true, touch's Topic must equal Opp's `Touch_Topic__c`.                                                                                                                                                        |
| `Persona_Filter__c`       | If non-blank, touch's `Persona__c` must equal this value.                                                                                                                                                        |
| `Touch_Type_Filter__c`    | If non-blank, touch's `Touch_Type__c` must equal this value.                                                                                                                                                     |
| `Min_Intent_Level__c`     | If non-blank, touch's `Intent_Level__c` must rank at or above (`Low` < `Medium` < `High`).                                                                                                                       |
| `Match_Path__c`           | Structural: `OCR` requires touch's Contact on the Opp's OCR; `ACR` requires AccountContactRelation; `Consultant` requires ACR with `IsDirect=false`; `Account` / `Domain` impose no extra structural constraint. |

Five rules ship out of the box — see [users/DEMO.md §Seeded routing rules](../../users/DEMO.md#seeded-routing-rules) for the full table.

## Side effects

- **DML:** `DMLManager.insertAsUser(signals)` on the built list of `Opportunity_Engagement_Signal__c`. One INSERT per `routeTouches` call.
- **Logger:** `Logger.info` on successful insert with the count. `Logger.error` on DML failure.
- **Idempotency:** existing signals keyed by `(Engagement_Touch__c, Opportunity__c, Match_Path__c)` are loaded up-front and skipped, so re-routing the same touch twice creates no duplicates. The `stagedKeys` set deduplicates within a single batch as well.

## Dependencies

| Direction      | What                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Depends on     | [`TouchRoutingRulesSelector`](../../../force-app/main/default/classes/engagement/TouchRoutingRulesSelector.cls), [`DMLManager`](../../../force-app/main/default/classes/dml/DMLManager.cls), [`Logger`](../../../force-app/main/default/classes/logging/Logger.cls), [`EngagementException`](../../../force-app/main/default/classes/engagement/EngagementException.cls), inline USER_MODE queries against `Engagement_Touch__c`, `Opportunity`, `OpportunityContactRole`, `AccountContactRelation`, `Opportunity_Engagement_Signal__c` |
| Depended on by | [`EngagementTouchTriggerHandler`](../../../force-app/main/default/classes/engagement/EngagementTouchTriggerHandler.cls) (production); the manual-invocation snippet in the operations runbook                                                                                                                                                                                                                                                                                                                                           |

## Permission model

Inherits the [`Engagement_Attribution_User`](../../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml) permset: read on `Engagement_Touch__c` / `Opportunity` / `OpportunityContactRole` / `AccountContactRelation`, read on `Touch_Routing_Rule__mdt` (custom metadata is universally readable for users with platform license), CRUD on `Opportunity_Engagement_Signal__c`.

The trigger handler runs in the **inserting user's** sharing context. A touch posted by the Integration User routes against opportunities the Integration User can see — make sure the Integration User has visibility to all candidate Opps via sharing rules or `View All` on Opportunity.

## Known limitations

- **Opportunity scope is "open only".** Closed-Won opportunities do not receive new signals. Acceptable for the sales-attribution use case; revisit if marketing wants post-close engagement intelligence.
- **Single match path per (touch, opp).** The highest-priority rule wins; signals don't accumulate match paths. A touch that matches both `OCR_Exact_Match` and `Account_Topic_Default` gets exactly one signal with `Match_Path__c = OCR`.
- **Rule ordering is by `Priority__c` ASC** — lower number = evaluated earlier. Counter-intuitive; flagged in the demo doc and the seeded rule table.
- **No retry on DML failure.** A failed insert rethrows; the trigger framework allows the parent DML to fail. If batch HubSpot ingestion partially fails because of routing, the touch upsert still succeeded but no signal exists — re-running `routeTouches({touch.Id})` recovers (it's idempotent).
- **Routing rule deploys are not hot-reload.** Adding a rule via Setup → Custom Metadata Types is live for the next touch event; deploying via metadata XML to `force-app/main/default/customMetadata/` requires a `sf project deploy start`.

## Related

- Trigger + handler: [`EngagementTouchTrigger`](../../../force-app/main/default/triggers/EngagementTouchTrigger.trigger), [`EngagementTouchTriggerHandler`](../../../force-app/main/default/classes/engagement/EngagementTouchTriggerHandler.cls).
- Selector: [`TouchRoutingRulesSelector`](../../../force-app/main/default/classes/engagement/TouchRoutingRulesSelector.cls).
- Tests: [`EngagementSignalRouterTest`](../../../force-app/main/default/classes/engagement/EngagementSignalRouterTest.cls), [`EngagementTouchTriggerHandlerTest`](../../../force-app/main/default/classes/engagement/EngagementTouchTriggerHandlerTest.cls).
- Seeded rules + demo verification: [users/DEMO.md §Phase 3 — Routing intelligence](../../users/DEMO.md#phase-3--routing-intelligence).
- Maintenance (decay / archival): [`EngagementSignalDecayBatch`](../../../force-app/main/default/classes/engagement/EngagementSignalDecayBatch.cls), [`EngagementTouchArchivalBatch`](../../../force-app/main/default/classes/engagement/EngagementTouchArchivalBatch.cls), scheduled via [`EngagementMaintenanceScheduler`](../../../force-app/main/default/classes/engagement/EngagementMaintenanceScheduler.cls).
- Operational invocation: [operations/apex-invocation-runbook.md §Manually call EngagementSignalRouter](../../operations/apex-invocation-runbook.md).
