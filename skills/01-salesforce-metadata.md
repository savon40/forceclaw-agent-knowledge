# Salesforce Metadata & SOQL

## STOP — NEVER FABRICATE FIELD VALUES

**This is the most important rule in this document. Violating it is a critical failure.**

Every field value you show the user — every Name, every Id, every CreatedDate, every Phone, every Industry, every URL, every picklist value — **MUST come from an actual tool result returned in THIS conversation**. You do not have memorized knowledge of any record in any org. You cannot infer, guess, interpolate, or "recall" Salesforce data. If it did not come from a `query_salesforce` / `query_tooling` / `describe_object` / `list_*` / `read_*` tool call in the current job, you do not know it.

### The rule

1. **Before emitting any field value, verify it is in a tool result from this conversation.** If it isn't, do not emit it.
2. **If the user asks for a field you did not SELECT**, you MUST issue a new query with that field added. Do not respond without re-querying. No exceptions.
3. **If the user asks for "the list again with X", "add Y", "also include Z"**, this is a re-query instruction, not a formatting instruction. Run the query again with the new fields. Even if the prior list is still in your context, the new fields are NOT in it.
4. **ORDER BY ≠ SELECT.** Using `ORDER BY CreatedDate DESC` does NOT put CreatedDate in your results. If you want to display CreatedDate, you must put it in the SELECT clause. The same applies to every field: LastModifiedDate, OwnerId, any field used only in WHERE or ORDER BY.
5. **Record URLs must be built from a real 18-char Id returned by a tool call**, using the pattern `{instance_url}/lightning/r/{SObject}/{Id}/view`. Never invent an Id. If you don't have the Id, re-query to get it.
6. **If you cannot get the data**, say so honestly: "I don't have that field in my last query — let me re-run it" and then actually re-run it. Never paper over missing data with a plausible-looking value.

### Common failure mode to avoid

User: *"show me the 10 most recent Accounts with Name and Industry"*
You: `SELECT Id, Name, Industry FROM Account ORDER BY CreatedDate DESC LIMIT 10` → returns 10 rows.
User: *"give me the list again with the created date and a link"*

**WRONG:** Reply with the same 10 rows and make up CreatedDate values. The previous query did not SELECT CreatedDate — you have no CreatedDate data. Fabricating one is a critical failure.

**RIGHT:** Re-run the query with CreatedDate added: `SELECT Id, Name, Industry, CreatedDate FROM Account ORDER BY CreatedDate DESC LIMIT 10`. Then build the link from the real Id and the instance URL.

### Proactive queries

When the user's initial request implies fields they'll likely want, include them in the SELECT the first time:

- "most recent X" / "recently created X" → include `CreatedDate`
- "most recently updated X" → include `LastModifiedDate`
- "who owns X" → include `Owner.Name`
- "list X with a link" → include `Id` (required to build the URL)
- "X by user Y" → include `CreatedBy.Name` or `Owner.Name` as relevant

A second tool call is cheap. Fabricated data is a product-killing bug. When in doubt, re-query.

---

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

**Use `query_salesforce` (standard SOQL) for:** data objects (Account, Contact, Opportunity, Case, etc.), `FlowDefinitionView`, `FlowVersionView`, `User`, `PermissionSet`, `PermissionSetAssignment`, `ObjectPermissions`, `FieldPermissions`, `UserRole`, `RecordType`, `Profile`.

**NEVER query objects ending in `__hd`, `__x`, `__xo`, `__b`, or any non-standard suffix.** These are internal Salesforce objects and will error. The only valid custom suffixes are `__c` (custom objects), `__mdt` (custom metadata), `__e` (platform events), and `__r` (relationship names in SOQL). If you need data about record types, use the `RecordType` standard object.

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
| `RecordType` | `Id`, `Name`, `DeveloperName`, `SobjectType`, `IsActive`, `Description`, `BusinessProcessId` | Record type lookups — use `DeveloperName` (not `Name`) for automation since it's translation-stable |
| `BusinessProcess` | `Id`, `Name`, `Description`, `IsActive`, `TableEnumOrId` (NOT `SobjectType`), `NamespacePrefix` | Business processes (Status sets for Case/Lead, StageName sets for Opportunity). **Filter parent object with `TableEnumOrId = 'Case'` — `BusinessProcess` does NOT have a `SobjectType` column** (only RecordType does). Only Case, Lead, and Opportunity ever have business processes. |
| `Profile` | `Id`, `Name`, `UserType` | Profile lookups |

