# Salesforce Metadata & SOQL

## STOP — Read this first

**The following sObjects will ERROR if you query them via standard SOQL (`query_salesforce`).
You MUST use the `query_tooling` tool for these:**

- `ValidationRule` — TOOLING API ONLY
- `WorkflowRule` — TOOLING API ONLY
- `CustomField` — TOOLING API ONLY
- `ApexClass` — TOOLING API ONLY
- `ApexTrigger` — TOOLING API ONLY
- `FlowDefinition` — TOOLING API ONLY
- `Flow` — TOOLING API ONLY
- `LightningComponentBundle` — TOOLING API ONLY
- `AssignmentRule` — TOOLING API ONLY

Querying any of these via `query_salesforce` returns: `sObject type 'X' is not supported.`

**Use `query_salesforce` (standard SOQL) for:** data objects (Account, Contact, Opportunity, Case, etc.), `FlowDefinitionView`, `FlowVersionView`, `User`, `PermissionSet`, `PermissionSetAssignment`, `ObjectPermissions`, `FieldPermissions`, `UserRole`.

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

## SOQL vs Tooling API — what lives where

**This is critical. Using the wrong API wastes turns and causes errors.**

### Queryable via standard SOQL (`query` tool)
| sObject | Key fields | Use for |
|---------|-----------|---------|
| `FlowDefinitionView` | `ApiName`, `Label`, `ProcessType`, `TriggerType`, `RecordTriggerType`, `TriggerObjectOrEventLabel`, `IsActive`, `ActiveVersionId` | Listing flows, checking if active, finding flows by trigger object |
| `FlowVersionView` | `FlowDefinitionViewId`, `Label`, `ProcessType`, `Status`, `VersionNumber`, `ApiVersion` | Flow version details |
| `User` | `Name`, `Email`, `Profile.Name`, `UserRole.Name`, `IsActive` | User lookups |
| `PermissionSet` | `Name`, `Label`, `IsOwnedByProfile` | Listing permission sets |
| `PermissionSetAssignment` | `AssigneeId`, `PermissionSetId` | Who has what permission set |
| `ObjectPermissions` | `SobjectType`, `PermissionsRead/Edit/Create/Delete` | Object-level access |
| `FieldPermissions` | `SobjectType`, `Field`, `PermissionsRead/Edit` | Field-level security |
| `UserRole` | `Name`, `ParentRoleId` | Role hierarchy |

### Queryable via Tooling API only (`query_tooling` tool)
| sObject | Key fields | Use for |
|---------|-----------|---------|
| `ValidationRule` | `ValidationName`, `Active`, `Description`, `ErrorMessage`, `EntityDefinition.QualifiedApiName` — `Metadata`/`FullName` single-row only (formula is inside `Metadata`) | Validation rules |
| `WorkflowRule` | `Name`, `TableEnumOrId` | Legacy workflow rules — NOT in standard SOQL |
| `FlowDefinition` | `DeveloperName`, `MasterLabel`, `ActiveVersionId`, `LatestVersionId`, `Description` — does NOT have ProcessType, TriggerType, Status | Flow metadata (prefer FlowDefinitionView for listing) |
| `Flow` | `DefinitionId`, `Definition.DeveloperName`, `MasterLabel`, `ProcessType`, `Status`, `VersionNumber`, `Metadata` — does NOT have TriggerType, RecordTriggerType, TriggerObjectOrEventLabel | Flow version metadata via Tooling API only |
| `CustomField` | `DeveloperName`, `TableEnumOrId`, `DataType` | Custom field definitions |
| `ApexClass` | `Name`, `Body`, `Status`, `ApiVersion` | Apex class metadata + source code |
| `ApexTrigger` | `Name`, `Body`, `TableEnumOrId`, `Status` | Trigger metadata + source code |
| `LightningComponentBundle` | `DeveloperName`, `MasterLabel`, `ApiVersion` | LWC bundles — Tooling API only |
| `AssignmentRule` | `Name`, `SobjectType`, `Active` | Lead/case assignment rules |

**Important notes:**
- `ApexClass.Body` and `ApexTrigger.Body` contain the full source code — only available via Tooling API, only in dev/sandbox orgs
- `WorkflowRule` is ONLY available via Tooling API — querying it via standard SOQL will fail
- `LightningComponentBundle` is ONLY available via Tooling API
- For listing flows, prefer `FlowDefinitionView` (standard SOQL) over `FlowDefinition` (Tooling) — it has friendlier fields like `IsActive`

## Tooling API reference

Use `query_tooling` for metadata that isn't accessible via standard SOQL.

