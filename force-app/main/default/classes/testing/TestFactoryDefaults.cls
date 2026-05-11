/**
 * @description Scratch-org STUB. The real TestFactoryDefaults in the work
 *              org carries per-SObject FieldDefaults inner classes that
 *              reference org-specific fields (Manual_Maintenance_Product__c,
 *              Machine__c, Warranty_*, etc.) that don't exist outside that
 *              org. Empty here so the scratch deploy compiles. Restore the
 *              real implementation before copying back to the work org.
 *
 *              Keeps only the constants TestFactory.cls references at
 *              compile time. Inner FieldDefaults classes are looked up
 *              dynamically by name (Type.forName) so their absence here
 *              just means createSObject returns the input unchanged - no
 *              defaults applied. Fine for the DML-less tests in this
 *              branch which set only the fields each scenario needs.
 *
 * @group Testing
 *
 * Change Log:
 * | Date       | Ticket   | Author     | Description                                |
 * |------------|----------|------------|--------------------------------------------|
 * | 2026-05-11 | CSI-7162 | David Wood | Scratch-org compile stub - restore at work |
 */
@IsTest
public without sharing class TestFactoryDefaults {
  public static final String TEST_USER_PERMISSION = 'TestUserPermission';
  public static final String DEFAULT_PRODUCT_FAMILY = '';
  public static final String DEFAULT_WARRANTY_PRODUCT = '';
}
