/**
 * @description Routes resolved `Engagement_Touch__c` events into
 *              `Opportunity_Engagement_Signal__c` records by applying the
 *              priority-ordered `Touch_Routing_Rule__mdt` set. One signal
 *              per (touch, opportunity) — the highest-priority rule that
 *              matches wins.
 *
 *              Bulkified across many touches: at most six SOQL queries
 *              regardless of input size (touches, opportunities, OCR, ACR,
 *              existing signals, routing rules). Per-touch / per-opp loops
 *              are O(n*m) over hash-map lookups — no nested queries.
 *
 *              Idempotent: existing signals keyed by (touch, opp, match path)
 *              are loaded up-front and skipped, so re-firing the trigger or
 *              re-routing the same touch twice creates no duplicates.
 *
 *              NoMatch / Ambiguous touches are deliberately filtered out —
 *              they require human triage before any signal is fair game.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 * @last 2026-05-13 — Q11 wave 2: PATH_CONSULTANT now reads Contact.Is_Consultant__c (populated by admin flow). PATH_ACR still gates on AccountContactRelation.IsDirect=false (Q10).
 */
public with sharing class EngagementSignalRouter {
  // ─── Constants ────────────────────────────────────────────────────────────

  private static final String CLASS_NAME = 'EngagementSignalRouter';
  private static final String STATUS_RESOLVED = 'Resolved';
  private static final String PATH_OCR = 'OCR';
  private static final String PATH_ACR = 'ACR';
  private static final String PATH_ACCOUNT = 'Account';
  private static final String PATH_DOMAIN = 'Domain';
  private static final String PATH_CONSULTANT = 'Consultant';

  // Intent ordering for `meetsIntent`: Low < Medium < High.
  private static final Map<String, Integer> INTENT_RANK = new Map<String, Integer>{
    'Low' => 1,
    'Medium' => 2,
    'High' => 3
  };

  // ─── Public surface ───────────────────────────────────────────────────────

  /**
   * @description Routes a batch of newly resolved touch ids into engagement
   *              signals. Idempotent across re-invocations.
   * @param touchIds The set of `Engagement_Touch__c` Ids to route. Null or
   *                 empty short-circuits.
   */
  public static void routeTouches(Set<Id> touchIds) {
    if (touchIds == null || touchIds.isEmpty()) {
      return;
    }

    List<Engagement_Touch__c> touches = queryResolvedTouches(touchIds);
    if (touches.isEmpty()) {
      return;
    }

    Set<Id> accountIds = collectAccountIds(touches);
    Set<Id> contactIds = collectContactIds(touches);

    Map<Id, List<Opportunity>> opportunitiesByAccount = queryOpenOpportunitiesByAccount(
      accountIds
    );
    Set<Id> allOpportunityIds = collectOpportunityIds(opportunitiesByAccount);

    Map<String, Boolean> ocrPresence = queryOcrPresence(
      contactIds,
      allOpportunityIds
    );
    Map<String, AccountContactRelation> acrByKey = queryAcrByKey(
      contactIds,
      accountIds
    );
    Set<Id> consultantContactIds = queryConsultantContactIds(contactIds);
    Set<String> existingSignalKeys = queryExistingSignalKeys(touchIds);
    List<Touch_Routing_Rule__mdt> rules = TouchRoutingRulesSelector.selectActiveOrderedByPriority();

    List<Opportunity_Engagement_Signal__c> toInsert = buildSignals(
      touches,
      opportunitiesByAccount,
      ocrPresence,
      acrByKey,
      consultantContactIds,
      existingSignalKeys,
      rules
    );

    if (toInsert.isEmpty()) {
      return;
    }
    insertSignals(toInsert);
  }

  // ─── Query helpers ────────────────────────────────────────────────────────

  private static List<Engagement_Touch__c> queryResolvedTouches(
    Set<Id> touchIds
  ) {
    return [
      SELECT
        Id,
        Contact__c,
        Account__c,
        Topic__c,
        Persona__c,
        Intent_Level__c,
        Touch_Type__c,
        Resolution_Status__c
      FROM Engagement_Touch__c
      WHERE Id IN :touchIds AND Resolution_Status__c = :STATUS_RESOLVED
      WITH USER_MODE
    ];
  }

  private static Map<Id, List<Opportunity>> queryOpenOpportunitiesByAccount(
    Set<Id> accountIds
  ) {
    Map<Id, List<Opportunity>> byAccount = new Map<Id, List<Opportunity>>();
    if (accountIds.isEmpty()) {
      return byAccount;
    }
    for (Opportunity opp : [
      SELECT Id, AccountId, Touch_Topic__c
      FROM Opportunity
      WHERE AccountId IN :accountIds AND IsClosed = FALSE
      WITH USER_MODE
    ]) {
      if (!byAccount.containsKey(opp.AccountId)) {
        byAccount.put(opp.AccountId, new List<Opportunity>());
      }
      byAccount.get(opp.AccountId).add(opp);
    }
    return byAccount;
  }

  private static Map<String, Boolean> queryOcrPresence(
    Set<Id> contactIds,
    Set<Id> opportunityIds
  ) {
    Map<String, Boolean> presence = new Map<String, Boolean>();
    if (contactIds.isEmpty() || opportunityIds.isEmpty()) {
      return presence;
    }
    for (OpportunityContactRole ocr : [
      SELECT Id, ContactId, OpportunityId, Role
      FROM OpportunityContactRole
      WHERE OpportunityId IN :opportunityIds AND ContactId IN :contactIds
      WITH USER_MODE
    ]) {
      presence.put(contactOppKey(ocr.ContactId, ocr.OpportunityId), true);
    }
    return presence;
  }

  private static Map<String, AccountContactRelation> queryAcrByKey(
    Set<Id> contactIds,
    Set<Id> accountIds
  ) {
    Map<String, AccountContactRelation> byKey = new Map<String, AccountContactRelation>();
    if (contactIds.isEmpty() || accountIds.isEmpty()) {
      return byKey;
    }
    for (AccountContactRelation acr : [
      SELECT Id, ContactId, AccountId, IsDirect, Roles
      FROM AccountContactRelation
      WHERE AccountId IN :accountIds AND ContactId IN :contactIds
      WITH USER_MODE
    ]) {
      byKey.put(contactAccountKey(acr.ContactId, acr.AccountId), acr);
    }
    return byKey;
  }

  /**
   * @description Returns the subset of `contactIds` flagged as consultants
   *              via the `Is_Consultant__c` boolean on Contact (populated by
   *              admin flow). Used by `PATH_CONSULTANT` rule matching.
   *              Empty input short-circuits to an empty set.
   *
   *              Dynamic SOQL with `Database.queryWithBinds` so this is safe
   *              in orgs where `Is_Consultant__c` hasn't been deployed yet
   *              (the field is gated by a Schema describe check; absent → no
   *              consultants matched, no parse error).
   *
   *              The guard also checks `isAccessible()` so orgs where the
   *              field exists but the running profile lacks FLS (e.g. a
   *              freshly-cloned admin profile) short-circuit cleanly rather
   *              than blowing up the AfterInsert with a USER_MODE column
   *              parse error.
   */
  private static Set<Id> queryConsultantContactIds(Set<Id> contactIds) {
    Set<Id> consultants = new Set<Id>();
    if (contactIds == null || contactIds.isEmpty()) {
      return consultants;
    }
    Map<String, Schema.SObjectField> contactFields = Contact.SObjectType.getDescribe()
      .fields.getMap();
    if (!contactFields.containsKey('is_consultant__c')) {
      return consultants;
    }
    if (!contactFields.get('is_consultant__c').getDescribe().isAccessible()) {
      return consultants;
    }
    String soql =
      'SELECT Id FROM Contact ' +
      'WHERE Id IN :contactIds AND Is_Consultant__c = TRUE';
    Map<String, Object> binds = new Map<String, Object>{
      'contactIds' => contactIds
    };
    for (
      Contact c : (List<Contact>) Database.queryWithBinds(
        soql,
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      consultants.add(c.Id);
    }
    return consultants;
  }

  private static Set<String> queryExistingSignalKeys(Set<Id> touchIds) {
    Set<String> keys = new Set<String>();
    for (Opportunity_Engagement_Signal__c sig : [
      SELECT Engagement_Touch__c, Opportunity__c, Match_Path__c
      FROM Opportunity_Engagement_Signal__c
      WHERE Engagement_Touch__c IN :touchIds
      WITH USER_MODE
    ]) {
      keys.add(
        signalKey(
          sig.Engagement_Touch__c,
          sig.Opportunity__c,
          sig.Match_Path__c
        )
      );
    }
    return keys;
  }

  // ─── Input shaping ────────────────────────────────────────────────────────

  private static Set<Id> collectAccountIds(List<Engagement_Touch__c> touches) {
    Set<Id> ids = new Set<Id>();
    for (Engagement_Touch__c t : touches) {
      if (t.Account__c != null) {
        ids.add(t.Account__c);
      }
    }
    return ids;
  }

  private static Set<Id> collectContactIds(List<Engagement_Touch__c> touches) {
    Set<Id> ids = new Set<Id>();
    for (Engagement_Touch__c t : touches) {
      if (t.Contact__c != null) {
        ids.add(t.Contact__c);
      }
    }
    return ids;
  }

  private static Set<Id> collectOpportunityIds(
    Map<Id, List<Opportunity>> opportunitiesByAccount
  ) {
    Set<Id> ids = new Set<Id>();
    for (List<Opportunity> opps : opportunitiesByAccount.values()) {
      for (Opportunity opp : opps) {
        ids.add(opp.Id);
      }
    }
    return ids;
  }

  // ─── Routing core ─────────────────────────────────────────────────────────

  private static List<Opportunity_Engagement_Signal__c> buildSignals(
    List<Engagement_Touch__c> touches,
    Map<Id, List<Opportunity>> opportunitiesByAccount,
    Map<String, Boolean> ocrPresence,
    Map<String, AccountContactRelation> acrByKey,
    Set<Id> consultantContactIds,
    Set<String> existingSignalKeys,
    List<Touch_Routing_Rule__mdt> rules
  ) {
    List<Opportunity_Engagement_Signal__c> toInsert = new List<Opportunity_Engagement_Signal__c>();
    Set<String> stagedKeys = new Set<String>();

    for (Engagement_Touch__c t : touches) {
      List<Opportunity> candidateOpps = opportunitiesByAccount.get(
        t.Account__c
      );
      if (candidateOpps == null || candidateOpps.isEmpty()) {
        continue;
      }
      for (Opportunity opp : candidateOpps) {
        Touch_Routing_Rule__mdt winner = findWinningRule(
          t,
          opp,
          ocrPresence,
          acrByKey,
          consultantContactIds,
          rules
        );
        if (winner == null) {
          continue;
        }
        String key = signalKey(t.Id, opp.Id, winner.Match_Path__c);
        if (existingSignalKeys.contains(key) || stagedKeys.contains(key)) {
          continue;
        }
        stagedKeys.add(key);
        toInsert.add(buildSignal(t, opp, winner));
      }
    }
    return toInsert;
  }

  private static Touch_Routing_Rule__mdt findWinningRule(
    Engagement_Touch__c t,
    Opportunity opp,
    Map<String, Boolean> ocrPresence,
    Map<String, AccountContactRelation> acrByKey,
    Set<Id> consultantContactIds,
    List<Touch_Routing_Rule__mdt> rules
  ) {
    for (Touch_Routing_Rule__mdt rule : rules) {
      if (
        ruleMatches(rule, t, opp, ocrPresence, acrByKey, consultantContactIds)
      ) {
        return rule;
      }
    }
    return null;
  }

  /**
   * @description Evaluates a single rule against a (touch, opportunity) pair.
   *              All non-blank constraints must pass for the rule to match.
   */
  private static Boolean ruleMatches(
    Touch_Routing_Rule__mdt rule,
    Engagement_Touch__c t,
    Opportunity opp,
    Map<String, Boolean> ocrPresence,
    Map<String, AccountContactRelation> acrByKey,
    Set<Id> consultantContactIds
  ) {
    if (rule.Require_Same_Account__c == true && t.Account__c != opp.AccountId) {
      return false;
    }
    if (
      rule.Require_Topic_Match__c == true &&
      (t.Topic__c == null ||
      t.Topic__c != opp.Touch_Topic__c)
    ) {
      return false;
    }
    if (
      String.isNotBlank(rule.Persona_Filter__c) &&
      t.Persona__c != rule.Persona_Filter__c
    ) {
      return false;
    }
    if (
      String.isNotBlank(rule.Touch_Type_Filter__c) &&
      t.Touch_Type__c != rule.Touch_Type_Filter__c
    ) {
      return false;
    }
    if (
      String.isNotBlank(rule.Min_Intent_Level__c) &&
      !meetsIntent(t.Intent_Level__c, rule.Min_Intent_Level__c)
    ) {
      return false;
    }
    return matchPathSatisfied(
      rule,
      t,
      opp,
      ocrPresence,
      acrByKey,
      consultantContactIds
    );
  }

  /**
   * @description Match-path-specific structural preconditions. `Account`
   *              and `Domain` paths impose no extra requirement here — the
   *              same-account + topic constraints above already gate them.
   */
  private static Boolean matchPathSatisfied(
    Touch_Routing_Rule__mdt rule,
    Engagement_Touch__c t,
    Opportunity opp,
    Map<String, Boolean> ocrPresence,
    Map<String, AccountContactRelation> acrByKey,
    Set<Id> consultantContactIds
  ) {
    String path = rule.Match_Path__c;
    if (path == PATH_OCR) {
      Boolean present = ocrPresence.get(contactOppKey(t.Contact__c, opp.Id));
      return present == true;
    }
    if (path == PATH_ACR) {
      // Indirect-only: ACR path represents a contact related to the account
      // through a third party (consultant/broker), not a direct employee.
      AccountContactRelation acrRow = acrByKey.get(
        contactAccountKey(t.Contact__c, t.Account__c)
      );
      return acrRow != null && acrRow.IsDirect == false;
    }
    if (path == PATH_CONSULTANT) {
      // Q11 wave 2: consultant test now reads Contact.Is_Consultant__c (admin
      // flow). Decoupled from ACR structure — a consultant may have no ACR yet
      // and still match this path.
      return t.Contact__c != null &&
        consultantContactIds != null &&
        consultantContactIds.contains(t.Contact__c);
    }
    // PATH_ACCOUNT, PATH_DOMAIN
    return true;
  }

  /**
   * @description Returns true when `touchLevel` meets or exceeds `ruleMin`
   *              on the Low < Medium < High ladder. A blank touch intent
   *              fails any non-blank minimum.
   */
  private static Boolean meetsIntent(String touchLevel, String ruleMin) {
    Integer required = INTENT_RANK.get(ruleMin);
    Integer actual = INTENT_RANK.get(touchLevel);
    if (required == null) {
      return true;
    }
    if (actual == null) {
      return false;
    }
    return actual >= required;
  }

  private static Opportunity_Engagement_Signal__c buildSignal(
    Engagement_Touch__c t,
    Opportunity opp,
    Touch_Routing_Rule__mdt rule
  ) {
    Opportunity_Engagement_Signal__c sig = new Opportunity_Engagement_Signal__c();
    sig.Opportunity__c = opp.Id;
    sig.Engagement_Touch__c = t.Id;
    sig.Contact__c = t.Contact__c;
    sig.Topic__c = t.Topic__c;
    sig.Confidence__c = rule.Confidence__c;
    sig.Match_Path__c = rule.Match_Path__c;
    sig.Dismissed__c = false;
    return sig;
  }

  // ─── DML ──────────────────────────────────────────────────────────────────

  private static void insertSignals(
    List<Opportunity_Engagement_Signal__c> toInsert
  ) {
    try {
      DMLManager.insertAsUser(toInsert);
      Logger.info(
        'Inserted ' + toInsert.size() + ' engagement signals.',
        CLASS_NAME,
        'insertSignals'
      );
    } catch (DmlException e) {
      Logger.error(e.getMessage(), CLASS_NAME, 'insertSignals');
      throw new EngagementException(
        'Failed to insert engagement signals: ' + e.getMessage()
      );
    } catch (Exception e) {
      Logger.error(e.getMessage(), CLASS_NAME, 'insertSignals');
      throw new EngagementException(
        'Unable to insert engagement signals: ' + e.getMessage()
      );
    }
  }

  // ─── Key helpers ──────────────────────────────────────────────────────────

  private static String contactOppKey(Id contactId, Id opportunityId) {
    return String.valueOf(contactId) + '|' + String.valueOf(opportunityId);
  }

  private static String contactAccountKey(Id contactId, Id accountId) {
    return String.valueOf(contactId) + '|' + String.valueOf(accountId);
  }

  private static String signalKey(Id touchId, Id opportunityId, String path) {
    return String.valueOf(touchId) +
      '|' +
      String.valueOf(opportunityId) +
      '|' +
      path;
  }
}
