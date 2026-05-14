/**
 * @description Return shape for `IEngagementService.addToOcrSafe`. Captures
 *              both the happy-path insert (`success=true`, `ocrId` populated)
 *              and the race-detection branch (`alreadyExists=true`,
 *              `addedByUserName` and `addedAt` populated for the
 *              AlreadyAddedModal UX). The race branch returns `success=false`
 *              by design — the row was not inserted by this transaction.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class AddToOcrResult {
  @AuraEnabled
  public Boolean success;
  @AuraEnabled
  public Boolean alreadyExists;
  @AuraEnabled
  public Id ocrId;
  @AuraEnabled
  public Id addedByUserId;
  @AuraEnabled
  public String addedByUserName;
  @AuraEnabled
  public DateTime addedAt;
  @AuraEnabled
  public String role;
  @AuraEnabled
  public Boolean isPrimary;
}
