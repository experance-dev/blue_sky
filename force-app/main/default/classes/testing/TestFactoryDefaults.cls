/*
 * Copyright (c) 2020-2026 David Wood
 * Licensed under the MIT License — see LICENSE in the repo root.
 * Source: <https://github.com/experance-dev/salesforce-utilities>
 */
/**
 * @description Default field-value sets for every SObject type used in tests.
 *              Inner-class names follow the convention `[ObjectName]Defaults` and
 *              `TestFactory.createSObject(sObj)` auto-discovers them by reflection.
 *              Custom-object suffixes (`__c`, `__`) are stripped before the lookup
 *              so a defaults class for `Engagement_Touch__c` would be named
 *              `Engagement_TouchDefaults`. A named variant (for example
 *              `OpportunityWithAccountDefaults`) lets callers reach a different
 *              defaults shape for the same SObjectType.
 *
 *              Composition lives in the defaults: a defaults class that needs a
 *              parent record should call `TestFactory.createSObject(...)` itself,
 *              so improvements to `AccountDefaults` propagate automatically to
 *              every child defaults class that hangs off it.
 *
 *              This file is the Wave A skeleton. The inner classes return empty
 *              maps so the TestFactory entry points compile and exercise the
 *              reflection path, and Wave B will fill each defaults class with the
 *              field values needed to satisfy the active validation rules in the
 *              receiving org.
 * @group Testing
 * @author David Wood
 * @since December 2020
 * @last May 2026 — initial port into Zelis engagement-attribution worktree
 */
@IsTest
public without sharing class TestFactoryDefaults {
  // TODO: Wave B — build Account defaults to satisfy active validation rules.
  public class AccountDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{};
    }
  }

  // TODO: Wave B — build Contact defaults to satisfy active validation rules.
  public class ContactDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{};
    }
  }

  /**
   * @description Contact defaults variant that composes a default Account
   *              via `TestFactory.createSObject(Account)` and points
   *              `Contact.AccountId` at it. Use this when a test needs a
   *              Contact wired to a parent Account in a single call.
   */
  public class ContactWithAccountDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      Account parent = (Account) TestFactory.createSObject(new Account(), true);
      return new Map<Schema.SObjectField, Object>{
        Contact.AccountId => parent.Id
      };
    }
  }

  // TODO: Wave B — build Opportunity defaults to satisfy active validation rules.
  public class OpportunityDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{};
    }
  }

  // TODO: Wave B — build User defaults to satisfy active validation rules.
  public class UserDefaults implements TestFactory.FieldDefaults {
    public Map<Schema.SObjectField, Object> getFieldDefaults() {
      return new Map<Schema.SObjectField, Object>{};
    }
  }
}
