# Flow Building

## Current capabilities

- List all active Flows in the org
- Read full Flow definitions and metadata structure
- Create new Flows via the Metadata API (record-triggered, autolaunched, scheduled, screen)
- **Update existing Flows** — modify elements, add new logic, change conditions, add branches. Use `get_flow_definition` to read the current flow, modify the metadata, then save with `update_flow`. This works on active flows — the Metadata API creates a new version automatically. You do NOT need to deactivate a flow before updating it.
- Activate and deactivate existing Flows
- Delete Flows (must be deactivated first)
- Answer questions about what a Flow does based on its metadata

## CRITICAL: How to Block a Save / Show an Error in a Before Save Flow

When the user wants a flow to **prevent a record from being saved** and **show an error message**, you MUST use a **Custom Error** element — NOT an "Update Records" element that reverts the field value.

**Wrong approach (DO NOT DO THIS):**
- Using an Update Records element to set the field back to its prior value
- This doesn't actually block the save or show an error — it just silently reverts the field

**Correct approach — use a Custom Error element in the flow metadata:**
In the Flow metadata JSON, add a `customErrors` element. This is the Flow equivalent of `addError()` in Apex.

```json
{
  "name": "Show_Error_Open_Opportunities",
  "label": "Show Error: Open Opportunities",
  "locationX": 176,
  "locationY": 500,
  "customErrorMessages": [
    {
      "errorMessage": "Cannot change Status to Churned because there are open Opportunities. Please close or delete all Opportunities first.",
      "fieldSelection": "Status__c",
      "isFieldError": true
    }
  ]
}
```

- `customErrorMessages.errorMessage` — the error message shown to the user
- `customErrorMessages.fieldSelection` — optional field to show the error on (makes it a field-level error)
- `customErrorMessages.isFieldError` — `true` to show on the field, `false` to show at the top of the page
- Connect the Decision element's "error path" to this Custom Error element instead of an Update Records element

**The Custom Error element blocks the save entirely** — the record is NOT saved and the user sees the error message. This is the correct way to implement validation logic in a Before Save flow.

---

## CRITICAL: Flow Formula Functions — What EXISTS and What DOESN'T

**SIZE() does NOT exist in Flow formulas.** Do NOT use SIZE() to count a collection. It will cause a syntax error.

**To count records in a collection:**
Use an **Assignment element** with the **"Equals Count"** operator:
- Create a Number variable (e.g., `OppCount`)
- Add an Assignment element
- Set: `OppCount` → **Equals Count** → `{!Get_Open_Opportunities}`
- This counts the records in the collection and stores it in the variable

**Available Flow formula functions** (ONLY use these — anything not on this list will error):

**Math:** ABS, CEILING, MCEILING, FLOOR, MFLOOR, ROUND, TRUNC, MOD, SQRT, EXP, LN, LOG, MAX, MIN

**Text:** LEN, UPPER, LOWER, INITCAP, LEFT, RIGHT, MID, TRIM, LPAD, RPAD, SUBSTITUTE, CONTAINS, BEGINS, FIND, REVERSE, HTMLENCODE, JSENCODE, URLENCODE, TEXT, VALUE

**Date/Time:** TODAY, NOW, DATE, DATEVALUE, DATETIMEVALUE, DAY, MONTH, YEAR, WEEKDAY, ADDMONTHS, DAYOFYEAR, ISOWEEK, ISOYEAR, FORMATDURATION, FROMUNIXTIME, UNIXTIMESTAMP

**Logical:** IF, AND, OR, NOT, CASE, ISBLANK, ISNULL, ISNUMBER, ISCLONE, ISNEW, ISCHANGED, PRIORVALUE

**Other:** REGEX, GEOLOCATION, DISTANCE, CURRENCYRATE, NULLVALUE, BLANKVALUE