### Queryable via Tooling API only (`query_tooling` tool)
| sObject | Key fields | Use for |
|---------|-----------|---------|
| `ValidationRule` | `ValidationName`, `Active`, `Description`, `ErrorMessage`, `EntityDefinition.QualifiedApiName` — `Metadata`/`FullName` single-row only (formula is inside `Metadata`) | Validation rules |
| `WorkflowRule` | `Name`, `TableEnumOrId` | Legacy workflow rules — NOT in standard SOQL |
| `FlowDefinition` | `DeveloperName`, `MasterLabel`, `ActiveVersionId`, `LatestVersionId`, `Description` — does NOT have ProcessType, TriggerType, Status | Flow metadata (prefer FlowDefinitionView for listing) |
| `Flow` | `Id`, `DefinitionId`, `FullName`, `MasterLabel`, `ProcessType`, `Status`, `VersionNumber`, `Metadata`, `ApiVersion`, `Description`, `Environments`, `IsTemplate`, `ManageableState`, `RunInMode`, `TimeZoneSidKey` — does NOT have `DeveloperName`, `TriggerType`, `RecordTriggerType`, `TriggerObjectOrEventLabel`. To find by name, query `FlowDefinition` first by `DeveloperName`, then get `Flow` by version ID. | Flow version metadata via Tooling API only |
| `CustomField` | `DeveloperName`, `FullName`, `TableEnumOrId`, `EntityDefinitionId`, `EntityDefinition.QualifiedApiName` (parent filter), `Metadata` (JSON blob with type/length/picklist/etc.) | Custom field definitions — see "CustomField field reference" below for the full list |
| `ApexClass` | `Name`, `Body`, `Status`, `ApiVersion` | Apex class metadata + source code |
| `ApexTrigger` | `Name`, `Body`, `TableEnumOrId`, `Status` | Trigger metadata + source code |
| `LightningComponentBundle` | `DeveloperName`, `MasterLabel`, `ApiVersion` | LWC bundles — Tooling API only |
| `AssignmentRule` | `Name`, `SobjectType`, `Active` | Lead/case assignment rules |
| `FlexiPage` | `DeveloperName`, `MasterLabel`, `Type`, `EntityDefinitionId`, `Metadata` (single-row only) | Lightning Record Pages, Home Pages, App Pages. Use to check Dynamic Forms field placement |

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

**CRITICAL — CustomField has a limited set of top-level queryable columns. Most field attributes (type, length, picklist values, formula, etc.) live INSIDE a `Metadata` JSON blob, not as top-level columns.** Official reference: https://developer.salesforce.com/docs/atlas.en-us.api_tooling.meta/api_tooling/tooling_api_objects_customfield.htm

**Top-level queryable columns on CustomField:**
- `Id`
- `DeveloperName` — the field's API name WITHOUT the `__c` suffix (e.g. `My_Field`, not `My_Field__c`)
- `FullName` — `Object__c.Field__c` style full name (including suffix)
- `TableEnumOrId` — standard object API name OR 15-char EntityDefinition Id for custom objects. **DO NOT filter by this for custom objects** — use `EntityDefinition.QualifiedApiName` instead (see below).
- `EntityDefinitionId` — 18-char Id of the parent entity
- `EntityDefinition.QualifiedApiName` — the parent object API name (parent relationship filter — works for both standard AND custom objects)
- `ManageableState`, `NamespacePrefix`
- `Metadata` — JSON blob containing `type`, `label`, `description`, `length`, `precision`, `scale`, `required`, `picklistValues`, `formula`, `referenceTo`, `relationshipName`, `deleteConstraint`, etc. **Only returned when querying a single row by Id or filtering by a unique field** (Salesforce limitation).
- `RelationshipName`, `ReferenceTo` — for Lookup/Master-Detail relationships
- `CreatedDate`, `LastModifiedDate`

**Columns that DO NOT exist on CustomField** (common mistakes):
- `DataType` — lives inside `Metadata.type`, NOT as a top-level column
- `Label` — lives inside `Metadata.label`
- `Length`, `Precision`, `Scale` — inside `Metadata`
- `QualifiedApiName` — only on the parent `EntityDefinition` relationship, NOT on CustomField itself
- `Required` — inside `Metadata.required`

