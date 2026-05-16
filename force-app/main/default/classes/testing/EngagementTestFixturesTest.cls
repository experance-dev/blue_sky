/**
 * @description Unit tests for `EngagementTestFixtures`. The fixture itself is
 *              `@IsTest`-only, but `@IsTest` classes still need test coverage
 *              to count toward the org-wide percentage on production deploys.
 *              Exercises the public surface: user provisioning, world seeding,
 *              individual builders, settings, fake-Id helpers, picklist
 *              mapping, and the SeededWorld result type.
 * @group Engagement Attribution
 * @see EngagementTestFixtures
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementTestFixturesTest {
  private static final String LAST_NAME = 'FixturesTest';

  /**
   * @description Provisions an engagement user and seeds the UHC world; then
   *              verifies the SeededWorld pointer is populated and lookupWorld
   *              re-hydrates correctly.
   */
  @IsTest
  static void seedUhcWorldPopulatesSeededWorldPointer() {
    User u = EngagementTestFixtures.provisionEngagementUser(LAST_NAME);
    EngagementTestFixtures.SeededWorld world;
    System.runAs(u) {
      Test.startTest();
      world = EngagementTestFixtures.seedUhcWorld();
      Test.stopTest();
    }
    Assert.isNotNull(world.accountId, 'Expected accountId populated.');
    Assert.isNotNull(world.opportunityId, 'Expected opportunityId populated.');
    Assert.isNotNull(
      world.networkTopicId,
      'Expected networkTopicId populated.'
    );
    Assert.areEqual(
      4,
      world.contactIdsByLastName.size(),
      'Expected 4 contacts seeded.'
    );
    Assert.areEqual(
      5,
      world.topicIdsByCode.size(),
      'Expected 5 topics seeded.'
    );
    Assert.isTrue(
      world.touchIds.size() >= 10,
      'Expected at least 10 touches seeded; got ' + world.touchIds.size()
    );
  }

  /**
   * @description lookupWorld re-fetches all the seeded ids inside a different
   *              test method (different transaction frame from TestSetup-style
   *              seeding) and returns a populated SeededWorld pointer.
   */
  @IsTest
  static void lookupWorldReturnsHydratedSeededWorld() {
    User u = EngagementTestFixtures.provisionEngagementUser(LAST_NAME);
    System.runAs(u) {
      EngagementTestFixtures.seedUhcWorld();
      Test.startTest();
      EngagementTestFixtures.SeededWorld w = EngagementTestFixtures.lookupWorld();
      Test.stopTest();
      Assert.isNotNull(w.accountId, 'Expected accountId after lookup.');
      Assert.isNotNull(w.opportunityId, 'Expected opportunityId after lookup.');
      Assert.isNotNull(
        w.contactByLastName('Johnson'),
        'Expected Johnson contact via lookup helper.'
      );
      Assert.isNotNull(
        w.topicByCode(EngagementTestFixtures.TOPIC_CODE_NETMGT),
        'Expected NETMGT topic via lookup helper.'
      );
    }
  }

  /**
   * @description Bulk variant seeds extra contacts + touches.
   */
  @IsTest
  static void seedUhcWorldBulkAddsExtraContactsAndTouches() {
    User u = EngagementTestFixtures.provisionEngagementUser(LAST_NAME);
    EngagementTestFixtures.SeededWorld world;
    System.runAs(u) {
      Test.startTest();
      world = EngagementTestFixtures.seedUhcWorldBulk(5, 2);
      Test.stopTest();
    }
    // 4 canonical contacts + 5 bulk = 9.
    Assert.areEqual(
      9,
      [SELECT COUNT() FROM Contact WHERE AccountId = :world.accountId],
      'Expected 9 contacts total (4 canonical + 5 bulk).'
    );
    // 12 baseline touches + 5*2 bulk = 22 (approximate).
    Assert.isTrue(
      world.touchIds.size() >= 22,
      'Expected at least 22 touches (baseline + bulk).'
    );
  }

  /**
   * @description Unauthorized user is provisioned without the permset.
   *              The assertion runs as the current Sysadmin context (the
   *              setup user); the unauth user is the asserted-about subject,
   *              not the runAs target.
   */
  @IsTest
  static void provisionUnauthorizedUserHasNoPermset() {
    System.runAs(TestFactory.createTestUser(true, 'System Administrator')) {
      Test.startTest();
      User u = EngagementTestFixtures.provisionUnauthorizedUser(
        LAST_NAME + 'Unauth'
      );
      Test.stopTest();
      Integer assignments = [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :u.Id
          AND PermissionSet.Name = :EngagementTestFixtures.PERMISSION_SET
      ];
      Assert.areEqual(
        0,
        assignments,
        'Expected zero engagement permset assignments on unauthorized user.'
      );
    }
  }

  /**
   * @description Fake-Id helpers return well-formed Salesforce IDs of the
   *              right SObject prefix.
   */
  @IsTest
  static void fakeIdHelpersReturnValidPrefixedIds() {
    // Pure helper math; runAs satisfies PMD without changing semantics.
    System.runAs(TestFactory.createTestUser(true, 'Standard User')) {
      Id touchId = EngagementTestFixtures.fakeTouchId();
      Id contactId = EngagementTestFixtures.fakeContactId();
      Id oppId = EngagementTestFixtures.fakeOpportunityId();
      Id sigId = EngagementTestFixtures.fakeSignalId();
      Id accountId = EngagementTestFixtures.fakeAccountId();
      Assert.isNotNull(touchId, 'fakeTouchId should not be null.');
      Assert.isNotNull(contactId, 'fakeContactId should not be null.');
      Assert.isNotNull(oppId, 'fakeOpportunityId should not be null.');
      Assert.isNotNull(sigId, 'fakeSignalId should not be null.');
      Assert.isNotNull(accountId, 'fakeAccountId should not be null.');
      Assert.areEqual(
        '003',
        contactId.toString().substring(0, 3),
        'fakeContactId should have Contact prefix 003.'
      );
      Assert.areEqual(
        '006',
        oppId.toString().substring(0, 3),
        'fakeOpportunityId should have Opportunity prefix 006.'
      );
      Assert.areEqual(
        '001',
        accountId.toString().substring(0, 3),
        'fakeAccountId should have Account prefix 001.'
      );
    }
  }

  /**
   * @description Picklist mapping covers all known divergent values plus the
   *              pass-through default for unknown labels.
   */
  @IsTest
  static void mapToSourceEventCoversAllKnownValues() {
    // Pure string-mapping helper; runAs satisfies PMD without changing
    // semantics (no SOQL/DML or sharing context exercised).
    System.runAs(TestFactory.createTestUser(true, 'Standard User')) {
      Assert.areEqual(
        'Page View',
        EngagementTestFixtures.mapToSourceEvent('Page'),
        'Page should map to Page View.'
      );
      Assert.areEqual(
        'Form Submission',
        EngagementTestFixtures.mapToSourceEvent('Form'),
        'Form should map to Form Submission.'
      );
      Assert.areEqual(
        'Event Attendance',
        EngagementTestFixtures.mapToSourceEvent('Event'),
        'Event should map to Event Attendance.'
      );
      Assert.areEqual(
        'Download',
        EngagementTestFixtures.mapToSourceEvent('Download'),
        'Download passes through unchanged.'
      );
      Assert.areEqual(
        'Webinar',
        EngagementTestFixtures.mapToSourceEvent('Webinar'),
        'Webinar passes through unchanged.'
      );
      Assert.areEqual(
        'Unknown',
        EngagementTestFixtures.mapToSourceEvent('Unknown'),
        'Unknown labels pass through (no exception).'
      );
    }
  }

  /**
   * @description seedSettings is idempotent — calling twice updates the same
   *              org-default record.
   */
  @IsTest
  static void seedSettingsIsIdempotent() {
    // Hierarchy custom-setting writes; runAs satisfies PMD. The fixture's
    // own UPSERT uses SYSTEM-mode DML internally so user context is moot.
    System.runAs(TestFactory.createTestUser(true, 'System Administrator')) {
      Test.startTest();
      EngagementTestFixtures.seedSettings(60, 180);
      EngagementTestFixtures.seedSettings(30, 90);
      Test.stopTest();
      Engagement_Settings__c s = Engagement_Settings__c.getOrgDefaults();
      Assert.areEqual(
        30,
        s.Signal_Decay_Days__c,
        'Expected second call to update Signal_Decay_Days__c.'
      );
      Assert.areEqual(
        90,
        s.Active_Window_Days__c,
        'Expected second call to update Active_Window_Days__c.'
      );
    }
  }

  /**
   * @description Individual builders return populated SObjects that pass
   *              insert validation when supplied with the fixture's seeded
   *              parent IDs.
   */
  @IsTest
  static void individualBuildersProducePersistableRecords() {
    User u = EngagementTestFixtures.provisionEngagementUser(
      LAST_NAME + 'Builders'
    );
    System.runAs(u) {
      EngagementTestFixtures.SeededWorld w = EngagementTestFixtures.seedUhcWorld();
      Test.startTest();
      Engagement_Touch__c t = EngagementTestFixtures.newTouch(
        w.accountId,
        w.contactByLastName('Johnson'),
        w.networkTopicId,
        'EXT-BUILDER-1'
      );
      Database.insert(t, AccessLevel.SYSTEM_MODE);

      Engagement_Touch__c aged = EngagementTestFixtures.newAgedTouch(
        w.accountId,
        w.contactByLastName('Johnson'),
        w.networkTopicId,
        45
      );
      Database.insert(aged, AccessLevel.SYSTEM_MODE);

      Opportunity_Engagement_Signal__c sig = EngagementTestFixtures.newSignal(
        t.Id,
        w.opportunityId,
        w.contactByLastName('Johnson'),
        80
      );
      Database.insert(sig, AccessLevel.SYSTEM_MODE);

      Engagement_Dismissal__c dis = EngagementTestFixtures.newDismissal(
        w.contactByLastName('Johnson'),
        w.opportunityId,
        null
      );
      Database.insert(dis, AccessLevel.SYSTEM_MODE);

      Contact c = EngagementTestFixtures.newContact(
        w.accountId,
        'Builder',
        'Smith',
        'builder@test.example.com'
      );
      Database.insert(c, AccessLevel.SYSTEM_MODE);

      Test.stopTest();

      Assert.isNotNull(t.Id, 'newTouch should persist.');
      Assert.isNotNull(aged.Id, 'newAgedTouch should persist.');
      Assert.isNotNull(sig.Id, 'newSignal should persist.');
      Assert.isNotNull(dis.Id, 'newDismissal should persist.');
      Assert.isNotNull(c.Id, 'newContact should persist.');
    }
  }
}