**Functions that DO NOT exist in Flow (common mistakes):**
- `SIZE()` — use Assignment with "Equals Count" operator instead
- `COUNT()` — this is SOQL, not a Flow formula
- `VLOOKUP()` — use a Get Records element instead
- `HYPERLINK()` — not available in Flow formulas
- `IMAGE()` — not available in Flow formulas

---

## Flow types

| Type | processType | triggerType | When to use |
|------|------------|-------------|-------------|
| **Record-Triggered (Before Save)** | `AutoLaunchedFlow` | `RecordBeforeSave` | Field updates on the same record — fastest, no DML limits |
| **Record-Triggered (After Save)** | `AutoLaunchedFlow` | `RecordAfterSave` | Need to create/update related records or call external services |
| **Screen Flow** | `Flow` | *(none)* | Interactive — user fills out screens, launched via button/link/page |
| **Autolaunched Flow** | `AutoLaunchedFlow` | *(none)* | Background processing, invoked by other automation or Apex |
| **Scheduled Flow** | `AutoLaunchedFlow` | `Scheduled` | Runs on a schedule against a set of records |
| **Platform Event-Triggered** | `AutoLaunchedFlow` | `PlatformEvent` | Runs when a platform event is published |

## Querying flow metadata — STOP and read this before querying

There are 4 different flow-related objects and they have DIFFERENT fields. Using the wrong field on the wrong object causes errors. **Always use the exact fields listed below.**

### FlowDefinitionView — USE THIS FOR LISTING FLOWS
**API:** Standard SOQL (`query_salesforce`). **NOT** Tooling API.
This is the **best object for listing flows** because it has TriggerType, IsActive, and the trigger object label.

**Available fields:**
`Id`, `DurableId`, `ApiName`, `Label`, `Description`, `ProcessType`, `TriggerType`, `TriggerObjectOrEventId`, `TriggerObjectOrEventLabel`, `RecordTriggerType`, `IsActive`, `ActiveVersionId`, `LatestVersionId`, `ManageableState`, `NamespacePrefix`, `IsTemplate`, `RunInMode`, `SourceTemplate`

**Example: List all record-triggered flows on Opportunity**
```sql
SELECT ApiName, Label, ProcessType, TriggerType, RecordTriggerType,
       TriggerObjectOrEventLabel, IsActive
FROM FlowDefinitionView
WHERE TriggerObjectOrEventLabel = 'Opportunity'
  AND IsActive = true
ORDER BY Label
LIMIT 200
```

**Example: List all active flows by type**
```sql
SELECT ApiName, Label, ProcessType, TriggerType, TriggerObjectOrEventLabel, IsActive
FROM FlowDefinitionView
WHERE IsActive = true
ORDER BY Label
LIMIT 200
```

**TriggerType values:** `RecordAfterSave`, `RecordBeforeSave`, `RecordBeforeDelete`, `Scheduled`, `PlatformEvent`
**RecordTriggerType values:** `Create`, `Update`, `CreateAndUpdate`, `Delete`

### FlowVersionView — for version history
**API:** Standard SOQL (`query_salesforce`). **NOT** Tooling API.

**Available fields:**
`Id`, `DurableId`, `FlowDefinitionViewId`, `Label`, `Description`, `Status`, `ProcessType`, `VersionNumber`, `ApiVersion`, `ApiVersionRuntime`, `RunInMode`, `IsTemplate`, `IsSwaddled`

**Example: Get version history for a flow**
```sql
SELECT Label, Status, ProcessType, VersionNumber, ApiVersion
FROM FlowVersionView
WHERE FlowDefinitionViewId = '[ID from FlowDefinitionView]'
ORDER BY VersionNumber DESC
LIMIT 10
```

### FlowDefinition — Tooling API only (limited fields)
**API:** Tooling API (`query_tooling`). Will error via standard SOQL.
Use this to look up the DeveloperName or check active version. Prefer FlowDefinitionView for listing.

