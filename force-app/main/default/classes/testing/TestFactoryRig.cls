/**
 * @description Test-rig scaffolds that build entire object clusters for
 *              integration-style test setup. The pattern: a rig method
 *              creates a coherent set of related records (Account →
 *              Contact → Opportunity → OpportunityContactRole → …) in
 *              one call, returning a `Map<String, List<SObject>>` keyed
 *              by SObject name so tests can pull whichever pieces they
 *              need without re-discovering relationships.
 *
 *              When to use a rig vs. `TestFactory.createSObject`:
 *                - Single record, no relationships needed → createSObject.
 *                - Cluster of related records with cross-references
 *                  (Opportunity needs Account, OCR needs both) → rig.
 *                - Bulk (N copies of the cluster) for governor-limit
 *                  tests → rig with `numberOfClusters` param.
 *
 *              Pattern reference: Stowers `TestFactoryRig.createOpportunityRig`.
 *              Each rig assumes `TestFactoryDefaults.disableValidationRules()`
 *              has fired in `@TestSetup` — they don't re-flip the switch.
 *
 * @group Testing
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                                                    |
 * |------------|----------|------------|--------------------------------------------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Scratch-org compile stub.                                                      |
 * | 2026-05-12 | CSI-7162 | Boomer     | Replace stub with `createEngagementCluster(N)` rig for MI tests: builds N      |
 * |            |          |            | coherent Account+Contact+PE_Provider_Opportunity clusters so MI integration    |
 * |            |          |            | tests get a populated graph in one call. Returns Map<String, List<SObject>>.   |
 */
@IsTest
public without sharing class TestFactoryRig {
  /**
   * @description Builds `numberOfClusters` independent Account-Contact-
   *              Opportunity clusters wired together. Each cluster:
   *                1 Account (no specific RT — base defaults are safe across
   *                  all Account RTs once `disableValidationRules` is on),
   *                1 Contact on that Account (Email always set per
   *                  `ContactDefaults`),
   *                1 Opportunity on that Account with
   *                  `PE_Provider_Opportunity` record type, qualifying for
   *                  the Jira-push integration,
   *                1 OpportunityContactRole linking Contact to Opportunity
   *                  with role 'Decision Maker' and primary=true so the
   *                  `Opportunity_Contact_Role_not_found` validation rule
   *                  passes once tests advance the Opp past initial creation.
   *
   *              Returns a `Map<String, List<SObject>>` keyed by SObject
   *              API name. Indexes line up across lists: `Account[i]` ↔
   *              `Contact[i]` ↔ `Opportunity[i]` ↔ `OpportunityContactRole[i]`.
   *              Tests assert on relationships by index.
   *
   *              Per `apex-tests.md`: prefer rig-built fixtures over
   *              ad-hoc per-test inserts for any test that needs more
   *              than one related record.
   *
   * @param numberOfClusters Count of clusters to build. Must be > 0.
   * @return `Map<String, List<SObject>>` keyed by 'Account', 'Contact',
   *         'Opportunity', 'OpportunityContactRole'. Lists are
   *         index-aligned across the four keys.
   */
  public static Map<String, List<SObject>> createEngagementCluster(
    Integer numberOfClusters
  ) {
    if (numberOfClusters == null || numberOfClusters <= 0) {
      throw new TestFactoryRigException(
        'createEngagementCluster requires numberOfClusters > 0; got ' +
          numberOfClusters
      );
    }

    // ─── Step 1: build all Accounts in one DML ──────────────────────────────
    List<Account> accounts = (List<Account>) TestFactory.createSObjectList(
      new Account(),
      numberOfClusters,
      'TestFactoryDefaults.AccountDefaults',
      false
    );
    insert accounts;

    // ─── Step 2: build all Contacts wired to their Accounts ─────────────────
    List<Contact> contacts = (List<Contact>) TestFactory.createSObjectList(
      new Contact(),
      numberOfClusters,
      'TestFactoryDefaults.ContactDefaults',
      false
    );
    for (Integer i = 0; i < numberOfClusters; i++) {
      contacts[i].AccountId = accounts[i].Id;
    }
    insert contacts;

    // ─── Step 3: build all PE_Provider_Opportunity Opportunities ────────────
    List<Opportunity> opportunities = (List<Opportunity>) TestFactory.createSObjectList(
      new Opportunity(),
      numberOfClusters,
      'TestFactoryDefaults.OpportunityPEProviderDefaults',
      false
    );
    for (Integer i = 0; i < numberOfClusters; i++) {
      opportunities[i].AccountId = accounts[i].Id;
    }
    insert opportunities;

    // ─── Step 4: build the OCR junction (primary=true for OCR rule) ─────────
    List<OpportunityContactRole> ocrs = new List<OpportunityContactRole>();
    for (Integer i = 0; i < numberOfClusters; i++) {
      ocrs.add(
        new OpportunityContactRole(
          OpportunityId = opportunities[i].Id,
          ContactId = contacts[i].Id,
          Role = 'Decision Maker',
          IsPrimary = true
        )
      );
    }
    insert ocrs;

    return new Map<String, List<SObject>>{
      'Account' => accounts,
      'Contact' => contacts,
      'Opportunity' => opportunities,
      'OpportunityContactRole' => ocrs
    };
  }

  /**
   * @description Custom exception for rig-construction failures. Extends
   *              `Exception` directly (not `UtilitiesModuleException`) — rigs
   *              are test-only; the module-exception hierarchy is for
   *              production code paths.
   */
  public class TestFactoryRigException extends Exception {
  }
}
