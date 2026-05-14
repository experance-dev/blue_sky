# `OpportunityTriggerHandler`

## Orientation

[`OpportunityTriggerHandler`](../../../force-app/main/default/classes/OpportunityTriggerHandler.cls) extends the generic `TriggerHandler` framework and is the thin dispatcher between [`OpportunityTrigger`](../../../force-app/main/default/triggers/OpportunityTrigger.trigger) and [`OpportunityService`](../../../force-app/main/default/classes/OpportunityService.cls). Per the class header: _"Add new side-effects on Opportunity by adding methods to OpportunityService, not here."_

## Public API

Two `protected override` methods inherited from `TriggerHandler`:

### `afterInsert()`

```apex
protected override void afterInsert() {
    OpportunityService.handleJiraPushInsert((List<Opportunity>) Trigger.new);
}
```

- **Params:** none (consumes `Trigger.new`).
- **Returns:** `void`.
- **Throws:** anything thrown by `OpportunityService.handleJiraPushInsert` — in practice nothing, because the service is purely additive (it only publishes a platform event).

### `afterUpdate()`

```apex
protected override void afterUpdate() {
    OpportunityService.handleJiraPushUpdate(
        (List<Opportunity>) Trigger.new,
        (Map<Id, Opportunity>) Trigger.oldMap
    );
}
```

- **Params:** none (consumes `Trigger.new` and `Trigger.oldMap`).
- **Returns:** `void`.
- **Throws:** nothing under normal operation. The service is internally fail-soft.

## Side effects

None directly. Side effects (platform-event publish, exception logging) live in [`OpportunityService`](OpportunityService.md) and [`JiraPushService`](JiraPushService.md).

## Dependencies

- `TriggerHandler` framework base class (see [best-practices/architecture.md](../../../best-practices/architecture.md))
- [`OpportunityService`](OpportunityService.md)

## Permission model

Standard Opportunity edit/create permission only. The handler does no SOQL or DML in its own scope.

## Known limitations

- No before-phase support. If a future feature needs pre-save mutation, override `beforeInsert` / `beforeUpdate` here and add a corresponding service method.
- Trigger framework bypass switches (if any) apply uniformly — there's no per-Jira-push bypass independent of "disable the Opportunity trigger entirely." See the [runbook](../../operations/csi7162-jira-push-runbook.md#disable-the-push) for the deliberate kill switch (CMDT `Active__c`).

## Related

- Trigger: [`OpportunityTrigger`](OpportunityTrigger.md)
- Service: [`OpportunityService`](OpportunityService.md)
- E2E test: [`OpportunityTriggerHandlerTest`](../../../force-app/main/default/classes/OpportunityTriggerHandlerTest.cls)
- Ticket: [CSI-7162](https://experance.atlassian.net/browse/CSI-7162)
