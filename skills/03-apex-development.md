# Apex Development

## When this applies

This skill applies when working with **dev/sandbox orgs** where write access is enabled. For production orgs, you can only view Apex metadata — not source code or make changes.

## Code style conventions

### Naming
- **Classes**: PascalCase — `AccountTriggerHandler`, `OpportunityService`
- **Methods**: camelCase — `getActiveAccounts()`, `validateEmail()`
- **Variables**: camelCase — `accountList`, `contactsByAccountId`
- **Constants**: UPPER_SNAKE — `MAX_BATCH_SIZE`, `DEFAULT_RECORD_TYPE`
- **Test classes**: `[ClassName]Test` — `AccountTriggerHandlerTest`
- **Trigger names**: `[Object]Trigger` — `AccountTrigger`, `OpportunityTrigger`

### File organization
- **One trigger per object** — all logic delegates to a handler class
- **Handler classes** separate from service/utility classes
- **Test classes** mirror the class they test

## Trigger pattern

Always use the **one-trigger-per-object** pattern. The trigger itself should contain zero logic — only delegation.

```apex
trigger AccountTrigger on Account (before insert, before update, after insert, after update, before delete, after delete) {
    AccountTriggerHandler handler = new AccountTriggerHandler();
    handler.run();
}
```

The handler class contains all logic, organized by execution context:
```apex
public class AccountTriggerHandler {
    public void run() {
        if (Trigger.isBefore) {
            if (Trigger.isInsert) beforeInsert(Trigger.new);
            if (Trigger.isUpdate) beforeUpdate(Trigger.new, Trigger.oldMap);
            if (Trigger.isDelete) beforeDelete(Trigger.old);
        }
        if (Trigger.isAfter) {
            if (Trigger.isInsert) afterInsert(Trigger.new);
            if (Trigger.isUpdate) afterUpdate(Trigger.new, Trigger.oldMap);
            if (Trigger.isDelete) afterDelete(Trigger.old);
        }
    }
    // ... handler methods
}
```

See `examples/apex/trigger.cls` and `examples/apex/handler-class.cls` for full reference.

## Test class requirements

Every Apex class and trigger needs test coverage. Salesforce requires **75% code coverage** for deployment, but aim for **90%+**.

### Test class structure
```apex
@IsTest
private class MyClassTest {
    @TestSetup
    static void setup() {
        // Create shared test data once
    }

    @IsTest
    static void testMethodName_givenCondition_expectedResult() {
        // Arrange
        // Act
        Test.startTest();
        // ... call the method
        Test.stopTest();
        // Assert
        System.assertEquals(expected, actual, 'Descriptive failure message');
    }
}
```

### Test best practices
- Use `@TestSetup` for data shared across test methods — it runs once and rolls back per method
- Wrap the code under test in `Test.startTest()` / `Test.stopTest()` — this resets governor limits
- **Always include assertion messages** — `System.assertEquals(expected, actual, 'message')`
- Test **bulk operations** — insert 200 records, not just 1
- Test **negative cases** — invalid data, missing fields, boundary conditions
- **Never use `@SeeAllData=true`** unless absolutely necessary (e.g., testing against standard price books)
- Use `System.runAs()` to test with different user permissions

See `examples/apex/test-class.cls` for a full reference.

## Governor limits to watch

When writing or reviewing Apex, watch for these common governor limit issues:

### SOQL in loops (most common issue)
```apex
// BAD — SOQL inside a for loop
for (Account acc : accounts) {
    List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acc.Id];
}

// GOOD — bulk query outside the loop
Map<Id, List<Contact>> contactsByAcct = new Map<Id, List<Contact>>();
for (Contact c : [SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds]) {
    if (!contactsByAcct.containsKey(c.AccountId)) {
        contactsByAcct.put(c.AccountId, new List<Contact>());
    }
    contactsByAcct.get(c.AccountId).add(c);
}
```

### DML in loops
```apex
// BAD
for (Account acc : accounts) {
    update acc;
}

// GOOD
update accounts; // bulk DML
```

### Key limits
- **100 SOQL queries** per synchronous transaction
- **150 DML statements** per transaction
- **10,000 DML rows** per transaction
- **50,000 query rows** per transaction
- **6 MB heap size** (synchronous), **12 MB** (async)
- **10 seconds CPU time** (synchronous), **60 seconds** (async)

## Common Apex patterns

### Null-safe field access
```apex
String email = contact.Email != null ? contact.Email : '';
// Or for related fields:
String accountName = contact.Account?.Name;
```