**Filter predicates that DO NOT work on CustomField:**
- `WHERE ReferenceTo = 'Opportunity'` — **invalid**. `ReferenceTo` is a multi-value field (a polymorphic lookup can reference multiple objects) and the Tooling API will reject any direct `=` filter on it with `ERROR at Row:1:Column:N`. You cannot use `LIKE`, `INCLUDES`, or `IN` against it either. **There is no way to query CustomField directly to find "all custom fields referencing object X".** Use `describe_object` on the *target* object and read its `childRelationships` array instead — every custom field that references that object shows up there with `field`, `relationshipName`, and `childSObject`. See the "What objects have a relationship to [Object]?" recipe below.
- `WHERE Metadata != null` — **invalid**. `Metadata` is a compound JSON field and cannot appear in any `WHERE` clause predicate (not `!= null`, not `= null`, not `LIKE`). It can only appear in the `SELECT` list, and only when the query returns exactly one row.
- `WHERE Metadata.type = 'Lookup'` — **invalid**. You cannot filter on fields *inside* the `Metadata` JSON blob. If you need to find all Lookup fields on an object, fetch them via `describe_object` (which returns `type` for every field), or query CustomFields one at a time and inspect `Metadata.type` in code.

**Listing custom fields on an object (STANDARD or CUSTOM):**
```sql
SELECT Id, DeveloperName, FullName
FROM CustomField
WHERE EntityDefinition.QualifiedApiName = 'Account'
ORDER BY DeveloperName
```
This works for both standard objects (`Account`) and custom objects (`My_Object__c`). **Always use `EntityDefinition.QualifiedApiName` for the filter, never `TableEnumOrId`** — `TableEnumOrId` contains the 15-char EntityDefinition Id (not the API name) for custom objects, so `WHERE TableEnumOrId = 'My_Object__c'` always returns zero rows for custom objects.

**Getting a field's full metadata (type, length, picklist values, etc.):**
```sql
SELECT Id, DeveloperName, FullName, Metadata
FROM CustomField
WHERE Id = '00N...'
```
The `Metadata` field can only be retrieved one row at a time (by Id or a unique identifier). You cannot include it in multi-row queries.

**If the user asks "what type is field X?"** — describe_object is usually faster than query_tooling. Only use CustomField.Metadata when you need info that describe_object doesn't return (like the raw formula source or deleteConstraint).

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
**Use `query_tooling`** (CustomField is Tooling API only). Note: CustomField does NOT have a `DataType` top-level column — that info is inside the `Metadata` JSON blob. For a "what fields" summary, stick to simple columns:
```sql
SELECT Id, DeveloperName, FullName, CreatedDate, CreatedBy.Name
FROM CustomField
WHERE CreatedDate = LAST_N_DAYS:30
ORDER BY CreatedDate DESC
LIMIT 50
```
If you need the type of a specific field, query by `Id` and include `Metadata` (type lives in `Metadata.type`):
```sql
SELECT Id, FullName, Metadata FROM CustomField WHERE Id = '00N...'
```

### "Show me formula fields on [Object]"
Use `describe_object` and filter for fields where `calculatedFormula` is not null.

### "What objects have a relationship to [Object]?" / "What references [Object]?"
**Use `describe_object` on the target object — do NOT try to query CustomField for this.**

The describe response contains a `childRelationships` array. Every entry is one object that points TO the target via a Lookup or Master-Detail field. Each entry includes:
- `childSObject` — the API name of the referencing object (e.g. `OpportunityContactRole`, `My_Custom_Object__c`)
- `field` — the API name of the field on the child object that holds the reference (e.g. `OpportunityId`, `Account__c`)
- `relationshipName` — the SOQL relationship name for subqueries (e.g. `OpportunityContactRoles`, `My_Custom_Objects__r`); `null` if there is no inverse relationship
- `cascadeDelete` — `true` indicates Master-Detail (delete cascades)
- `restrictedDelete` — `true` indicates a lookup with "Don't allow deletion" set

This single `describe_object` call returns the complete answer for both standard AND custom child objects in one shot. It is faster, cheaper, and more accurate than any Tooling API alternative.

**To find fields ON the target object that point OUT to other objects** (the parent direction), look at the same `describe_object` response's `fields` array — each field with `type: "reference"` has a `referenceTo` array listing the object(s) it can point to.

**Anti-patterns — these all fail:**
```sql
-- INVALID: ReferenceTo is multi-value, cannot be filtered with =
SELECT Id, DeveloperName, ReferenceTo FROM CustomField WHERE ReferenceTo = 'Opportunity'

-- INVALID: Metadata cannot appear in WHERE at all
SELECT Id, DeveloperName FROM CustomField WHERE Metadata != null

-- INVALID: cannot reach inside the Metadata JSON in a WHERE clause
SELECT Id FROM CustomField WHERE Metadata.type = 'Lookup'
```

