/**
 * @description Tests for `EngagementSignalRouter.routeTouches`. The seeded CMT
 *              rule set is fixed at deploy time, so each test asserts behaviour
 *              against the production rule cascade (priority-10 OCR through
 *              priority-50 Account/Topic default) rather than synthesising
 *              its own rules.
 * @group Engagement Attribution
 * @see EngagementSignalRouter
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementSignalRouterTest {
  private static final String PERMISSION_SET = 'Additional_Permissions_Marketing_Influence_Integration';
  private static final String USER_LAST_NAME = 'SignalRouterTest';

  /**
   * @description Provisions a permission-set-assigned test user and seeds the
   *              shared world: 1 Account, 1 Contact, 1 Touch_Topic, 1 open
   *              Opportunity tied to the topic, and 1 already-resolved touch
   *              pointing at all of the above.
   */
  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    User u = provisionTestUser();
    System.runAs(u) {
      seedWorld();
    }
  }

  // ─── Tests ────────────────────────────────────────────────────────────────

  /**
   * @description The cascade selects the highest-priority rule whose preconditions
   *              are met. With a same-account + same-topic touch and only the
   *              implicit AccountContactRelation (`IsDirect = true`) that
   *              Salesforce auto-creates for a Contact's primary Account, the
   *              ACR rule must NOT match — Q10 restricts the ACR path to
   *              indirect relationships only. The cascade falls through to the
   *              priority-50 Account/Topic default.
   */
  @IsTest
  static void routeTouchesCreatesAccountSignal() {
    System.runAs(getTestUser()) {
      Id touchId = getSeededTouchId();

      Test.startTest();
      EngagementSignalRouter.routeTouches(new Set<Id>{ touchId });
      Test.stopTest();

      List<Opportunity_Engagement_Signal__c> signals = querySignalsForTouch(
        touchId
      );
      Assert.isFalse(
        signals.isEmpty(),
        'Expected at least one signal from the routing cascade.'
      );
      Assert.areEqual(
        'Account',
        signals[0].Match_Path__c,
        'Implicit (IsDirect=true) ACR must not match the ACR rule; cascade falls through to priority-50 Account default.'
      );
    }
  }

  /**
   * @description Adding the touch's Contact to the Opp's OCR makes the
   *              priority-10 OCR rule the highest-priority match. The signal
   *              must carry Match_Path='OCR'.
   */
  @IsTest
  static void routeTouchesFiresOCRRuleWhenContactOnOpp() {
    System.runAs(getTestUser()) {
      Id touchId = getSeededTouchId();
      Engagement_Touch__c touch = querySeededTouch(touchId);
      Id oppId = querySeededOpportunityId();
      Database.insert(
        new OpportunityContactRole(
          OpportunityId = oppId,
          ContactId = touch.Contact__c,
          Role = 'Evaluator'
        ),
        AccessLevel.SYSTEM_MODE
      );

      Test.startTest();
      EngagementSignalRouter.routeTouches(new Set<Id>{ touchId });
      Test.stopTest();

      List<Opportunity_Engagement_Signal__c> signals = querySignalsForTouch(
        touchId
      );
      // OCR rule wins at priority 10. The implicit ACR + priority-20 ACR rule
      // would otherwise fire too, but the router selects only the
      // highest-priority match per (touch, opportunity).
      Assert.isFalse(
        signals.isEmpty(),
        'Expected at least one signal — OCR rule should win.'
      );
      Assert.areEqual(
        'OCR',
        signals[0].Match_Path__c,
        'Expected Match_Path=OCR from the priority-10 rule.'
      );
    }
  }

  /**
   * @description A Contact whose primary Account is a different (consultant)
   *              account but who is related to the target Account via an
   *              explicit AccountContactRelation with `IsDirect = false`
   *              represents the indirect-relationship scenario the ACR path
   *              is designed to catch. With no OCR on the Opportunity the
   *              priority-20 ACR rule must win and stamp `Match_Path = ACR`.
   */
  @IsTest
  static void routeTouchesFiresACRRuleForIndirectRelation() {
    System.runAs(getTestUser()) {
      Id consultantTouchId = seedIndirectConsultantTouch();

      Test.startTest();
      EngagementSignalRouter.routeTouches(new Set<Id>{ consultantTouchId });
      Test.stopTest();

      List<Opportunity_Engagement_Signal__c> signals = querySignalsForTouch(
        consultantTouchId
      );
      Assert.isFalse(
        signals.isEmpty(),
        'Expected at least one signal — indirect ACR should fire the ACR rule.'
      );
      Assert.areEqual(
        'ACR',
        signals[0].Match_Path__c,
        'Indirect (IsDirect=false) ACR must match the priority-20 ACR rule.'
      );
    }
  }

  /**
   * @description Calling `routeTouches` twice with the same touch id must
   *              create at most one signal — idempotency contract.
   */
  @IsTest
  static void routeTouchesSkipsDuplicates() {
    System.runAs(getTestUser()) {
      Id touchId = getSeededTouchId();

      Test.startTest();
      EngagementSignalRouter.routeTouches(new Set<Id>{ touchId });
      EngagementSignalRouter.routeTouches(new Set<Id>{ touchId });
      Test.stopTest();

      Integer count = [
        SELECT COUNT()
        FROM Opportunity_Engagement_Signal__c
        WHERE Engagement_Touch__c = :touchId
      ];
      Assert.areEqual(
        1,
        count,
        'Expected idempotency — second call must not create a duplicate.'
      );
    }
  }

  /**
   * @description Touches whose Resolution_Status is NoMatch (or anything other
   *              than Resolved) must be filtered out at query time, producing
   *              zero signals regardless of routing-rule matches.
   */
  @IsTest
  static void routeTouchesSkipsNoMatchTouches() {
    System.runAs(getTestUser()) {
      // querySeededTouch only selects a subset of fields, so we re-query the
      // seeded touch with the broader projection needed to clone deterministically.
      Engagement_Touch__c source = [
        SELECT
          Account__c,
          Contact__c,
          Topic__c,
          Touch_Type__c,
          Source_System__c,
          Persona__c,
          Intent_Level__c,
          Occurred_At__c,
          Is_Active__c,
          Processing_Status__c,
          Email_At_Touch__c
        FROM Engagement_Touch__c
        WHERE External_Id__c = 'EXT-ROUTER-1'
        LIMIT 1
      ];
      Engagement_Touch__c noMatch = source.clone(false, false, false, false);
      noMatch.External_Id__c = 'EXT-NOMATCH-1';
      noMatch.Resolution_Status__c = 'NoMatch';
      Database.insert(noMatch, AccessLevel.SYSTEM_MODE);

      Test.startTest();
      EngagementSignalRouter.routeTouches(new Set<Id>{ noMatch.Id });
      Test.stopTest();

      Integer count = [
        SELECT COUNT()
        FROM Opportunity_Engagement_Signal__c
        WHERE Engagement_Touch__c = :noMatch.Id
      ];
      Assert.areEqual(0, count, 'Expected zero signals for a NoMatch touch.');
    }
  }

  // ─── Setup helpers ────────────────────────────────────────────────────────

  private static void seedWorld() {
    Account a = new Account(Name = 'UHC Router Test');
    Database.insert(a, AccessLevel.SYSTEM_MODE);

    Contact c = new Contact(
      FirstName = 'Routing',
      LastName = 'Tester',
      Email = 'route@test.example.com',
      AccountId = a.Id
    );
    Database.insert(c, AccessLevel.SYSTEM_MODE);

    Touch_Topic__c topic = new Touch_Topic__c(
      Topic_Name__c = 'Network Management',
      External_Code__c = 'TOPIC_NET_MGMT_ROUTER'
    );
    Database.insert(topic, AccessLevel.SYSTEM_MODE);

    Opportunity opp = new Opportunity(
      Name = 'Routing Test Opp',
      AccountId = a.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      Touch_Topic__c = topic.Id
    );
    Database.insert(opp, AccessLevel.SYSTEM_MODE);

    Engagement_Touch__c t = new Engagement_Touch__c(
      External_Id__c = 'EXT-ROUTER-1',
      Source_System__c = 'HubSpot',
      Email_At_Touch__c = 'route@test.example.com',
      Contact__c = c.Id,
      Account__c = a.Id,
      Topic__c = topic.Id,
      Occurred_At__c = Datetime.now().addMinutes(-15),
      Is_Active__c = true,
      Resolution_Status__c = 'Resolved',
      Processing_Status__c = 'Processed',
      Persona__c = 'Executive',
      Intent_Level__c = 'Medium',
      Touch_Type__c = 'Download'
    );
    Database.insert(t, AccessLevel.SYSTEM_MODE);
  }

  /**
   * @description Inserts a second Account ("consultant") and Contact, links
   *              the Contact to the seeded target Account via an explicit
   *              `IsDirect = false` AccountContactRelation, and creates a
   *              Resolved Engagement Touch pointing at (consultant contact,
   *              target account). Returns the new touch Id.
   */
  private static Id seedIndirectConsultantTouch() {
    Account targetAccount = [
      SELECT Id
      FROM Account
      WHERE Name = 'UHC Router Test'
      LIMIT 1
    ];
    Touch_Topic__c topic = [
      SELECT Id
      FROM Touch_Topic__c
      WHERE External_Code__c = 'TOPIC_NET_MGMT_ROUTER'
      LIMIT 1
    ];

    Account consultantAccount = new Account(Name = 'Consultant Firm Test');
    Database.insert(consultantAccount, AccessLevel.SYSTEM_MODE);

    Contact consultantContact = new Contact(
      FirstName = 'Indirect',
      LastName = 'Consultant',
      Email = 'consultant@test.example.com',
      AccountId = consultantAccount.Id
    );
    Database.insert(consultantContact, AccessLevel.SYSTEM_MODE);

    // Explicit indirect ACR linking the consultant contact to the target account.
    // IsDirect is platform-managed in dwood_z (field is read-only in this API
    // version); SF auto-flags this relationship as indirect because targetAccount
    // is not the contact's primary Account. See EngagementTestFixtures BUG note.
    AccountContactRelation indirectAcr = new AccountContactRelation(
      ContactId = consultantContact.Id,
      AccountId = targetAccount.Id,
      Roles = 'Business User'
    );
    Database.insert(indirectAcr, AccessLevel.SYSTEM_MODE);

    Engagement_Touch__c t = new Engagement_Touch__c(
      External_Id__c = 'EXT-ROUTER-INDIRECT-1',
      Source_System__c = 'HubSpot',
      Email_At_Touch__c = 'consultant@test.example.com',
      Contact__c = consultantContact.Id,
      Account__c = targetAccount.Id,
      Topic__c = topic.Id,
      Occurred_At__c = Datetime.now().addMinutes(-10),
      Is_Active__c = true,
      Resolution_Status__c = 'Resolved',
      Processing_Status__c = 'Processed',
      Persona__c = 'Executive',
      Intent_Level__c = 'Medium',
      Touch_Type__c = 'Download'
    );
    Database.insert(t, AccessLevel.SYSTEM_MODE);
    return t.Id;
  }

  private static Id getSeededTouchId() {
    return [
      SELECT Id
      FROM Engagement_Touch__c
      WHERE External_Id__c = 'EXT-ROUTER-1'
      LIMIT 1
    ]
    .Id;
  }

  private static Engagement_Touch__c querySeededTouch(Id touchId) {
    return [
      SELECT Id, Account__c, Contact__c, Topic__c, Resolution_Status__c
      FROM Engagement_Touch__c
      WHERE Id = :touchId
      LIMIT 1
    ];
  }

  private static Id querySeededOpportunityId() {
    return [
      SELECT Id
      FROM Opportunity
      WHERE Name = 'Routing Test Opp'
      LIMIT 1
    ]
    .Id;
  }

  private static List<Opportunity_Engagement_Signal__c> querySignalsForTouch(
    Id touchId
  ) {
    return [
      SELECT Id, Match_Path__c, Confidence__c, Opportunity__c, Contact__c
      FROM Opportunity_Engagement_Signal__c
      WHERE Engagement_Touch__c = :touchId
      ORDER BY Confidence__c DESC
    ];
  }

  private static User provisionTestUser() {
    // Delegates to the shared fixture, which wraps the User +
    // PermissionSetAssignment inserts in `System.runAs(adminUser)` to avoid
    // MIXED_DML against the prior Process_Automation_Switch__c upsert.
    return EngagementTestFixtures.provisionEngagementUser(USER_LAST_NAME);
  }

  private static User getTestUser() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :USER_LAST_NAME
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }
}
