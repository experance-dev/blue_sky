/**
 * @description Persona-aware User provisioning helper scoped to the Engagement
 *              Attribution (Marketing Influence) feature. Wraps the existing
 *              `EngagementTestFixtures.provisionEngagementUser` / `provisionUnauthorizedUser`
 *              primitives with a named-persona vocabulary that lets one test
 *              method exercise the same behaviour across multiple personas via
 *              `System.runAs` — the persona-coverage pattern.
 *
 *              The single-test-method-multi-persona shape (instead of one test
 *              method per persona) keeps the assertion contract uniform — if
 *              an assertion drifts, it drifts for every persona simultaneously
 *              and the offending change is obvious at code-review time. It also
 *              halves the number of @TestSetup re-runs needed for persona-fan
 *              coverage on a feature with N personas.
 *
 *              Persona keys map onto MI's OWD-Private functional permset ladder:
 *
 *                'mi_view'        — Additional_Permissions_Marketing_Influence_View
 *                'mi_power_user'  — Additional_Permissions_Marketing_Influence_Power_User
 *                'mi_admin'       — Additional_Permissions_Marketing_Influence_Admin
 *                'mi_integration' — Additional_Permissions_Marketing_Influence_Integration
 *                'no_perm'        — Standard User profile, no MI permset (negative-path)
 *
 *              Lives under `classes/engagement/` rather than `classes/testing/`
 *              because the persona vocabulary is MI-feature-specific. A future
 *              cross-feature equivalent would live in its own feature folder
 *              (or be generalised once a second consumer materialises).
 *
 * @group   Engagement Attribution
 * @author  David Wood
 * @since   May 2026
 */
@IsTest
public with sharing class PersonaTestFactory {
  // ─── Persona keys (public for test-side switch / case readability) ─────────

  public static final String VIEW = 'mi_view';
  public static final String POWER_USER = 'mi_power_user';
  public static final String ADMIN = 'mi_admin';
  public static final String INTEGRATION = 'mi_integration';
  public static final String NO_PERM = 'no_perm';

  // ─── Permset map (private) ────────────────────────────────────────────────

  private static final Map<String, String> PERMSET_BY_PERSONA = new Map<String, String>{
    VIEW => 'Additional_Permissions_Marketing_Influence_View',
    POWER_USER => 'Additional_Permissions_Marketing_Influence_Power_User',
    ADMIN => 'Additional_Permissions_Marketing_Influence_Admin',
    INTEGRATION => 'Additional_Permissions_Marketing_Influence_Integration'
  };

  // ─── Public API ───────────────────────────────────────────────────────────

  /**
   * @description Provisions a Standard-licence User with the permset that maps
   *              to the supplied persona key. The User is persisted in
   *              SYSTEM_MODE inside `System.runAs(adminUser)` to avoid the
   *              setup-object MIXED_DML pitfall (User insert + PermissionSetAssignment
   *              insert cannot follow non-setup DML). The `no_perm` persona
   *              provisions the User without assigning any MI permset, which
   *              is the negative-path baseline.
   *
   *              LastName is composed as `Persona_<key>` so multiple personas
   *              co-exist inside the same `@TestSetup` and `userFor` is callable
   *              repeatedly without colliding usernames (a random suffix on the
   *              email/username takes care of that). On second-and-subsequent
   *              calls within the same test class, `userFor` re-uses the
   *              already-provisioned User instead of re-inserting — keeps
   *              setup-DML usage well clear of governor limits when a test
   *              cycles through 4-5 personas.
   *
   * @param personaKey One of the constants on this class.
   * @return The provisioned User, freshly queried (or cached from the first
   *         provisioning call for this persona in this transaction).
   */
  public static User userFor(String personaKey) {
    if (personaKey == null) {
      throw new EngagementException(
        'PersonaTestFactory.userFor: personaKey is required.'
      );
    }
    if (personaKey != NO_PERM && !PERMSET_BY_PERSONA.containsKey(personaKey)) {
      throw new EngagementException(
        'PersonaTestFactory.userFor: unknown personaKey "' +
          personaKey +
          '". Expected one of mi_view / mi_power_user / mi_admin / mi_integration / no_perm.'
      );
    }

    String lastName = lastNameFor(personaKey);

    // Cheap pre-check — re-use any existing User the running transaction
    // already provisioned under this persona, so repeated userFor() calls
    // inside one test method don't burn setup-DML cycles.
    List<User> existing = [
      SELECT Id, Username
      FROM User
      WHERE LastName = :lastName
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0];
    }

    if (personaKey == NO_PERM) {
      return EngagementTestFixtures.provisionUnauthorizedUser(lastName);
    }

    // For permsetted personas, provision then re-assign to the persona's
    // permset. `provisionEngagementUser` defaults to the Integration permset
    // (the fixture-tier baseline); if the requested persona is anything else,
    // overwrite the assignment to point at the requested permset.
    User u = EngagementTestFixtures.provisionEngagementUser(lastName);
    String requestedPermset = PERMSET_BY_PERSONA.get(personaKey);
    if (requestedPermset != EngagementTestFixtures.PERMISSION_SET) {
      reassignPermset(u.Id, requestedPermset);
    }
    return u;
  }

  /**
   * @description Convenience wrapper — returns the persona's User and runs the
   *              supplied callback inside `System.runAs(user)`. Callback shape
   *              is a no-arg lambda; tests that need the user instance can
   *              call `userFor(...)` directly. Trade-off: Apex closures don't
   *              capture the test's local variables, so heavy use of this
   *              wrapper inside data-driven loops would require either
   *              `@TestVisible` static state or per-persona setup duplication.
   *              For the common case (1-2 persona assertions per test method),
   *              the inline `System.runAs(PersonaTestFactory.userFor(persona))`
   *              call site is clearer.
   *
   *              NOTE: not implemented in v1 — kept here as a header-only
   *              placeholder to anchor a future enhancement. Tests should use
   *              the explicit `System.runAs(PersonaTestFactory.userFor(...))`
   *              pattern (see `*AcrossPersonas` examples in the test suite).
   */
  // public static void runAs(String personaKey, PersonaCallback cb) { ... }

  // ─── Private helpers ──────────────────────────────────────────────────────

  /**
   * @description Drops any existing MI permset assignment from the User and
   *              assigns the requested one. Lets `userFor(POWER_USER)` work
   *              even though the underlying `provisionEngagementUser` always
   *              starts the user on the Integration permset.
   */
  private static void reassignPermset(Id userId, String permsetName) {
    List<PermissionSetAssignment> existing = [
      SELECT Id, PermissionSet.Name
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :userId
        AND PermissionSet.Name LIKE 'Additional_Permissions_Marketing_Influence_%'
    ];
    PermissionSet target = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :permsetName
      LIMIT 1
    ];

    System.runAs(getAdminUser()) {
      if (!existing.isEmpty()) {
        Database.delete(existing, AccessLevel.SYSTEM_MODE);
      }
      Database.insert(
        new PermissionSetAssignment(
          AssigneeId = userId,
          PermissionSetId = target.Id
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
  }

  private static User getAdminUser() {
    return [
      SELECT Id
      FROM User
      WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE
      LIMIT 1
    ];
  }

  private static String lastNameFor(String personaKey) {
    return 'Persona_' + personaKey;
  }
}
