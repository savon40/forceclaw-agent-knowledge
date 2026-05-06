# Apex Development

## When this applies

This skill applies when working with **dev/sandbox orgs** where write access is enabled. For production orgs, you can only view Apex metadata — not source code or make changes.

## Review gate by change type

Different Apex changes need different review lenses. Don't run the same checklist for every change — match the gate to the kind of work.

| Change type | Required review | Test discipline |
|---|---|---|
| **Trigger** | Handler pattern, operation context, recursion guard, Salesforce order of execution, Flow interaction, bulk behavior | Bulk tests (200+ records), changed-vs-unchanged field paths, delete/undelete when relevant |
| **Controller** (LWC/Aura/REST) | UI/API contract, DTO shape, sharing posture, CRUD/FLS, user-mode vs system-mode | Focused tests for each public method, caller inspection (which LWC/Aura calls it), error paths surfaced as toast/error |
| **Async** (Queueable / Batch / Schedulable / @future) | Enqueue path, transaction boundary, side effects, idempotency on retry | `Test.startTest()` / `Test.stopTest()` boundary, durable result assertions, retry de-duplication |
| **Callout** | Named credentials, mocks for every path, failure handling, callout-after-DML rules | Mock success, auth failure, missing config, provider-specific responses — every path has a mock |
| **Files** (`ContentVersion`, `ContentDocument`, `ContentDocumentLink`) | Latest-version behavior, parent record state refresh, sharing for portal/Experience users | File lifecycle assertions (insert version → query DocumentId → verify Link → assert latest), `@IsTest(isParallel=false)` only where row locks force it |
| **Communication** (email, Chatter, activity, notifications) | Actor context, target record, body/template source, idempotency for retries, sanitized failure logging | Duplicate-prevention assertions, async completion, missing-template/config paths |
| **Test-only** | Production contract preserved, test data created in the test or factory | Re-run only the focused failing tests; don't ship broad rewrites in a hotfix |

When reporting back, name the gate you used. A trigger change reviewed under the "controller" gate will miss recursion and order-of-execution risks.

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

> Exact numeric limits are release-sensitive. When the precise number matters, link to or quote Salesforce's current governor-limit docs rather than hard-coding values that may drift.

### Governor-limit risk by area

Don't add a generic "watch out for governor limits" warning. Tie the risk to where it actually shows up:

| Area | Limit risk to inspect |
|---|---|
| **Trigger** | Records per transaction, SOQL/DML count, duplicate DML rows, recursion depth, async enqueue count per record |
| **Service class** | Query row volume, CPU-heavy loops, map size, callout/DML ordering |
| **Async Apex** | Chain depth, batch scope size, retry duplication, per-scope query/DML volume |
| **Files / PDFs** | Heap (base64 strings, large blobs), `ContentVersion` row locks, version queries, generated-document handoff |
| **Tests** | One `executeBatch` per test method, test data volume, file row locks, callout mock setup |
| **Dynamic SOQL** | Injection risk, unbounded filters, unselective queries, missing field allowlists |

When a limit is the actual risk for the change, name the mitigation and the validation evidence in the Slack summary. Don't paste the full numeric table.

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

### Sharing keyword vs CRUD/FLS — they solve different problems

`with sharing` is **not** the same as enforcing CRUD/FLS. The sharing keyword controls **which records** the user can access (record-level visibility). CRUD/FLS controls **which objects and fields** the user can read/write (object-level and field-level access). A class declared `with sharing` can still leak fields the user shouldn't see if you don't enforce field-level security separately.

| Concern | What enforces it |
|---|---|
| Which records the user sees | `with sharing` / `inherited sharing` keywords + sharing rules / OWD / role hierarchy |
| Whether the user can read/edit/delete the object at all | Object permissions (CRUD) — checked via user-mode, `Schema.sObjectType.X.isAccessible()`, or `WITH SECURITY_ENFORCED` |
| Whether the user can see/edit each field | Field-level security (FLS) — checked via user-mode, `stripInaccessible`, `WITH SECURITY_ENFORCED`, or `Schema.SObjectField.isAccessible()` |
| Whether the user can perform a business action | Custom permissions, permission sets, profile permissions — checked via `FeatureManagement` or `User.hasPermission` |

When the user asks for "secure" Apex, ask which of these they actually want. Most "I want CRUD/FLS enforced" requests turn out to need both sharing AND field/object enforcement.

### Four strategies for enforcing CRUD/FLS

Each one solves a different shape of problem. Pick the one that matches the situation; don't reflex to the same one every time.