If you genuinely need to find references **across the entire org** (not for one target object) — for example "list every lookup field in the org and what it points to" — there is no clean Tooling API query for that. The only correct approach is to iterate over objects and call `describe_object` on each, then collect the `reference`-typed fields. Don't fake it with CustomField filters.

### "What record types exist on [Object]?"
**Use `query_salesforce`** (RecordType is a standard SOQL object — NOT Tooling API):
```sql
SELECT Id, Name, DeveloperName, IsActive, Description
FROM RecordType
WHERE SobjectType = 'Opportunity'
ORDER BY Name
```

### "What business processes exist on Case / Lead / Opportunity?"
**Use `query_salesforce`** (BusinessProcess is a standard SOQL object). **Filter by `TableEnumOrId`, NOT `SobjectType`** — that's a common mistake (`SobjectType` is the column on `RecordType`, not on `BusinessProcess`):
```sql
SELECT Id, Name, Description, IsActive
FROM BusinessProcess
WHERE TableEnumOrId = 'Case' AND IsActive = true
ORDER BY Name
```
Only Case, Lead, and Opportunity ever have business processes — querying any other value returns zero rows.

### "Create a new record type on Case / Lead / Opportunity"
**Case, Lead, and Opportunity record types REQUIRE a Business Process.** Salesforce will reject `create_record_type` with `Required field is missing: businessProcess` if you don't supply one. The `create_record_type` tool now also fails fast with a clear message in this case. Workflow:

1. **Find or create a business process** — first query existing ones (recipe above). If one fits the user's needs, use its `Name` (which is the DeveloperName).
2. **If you need a new business process,** check that all the Status (Case/Lead) or StageName (Opportunity) values you want to expose already exist on the picklist field. Use `describe_object` on the parent object and look at `fields[].picklistValues` for `Status` or `StageName`.
3. **If any picklist values are missing,** add them first with `add_picklist_values` — `BusinessProcess` can ONLY reference values that already exist on the picklist field.
4. **Call `create_business_process`** with `object_name`, `process_name`, and the ordered list of `picklist_values` to expose. Optionally pass a `default_value` (otherwise the first value is the default).
5. **Then call `create_record_type`** with `business_process` set to the new process's `process_name`.

For Account, Contact, custom objects, and any other object that supports record types, you can call `create_record_type` directly without a business process — they don't use them.

### "Which profiles have access to record type X?"
Use the `read_profile_record_type_visibility` tool to check visibility per profile.

### "Give all profiles access to record type X" / "Grant record type visibility"
You CAN do this — use `update_profile_record_type_defaults` for each profile. Steps:
1. Query all profiles: `SELECT Id, Name FROM Profile`
2. For each profile, call `update_profile_record_type_defaults` with `record_type: "Object.RecordTypeDeveloperName"`, `visible: true`
3. Use the standard profile name-to-API-name mapping (e.g., "System Administrator" → "Admin", "Standard User" → "Standard") since the Metadata API uses API names

**Important Salesforce fact:** Record type access is managed on the **Profile** page in Setup (Setup → Users → Profiles → [Profile] → Record Type Settings), NOT on the Record Type page. There is NO "Profile Assignments" section on the Record Type detail page. Do not tell users to go to the Record Type page to assign profiles.

### "What objects exist in this org?"
Use the `list_objects` tool. To filter to custom objects only, look for API names ending in `__c`.

## Required fields — page layouts and FLS gotchas

Required fields (fields created with `required: true`, like a required custom text field, a Master-Detail field, or a system field) behave differently from optional fields in a few ways that trip up automation. Knowing these saves wasted tool calls.

### Required fields are auto-placed on every page layout
Salesforce automatically places required fields on every page layout in a dedicated required-fields section. **You cannot add them to additional sections** — Salesforce will reject the layout update with:
```
FIELD_INTEGRITY_EXCEPTION: Field: field, value:My_Field__c appears more than once
```

