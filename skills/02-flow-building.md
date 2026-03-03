# Flow Building

## Current capabilities

- List all active Flows in the org
- Read full Flow definitions and metadata structure
- Create new Flows via the Metadata API (record-triggered, autolaunched, scheduled, screen)
- Activate and deactivate existing Flows
- Answer questions about what a Flow does based on its metadata

## Flow types

| Type | processType | triggerType | When to use |
|------|------------|-------------|-------------|
| **Record-Triggered (Before Save)** | `AutoLaunchedFlow` | `RecordBeforeSave` | Field updates on the same record — fastest, no DML limits |
| **Record-Triggered (After Save)** | `AutoLaunchedFlow` | `RecordAfterSave` | Need to create/update related records or call external services |
| **Screen Flow** | `Flow` | *(none)* | Interactive — user fills out screens, launched via button/link/page |
| **Autolaunched Flow** | `AutoLaunchedFlow` | *(none)* | Background processing, invoked by other automation or Apex |
| **Scheduled Flow** | `AutoLaunchedFlow` | `Scheduled` | Runs on a schedule against a set of records |
| **Platform Event-Triggered** | `AutoLaunchedFlow` | `PlatformEvent` | Runs when a platform event is published |

## Querying Flows

### List all Flows (standard SOQL — preferred)
```sql
SELECT ApiName, Label, ProcessType, TriggerType, IsActive
FROM FlowDefinitionView
ORDER BY Label
LIMIT 200
```
Use `FlowDefinitionView` via the standard `query` tool — it has the `IsActive` field directly.

### Get Flow version details
```sql
SELECT MasterLabel, ProcessType, Status, VersionNumber
FROM FlowVersionView
WHERE FlowDefinitionViewId = '[ID from FlowDefinitionView]'
ORDER BY VersionNumber DESC
LIMIT 10
```

### List Flows via Tooling API (alternative)
```sql
SELECT DeveloperName, ActiveVersionId, LatestVersionId, Description
FROM FlowDefinition
ORDER BY DeveloperName
LIMIT 200
```
A Flow is **active** when `ActiveVersionId` is not null. It's on the **latest version** when `ActiveVersionId = LatestVersionId`.

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
