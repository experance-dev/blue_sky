/**
 * @description Service layer for Opportunity. Owns the domain-level
 *              decisions about Opportunity behavior - anything that
 *              doesn't belong in the trigger handler or the selector
 *              lives here. The trigger handler delegates each phase
 *              to a method on this class.
 *
 * @group Opportunity
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                                                       |
 * |------------|----------|------------|-----------------------------------------------------------------------------------|
 * | 2026-05-12 | CSI-7162 | David Wood | Wire Opportunity to Jira-push integration via Platform Events; add               |
 * |            |          |            | PE_Provider_Opportunity record-type precondition (filter the broken-and-unwired  |
 * |            |          |            | dwood_z OpportunityJiraSyncService was meant to enforce, lifted into the domain  |
 * |            |          |            | layer). Cached RT lookup, no SOQL.                                                |
 */
public with sharing class OpportunityService {
  private static final String ALREADY_CLONED = 'Already_Cloned__c';
  private static final String NUMBER_OF_CLONES = 'Number_of_Clones__c';
  private static final Integer PHASE_INCREMENT = 1;

  // Opportunity fields whose change is worth a Jira sync. Curated for what
  // downstream Jira issue tracking actually mirrors (stage, value, owner,
  // timing). Each entry incurs one platform event per qualifying record;
  // add/remove deliberately. Schema.SObjectField tokens (not String names)
  // so a typo or rename is caught at compile time.
  @TestVisible
  private static final Set<Schema.SObjectField> JIRA_QUALIFYING_FIELDS = new Set<Schema.SObjectField>{
    Opportunity.StageName,
    Opportunity.Amount,
    Opportunity.CloseDate,
    Opportunity.AccountId,
    Opportunity.OwnerId,
    Opportunity.Probability
  };

  // Only opportunities of this developer-named RecordType push to Jira.
  // Preserves the business rule the (broken, unwired) dwood_z
  // OpportunityJiraSyncService was meant to enforce: Jira sync is opt-in by
  // record type, not org-wide. If MI wants a wider net later, add more
  // developer names to JIRA_PUSH_RT_DEVELOPER_NAMES — or surface this set
  // to CMDT (Jira_Push_Object__mdt already gates by SObject; a per-RT
  // sub-gate would be the next iteration).
  @TestVisible
  private static final Set<String> JIRA_PUSH_RT_DEVELOPER_NAMES = new Set<String>{
    'PE_Provider_Opportunity'
  };

  // Per-transaction cache so the RT->Id lookup is one Schema describe call,
  // not one per record. Schema describes are themselves cheap but the cache
  // matters in 200-record batches.
  @TestVisible
  private static Set<Id> jiraPushRecordTypeIdsCache;

  /**
   * @description After-insert entry point. Filters newList to records whose
   *              RecordType is in JIRA_PUSH_RT_DEVELOPER_NAMES, then publishes
   *              every survivor. Insert path doesn't field-filter — first
   *              sync establishes the Jira link.
   * @param newList Trigger.new from OpportunityTriggerHandler.afterInsert.
   */
  public static void handleJiraPushInsert(List<Opportunity> newList) {
    if (newList == null || newList.isEmpty()) {
      return;
    }
    List<Opportunity> filtered = filterToJiraPushRecordTypes(newList);
    if (filtered.isEmpty()) {
      return;
    }
    JiraPushService.publishInserts(filtered);
  }

  /**
   * @description After-update entry point. Two-stage filter:
   *              (1) drop records whose RecordType is not in
   *                  JIRA_PUSH_RT_DEVELOPER_NAMES,
   *              (2) drop records whose qualifying fields didn't change.
   *              Survivors go to the generic publisher.
   * @param newList Trigger.new from OpportunityTriggerHandler.afterUpdate.
   * @param oldMap  Trigger.oldMap from the same trigger.
   */
  public static void handleJiraPushUpdate(
    List<Opportunity> newList,
    Map<Id, Opportunity> oldMap
  ) {
    if (newList == null || newList.isEmpty() || oldMap == null) {
      return;
    }

    // ─── Step 1: filter to opted-in record types ─────────────────────────────
    // Lifts the gate the broken dwood_z OpportunityJiraSyncService was
    // supposed to enforce. RT filter runs first so the (more expensive)
    // field-change check only runs on records that could possibly publish.
    List<Opportunity> rtFiltered = filterToJiraPushRecordTypes(newList);
    if (rtFiltered.isEmpty()) {
      return;
    }

    // ─── Step 2: filter rtFiltered to records with a qualifying-field change ─
    // Anything else (Description edits, touch-only updates, etc.) is noise
    // we don't want syncing to Jira.
    List<Opportunity> changed = new List<Opportunity>();
    for (Opportunity o : rtFiltered) {
      // oldMap can be missing the record in undelete / programmatic-update
      // edge cases. Skip rather than throw - leaving the record un-synced
      // is safer than aborting the whole batch on one anomaly.
      Opportunity old = oldMap.get(o.Id);
      if (old == null) {
        continue;
      }
      if (anyQualifyingFieldChanged(o, old, JIRA_QUALIFYING_FIELDS)) {
        changed.add(o);
      }
    }

    // ─── Step 3: hand the filtered records to the generic publisher ──────────
    if (!changed.isEmpty()) {
      JiraPushService.publishUpdates(changed);
    }
  }

  /**
   * @description Returns the input list filtered to records whose
   *              RecordTypeId resolves to a developer name in
   *              JIRA_PUSH_RT_DEVELOPER_NAMES. Records with a null
   *              RecordTypeId (no record-type assigned, or an org where
   *              Opportunity has no record types) are dropped — the
   *              business rule is opt-in, so unrecognized RTs don't push.
   * @param input Records to filter.
   * @return The subset of `input` whose RecordType is opted into Jira push.
   */
  @TestVisible
  private static List<Opportunity> filterToJiraPushRecordTypes(
    List<Opportunity> input
  ) {
    Set<Id> jiraPushRtIds = getJiraPushRecordTypeIds();
    if (jiraPushRtIds.isEmpty()) {
      // Org has no matching RecordType deployed. Refuse to publish anything
      // rather than fail open — the dwood_z parity rule is "PE_Provider_-
      // Opportunity only" and an absent RT means we can't honor that.
      return new List<Opportunity>();
    }
    List<Opportunity> out = new List<Opportunity>();
    for (Opportunity o : input) {
      if (o.RecordTypeId != null && jiraPushRtIds.contains(o.RecordTypeId)) {
        out.add(o);
      }
    }
    return out;
  }

  /**
   * @description Cached lookup of RecordTypeIds for every developer name in
   *              JIRA_PUSH_RT_DEVELOPER_NAMES. Computed once per transaction.
   *              Uses Schema.SObjectType.Opportunity.getRecordTypeInfosBy-
   *              DeveloperName() — describes only, no SOQL.
   * @return Set of RecordTypeIds opted into Jira push (possibly empty).
   */
  @TestVisible
  private static Set<Id> getJiraPushRecordTypeIds() {
    if (jiraPushRecordTypeIdsCache != null) {
      return jiraPushRecordTypeIdsCache;
    }
    Map<String, Schema.RecordTypeInfo> rtByDevName = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();
    Set<Id> ids = new Set<Id>();
    for (String devName : JIRA_PUSH_RT_DEVELOPER_NAMES) {
      Schema.RecordTypeInfo info = rtByDevName.get(devName);
      if (info != null) {
        ids.add(info.getRecordTypeId());
      }
    }
    jiraPushRecordTypeIdsCache = ids;
    return ids;
  }

  /**
   * @description Returns true if any field in `fields` differs between the
   *              new and old record. Pure function over a record pair and a
   *              field-token set - reusable by any domain service that needs
   *              the same change-detection semantics.
   * @param newRec The post-update record.
   * @param oldRec The pre-update record (from Trigger.oldMap).
   * @param fields Schema.SObjectField tokens to compare. Caller owns this set.
   */
  @TestVisible
  private static Boolean anyQualifyingFieldChanged(
    Opportunity newRec,
    Opportunity oldRec,
    Set<Schema.SObjectField> fields
  ) {
    // Object != Object does value equality for boxed primitives (Date,
    // Decimal, Double, Id, String, Boolean), and null != null is false -
    // so null-to-value and value-to-null both return true, no special
    // casing required for any field in JIRA_QUALIFYING_FIELDS.
    for (Schema.SObjectField field : fields) {
      if (newRec.get(field) != oldRec.get(field)) {
        return true;
      }
    }
    return false;
  }

  // ─── Pre-existing dwood_z org methods (preserved for backward compatibility) ─
  // These methods are called by ScheduleEnrollmentStatusProcess and other
  // dwood_z org classes that pre-date the CSI-7162 work. Removing them would
  // break a hundred dependent classes at compile time. Out-of-scope for the
  // current ticket; preserved verbatim from the org until they get their own
  // rewrite ticket.

  public static void processEnrollmentRequests() {
    Map<String, Object> optyBind = new Map<String, Object>{
      'optyStatus' => new List<String>{ 'Closed/Lost', 'Closed/Won' },
      'recordType' => 'Guided_Enrollment'
    };
    QueryBuilder optyQueryBuilder = new QueryBuilder()
      .setSObjectType(Opportunity.getSObjectType())
      .setFields(
        new List<String>{ 'Id', 'PE_Guided_Enrollment_Code__c', 'StageName' }
      )
      .setCondition(
        'StageName Not In :optyStatus AND RecordType.DeveloperName = :recordType AND PE_Guided_Enrollment_Code__c <> null'
      )
      .setBindVariables(optyBind);
    Map<Id, Opportunity> opportunities = new OpportunitySelector(
        optyQueryBuilder
      )
      .getOpportunityRecords();
    GetEnrollmentStatus submitJob = new GetEnrollmentStatus(opportunities);
    Id jobID = System.enqueueJob(submitJob);
  }

  public static List<Opportunity> cloneOpportunityWithQuotes(
    Opportunity opportunity,
    Integer numberOfClones
  ) {
    CloneOpportunitiesImpl opportunityCloner = new CloneOpportunitiesImpl();
    OpportunityCloneSettings cloneSettings = resolveParentAndPhaseDetails(
      opportunity,
      numberOfClones
    );

    Map<Id, Opportunity> clonedOpportunitiesById = opportunityCloner.createOpportunityClones(
      cloneSettings.parentOpportunity,
      numberOfClones,
      cloneSettings.nextPhaseNumber
    );

    List<Quote> opportunityQuotes = getOpportunityQuotes(
      cloneSettings.parentOpportunity.Id
    );

    List<Quote> clonedQuotes = opportunityCloner.cloneQuotesForTargetOpportunities(
      opportunityQuotes,
      clonedOpportunitiesById
    );

    Map<String, Object> valuesByFieldName = new Map<String, Object>{
      ALREADY_CLONED => true,
      NUMBER_OF_CLONES => cloneSettings.cumulativeCloneCount
    };
    opportunityCloner.updateOpportunity(
      cloneSettings.parentOpportunity.Id,
      valuesByFieldName
    );

    return clonedOpportunitiesById.values();
  }

  public static List<Quote> getOpportunityQuotes(Id opportunityId) {
    return new QuoteService().getQuotesByOpportunityId(opportunityId);
  }

  private static OpportunityCloneSettings resolveParentAndPhaseDetails(
    Opportunity opportunity,
    Integer numberOfClones
  ) {
    Integer previousCloneCount;
    Opportunity parentOpportunity;

    if (isCreatedFromCloning(opportunity)) {
      parentOpportunity = getParentOpportunity(opportunity);
      previousCloneCount = ((Decimal) parentOpportunity.Number_of_Clones__c)
        .intValue() ?? 0;
    } else {
      parentOpportunity = opportunity;
      previousCloneCount = Integer.valueOf(opportunity.Number_Of_Clones__c) ??
        0;
    }

    Integer nextPhaseNumber = previousCloneCount + PHASE_INCREMENT;
    Integer cumulativeCloneCount = previousCloneCount + numberOfClones;

    return new OpportunityCloneSettings(
      parentOpportunity,
      nextPhaseNumber,
      cumulativeCloneCount
    );
  }

  private static Boolean isCreatedFromCloning(Opportunity opportunity) {
    return String.isNotBlank(opportunity.Cloned_From__c);
  }

  private static Opportunity getParentOpportunity(Opportunity opportunity) {
    Map<String, Object> bindMap = new Map<String, Object>{
      'parentId' => opportunity.Cloned_From__c
    };
    QueryBuilder queryBuilder = new QueryBuilder()
      .setSObjectType(Opportunity.getSObjectType())
      .setFields(SchemaUtils.getAllFields(Opportunity.getSObjectType()))
      .setCondition('Id =: parentId')
      .setBindVariables(bindMap)
      .setAccessLevel(System.AccessLevel.SYSTEM_MODE);
    return new OpportunitySelector(queryBuilder)
      .getOpportunityRecords()
      .values()[0];
  }

  private class OpportunityCloneSettings {
    Opportunity parentOpportunity;
    Integer nextPhaseNumber;
    Integer cumulativeCloneCount;

    OpportunityCloneSettings(
      Opportunity parentOpportunity,
      Integer nextPhaseNumber,
      Integer cumulativeCloneCount
    ) {
      this.parentOpportunity = parentOpportunity;
      this.nextPhaseNumber = nextPhaseNumber;
      this.cumulativeCloneCount = cumulativeCloneCount;
    }
  }
}
