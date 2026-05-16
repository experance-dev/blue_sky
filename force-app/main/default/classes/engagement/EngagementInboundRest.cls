/**
 * @description Inbound REST endpoint for HubSpot (and other source-system)
 *              engagement events. Parses a batched JSON envelope, validates
 *              required fields per event, resolves Topic / Campaign references
 *              in a bulkified up-front pass, then upserts each event into
 *              `Engagement_Touch__c` keyed on `External_Id__c` so HubSpot
 *              re-deliveries are idempotent. Identity resolution
 *              (Contact / Lead / Account) is delegated to
 *              `IdentityResolutionService` and runs in-memory before the upsert.
 *
 *              Authentication: relies on the calling user's session — the
 *              caller is expected to be the Integration User (API Enabled +
 *              the `Engagement_Attribution_User` permission set). No custom
 *              auth code lives here.
 *
 *              Response contract: HTTP 200 with an `InboundResult` JSON body
 *              capturing per-batch counts and a flat list of error messages.
 *              The endpoint returns HTTP 400 only when the top-level JSON
 *              fails to parse — individual event failures are captured in
 *              the `errors` array so HubSpot can keep streaming.
 *
 *              `global` is required because `@RestResource` cannot be applied
 *              to a `public` class. `with sharing` follows the project-wide
 *              mandate from best-practices/apex.md; the running Integration
 *              User's sharing context governs which records the touch may
 *              link to.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 * @last 2026-05-16 — PR #6 sweep: §6.3 upsertTouches now sets HTTP 500 on catastrophic upsert blowout so HubSpot retries; §3.1 Logger.logException + txn-correlated error responses on parseBody + upsertTouches catches.
 */