**Available fields:**
`Id`, `DeveloperName`, `MasterLabel`, `ActiveVersionId`, `LatestVersionId`, `Description`, `NamespacePrefix`, `ManageableState`

**Does NOT have:** `ProcessType`, `TriggerType`, `Status`, `VersionNumber`, `IsActive`, `TriggerObjectOrEventLabel`

**Example:**
```sql
SELECT DeveloperName, ActiveVersionId, LatestVersionId, Description
FROM FlowDefinition
ORDER BY DeveloperName
LIMIT 200
```
A Flow is **active** when `ActiveVersionId` is not null.

### Flow — Tooling API only (flow version metadata)
**API:** Tooling API (`query_tooling`). Will error via standard SOQL.
Represents a specific flow VERSION. Use this to read full flow metadata or to filter by ProcessType/Status.

**Available fields:**
`Id`, `DefinitionId`, `Definition.DeveloperName`, `MasterLabel`, `ProcessType`, `Status`, `VersionNumber`, `Description`, `ApiVersion`, `FullName` (not filterable), `Metadata` (not filterable — returns full flow definition JSON), `CreatedDate`, `CreatedById`, `LastModifiedDate`, `LastModifiedById`

**Does NOT have:** `RecordTriggerType`, `TriggerType`, `TriggerOrder`, `TriggerObjectOrEvent`, `TriggerObjectOrEventLabel`

**Example: Get active flow versions**
```sql
SELECT Id, Definition.DeveloperName, MasterLabel, ProcessType, Status, VersionNumber
FROM Flow
WHERE Status = 'Active'
ORDER BY MasterLabel
LIMIT 200
```

**Example: Read full metadata for a specific flow**
```sql
SELECT Id, Metadata FROM Flow WHERE Definition.DeveloperName = 'My_Flow_Name'
```

### Quick reference — which field is on which object

| Field | FlowDefinitionView | FlowVersionView | FlowDefinition | Flow |
|-------|:-:|:-:|:-:|:-:|
| TriggerType | YES | no | no | no |
| RecordTriggerType | YES | no | no | no |
| TriggerObjectOrEventLabel | YES | no | no | no |
| IsActive | YES | no | no | no |
| ProcessType | YES | YES | no | YES |
| Status | no | YES | no | YES |
| VersionNumber | no | YES | no | YES |
| DeveloperName | no (use ApiName) | no | YES | no |
| ActiveVersionId | YES | no | YES | no |
| Metadata (full JSON) | no | no | no | YES |

## Building Flows

### Flow metadata structure (JSON → Metadata API)

The `create_flow` tool accepts a JSON `metadata` object that mirrors the Flow XML structure. Key top-level properties:

```
metadata: {
  processType       — "AutoLaunchedFlow" | "Flow" | etc.
  apiVersion        — "62.0" (always use 62.0)
  status            — "Active" or "Draft"
  interviewLabel    — e.g. "My_Flow {!$Flow.CurrentDateTime}"
  environments      — "Default"
  description       — what the flow does

  start             — the entry point (trigger config, entry conditions)
  decisions         — array of decision elements (if/else branching)
  assignments       — array of variable assignments
  recordLookups     — array of record lookup (Get Records) elements
  recordCreates     — array of record create elements
  recordUpdates     — array of record update elements
  recordDeletes     — array of record delete elements
  formulas          — array of formula resources
  textTemplates     — array of text template resources
  variables         — array of flow variables
  actionCalls       — array of action calls (send email, post to Slack, invoke subflow, etc.)
  loops             — array of loop elements
  screens           — array of screen elements (Screen Flows only)
  collectionProcessors — array of collection processors (sort, filter)

  processMetadataValues — builder metadata, always include:
    [
      { name: "BuilderType", value: { stringValue: "LightningFlowBuilder" } },
      { name: "CanvasMode", value: { stringValue: "AUTO_LAYOUT_CANVAS" } },
      { name: "OriginBuilderType", value: { stringValue: "LightningFlowBuilder" } }
    ]
}
```

