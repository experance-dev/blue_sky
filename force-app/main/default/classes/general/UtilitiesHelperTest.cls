/**
 * @description Test coverage for the UtilitiesHelper class.
 *
 * @group General
 * @see UtilitiesHelper
 *
 * @author David Wood
 * @since June 2024
 * @last May 2026 — Wave 6 conformance
 */
@isTest
public without sharing class UtilitiesHelperTest {
  @TestSetup
  static void makeData() {
    TestFactory.createMinAccessUser(true);
  }

  @isTest
  static void testCreateDynamicIdMap() {
    List<Account> accounts = new List<Account>();
    accounts.add(
      (Account) TestFactory.createSObject(
        new Account(Name = 'Acme', BillingStreet = '123 Main St'),
        false
      )
    );
    accounts.add(
      (Account) TestFactory.createSObject(
        new Account(Name = 'Globex', BillingStreet = '456 Oak Rd'),
        false
      )
    );
    insert accounts;

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Map<Id, Account> accountMap = (Map<Id, Account>) UtilitiesHelper.createDynamicIdMap(
        'Account',
        'Id',
        accounts
      );
      Assert.areEqual(
        2,
        accountMap.size(),
        'There should be 2 accounts in the map'
      );
      Assert.areEqual(
        accounts[0].Id,
        accountMap.get(accounts[0].Id).Id,
        'The first account should be in the map'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateDynamicStringMap() {
    List<Account> accounts = new List<Account>();
    accounts.add(
      (Account) TestFactory.createSObject(
        new Account(Name = 'Acme', BillingStreet = '123 Main St'),
        false
      )
    );
    accounts.add(
      (Account) TestFactory.createSObject(
        new Account(Name = 'Globex', BillingStreet = '456 Oak Rd'),
        false
      )
    );
    insert accounts;

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Map<String, Account> accountMap = (Map<String, Account>) UtilitiesHelper.createDynamicStringMap(
        'Account',
        'BillingStreet',
        accounts
      );
      Assert.areEqual(
        2,
        accountMap.size(),
        'There should be 2 accounts in the map'
      );
      Assert.areEqual(
        accounts[0].BillingStreet,
        accountMap.get(accounts[0].BillingStreet).BillingStreet,
        'The first account should be in the map'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateDynamicIdListMap() {
    // In-memory grouping assertion — no DML needed. The template carries the
    // shared AccountId so every cloned Contact inherits the same parent and
    // the resulting Map<Id, List<Contact>> has exactly one key. Setting it
    // on the template (not in defaults) keeps the parent intent visible at
    // the call site and avoids side effects in the shared defaults class.
    Id sharedAccountId = TestFactory.getFakeId(Account.SObjectType);
    Contact template = new Contact(AccountId = sharedAccountId);
    List<Contact> contacts = (List<Contact>) TestFactory.createSObjectList(
      template,
      3,
      'TestFactoryDefaults.ContactWithAccountDefaults',
      false
    );

    Test.startTest();
    System.runAs(TestFactory.getMinAccessUser()) {
      Map<Id, List<Contact>> contactMap = UtilitiesHelper.createDynamicIdListMap(
        'Contact',
        'AccountId',
        contacts
      );
      Assert.areEqual(1, contactMap.size(), 'There should be 1 account Id key');
      Assert.areEqual(
        3,
        contactMap.get(sharedAccountId).size(),
        'There should be 3 contacts for the first account'
      );
    }
    Test.stopTest();
  }
}
