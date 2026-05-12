# `OpportunityTrigger`

## Orientation

[`OpportunityTrigger`](../../../force-app/main/default/triggers/OpportunityTrigger.trigger) is the platform-trigger entry point for `Opportunity`. It contains zero business logic — it instantiates [`OpportunityTriggerHandler`](../../../force-app/main/default/classes/OpportunityTriggerHandler.cls) and calls `.run()`. Conventions enforced: one trigger per SObject, no inline logic, both `after insert` and `after update` only (no before-phases for this feature).

## Public API

```apex
trigger OpportunityTrigger on Opportunity(after insert, after update) {
  new OpportunityTriggerHandler().run();
}
```

No public surface. The `TriggerHandler.run()` invocation routes to `afterInsert()` / `afterUpdate()` overrides defined on the handler.

## Side effects

None directly — everything flows through [`OpportunityTriggerHandler`](OpportunityTriggerHandler.md).

## Dependencies

- [`OpportunityTriggerHandler`](../../../force-app/main/default/classes/OpportunityTriggerHandler.cls)
- The shared `TriggerHandler` framework base class (governs phase routing, recursion control, bypass switches — see [best-practices/architecture.md](../../../best-practices/architecture.md)).

## Permission model

No additional permset entries. The trigger fires under the running user's context; the user only needs Opportunity edit access (already granted by standard CRUD).

## Known limitations

- Only handles `after` phases. If pre-save validation needs to factor into the push decision, that work would need a `before` phase added here.
- Subject to the standard Salesforce 200-record per-batch chunking. `OpportunityService` is bulk-safe; see [`OpportunityService`](OpportunityService.md).

## Related

- Handler: [`OpportunityTriggerHandler`](OpportunityTriggerHandler.md)
- Service: [`OpportunityService`](OpportunityService.md)
- End-to-end test: [`OpportunityTriggerHandlerTest`](../../../force-app/main/default/classes/OpportunityTriggerHandlerTest.cls)
- Ticket: [CSI-7162](https://experance.atlassian.net/browse/CSI-7162)
