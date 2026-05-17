# `IdentityResolutionService`

[`force-app/main/default/classes/engagement/IdentityResolutionService.cls`](../../../force-app/main/default/classes/engagement/IdentityResolutionService.cls)

## Orientation

Resolves the Contact / Lead / Account references on a batch of inbound `Engagement_Touch__c` records. For each touch, matches `Email_At_Touch__c` against `Contact.Email` (preferred) then `Lead.Email`, sets `Contact__c` / `Lead__c` / `Account__c` and `Resolution_Status__c` in-place, returns void. Called by [`EngagementInboundRest.ingest`](EngagementInboundRest.md) immediately before the upsert.

Bulkified: **two SOQL queries total** regardless of input size (one for Contacts, one for Leads). Email comparison is case-insensitive — the service lowercases for keying; Salesforce's Email field is case-insensitive at the index layer so `IN :emails` matches all casings.

## Public API

| Method                                                            | Params                                                    | Returns | Throws                                                         |
| ----------------------------------------------------------------- | --------------------------------------------------------- | ------- | -------------------------------------------------------------- |
| `resolveAll(List<Engagement_Touch__c> touches)` — `public static` | `touches` — mutated in place; null / empty short-circuits | `void`  | — (defensive: blank emails are marked `NoMatch`, never throws) |

That is the entire public surface.

### Resolution semantics

| Match count                            | Outcome                                                                                                                                                                                                    |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Exactly 1 Contact                      | `Resolved` + `Contact__c` + `Account__c` (from Contact.AccountId)                                                                                                                                          |
| >1 Contact                             | `Ambiguous`. No Contact / Account binding.                                                                                                                                                                 |
| 0 Contact + exactly 1 unconverted Lead | `Resolved` + `Lead__c`. Account / Contact stay null until the Lead converts — see [`LeadEngagementReparentHandler`](../../../force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls). |
| 0 Contact + >1 Lead                    | `Ambiguous`.                                                                                                                                                                                               |
| 0 Contact + 0 Lead                     | `NoMatch`. Eligible for human review.                                                                                                                                                                      |
| Blank `Email_At_Touch__c`              | `NoMatch` (defensive — REST endpoint normally rejects these upstream).                                                                                                                                     |

**Contact precedence.** A known Contact always wins over a Lead. If the same email appears on both a Contact and a Lead, the Contact match is used. (Converted Leads are excluded from the Lead query — `IsConverted = FALSE` — so a converted lead's email won't double-match.)

## Side effects

- **Mutates input.** `Contact__c`, `Lead__c`, `Account__c`, `Resolution_Status__c` are set in place on every element of `touches`. Callers receive the same list reference; no return value.
- **No DML.** This service does not insert/update/delete anything. It only reads.
- **No logging in the resolution path.** The service is silent on the happy path; ambiguity and no-match are surfaced via `Resolution_Status__c` only.
- **Two SOQL queries** per call (regardless of input batch size).

## Dependencies

| Direction      | What                                                                                |
| -------------- | ----------------------------------------------------------------------------------- |
| Depends on     | Inline USER_MODE queries against `Contact` and `Lead`. No external collaborators.   |
| Depended on by | [`EngagementInboundRest.ingest`](EngagementInboundRest.md) (sole production caller) |

## Permission model

Runs in the caller's sharing context. `with sharing` + `WITH USER_MODE` on both queries means the Integration User must have:

- Read on `Contact` (incl. FLS on `Email`, `AccountId`).
- Read on `Lead` (incl. FLS on `Email`, `IsConverted`).

Both grants are in the [`Engagement_Attribution_User`](../../../force-app/main/default/permissionsets/Engagement_Attribution_User.permissionset-meta.xml) permission set.

A Contact / Lead the Integration User cannot see is structurally invisible — the touch resolves to `NoMatch` even though the email exists in the org. Important sharing implication: if the Integration User is a low-privilege profile without `View All` on Contact, you'll get spurious `NoMatch` results. Either grant `View All`, or move identity resolution to a `without sharing` service with explicit security review (Sage approval required).

## Known limitations

- **Email is the only identity signal.** Phone, name, or marketing-cookie correlation is not considered. Acceptable for Phase 2 — HubSpot's wire format always carries email.
- **Account inheritance from Contact only.** A touch resolved to a Lead does not populate `Account__c`. `LeadEngagementReparentHandler` patches this when the Lead converts.
- **Case-insensitive only at the index layer.** A Contact email stored as `Sarah.Johnson@uhc.example.com` will match an inbound `sarah.johnson@uhc.example.com` because the platform indexes case-insensitively. If you encounter a non-match where you expect a match, check for trailing whitespace or zero-width characters in the source-system payload.
- **Ambiguity is a dead end here.** The service marks `Ambiguous` and stops. Manual triage flow (admin LWC) is a Phase 4 deliverable; see [users/DEMO.md §Phase 4](../../users/DEMO.md#phase-4--admin-tools--maintenance) and the [test-strategy](../../testing/test-strategy.md) for the human-review surface plan.

## Related

- REST entry point: [`EngagementInboundRest`](EngagementInboundRest.md).
- Lead-conversion handler: [`LeadEngagementReparentHandler`](../../../force-app/main/default/classes/engagement/LeadEngagementReparentHandler.cls).
- Tests: [`IdentityResolutionServiceTest`](../../../force-app/main/default/classes/engagement/IdentityResolutionServiceTest.cls).
- Demo flow demonstrating Lead → Contact reparenting: [users/DEMO.md §Lead-conversion reparenting demo](../../users/DEMO.md#lead-conversion-reparenting-demo).
- ADR: [0001 — three-layer pattern](../../architecture/decisions/0001-three-layer-selector-service-controller.md) (this is a Service per the layering rule, not a Selector — it implements the resolution rules, not just read-by-key access).