When using `update_page_layout` with `action: "add_section"` or `action: "add"`, **do NOT include required fields in the field list**. They're already on the layout. If you got the field list from the user's request and one of them is required (e.g. the object's `Name` field, or a required custom field you just created with `required: true`), filter it out before adding the rest to the new section.

If you're not sure whether a field is required, call `describe_object` and check `fields[].nillable` — `nillable: false` AND `defaultedOnCreate: false` means the field is required and will be auto-placed.

### FLS is a no-op on required fields
Required fields are always readable and editable for any user with object access — there is no FLS to set. The `set_field_level_security` tool detects this case and short-circuits with a success message like:
> Skipped — `Object.Field__c` is a required field, so field-level security is automatically enforced for all profiles…

This is normal and expected. **Do not interpret it as an error** — there is genuinely nothing to do at the FLS layer. If the user wants the field to be optional (so FLS becomes meaningful), call `update_custom_field` with `required: false` first, then set FLS.

### Workflow: creating a required field on a new object
The common pattern that hits both gotchas at once is: "create object → create required field → set FLS for profiles → add field to a section on the page layout." Here's the right order:

1. `create_custom_object` — creates the object
2. `create_custom_field` — for each field, including the required ones
3. `set_field_level_security` — for the **non-required** fields only. Skip required fields entirely; the tool will short-circuit them but it's cleaner to not call it at all.
4. `update_page_layout` (`add_section` or `add`) — for the **non-required** fields only. Required fields are already on the layout in the auto-placed required section.
5. `update_profile_object_permissions` — grant CRUD on the object to the profiles that need it
6. `update_profile_tab_visibility` — if you also created a custom tab, expose it on the right profiles

## Why a field might not be visible on a record page

When a user asks "why can't I see field X on this record," there are MULTIPLE possible reasons.
**Do NOT assume it's only a page layout issue.** Check ALL of these in order:

### 1. Field-Level Security (FLS)
The user's profile or permission sets may not grant visibility to the field.
- Query: `SELECT Id, Field, SobjectType, PermissionsRead, PermissionsEdit FROM FieldPermissions WHERE SobjectType = '{Object}' AND Field = '{Object}.{FieldName}'`
- Also check the user's profile and assigned permission sets

### 2. Lightning Record Page with Dynamic Forms (FlexiPage)
**IMPORTANT:** Many orgs use **Lightning Record Pages (FlexiPages)** with **Dynamic Forms** instead of traditional page layouts. When Dynamic Forms are enabled on an object:
- Fields are placed **directly on the FlexiPage**, NOT through the page layout
- The page layout's field section is replaced by individual field components on the FlexiPage
- A field can exist on the page layout but still NOT appear on the record page if the FlexiPage doesn't include it
- Fields on Dynamic Forms can have **visibility rules** (component visibility filters) that show/hide them based on record data

**How to check:** FlexiPages are queryable via the **Tooling API**.

**Step 1 — List FlexiPages for an object:**
```sql
SELECT Id, DeveloperName, MasterLabel, Type
FROM FlexiPage
WHERE EntityDefinitionId = 'Opportunity'
ORDER BY MasterLabel
```
Common `Type` values: `RecordPage` (Lightning Record Page), `HomePage`, `AppPage`.

**Step 2 — Read a specific FlexiPage's full structure (including Dynamic Form fields):**
```sql
SELECT Id, DeveloperName, MasterLabel, Metadata
FROM FlexiPage
WHERE DeveloperName = 'Opportunity_Record_Page'
LIMIT 1
```
**IMPORTANT:** The `Metadata` field can only be included when the query returns exactly 1 row (same restriction as ValidationRule.Metadata). Use `LIMIT 1` with a specific `DeveloperName`.

**Step 3 — Read the Metadata:**
The `Metadata` JSON contains `flexiPageRegions` → each region has `itemInstances` → each item has a `componentName` (e.g., `flexipage:fieldSection`, `flowruntime:interview`, etc.) and `fieldItem` references that list which fields are on the page.

Look for `fieldItem` entries — these are the fields placed via Dynamic Forms. If the field you're looking for is NOT in any `fieldItem`, that's why it's not visible.

### 3. Page Layout
The field may not be on the assigned page layout.
- Use `list_page_layouts` and `read_page_layout` to check
- Different record types can have different page layouts assigned
- Check which page layout the user's profile is assigned to for this record type

### 4. Record Type
The user may be viewing a record type that has a different page layout assigned.

### 5. The field is empty/null
Some admins hide empty fields. This is a Dynamic Forms visibility rule (e.g., "only show this field when it has a value").

### When investigating field visibility, always:
1. Check FLS first (FieldPermissions query)
2. Check if the object has FlexiPages with Dynamic Forms (query FlexiPage via Tooling API)
3. If a FlexiPage exists, read its Metadata to see if the field is placed on it
4. If no FlexiPage or Dynamic Forms, check the page layout
5. Tell the user exactly what you found — "The field is on the page layout but NOT on the Lightning Record Page" or "The field is missing from both"

**You CAN read FlexiPages** via the Tooling API `query_tooling` tool. You CANNOT currently modify them — if a field needs to be added to a FlexiPage, tell the user to do it in the Lightning App Builder.

---

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
