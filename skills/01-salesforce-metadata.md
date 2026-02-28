# Salesforce Metadata & SOQL

## When to use which tool

| Question type | Tool | Why |
|---|---|---|
| "What fields does Account have?" | `describe_object` | Returns field list, types, picklist values, relationships |
| "Show me all validation rules on Opportunity" | `query_tooling` | ValidationRule is a Tooling API object |
| "How many Contacts are there?" | `query` (SOQL) | Standard data query with COUNT() |
| "What does the Status field look like?" | `describe_object` | Picklist values, field type, formula |
| "Who has access to…" | See `05-permissions.md` | Permission queries |

## SOQL patterns

### Counting records
```sql
SELECT COUNT() FROM Contact WHERE AccountId != null
```
Always use `COUNT()` for "how many" questions. Never fetch all records to count them client-side.

### Finding records by criteria
```sql
SELECT Id, Name, Email, CreatedDate
FROM Contact
WHERE Account.Industry = 'Technology'
  AND CreatedDate = THIS_YEAR
ORDER BY CreatedDate DESC
LIMIT 200
```

### Relationship queries (parent-to-child)
```sql
SELECT Id, Name,
  (SELECT Id, FirstName, LastName, Email FROM Contacts LIMIT 10)
FROM Account
WHERE Industry = 'Technology'
LIMIT 50
```

### Relationship queries (child-to-parent)
```sql
SELECT Id, Name, Account.Name, Account.Industry
FROM Contact
WHERE Account.Industry = 'Technology'
LIMIT 200
```

### Date literals
Use Salesforce date literals — they're cleaner than hardcoded dates:
- `TODAY`, `YESTERDAY`, `TOMORROW`
- `THIS_WEEK`, `LAST_WEEK`, `NEXT_WEEK`
- `THIS_MONTH`, `LAST_MONTH`, `NEXT_MONTH`
- `THIS_QUARTER`, `LAST_QUARTER`, `THIS_YEAR`, `LAST_YEAR`
- `LAST_N_DAYS:30`, `NEXT_N_DAYS:7`, `LAST_N_MONTHS:6`

### Aggregate queries
```sql
SELECT Account.Name, COUNT(Id) contactCount
FROM Contact
GROUP BY Account.Name
ORDER BY COUNT(Id) DESC
LIMIT 50
```

### Finding duplicates
```sql
SELECT Email, COUNT(Id) dupeCount
FROM Contact
WHERE Email != null
GROUP BY Email
HAVING COUNT(Id) > 1
ORDER BY COUNT(Id) DESC
LIMIT 50
```

## Tooling API reference

Use `query_tooling` for metadata that isn't accessible via standard SOQL.

### ValidationRule
```sql
SELECT Id, EntityDefinition.QualifiedApiName, Active, Description,
       ErrorConditionFormula, ErrorMessage
FROM ValidationRule
WHERE EntityDefinition.QualifiedApiName = 'Opportunity'
  AND Active = true
```
Key fields: `Active`, `Description`, `ErrorConditionFormula`, `ErrorMessage`, `ErrorDisplayField`

### WorkflowRule
```sql
SELECT Id, Name, TableEnumOrId
FROM WorkflowRule
WHERE TableEnumOrId = 'Case'
```
Note: Legacy automation. If a user asks about "automation on X", check both WorkflowRules and Flows.

### FlowDefinition
```sql
SELECT DeveloperName, ActiveVersionId, LatestVersionId, Description
FROM FlowDefinition
WHERE DeveloperName LIKE '%Lead%'
```
To check if a Flow is active, compare `ActiveVersionId` to `LatestVersionId`.

### CustomField
```sql
SELECT Id, DeveloperName, TableEnumOrId, DataType, FullName
FROM CustomField
WHERE TableEnumOrId = 'Account'
```

### ApexClass
```sql
SELECT Id, Name, Status, ApiVersion, LengthWithoutComments
FROM ApexClass
WHERE Name LIKE '%Handler%'
ORDER BY Name
```
Note: This gives metadata only. Use the dedicated `get_apex_class` tool to view source code (dev/sandbox orgs only).

### ApexTrigger
```sql
SELECT Id, Name, TableEnumOrId, Status, ApiVersion
FROM ApexTrigger
WHERE TableEnumOrId = 'Account'
```

### AssignmentRule
```sql
SELECT Id, Name, SobjectType, Active
FROM AssignmentRule
WHERE SobjectType = 'Lead'
```

### PermissionSet
```sql
SELECT Id, Name, Label, IsOwnedByProfile, Description
FROM PermissionSet
WHERE IsOwnedByProfile = false
```

## Common query recipes

### "What automation exists on [Object]?"
Run these queries and combine the results:
1. Validation rules: `SELECT ... FROM ValidationRule WHERE EntityDefinition.QualifiedApiName = '[Object]'`
2. Workflow rules: `SELECT ... FROM WorkflowRule WHERE TableEnumOrId = '[Object]'`
3. Flows: `SELECT ... FROM FlowDefinition` (then filter by relevance)
4. Apex triggers: `SELECT ... FROM ApexTrigger WHERE TableEnumOrId = '[Object]'`

### "What fields were recently added?"
```sql
SELECT DeveloperName, TableEnumOrId, DataType, CreatedDate
FROM CustomField
WHERE CreatedDate = LAST_N_DAYS:30
ORDER BY CreatedDate DESC
LIMIT 50
```

### "Show me formula fields on [Object]"
Use `describe_object` and filter for fields where `calculatedFormula` is not null.

### "What objects exist in this org?"
Use the `list_objects` tool. To filter to custom objects only, look for API names ending in `__c`.
