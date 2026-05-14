/**
 * @description Identity-resolution service for inbound engagement touches.
 *              For each `Engagement_Touch__c`, attempts to bind the touch to
 *              a Salesforce Contact (preferred) or Lead by matching
 *              `Email_At_Touch__c` against Contact.Email then Lead.Email.
 *              Mutates the input list in place — sets
 *              `Contact__c` / `Lead__c` / `Account__c` / `Resolution_Status__c`.
 *
 *              Bulkified: at most two SOQL queries regardless of input size —
 *              one for Contacts, one for Leads. Email comparison is
 *              case-insensitive: callers ingest emails verbatim, this service
 *              lowercases for keying. Salesforce's Email field is itself
 *              case-insensitive at the index layer, so the `IN :emails` bind
 *              matches all casings of the source email.
 *
 *              Resolution semantics:
 *              - Exactly one Contact match → `Resolved`, populate Contact + Account.
 *              - >1 Contact match → `Ambiguous`, no Contact/Account binding.
 *              - 0 Contact matches, exactly one Lead match → `Resolved`,
 *                populate Lead (Account/Contact remain null until the Lead
 *                converts; see `LeadEngagementReparentHandler`).
 *              - >1 Lead match → `Ambiguous`.
 *              - 0 Contact + 0 Lead → `NoMatch` (eligible for human review).
 *              - Blank email → `NoMatch` (defensive — REST endpoint normally
 *                rejects these before they reach this service).
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
public with sharing class IdentityResolutionService {
  // ─── Constants ────────────────────────────────────────────────────────────

  private static final String STATUS_RESOLVED = 'Resolved';
  private static final String STATUS_AMBIGUOUS = 'Ambiguous';
  private static final String STATUS_NO_MATCH = 'NoMatch';
  private static final String CLASS_NAME = 'IdentityResolutionService';

  // ─── Public surface ───────────────────────────────────────────────────────

  /**
   * @description Resolves Contact / Lead / Account references for every
   *              touch in the supplied list. Mutates each record in place
   *              and returns void — this method is intended to be invoked
   *              from `EngagementInboundRest` immediately before the upsert.
   *
   *              Bulkified to two SOQL queries (Contact + Lead) regardless
   *              of input size. Touches with blank email are flagged
   *              `NoMatch` without contributing to the query bind set.
   * @param touches The touch records to resolve (mutated in place; safe
   *                to pass an empty or null list — both short-circuit).
   */
  public static void resolveAll(List<Engagement_Touch__c> touches) {
    if (touches == null || touches.isEmpty()) {
      return;
    }
    Set<String> emails = collectLowerCasedEmails(touches);
    if (emails.isEmpty()) {
      markAllNoMatch(touches);
      return;
    }

    Map<String, List<Contact>> contactsByEmail = queryContactsByEmail(emails);
    Map<String, List<Lead>> leadsByEmail = queryLeadsByEmail(emails);

    for (Engagement_Touch__c t : touches) {
      applyResolution(t, contactsByEmail, leadsByEmail);
    }
  }

  // ─── Private — input shaping ──────────────────────────────────────────────

  private static Set<String> collectLowerCasedEmails(
    List<Engagement_Touch__c> touches
  ) {
    Set<String> emails = new Set<String>();
    for (Engagement_Touch__c t : touches) {
      if (String.isNotBlank(t.Email_At_Touch__c)) {
        emails.add(t.Email_At_Touch__c.toLowerCase());
      }
    }
    return emails;
  }

  private static void markAllNoMatch(List<Engagement_Touch__c> touches) {
    for (Engagement_Touch__c t : touches) {
      t.Resolution_Status__c = STATUS_NO_MATCH;
    }
  }

  // ─── Private — queries ────────────────────────────────────────────────────

  private static Map<String, List<Contact>> queryContactsByEmail(
    Set<String> emails
  ) {
    Map<String, List<Contact>> byEmail = new Map<String, List<Contact>>();
    for (Contact c : [
      SELECT Id, Email, AccountId
      FROM Contact
      WHERE Email IN :emails
      WITH USER_MODE
    ]) {
      String key = (c.Email == null) ? null : c.Email.toLowerCase();
      if (key == null) {
        continue;
      }
      if (!byEmail.containsKey(key)) {
        byEmail.put(key, new List<Contact>());
      }
      byEmail.get(key).add(c);
    }
    return byEmail;
  }

  private static Map<String, List<Lead>> queryLeadsByEmail(Set<String> emails) {
    Map<String, List<Lead>> byEmail = new Map<String, List<Lead>>();
    for (Lead l : [
      SELECT Id, Email, IsConverted
      FROM Lead
      WHERE Email IN :emails AND IsConverted = FALSE
      WITH USER_MODE
    ]) {
      String key = (l.Email == null) ? null : l.Email.toLowerCase();
      if (key == null) {
        continue;
      }
      if (!byEmail.containsKey(key)) {
        byEmail.put(key, new List<Lead>());
      }
      byEmail.get(key).add(l);
    }
    return byEmail;
  }

  // ─── Private — per-record resolution ──────────────────────────────────────

  private static void applyResolution(
    Engagement_Touch__c t,
    Map<String, List<Contact>> contactsByEmail,
    Map<String, List<Lead>> leadsByEmail
  ) {
    if (String.isBlank(t.Email_At_Touch__c)) {
      t.Resolution_Status__c = STATUS_NO_MATCH;
      return;
    }
    String key = t.Email_At_Touch__c.toLowerCase();

    // Contact precedence: a known Contact always wins over a Lead.
    List<Contact> contactMatches = contactsByEmail.get(key);
    if (contactMatches != null && !contactMatches.isEmpty()) {
      if (contactMatches.size() == 1) {
        t.Contact__c = contactMatches[0].Id;
        t.Account__c = contactMatches[0].AccountId;
        t.Resolution_Status__c = STATUS_RESOLVED;
      } else {
        t.Resolution_Status__c = STATUS_AMBIGUOUS;
      }
      return;
    }

    List<Lead> leadMatches = leadsByEmail.get(key);
    if (leadMatches != null && !leadMatches.isEmpty()) {
      if (leadMatches.size() == 1) {
        t.Lead__c = leadMatches[0].Id;
        t.Resolution_Status__c = STATUS_RESOLVED;
      } else {
        t.Resolution_Status__c = STATUS_AMBIGUOUS;
      }
      return;
    }

    t.Resolution_Status__c = STATUS_NO_MATCH;
  }
}
