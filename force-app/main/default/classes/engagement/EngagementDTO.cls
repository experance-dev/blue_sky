/**
 * @description LWC-facing DTO for the Engagement Attribution feature. Frozen
 *              shape per PHASE1-HANDOFF.md §Apex DTO contract — additions or
 *              renames require coordinated LWC + Apex change.
 *
 *              One DTO per engaged Contact, with per-asset breakdown nested in
 *              `assets` for the View-All / expand UX. Booleans (`onOcr`,
 *              `isAcr`, `isConsultant`) capture the cross-context flags the
 *              panel uses to switch sections and render badges.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class EngagementDTO {
  @AuraEnabled
  public Id contactId;
  @AuraEnabled
  public String name;
  @AuraEnabled
  public String title;
  @AuraEnabled
  public String accountName;
  @AuraEnabled
  public Boolean onOcr;
  @AuraEnabled
  public String ocrRole;
  @AuraEnabled
  public Boolean isAcr;
  @AuraEnabled
  public String acrRole;
  @AuraEnabled
  public Boolean isConsultant;
  @AuraEnabled
  public List<String> topics;
  @AuraEnabled
  public Integer touchCount;
  @AuraEnabled
  public DateTime lastTouchAt;
  @AuraEnabled
  public List<AssetEngagement> assets;

  /**
   * @description Per-asset breakdown nested inside an EngagementDTO. One
   *              instance per (Asset_Name__c, Touch_Type__c) tuple for the
   *              owning Contact. The repeat-count badge in the LWC consumes
   *              `count`; `firstAt` / `lastAt` drive the time-range pill.
   */
  public class AssetEngagement {
    @AuraEnabled
    public String assetName;
    @AuraEnabled
    public String touchType;
    @AuraEnabled
    public Integer count;
    @AuraEnabled
    public DateTime firstAt;
    @AuraEnabled
    public DateTime lastAt;
    @AuraEnabled
    public String campaignName;
  }
}