### Element connectors

Every element that leads to another element needs a `connector` with `targetReference` pointing to the next element's `name`:

```json
{
  "name": "My_Decision",
  "rules": [{
    "name": "Yes_Outcome",
    "connector": { "targetReference": "Update_Record" },
    "conditionLogic": "and",
    "conditions": [...]
  }],
  "defaultConnector": { "targetReference": "End_Flow" }
}
```

### Start element for record-triggered flows

```json
{
  "start": {
    "locationX": 0,
    "locationY": 0,
    "object": "Account",
    "recordTriggerType": "CreateAndUpdate",
    "triggerType": "RecordBeforeSave",
    "connector": { "targetReference": "First_Element" },
    "filterLogic": "and",
    "filters": [
      {
        "field": "StageName",
        "operator": "EqualTo",
        "value": { "stringValue": "Closed Won" }
      }
    ]
  }
}
```

**`recordTriggerType` values:** `Create`, `Update`, `CreateAndUpdate`, `Delete`
**`triggerType` values:** `RecordBeforeSave`, `RecordAfterSave`

For after-save flows that should run asynchronously, use `scheduledPaths` with `AsyncAfterCommit`:
```json
{
  "start": {
    "object": "Case",
    "recordTriggerType": "Create",
    "triggerType": "RecordAfterSave",
    "scheduledPaths": [{
      "connector": { "targetReference": "First_Element" },
      "pathType": "AsyncAfterCommit"
    }]
  }
}
```

### Decision elements

```json
{
  "name": "Check_Stage",
  "label": "Check Stage",
  "description": "Check if the Opportunity stage is Closed Won",
  "locationX": 0,
  "locationY": 0,
  "defaultConnectorLabel": "Default Outcome",
  "defaultConnector": { "targetReference": "Some_Other_Element" },
  "rules": [{
    "name": "Is_Closed_Won",
    "label": "Is Closed Won",
    "conditionLogic": "and",
    "conditions": [{
      "leftValueReference": "$Record.StageName",
      "operator": "EqualTo",
      "rightValue": { "stringValue": "Closed Won" }
    }],
    "connector": { "targetReference": "Update_Close_Date" }
  }]
}
```

**`conditionLogic`:** `and`, `or`, or custom like `1 AND (2 OR 3)`
**Operators:** `EqualTo`, `NotEqualTo`, `GreaterThan`, `LessThan`, `GreaterThanOrEqualTo`, `LessThanOrEqualTo`, `Contains`, `StartsWith`, `EndsWith`, `IsNull`, `IsChanged`, `WasSet`

### Record update elements (before-save — same record)

For before-save flows, use `$Record` to update fields on the triggering record:
```json
{
  "name": "Set_Close_Date",
  "label": "Set Close Date",
  "locationX": 0,
  "locationY": 0,
  "inputAssignments": [{
    "field": "CloseDate",
    "value": { "elementReference": "$Flow.CurrentDate" }
  }]
}
```

### Record update elements (after-save — update related records)

```json
{
  "name": "Update_Parent_Account",
  "label": "Update Parent Account",
  "locationX": 0,
  "locationY": 0,
  "object": "Account",
  "filterLogic": "and",
  "filters": [{
    "field": "Id",
    "operator": "EqualTo",
    "value": { "elementReference": "$Record.AccountId" }
  }],
  "inputAssignments": [{
    "field": "Last_Opportunity_Date__c",
    "value": { "elementReference": "$Flow.CurrentDate" }
  }]
}
```

### Record create elements

