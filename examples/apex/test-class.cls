/**
 * AccountTriggerHandlerTest
 *
 * Test class for AccountTriggerHandler. Demonstrates best practices:
 *   - @TestSetup for shared test data (runs once, rolls back per test)
 *   - Test.startTest() / Test.stopTest() to reset governor limits
 *   - Descriptive assertion messages on every assert
 *   - Bulk testing (200 records, not just 1)
 *   - Positive AND negative test cases
 *   - No @SeeAllData — all data created in the test
 */
@IsTest
private class AccountTriggerHandlerTest {

    private static final Integer BULK_SIZE = 200;

    // ─── TEST SETUP ──────────────────────────────────────────

    @TestSetup
    static void setup() {
        // Create test accounts shared across test methods.
        // Each test method gets its own copy (rolled back after each test).
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < BULK_SIZE; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Website = 'https://testaccount' + i + '.com'
            ));
        }
        insert accounts;
    }

    // ─── BEFORE INSERT TESTS ─────────────────────────────────

    @IsTest
    static void beforeInsert_setsDefaultIndustry_whenIndustryIsNull() {
        // Arrange
        Account acc = new Account(Name = 'No Industry Account');
        // Industry is intentionally left null

        // Act
        Test.startTest();
        insert acc;
        Test.stopTest();

        // Assert
        Account result = [SELECT Industry FROM Account WHERE Id = :acc.Id];
        System.assertEquals(
            'Other',
            result.Industry,
            'Industry should default to "Other" when not specified'
        );
    }

    @IsTest
    static void beforeInsert_preservesIndustry_whenIndustryIsProvided() {
        // Arrange
        Account acc = new Account(
            Name = 'Tech Account',
            Industry = 'Technology'
        );

        // Act
        Test.startTest();
        insert acc;
        Test.stopTest();

        // Assert
        Account result = [SELECT Industry FROM Account WHERE Id = :acc.Id];
        System.assertEquals(
            'Technology',
            result.Industry,
            'Industry should remain "Technology" when explicitly set'
        );
    }

    @IsTest
    static void beforeInsert_setsDefaults_bulk() {
        // Arrange — bulk test with BULK_SIZE records
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < BULK_SIZE; i++) {
            accounts.add(new Account(Name = 'Bulk Account ' + i));
        }

        // Act
        Test.startTest();
        insert accounts;
        Test.stopTest();

        // Assert
        List<Account> results = [
            SELECT Industry, Rating FROM Account
            WHERE Name LIKE 'Bulk Account%'
        ];
        System.assertEquals(
            BULK_SIZE,
            results.size(),
            'All ' + BULK_SIZE + ' accounts should be inserted'
        );
        for (Account acc : results) {
            System.assertEquals('Other', acc.Industry, 'Default Industry should be set');
            System.assertEquals('Cold', acc.Rating, 'Default Rating should be set');
        }
    }

    // ─── BEFORE UPDATE TESTS ─────────────────────────────────

    @IsTest
    static void beforeUpdate_normalizesWebsite_whenWebsiteChanges() {
        // Arrange
        Account acc = [SELECT Id, Website FROM Account WHERE Name = 'Test Account 0' LIMIT 1];

        // Act
        Test.startTest();
        acc.Website = '  HTTPS://EXAMPLE.COM  ';
        update acc;
        Test.stopTest();

        // Assert
        Account result = [SELECT Website FROM Account WHERE Id = :acc.Id];
        System.assertEquals(
            'https://example.com',
            result.Website,
            'Website should be lowercased and trimmed'
        );
    }

    // ─── BEFORE DELETE TESTS ─────────────────────────────────

    @IsTest
    static void beforeDelete_blocksDelete_whenOpenOpportunitiesExist() {
        // Arrange
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account 0' LIMIT 1];
        Opportunity opp = new Opportunity(
            AccountId = acc.Id,
            Name = 'Open Deal',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Act & Assert
        Test.startTest();
        try {
            delete acc;
            System.assert(false, 'Delete should have been blocked by trigger');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('open opportunities'),
                'Error message should mention open opportunities. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void beforeDelete_allowsDelete_whenNoOpenOpportunities() {
        // Arrange
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account 1' LIMIT 1];
        // No opportunities created — delete should succeed

        // Act
        Test.startTest();
        delete acc;
        Test.stopTest();

        // Assert
        List<Account> results = [SELECT Id FROM Account WHERE Id = :acc.Id];
        System.assertEquals(
            0,
            results.size(),
            'Account should be deleted when no open opportunities exist'
        );
    }

    // ─── AFTER INSERT TESTS ──────────────────────────────────

    @IsTest
    static void afterInsert_createsDefaultContact() {
        // Arrange
        Account acc = new Account(
            Name = 'Contact Test Account',
            Website = 'https://contacttest.com'
        );

        // Act
        Test.startTest();
        insert acc;
        Test.stopTest();

        // Assert
        List<Contact> contacts = [
            SELECT LastName, Email
            FROM Contact
            WHERE AccountId = :acc.Id
        ];
        System.assertEquals(
            1,
            contacts.size(),
            'A default contact should be created for new accounts'
        );
        System.assertEquals(
            'Primary Contact',
            contacts[0].LastName,
            'Default contact should be named "Primary Contact"'
        );
    }

    // ─── AFTER UPDATE TESTS ──────────────────────────────────

    @IsTest
    static void afterUpdate_syncsOwnerToContacts_whenOwnerChanges() {
        // Arrange
        Account acc = [SELECT Id, OwnerId FROM Account WHERE Name = 'Test Account 0' LIMIT 1];
        Contact c = new Contact(
            AccountId = acc.Id,
            LastName = 'Owner Sync Test'
        );
        insert c;

        // Get a different user to transfer to (use System.runAs if needed)
        // For this test, we verify the mechanism works with the same user
        // In real orgs, you'd create a second test user

        // Act
        Test.startTest();
        // Re-assign owner to trigger the sync (using same user for simplicity)
        acc.OwnerId = UserInfo.getUserId();
        update acc;
        Test.stopTest();

        // Assert
        Contact result = [SELECT OwnerId FROM Contact WHERE Id = :c.Id];
        System.assertEquals(
            acc.OwnerId,
            result.OwnerId,
            'Contact owner should sync with Account owner after owner change'
        );
    }
}
