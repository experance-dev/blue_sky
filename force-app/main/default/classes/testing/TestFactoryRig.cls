/*
 * Copyright (c) 2020-2026 David Wood
 * Licensed under the MIT License — see LICENSE in the repo root.
 * Source: <https://github.com/experance-dev/salesforce-utilities>
 */
/**
 * @description Scratch-org STUB. The real TestFactoryRig in the work org
 *              builds org-specific test scaffolding (Quote_Program__c,
 *              Machine__c, Program_Rate__c, etc.) that don't exist
 *              outside that org's metadata. Empty here so the scratch
 *              deploy compiles. Restore the real implementation before
 *              copying back to the work org.
 *
 * @group Testing
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                |
 * |------------|----------|------------|--------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Scratch-org compile stub - restore at work |
 */
@IsTest
@SuppressWarnings('PMD.EmptyStatementBlock, PMD.ApexDoc')
public class TestFactoryRig {
  // Intentionally empty - real implementation lives in the work org.
}