| Strategy | Behavior | When to use |
|---|---|---|
| **`WITH USER_MODE` / `AccessLevel.USER_MODE`** | Auto-enforces both object and field access; throws on violation | Static SOQL/DML in user-facing code (controllers, invocables). API 62.0+. Preferred default for new exposed Apex. |
| **`Security.stripInaccessible()`** | Returns the records with inaccessible fields **silently removed** | When you want to return whatever the user is allowed to see, without throwing. Useful for list views or DTO responses where partial data is OK. |
| **`WITH SECURITY_ENFORCED`** | Throws on any inaccessible field in the SELECT clause | Dynamic SOQL in user-facing code where you'd rather fail loudly than silently filter. Older alternative to user-mode. |
| **Describe checks (`Schema.sObjectType.X.isAccessible()`)** | Manual programmatic check before access | Dynamic field allowlists, conditional logic based on access, when none of the above fits the contract |

### `WITH USER_MODE` — preferred default (API 62.0+)
```apex
List<Account> accounts = [
    SELECT Id, Name, AnnualRevenue
    FROM Account
    WHERE Industry = 'Technology'
    WITH USER_MODE
];

Database.insert(accounts, AccessLevel.USER_MODE);
Database.update(accounts, AccessLevel.USER_MODE);
```

### `Security.stripInaccessible()` — silent filter
```apex
SObjectAccessDecision decision = Security.stripInaccessible(
    AccessType.READABLE,
    [SELECT Id, Name, SSN__c FROM Contact]
);
List<Contact> safeContacts = decision.getRecords();
// SSN__c removed if user lacks FLS read access
// decision.getRemovedFields() shows what was stripped
```

### `WITH SECURITY_ENFORCED` — throws on violation
```apex
List<Account> accounts = [
    SELECT Id, Name, AnnualRevenue
    FROM Account
    WHERE Industry = 'Technology'
    WITH SECURITY_ENFORCED
];
// Throws QueryException if user lacks read on any selected field
```

