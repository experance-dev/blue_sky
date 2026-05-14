/**
 * @description Tests for `EngagementInboundRest`. Initialises
 *              `RestContext.request` / `RestContext.response` directly
 *              (no HTTP layer in Apex tests) and invokes the static
 *              `@HttpPost` entry point. Covers the six contract scenarios
 *              from the Phase 2 spec: happy path, no-match email, missing
 *              required field, duplicate-external-id upsert, topic resolved
 *              by external code, ambiguous resolution.
 * @group Engagement Attribution
 * @see EngagementInboundRest
 * @author David Wood
 * @since May 2026
 */
@IsTest
private class EngagementInboundRestTest {
  // ─── Constants ────────────────────────────────────────────────────────────

  private static final String PERMISSION_SET = 'Additional_Permissions_Marketing_Influence_Integration';
  private static final String USER_LAST_NAME = 'EngageRestTest';
  private static final String TOPIC_CODE = 'TOPIC_NETWORK_MGMT';
  private static final String SARAH_EMAIL = 'sarah.johnson@uhc.example.com';
  private static final String MIKE_EMAIL = 'mike.chen@uhc.example.com';

  // ─── Setup ────────────────────────────────────────────────────────────────

  /**
   * @description Provisions the Integration-style test user and a small
   *              seed world: one Account, two Contacts, one Touch_Topic
   *              with the `TOPIC_NETWORK_MGMT` external code.
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
   * @description Happy path: two events both match known Contacts by email,
   *              both upsert with `Resolution_Status = Resolved` and Contact
   *              populated, response counts reflect the outcome.
   */
  @IsTest
  static void ingestHappyPathInsertsResolvedTouches() {
    System.runAs(getTestUser()) {
      String body = JSON.serialize(
        new Map<String, Object>{
          'events' => new List<Object>{
            buildEventMap('HS-001', SARAH_EMAIL),
            buildEventMap('HS-002', MIKE_EMAIL)
          }
        }
      );
      setupRestContext(body);

      Test.startTest();
      EngagementInboundRest.InboundResult result = EngagementInboundRest.ingest();
      Test.stopTest();

      Assert.areEqual(2, result.received, 'Expected 2 events received.');
      Assert.areEqual(2, result.resolved, 'Expected both events resolved.');
      Assert.areEqual(0, result.errored, 'Expected no errors.');

      List<Engagement_Touch__c> rows = [
        SELECT Id, Resolution_Status__c, Contact__c, External_Id__c
        FROM Engagement_Touch__c
        WHERE External_Id__c IN ('HS-001', 'HS-002')
      ];
      Assert.areEqual(2, rows.size(), 'Expected two rows persisted.');
      for (Engagement_Touch__c r : rows) {
        Assert.areEqual(
          'Resolved',
          r.Resolution_Status__c,
          'Expected each row marked Resolved.'
        );
        Assert.isNotNull(r.Contact__c, 'Expected Contact populated.');
      }
    }
  }

  /**
   * @description Unknown email goes to `NoMatch` — row still upserts (so
   *              admins can review), Contact is null, processing status flips
   *              to `New`.
   */
  @IsTest
  static void ingestUnknownEmailMarksNoMatch() {
    System.runAs(getTestUser()) {
      String body = JSON.serialize(
        new Map<String, Object>{
          'events' => new List<Object>{
            buildEventMap('HS-NOMATCH', 'stranger@nowhere.example.com')
          }
        }
      );
      setupRestContext(body);

      Test.startTest();
      EngagementInboundRest.InboundResult result = EngagementInboundRest.ingest();
      Test.stopTest();

      Assert.areEqual(1, result.received, 'Expected 1 event received.');
      Assert.areEqual(1, result.noMatch, 'Expected 1 NoMatch count.');

      List<Engagement_Touch__c> rows = [
        SELECT Id, Resolution_Status__c, Processing_Status__c, Contact__c
        FROM Engagement_Touch__c
        WHERE External_Id__c = 'HS-NOMATCH'
      ];
      Assert.areEqual(1, rows.size(), 'Expected the NoMatch row inserted.');
      Assert.areEqual(
        'NoMatch',
        rows[0].Resolution_Status__c,
        'Expected Resolution_Status = NoMatch.'
      );
      Assert.areEqual(
        'New',
        rows[0].Processing_Status__c,
        'Expected Processing_Status = New so admins can triage.'
      );
      Assert.isNull(
        rows[0].Contact__c,
        'Expected Contact lookup left null on NoMatch.'
      );
    }
  }

