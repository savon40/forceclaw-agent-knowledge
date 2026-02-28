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