### Collecting IDs from a list
```apex
Set<Id> accountIds = new Set<Id>();
for (Contact c : contacts) {
    if (c.AccountId != null) {
        accountIds.add(c.AccountId);
    }
}
// Or using a Map shortcut:
Map<Id, Contact> contactMap = new Map<Id, Contact>(contacts);
Set<Id> contactIds = contactMap.keySet();
```

### Building a map from query results
```apex
Map<Id, Account> accountMap = new Map<Id, Account>(
    [SELECT Id, Name, Industry FROM Account WHERE Id IN :accountIds]
);
Account acc = accountMap.get(someAccountId);
```

### Detecting field changes in triggers
```apex
for (Account newAcc : Trigger.new) {
    Account oldAcc = Trigger.oldMap.get(newAcc.Id);
    if (newAcc.OwnerId != oldAcc.OwnerId) {
        // Owner changed — do something
    }
}
```

## Bulk safety rules — ALWAYS follow these

These are non-negotiable. Every piece of Apex you write or review must pass these checks.

### The golden rules
1. **No SOQL inside loops** — query once BEFORE the loop, use a Map for lookups
2. **No DML inside loops** — collect records in a List, do a single DML after the loop
3. **No callouts inside loops** — collect data, make callouts after the loop (or use async)
4. **Test with 200+ records** — always write bulk tests with at least 200 records (201 is ideal to hit batch boundaries)

### Bulkification patterns

**Map-based lookups (replace SOQL in loops):**
```apex
// Query once, build a map
Map<Id, Account> accountMap = new Map<Id, Account>(
    [SELECT Id, Name, BillingCity FROM Account WHERE Id IN :accountIds]
);
// Use the map in your loop
for (Contact c : contacts) {
    Account acc = accountMap.get(c.AccountId);
    if (acc != null) {
        c.MailingCity = acc.BillingCity;
    }
}
```

**Collect-then-DML (replace DML in loops):**
```apex
List<Task> tasksToCreate = new List<Task>();
for (Opportunity opp : opps) {
    tasksToCreate.add(new Task(
        Subject = 'Follow up',
        WhatId = opp.Id,
        OwnerId = opp.OwnerId
    ));
}
if (!tasksToCreate.isEmpty()) {
    insert tasksToCreate;
}
```

**Conditional DML (only update changed records):**
```apex
List<Account> accountsToUpdate = new List<Account>();
for (Account acc : accounts) {
    if (acc.Rating != 'Hot' && acc.AnnualRevenue > 1000000) {
        acc.Rating = 'Hot';
        accountsToUpdate.add(acc);
    }
}
if (!accountsToUpdate.isEmpty()) {
    update accountsToUpdate;
}
```

### Governor limit monitoring
Use `Limits` class strategically to detect approaching limits:
```apex
System.debug('SOQL queries used: ' + Limits.getQueries() + '/' + Limits.getLimitQueries());
System.debug('DML statements used: ' + Limits.getDmlStatements() + '/' + Limits.getLimitDmlStatements());
System.debug('CPU time used: ' + Limits.getCpuTime() + '/' + Limits.getLimitCpuTime());
```

## CRUD/FLS security patterns

### Modern approach (API 62.0+) — preferred
Use `WITH USER_MODE` in SOQL to enforce field-level security automatically:
```apex
List<Account> accounts = [
    SELECT Id, Name, AnnualRevenue
    FROM Account
    WHERE Industry = 'Technology'
    WITH USER_MODE
];
```

For DML operations:
```apex
Database.insert(accounts, AccessLevel.USER_MODE);
Database.update(accounts, AccessLevel.USER_MODE);
```

### Legacy approach (pre-62.0)
Use `Security.stripInaccessible()`:
```apex
SObjectAccessDecision decision = Security.stripInaccessible(
    AccessType.READABLE,
    [SELECT Id, Name, SSN__c FROM Contact]
);
List<Contact> safeContacts = decision.getRecords();
// SSN__c will be stripped if user lacks FLS read access
```

### Sharing keywords — ALWAYS declare explicitly
```apex
public with sharing class AccountService { }      // Enforces sharing rules (default for user-facing code)
public without sharing class SystemService { }     // Bypasses sharing (use sparingly, document WHY)
public inherited sharing class UtilityHelper { }   // Inherits from caller (use for shared utility classes)
```
**Never leave sharing undeclared** — it defaults to `without sharing` which is a security risk.

