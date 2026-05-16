/**
 * @description Service implementation. Aggregates Engagement_Touch__c records
 *              by Contact, joins OpportunityContactRole + AccountContactRelation
 *              context, and returns EngagementDTOs for the LWC layer. Provides
 *              race-protected OCR insert via `addToOcrSafe` per the handoff
 *              contract: re-query inside the same Apex transaction, return the
 *              existing row's metadata when a concurrent writer beat us to it.
 *
 *              Primary semantics note (handoff §Open questions): when caller
 *              passes `isPrimary=true` and another primary already exists on
 *              the Opportunity, Salesforce silently un-flags the prior primary.
 *              Phase 1 ships this default platform behaviour; the
 *              AddToDealTeamModal warns the user separately.
 *
 *              All SOQL/DML enforce CRUD/FLS — SOQL via `WITH USER_MODE`, DML
 *              via DMLManager's `xxxAsUser` overloads (which delegate to
 *              `AccessLevel.USER_MODE`).
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 * @last 2026-05-16 — PR #6 sweep: §3.1 Logger.logException + txn-correlated rethrows on all catch sites; §2.3 dismissSignal now routes via DMLManager.updateAsUser; §1.2.1 loadSourceEventTypeDisplayMap converted from CMDT SOQL to Engagement_Picklist_Display__mdt.getAll() with in-memory filter.
 */