@SuppressWarnings('PMD.CyclomaticComplexity')
@RestResource(urlMapping='/engagement/touches/*')
global with sharing class EngagementInboundRest {
  // §12 narrow waiver — Class-level CC: the inbound pipeline is a six-step
  // sequence (parse → validate → lookup topics → lookup campaigns → build →
  // resolve → upsert). Per-method CC is in spec (highest 7); the class total
  // flags because of the step count, not density. Each step is its own
  // single-responsibility helper.
  // ─── Constants ────────────────────────────────────────────────────────────

  private static final String CLASS_NAME = 'EngagementInboundRest';
  private static final String STATUS_PENDING = 'Pending';
  private static final String STATUS_RESOLVED = 'Resolved';
  private static final String STATUS_AMBIGUOUS = 'Ambiguous';
  private static final String STATUS_NO_MATCH = 'NoMatch';
  private static final String PROC_NEW = 'New';
  private static final String PROC_PROCESSED = 'Processed';
  private static final String PROC_ERROR = 'Error';

  // ─── HTTP entry point ─────────────────────────────────────────────────────

  /**
   * @description Handles `POST /services/apexrest/engagement/touches/`.
   *              See class header for the contract.
   * @return `InboundResult` populated with per-batch counts and any per-event
   *         errors. Serialized to JSON automatically by the REST runtime.
   */
  @HttpPost
  global static InboundResult ingest() {
    InboundResult result = new InboundResult();
    RestRequest req = RestContext.request;

    InboundPayload payload = parseBody(req, result);
    if (payload == null || payload.events == null) {
      return result;
    }

    result.received = payload.events.size();

    List<InboundEvent> validEvents = filterAndCollectErrors(
      payload.events,
      result
    );
    if (validEvents.isEmpty()) {
      return result;
    }

    Map<String, Id> topicIdByCode = lookupTopicIdsByExternalCode(validEvents);
    Map<String, Id> campaignIdByName = lookupCampaignIdsByName(validEvents);

    List<Engagement_Touch__c> touches = buildTouches(
      validEvents,
      topicIdByCode,
      campaignIdByName
    );

    IdentityResolutionService.resolveAll(touches);
    applyProcessingStatus(touches);
    tallyResolutionStatuses(touches, result);
    upsertTouches(touches, result);

    return result;
  }

  // ─── Step 1: parse top-level body ─────────────────────────────────────────

  private static InboundPayload parseBody(
    RestRequest req,
    InboundResult result
  ) {
    if (req == null || req.requestBody == null) {
      RestContext.response.statusCode = 400;
      result.errors.add('Empty request body');
      return null;
    }
    String body = req.requestBody.toString();
    if (String.isBlank(body)) {
      RestContext.response.statusCode = 400;
      result.errors.add('Empty request body');
      return null;
    }
    try {
      return (InboundPayload) JSON.deserialize(body, InboundPayload.class);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'parseBody');
      RestContext.response.statusCode = 400;
      // Sanitized response: HubSpot retries on 4xx are upstream policy; the
      // caller needs a stable correlator, not raw parser detail.
      result.errors.add(
        'Invalid JSON. Error ID: ' + System.Request.getCurrent().getRequestId()
      );
      return null;
    }
  }

  // ─── Step 2: per-event validation ─────────────────────────────────────────

  private static List<InboundEvent> filterAndCollectErrors(
    List<InboundEvent> events,
    InboundResult result
  ) {
    List<InboundEvent> valid = new List<InboundEvent>();
    for (InboundEvent e : events) {
      String validationError = validateEvent(e);
      if (validationError == null) {
        valid.add(e);
      } else {
        result.errored += 1;
        result.errors.add(validationError);
      }
    }
    return valid;
  }

  private static String validateEvent(InboundEvent e) {
    if (e == null) {
      return 'Null event payload';
    }
    if (String.isBlank(e.external_id)) {
      return 'Missing required field external_id';
    }
    if (String.isBlank(e.email)) {
      return 'Missing required field email for external_id=' + e.external_id;
    }
    if (e.occurred_at == null) {
      return 'Missing required field occurred_at for external_id=' +
        e.external_id;
    }
    return null;
  }

  // ─── Step 3: bulkified parent-lookup queries ──────────────────────────────

  private static Map<String, Id> lookupTopicIdsByExternalCode(
    List<InboundEvent> events
  ) {
    Set<String> codes = new Set<String>();
    for (InboundEvent e : events) {
      if (String.isNotBlank(e.topic_external_code)) {
        codes.add(e.topic_external_code);
      }
    }
    Map<String, Id> idByCode = new Map<String, Id>();
    if (codes.isEmpty()) {
      return idByCode;
    }
    for (Touch_Topic__c t : [
      SELECT Id, External_Code__c
      FROM Touch_Topic__c
      WHERE External_Code__c IN :codes
      WITH USER_MODE
    ]) {
      idByCode.put(t.External_Code__c, t.Id);
    }
    for (String c : codes) {
      if (!idByCode.containsKey(c)) {
        Logger.warn(
          'Topic external_code not found: ' + c,
          CLASS_NAME,
          'lookupTopicIdsByExternalCode'
        );
      }
    }
    return idByCode;
  }

  private static Map<String, Id> lookupCampaignIdsByName(
    List<InboundEvent> events
  ) {
    Set<String> names = new Set<String>();
    for (InboundEvent e : events) {
      if (String.isNotBlank(e.campaign_external_id)) {
        names.add(e.campaign_external_id);
      }
    }
    Map<String, Id> idByName = new Map<String, Id>();
    if (names.isEmpty()) {
      return idByName;
    }
    for (Campaign c : [
      SELECT Id, Name
      FROM Campaign
      WHERE Name IN :names
      WITH USER_MODE
    ]) {
      idByName.put(c.Name, c.Id);
    }
    return idByName;
  }

  // ─── Step 4: build Engagement_Touch records ───────────────────────────────

  private static List<Engagement_Touch__c> buildTouches(
    List<InboundEvent> events,
    Map<String, Id> topicIdByCode,
    Map<String, Id> campaignIdByName
  ) {
    List<Engagement_Touch__c> touches = new List<Engagement_Touch__c>();
    for (InboundEvent e : events) {
      Engagement_Touch__c t = new Engagement_Touch__c(
        External_Id__c = e.external_id,
        Source_System__c = e.source_system,
        Source_Event_Type__c = e.source_event_type,
        Source_Event_Id__c = e.source_event_id,
        Email_At_Touch__c = e.email,
        Occurred_At__c = e.occurred_at,
        Ingested_At__c = System.now(),
        Asset_Name__c = e.asset_name,
        Asset_Url__c = e.asset_url,
        Touch_Type__c = e.touch_type,
        Touch_Subtype__c = e.touch_subtype,
        Persona__c = e.persona,
        Intent_Level__c = e.intent_level,
        Is_Active__c = true,
        Resolution_Status__c = STATUS_PENDING
      );
      if (
        String.isNotBlank(e.topic_external_code) &&
        topicIdByCode.containsKey(e.topic_external_code)
      ) {
        t.Topic__c = topicIdByCode.get(e.topic_external_code);
      }
      if (
        String.isNotBlank(e.campaign_external_id) &&
        campaignIdByName.containsKey(e.campaign_external_id)
      ) {
        t.Campaign__c = campaignIdByName.get(e.campaign_external_id);
      }
      touches.add(t);
    }
    return touches;
  }

  // ─── Step 5: status assignment + tallying ─────────────────────────────────

  private static void applyProcessingStatus(List<Engagement_Touch__c> touches) {
    for (Engagement_Touch__c t : touches) {
      if (t.Resolution_Status__c == STATUS_NO_MATCH) {
        t.Processing_Status__c = PROC_NEW;
      } else {
        t.Processing_Status__c = PROC_PROCESSED;
      }
    }
  }

  private static void tallyResolutionStatuses(
    List<Engagement_Touch__c> touches,
    InboundResult result
  ) {
    for (Engagement_Touch__c t : touches) {
      if (t.Resolution_Status__c == STATUS_RESOLVED) {
        result.resolved += 1;
      } else if (t.Resolution_Status__c == STATUS_AMBIGUOUS) {
        result.ambiguous += 1;
      } else if (t.Resolution_Status__c == STATUS_NO_MATCH) {
        result.noMatch += 1;
      }
    }
  }

  // ─── Step 6: upsert via DMLManager (USER_MODE) ────────────────────────────

  private static void upsertTouches(
    List<Engagement_Touch__c> touches,
    InboundResult result
  ) {
    if (touches.isEmpty()) {
      return;
    }
    try {
      // Upsert on the External_Id__c key for idempotent re-delivery.
      // NOTE: `DMLManager` does not currently expose an upsert-by-external-id
      // overload, so this call uses the platform `Database.upsert` directly
      // while still enforcing CRUD/FLS via `AccessLevel.USER_MODE` — the same
      // mode `DMLManager.upsertAsUser` delegates to internally. Tracked as a
      // future DMLManager enhancement.
      Schema.SObjectField externalIdField = Engagement_Touch__c.External_Id__c;
      Database.upsert(touches, externalIdField, false, AccessLevel.USER_MODE);
    } catch (Exception e) {
      // §6.3 — catastrophic upsert blowout (vs per-event validation rejection).
      // Surface HTTP 500 so the upstream webhook retries per its idempotency
      // contract; returning 200 here would have HubSpot ACK and drop the batch.
      Logger.logException(e, CLASS_NAME, 'upsertTouches');
      RestContext.response.statusCode = 500;
      result.errored += touches.size();
      result.errors.add(
        'Upsert failed. Error ID: ' + System.Request.getCurrent().getRequestId()
      );
    }
  }

  // ─── DTO inner classes ────────────────────────────────────────────────────

  /**
   * @description Top-level POST body shape. Matches the contract in the Phase 2
   *              spec: `{ "events": [ ... ] }`.
   */
  global class InboundPayload {
    global List<InboundEvent> events;
  }

  /**
   * @description Per-event JSON shape from HubSpot. Field names use
   *              snake_case to match the source-system convention; they map
   *              directly to incoming JSON keys via `JSON.deserialize`.
   *              The snake_case is load-bearing — renaming would break the
   *              HubSpot contract. PMD's `FieldNamingConventions` rule is
   *              suppressed at the class level for this DTO only; not a
   *              project-wide pattern (per §12.3.3 scope).
   */
  @SuppressWarnings('PMD.FieldNamingConventions')
  global class InboundEvent {
    global String external_id;
    global String source_system;
    global String source_event_type;
    global String source_event_id;
    global String email;
    global Datetime occurred_at;
    global String asset_name;
    global String asset_url;
    global String topic_external_code;
    global String campaign_external_id;
    global String touch_type;
    global String touch_subtype;
    global String persona;
    global String intent_level;
  }

  /**
   * @description Per-batch response counters returned to the caller.
   *              `errors` is a flat list of human-readable messages, one
   *              entry per rejected event plus any upsert-level failure.
   */
  global class InboundResult {
    global Integer received;
    global Integer resolved;
    global Integer ambiguous;
    global Integer noMatch;
    global Integer errored;
    global List<String> errors;

    /**
     * @description No-arg constructor — initialises all counters to zero
     *              and the errors list to empty so the handler can
     *              increment + append without null-check noise.
     */
    global InboundResult() {
      this.received = 0;
      this.resolved = 0;
      this.ambiguous = 0;
      this.noMatch = 0;
      this.errored = 0;
      this.errors = new List<String>();
    }
  }
}