  /**
   * @description Missing required field (`external_id`) rejects the event
   *              into the errors list — no row is inserted, response
   *              `errored` increments, `errors` carries the message.
   */
  @IsTest
  static void ingestMissingRequiredFieldGoesToErrors() {
    System.runAs(getTestUser()) {
      Map<String, Object> bad = buildEventMap(null, SARAH_EMAIL);
      bad.remove('external_id');
      String body = JSON.serialize(
        new Map<String, Object>{ 'events' => new List<Object>{ bad } }
      );
      setupRestContext(body);

      Test.startTest();
      EngagementInboundRest.InboundResult result = EngagementInboundRest.ingest();
      Test.stopTest();

      Assert.areEqual(1, result.received, 'Expected 1 event received.');
      Assert.areEqual(
        1,
        result.errored,
        'Expected the malformed event counted as errored.'
      );
      Assert.isTrue(
        result.errors.size() >= 1,
        'Expected at least one error message recorded.'
      );

      List<Engagement_Touch__c> rows = [SELECT Id FROM Engagement_Touch__c];
      Assert.areEqual(
        0,
        rows.size(),
        'Expected no rows inserted when the only event was invalid.'
      );
    }
  }

  /**
   * @description Idempotency: posting the same `external_id` twice yields
   *              exactly one row — the second post upserts onto the first.
   */
  @IsTest
  static void ingestDuplicateExternalIdUpserts() {
    System.runAs(getTestUser()) {
      String body = JSON.serialize(
        new Map<String, Object>{
          'events' => new List<Object>{ buildEventMap('HS-DUP', SARAH_EMAIL) }
        }
      );

      Test.startTest();
      setupRestContext(body);
      EngagementInboundRest.ingest();
      setupRestContext(body);
      EngagementInboundRest.ingest();
      Test.stopTest();

      List<Engagement_Touch__c> rows = [
        SELECT Id
        FROM Engagement_Touch__c
        WHERE External_Id__c = 'HS-DUP'
      ];
      Assert.areEqual(
        1,
        rows.size(),
        'Expected exactly one row after re-delivery (upsert on External_Id__c).'
      );
    }
  }

  /**
   * @description Topic resolution by external_code: the seeded
   *              `Touch_Topic__c` with `External_Code__c = TOPIC_NETWORK_MGMT`
   *              must be linked on the resulting `Engagement_Touch__c`.
   */
  @IsTest
  static void ingestTopicResolvedByExternalCode() {
    System.runAs(getTestUser()) {
      Id expectedTopicId = [
        SELECT Id
        FROM Touch_Topic__c
        WHERE External_Code__c = :TOPIC_CODE
        LIMIT 1
      ]
      .Id;

      String body = JSON.serialize(
        new Map<String, Object>{
          'events' => new List<Object>{ buildEventMap('HS-TOPIC', SARAH_EMAIL) }
        }
      );
      setupRestContext(body);

      Test.startTest();
      EngagementInboundRest.ingest();
      Test.stopTest();

      Engagement_Touch__c row = [
        SELECT Topic__c
        FROM Engagement_Touch__c
        WHERE External_Id__c = 'HS-TOPIC'
        LIMIT 1
      ];
      Assert.areEqual(
        expectedTopicId,
        row.Topic__c,
        'Expected Topic__c populated from the external_code lookup.'
      );
    }
  }

  /**
   * @description Ambiguous: two Contacts share an email. The event resolves
   *              to `Ambiguous` with no Contact set so a human can adjudicate.
   */
  @IsTest
  static void ingestAmbiguousMultipleContactsMatch() {
    System.runAs(getTestUser()) {
      // Seed a second Contact with the same email as Sarah Johnson.
      Account acct = [SELECT Id FROM Account LIMIT 1];
      Contact duplicate = new Contact(
        FirstName = 'Sarah',
        LastName = 'Twin',
        Email = SARAH_EMAIL,
        AccountId = acct.Id
      );
      Database.insert(duplicate, AccessLevel.SYSTEM_MODE);

      String body = JSON.serialize(
        new Map<String, Object>{
          'events' => new List<Object>{ buildEventMap('HS-AMBIG', SARAH_EMAIL) }
        }
      );
      setupRestContext(body);

      Test.startTest();
      EngagementInboundRest.InboundResult result = EngagementInboundRest.ingest();
      Test.stopTest();

      Assert.areEqual(
        1,
        result.ambiguous,
        'Expected ambiguous counter to increment.'
      );
      Engagement_Touch__c row = [
        SELECT Resolution_Status__c, Contact__c
        FROM Engagement_Touch__c
        WHERE External_Id__c = 'HS-AMBIG'
        LIMIT 1
      ];
      Assert.areEqual(
        'Ambiguous',
        row.Resolution_Status__c,
        'Expected Resolution_Status = Ambiguous on multi-match.'
      );
      Assert.isNull(
        row.Contact__c,
        'Expected Contact__c null on ambiguous resolution.'
      );
    }
  }

