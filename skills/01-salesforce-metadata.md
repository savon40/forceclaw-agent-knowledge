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
