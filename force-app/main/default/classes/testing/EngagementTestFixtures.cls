/**
 * @description Shared seeded-world helper for the Engagement Attribution test
 *              suite. Provisions a Standard-licence user with the
 *              `Additional_Permissions_Marketing_Influence_Integration` permset, seeds a canonical UHC
 *              world (1 Account, 4 Contacts, 5 Topics, 1 Opportunity, 2 OCRs,
 *              1 indirect ACR, ~12 Touches), and exposes fine-grained builders
 *              for negative-path and bulk tests. Replaces the 20 hand-rolled
 *              `seedWorld` copies that drifted across test classes.
 *
 *              Lives under `classes/testing/` alongside the personal `TestFactory`
 *              utilities. Composes them, does not replace them — TestFactory
 *              remains the project-wide default-builder; this class is the
 *              engagement-specific scenario builder.
 *
 *              Picklist mapping note: `Touch_Type__c` and `Source_Event_Type__c`
 *              have divergent restricted picklists (Page vs Page View, Form vs
 *              Form Submission, Event vs Event Attendance). `mapToSourceEvent`
 *              normalises the test-side input to the wire-side value. Surfaces
 *              the contract drift between the LWC-friendly short label and the
 *              HubSpot-friendly long label rather than papering over it.
 *
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 * @last May 2026 — added dwood_z Opportunity RecordType binding so seeded
 *                  Opportunities pass through OpportunityTriggerHandler.handleBeforeInsert
 *                  (which requires a non-null, mapped RecordTypeId).
 */
