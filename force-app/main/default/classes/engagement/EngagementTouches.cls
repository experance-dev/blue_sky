/**
 * @description Domain class for Engagement_Touch__c. Houses business logic that
 *              applies to a collection of touches (validation, normalization,
 *              denormalization of Account from Contact, etc.). Phase 1 ships
 *              a minimal skeleton; Phase 2 adds trigger-invoked behavior when
 *              the HubSpot ingestion endpoint goes live.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class EngagementTouches {
  private final List<Engagement_Touch__c> records;

  public EngagementTouches(List<Engagement_Touch__c> records) {
    this.records = (records == null)
      ? new List<Engagement_Touch__c>()
      : records;
  }

  /**
   * @description Returns the backing list of records held by this Domain.
   * @return List of Engagement_Touch__c records (never null).
   */
  public List<Engagement_Touch__c> getRecords() {
    return this.records;
  }

  /**
   * @description Convenience static constructor for fluent call sites.
   * @param records List of records to wrap.
   * @return New EngagementTouches Domain instance.
   */
  public static EngagementTouches newInstance(
    List<Engagement_Touch__c> records
  ) {
    return new EngagementTouches(records);
  }

  /**
   * @description Phase 2: normalize Account__c from Contact lookup if Account__c
   *              is null. Phase 1 implementation: no-op — records arrive
   *              pre-normalized via the seed script.
   */
  public void denormalizeAccountFromContact() {
    // Phase 1: no-op. Wire up in Phase 2 when HubSpot ingestion writes raw touches.
  }
}