  // ─── New tests (David Wood, 2026-05-12) ───────────────────────────────────

  /**
   * @description Empty request body returns 400 and adds the error to
   *              `result.errors[]`. Covers parseBody empty-body branch.
   */
  @IsTest
  static void ingestEmptyBodyReturns400() {
    System.runAs(getTestUser()) {
      setupRestContext('');
      Test.startTest();
      EngagementInboundRest.InboundResult result = EngagementInboundRest.ingest();
      Test.stopTest();
      Assert.isFalse(
        result.errors.isEmpty(),
        'Expected the errors array populated on empty body.'
      );
      Assert.areEqual(
        400,
        RestContext.response.statusCode,
        'Expected HTTP 400 for empty body.'
      );
    }
  }

  /**
   * @description Null requestBody is treated as empty. Covers the
   *              `req.requestBody == null` guard.
   */
  @IsTest
  static void ingestNullBodyReturns400() {
    System.runAs(getTestUser()) {
      RestRequest req = new RestRequest();
      req.requestURI = '/services/apexrest/engagement/touches/';
      req.httpMethod = 'POST';
      // Intentionally do NOT set requestBody.
      RestContext.request = req;
      RestContext.response = new RestResponse();
      Test.startTest();
      EngagementInboundRest.InboundResult result = EngagementInboundRest.ingest();
      Test.stopTest();
      Assert.isFalse(
        result.errors.isEmpty(),
        'Expected errors when requestBody is null.'
      );
    }
  }

  /**
   * @description Invalid JSON body returns 400 and adds the parse failure to
   *              `result.errors[]`. Covers the JSON.deserialize catch branch.
   */
  @IsTest
  static void ingestInvalidJsonReturns400() {
    System.runAs(getTestUser()) {
      setupRestContext('{not-valid-json');
      Test.startTest();
      EngagementInboundRest.InboundResult result = EngagementInboundRest.ingest();
      Test.stopTest();
      Assert.areEqual(
        400,
        RestContext.response.statusCode,
        'Expected HTTP 400 on invalid JSON.'
      );
      Assert.isFalse(
        result.errors.isEmpty(),
        'Expected errors array populated on invalid JSON.'
      );
    }
  }

  /**
   * @description Event with a blank email goes to the errors array (validation
   *              rejects it before resolution).
   */
  @IsTest
  static void ingestEventWithBlankEmailGoesToErrors() {
    System.runAs(getTestUser()) {
      Map<String, Object> bad = buildEventMap('HS-BLANK', '');
      String body = JSON.serialize(
        new Map<String, Object>{ 'events' => new List<Object>{ bad } }
      );
      setupRestContext(body);
      Test.startTest();
      EngagementInboundRest.InboundResult result = EngagementInboundRest.ingest();
      Test.stopTest();
      Assert.areEqual(
        1,
        result.errored,
        'Expected one validation error for blank email.'
      );
      Assert.isFalse(
        result.errors.isEmpty(),
        'Expected the errors array populated.'
      );
    }
  }

  /**
   * @description Event with a null occurred_at goes to the errors array.
   */
  @IsTest
  static void ingestEventWithNullOccurredAtGoesToErrors() {
    System.runAs(getTestUser()) {
      Map<String, Object> bad = buildEventMap('HS-NOWHEN', SARAH_EMAIL);
      bad.put('occurred_at', null);
      String body = JSON.serialize(
        new Map<String, Object>{ 'events' => new List<Object>{ bad } }
      );
      setupRestContext(body);
      Test.startTest();
      EngagementInboundRest.InboundResult result = EngagementInboundRest.ingest();
      Test.stopTest();
      Assert.areEqual(
        1,
        result.errored,
        'Expected one validation error for null occurred_at.'
      );
    }
  }

