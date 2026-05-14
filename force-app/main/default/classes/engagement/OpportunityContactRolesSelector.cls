/**
 * @description Selector for OpportunityContactRole records. Centralizes SOQL
 *              used by the Engagement Attribution feature — both the panel
 *              render path (which roles are on the deal team) and the
 *              addToOcrSafe race-protection re-check.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class OpportunityContactRolesSelector {
  /**
   * @description Returns every OpportunityContactRole on the given Opportunity,
   *              ordered by CreatedDate descending. Returns an empty list when
   *              the supplied Id is null or blank.
   * @param opportunityId Id of the Opportunity to scope on.
   * @return List of OpportunityContactRole records, possibly empty.
   */
  public static List<OpportunityContactRole> selectByOpportunityId(
    Id opportunityId
  ) {
    if (
      opportunityId == null || String.isBlank(String.valueOf(opportunityId))
    ) {
      return new List<OpportunityContactRole>();
    }
    return [
      SELECT
        Id,
        OpportunityId,
        ContactId,
        Contact.Name,
        Contact.Title,
        Role,
        IsPrimary,
        CreatedById,
        CreatedBy.Name,
        CreatedDate
      FROM OpportunityContactRole
      WHERE OpportunityId = :opportunityId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
    ];
  }

  /**
   * @description Returns the OpportunityContactRole, if any, for the given
   *              (Opportunity, Contact) pair. Used by addToOcrSafe to perform
   *              the race-protection re-check inside the write transaction.
   *              Returns an empty list when either Id is null/blank.
   * @param opportunityId Id of the Opportunity.
   * @param contactId Id of the Contact.
   * @return List of 0 or 1 OpportunityContactRole records.
   */
  public static List<OpportunityContactRole> selectByOpportunityAndContact(
    Id opportunityId,
    Id contactId
  ) {
    if (
      opportunityId == null ||
      String.isBlank(String.valueOf(opportunityId)) ||
      contactId == null ||
      String.isBlank(String.valueOf(contactId))
    ) {
      return new List<OpportunityContactRole>();
    }
    return [
      SELECT
        Id,
        OpportunityId,
        ContactId,
        Contact.Name,
        Contact.Title,
        Role,
        IsPrimary,
        CreatedById,
        CreatedBy.Name,
        CreatedDate
      FROM OpportunityContactRole
      WHERE OpportunityId = :opportunityId AND ContactId = :contactId
      WITH USER_MODE
      LIMIT 1
    ];
  }
}
