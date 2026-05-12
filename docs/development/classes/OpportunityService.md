# `OpportunityService`

## Orientation

[`OpportunityService`](../../../force-app/main/default/classes/OpportunityService.cls) is the Opportunity domain service. It owns the question _"does this Opportunity change warrant a Jira sync?"_ and translates `Trigger.new` / `Trigger.oldMap` into calls to the SObject-agnostic [`JiraPushService`](JiraPushService.md). It is the **only** class in this feature that names individual Opportunity fields.

## Public API

### `JIRA_QUALIFYING_FIELDS`

```apex
@TestVisible
private static final Set<Schema.SObjectField> JIRA_QUALIFYING_FIELDS = new Set<Schema.SObjectField>{
    Opportunity.StageName,
    Opportunity.Amount,
    Opportunity.CloseDate,
    Opportunity.AccountId,
    Opportunity.OwnerId,
    Opportunity.Probability
};
```

The curated set of fields whose change triggers a Jira sync on update. `Schema.SObjectField` tokens (not strings) so a rename or typo is caught at compile time. Each entry costs one platform event per qualifying record per transaction.

### `handleJiraPushInsert(List<Opportunity> newList)`

- **Signature:** `public static void handleJiraPushInsert(List<Opportunity> newList)`
- **Params:** `newList` — `Trigger.new` from `OpportunityTriggerHandler.afterInsert`.
- **Returns:** `void`.
- **Throws:** nothing under normal operation. Publishing is internally fail-soft (failures are logged to `API_Exception_Log__c`, not thrown).
- **Behavior:** Every newly-created Opportunity is published. No filter at this layer — the initial sync establishes the Jira link. Note that `JiraPushService.publishInserts` itself now consults the `Jira_Push_Object__mdt.Active__c` kill switch at the publish site (Boomer's M1 fix), so an inactive CMDT short-circuits before any PE is published.
- **Example:**
  ```apex
  // In OpportunityTriggerHandler:
  protected override void afterInsert() {
      OpportunityService.handleJiraPushInsert((List<Opportunity>) Trigger.new);
  }
  ```

### `handleJiraPushUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap)`

- **Signature:** `public static void handleJiraPushUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap)`
- **Params:** `newList` — `Trigger.new`. `oldMap` — `Trigger.oldMap`.
- **Returns:** `void`.
- **Throws:** nothing under normal operation.
- **Behavior:** Filters `newList` to records where at least one field in `JIRA_QUALIFYING_FIELDS` changed (uses `anyQualifyingFieldChanged`), then delegates the filtered list to `JiraPushService.publishUpdates(...)`. Records missing from `oldMap` are skipped quietly (defensive guard against undelete/programmatic edge cases). As with the insert path, the publish-site CMDT gate in `JiraPushService.isActive` will short-circuit if the SObject is currently disabled.

### `anyQualifyingFieldChanged(Opportunity newRec, Opportunity oldRec, Set<Schema.SObjectField> fields)` _(TestVisible private)_

- **Signature:** `private static Boolean anyQualifyingFieldChanged(Opportunity newRec, Opportunity oldRec, Set<Schema.SObjectField> fields)`
- **Returns:** `Boolean` — true if any field in `fields` differs between `newRec` and `oldRec`.
- **Notes:** Pure function. Caller owns the field set — reusable by any domain service that wants the same change-detection semantics (the helper itself is not Opportunity-specific apart from the typed parameters).

## Side effects

- **Indirectly publishes platform events** via [`JiraPushService.publishInserts`](JiraPushService.md#publishinserts) / [`JiraPushService.publishUpdates`](JiraPushService.md#publishupdates). One `Jira_Push_Request__e` per qualifying record.
- **No DML** in its own scope.
- **No SOQL** in its own scope.
- **No logging** in its own scope — logging is the responsibility of `JiraPushService` and `JiraPushDispatcher`.

## Dependencies

- `Opportunity` SObject (compile-time field references via `Opportunity.StageName` etc.).
- [`JiraPushService`](JiraPushService.md) — publisher.
- `Schema.SObjectField` system class.

## Permission model

The running user needs no special permission beyond Opportunity edit. The class uses `with sharing` (consistent with [best-practices/apex.md](../../../best-practices/apex.md)); the actual platform-event publish elevates implicitly per Salesforce PE semantics, so a low-privilege user editing an Opportunity can still trigger a downstream Jira sync — by design.

## Known limitations

- **Hard-coded to `Opportunity`.** Adding a new push target SObject requires a sibling service class with its own qualifying-fields set; do not generalize this class.
- **Field set is build-time, not runtime-configurable.** Admins cannot toggle individual qualifying fields without a code change. If that becomes a requirement, expose the set through CMDT — but this was an explicit non-goal for CSI-7162.
- **Custom formula fields don't trigger after-update.** A formula field whose value changes because its inputs changed does not by itself fire `after update`; the input change does. If a Jira-relevant value is a formula, watch the underlying input fields instead.

## Related

- Trigger handler: [`OpportunityTriggerHandler`](OpportunityTriggerHandler.md)
- Downstream publisher: [`JiraPushService`](JiraPushService.md)
- Tests: [`OpportunityServiceTest`](../../../force-app/main/default/classes/OpportunityServiceTest.cls)
- E2E test: [`OpportunityTriggerHandlerTest`](../../../force-app/main/default/classes/OpportunityTriggerHandlerTest.cls)
- Ticket: [CSI-7162](https://experance.atlassian.net/browse/CSI-7162)
