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
 * | 2026-05-12 | CSI-7162 | David Wood | Wire Opportunity to Jira-push integration via Platform Events          |
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

  /**
   * @description After-insert entry point. Every newly-created Opportunity
   *              gets pushed - the initial sync establishes the Jira link,
   *              so no filter is applied.
   * @param newList Trigger.new from OpportunityTriggerHandler.afterInsert.
   */
  public static void handleJiraPushInsert(List<Opportunity> newList) {
    if (newList == null || newList.isEmpty()) {
      return;
    }
    JiraPushService.publishInserts(newList);
  }

  /**
   * @description After-update entry point. Filters newList down to records
   *              where at least one QUALIFYING_FIELDS field changed, then
   *              delegates the publish.
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

    // ─── Step 1: filter newList to records with a qualifying-field change ────
    // Anything else (Description edits, touch-only updates, etc.) is noise
    // we don't want syncing to Jira.
    List<Opportunity> changed = new List<Opportunity>();
    for (Opportunity o : newList) {
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

    // ─── Step 2: hand the filtered records to the generic publisher ──────────
    if (!changed.isEmpty()) {
      JiraPushService.publishUpdates(changed);
    }
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