### ValidationRule ← TOOLING API ONLY
Use tool: **`query_tooling`** (NOT `query_salesforce` — will error)

**Available fields:**
| Field | Type | Notes |
|-------|------|-------|
| `Id` | id | Record ID |
| `ValidationName` | string | API name of the validation rule |
| `Active` | boolean | Whether the rule is active |
| `Description` | string | Description |
| `EntityDefinitionId` | string | ID of the parent entity |
| `EntityDefinition.QualifiedApiName` | string | API name of the parent object (use in WHERE) |
| ~~`ErrorConditionFormula`~~ | — | **DOES NOT EXIST** as a direct field. The formula is inside the `Metadata` compound field only. |
| `ErrorMessage` | string | Error message shown to user |
| `CreatedDate` | datetime | When the rule was created |
| `CreatedById` | id | Who created it |
| `LastModifiedDate` | datetime | Last modified date |
| `LastModifiedById` | id | Who last modified it |
| `ManageableState` | string | Package state (unmanaged, installed, etc.) |
| `NamespacePrefix` | string | Namespace if from a package |
| `Metadata` | complex | Full metadata (contains `errorConditionFormula`, `errorDisplayField`, `errorMessage`, `active`, `description`, `shouldEvaluateOnChange`, `urls`) — **can only be queried when result is exactly 1 row** (use LIMIT 1 + specific WHERE) |
| `FullName` | string | Full API name — **same single-row restriction as Metadata** |

**IMPORTANT:** `Metadata` and `FullName` fields cause an error if the query returns more than 1 row. When listing multiple rules, do NOT include `Metadata` or `FullName`. Query those fields only when fetching a single rule by name.

**Listing all validation rules on an object (NO Metadata/FullName):**
```sql
SELECT Id, ValidationName, Active, Description, ErrorMessage
FROM ValidationRule
WHERE EntityDefinition.QualifiedApiName = 'Opportunity'
ORDER BY ValidationName
```

**Getting full details for a single rule (with Metadata):**
```sql
SELECT Id, ValidationName, Active, Description, ErrorMessage, Metadata
FROM ValidationRule
WHERE ValidationName = 'My_Rule_Name'
  AND EntityDefinition.QualifiedApiName = 'Opportunity'
LIMIT 1
```

### WorkflowRule ← TOOLING API ONLY
Use tool: **`query_tooling`** (NOT `query_salesforce` — will error)
```sql
SELECT Id, Name, TableEnumOrId
FROM WorkflowRule
WHERE TableEnumOrId = 'Case'
```
Note: Legacy automation. If a user asks about "automation on X", check both WorkflowRules and Flows.

### FlowDefinition ← TOOLING API ONLY
Use tool: **`query_tooling`** (NOT `query_salesforce` — will error)
**Available fields:** `Id`, `DeveloperName`, `MasterLabel`, `ActiveVersionId`, `LatestVersionId`, `Description`, `NamespacePrefix`, `ManageableState`
**Does NOT have:** `ProcessType`, `TriggerType`, `Status`, `VersionNumber`, `IsActive`, `TriggerObjectOrEventLabel`
```sql
SELECT DeveloperName, MasterLabel, ActiveVersionId, LatestVersionId, Description
FROM FlowDefinition
WHERE DeveloperName LIKE '%Lead%'
```
To check if a Flow is active: `ActiveVersionId` is not null.
**Prefer `FlowDefinitionView` via standard SOQL for listing flows** — it has `IsActive`, `TriggerType`, `TriggerObjectOrEventLabel` directly. See `02-flow-building.md` for complete field reference.

### CustomField ← TOOLING API ONLY
Use tool: **`query_tooling`** (NOT `query_salesforce` — will error)
```sql
SELECT Id, DeveloperName, TableEnumOrId, DataType, FullName
FROM CustomField
WHERE TableEnumOrId = 'Account'
```

### ApexClass ← TOOLING API ONLY
Use tool: **`query_tooling`** (NOT `query_salesforce` — will error)
```sql
SELECT Id, Name, Status, ApiVersion, LengthWithoutComments
FROM ApexClass
WHERE Name LIKE '%Handler%'
ORDER BY Name
```
Note: This gives metadata only. Use the dedicated `get_apex_class` tool to view source code (dev/sandbox orgs only).

### ApexTrigger ← TOOLING API ONLY
Use tool: **`query_tooling`** (NOT `query_salesforce` — will error)
```sql
SELECT Id, Name, Body, TableEnumOrId, Status, ApiVersion
FROM ApexTrigger
WHERE TableEnumOrId = 'Account'
```
Note: `Body` field contains the full trigger source code (dev/sandbox orgs only).