@SuppressWarnings('PMD.CyclomaticComplexity, PMD.CognitiveComplexity')
public with sharing class EngagementServiceImpl implements IEngagementService {
  // §12 narrow waiver — Class-level CC + Cognitive: this service joins five
  // independent data sources (touches, OCR, ACR, dismissals, CMDT picklist
  // display) into a single DTO surface. Per-method complexity is in spec
  // (highest is 9 on assembleDTOs); the class-level total reflects the
  // breadth of the join pipeline, each step a single-responsibility helper.
  // ─── Constants ────────────────────────────────────────────────────────────

  private static final String CLASS_NAME = 'EngagementServiceImpl';
  private static final String SOURCE_EVENT_TYPE_KEY = 'Engagement_Touch__c.Source_Event_Type__c';

  /**
   * @description Cached `API_Value__c → Display_Label__c` map for the
   *              `Engagement_Touch__c.Source_Event_Type__c` picklist, loaded
   *              from `Engagement_Picklist_Display__mdt` rows where
   *              `Active__c = true`. Lazily populated on first read in
   *              `displayLabelFor`. `@TestVisible` so the test team can seed
   *              the map without DML.
   */
  @TestVisible
  private static Map<String, String> sourceEventTypeDisplayMap;

  // ─── Public surface ───────────────────────────────────────────────────────

  /**
   * @description Returns engagement DTOs scoped to an Opportunity. See
   *              IEngagementService for the contract.
   * @param opportunityId Opportunity providing Account + Topic scope.
   * @return List of EngagementDTOs ordered by lastTouchAt DESC.
   */
  public List<EngagementDTO> getForOpportunity(Id opportunityId) {
    if (opportunityId == null) {
      return new List<EngagementDTO>();
    }

    Id accountId = resolveOpportunityAccountId(opportunityId);
    if (accountId == null) {
      return new List<EngagementDTO>();
    }

    Set<Id> topicIds = collectTopicIds(
      TouchTopicSelector.selectByOpportunityId(opportunityId)
    );

    List<Engagement_Touch__c> touches = EngagementTouchesSelector.selectByOpportunityWithTopics(
      opportunityId,
      topicIds
    );
    if (touches.isEmpty()) {
      return new List<EngagementDTO>();
    }

    Map<Id, OpportunityContactRole> ocrByContactId = indexOcrsByContact(
      OpportunityContactRolesSelector.selectByOpportunityId(opportunityId)
    );

    Set<Id> contactIds = collectContactIds(touches);
    Map<Id, AccountContactRelation> acrByContactId = queryAcrsByContact(
      contactIds,
      accountId
    );

    Map<Id, DateTime> dismissalsByContact = EngagementDismissalsSelector.selectLatestByOpportunityForCurrentUser(
      opportunityId
    );

    return assembleDTOs(
      touches,
      ocrByContactId,
      acrByContactId,
      dismissalsByContact
    );
  }

  /**
   * @description Returns engagement DTOs scoped to an Account. No OCR context.
   * @param accountId Account scope for the engagement query.
   * @return List of EngagementDTOs ordered by lastTouchAt DESC.
   */
  public List<EngagementDTO> getForAccount(Id accountId) {
    if (accountId == null) {
      return new List<EngagementDTO>();
    }

    List<Engagement_Touch__c> touches = EngagementTouchesSelector.selectByAccountIds(
      new Set<Id>{ accountId }
    );
    if (touches.isEmpty()) {
      return new List<EngagementDTO>();
    }

    Set<Id> contactIds = collectContactIds(touches);
    Map<Id, AccountContactRelation> acrByContactId = queryAcrsByContact(
      contactIds,
      accountId
    );

    Map<Id, DateTime> dismissalsByContact = EngagementDismissalsSelector.selectLatestByAccountForCurrentUser(
      accountId
    );

    // Account scope: no OCR context — pass an empty map so `onOcr` resolves false.
    return assembleDTOs(
      touches,
      new Map<Id, OpportunityContactRole>(),
      acrByContactId,
      dismissalsByContact
    );
  }

  /**
   * @description Race-protected OCR insert. Implements the protocol from
   *              PHASE1-HANDOFF.md line 196: validate inputs → re-query
   *              existing OCR inside the same Apex transaction → either
   *              return `alreadyExists` with the existing row's metadata or
   *              insert via DMLManager and return the new Id.
   * @param contactId Contact to add to the deal team.
   * @param opportunityId Opportunity to add the Contact to.
   * @param role OpportunityContactRole.Role.
   * @param isPrimary Whether to flag the new OCR as Primary. Note: standard
   *                  platform behaviour silently un-flags any prior primary.
   * @return AddToOcrResult capturing success or race-detection state.
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  public AddToOcrResult addToOcrSafe(
    Id contactId,
    Id opportunityId,
    String role,
    Boolean isPrimary
  ) {
    // 4-param contract mirrors the LWC wire signature — keeps the controller
    // pass-through trivial and avoids a DTO repack on a hot path.
    validateAddToOcrInput(contactId, opportunityId, role);

    List<OpportunityContactRole> existingOcrs = OpportunityContactRolesSelector.selectByOpportunityAndContact(
      opportunityId,
      contactId
    );
    if (!existingOcrs.isEmpty()) {
      return buildAlreadyExistsResult(existingOcrs[0]);
    }

    Boolean effectivePrimary = isPrimary == true;
    OpportunityContactRole ocr = new OpportunityContactRole(
      OpportunityId = opportunityId,
      ContactId = contactId,
      Role = role,
      IsPrimary = effectivePrimary
    );

    try {
      DMLManager.insertAsUser(ocr);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'addToOcrSafe');
      throw new EngagementException(
        'Unable to add Contact to Deal Team. Contact your Administrator and let them know: ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }

    return buildSuccessResult(ocr.Id, role, effectivePrimary);
  }

  /**
   * @description Phase 1 stub for signal dismissal. Throws on null Id; tolerates
   *              non-existent records gracefully (the Phase 1 LWC does not yet
   *              invoke this, but the shape is fixed for Phase 3).
   * @param signalId Signal record Id to dismiss.
   * @param reason Free-form reason captured for analytics.
   */
  public void dismissSignal(Id signalId, String reason) {
    if (signalId == null) {
      throw new EngagementException('signalId required');
    }
    try {
      Opportunity_Engagement_Signal__c signal = new Opportunity_Engagement_Signal__c(
        Id = signalId,
        Dismissed__c = true,
        Dismissed_Reason__c = reason
      );
      DMLManager.updateAsUser(new List<SObject>{ signal });
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'dismissSignal');
      throw new EngagementException(
        'Unable to dismiss signal. Contact your Administrator and let them know: ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }
  }

  /**
   * @description Records a per-user dismissal so the given Contact disappears
   *              from this user's engagement panel for the given scope until
   *              the next new touch arrives. Exactly one of `opportunityId` /
   *              `accountId` must be non-null (XOR — the click context).
   *              Multiple dismissals per (user, contact, scope) are allowed;
   *              `EngagementDismissalsSelector` collapses them to
   *              MAX(Dismissed_At__c) on read.
   * @param contactId Contact the user is dismissing.
   * @param opportunityId Opportunity scope (null when dismissing on Account).
   * @param accountId Account scope (null when dismissing on Opportunity).
   */
  public void dismissContact(Id contactId, Id opportunityId, Id accountId) {
    if (contactId == null) {
      throw new EngagementException('contactId required');
    }
    Boolean hasScope = (opportunityId != null) ^ (accountId != null);
    if (!hasScope) {
      throw new EngagementException(
        'Exactly one of opportunityId or accountId must be provided'
      );
    }
    Engagement_Dismissal__c d = new Engagement_Dismissal__c(
      Contact__c = contactId,
      Opportunity__c = opportunityId,
      Account__c = accountId,
      Dismissed_At__c = System.now()
    );
    try {
      DMLManager.insertAsUser(d);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'dismissContact');
      throw new EngagementException(
        'Unable to dismiss contact. Contact your Administrator and let them know: ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }
  }

  // ─── Private helpers — query / index ──────────────────────────────────────

  private static Id resolveOpportunityAccountId(Id opportunityId) {
    List<Opportunity> opps = [
      SELECT AccountId, Touch_Topic__c
      FROM Opportunity
      WHERE Id = :opportunityId
      WITH USER_MODE
      LIMIT 1
    ];
    if (opps.isEmpty()) {
      return null;
    }
    return opps[0].AccountId;
  }

  private static Set<Id> collectTopicIds(List<Touch_Topic__c> topics) {
    Set<Id> topicIds = new Set<Id>();
    if (topics == null) {
      return topicIds;
    }
    for (Touch_Topic__c topic : topics) {
      topicIds.add(topic.Id);
    }
    return topicIds;
  }

  private static Set<Id> collectContactIds(List<Engagement_Touch__c> touches) {
    Set<Id> contactIds = new Set<Id>();
    for (Engagement_Touch__c t : touches) {
      if (t.Contact__c != null) {
        contactIds.add(t.Contact__c);
      }
    }
    return contactIds;
  }

  private static Map<Id, OpportunityContactRole> indexOcrsByContact(
    List<OpportunityContactRole> ocrs
  ) {
    Map<Id, OpportunityContactRole> indexed = new Map<Id, OpportunityContactRole>();
    for (OpportunityContactRole ocr : ocrs) {
      if (ocr.ContactId != null && !indexed.containsKey(ocr.ContactId)) {
        indexed.put(ocr.ContactId, ocr);
      }
    }
    return indexed;
  }

  private static Map<Id, AccountContactRelation> queryAcrsByContact(
    Set<Id> contactIds,
    Id accountId
  ) {
    Map<Id, AccountContactRelation> acrByContactId = new Map<Id, AccountContactRelation>();
    if (contactIds == null || contactIds.isEmpty() || accountId == null) {
      return acrByContactId;
    }
    for (AccountContactRelation acr : [
      SELECT Id, ContactId, AccountId, Roles, IsDirect
      FROM AccountContactRelation
      WHERE ContactId IN :contactIds AND AccountId = :accountId
      WITH USER_MODE
    ]) {
      if (!acrByContactId.containsKey(acr.ContactId)) {
        acrByContactId.put(acr.ContactId, acr);
      }
    }
    return acrByContactId;
  }

  // ─── Private helpers — DTO assembly ───────────────────────────────────────

  /**
   * @description Groups touches by Contact, builds one DTO per Contact with the
   *              joined OCR + ACR flags applied, and returns the result sorted
   *              by lastTouchAt DESC. Contacts dismissed by the running user
   *              are skipped when their MAX(Occurred_At) is at or before the
   *              dismissal timestamp — a newer touch makes them reappear.
   * @param touches Source touches (any Contact mix; grouped internally).
   * @param ocrByContactId Map of OCR by ContactId for the active Opportunity
   *                       scope; empty map on Account scope.
   * @param acrByContactId Map of ACR by ContactId for the active Account
   *                       scope; empty map when ACR is not relevant.
   * @param dismissalsByContact Map of MAX(Dismissed_At) by ContactId for the
   *                            running user in the active scope.
   * @return List of EngagementDTOs sorted by lastTouchAt DESC, nulls last.
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static List<EngagementDTO> assembleDTOs(
    List<Engagement_Touch__c> touches,
    Map<Id, OpportunityContactRole> ocrByContactId,
    Map<Id, AccountContactRelation> acrByContactId,
    Map<Id, DateTime> dismissalsByContact
  ) {
    // Four maps are the natural shape of the pipeline join — each comes from
    // its own hoisted SOQL and is consumed once. A DTO repack would add a
    // construction layer without simplifying the call site.
    Map<Id, List<Engagement_Touch__c>> touchesByContact = groupTouchesByContact(
      touches
    );

    List<EngagementDTO> dtos = new List<EngagementDTO>();
    for (Id contactId : touchesByContact.keySet()) {
      if (isDismissed(contactId, touchesByContact, dismissalsByContact)) {
        continue;
      }
      dtos.add(
        buildDtoForContact(
          contactId,
          touchesByContact.get(contactId),
          ocrByContactId.get(contactId),
          acrByContactId.get(contactId)
        )
      );
    }

    sortByLastTouchDesc(dtos);
    return dtos;
  }

  /**
   * @description Returns true when the contact has a dismissal whose timestamp
   *              is at or after the contact's most-recent touch. A null
   *              dismissal (no dismissal recorded) or a touch newer than the
   *              dismissal returns false.
   * @param contactId Contact under evaluation.
   * @param touchesByContact Grouped touches indexed by ContactId.
   * @param dismissalsByContact Map of MAX(Dismissed_At) by ContactId.
   * @return True when the contact is currently dismissed; false otherwise.
   */
  private static Boolean isDismissed(
    Id contactId,
    Map<Id, List<Engagement_Touch__c>> touchesByContact,
    Map<Id, DateTime> dismissalsByContact
  ) {
    if (dismissalsByContact == null || dismissalsByContact.isEmpty()) {
      return false;
    }
    DateTime dismissedAt = dismissalsByContact.get(contactId);
    if (dismissedAt == null) {
      return false;
    }
    DateTime lastTouchAt = computeMaxOccurredAt(
      touchesByContact.get(contactId)
    );
    return lastTouchAt == null || lastTouchAt <= dismissedAt;
  }

  private static Map<Id, List<Engagement_Touch__c>> groupTouchesByContact(
    List<Engagement_Touch__c> touches
  ) {
    Map<Id, List<Engagement_Touch__c>> grouped = new Map<Id, List<Engagement_Touch__c>>();
    for (Engagement_Touch__c t : touches) {
      if (t.Contact__c == null) {
        continue;
      }
      if (!grouped.containsKey(t.Contact__c)) {
        grouped.put(t.Contact__c, new List<Engagement_Touch__c>());
      }
      grouped.get(t.Contact__c).add(t);
    }
    return grouped;
  }

  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static EngagementDTO buildDtoForContact(
    Id contactId,
    List<Engagement_Touch__c> contactTouches,
    OpportunityContactRole ocr,
    AccountContactRelation acr
  ) {
    // Same rationale as `assembleDTOs` — pipeline-join inputs, consumed once.
    EngagementDTO dto = new EngagementDTO();
    dto.contactId = contactId;

    Engagement_Touch__c sample = contactTouches[0];
    dto.name = (sample.Contact__r != null) ? sample.Contact__r.Name : null;
    dto.title = (sample.Contact__r != null) ? sample.Contact__r.Title : null;
    dto.accountName = (sample.Contact__r != null &&
      sample.Contact__r.Account != null)
      ? sample.Contact__r.Account.Name
      : null;

    dto.onOcr = ocr != null;
    dto.ocrRole = (ocr != null) ? ocr.Role : null;

    dto.isAcr = acr != null;
    dto.acrRole = (acr != null) ? acr.Roles : null;
    // Q11 wave 2: consultant flag now reads from Contact.Is_Consultant__c (admin
    // flow populates it). The legacy ACR.IsDirect=false heuristic is retired —
    // the new field is the single source of truth for "this contact is a consultant".
    dto.isConsultant =
      sample.Contact__r != null &&
      sample.Contact__r.Is_Consultant__c == true;

    dto.topics = collectDistinctTopicNames(contactTouches);
    dto.touchCount = contactTouches.size();
    dto.lastTouchAt = computeMaxOccurredAt(contactTouches);
    dto.assets = buildAssetEngagements(contactTouches);

    return dto;
  }

  private static List<String> collectDistinctTopicNames(
    List<Engagement_Touch__c> touches
  ) {
    Set<String> uniqueNames = new Set<String>();
    for (Engagement_Touch__c t : touches) {
      if (t.Topic__r != null && String.isNotBlank(t.Topic__r.Name)) {
        uniqueNames.add(t.Topic__r.Name);
      }
    }
    List<String> ordered = new List<String>(uniqueNames);
    ordered.sort();
    return ordered;
  }

  private static DateTime computeMaxOccurredAt(
    List<Engagement_Touch__c> touches
  ) {
    DateTime max = null;
    for (Engagement_Touch__c t : touches) {
      if (t.Occurred_At__c == null) {
        continue;
      }
      if (max == null || t.Occurred_At__c > max) {
        max = t.Occurred_At__c;
      }
    }
    return max;
  }

  private static List<EngagementDTO.AssetEngagement> buildAssetEngagements(
    List<Engagement_Touch__c> touches
  ) {
    Map<String, EngagementDTO.AssetEngagement> byKey = new Map<String, EngagementDTO.AssetEngagement>();
    for (Engagement_Touch__c t : touches) {
      String key = assetGroupingKey(t);
      EngagementDTO.AssetEngagement asset = byKey.get(key);
      if (asset == null) {
        asset = new EngagementDTO.AssetEngagement();
        asset.assetName = t.Asset_Name__c;
        // Q8 wave 2: Source_Event_Type__c (raw API value) is mapped to a
        // friendly display label via Engagement_Picklist_Display__mdt. Falls
        // back to Touch_Type__c when no CMDT row covers the source value, so
        // existing rows render unchanged when no mapping is configured.
        asset.touchType = displayLabelFor(
          t.Source_Event_Type__c,
          t.Touch_Type__c
        );
        asset.count = 0;
        byKey.put(key, asset);
      }
      asset.count += 1;
      asset.firstAt = minDateTime(asset.firstAt, t.Occurred_At__c);
      asset.lastAt = maxDateTime(asset.lastAt, t.Occurred_At__c);
      if (
        asset.campaignName == null &&
        t.Campaign__r != null &&
        String.isNotBlank(t.Campaign__r.Name)
      ) {
        asset.campaignName = t.Campaign__r.Name;
      }
    }
    return new List<EngagementDTO.AssetEngagement>(byKey.values());
  }

  private static String assetGroupingKey(Engagement_Touch__c t) {
    String assetName = (t.Asset_Name__c == null) ? '' : t.Asset_Name__c;
    String touchType = (t.Touch_Type__c == null) ? '' : t.Touch_Type__c;
    return assetName + '||' + touchType;
  }

  /**
   * @description Returns the user-facing label for a raw
   *              `Source_Event_Type__c` value by consulting
   *              `Engagement_Picklist_Display__mdt`. Falls back to
   *              `fallback` (typically `Touch_Type__c`) when no active CMDT
   *              row matches or when `sourceEventType` is blank. The CMDT
   *              map is loaded once per transaction.
   * @param sourceEventType Raw API value from the touch's Source_Event_Type__c.
   * @param fallback Display value to return if no mapping exists.
   * @return Display label from CMDT or the fallback when no row matches.
   */
  @TestVisible
  private static String displayLabelFor(
    String sourceEventType,
    String fallback
  ) {
    if (String.isBlank(sourceEventType)) {
      return fallback;
    }
    Map<String, String> displayMap = loadSourceEventTypeDisplayMap();
    String label = displayMap.get(sourceEventType);
    return String.isNotBlank(label) ? label : fallback;
  }

  /**
   * @description Lazy-loads + caches the `API_Value__c → Display_Label__c`
   *              map for the Source_Event_Type__c picklist. Reads
   *              `Engagement_Picklist_Display__mdt.getAll().values()` (zero
   *              SOQL — CMDT is platform-cached per §1.2.1), filters in
   *              memory to `Active__c = TRUE` and the matching
   *              `Field_API_Name__c`. Subsequent calls in the same
   *              transaction hit the cached map without re-walking the
   *              metadata collection.
   *
   *              Schema describe guard remains so the call is safe in orgs
   *              where the CMDT fields haven't been deployed yet (missing
   *              field → empty map). USER_MODE is not relevant on CMDT —
   *              the platform bypasses CRUD/FLS for `__mdt` types by rule.
   * @return Map of `API_Value__c → Display_Label__c` for the active rows of
   *         the `Source_Event_Type__c` field. Empty when the CMDT fields are
   *         missing or FLS-blocked.
   */
  @SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
  private static Map<String, String> loadSourceEventTypeDisplayMap() {
    if (sourceEventTypeDisplayMap != null) {
      return sourceEventTypeDisplayMap;
    }
    sourceEventTypeDisplayMap = new Map<String, String>();

    // §12.3.2 waiver — schema-describe-guard pattern; required to safely fail
    // open when the CMDT fields aren't deployed yet. Magnus-signed canonical
    // suppression scope.
    Map<String, Schema.SObjectField> cmdtFields = Engagement_Picklist_Display__mdt.SObjectType.getDescribe()
      .fields.getMap();
    String[] required = new List<String>{
      'api_value__c',
      'display_label__c',
      'active__c',
      'field_api_name__c'
    };
    for (String f : required) {
      if (!cmdtFields.containsKey(f)) {
        return sourceEventTypeDisplayMap;
      }
      if (!cmdtFields.get(f).getDescribe().isAccessible()) {
        return sourceEventTypeDisplayMap;
      }
    }

    // §1.2.1 — Type.getAll() over CMDT SOQL: zero governor cost, platform-cached.
    for (
      Engagement_Picklist_Display__mdt row : Engagement_Picklist_Display__mdt.getAll()
        .values()
    ) {
      if (row.Active__c != true) {
        continue;
      }
      if (row.Field_API_Name__c != SOURCE_EVENT_TYPE_KEY) {
        continue;
      }
      if (String.isNotBlank(row.API_Value__c)) {
        sourceEventTypeDisplayMap.put(row.API_Value__c, row.Display_Label__c);
      }
    }
    return sourceEventTypeDisplayMap;
  }

  private static DateTime minDateTime(DateTime current, DateTime candidate) {
    if (candidate == null) {
      return current;
    }
    if (current == null || candidate < current) {
      return candidate;
    }
    return current;
  }

  private static DateTime maxDateTime(DateTime current, DateTime candidate) {
    if (candidate == null) {
      return current;
    }
    if (current == null || candidate > current) {
      return candidate;
    }
    return current;
  }

  /**
   * @description In-place sort of DTOs by lastTouchAt DESC. Nulls sort last.
   *              Implemented as an insertion-style swap loop because Apex's
   *              `List.sort()` requires Comparable on the element type and
   *              DTOs are returned to Aura/LWC as serialized JSON.
   * @param dtos The DTO list to sort; mutated in place.
   */
  private static void sortByLastTouchDesc(List<EngagementDTO> dtos) {
    Integer size = dtos.size();
    for (Integer i = 1; i < size; i++) {
      EngagementDTO current = dtos[i];
      Integer j = i - 1;
      while (j >= 0 && compareDescByLastTouch(dtos[j], current) > 0) {
        dtos[j + 1] = dtos[j];
        j--;
      }
      dtos[j + 1] = current;
    }
  }

  private static Integer compareDescByLastTouch(
    EngagementDTO a,
    EngagementDTO b
  ) {
    if (a.lastTouchAt == b.lastTouchAt) {
      return 0;
    }
    if (a.lastTouchAt == null) {
      return 1;
    }
    if (b.lastTouchAt == null) {
      return -1;
    }
    return (a.lastTouchAt > b.lastTouchAt) ? -1 : 1;
  }

  // ─── Private helpers — addToOcrSafe ───────────────────────────────────────

  private static void validateAddToOcrInput(
    Id contactId,
    Id opportunityId,
    String role
  ) {
    if (contactId == null) {
      throw new EngagementException('contactId required');
    }
    if (opportunityId == null) {
      throw new EngagementException('opportunityId required');
    }
    if (String.isBlank(role)) {
      throw new EngagementException('role required');
    }
  }

  private static AddToOcrResult buildAlreadyExistsResult(
    OpportunityContactRole existing
  ) {
    AddToOcrResult result = new AddToOcrResult();
    result.success = false;
    result.alreadyExists = true;
    result.ocrId = existing.Id;
    result.addedByUserId = existing.CreatedById;
    result.addedByUserName = (existing.CreatedBy != null)
      ? existing.CreatedBy.Name
      : null;
    result.addedAt = existing.CreatedDate;
    result.role = existing.Role;
    result.isPrimary = existing.IsPrimary;
    return result;
  }

  private static AddToOcrResult buildSuccessResult(
    Id ocrId,
    String role,
    Boolean isPrimary
  ) {
    AddToOcrResult result = new AddToOcrResult();
    result.success = true;
    result.alreadyExists = false;
    result.ocrId = ocrId;
    result.role = role;
    result.isPrimary = isPrimary;
    return result;
  }
}