### Describe checks — manual / dynamic
```apex
if (Schema.sObjectType.Account.fields.AnnualRevenue.isAccessible()) {
    // safe to query/return AnnualRevenue
}

// For dynamic SOQL — validate every field the caller asked for:
for (String fieldName : requestedFields) {
    Schema.SObjectField field = Account.SObjectType.getDescribe().fields.getMap().get(fieldName);
    if (field == null || !field.getDescribe().isAccessible()) {
        throw new SecurityException('Field not accessible: ' + fieldName);
    }
}
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

## Test data factories

Tests should create their own data — never depend on existing records, real usernames, customer record names, profile names, role IDs, or anything else that varies by org.

### Factory rules
- **Required fields only.** Populate the fields the scenario needs, plus required fields. Leave optional fields blank in at least one test so you cover the empty-state path.
- **Stable but unique values.** `'Test Account ' + i`, not `'Acme'`. Two tests running back-to-back must not collide on a unique field.
- **No real org state.** No customer names, real emails, real Salesforce User IDs, real Profile names. Tests have to pass on someone else's sandbox.
- **No `@IsTest(SeeAllData=true)`.** The only valid use is testing against standard Pricebook in a context where `Test.getStandardPricebookId()` doesn't satisfy the requirement — and even then, document why.
- **Inspect validation rules and required fields first.** Required-field failures in tests are usually test-data failures, not product failures. Before writing a factory, query the object's validation rules and required fields.

### Factory pattern
```apex
@IsTest
public class TestDataFactory {
    public static List<Account> createAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                BillingCountry = 'United States'  // satisfies a hypothetical validation rule
            ));
        }
        insert accounts;
        return accounts;
    }

    public static User createTestUser(String profileName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        return new User(
            ProfileId = p.Id,
            LastName = 'TestUser',
            Email = 'test-' + DateTime.now().getTime() + '@example.com.invalid',
            Username = 'test-' + DateTime.now().getTime() + '@example.com.invalid',
            Alias = 'tuser',
            CommunityNickname = 'tuser' + DateTime.now().getTime(),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}
```

### Anti-patterns
```apex
// BAD — depends on existing data
List<User> existingUsers = [SELECT Id FROM User WHERE Name = 'Sarah Smith' LIMIT 1];

// BAD — collision on unique fields between test runs
Account a = new Account(Name = 'Acme');

// BAD — relies on standard org Profile names that vary by org type/edition
Profile p = [SELECT Id FROM Profile WHERE Name = 'Custom: Sales Profile'];

// BAD — uses production data
Account a = [SELECT Id FROM Account WHERE Name = 'Acme Corp'];
```

## Assertion discipline — test the contract, not the implementation

The point of a test is to prove behavior. Coverage is a side effect. A test that runs every line but asserts nothing meaningful is not a test.

### What good assertions check
- Records were inserted, updated, deleted, or **left unchanged** as intended (negative-space assertions matter)
- Errors thrown for invalid input — assert both the type and the message
- Async work produced the expected **durable result** (record state, log entry, status field) — not internal call counts
- Callouts were mocked correctly — assert what the production code did with the mocked response, not that the mock was set up
- Sharing or permission behavior is enforced when relevant (use `System.runAs()`)
- **No unintended records were changed** — query the rest of the test data and assert it's unchanged

### Don't weaken assertions to make tests pass
```apex
// BAD — asserts nothing
Assert.isTrue(true, 'placeholder');

// BAD — runs the code but doesn't check behavior
Test.startTest();
service.process(records);
Test.stopTest();
// (no assertions)

// BAD — asserts implementation detail that will break on refactor
Assert.areEqual(3, service.queryCount, 'expected 3 queries');

// GOOD — asserts the contract
Test.startTest();
service.process(records);
Test.stopTest();
List<Opportunity> updated = [SELECT Id, StageName FROM Opportunity WHERE Id IN :records];
for (Opportunity o : updated) {
    Assert.areEqual('Closed Won', o.StageName, 'process() should close all opportunities');
}
```

### Test the changed contract, not stale literals
When a behavior change is intentional, the tests for that behavior must change too. If the contract is now "advance only when payment confirmed," the test asserts the new contract — don't keep the old `'Stage 3'` literal because it used to pass.

Common new-contract assertions:
- "no unsafe advancement" — record stage unchanged
- "retry date set" — `RetryAt__c` populated
- "duplicate blocked" — count remained at 1
- "optional integration skipped safely" — log entry exists, no exception thrown
- "source-of-truth field wins" — the authoritative field overrides the stale value
- "existing populated values preserved" — the update didn't blank out previously set fields

## Batch test scope limit — one executeBatch per test

Apex enforces **one batch execution scope** per test method. If your test data creates two qualifying chunks and the batch size is one, the test fails with:

```
No more than one executeBatch can be called from within a test method
```

### Fix patterns
```apex
@IsTest
static void testBatchProcess() {
    // Insert exactly one batch's worth of test data, OR
    // use a batch size large enough that all test data fits in one execute scope.

    // GOOD — 5 records, batch size 200: all fit in one scope
    List<Account> accounts = TestDataFactory.createAccounts(5);

    Test.startTest();
    Database.executeBatch(new MyBatch(), 200);
    Test.stopTest();

    // Assert durable result
    List<Account> updated = [SELECT Id, Status__c FROM Account WHERE Id IN :accounts];
    for (Account a : updated) {
        Assert.areEqual('Processed', a.Status__c, 'all accounts should be processed');
    }
}
```

### When you need multiple scopes
Split into separate test methods. Each `@IsTest static void` method gets its own batch scope budget.

## Callout mocking — every path needs a mock

Tests cannot make real HTTP callouts. Salesforce throws `CalloutException`. Every callout path needs a mock — including the failure paths.

### Mock every path the production code handles
- **Success** — the happy path, parsed response, downstream side effect
- **Auth failure** (401, 403) — token expired, refresh attempted, error logged
- **Missing config** — Named Credential not set, secret missing, callout skipped with diagnostic
- **Provider-specific failures** — rate limit (429), validation error (400 with structured body), 5xx server error
- **Timeout** — production code's retry / fallback behavior

### Pattern: HttpCalloutMock
```apex
@IsTest
private class IntegrationServiceTest {

    @IsTest
    static void testCallout_success() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest();
        IntegrationResult r = IntegrationService.fetchData('account-123');
        Test.stopTest();
        Assert.isTrue(r.success, 'should succeed on 200');
        Assert.areEqual('expected-value', r.data, 'should parse response correctly');
    }

    @IsTest
    static void testCallout_authFailure() {
        Test.setMock(HttpCalloutMock.class, new AuthFailMock());
        Test.startTest();
        IntegrationResult r = IntegrationService.fetchData('account-123');
        Test.stopTest();
        Assert.isFalse(r.success, 'should fail on 401');
        Assert.areEqual('AUTH_FAILED', r.errorCategory, 'should categorize as auth failure');
    }

    @IsTest
    static void testCallout_missingConfig() {
        // No mock needed — test the production code's handling of missing Named Credential
        Test.startTest();
        try {
            IntegrationService.fetchData(null);
            Assert.fail('should have thrown ConfigurationException');
        } catch (ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('Named Credential'), 'message should reference config');
        }
        Test.stopTest();
    }

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"data":"expected-value"}');
            return res;
        }
    }

    private class AuthFailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"error":"token_expired"}');
            return res;
        }
    }
}
```

### Callouts after DML
Synchronous DML followed by a callout in the same transaction throws `CalloutException`. Either:
- Move the callout into a `@future(callout=true)` or `Queueable implements Database.AllowsCallouts`
- Move the DML after the callout
- Use `Test.startTest()` / `Test.stopTest()` to defer the callout in tests when production uses async

## File tests — fragile, plan accordingly

Salesforce Files (`ContentVersion`, `ContentDocument`, `ContentDocumentLink`) tests are common sources of flakiness.

### Why they're fragile
- **`ContentVersion` inserts can cause row locks** under broad parallel test runs — multiple tests inserting versions to the same parent record contend
- **`ContentDocumentLink` is event-driven** — creating one fires triggers, validation rules, and Flows that may not be idempotent
- **Latest-version logic** matters — `ContentDocument.LatestPublishedVersionId` references a specific version, not "the most recent insert"
- **`@IsTest(isParallel=false)`** is a sledgehammer — every test marked this way slows the suite. Use it only when row locks make parallel execution unreliable.

### File lifecycle test pattern
```apex
@IsTest
static void testFileAttachedToAccount() {
    Account acc = TestDataFactory.createAccounts(1)[0];

    Test.startTest();

    // Insert ContentVersion
    ContentVersion cv = new ContentVersion(
        Title = 'Test File',
        PathOnClient = 'test.pdf',
        VersionData = Blob.valueOf('test content'),
        IsMajorVersion = true
    );
    insert cv;

    // Query the resulting ContentDocumentId
    cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
    Assert.isNotNull(cv.ContentDocumentId, 'ContentDocumentId should be set after insert');

    // Link to the parent record
    ContentDocumentLink cdl = new ContentDocumentLink(
        ContentDocumentId = cv.ContentDocumentId,
        LinkedEntityId = acc.Id,
        ShareType = 'V',
        Visibility = 'AllUsers'
    );
    insert cdl;

    Test.stopTest();

    // Assert the link exists and points at the latest version
    List<ContentDocumentLink> links = [
        SELECT Id, ContentDocument.LatestPublishedVersionId
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :acc.Id
    ];
    Assert.areEqual(1, links.size(), 'one link should exist');
    Assert.areEqual(cv.Id, links[0].ContentDocument.LatestPublishedVersionId,
        'link should reference the latest version');
}
```

### What to assert in file tests
- Insert succeeded and `ContentDocumentId` came back
- Link to the parent record was created (or already existed and wasn't duplicated)
- Latest-version reference points at the right version
- Parent record state refreshed if production code recomputes counts/rollups
- No-file path — the production code handles "no files attached" gracefully
- Missing-link path — production code handles "file exists but link to this user/record missing"

## Communication automation tests — duplicates and idempotency

For email, Chatter posts, activity creation, notifications, and generated-document side effects, test:

- **Missing template / configuration** — production code logs and skips, doesn't crash
- **Missing merge data** — empty fields, null relationships, default fallbacks
- **Duplicate retry prevention** — same operation called twice produces one side effect, not two. Assert via an idempotency key, status field, or count.
- **Async completion** — wrap in `Test.startTest()` / `Test.stopTest()` and assert durable result
- **Denied or missing target record access** — `System.runAs()` a user without access, verify safe failure

### Don't assert exact private-facing message text
- Production message bodies often contain customer data — keep them out of test asserts that may be read by anyone with repo access.
- Assert structure (subject contains, recipient list size, action recorded, idempotency key set), not exact body content.

### Pattern: idempotency assertion
```apex
@IsTest
static void testEmailNotSentTwiceOnRetry() {
    Account acc = TestDataFactory.createAccounts(1)[0];

    Test.startTest();
    NotificationService.sendOnboardingEmail(acc.Id);
    NotificationService.sendOnboardingEmail(acc.Id);  // retry / duplicate call
    Test.stopTest();

    // Assert exactly one email log entry exists
    List<Email_Log__c> logs = [SELECT Id FROM Email_Log__c WHERE Account__c = :acc.Id];
    Assert.areEqual(1, logs.size(), 'duplicate call should not create a second email log');
}
```

## Coverage strategy

- **Add branch coverage for validation and error paths** in classes you're deploying. Coverage gates apply to changed classes specifically.
- **Prefer focused subsystem tests** over broad unrelated tests for a narrow production deploy. Don't pull in legacy classes that fail for unrelated reasons.
- **Don't chase high org-wide coverage** through risky broad refactors in a hotfix. Org-wide coverage and per-class coverage on a deploy package are different metrics.
- **Coverage is necessary, not sufficient.** A class can have 100% coverage and still be wrong. Prioritize assertion quality over coverage percentage.