### LightningComponentBundle ← TOOLING API ONLY
Use tool: **`query_tooling`** (NOT `query_salesforce` — will error)
```sql
SELECT Id, DeveloperName, MasterLabel, ApiVersion
FROM LightningComponentBundle
ORDER BY DeveloperName
LIMIT 200
```

### AssignmentRule ← TOOLING API ONLY
Use tool: **`query_tooling`** (NOT `query_salesforce` — will error)
```sql
SELECT Id, Name, SobjectType, Active
FROM AssignmentRule
WHERE SobjectType = 'Lead'
```

### PermissionSet ← standard SOQL
Use tool: **`query_salesforce`**
```sql
SELECT Id, Name, Label, IsOwnedByProfile, Description
FROM PermissionSet
WHERE IsOwnedByProfile = false
```

## Common query recipes

### "What automation exists on [Object]?"
Run these queries and combine the results:
1. Validation rules — **use `query_tooling`**: `SELECT ... FROM ValidationRule WHERE EntityDefinition.QualifiedApiName = '[Object]'`
2. Workflow rules — **use `query_tooling`**: `SELECT ... FROM WorkflowRule WHERE TableEnumOrId = '[Object]'`
3. Flows — **use `query_salesforce`**: `SELECT ApiName, Label, ProcessType, TriggerType, IsActive FROM FlowDefinitionView WHERE IsActive = true`
4. Apex triggers — **use `query_tooling`**: `SELECT ... FROM ApexTrigger WHERE TableEnumOrId = '[Object]'`

### "What fields were recently added?"
**Use `query_tooling`** (CustomField is Tooling API only):
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

## SOQL optimization guide

### Indexing and selectivity
Salesforce automatically indexes certain fields. Queries that use indexed fields in WHERE clauses are **selective** and perform better.

**Always-indexed fields** (use these in WHERE clauses for best performance):
- `Id`, `Name`, `OwnerId`, `CreatedDate`, `LastModifiedDate`, `SystemModstamp`
- `RecordTypeId`
- External ID fields (custom fields marked as External ID)
- Master-Detail relationship fields
- Lookup fields

**Selectivity rules:**
- A query is selective if the WHERE clause matches < 10% of the first 1,000,000 records (or < 5% beyond 1M)
- Non-selective queries on large objects (100K+ records) may hit "Non-selective query" errors

### SOQL anti-patterns to avoid

| Anti-pattern | Why it's bad | Fix |
|---|---|---|
| SOQL inside loops | Hits 100-query governor limit | Query once before the loop, use a Map for lookups |
| Leading wildcards (`LIKE '%term'`) | Cannot use index, scans all records | Use trailing wildcards (`LIKE 'term%'`) or filter in Apex post-query |
| Negative operators (`!=`, `NOT IN`) in WHERE | Cannot use index | Query for what you want instead of what you don't |
| `SELECT *` / `FIELDS(ALL)` | Returns all fields — performance and security issue | Query only the fields you need |
| No LIMIT on queries | Can return up to 50,000 rows | Always add a reasonable LIMIT |
| Deep relationship traversal (>5 levels) | Salesforce limit is 5 levels for child-to-parent | Flatten into separate queries |
| Unfiltered subqueries | Child queries return up to 200 rows per parent | Always add WHERE and LIMIT to subqueries |
| Querying for NULL (`WHERE Field = null`) | Rarely uses index | Combine with a selective indexed filter |
| Formula fields in WHERE | Formulas aren't indexed | Use the underlying source field instead |

### SOQL security patterns
```sql
-- Enforce FLS automatically (preferred, API 62.0+)
SELECT Id, Name, AnnualRevenue FROM Account WITH USER_MODE

-- System context (use for internal/admin operations, document why)
SELECT Id, Name FROM Account WITH SYSTEM_MODE
```

### Query optimization tips
1. **Always query only the fields you need** — extra fields increase data transfer and heap usage
2. **Use bind variables in Apex** — they prevent SOQL injection and are faster than string concatenation
3. **Use aggregate queries for counts/sums** — `SELECT COUNT() FROM Contact` is faster than fetching all records and counting in Apex
4. **Use SOQL FOR loops for large result sets** — processes records in batches of 200, avoids heap limits:
   ```apex
   for (List<Account> batch : [SELECT Id, Name FROM Account WHERE Industry = 'Tech']) {
       // processes 200 records at a time
   }
   ```
5. **Use Map constructor for O(1) lookups** — `new Map<Id, Account>(accountList)` is faster than looping