@IsTest
public with sharing class EngagementTestFixtures {
  // ─── Constants ────────────────────────────────────────────────────────────

  public static final String PERMISSION_SET = 'Additional_Permissions_Marketing_Influence_Integration';
  public static final String ACCOUNT_NAME = 'United Healthcare Test';
  public static final String OPP_NAME = 'Network Pricing Test';
  public static final String TOPIC_CODE_NETMGT = 'NETMGT';
  public static final String TOPIC_CODE_PAYINT = 'PAYINT';
  public static final String TOPIC_CODE_CLAIMS = 'CLAIMS';
  public static final String TOPIC_CODE_PRICE = 'PRICE';
  public static final String TOPIC_CODE_OON = 'OON';
  public static final String SARAH_EMAIL = 'sarah.johnson@uhc.example.com';
  public static final String MIKE_EMAIL = 'mike.chen@uhc.example.com';
  public static final String LISA_EMAIL = 'lisa.patel@uhc.example.com';
  public static final String TOM_EMAIL = 'tom.davis@uhc.example.com';

  // ─── User provisioning ────────────────────────────────────────────────────

  /**
   * @description Provisions a Standard-licence user with the
   *              Additional_Permissions_Marketing_Influence_Integration permset assigned. Username is
   *              randomised so concurrent test classes don't collide.
   *
   *              The User insert + PermissionSetAssignment insert are wrapped
   *              in `System.runAs(adminUser)` because setup-object DML
   *              (User, PermissionSetAssignment) cannot follow non-setup DML
   *              (e.g. Process_Automation_Switch__c upsert) in the same
   *              transaction. Running setup DML under an admin's runAs scope
   *              gives Salesforce a fresh DML context and the perms required
   *              to insert users/permset assignments unconditionally.
   *              Tests continue to exercise the seeded non-admin user via
   *              `System.runAs(getTestUser())` in each test body.
   * @param lastName Distinguishing last name (used by `getProvisionedUser`).
   * @return The provisioned User. Already inserted in SYSTEM_MODE.
   */
  public static User provisionEngagementUser(String lastName) {
    User u = buildBaseUser(lastName);
    System.runAs(getAdminUser()) {
      Database.insert(u, AccessLevel.SYSTEM_MODE);
      assignPermset(u.Id, PERMISSION_SET);
    }
    return u;
  }

  /**
   * @description Provisions a Standard-licence user WITHOUT the permset, for
   *              USER_MODE-denial negative-path tests. Wrapped in
   *              `System.runAs(adminUser)` for the same MIXED_DML reason
   *              documented on `provisionEngagementUser`.
   * @param lastName Distinguishing last name.
   * @return The provisioned User without permset assignment.
   */
  public static User provisionUnauthorizedUser(String lastName) {
    User u = buildBaseUser(lastName);
    System.runAs(getAdminUser()) {
      Database.insert(u, AccessLevel.SYSTEM_MODE);
    }
    return u;
  }

  /**
   * @description Retrieves the latest-created User with the supplied LastName.
   *              Use the same `lastName` passed to `provisionEngagementUser`.
   */
  public static User getProvisionedUser(String lastName) {
    return [
      SELECT Id, Username
      FROM User
      WHERE LastName = :lastName
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }

  // ─── Cross-user record sharing ────────────────────────────────────────────

  /**
   * @description Shares each record in `records` with every user in `users` at
   *              the supplied access level. The right `*Share` SObject is
   *              chosen per parent SObjectType (`AccountShare`, `ContactShare`,
   *              `OpportunityShare`, generic `RowCause` for everything else).
   *              Inserts are batched into a single DML and run inside
   *              `System.runAs(adminUser)` to clear the MIXED_DML guard that
   *              tends to bite tests which provision Users then immediately
   *              share records to them.
   *
   *              Use case: persona-coverage tests that seed records as one
   *              persona but then assert across multiple personas, under
   *              OWD-Private orgs (dwood_z + Zelis production). Without
   *              explicit shares the non-owning personas can't see the
   *              records at all, and a `WITH USER_MODE` SOQL returns empty —
   *              which masquerades as a "permset-broken" symptom when the
   *              real cause is sharing.
   *
   *              `accessLevel` is the field-level `*AccessLevel` value
   *              ('Read' or 'Edit'); the method maps that to the per-object
   *              field name (`AccountAccessLevel`, `OpportunityAccessLevel`,
   *              `ContactAccessLevel`, `AccessLevel` for generic shares).
   *
   * @param records    Parent records to share. All in one call must share the
   *                   same SObjectType to keep the per-call share-row shape
   *                   uniform.
   * @param users      Users to grant access to.
   * @param accessLevel `'Read'` or `'Edit'`.
   */
  public static void shareRecordsToUsers(
    List<SObject> records,
    List<User> users,
    String accessLevel
  ) {
    if (
      records == null ||
      records.isEmpty() ||
      users == null ||
      users.isEmpty()
    ) {
      return;
    }
    Schema.SObjectType sot = records[0].getSObjectType();
    String typeName = String.valueOf(sot);
    List<SObject> shares = new List<SObject>();

    for (SObject rec : records) {
      for (User u : users) {
        SObject share = buildShareRow(typeName, rec.Id, u.Id, accessLevel);
        if (share != null) {
          shares.add(share);
        }
      }
    }

    if (shares.isEmpty()) {
      return;
    }

    System.runAs(getAdminUser()) {
      // allOrNone=false so partial duplicates (e.g. existing share rows from
      // an earlier call) don't fail the whole batch. Test seeding is
      // additive; duplicate-share-row failures are expected and benign.
      Database.insert(shares, false);
    }
  }

  /**
   * @description Builds the right *Share SObject for the parent record type.
   *              Returns null for SObject types that don't have a manual
   *              Share table (master-detail children, setup objects, etc.),
   *              which is the test-seeding signal to skip rather than throw.
   */
  private static SObject buildShareRow(
    String typeName,
    Id parentId,
    Id userId,
    String accessLevel
  ) {
    if (typeName == 'Account') {
      return new AccountShare(
        AccountId = parentId,
        UserOrGroupId = userId,
        AccountAccessLevel = accessLevel,
        OpportunityAccessLevel = accessLevel,
        CaseAccessLevel = accessLevel
      );
    }
    if (typeName == 'Contact') {
      return new ContactShare(
        ContactId = parentId,
        UserOrGroupId = userId,
        ContactAccessLevel = accessLevel
      );
    }
    if (typeName == 'Opportunity') {
      return new OpportunityShare(
        OpportunityId = parentId,
        UserOrGroupId = userId,
        OpportunityAccessLevel = accessLevel
      );
    }
    // For everything else (custom objects with OWD Private + manual sharing
    // enabled), the share SObject is `<Object>__Share` and the parent FK is
    // `ParentId`. Resolved via dynamic SObject build; returns null if the
    // share SObject doesn't exist (object lacks manual sharing).
    String shareName = typeName.endsWith('__c')
      ? typeName.substring(0, typeName.length() - 3) + '__Share'
      : typeName + 'Share';
    Schema.DescribeSObjectResult d = Schema.getGlobalDescribe()
      .get(shareName)
      ?.getDescribe();
    if (d == null) {
      return null;
    }
    SObject share = d.getSObjectType().newSObject();
    share.put('ParentId', parentId);
    share.put('UserOrGroupId', userId);
    share.put('AccessLevel', accessLevel);
    return share;
  }

  // ─── World seeding ────────────────────────────────────────────────────────

  /**
   * @description Inserts the canonical UHC world and returns a SeededWorld
   *              pointer to every Id the tests need. Caller is expected to be
   *              inside `System.runAs(engagementUser)` so the inserts respect
   *              USER_MODE and the world ends up owned by the test user.
   * @return SeededWorld holding every seeded record Id.
   */
  public static SeededWorld seedUhcWorld() {
    return seedUhcWorldBulk(0, 0);
  }

  /**
   * @description Seeds the canonical UHC world PLUS `extraContacts` additional
   *              Contacts each with `touchesPerExtraContact` Touches. Useful for
   *              200-record governor-limit stress tests.
   * @param extraContacts Number of additional Contacts to seed beyond the 4
   *                      canonical ones.
   * @param touchesPerExtraContact Touches per extra Contact.
   */
  public static SeededWorld seedUhcWorldBulk(
    Integer extraContacts,
    Integer touchesPerExtraContact
  ) {
    SeededWorld w = new SeededWorld();

    // dwood_z baseline: the Zelis-owned trigger handlers (Account, Contact,
    // Opportunity) require pre-existing dependencies (record types, custom
    // settings, Jira-push config) that MI's seeded world does not provide.
    // Disable all process automation for the duration of the test transaction
    // so MI tests exercise MI behaviour, not Zelis trigger plumbing.
    disableAllProcessAutomation();

    Account acct = new Account(Name = ACCOUNT_NAME);
    Database.insert(acct, AccessLevel.SYSTEM_MODE);
    w.accountId = acct.Id;

    Contact sarah = newContactRecord(
      acct.Id,
      'Sarah',
      'Johnson',
      'Chief Financial Officer',
      SARAH_EMAIL
    );
    Contact mike = newContactRecord(
      acct.Id,
      'Mike',
      'Chen',
      'VP Engineering',
      MIKE_EMAIL
    );
    Contact lisa = newContactRecord(
      acct.Id,
      'Lisa',
      'Patel',
      'Director Network',
      LISA_EMAIL
    );
    Contact tom = newContactRecord(
      acct.Id,
      'Tom',
      'Davis',
      'Chief Revenue Officer',
      TOM_EMAIL
    );
    List<Contact> contacts = new List<Contact>{ sarah, mike, lisa, tom };
    Database.insert(contacts, AccessLevel.SYSTEM_MODE);

    w.contactIdsByLastName = new Map<String, Id>{
      'Johnson' => sarah.Id,
      'Chen' => mike.Id,
      'Patel' => lisa.Id,
      'Davis' => tom.Id
    };

    Touch_Topic__c netmgt = newTopicRecord(
      'Network Management',
      TOPIC_CODE_NETMGT
    );
    Touch_Topic__c payint = newTopicRecord(
      'Payment Integrity',
      TOPIC_CODE_PAYINT
    );
    Touch_Topic__c claims = newTopicRecord('Claims Editing', TOPIC_CODE_CLAIMS);
    Touch_Topic__c price = newTopicRecord(
      'Price Transparency',
      TOPIC_CODE_PRICE
    );
    Touch_Topic__c oon = newTopicRecord(
      'Out-of-Network Claims',
      TOPIC_CODE_OON
    );
    Database.insert(
      new List<Touch_Topic__c>{ netmgt, payint, claims, price, oon },
      AccessLevel.SYSTEM_MODE
    );

    w.networkTopicId = netmgt.Id;
    w.topicIdsByCode = new Map<String, Id>{
      TOPIC_CODE_NETMGT => netmgt.Id,
      TOPIC_CODE_PAYINT => payint.Id,
      TOPIC_CODE_CLAIMS => claims.Id,
      TOPIC_CODE_PRICE => price.Id,
      TOPIC_CODE_OON => oon.Id
    };

    // dwood_z baseline: OpportunityTriggerHandler.splitOpportunitiesByRecordType
    // (called from after-insert) NPEs when RecordTypeId is null. Resolve a
    // non-PEProvider record type at runtime so the trigger short-circuits on
    // the record-type switch (no PEProviderOpportunityImpl side effects) and
    // the seeded Opportunity passes through cleanly. Falls back to no
    // RecordTypeId in orgs where Opportunity has none configured.
    // Opportunity_Name_Descriptor__c satisfies an active dwood_z VR; harmless
    // in any other org because the field is custom to this org.
    Opportunity opp = new Opportunity(
      Name = OPP_NAME,
      AccountId = acct.Id,
      StageName = 'Proposal/Quote',
      CloseDate = Date.today().addDays(30),
      Touch_Topic__c = netmgt.Id,
      Opportunity_Name_Descriptor__c = 'Test'
    );
    Id genericOppRecordTypeId = resolveNonPEProviderOpportunityRecordTypeId();
    if (genericOppRecordTypeId != null) {
      opp.RecordTypeId = genericOppRecordTypeId;
    }
    Database.insert(opp, AccessLevel.SYSTEM_MODE);
    w.opportunityId = opp.Id;

    OpportunityContactRole mikeOcr = new OpportunityContactRole(
      OpportunityId = opp.Id,
      ContactId = mike.Id,
      Role = 'Technical Buyer'
    );
    OpportunityContactRole tomOcr = new OpportunityContactRole(
      OpportunityId = opp.Id,
      ContactId = tom.Id,
      Role = 'Executive Sponsor',
      IsPrimary = true
    );
    Database.insert(
      new List<OpportunityContactRole>{ mikeOcr, tomOcr },
      AccessLevel.SYSTEM_MODE
    );
    w.mikeChenOcrId = mikeOcr.Id;

    // BUG: AccountContactRelation.IsDirect is not writable at all in this
    // org's API version — both insert AND update throw SObjectException.
    // Result: the fixture cannot seed a "consultant" Contact with
    // IsDirect=false. ACR rows still seed as IsDirect=true (the implicit
    // primary-account relation) so isAcr=true assertions work; isConsultant
    // assertions do not. Flagged for David Wood.
    try {
      AccountContactRelation directAcr = new AccountContactRelation(
        AccountId = acct.Id,
        ContactId = lisa.Id,
        Roles = 'Business User'
      );
      Database.insert(directAcr, AccessLevel.SYSTEM_MODE);
      w.lisaPatelAcrId = directAcr.Id;
    } catch (Exception e) {
      Logger.warn(
        'Indirect ACR seed failed: ' + e.getMessage(),
        'EngagementTestFixtures',
        'seedUhcWorld'
      );
    }

    w.touchIds = new List<Id>();
    List<Engagement_Touch__c> baselineTouches = buildBaselineTouches(
      acct.Id,
      sarah.Id,
      mike.Id,
      lisa.Id,
      tom.Id,
      netmgt.Id
    );

    if (extraContacts != null && extraContacts > 0) {
      List<Contact> bulkContacts = new List<Contact>();
      for (Integer i = 0; i < extraContacts; i++) {
        bulkContacts.add(
          newContactRecord(
            acct.Id,
            'Bulk',
            'Contact' + i,
            'Tester',
            'bulk' + i + '@uhc.example.com'
          )
        );
      }
      Database.insert(bulkContacts, AccessLevel.SYSTEM_MODE);
      DateTime base = Datetime.now();
      Integer perContact = touchesPerExtraContact == null
        ? 1
        : touchesPerExtraContact;
      for (Contact c : bulkContacts) {
        for (Integer j = 0; j < perContact; j++) {
          baselineTouches.add(
            newTouchRecord(
              acct.Id,
              c.Id,
              netmgt.Id,
              'Bulk Asset ' + j,
              'Download',
              base.addMinutes(-1 * (10 + j))
            )
          );
        }
      }
    }

    Database.insert(baselineTouches, AccessLevel.SYSTEM_MODE);
    for (Engagement_Touch__c t : baselineTouches) {
      w.touchIds.add(t.Id);
    }

    return w;
  }

  /**
   * @description Re-fetches the seeded world from the database. Use inside
   *              individual test methods (TestSetup runs in its own transaction
   *              and the ids aren't available across method boundaries).
   */
  public static SeededWorld lookupWorld() {
    SeededWorld w = new SeededWorld();
    Account acct = [
      SELECT Id
      FROM Account
      WHERE Name = :ACCOUNT_NAME
      LIMIT 1
    ];
    w.accountId = acct.Id;

    Opportunity opp = [
      SELECT Id
      FROM Opportunity
      WHERE Name = :OPP_NAME
      LIMIT 1
    ];
    w.opportunityId = opp.Id;

    w.contactIdsByLastName = new Map<String, Id>();
    for (Contact c : [
      SELECT Id, LastName
      FROM Contact
      WHERE AccountId = :acct.Id
    ]) {
      w.contactIdsByLastName.put(c.LastName, c.Id);
    }

    w.topicIdsByCode = new Map<String, Id>();
    for (Touch_Topic__c t : [SELECT Id, External_Code__c FROM Touch_Topic__c]) {
      w.topicIdsByCode.put(t.External_Code__c, t.Id);
    }
    w.networkTopicId = w.topicIdsByCode.get(TOPIC_CODE_NETMGT);

    w.touchIds = new List<Id>();
    for (Engagement_Touch__c t : [
      SELECT Id
      FROM Engagement_Touch__c
      WHERE Account__c = :acct.Id
    ]) {
      w.touchIds.add(t.Id);
    }
    return w;
  }

  // ─── Individual builders ──────────────────────────────────────────────────

  public static Contact newContact(
    Id accountId,
    String first,
    String last,
    String email
  ) {
    return newContactRecord(accountId, first, last, 'Tester', email);
  }

  public static Engagement_Touch__c newTouch(
    Id accountId,
    Id contactId,
    Id topicId,
    String externalId
  ) {
    Engagement_Touch__c t = newTouchRecord(
      accountId,
      contactId,
      topicId,
      'Network Pricing Whitepaper',
      'Download',
      Datetime.now().addMinutes(-30)
    );
    t.External_Id__c = externalId;
    return t;
  }

  /**
   * @description Builds (does not insert) an aged Touch with `Occurred_At__c`
   *              set to N days ago. Used by decay-batch tests.
   */
  public static Engagement_Touch__c newAgedTouch(
    Id accountId,
    Id contactId,
    Id topicId,
    Integer ageDays
  ) {
    return newTouchRecord(
      accountId,
      contactId,
      topicId,
      'Aged Asset',
      'Download',
      Datetime.now().addDays(-1 * ageDays)
    );
  }

  public static Opportunity_Engagement_Signal__c newSignal(
    Id touchId,
    Id oppId,
    Id contactId,
    Decimal confidence
  ) {
    return new Opportunity_Engagement_Signal__c(
      Engagement_Touch__c = touchId,
      Opportunity__c = oppId,
      Contact__c = contactId,
      Confidence__c = confidence,
      Match_Path__c = 'Account'
    );
  }

  public static Engagement_Dismissal__c newDismissal(
    Id contactId,
    Id oppId,
    Id accountId
  ) {
    return new Engagement_Dismissal__c(
      Contact__c = contactId,
      Opportunity__c = oppId,
      Account__c = accountId,
      Dismissed_At__c = System.now()
    );
  }

  // ─── Process automation guard ─────────────────────────────────────────────

  /**
   * @description Upserts the org-default Process_Automation_Switch__c so the
   *              Zelis-owned trigger handlers (Account, Contact, Opportunity,
   *              AccountContactRelation, etc.) short-circuit during MI tests.
   *              MI does not depend on those handlers; they short-circuit on
   *              dwood_z because their pre-existing fixture data (record
   *              types, Jira config, etc.) isn't present in MI's seeded world.
   *
   *              Also injects an empty Jira_Push_Object__mdt cache override
   *              into JiraPushService so the after-insert path doesn't query
   *              the CMDT (which is not guaranteed to be deployed/queryable
   *              in every org, e.g. dwood_z's minimal-fixture state). An
   *              empty override makes `isActive` return false for every
   *              SObject, so `publish` early-returns without throwing.
   *
   *              Call this first from any helper that inserts standard objects.
   *              Idempotent.
   */
  public static void disableAllProcessAutomation() {
    // Wrap the non-setup DML inside System.runAs(adminUser) so test classes
    // that call this BEFORE provisioning a User (the typical pattern) don't
    // hit MIXED_DML_OPERATION on the subsequent User insert. The runAs block
    // resets the per-transaction setup/non-setup DML guard.
    System.runAs(getAdminUser()) {
      Process_Automation_Switch__c sw = Process_Automation_Switch__c.getOrgDefaults();
      if (sw == null || sw.Id == null) {
        sw = new Process_Automation_Switch__c();
      }
      sw.All_Process_Disabled__c = true;
      upsert sw;
    }
    // Static-field assignment (no DML) — safe to run outside runAs.
    JiraPushService.configCacheOverride = new Map<String, Jira_Push_Object__mdt>();
  }

  // ─── Settings ─────────────────────────────────────────────────────────────

  /**
   * @description Inserts/updates the org-default Engagement_Settings__c record
   *              with the given decay window. Idempotent.
   */
  public static void seedSettings(Integer decayDays, Integer activeWindowDays) {
    Engagement_Settings__c s = Engagement_Settings__c.getOrgDefaults();
    if (s == null || s.Id == null) {
      s = new Engagement_Settings__c();
    }
    s.Signal_Decay_Days__c = decayDays;
    s.Active_Window_Days__c = activeWindowDays;
    upsert s;
  }

  // ─── Fake IDs ─────────────────────────────────────────────────────────────

  public static Id fakeTouchId() {
    return Utilities.getFakeId(Engagement_Touch__c.SObjectType);
  }

  public static Id fakeContactId() {
    return Utilities.getFakeId(Contact.SObjectType);
  }

  public static Id fakeOpportunityId() {
    return Utilities.getFakeId(Opportunity.SObjectType);
  }

  public static Id fakeSignalId() {
    return Utilities.getFakeId(Opportunity_Engagement_Signal__c.SObjectType);
  }

  public static Id fakeAccountId() {
    return Utilities.getFakeId(Account.SObjectType);
  }

  // ─── Picklist mapping ─────────────────────────────────────────────────────

  /**
   * @description Maps the LWC-friendly Touch_Type__c label (Page/Form/Event)
   *              to the wire-friendly Source_Event_Type__c value (Page View /
   *              Form Submission / Event Attendance).
   */
  public static String mapToSourceEvent(String touchType) {
    if (touchType == 'Page') {
      return 'Page View';
    }
    if (touchType == 'Form') {
      return 'Form Submission';
    }
    if (touchType == 'Event') {
      return 'Event Attendance';
    }
    return touchType;
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  private static User buildBaseUser(String lastName) {
    Profile standard = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    Integer rand = Crypto.getRandomInteger();
    return new User(
      ProfileId = standard.Id,
      LastName = lastName,
      Email = 'engfix+' + rand + '@test.example.com',
      Username = 'engfix' + rand + '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'engfix',
      TimeZoneSidKey = 'America/Los_Angeles',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US'
    );
  }

  /**
   * @description Returns an active System Administrator User for use inside
   *              `System.runAs(...)` blocks that perform setup-object DML
   *              (User, PermissionSetAssignment). Mirrors the private helper
   *              in `TestFactory.cls`; duplicated here only because
   *              `TestFactory.getAdminUser` is `private`. If `TestFactory`
   *              ever exposes it publicly, replace this with the call.
   */
  private static User getAdminUser() {
    return [
      SELECT Id
      FROM User
      WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE
      LIMIT 1
    ];
  }

  /**
   * @description Returns the Id of the first active Opportunity record type
   *              whose DeveloperName is not `PE_Provider_Opportunity`. The
   *              Zelis OpportunityTriggerHandler branches on
   *              `PE_Provider_Opportunity` and calls
   *              PEProviderOpportunityImpl.onAfterInsert which has its own
   *              dependencies the MI fixture does not satisfy. Picking any
   *              other active record type lets the trigger short-circuit
   *              on the record-type switch. Returns null if no suitable
   *              record type exists, in which case the caller can choose
   *              to skip the RecordTypeId binding entirely.
   */
  private static Id resolveNonPEProviderOpportunityRecordTypeId() {
    Schema.DescribeSObjectResult oppDescribe = Opportunity.SObjectType.getDescribe();
    for (Schema.RecordTypeInfo info : oppDescribe.getRecordTypeInfos()) {
      if (
        info.isActive() &&
        !info.isMaster() &&
        info.getDeveloperName() != 'PE_Provider_Opportunity'
      ) {
        return info.getRecordTypeId();
      }
    }
    return null;
  }

  private static void assignPermset(Id userId, String name) {
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :name
      LIMIT 1
    ];
    Database.insert(
      new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id),
      AccessLevel.SYSTEM_MODE
    );
  }

  private static Contact newContactRecord(
    Id accountId,
    String first,
    String last,
    String title,
    String email
  ) {
    return new Contact(
      FirstName = first,
      LastName = last,
      Title = title,
      Email = email,
      AccountId = accountId
    );
  }

  private static Touch_Topic__c newTopicRecord(String topicName, String code) {
    return new Touch_Topic__c(
      Name = topicName,
      Topic_Name__c = topicName,
      External_Code__c = code
    );
  }

  private static Engagement_Touch__c newTouchRecord(
    Id accountId,
    Id contactId,
    Id topicId,
    String assetName,
    String touchType,
    DateTime occurred
  ) {
    return new Engagement_Touch__c(
      Account__c = accountId,
      Contact__c = contactId,
      Topic__c = topicId,
      Asset_Name__c = assetName,
      Touch_Type__c = touchType,
      Source_Event_Type__c = mapToSourceEvent(touchType),
      Source_System__c = 'Manual',
      Processing_Status__c = 'Processed',
      Resolution_Status__c = 'Resolved',
      Is_Active__c = true,
      Occurred_At__c = occurred,
      External_Id__c = 'EXT-' + Crypto.getRandomInteger()
    );
  }

  private static List<Engagement_Touch__c> buildBaselineTouches(
    Id accountId,
    Id sarahId,
    Id mikeId,
    Id lisaId,
    Id tomId,
    Id networkTopicId
  ) {
    DateTime now = Datetime.now();
    List<Engagement_Touch__c> touches = new List<Engagement_Touch__c>();

    // Sarah's 3-download repeat cluster on the same whitepaper.
    for (Integer i = 0; i < 3; i++) {
      touches.add(
        newTouchRecord(
          accountId,
          sarahId,
          networkTopicId,
          'Network Pricing Whitepaper',
          'Download',
          now.addMinutes(-30 - (i * 10))
        )
      );
    }

    // Mike Chen — 3 distinct touches.
    touches.add(
      newTouchRecord(
        accountId,
        mikeId,
        networkTopicId,
        'Architecture Webinar',
        'Webinar',
        now.addMinutes(-90)
      )
    );
    touches.add(
      newTouchRecord(
        accountId,
        mikeId,
        networkTopicId,
        'API Reference',
        'Page',
        now.addMinutes(-120)
      )
    );
    touches.add(
      newTouchRecord(
        accountId,
        mikeId,
        networkTopicId,
        'Demo Request Form',
        'Form',
        now.addMinutes(-60)
      )
    );

    // Lisa Patel — 3 consultant evaluations.
    touches.add(
      newTouchRecord(
        accountId,
        lisaId,
        networkTopicId,
        'Vendor Comparison Sheet',
        'Download',
        now.addMinutes(-150)
      )
    );
    touches.add(
      newTouchRecord(
        accountId,
        lisaId,
        networkTopicId,
        'Pricing Benchmark Report',
        'Download',
        now.addMinutes(-180)
      )
    );
    touches.add(
      newTouchRecord(
        accountId,
        lisaId,
        networkTopicId,
        'Industry Analyst Brief',
        'Page',
        now.addMinutes(-200)
      )
    );

    // Tom Davis — 3 exec touches.
    touches.add(
      newTouchRecord(
        accountId,
        tomId,
        networkTopicId,
        'Executive Briefing',
        'Event',
        now.addMinutes(-300)
      )
    );
    touches.add(
      newTouchRecord(
        accountId,
        tomId,
        networkTopicId,
        'CRO Roundtable',
        'Event',
        now.addMinutes(-400)
      )
    );
    touches.add(
      newTouchRecord(
        accountId,
        tomId,
        networkTopicId,
        'Quarterly Newsletter',
        'Page',
        now.addMinutes(-500)
      )
    );

    return touches;
  }

  // ─── Result type ──────────────────────────────────────────────────────────

  /**
   * @description Pointer to every Id seeded in `seedUhcWorld`. Callers
   *              retrieve via `lookupWorld()` inside individual test methods.
   */
  public class SeededWorld {
    public Id accountId;
    public Id opportunityId;
    public Id networkTopicId;
    public Id mikeChenOcrId;
    public Id lisaPatelAcrId;
    public Map<String, Id> contactIdsByLastName;
    public Map<String, Id> topicIdsByCode;
    public List<Id> touchIds;

    public Id contactByLastName(String lastName) {
      return contactIdsByLastName == null
        ? null
        : contactIdsByLastName.get(lastName);
    }

    public Id topicByCode(String code) {
      return topicIdsByCode == null ? null : topicIdsByCode.get(code);
    }
  }
}