  /**
   * @description Unknown topic_external_code lookup returns empty map; the
   *              event still ingests with Topic__c null and a warning logged.
   */
  @IsTest
  static void ingestUnknownTopicCodeLeavesTopicNull() {
    System.runAs(getTestUser()) {
      Map<String, Object> evt = buildEventMap('HS-BAD-TOPIC', SARAH_EMAIL);
      evt.put('topic_external_code', 'COMPLETELY_UNKNOWN');
      String body = JSON.serialize(
        new Map<String, Object>{ 'events' => new List<Object>{ evt } }
      );
      setupRestContext(body);

      Test.startTest();
      EngagementInboundRest.ingest();
      Test.stopTest();

      Engagement_Touch__c row = [
        SELECT Topic__c
        FROM Engagement_Touch__c
        WHERE External_Id__c = 'HS-BAD-TOPIC'
        LIMIT 1
      ];
      Assert.areEqual(
        null,
        row.Topic__c,
        'Expected Topic__c null when topic_external_code does not match.'
      );
    }
  }

  /**
   * @description Bulk: 50 events in one POST → result.received=50 and the
   *              transaction stays within governor limits.
   */
  @IsTest
  static void ingestBulk50EventsRespectsGovernors() {
    System.runAs(getTestUser()) {
      List<Object> events = new List<Object>();
      for (Integer i = 0; i < 50; i++) {
        events.add(buildEventMap('HS-BULK-' + i, SARAH_EMAIL));
      }
      String body = JSON.serialize(
        new Map<String, Object>{ 'events' => events }
      );
      setupRestContext(body);

      Integer queriesBefore = Limits.getQueries();
      Test.startTest();
      EngagementInboundRest.InboundResult result = EngagementInboundRest.ingest();
      Test.stopTest();

      Assert.areEqual(
        50,
        result.received,
        'Expected all 50 events tallied as received.'
      );
      Integer queriesUsed = Limits.getQueries() - queriesBefore;
      Assert.isTrue(
        queriesUsed < 15,
        'Expected query count to stay bounded under bulk; used ' + queriesUsed
      );
    }
  }

  // ─── Test helpers ─────────────────────────────────────────────────────────

  /**
   * @description Initialises `RestContext.request` with the supplied POST body.
   *              Apex tests bypass HTTP entirely — the framework reads the
   *              static `RestContext.request` directly when the resource
   *              method is invoked.
   * @param body Raw JSON string for the POST body.
   */
  private static void setupRestContext(String body) {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/engagement/touches/';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body);
    RestContext.request = req;
    RestContext.response = new RestResponse();
  }

  /**
   * @description Builds a fully-populated event map. Tests pass null for
   *              `externalId` then `remove('external_id')` to exercise the
   *              missing-required-field path.
   */
  private static Map<String, Object> buildEventMap(
    String externalId,
    String email
  ) {
    return new Map<String, Object>{
      'external_id' => externalId,
      'source_system' => 'HubSpot',
      'source_event_type' => 'Download',
      'source_event_id' => '12345',
      'email' => email,
      'occurred_at' => '2026-05-10T14:00:00.000+0000',
      'asset_name' => 'Network Pricing Whitepaper',
      'asset_url' => 'https://zelis.com/whitepaper',
      'topic_external_code' => TOPIC_CODE,
      'campaign_external_id' => null,
      'touch_type' => 'Download',
      'touch_subtype' => 'PDF Download',
      'persona' => 'Executive',
      'intent_level' => 'Medium'
    };
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
      Email = 'engagerest@test.example.com',
      Username = 'engagerest' + Crypto.getRandomInteger() + '@test.example.com',
      CompanyName = 'TEST',
      Title = 'tester',
      Alias = 'engrest',
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

  private static void seedWorld() {
    Account acct = new Account(Name = 'United Healthcare Test');
    Database.insert(acct, AccessLevel.SYSTEM_MODE);

    Contact sarah = new Contact(
      FirstName = 'Sarah',
      LastName = 'Johnson',
      Title = 'CFO',
      Email = SARAH_EMAIL,
      AccountId = acct.Id
    );
    Contact mike = new Contact(
      FirstName = 'Mike',
      LastName = 'Chen',
      Title = 'VP Eng',
      Email = MIKE_EMAIL,
      AccountId = acct.Id
    );
    Database.insert(new List<Contact>{ sarah, mike }, AccessLevel.SYSTEM_MODE);

    Touch_Topic__c topic = new Touch_Topic__c(
      Name = 'Network Management',
      Topic_Name__c = 'Network Management',
      External_Code__c = TOPIC_CODE
    );
    Database.insert(topic, AccessLevel.SYSTEM_MODE);
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