```json
{
  "name": "Create_Task",
  "label": "Create Follow-up Task",
  "locationX": 0,
  "locationY": 0,
  "object": "Task",
  "connector": { "targetReference": "Next_Element" },
  "inputAssignments": [
    { "field": "Subject", "value": { "stringValue": "Follow up on closed opportunity" } },
    { "field": "WhoId", "value": { "elementReference": "$Record.ContactId" } },
    { "field": "OwnerId", "value": { "elementReference": "$Record.OwnerId" } },
    { "field": "ActivityDate", "value": { "elementReference": "DueDateFormula" } },
    { "field": "Status", "value": { "stringValue": "Not Started" } }
  ]
}
```

### Formula resources

```json
{
  "name": "DueDateFormula",
  "dataType": "Date",
  "expression": "{!$Flow.CurrentDate} + 7"
}
```

### Assignment elements

```json
{
  "name": "Set_Variables",
  "label": "Set Variables",
  "locationX": 0,
  "locationY": 0,
  "assignmentItems": [{
    "assignToReference": "myVariable",
    "operator": "Assign",
    "value": { "elementReference": "$Record.Name" }
  }],
  "connector": { "targetReference": "Next_Element" }
}
```

### Value references

- `$Record` — the triggering record (record-triggered flows only)
- `$Record__Prior` — the record's values BEFORE the update (only in update-triggered flows)
- `$Flow.CurrentDate` — today's date
- `$Flow.CurrentDateTime` — current date/time
- `$Api.Partner_Server_URL_290` — org instance URL (useful for building links)
- `{!VariableName}` — reference to a flow variable or formula (in text templates)
- Direct element references use just the element name: `"elementReference": "My_Formula"`

### Value types in conditions and assignments

```json
{ "stringValue": "some text" }
{ "booleanValue": true }
{ "numberValue": 42 }
{ "elementReference": "$Record.FieldName" }
{ "elementReference": "FormulaOrVariableName" }
```

## Record Lookup (Get Records) elements

Use `recordLookups` to query related records in a flow. This is how you check for child records, look up parent data, etc.

```json
{
  "name": "Get_Open_Opportunities",
  "label": "Get Open Opportunities",
  "locationX": 176,
  "locationY": 300,
  "object": "Opportunity",
  "filterLogic": "and",
  "filters": [
    {
      "field": "AccountId",
      "operator": "EqualTo",
      "value": { "elementReference": "$Record.Id" }
    },
    {
      "field": "IsClosed",
      "operator": "EqualTo",
      "value": { "booleanValue": false }
    }
  ],
  "getFirstRecordOnly": false,
  "storeOutputAutomatically": true,
  "connector": { "targetReference": "Check_Has_Open_Opps" }
}
```

- `getFirstRecordOnly: false` → returns a collection (for counting or looping)
- `getFirstRecordOnly: true` → returns a single record
- `storeOutputAutomatically: true` → auto-stores results (use the element name as the reference, e.g., `{!Get_Open_Opportunities}`)

---

## COMPLETE EXAMPLE: Before Save Validation Flow (Block save with error)

This is the most common pattern admins ask for. "Don't let users do X if Y exists."

**Full metadata for: "Prevent Account Status change to Churned if open Opportunities exist"**