### Relationship query patterns

**Child-to-parent (dot notation, up to 5 levels):**
```sql
SELECT Id, Name, Account.Name, Account.Owner.Name
FROM Contact
WHERE Account.Industry = 'Technology'
```

**Parent-to-child (subquery, use relationship name):**
```sql
SELECT Id, Name,
  (SELECT Id, LastName, Email FROM Contacts WHERE IsActive__c = true LIMIT 10)
FROM Account
WHERE Industry = 'Technology'
LIMIT 50
```

Standard relationship names: `Contacts`, `Opportunities`, `Cases`, `Tasks`, `Events`, `Notes`
Custom relationship names: use the `__r` suffix (e.g., `Invoices__r`)

### Aggregate query patterns
```sql
-- Group by with having (find duplicates, top accounts, etc.)
SELECT AccountId, Account.Name, COUNT(Id) oppCount, SUM(Amount) totalAmount
FROM Opportunity
WHERE StageName = 'Closed Won' AND CloseDate = THIS_YEAR
GROUP BY AccountId, Account.Name
HAVING COUNT(Id) > 5
ORDER BY SUM(Amount) DESC
LIMIT 20
```

**Date functions in aggregates:**
```sql
SELECT CALENDAR_YEAR(CloseDate) yr, CALENDAR_QUARTER(CloseDate) qtr, SUM(Amount) total
FROM Opportunity
WHERE StageName = 'Closed Won'
GROUP BY CALENDAR_YEAR(CloseDate), CALENDAR_QUARTER(CloseDate)
ORDER BY CALENDAR_YEAR(CloseDate) DESC, CALENDAR_QUARTER(CloseDate) DESC
```

## Metadata naming conventions

When creating custom objects, fields, or other metadata, follow these naming standards:

### Custom objects
- **Format**: `PascalCase__c`, singular noun
- **Max length**: 40 characters
- **Good**: `Invoice__c`, `Product_Catalog__c`, `Service_Request__c`
- **Bad**: `Invoices__c` (plural), `Inv__c` (abbreviated), `SvcReq__c` (cryptic)

### Custom fields
- **Format**: `Descriptive_Name__c`, PascalCase with underscores
- **Max length**: 40 characters
- **Use suffixes for clarity**: `_Date`, `_Amount`, `_Count`, `_Percent`, `_Flag`, `_Code`
- **Good**: `Total_Amount__c`, `Due_Date__c`, `Is_Active_Flag__c`
- **Bad**: `Amt__c`, `Field1__c`, `TCV__c`

### Permission sets
- **Format**: `[Feature]_[AccessLevel]`
- **Good**: `Invoice_Full_Access`, `Sales_Data_Read_Only`, `ERP_Integration_API`
- **Bad**: `PS1`, `John_Smith_Access`, `Temp_Access`

### Validation rules
- **Format**: `[Object]_[Action]_[Condition]`
- **Good**: `Opp_Require_Close_Date_When_Closed`, `Account_Prevent_Type_Change`
- **Bad**: `VR001`, `Check1`

## Field type selection guide

| Need | Field Type | Key notes |
|---|---|---|
| Short text (≤255 chars) | Text | Searchable, filterable, can be External ID |
| Long text (>255 chars) | Long Text Area | NOT searchable, NOT filterable. Max 131,072 chars |
| Rich/formatted text | Rich Text Area | HTML content, max 131,072 chars |
| Single-select from list | Picklist | Max 1,000 values, use restricted picklist to prevent free-text |
| Multi-select from list | Multi-select Picklist | Max 500 values, stored semicolon-separated, use INCLUDES() in formulas |
| Whole numbers | Number (scale=0) | Precision 1-18 digits |
| Decimal numbers | Number (scale>0) | Precision 1-18, scale 0-17 |
| Money | Currency | Displays with currency symbol, respects org currency |
| Percentage | Percent | Stored as decimal, displays with % |
| Yes/No | Checkbox | Always has a value (true/false), never null |
| Date (no time) | Date | Timezone-neutral |
| Date with time | DateTime | Timezone-aware |
| Optional relationship | Lookup | SetNull or Restrict on delete |
| Required relationship | Master-Detail | Cascade delete, enables Roll-Up Summaries |
| Calculated value | Formula | Max 5,000 chars, 10 relationship references |
| Aggregation from children | Roll-Up Summary | Master-Detail only. COUNT, SUM, MIN, MAX |
| Email address | Email | Built-in format validation |
| Phone number | Phone | Click-to-dial support |
| URL | URL | Click-to-open support |