### SOQL injection prevention
```apex
// GOOD — use bind variables (always preferred)
String searchTerm = userInput;
List<Account> results = [SELECT Id, Name FROM Account WHERE Name = :searchTerm];

// BACKUP — escape if dynamic SOQL is absolutely necessary
String safeTerm = String.escapeSingleQuotes(userInput);
String query = 'SELECT Id, Name FROM Account WHERE Name = \'' + safeTerm + '\'';
```

## Anti-patterns — NEVER generate these

### Critical anti-patterns (block deployment)
| Anti-pattern | Why it's dangerous | Fix |
|---|---|---|
| SOQL in loop | Hits 100-query limit | Query once, use Map |
| DML in loop | Hits 150-statement limit | Collect in List, single DML |
| Missing sharing keyword | Defaults to `without sharing` | Always declare `with sharing` or `inherited sharing` |
| Hardcoded Record IDs | Break between orgs/sandboxes | Use Custom Metadata, Custom Labels, or queries |
| Empty catch blocks | Silently swallows errors | Log with `System.debug(LoggingLevel.ERROR, ...)` or rethrow |
| String concatenation in SOQL | SQL injection vulnerability | Use bind variables |
| Tests without assertions | Pass without validating anything | Use `Assert.areEqual()` with descriptive message |

### LLM-specific mistakes to avoid
These are common errors that AI generates but don't exist in Apex:
- **Non-existent methods**: `addMilliseconds()`, `stream()`, `getOrDefault()`, `StringBuilder` — these are Java, not Apex
- **Java collection types**: `ArrayList`, `HashMap`, `HashSet` — use `List<>`, `Map<>`, `Set<>`
- **Map access without null safety**: Always use `containsKey()` or `?.` before accessing map values
- **Missing SOQL fields**: Accessing a field not in the SELECT clause causes a runtime error — always query every field you use
- **Recursive trigger loops**: Use a static Set<Id> to track processed record IDs, not just a static Boolean flag
- **Invalid InvocableVariable types**: `Map` and `Set` are NOT supported — use `List` of wrapper classes instead

### Code review red flags
- Multiple triggers on the same object (should be one trigger per object)
- Logic directly in trigger body (should delegate to handler class)
- No bulk test (tests that only create 1 record)
- `@SeeAllData=true` (almost never needed)

## Async Apex selection guide

| Pattern | When to use | Limits |
|---|---|---|
| `@future` | Simple async, no chaining, ≤50 calls/transaction | Can't chain, can't track |
| `Queueable` | Complex async, chaining needed, pass objects | Can chain (1 child in prod) |
| `Batch` | Process 50K+ records | 5 concurrent batch jobs |
| `Schedulable` | Run on a schedule | Combine with Batch for large datasets |

**Choose Queueable over @future** in most cases — it's more flexible and supports object parameters.

## Naming conventions — expanded

### Classes
| Type | Pattern | Example |
|---|---|---|
| Service | `[Object]Service` | `AccountService` |
| Controller | `[Feature]Controller` | `AccountPageController` |
| Trigger Handler | `[Object]TriggerHandler` | `AccountTriggerHandler` |
| Batch | `[Purpose]_Batch` | `AccountCleanup_Batch` |
| Queueable | `[Purpose]_Queueable` | `AccountSync_Queueable` |
| Selector | `[Object]Selector` | `AccountSelector` |
| Test | `[ClassName]Test` | `AccountServiceTest` |
| Exception | `[Reason]Exception` | `InsufficientFundsException` |

### Variables
| Type | Pattern | Example |
|---|---|---|
| Boolean | `is/has` prefix | `isValid`, `hasPermission` |
| List | plural noun | `accounts`, `contactRecords` |
| Set | `[noun]Ids` | `accountIds`, `userIds` |
| Map | `[noun]By[Key]` | `accountsByEmail`, `contactsById` |
| Constants | UPPER_SNAKE | `MAX_BATCH_SIZE` |

## Testing patterns — expanded

### Test structure (Arrange-Act-Assert with PNB coverage)
Every test class should cover three paths:
- **P**ositive — happy path, valid data, expected behavior
- **N**egative — invalid data, missing fields, boundary conditions, error paths
- **B**ulk — 200+ records to verify governor limit safety