```json
{
  "processType": "AutoLaunchedFlow",
  "apiVersion": "62.0",
  "interviewLabel": "Prevent_Account_Churn_With_Open_Opps {!$Flow.CurrentDateTime}",
  "environments": "Default",
  "status": "Active",
  "description": "Prevents Account Status from being changed to Churned when there are open Opportunities on the Account.",
  "processMetadataValues": [
    { "name": "BuilderType", "value": { "stringValue": "LightningFlowBuilder" } },
    { "name": "CanvasMode", "value": { "stringValue": "AUTO_LAYOUT_CANVAS" } },
    { "name": "OriginBuilderType", "value": { "stringValue": "LightningFlowBuilder" } }
  ],
  "start": {
    "locationX": 176,
    "locationY": 0,
    "object": "Account",
    "recordTriggerType": "Update",
    "triggerType": "RecordBeforeSave",
    "connector": { "targetReference": "Get_Open_Opportunities" },
    "filterLogic": "and",
    "filters": [
      {
        "field": "Status__c",
        "operator": "IsChanged",
        "value": { "booleanValue": true }
      },
      {
        "field": "Status__c",
        "operator": "EqualTo",
        "value": { "stringValue": "Churned" }
      }
    ]
  },
  "recordLookups": [
    {
      "name": "Get_Open_Opportunities",
      "label": "Get Open Opportunities",
      "locationX": 176,
      "locationY": 200,
      "object": "Opportunity",
      "filterLogic": "and",
      "filters": [
        {
          "field": "AccountId",
          "operator": "EqualTo",
          "value": { "elementReference": "$Record.Id" }
        },
        {
          "field": "IsClosed",
          "operator": "EqualTo",
          "value": { "booleanValue": false }
        }
      ],
      "getFirstRecordOnly": true,
      "storeOutputAutomatically": true,
      "connector": { "targetReference": "Has_Open_Opportunities" }
    }
  ],
  "decisions": [
    {
      "name": "Has_Open_Opportunities",
      "label": "Has Open Opportunities?",
      "locationX": 176,
      "locationY": 400,
      "defaultConnectorLabel": "No Open Opps",
      "rules": [
        {
          "name": "Open_Opps_Found",
          "label": "Open Opps Found",
          "conditionLogic": "and",
          "conditions": [
            {
              "leftValueReference": "Get_Open_Opportunities",
              "operator": "IsNull",
              "rightValue": { "booleanValue": false }
            }
          ],
          "connector": { "targetReference": "Show_Error" }
        }
      ]
    }
  ],
  "customErrors": [
    {
      "name": "Show_Error",
      "label": "Show Error: Open Opportunities Exist",
      "locationX": 176,
      "locationY": 600,
      "customErrorMessages": [
        {
          "errorMessage": "Cannot change Account Status to Churned because there are open Opportunities. Please close or delete all Opportunities first.",
          "fieldSelection": "Status__c",
          "isFieldError": true
        }
      ]
    }
  ]
}
```

**Key points about this pattern:**
- `getFirstRecordOnly: true` — we only need to know IF any exist, not get all of them
- Decision checks if the lookup result `IsNull = false` (i.e., a record was found)
- `customErrors` element blocks the save and shows the error — NOT an Update Records element
- Entry conditions use `IsChanged` + `EqualTo` so the flow only fires when Status actually changes to Churned

---

## COMPLETE EXAMPLE: Before Save Field Update Flow

**"Set Close Date to today when Opportunity Stage changes to Closed Won"**

```json
{
  "processType": "AutoLaunchedFlow",
  "apiVersion": "62.0",
  "status": "Active",
  "start": {
    "locationX": 176,
    "locationY": 0,
    "object": "Opportunity",
    "recordTriggerType": "Update",
    "triggerType": "RecordBeforeSave",
    "connector": { "targetReference": "Set_Close_Date" },
    "filterLogic": "and",
    "filters": [
      {
        "field": "StageName",
        "operator": "IsChanged",
        "value": { "booleanValue": true }
      },
      {
        "field": "StageName",
        "operator": "EqualTo",
        "value": { "stringValue": "Closed Won" }
      }
    ]
  },
  "recordUpdates": [
    {
      "name": "Set_Close_Date",
      "label": "Set Close Date to Today",
      "locationX": 176,
      "locationY": 200,
      "inputAssignments": [
        {
          "field": "CloseDate",
          "value": { "elementReference": "$Flow.CurrentDate" }
        }
      ]
    }
  ],
  "processMetadataValues": [
    { "name": "BuilderType", "value": { "stringValue": "LightningFlowBuilder" } },
    { "name": "CanvasMode", "value": { "stringValue": "AUTO_LAYOUT_CANVAS" } },
    { "name": "OriginBuilderType", "value": { "stringValue": "LightningFlowBuilder" } }
  ]
}
```

---

## Flow building workflow — plan, confirm, build (separate turns)

