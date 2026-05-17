/**
 * @description Tests for the EngagementTouches Domain skeleton. Phase 1
 *              behavior is intentionally minimal — these tests pin the
 *              constructor contract and document the deferred Phase 2
 *              denormalization behavior.
 * @group Engagement Attribution
 * @see EngagementTouches
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementTouchesTest {
  /**
   * @description Null input to newInstance must yield an empty backing list,
   *              not a NullPointerException downstream.
   */
  @IsTest
  static void newInstanceEmptyListReturnsEmptyDomain() {
    System.runAs(TestFactory.createTestUser(true, 'Standard User')) {
      Test.startTest();
      EngagementTouches domain = EngagementTouches.newInstance(null);
      Test.stopTest();

      Assert.isNotNull(
        domain.getRecords(),
        'Expected getRecords to return an empty list, not null.'
      );
      Assert.areEqual(
        0,
        domain.getRecords().size(),
        'Expected an empty backing list when constructed with null.'
      );
    }
  }

  /**
   * @description Documents Phase 1 behavior: denormalizeAccountFromContact
   *              is a no-op and must NOT mutate the records. Phase 2 will
   *              replace this assertion with positive coverage.
   */
  @IsTest
  static void denormalizeAccountFromContactIsNoOpPhase1() {
    System.runAs(TestFactory.createTestUser(true, 'Standard User')) {
      Engagement_Touch__c touch = new Engagement_Touch__c(
        Id = Utilities.getFakeId(Engagement_Touch__c.SObjectType),
        Account__c = null
      );

      Test.startTest();
      EngagementTouches domain = EngagementTouches.newInstance(
        new List<Engagement_Touch__c>{ touch }
      );
      domain.denormalizeAccountFromContact();
      Test.stopTest();

      Assert.isNull(
        domain.getRecords()[0].Account__c,
        'Phase 1: denormalize is a no-op; Account__c must remain null.'
      );
    }
  }
}
