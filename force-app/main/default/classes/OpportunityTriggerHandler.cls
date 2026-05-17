/*
*********************************************************
Apex Trigger Name  : OpportunityTriggerHandler
Created Date       : Jan 27, 2025
@description       : This class is a trigger handler for opportunity object and extends TriggerHandler class
@author            : Baba Shaik
Modification Log:
Ver   Date         		Author                        Modification
1.0   Jan 27, 2025   Baba Shaik                      Initial Version
2.0   May 07, 2026   David Wood                      Added Jira sync integration via Platform Events
3.0   May 13, 2026   David Wood                      CSI-7162: wire to OpportunityService.handleJiraPushX
4.0   May 14, 2026   David Wood                      Restored exception observability: Logger.logException + txn ID in user-facing message
*********************************************************
*/

public with sharing class OpportunityTriggerHandler extends TriggerHandler {
  Map<Id, Schema.RecordTypeInfo> recordTypeInfosById = Schema.SObjectType.Opportunity.getRecordTypeInfosById();
  Map<String, Type> typeByImplementation = new Map<String, Type>{
    'PE_Provider_Opportunity' => PEProviderOpportunityImpl.class
  };

  /**
   * @description Entry point method called by the TriggerHandler framework. Routes trigger execution
   *              to the appropriate handler method based on trigger operation type. Respects
   *              ProcessAutomationSwitches to allow selective enabling/disabling of trigger logic.
   *              This method is automatically invoked for all Opportunity trigger contexts.
   *
   * @example
   * // Called automatically by the trigger framework:
   * // trigger OpportunityTrigger on Opportunity (before insert, before update, after insert, after update) {
   * //     new OpportunityTriggerHandler().run();
   * // }
   */
  public void initialise() {
    if (
      !ProcessAutomationSwitches.ALL_PROCESSES_DISABLED &&
      !ProcessAutomationSwitches.opportunityProcessDisabled
    ) {
      switch on Trigger.operationType {
        when BEFORE_INSERT {
          handleBeforeInsert();
        }
        when BEFORE_UPDATE {
          handleBeforeUpdate();
        }
        when AFTER_INSERT {
          handleAfterInsert();
        }
        when AFTER_UPDATE {
          handleAfterUpdate();
        }
      }
    }
  }

  /**
   * @description Handles before update trigger logic for Opportunities. Organizes Opportunities by
   *              record type and delegates processing to record-type-specific implementations.
   *              Currently supports PE_Provider_Opportunity record type with validation and
   *              business logic enforcement before DML commits.
   *
   * @throws OpportunityTriggerException If any validation or business logic fails during processing
   *
   * @example
   * // Automatically called when Opportunities are updated:
   * // - Validates field requirements per record type
   * // - Enforces business rules before database commit
   * // - Prevents invalid data from being saved
   */
  private void handleBeforeUpdate() {
    try {
      Map<Id, Opportunity> oldOpportunityById = new Map<Id, Opportunity>();
      Map<String, Map<Id, Opportunity>> opportunityMapByRecordType = splitOpportunitiesByRecordType(
        (List<Opportunity>) Trigger.new
      );
      for (String recordType : opportunityMapByRecordType.keySet()) {
        for (
          Id OpportunityId : opportunityMapByRecordType.get(recordType).keySet()
        ) {
          oldOpportunityById.put(
            OpportunityId,
            (Opportunity) Trigger.oldMap.get(OpportunityId)
          );
        }
        if (recordType.equalsIgnoreCase('PE_Provider_Opportunity')) {
          IPEProviderOpportunity opportunityProviderImpl = (IPEProviderOpportunity) typeByImplementation.get(
              recordType
            )
            .newInstance();
          opportunityProviderImpl.onBeforeUpdate(
            oldOpportunityById,
            opportunityMapByRecordType.get(recordType)
          );
        }
      }
    } catch (Exception e) {
      Logger.logException(e, 'OpportunityTriggerHandler', 'handleBeforeUpdate');
      throw new OpportunityTriggerException(
        'Opportunity Update failed. Contact your Administrator and let them know: ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }
  }

  /**
   * @description Handles before insert trigger logic for Opportunities. Organizes new Opportunities
   *              by record type and delegates processing to record-type-specific implementations.
   *              Currently supports PE_Provider_Opportunity record type with field defaulting,
   *              validation, and business logic enforcement before DML commits.
   *
   * @throws OpportunityTriggerException If any validation or business logic fails during processing
   *
   * @example
   * // Automatically called when new Opportunities are created:
   * // - Sets default field values per record type
   * // - Validates required fields and business rules
   * // - Prepares records for database insertion
   */
  private void handleBeforeInsert() {
    try {
      Map<String, List<Opportunity>> opportunityByRecordType = new Map<String, List<Opportunity>>();
      for (Opportunity opportunity : (List<Opportunity>) Trigger.new) {
        String recordType = recordTypeInfosById.get(opportunity.RecordTypeId)
          .getDeveloperName();
        if (opportunityByRecordType.containsKey(recordType)) {
          opportunityByRecordType.get(recordType).add(opportunity);
        } else {
          opportunityByRecordType.put(
            recordType,
            new List<opportunity>{ opportunity }
          );
        }
      }
      for (String recordType : opportunityByRecordType.keySet()) {
        if (recordType.equalsIgnoreCase('PE_Provider_Opportunity')) {
          IPEProviderOpportunity opportunityProviderImpl = (IPEProviderOpportunity) typeByImplementation.get(
              recordType
            )
            .newInstance();
          opportunityProviderImpl.onBeforeInsert(
            opportunityByRecordType.get(recordType)
          );
        }
      }
    } catch (Exception e) {
      Logger.logException(e, 'OpportunityTriggerHandler', 'handleBeforeInsert');
      throw new OpportunityTriggerException(
        'Opportunity Insert failed. Contact your Administrator and let them know: ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }
  }

  /**
   * @description Handles after insert trigger logic for Opportunities. Organizes newly inserted
   *              Opportunities by record type, delegates processing to record-type-specific
   *              implementations, and routes qualifying records to the CSI-7162 Jira push pipeline
   *              via OpportunityService. This method processes logic that requires committed
   *              record IDs and performs non-blocking operations.
   *
   * @throws OpportunityTriggerException If any post-insert processing fails
   *
   * @example
   * // Automatically called after new Opportunities are inserted:
   * // - Creates related records (Tasks, Events, etc.)
   * // - Routes qualifying inserts to JiraPushService via OpportunityService
   * // - Performs operations requiring committed record IDs
   */
  private void handleAfterInsert() {
    try {
      Map<String, Map<Id, Opportunity>> opportunityMapByRecordType = splitOpportunitiesByRecordType(
        (List<Opportunity>) Trigger.new
      );
      for (String recordType : opportunityMapByRecordType.keySet()) {
        if (recordType.equalsIgnoreCase('PE_Provider_Opportunity')) {
          IPEProviderOpportunity ofpOpportunities = (IPEProviderOpportunity) typeByImplementation.get(
              recordType
            )
            .newInstance();
          ofpOpportunities.onAfterInsert(
            opportunityMapByRecordType.get(recordType)
          );
        }
      }

      // CSI-7162: route qualifying Opportunity inserts to JiraPushService
      OpportunityService.handleJiraPushInsert((List<Opportunity>) Trigger.new);
    } catch (Exception e) {
      Logger.logException(e, 'OpportunityTriggerHandler', 'handleAfterInsert');
      throw new OpportunityTriggerException(
        'Opportunity Insert failed. Contact your Administrator and let them know: ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }
  }

  /**
   * @description Handles after update trigger logic for Opportunities. Organizes updated
   *              Opportunities by record type, delegates processing to record-type-specific
   *              implementations, and routes qualifying records to the CSI-7162 Jira push pipeline
   *              via OpportunityService when relevant field changes are detected. This method
   *              processes logic that requires committed record changes and performs non-blocking
   *              operations.
   *
   * @throws OpportunityTriggerException If any post-update processing fails
   *
   * @example
   * // Automatically called after Opportunities are updated:
   * // - Updates related records based on field changes
   * // - Routes qualifying updates to JiraPushService via OpportunityService
   * // - Performs operations requiring access to old and new field values
   */
  private void handleAfterUpdate() {
    try {
      Map<Id, Opportunity> oldOpportunitiesById = new Map<Id, Opportunity>();
      Map<String, Map<Id, Opportunity>> opportunitiesMapByRecordType = splitOpportunitiesByRecordType(
        (List<Opportunity>) Trigger.new
      );
      for (String recordType : opportunitiesMapByRecordType.keySet()) {
        if (recordType == 'PE_Provider_Opportunity') {
          for (
            Id opportunityId : opportunitiesMapByRecordType.get(recordType)
              .keySet()
          ) {
            oldOpportunitiesById.put(
              opportunityId,
              (Opportunity) Trigger.oldMap.get(opportunityId)
            );
          }
          IPEProviderOpportunity ofpOpportunities = (IPEProviderOpportunity) typeByImplementation.get(
              recordType
            )
            .newInstance();
          ofpOpportunities.onAfterUpdate(
            oldOpportunitiesById,
            opportunitiesMapByRecordType.get(recordType)
          );
        }
      }

      // CSI-7162: route qualifying Opportunity updates to JiraPushService
      OpportunityService.handleJiraPushUpdate(
        (List<Opportunity>) Trigger.new,
        (Map<Id, Opportunity>) Trigger.oldMap
      );
    } catch (Exception e) {
      Logger.logException(e, 'OpportunityTriggerHandler', 'handleAfterUpdate');
      throw new OpportunityTriggerException(
        'Opportunity Update failed. Contact your Administrator and let them know: ' +
          e.getTypeName() +
          ' [txn:' +
          System.Request.getCurrent().getRequestId() +
          ']'
      );
    }
  }

  /**
   * @description Organizes a list of Opportunities into a map structure grouped by record type
   *              developer name. This utility method enables record-type-specific processing by
   *              creating separate collections for each record type, allowing the trigger handler
   *              to route records to their appropriate implementation classes.
   *
   * @param Opportunities List of Opportunity records to organize by record type
   *
   * @return Map<String, Map<Id, Opportunity>> A two-level map where:
   *         - Outer key: Record type developer name (e.g., 'PE_Provider_Opportunity')
   *         - Inner map: Opportunity records indexed by their Salesforce IDs
   *
   * @example
   * List<Opportunity> opps = Trigger.new;
   * Map<String, Map<Id, Opportunity>> oppsByType = splitOpportunitiesByRecordType(opps);
   *
   * // Access PE Provider Opportunities:
   * Map<Id, Opportunity> peOpps = oppsByType.get('PE_Provider_Opportunity');
   * if (peOpps != null) {
   *     // Process PE Provider-specific logic
   * }
   */
  private Map<String, Map<Id, Opportunity>> splitOpportunitiesByRecordType(
    List<Opportunity> Opportunities
  ) {
    Map<String, Map<Id, Opportunity>> OpportunitiesMapByRecordType = new Map<String, Map<Id, Opportunity>>();
    for (Opportunity Opportunity : Opportunities) {
      String recordType = recordTypeInfosById.get(Opportunity.RecordTypeId)
        .getDeveloperName();
      if (OpportunitiesMapByRecordType.containsKey(recordType)) {
        OpportunitiesMapByRecordType.get(recordType)
          .put(Opportunity.Id, Opportunity);
      } else {
        OpportunitiesMapByRecordType.put(
          recordType,
          new Map<Id, Opportunity>{ Opportunity.Id => Opportunity }
        );
      }
    }
    return OpportunitiesMapByRecordType;
  }

  /**
   * @description Custom exception class for Opportunity trigger processing failures. Used to wrap
   *              and communicate trigger execution errors to users with user-friendly messages
   *              while preserving the technical exception details for administrators. This provides
   *              a consistent error handling pattern across all Opportunity trigger operations.
   *
   * @example
   * try {
   *     // Trigger processing logic
   * } catch (Exception e) {
   *     throw new OpportunityTriggerException(
   *         'Opportunity Update failed. Contact your Administrator'
   *     );
   * }
   */
  public class OpportunityTriggerException extends Exception {
  }
}
