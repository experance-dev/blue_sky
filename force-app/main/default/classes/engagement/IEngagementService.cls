/**
 * @description Service contract for the Engagement Attribution feature.
 *              `EngagementController` depends on this interface (not the
 *              concrete implementation) so tests can inject mock behaviour
 *              via `EngagementController.setServiceForTest`.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public interface IEngagementService {
  /**
   * @description Returns one DTO per Contact engaged on the Opportunity's
   *              Account, scoped to the Opportunity's Touch_Topic context and
   *              joined with OCR + AccountContactRelation flags.
   * @param opportunityId Opportunity providing Account + Topic scope.
   * @return List of EngagementDTOs ordered by lastTouchAt DESC.
   */
  List<EngagementDTO> getForOpportunity(Id opportunityId);

  /**
   * @description Returns one DTO per Contact engaged on the Account, with no
   *              Opportunity / OCR context (`onOcr` is always false in this
   *              scope).
   * @param accountId Account scope for the engagement query.
   * @return List of EngagementDTOs ordered by lastTouchAt DESC.
   */
  List<EngagementDTO> getForAccount(Id accountId);

  /**
   * @description Race-protected OCR insert. Re-checks for an existing OCR on
   *              the (Opportunity, Contact) pair inside the same transaction
   *              before inserting. Returns details of the existing row when a
   *              race is detected; throws EngagementException on invalid input
   *              or DML failure.
   * @param contactId Contact to add.
   * @param opportunityId Opportunity to add the Contact to.
   * @param role OpportunityContactRole.Role value.
   * @param isPrimary Whether to flag the new OCR as Primary.
   * @return AddToOcrResult capturing success or race-detection state.
   */
  AddToOcrResult addToOcrSafe(
    Id contactId,
    Id opportunityId,
    String role,
    Boolean isPrimary
  );

  /**
   * @description Marks an Opportunity_Engagement_Signal__c as dismissed.
   *              Phase 1 stub — signals are produced in Phase 3, so the
   *              implementation tolerates non-existent Ids gracefully.
   * @param signalId Signal record Id to dismiss.
   * @param reason Free-form reason captured for analytics.
   */
  void dismissSignal(Id signalId, String reason);

  /**
   * @description Records a per-user dismissal so the given Contact disappears
   *              from this user's engagement panel for the given scope until
   *              a new touch arrives (Engagement_Touch__c.Occurred_At greater
   *              than the dismissal's Dismissed_At__c). Exactly one of
   *              `opportunityId` / `accountId` must be non-null — the scope of
   *              where the user clicked × on the panel.
   * @param contactId Contact the user is dismissing.
   * @param opportunityId Opportunity scope (null when dismissing on Account).
   * @param accountId Account scope (null when dismissing on Opportunity).
   */
  void dismissContact(Id contactId, Id opportunityId, Id accountId);
}
