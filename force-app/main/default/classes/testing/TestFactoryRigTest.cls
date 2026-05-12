/**
 * @description Tests for `TestFactoryRig`. Default test pattern per
 *              `apex-tests.md`: prefer DML-mocked unit tests. These
 *              tests DO use DML — that's the contract of the rig (it
 *              inserts the cluster). The rig is the small set of tests
 *              we accept DML in because the rig itself is what other
 *              tests delegate to so they can stay DML-free.
 *
 *              `@TestSetup` flips the kill-switch
 *              (`TestFactoryDefaults.disableValidationRules`) so the rig's
 *              inserts don't trip dwood_z's 56 gated validation rules.
 *              The 7 ungated outliers are pre-defended by the per-SObject
 *              defaults the rig uses.
 *
 * @group Testing
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                                                    |
 * |------------|----------|------------|--------------------------------------------------------------------------------|
 * | 2026-05-12 | CSI-7162 | Boomer     | Initial coverage for `createEngagementCluster(N)`: single-cluster sanity,      |
 * |            |          |            | small-bulk relationships, OCR primary-flag, governor-limit bounds, and        |
 * |            |          |            | negative-input throws.                                                         |
 */
@IsTest
private class TestFactoryRigTest {
  @TestSetup
  static void setup() {
    TestFactoryDefaults.disableValidationRules();
  }

  /**
   * @description Single-cluster sanity. Builds 1 cluster, asserts the
   *              return map has exactly the four expected keys, each list
   *              has size 1, and the cross-references line up (Contact.AccountId,
   *              Opportunity.AccountId, OCR.OpportunityId, OCR.ContactId).
   */
  @IsTest
  static void testCreateEngagementClusterBuildsOneFullCluster() {
    Test.startTest();
    Map<String, List<SObject>> graph = TestFactoryRig.createEngagementCluster(1);
    Test.stopTest();

    Assert.areEqual(
      new Set<String>{
        'Account',
        'Contact',
        'Opportunity',
        'OpportunityContactRole'
      },
      graph.keySet(),
      'Rig must return exactly the four expected keys.'
    );
    Assert.areEqual(1, graph.get('Account').size(), 'One Account.');
    Assert.areEqual(1, graph.get('Contact').size(), 'One Contact.');
    Assert.areEqual(1, graph.get('Opportunity').size(), 'One Opportunity.');
    Assert.areEqual(
      1,
      graph.get('OpportunityContactRole').size(),
      'One OCR.'
    );

    Account a = (Account) graph.get('Account')[0];
    Contact c = (Contact) graph.get('Contact')[0];
    Opportunity o = (Opportunity) graph.get('Opportunity')[0];
    OpportunityContactRole ocr = (OpportunityContactRole) graph.get(
      'OpportunityContactRole'
    )[0];

    Assert.areEqual(a.Id, c.AccountId, 'Contact must be on the rig Account.');
    Assert.areEqual(
      a.Id,
      o.AccountId,
      'Opportunity must be on the rig Account.'
    );
    Assert.areEqual(
      o.Id,
      ocr.OpportunityId,
      'OCR must point at the rig Opportunity.'
    );
    Assert.areEqual(c.Id, ocr.ContactId, 'OCR must point at the rig Contact.');
    Assert.isTrue(
      ocr.IsPrimary,
      'OCR must be primary so Opportunity_Contact_Role_not_found rule is happy.'
    );
  }

  /**
   * @description Small-bulk relationship integrity. 5 clusters; each
   *              cluster's records must reference each other by index
   *              (Account[i] ↔ Contact[i] ↔ Opportunity[i] ↔ OCR[i]).
   *              Locks the per-index contract the rig advertises.
   */
  @IsTest
  static void testCreateEngagementClusterBulkIndexAlignment() {
    Test.startTest();
    Map<String, List<SObject>> graph = TestFactoryRig.createEngagementCluster(5);
    Test.stopTest();

    List<Account> accounts = (List<Account>) graph.get('Account');
    List<Contact> contacts = (List<Contact>) graph.get('Contact');
    List<Opportunity> opps = (List<Opportunity>) graph.get('Opportunity');
    List<OpportunityContactRole> ocrs = (List<OpportunityContactRole>) graph.get(
      'OpportunityContactRole'
    );

    Assert.areEqual(5, accounts.size());
    Assert.areEqual(5, contacts.size());
    Assert.areEqual(5, opps.size());
    Assert.areEqual(5, ocrs.size());

    for (Integer i = 0; i < 5; i++) {
      Assert.areEqual(
        accounts[i].Id,
        contacts[i].AccountId,
        'Contact[' + i + '] must be on Account[' + i + '].'
      );
      Assert.areEqual(
        accounts[i].Id,
        opps[i].AccountId,
        'Opportunity[' + i + '] must be on Account[' + i + '].'
      );
      Assert.areEqual(
        opps[i].Id,
        ocrs[i].OpportunityId,
        'OCR[' + i + '] must point at Opportunity[' + i + '].'
      );
      Assert.areEqual(
        contacts[i].Id,
        ocrs[i].ContactId,
        'OCR[' + i + '] must point at Contact[' + i + '].'
      );
    }
  }

  /**
   * @description Governor-limit bounds. The rig uses exactly 4 DML
   *              statements regardless of cluster count (1 per SObject
   *              family). Asserts the rig stays bulk-safe so callers
   *              can use it inside `Test.startTest()` without burning
   *              the DML budget.
   */
  @IsTest
  static void testCreateEngagementClusterUsesFourDmlStatements() {
    Test.startTest();
    Integer dmlBefore = Limits.getDmlStatements();
    TestFactoryRig.createEngagementCluster(10);
    Integer dmlAfter = Limits.getDmlStatements();
    Test.stopTest();

    Assert.areEqual(
      4,
      dmlAfter - dmlBefore,
      'Rig must use exactly 4 DML statements for N clusters (1 per SObject family).'
    );
  }

  /**
   * @description Negative input: zero must throw a typed exception
   *              (not a generic NullPointerException or governor crash).
   */
  @IsTest
  static void testCreateEngagementClusterZeroThrows() {
    Boolean threw = false;
    try {
      TestFactoryRig.createEngagementCluster(0);
    } catch (TestFactoryRig.TestFactoryRigException ex) {
      threw = true;
      Assert.isTrue(
        ex.getMessage().contains('numberOfClusters'),
        'Exception message should reference the bad parameter name.'
      );
    }
    Assert.isTrue(threw, 'Zero clusters must throw TestFactoryRigException.');
  }

  /**
   * @description Negative input: null must also throw.
   */
  @IsTest
  static void testCreateEngagementClusterNullThrows() {
    Boolean threw = false;
    try {
      TestFactoryRig.createEngagementCluster(null);
    } catch (TestFactoryRig.TestFactoryRigException ex) {
      threw = true;
    }
    Assert.isTrue(threw, 'Null clusters must throw TestFactoryRigException.');
  }
}