Building a flow is ALWAYS a two-turn process:

1. **Turn 1 (plan):** Gather context with read-only tools (query flows on the object, describe the object, read any existing flow you'd be updating). Generate a flowchart diagram with `generate_diagram`. Present the plan as text: what the flow does, its trigger, the elements, any assumptions. Ask "Should I go ahead?". **STOP the turn here.** Do NOT call `create_flow` or `update_flow` in this same response.
2. **Turn 2 (build):** After the user confirms ("yes", "build it", "go ahead", "looks good"), immediately call `create_flow` / `update_flow` with the full metadata JSON. No re-summarizing, no re-asking.

A single response must NEVER contain both a plan/diagram AND a `create_flow` / `update_flow` call. The diagram tool call itself does NOT count as confirmation — after generating the diagram, end the turn and let the user review it.

## Flow best practices

1. **Use before-save flows for same-record field updates** — they don't consume DML limits and are faster
2. **Use after-save flows when you need to create/update related records** or call external services
3. **Always add entry conditions** via `filters` on the `start` element to prevent unnecessary runs
4. **Use `IsChanged` operator** in entry conditions to only fire when specific fields change:
   ```json
   { "field": "StageName", "operator": "IsChanged", "value": { "booleanValue": true } }
   ```
5. **Set `locationX` and `locationY` to 0** for all elements — the Flow Builder auto-layout will position them
6. **Use descriptive element names** with underscores (e.g., `Check_Stage_Is_Closed_Won`)
7. **Always include `processMetadataValues`** for BuilderType, CanvasMode, and OriginBuilderType
8. **Use `apiVersion: "62.0"`** for compatibility
9. **Before-save vs after-save decision guide:**
   - Updating a field on the SAME record → before-save
   - Creating/updating OTHER records → after-save
   - Sending notifications → after-save (async preferred)
   - Both same-record and related-record updates → split into two flows (before + after)

## Bulk safety checklist — ALWAYS verify before deploying

Every Flow you build or modify must pass these checks:

### Critical bulk safety rules
| Rule | Why | How to verify |
|---|---|---|
| No Get Records inside loops | Hits SOQL governor limit (100 queries) | Check that no `recordLookups` element is inside a `loops` element |
| No Create/Update/Delete inside loops | Hits DML governor limit (150 statements) | Check that no `recordCreates`/`recordUpdates`/`recordDeletes` are inside `loops` |
| Use entry conditions on all record-triggered flows | Prevents unnecessary execution on every record save | Check `start.filters` — should never be empty |
| Use `IsChanged` in entry conditions when appropriate | Prevents re-firing when unrelated fields change | Add `IsChanged` operator for the fields you care about |
| Before-save for same-record updates | Before-save doesn't consume DML limits — it's faster | Don't use after-save if you're only updating `$Record` fields |

### Performance tips
- **Use Transform instead of Loop** for simple field mapping — Transform is 30-50% faster and runs server-side
- **Filter collections** instead of querying again — use collection filters when you already have the data
- **Limit subflow nesting depth** — max 50 levels allowed, but keep to 3-4 for maintainability

## Fault paths — ALWAYS add to DML operations

Every `recordCreates`, `recordUpdates`, and `recordDeletes` element MUST have a fault connector. Without fault paths, DML failures cause unhandled exceptions that are hard to debug.

### Pattern: Fault path with error logging
Add a `faultConnector` to every DML element that points to an error-handling element:

```json
{
  "name": "Create_Follow_Up_Task",
  "label": "Create Follow-up Task",
  "object": "Task",
  "faultConnector": { "targetReference": "Handle_Error" },
  "connector": { "targetReference": "Next_Step" },
  "inputAssignments": [...]
}
```

The error handler can:
- Log to a custom object (e.g., `Error_Log__c`)
- Send an email notification
- Set a status variable for downstream decisions
- Use `{!$Flow.FaultMessage}` to capture the error text

### Important fault path rules
- **Fault connectors cannot self-reference** — an element's fault path cannot point back to itself (deployment blocker)
- **Subflows must be deployed and activated before parent flows** — or deployment fails

## Flow XML gotchas — common deployment failures

| Issue | Problem | Fix |
|---|---|---|
| `storeOutputAutomatically: true` in recordLookups | Retrieves ALL fields including sensitive data — security risk | Explicitly list needed fields with `outputAssignments` |
| Relationship fields in recordLookups | Not supported (e.g., `Account.Name` in a Contact lookup) | Use a two-step query: Get Records for Contact → Get Records for Account using the AccountId |
| `$Record` vs `$Record__c` | `$Record` = triggering record; `$Record__c` doesn't exist | Always use `$Record` (no __c suffix) |
| Element ordering in XML | Root-level elements must be in alphabetical order | Sort: `actionCalls`, `assignments`, `decisions`, `formulas`, `recordCreates`, `recordLookups`, `recordUpdates`, `start`, `variables` |
| Missing `processMetadataValues` | Flow Builder won't render properly | Always include BuilderType, CanvasMode, OriginBuilderType |

## Subflow patterns

### When to use subflows
- **Reusable logic** shared across multiple flows (e.g., error logging, email alerts, record validation)
- **Breaking up complex flows** — keep each flow focused on one responsibility
- **Testability** — subflows can be tested independently

### Calling a subflow
```json
{
  "name": "Log_Error",
  "label": "Log Error",
  "actionType": "subflow",
  "actionName": "Sub_LogError",
  "connector": { "targetReference": "Next_Element" },
  "inputParameters": [
    { "name": "ErrorMessage", "value": { "elementReference": "$Flow.FaultMessage" } },
    { "name": "FlowName", "value": { "stringValue": "My_Flow_Name" } },
    { "name": "RecordId", "value": { "elementReference": "$Record.Id" } }
  ]
}
```

### Common reusable subflow ideas
| Subflow | Purpose | Inputs |
|---|---|---|
| `Sub_LogError` | Write error details to an Error_Log__c record | ErrorMessage, FlowName, RecordId |
| `Sub_SendEmailAlert` | Send a notification email | RecipientId, Subject, Body |
| `Sub_ValidateRecord` | Check required fields and business rules before save | RecordId, ObjectType |

## Flow testing checklist

Before activating any flow, verify:

- [ ] **Path coverage** — test every decision branch (every outcome, including the default)
- [ ] **Bulk test** — trigger with 200+ records at once (e.g., bulk data load or mass update)
- [ ] **Edge cases** — null values, empty collections, blank text fields, date boundaries
- [ ] **User context** — test with different profiles (admin, standard user, community user)
- [ ] **Error handling** — verify fault paths fire correctly when DML fails
- [ ] **Entry conditions** — verify the flow does NOT fire when conditions are not met
- [ ] **Before-save only updates $Record** — verify no DML elements exist in before-save flows (they'll fail)

## Flow type selection guide

| Need | Flow Type | triggerType | processType |
|---|---|---|---|
| Update fields on the same record when it's saved | Record-Triggered (Before Save) | `RecordBeforeSave` | `AutoLaunchedFlow` |
| Create/update related records when a record is saved | Record-Triggered (After Save) | `RecordAfterSave` | `AutoLaunchedFlow` |
| User fills out a form / wizard | Screen Flow | *(none)* | `Flow` |
| Background processing called by other automation or Apex | Autolaunched | *(none)* | `AutoLaunchedFlow` |
| Process records on a schedule (e.g., nightly cleanup) | Scheduled | `Scheduled` | `AutoLaunchedFlow` |
| React to platform events | Platform Event-Triggered | `PlatformEvent` | `AutoLaunchedFlow` |
| Multi-step process with approvals or wait states | Orchestrator | *(special)* | `Orchestrator` |
