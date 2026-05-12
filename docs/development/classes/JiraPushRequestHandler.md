# `JiraPushRequestHandler`

## Orientation

[`JiraPushRequestHandler`](../../../force-app/main/default/classes/JiraPushRequestHandler.cls) is the `TriggerHandler` for the `Jira_Push_Request__e` platform event. Invoked by [`JiraPushRequestTrigger`](../../../force-app/main/default/triggers/JiraPushRequestTrigger.trigger). Platform-event triggers only have an `after insert` phase, so this class has exactly one override.

## Public API

### `afterInsert()`

```apex
protected override void afterInsert() {
    JiraPushDispatcher.process(
        (List<Jira_Push_Request__e>) Trigger.new
    );
}
```

- **Params:** none (consumes `Trigger.new`).
- **Returns:** `void`.
- **Throws:** nothing under normal operation. [`JiraPushDispatcher.process`](JiraPushDispatcher.md) is internally fail-soft (caught exceptions land in `API_Exception_Log__c`).

## Side effects

None directly. All work flows through [`JiraPushDispatcher.process`](JiraPushDispatcher.md), which:

- Reads `Jira_Push_Object__mdt` (via `JiraPushService.getConfig`).
- Calls `JCFS.API.pushUpdatesToJira(...)` (via `IJcfsApi`).
- Writes `API_Exception_Log__c` on malformed-Id, unknown-SObject, or JCFS-side failure.

## Dependencies

- [`JiraPushDispatcher`](JiraPushDispatcher.md)
- `TriggerHandler` framework base class
- [`Jira_Push_Request__e`](../../../force-app/main/default/objects/Jira_Push_Request__e/Jira_Push_Request__e.object-meta.xml)

## Permission model

Platform-event triggers run as the **Automated Process User** (a Salesforce-internal system user), **not** as the user who originated the event. The Automated Process User has system-level access for the duration of the trigger and is not subject to org-wide-defaults. Consequence: the dispatcher can act on `Jira_Push_Object__mdt` and write `API_Exception_Log__c` regardless of the originating user's permissions.

No additional permset entries needed.

## Known limitations

- **PE triggers cannot be retried by the platform.** If the handler throws an uncaught exception, the platform delivers a finite number of replay attempts before discarding the event. The class delegates to a fail-soft dispatcher specifically to avoid this — uncaught exceptions here would be a regression.
- **No `@future` from inside the handler.** JCFS specifically requires trigger context; calling `@future` would break the JCFS contract. Honored by routing straight to `JiraPushDispatcher.process` synchronously.

## Related

- Trigger: [`JiraPushRequestTrigger`](../../../force-app/main/default/triggers/JiraPushRequestTrigger.trigger)
- Dispatcher: [`JiraPushDispatcher`](JiraPushDispatcher.md)
- Tests: [`JiraPushRequestHandlerTest`](../../../force-app/main/default/classes/JiraPushRequestHandlerTest.cls)
- Ticket: [CSI-7162](https://experance.atlassian.net/browse/CSI-7162)
