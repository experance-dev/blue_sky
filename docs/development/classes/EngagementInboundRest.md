# `EngagementInboundRest`

[`force-app/main/default/classes/engagement/EngagementInboundRest.cls`](../../../force-app/main/default/classes/engagement/EngagementInboundRest.cls)

## Orientation

The inbound REST endpoint at `/services/apexrest/engagement/touches/`. Accepts a batched JSON envelope from HubSpot (or any other source system), validates per-event required fields, resolves Topic / Campaign references in a bulkified up-front pass, delegates Contact / Lead / Account resolution to [`IdentityResolutionService.resolveAll`](IdentityResolutionService.md), then upserts the resulting [`Engagement_Touch__c`](../../../force-app/main/default/objects/Engagement_Touch__c/) records keyed on `External_Id__c` so HubSpot re-deliveries are idempotent. Single SOQL per parent object regardless of batch size.

`global with sharing` — `global` is required because `@RestResource` cannot be applied to a `public` class; `with sharing` follows the project mandate. The running Integration User's sharing context governs which records the touch may link to.

## Endpoint contract

```
POST  /services/apexrest/engagement/touches/
Content-Type: application/json
Authorization: Bearer <session-id>
```

### Request body (`InboundPayload`)

```json
{
  "events": [
    {
      "external_id": "HS-abc123",
      "source_system": "HubSpot",
      "source_event_type": "Download",
      "source_event_id": "12345",
      "email": "sarah.johnson@uhc.example.com",
      "occurred_at": "2026-05-10T14:00:00Z",
      "asset_name": "Network Pricing Whitepaper",
      "asset_url": "https://zelis.com/whitepaper",
      "topic_external_code": "TOPIC_NETWORK_MGMT",
      "campaign_external_id": null,
      "touch_type": "Download",
      "touch_subtype": "PDF Download",
      "persona": "Executive",
      "intent_level": "Medium"
    }
  ]
}
```

**Required per event:** `external_id`, `email`, `occurred_at`. Missing any of these → the event is rejected (counted in `errored`, message appended to `errors`); other events in the batch continue.

### Response body (`InboundResult`, always JSON, almost always HTTP 200)

```json
{
  "received": 1,
  "resolved": 1,
  "ambiguous": 0,
  "noMatch": 0,
  "errored": 0,
  "errors": []
}
```

| Field       | Meaning                                                        |
| ----------- | -------------------------------------------------------------- |
| `received`  | Total events in the inbound payload.                           |
| `resolved`  | Resolved to exactly one Contact or one Lead.                   |
| `ambiguous` | Multiple Contact or Lead matches on the email — not bound.     |
| `noMatch`   | Zero Contact and zero Lead matches — queued for human review.  |
| `errored`   | Per-event validation rejects + any batch-level upsert failure. |
| `errors`    | Flat list of human-readable error messages.                    |

### HTTP status codes

| Code | When                                                                           |
| ---- | ------------------------------------------------------------------------------ |
| 200  | Default response. Per-event failures are in `errors` array.                    |
| 400  | Top-level JSON body could not be parsed at all (empty body or malformed JSON). |

The endpoint deliberately returns 200 even with all events erroring so HubSpot can keep streaming — partial-success is the design.

## Public API (Apex)

| Method                                    | Params                          | Returns                                                  | Throws                                    |
| ----------------------------------------- | ------------------------------- | -------------------------------------------------------- | ----------------------------------------- |
| `ingest()` — `@HttpPost`, `global static` | — (reads `RestContext.request`) | `InboundResult` (serialized to JSON by the REST runtime) | — (all exceptions captured into `errors`) |

### Inner classes (DTO contract)

- **`InboundPayload`** — `{ events: List<InboundEvent> }`. `global` (crosses the REST boundary).
- **`InboundEvent`** — per-event payload. Snake_case field names match the HubSpot wire format. `global`.
- **`InboundResult`** — per-batch counters. `global`.

## Processing flow

