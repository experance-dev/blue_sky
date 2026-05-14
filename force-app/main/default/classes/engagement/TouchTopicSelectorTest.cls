/**
 * @description Happy-path tests for TouchTopicSelector. Seeds the Zelis-flavored
 *              topic catalog from the Phase 1 handoff and exercises each public
 *              method under a permset-assigned test user.
 * @group Engagement Attribution
 * @see TouchTopicSelector
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class TouchTopicSelectorTest {
  private static final String PERMSET_NAME = 'Engagement_Attribution_User';
  private static final List<String> TOPIC_NAMES = new List<String>{
    'Claims Editing',
    'Member Engagement',
    'Network Management',
    'Payment Integrity',
    'Price Transparency'
  };

  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    // Standard User profile grants the standard Account/Opportunity access that
    // the permset itself doesn't replicate; permset adds the engagement objects.
    User u = TestFactory.createTestUser(true, 'Standard User');
    System.runAs(u) {
      List<Touch_Topic__c> topics = new List<Touch_Topic__c>();
      for (Integer i = 0; i < TOPIC_NAMES.size(); i++) {
        topics.add(
          new Touch_Topic__c(
            Topic_Name__c = TOPIC_NAMES[i],
            External_Code__c = 'TT-' + String.valueOf(i + 1).leftPad(3, '0')
          )
        );
      }
      Database.insert(topics, AccessLevel.SYSTEM_MODE);
    }
    TestFactory.assignPermSetToUser(u, PERMSET_NAME);
  }

  /**
   * @description Verifies selectAll returns every seeded topic ordered alphabetically by Topic_Name__c.
   */
  @IsTest
  static void selectAllReturnsAllTopicsSortedByName() {
    System.runAs(getTestUser()) {
      Test.startTest();
      List<Touch_Topic__c> topics = TouchTopicSelector.selectAll();
      Test.stopTest();

      Assert.areEqual(
        TOPIC_NAMES.size(),
        topics.size(),
        'Expected all seeded topics to be returned.'
      );
      List<String> expected = new List<String>(TOPIC_NAMES);
      expected.sort();
      for (Integer i = 0; i < expected.size(); i++) {
        Assert.areEqual(
          expected[i],
          topics[i].Topic_Name__c,
          'Expected topics ordered alphabetically at index ' + i + '.'
        );
      }
    }
  }

  /**
   * @description Verifies selectByIds returns a map keyed by Id containing only the requested topics.
   */
  @IsTest
  static void selectByIdsReturnsRequestedMap() {
    System.runAs(getTestUser()) {
      List<Touch_Topic__c> seeded = [
        SELECT Id
        FROM Touch_Topic__c
        ORDER BY Topic_Name__c ASC
        LIMIT 2
      ];
      Set<Id> ids = new Set<Id>{ seeded[0].Id, seeded[1].Id };

      Test.startTest();
      Map<Id, Touch_Topic__c> result = TouchTopicSelector.selectByIds(ids);
      Test.stopTest();

      Assert.areEqual(
        2,
        result.size(),
        'Expected map size to match requested id count.'
      );
      Assert.isTrue(
        result.containsKey(seeded[0].Id),
        'Expected first requested topic to be in the result map.'
      );
      Assert.isTrue(
        result.containsKey(seeded[1].Id),
        'Expected second requested topic to be in the result map.'
      );
    }
  }

  /**
   * @description Verifies selectByIds short-circuits to an empty map when given an empty input set.
   */
  @IsTest
  static void selectByIdsEmptySetReturnsEmptyMap() {
    System.runAs(getTestUser()) {
      Test.startTest();
      Map<Id, Touch_Topic__c> result = TouchTopicSelector.selectByIds(
        new Set<Id>()
      );
      Test.stopTest();

      Assert.areEqual(0, result.size(), 'Expected empty map for empty id set.');
    }
  }

  /**
   * @description Verifies selectByOpportunityId scopes to the Opportunity's Touch_Topic__c when set.
   */
  @IsTest
  static void selectByOpportunityIdWithTopicSetReturnsScoped() {
    System.runAs(getTestUser()) {
      Touch_Topic__c topic = [
        SELECT Id, Topic_Name__c
        FROM Touch_Topic__c
        WHERE Topic_Name__c = 'Payment Integrity'
        LIMIT 1
      ];
      Account acct = (Account) TestFactory.createSObject(
        new Account(Name = 'United Healthcare'),
        true
      );
      Opportunity opp = (Opportunity) TestFactory.createSObject(
        new Opportunity(
          Name = 'Network Pricing Implementation',
          AccountId = acct.Id,
          StageName = 'Prospecting',
          CloseDate = Date.today().addDays(30),
          Touch_Topic__c = topic.Id
        ),
        true
      );

      Test.startTest();
      List<Touch_Topic__c> result = TouchTopicSelector.selectByOpportunityId(
        opp.Id
      );
      Test.stopTest();

      Assert.areEqual(
        1,
        result.size(),
        'Expected exactly one topic when Opportunity.Touch_Topic__c is set.'
      );
      Assert.areEqual(
        topic.Id,
        result[0].Id,
        'Expected the scoped topic to be the one referenced on the Opportunity.'
      );
    }
  }

  /**
   * @description Verifies selectByOpportunityId falls back to the full catalog when Touch_Topic__c is unset.
   */
  @IsTest
  static void selectByOpportunityIdNoTopicSetReturnsAll() {
    System.runAs(getTestUser()) {
      Account acct = (Account) TestFactory.createSObject(
        new Account(Name = 'United Healthcare'),
        true
      );
      Opportunity opp = (Opportunity) TestFactory.createSObject(
        new Opportunity(
          Name = 'Network Pricing Implementation',
          AccountId = acct.Id,
          StageName = 'Prospecting',
          CloseDate = Date.today().addDays(30)
        ),
        true
      );

      Test.startTest();
      List<Touch_Topic__c> result = TouchTopicSelector.selectByOpportunityId(
        opp.Id
      );
      Test.stopTest();

      Assert.areEqual(
        TOPIC_NAMES.size(),
        result.size(),
        'Expected the full topic catalog when Opportunity.Touch_Topic__c is null.'
      );
    }
  }

  private static User getTestUser() {
    return TestFactory.getCreatedTestUser(PERMSET_NAME);
  }
}
