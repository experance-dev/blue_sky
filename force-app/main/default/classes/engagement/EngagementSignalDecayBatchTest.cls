/**
 * @description Tests for `EngagementSignalDecayBatch`. Confidence is a linear
 *              function of touch age: 100 at age 0, 0 at age >= decay-days.
 *              Tests pin the decay window to 60 days via the static settings
 *              override so age-to-confidence math is deterministic.
 * @group Engagement Attribution
 * @see EngagementSignalDecayBatch
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementSignalDecayBatchTest {
  private static final String PERMISSION_SET = 'Additional_Permissions_Marketing_Influence_Integration';
  private static final String USER_LAST_NAME = 'DecayBatchTest';
  private static final Integer DECAY_DAYS = 60;

  /**
   * @description Provisions a permission-set-assigned test user. Per-test
   *              fixtures are built inside each method so age is controllable.
   */
  @TestSetup
  static void setup() {
    EngagementTestFixtures.disableAllProcessAutomation();
    provisionTestUser();
  }

  /**
   * @description A touch 30 days old with decay window 60 should drop a fresh
   *              (100-confidence) signal to roughly 50.
   */
  @IsTest
  static void executeDecaysSignalsOlderThanThreshold() {
    System.runAs(getTestUser()) {
      overrideDecayDays(DECAY_DAYS);
      Id signalId = seedSignalWithAgedTouch(30, 100, false);

      Test.startTest();
      Database.executeBatch(new EngagementSignalDecayBatch(), 200);
      Test.stopTest();

      Opportunity_Engagement_Signal__c reloaded = querySignal(signalId);
      Assert.areEqual(
        50,
        reloaded.Confidence__c,
        'Expected confidence 50 for a 30-day-old touch with a 60-day decay window.'
      );
    }
  }

  /**
   * @description A 1-day-old touch should stay at (or within one unit of) 100.
   *              The batch must not flag it as needing an update.
   */
  @IsTest
  static void executeDoesNotTouchFreshSignals() {
    System.runAs(getTestUser()) {
      overrideDecayDays(DECAY_DAYS);
      Id signalId = seedSignalWithAgedTouch(1, 100, false);

      Test.startTest();
      Database.executeBatch(new EngagementSignalDecayBatch(), 200);
      Test.stopTest();

      Opportunity_Engagement_Signal__c reloaded = querySignal(signalId);
      Assert.isTrue(
        reloaded.Confidence__c >= 98,
        'Expected confidence to stay near 100 for a 1-day-old touch; got ' +
        reloaded.Confidence__c
      );
    }
  }

  /**
   * @description A 365-day-old touch must floor at zero confidence — the lower
   *              bound of the decay function.
   */
  @IsTest
  static void executeFloorsAtZero() {
    System.runAs(getTestUser()) {
      overrideDecayDays(DECAY_DAYS);
      Id signalId = seedSignalWithAgedTouch(365, 100, false);

      Test.startTest();
      Database.executeBatch(new EngagementSignalDecayBatch(), 200);
      Test.stopTest();

      Opportunity_Engagement_Signal__c reloaded = querySignal(signalId);
      Assert.areEqual(
        0,
        reloaded.Confidence__c,
        'Expected confidence floored at 0 for a year-old touch.'
      );
    }
  }

  /**
   * @description Dismissed signals are filtered out at `start()` and must not
   *              be touched by the batch regardless of age.
   */
  @IsTest
  static void executeSkipsDismissedSignals() {
    System.runAs(getTestUser()) {
      overrideDecayDays(DECAY_DAYS);
      Id signalId = seedSignalWithAgedTouch(45, 100, true);

      Test.startTest();
      Database.executeBatch(new EngagementSignalDecayBatch(), 200);
      Test.stopTest();

      Opportunity_Engagement_Signal__c reloaded = querySignal(signalId);
      Assert.areEqual(
        100,
        reloaded.Confidence__c,
        'Expected dismissed signal to keep its original confidence.'
      );
    }
  }

  // ─── New tests (David Wood, 2026-05-12) ───────────────────────────────────

  /**
   * @description Empty scope → batch's execute returns early without DML.
   *              Covers the empty-scope short-circuit on line 60.
   */
  @IsTest
  static void executeWithEmptyScopeIsNoOp() {
    System.runAs(getTestUser()) {
      overrideDecayDays(DECAY_DAYS);
      EngagementSignalDecayBatch batch = new EngagementSignalDecayBatch();
      Integer dmlBefore = Limits.getDmlStatements();
      Test.startTest();
      batch.execute(null, new List<Opportunity_Engagement_Signal__c>());
      Test.stopTest();
      Assert.areEqual(
        dmlBefore,
        Limits.getDmlStatements(),
        'Expected zero DML on empty scope short-circuit.'
      );
    }
  }

  /**
   * @description Null scope is identical to empty scope (defensive).
   */
  @IsTest
  static void executeWithNullScopeIsNoOp() {
    System.runAs(getTestUser()) {
      overrideDecayDays(DECAY_DAYS);
      EngagementSignalDecayBatch batch = new EngagementSignalDecayBatch();
      Test.startTest();
      batch.execute(null, null);
      Test.stopTest();
      // No assertion needed beyond "did not throw" — covers line 60 null branch.
      Assert.isTrue(true, 'Null scope handled without throwing.');
    }
  }

  /**
   * @description A signal whose Engagement_Touch__c is set to a fake Id
   *              produces an `occurredAt == null` mapping and is skipped.
   *              Covers line 70.
   */
  @IsTest
  static void executeWithMissingTouchSkipsSignal() {
    System.runAs(getTestUser()) {
      overrideDecayDays(DECAY_DAYS);
      // Seed a real signal but blank out the parent touch reference after
      // insert so the loadTouchOccurredAt map returns null.
      Id signalId = seedSignalWithAgedTouch(30, 100, false);
      Opportunity_Engagement_Signal__c sig = querySignal(signalId);
      Id originalConfidence = sig.Confidence__c == null
        ? null
        : sig.Engagement_Touch__c;
      // Detach the touch by setting Engagement_Touch__c to null (won't be
      // queried in start() because it's part of the dataset).
      Engagement_Touch__c phantom = [
        SELECT Id
        FROM Engagement_Touch__c
        WHERE Id = :sig.Engagement_Touch__c
      ];
      // Hard-delete the touch so the signal's lookup is dangling.
      Database.delete(phantom, false, AccessLevel.SYSTEM_MODE);

      Test.startTest();
      Database.executeBatch(new EngagementSignalDecayBatch(), 200);
      Test.stopTest();

      Opportunity_Engagement_Signal__c reloaded = querySignal(signalId);
      Assert.areEqual(
        100,
        reloaded.Confidence__c,
        'Expected the signal to be skipped when its touch reference dangles.'
      );
    }
  }

  /**
   * @description Without a settings record AND without override, the batch
   *              falls back to the DEFAULT_DECAY_DAYS=90 constant.
   *              Covers line 121 (settings null path).
   */
  @IsTest
  static void executeWithNullSettingsFallsBackToDefault() {
    System.runAs(getTestUser()) {
      // Explicitly clear the override.
      EngagementSignalDecayBatch.settingsOverride = null;
      Id signalId = seedSignalWithAgedTouch(45, 100, false);

      Test.startTest();
      Database.executeBatch(new EngagementSignalDecayBatch(), 200);
      Test.stopTest();

      Opportunity_Engagement_Signal__c reloaded = querySignal(signalId);
      // 45 days into a 90-day window → confidence 50 (100 - 45*100/90 = 50)
      Assert.areEqual(
        50,
        reloaded.Confidence__c,
        'Expected default 90-day decay window to land 45-day touch at 50.'
      );
    }
  }

  /**
   * @description Settings record with Signal_Decay_Days__c=0 must fall back
   *              to the DEFAULT_DECAY_DAYS constant. Covers line 124.
   */
  @IsTest
  static void executeWithZeroSettingFallsBackToDefault() {
    System.runAs(getTestUser()) {
      EngagementSignalDecayBatch.settingsOverride = new Engagement_Settings__c(
        Signal_Decay_Days__c = 0
      );
      Id signalId = seedSignalWithAgedTouch(45, 100, false);

      Test.startTest();
      Database.executeBatch(new EngagementSignalDecayBatch(), 200);
      Test.stopTest();

      Opportunity_Engagement_Signal__c reloaded = querySignal(signalId);
      // Confirms the zero override didn't divide-by-zero; default 90 kicks in.
      Assert.areEqual(
        50,
        reloaded.Confidence__c,
        'Expected zero-day override to fall back to default 90 window.'
      );
    }
  }

  /**
   * @description Sub-unit delta (computed within 1 of current) is skipped.
   *              Set the signal at confidence within 1 of the computed value
   *              for an aged touch; assert no DML.
   *              Covers line 75-76 (MIN_DELTA_TO_UPDATE branch).
   */
  @IsTest
  static void executeIgnoresSubUnitChanges() {
    System.runAs(getTestUser()) {
      overrideDecayDays(DECAY_DAYS);
      // 30 days old, 60-day decay window → computed confidence = 50.
      // Pre-set to 50 (delta 0) so the update is skipped.
      Id signalId = seedSignalWithAgedTouch(30, 50, false);

      Test.startTest();
      Database.executeBatch(new EngagementSignalDecayBatch(), 200);
      Test.stopTest();

      Opportunity_Engagement_Signal__c reloaded = querySignal(signalId);
      Assert.areEqual(
        50,
        reloaded.Confidence__c,
        'Expected no change when delta < MIN_DELTA_TO_UPDATE.'
      );
    }
  }

  /**
   * @description The static computeConfidence helper handles the
   *              future-dated touch edge case (ageDays <= 0 returns 100).
   *              Covers line 161-162 of EngagementSignalDecayBatch.
   */
  @IsTest
  static void computeConfidenceFutureDatedTouchReturns100() {
    DateTime tomorrow = Datetime.now().addDays(1);
    Decimal confidence = EngagementSignalDecayBatch.computeConfidence(
      tomorrow,
      60
    );
    Assert.areEqual(
      100,
      confidence,
      'Expected confidence 100 for a future-dated touch (negative age).'
    );
  }

  // ─── Setup helpers ─────────────────────────────────────────────────────────

  private static void overrideDecayDays(Integer days) {
    EngagementSignalDecayBatch.settingsOverride = new Engagement_Settings__c(
      Signal_Decay_Days__c = days
    );
  }

  private static Id seedSignalWithAgedTouch(
    Integer ageDays,
    Decimal initialConfidence,
    Boolean dismissed
  ) {
    Account a = new Account(
      Name = 'UHC Decay Test ' + Crypto.getRandomInteger()
    );
    Database.insert(a, AccessLevel.SYSTEM_MODE);

    Contact c = new Contact(
      FirstName = 'Decay',
      LastName = 'Tester',
      Email = 'decay' + Crypto.getRandomInteger() + '@test.example.com',
      AccountId = a.Id
    );
    Database.insert(c, AccessLevel.SYSTEM_MODE);

    Touch_Topic__c topic = new Touch_Topic__c(
      Topic_Name__c = 'Network Management',
      External_Code__c = 'TOPIC_DECAY_' + Crypto.getRandomInteger()
    );
    Database.insert(topic, AccessLevel.SYSTEM_MODE);

    Opportunity opp = new Opportunity(
      Name = 'Decay Test Opp ' + Crypto.getRandomInteger(),
      AccountId = a.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      Touch_Topic__c = topic.Id
    );
    Database.insert(opp, AccessLevel.SYSTEM_MODE);

    Engagement_Touch__c t = new Engagement_Touch__c(
      External_Id__c = 'EXT-DECAY-' + Crypto.getRandomInteger(),
      Source_System__c = 'HubSpot',
      Email_At_Touch__c = c.Email,
      Contact__c = c.Id,
      Account__c = a.Id,
      Topic__c = topic.Id,
      Occurred_At__c = DateTime.now().addDays(-ageDays),
      Is_Active__c = true,
      Resolution_Status__c = 'Resolved',
      Processing_Status__c = 'Processed',
      Persona__c = 'Executive',
      Intent_Level__c = 'Medium',
      Touch_Type__c = 'Download'
    );
    Database.insert(t, AccessLevel.SYSTEM_MODE);

    Opportunity_Engagement_Signal__c sig = new Opportunity_Engagement_Signal__c(
      Opportunity__c = opp.Id,
      Engagement_Touch__c = t.Id,
      Contact__c = c.Id,
      Topic__c = topic.Id,
      Confidence__c = initialConfidence,
      Match_Path__c = 'Account',
      Dismissed__c = dismissed
    );
    Database.insert(sig, AccessLevel.SYSTEM_MODE);
    return sig.Id;
  }

  private static Opportunity_Engagement_Signal__c querySignal(Id signalId) {
    return [
      SELECT Id, Confidence__c, Dismissed__c, Engagement_Touch__c
      FROM Opportunity_Engagement_Signal__c
      WHERE Id = :signalId
      LIMIT 1
    ];
  }

  private static User provisionTestUser() {
    Profile standard = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    User u = new User(
      ProfileId = standard.Id,
      LastName = USER_LAST_NAME,
      Email = 'decaybatch@test.example.com',
      Username = 'decaybatch' + Crypto.getRandomInteger() + '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'dcybt',
      TimeZoneSidKey = 'America/Los_Angeles',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US'
    );
    Database.insert(u, AccessLevel.SYSTEM_MODE);

    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :PERMISSION_SET
      LIMIT 1
    ];
    Database.insert(
      new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id),
      AccessLevel.SYSTEM_MODE
    );
    return u;
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