1. **Parse body** — `parseBody`. Top-level JSON failure → HTTP 400 + early return.
2. **Validate** — `filterAndCollectErrors`. Per-event required-field check; rejects bypass the downstream pipeline.
3. **Bulk parent lookups** — `lookupTopicIdsByExternalCode` queries `Touch_Topic__c` by `External_Code__c`; `lookupCampaignIdsByName` queries `Campaign` by `Name`. Both use `WITH USER_MODE`. Missing topic codes are `Logger.warn`'d but do not reject the event.
4. **Build records** — `buildTouches` constructs `Engagement_Touch__c` with `Resolution_Status__c = Pending`.
5. **Identity resolution** — delegates to [`IdentityResolutionService.resolveAll`](IdentityResolutionService.md). Mutates the list in place, sets `Contact__c` / `Lead__c` / `Account__c` / `Resolution_Status__c`.
6. **Status assignment** — `applyProcessingStatus`. `NoMatch` → `Processing_Status__c = New` (eligible for human triage); everything else → `Processed`.
7. **Tally** — `tallyResolutionStatuses` increments the `resolved` / `ambiguous` / `noMatch` counters.
8. **Upsert** — `upsertTouches`. `Database.upsert(touches, External_Id__c, false, AccessLevel.USER_MODE)`. `allOrNothing=false` so a partial-batch failure doesn't roll back the whole call.

## Side effects

- **Upserts** `Engagement_Touch__c` records keyed on `External_Id__c`. Idempotent across HubSpot re-delivery — the same `external_id` updates the existing row instead of duplicating.
- **Logger output:** `Logger.warn` for unmatched topic codes; `Logger.error` for JSON parse failures and upsert failures.
- **No emails sent.** No async work enqueued. No platform events fired.
- **Trigger cascade:** every upserted touch fires [`EngagementTouchTrigger`](../../../force-app/main/default/triggers/EngagementTouchTrigger.trigger) which delegates to [`EngagementTouchTriggerHandler`](../../../force-app/main/default/classes/engagement/EngagementTouchTriggerHandler.cls), which routes resolved touches through [`EngagementSignalRouter.routeTouches`](EngagementSignalRouter.md). So a HubSpot POST may produce `Opportunity_Engagement_Signal__c` rows as a side effect of the trigger cascade.

## Dependencies

| Direction      | What                                                                                                                                                                                                 |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Depends on     | [`IdentityResolutionService`](IdentityResolutionService.md), [`Logger`](../../../force-app/main/default/classes/logging/Logger.cls), inline SOQL against `Touch_Topic__c` and `Campaign` (USER_MODE) |
| Depended on by | External callers — HubSpot integration; the anonymous-Apex test harness in [operations/apex-invocation-runbook.md §Manually invoke the REST endpoint](../../operations/apex-invocation-runbook.md)   |

## Permission model

The Integration User profile needs:

- **API Enabled** (system permission).
- Membership in the **Engagement Attribution User** permission set ([`Engagement_Attribution_User`](../../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml)) — grants Apex class access to `EngagementInboundRest` + CRUD on `Engagement_Touch__c`, `Touch_Topic__c`, `Campaign`, `Contact`, `Lead`.

Authentication is **session-based** — no custom auth code lives in the class. Production callers use a Connected App + JWT bearer flow or a direct session-id from a username-password OAuth flow. The `with sharing` modifier means the Integration User's sharing rules govern which Contact / Lead the touch can bind to.

## Known limitations

- **No DMLManager upsert-by-external-id overload yet.** The class uses `Database.upsert(...)` directly with `AccessLevel.USER_MODE`. Tracked as a future `DMLManager.upsertAsUser(records, externalIdField)` enhancement; reviewed and approved as the documented exception in [development/apex-conventions.md §DMLManager over raw DML](../apex-conventions.md#dmlmanager-over-raw-dml).
- **HTTP 400 only on top-level parse failure.** Per-event validation failures return 200 with the error in the body. This is by design — HubSpot's retry policy escalates on 4xx/5xx but lets 200-with-errors flow.
- **Campaign lookup is by Name, not by external id.** Field is misnamed `campaign_external_id`; the lookup query matches on `Campaign.Name`. Acceptable for Phase 2; revisit if Zelis wires a real campaign-id correlation.
- **Topic-code mismatches log but don't reject.** A touch with an unmatched `topic_external_code` still upserts with `Topic__c = null`. The `Logger.warn` is the audit trail; review the log if downstream routing produces unexpected results.

## Related

- Identity resolver: [`IdentityResolutionService`](IdentityResolutionService.md).
- Signal router (downstream of trigger cascade): [`EngagementSignalRouter`](EngagementSignalRouter.md).
- Lead reparenting (Phase 2 partner): [`LeadEngagementReparentHandler`](../../../force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls).
- Tests: [`EngagementInboundRestTest`](../../../force-app/main/default/classes/engagement/EngagementInboundRestTest.cls).
- Demo runbook: [users/DEMO.md §Phase 2 — HubSpot ingestion](../../users/DEMO.md#phase-2--hubspot-ingestion).
- Operational invocation: [operations/apex-invocation-runbook.md §Manually invoke the REST endpoint](../../operations/apex-invocation-runbook.md).
