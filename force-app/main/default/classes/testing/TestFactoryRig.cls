/*
 * Copyright (c) 2020-2026 David Wood
 * Licensed under the MIT License — see LICENSE in the repo root.
 * Source: <https://github.com/experance-dev/salesforce-utilities>
 */
/**
 * @description Domain-agnostic test-rig scaffold. A rig assembles a full
 *              scenario graph for a feature — for example an Account with
 *              two related Contacts, an Opportunity in a known stage, and
 *              the supporting engagement records — through a single static
 *              entry point named after the scenario (`createXxxRig(...)`).
 *              Tests then receive the assembled graph in one call instead
 *              of duplicating the wiring across `@TestSetup` blocks.
 *
 *              Rigs compose `TestFactory.createSObject(...)` and the relevant
 *              `TestFactoryDefaults` inner classes, so any fix to a defaults
 *              class propagates to every rig that hangs off it. Keep the
 *              static entry-point pattern stable so callers do not need to
 *              change as the rig's internals evolve.
 *
 *              This file is the Wave A skeleton: it carries the class
 *              declaration only. Wave C will introduce the engagement-
 *              attribution rig and any other Sales-Cloud rigs needed by
 *              the test suite.
 * @group Testing
 * @author David Wood
 * @since December 2020
 * @last May 2026 — initial port into Zelis engagement-attribution worktree
 */
@IsTest
public without sharing class TestFactoryRig {
  // TODO: Wave C — build createEngagementAttributionRig() and any generic
  // Sales-Cloud rig methods needed by the engagement-attribution test suite.
}
