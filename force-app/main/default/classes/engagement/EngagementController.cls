/**
 * @description Aura/LWC-facing controller. Thin wrappers around
 *              `IEngagementService`. Every exception is logged via Logger and
 *              re-thrown as `AuraHandledException` with a sanitized message so
 *              the LWC layer never receives raw stack traces.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class EngagementController {
  private static final String CLASS_NAME = 'EngagementController';
  private static IEngagementService service = new EngagementServiceImpl();

  /**
   * @description Returns engagement DTOs for the Opportunity scope.
   * @param opportunityId Opportunity Id.
   * @return List of EngagementDTOs.
   */
  @AuraEnabled(cacheable=true)
  public static List<EngagementDTO> getForOpportunity(Id opportunityId) {
    try {
      return service.getForOpportunity(opportunityId);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'getForOpportunity');
      throw new AuraHandledException(
        'Unable to load engagement data for this opportunity. Error ID: ' +
        System.Request.getCurrent().getRequestId()
      );
    }
  }

  /**
   * @description Returns engagement DTOs for the Account scope.
   * @param accountId Account Id.
   * @return List of EngagementDTOs.
   */
  @AuraEnabled(cacheable=true)
  public static List<EngagementDTO> getForAccount(Id accountId) {
    try {
      return service.getForAccount(accountId);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'getForAccount');
      throw new AuraHandledException(
        'Unable to load engagement data for this account. Error ID: ' +
        System.Request.getCurrent().getRequestId()
      );
    }
  }

  /**
   * @description Race-protected OCR insert; delegates to the service.
   * @param contactId Contact to add.
   * @param opportunityId Opportunity to add the Contact to.
   * @param role OpportunityContactRole.Role.
   * @param isPrimary Whether to mark the new OCR as Primary.
   * @return AddToOcrResult capturing success or race-detection state.
   */
  @SuppressWarnings('PMD.ExcessiveParameterList')
  @AuraEnabled
  public static AddToOcrResult addToOcrSafe(
    Id contactId,
    Id opportunityId,
    String role,
    Boolean isPrimary
  ) {
    // 4-param signature is the LWC wire contract. Repacking into a DTO costs
    // a JSON round-trip in jest tests and the AddToDealTeamModal payload for
    // zero readability gain at the call site.
    try {
      return service.addToOcrSafe(contactId, opportunityId, role, isPrimary);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'addToOcrSafe');
      throw new AuraHandledException(
        'Unable to add the contact to the deal team. Error ID: ' +
        System.Request.getCurrent().getRequestId()
      );
    }
  }

  /**
   * @description Dismisses an Opportunity_Engagement_Signal__c record. Phase 1
   *              stub — signals come online in Phase 3.
   * @param signalId Signal Id.
   * @param reason Free-form dismissal reason.
   */
  @AuraEnabled
  public static void dismissSignal(Id signalId, String reason) {
    try {
      service.dismissSignal(signalId, reason);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'dismissSignal');
      throw new AuraHandledException(
        'Unable to dismiss the signal. Error ID: ' +
        System.Request.getCurrent().getRequestId()
      );
    }
  }

  /**
   * @description Records a per-user dismissal so the given Contact disappears
   *              from this user's engagement panel for the given scope. The
   *              LWC layer calls this when the user clicks the × on a
   *              contact row. Exactly one of `opportunityId` / `accountId`
   *              must be non-null.
   * @param contactId Contact the user is dismissing.
   * @param opportunityId Opportunity scope (null when dismissing on Account).
   * @param accountId Account scope (null when dismissing on Opportunity).
   */
  @AuraEnabled
  public static void dismissContact(
    Id contactId,
    Id opportunityId,
    Id accountId
  ) {
    try {
      service.dismissContact(contactId, opportunityId, accountId);
    } catch (Exception e) {
      Logger.logException(e, CLASS_NAME, 'dismissContact');
      throw new AuraHandledException(
        'Unable to dismiss this contact. Try again. Error ID: ' +
        System.Request.getCurrent().getRequestId()
      );
    }
  }

  /**
   * @description Test-only setter for injecting a mock service.
   * @param mockService IEngagementService stub.
   */
  @TestVisible
  private static void setServiceForTest(IEngagementService mockService) {
    service = mockService;
  }
}