```apex
@IsTest
private class OpportunityServiceTest {
    @TestSetup
    static void setup() {
        // Create shared test data once — rolls back per test method
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 201; i++) {
            accounts.add(new Account(Name = 'Test Account ' + i));
        }
        insert accounts;
    }

    @IsTest
    static void testCloseOpportunity_positiveCase() {
        // Arrange
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = new Opportunity(
            Name = 'Test Opp', AccountId = acc.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Act
        Test.startTest();
        OpportunityService.closeOpportunity(opp.Id);
        Test.stopTest();

        // Assert
        Opportunity result = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        Assert.areEqual('Closed Won', result.StageName, 'Opportunity should be Closed Won');
    }

    @IsTest
    static void testCloseOpportunity_negativeCase_alreadyClosed() {
        // Test that closing an already-closed opp throws an error
    }

    @IsTest
    static void testCloseOpportunity_bulkCase() {
        // Test with 200 records to verify bulk safety
        List<Account> accounts = [SELECT Id FROM Account];
        List<Opportunity> opps = new List<Opportunity>();
        for (Account acc : accounts) {
            opps.add(new Opportunity(
                Name = 'Bulk Test', AccountId = acc.Id,
                StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
            ));
        }
        insert opps;

        Test.startTest();
        OpportunityService.closeOpportunities(new Map<Id, Opportunity>(opps).keySet());
        Test.stopTest();

        List<Opportunity> results = [SELECT StageName FROM Opportunity WHERE Id IN :opps];
        for (Opportunity o : results) {
            Assert.areEqual('Closed Won', o.StageName, 'All opportunities should be Closed Won');
        }
    }
}
```

### Use Assert class (not System.assert)
```apex
Assert.areEqual(expected, actual, 'message');   // preferred
Assert.isTrue(condition, 'message');
Assert.isFalse(condition, 'message');
Assert.isNull(value, 'message');
Assert.isNotNull(value, 'message');
Assert.isInstanceOfType(obj, Type.class, 'message');
```

## Date vs DateTime — critical SOQL binding rules

Salesforce enforces strict type matching between bind variables and SOQL field types. Mismatches cause compile errors.

**Rule:** Use `Date` bind variables for `Date` fields, and `DateTime` bind variables for `DateTime` fields. Never mix them.

### Common Date fields (use `Date` type)
- `Task.ActivityDate`, `Event.ActivityDate`
- `Opportunity.CloseDate`
- `Contract.StartDate`
- `Account.LastActivityDate` (system-maintained)

### Common DateTime fields (use `DateTime` type)
- `Task.CreatedDate`, `Event.CreatedDate`
- `Account.CreatedDate`, `Contact.CreatedDate`
- `Opportunity.CreatedDate`, `Case.CreatedDate`
- `Account.LastModifiedDate`

### Pattern
```apex
// CORRECT — Date bind for Date field
Date cutoff = Date.today().addDays(-30);
List<Task> tasks = [SELECT Id FROM Task WHERE ActivityDate >= :cutoff];

// WRONG — DateTime bind for Date field (compile error)
DateTime cutoff = DateTime.now().addDays(-30);
List<Task> tasks = [SELECT Id FROM Task WHERE ActivityDate >= :cutoff]; // ERROR
```

## Read-only and system-managed fields in test data

These fields CANNOT be set during insert/update, even in test context:

| Field | Why | Workaround |
|-------|-----|------------|
| `Contract.EndDate` | Calculated from `StartDate + ContractTerm` | Set `StartDate` and `ContractTerm` instead |
| `Case.CreatedDate` | System-managed timestamp | Use `Test.setCreatedDate(recordId, dateTimeValue)` after insert |
| `Opportunity.CreatedDate` | System-managed timestamp | Use `Test.setCreatedDate(recordId, dateTimeValue)` after insert |
| `Account.CreatedDate` | System-managed timestamp | Use `Test.setCreatedDate(recordId, dateTimeValue)` after insert |
| `*.LastModifiedDate` | System-managed | Cannot be set; design tests around relative dates |
| `*.LastActivityDate` | System-calculated from Tasks/Events | Insert Tasks/Events to populate it |
| `*.SystemModstamp` | System-managed | Cannot be set |

### Pattern for setting CreatedDate in tests
```apex
@IsTest
static void testWithOldRecord() {
    Account acc = new Account(Name = 'Test');
    insert acc;
    // Set CreatedDate AFTER insert using Test utility
    Test.setCreatedDate(acc.Id, DateTime.now().addDays(-90));
    // Re-query to get updated value
    acc = [SELECT Id, CreatedDate FROM Account WHERE Id = :acc.Id];
}
```

### Pattern for Contract test data
```apex
// WRONG — EndDate is not writeable
Contract c = new Contract(AccountId = acc.Id, StartDate = Date.today(), EndDate = Date.today().addMonths(12));

// CORRECT — use ContractTerm (months) and StartDate
Contract c = new Contract(AccountId = acc.Id, StartDate = Date.today(), ContractTerm = 12, Status = 'Draft');
```
