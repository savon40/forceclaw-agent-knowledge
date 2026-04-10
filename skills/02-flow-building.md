# Flow Building

## Current capabilities

- List all active Flows in the org
- Read full Flow definitions and metadata structure
- **Create new Flows** using the **simplified flow_definition format** (preferred) — describe the trigger, steps, and resources. The tool builds valid Salesforce metadata automatically. No need to provide locationX/Y, connectors, processMetadataValues, or any boilerplate.
- **Update existing Flows** — modify elements, add new logic, change conditions, add branches. Use `get_flow_definition` to read the current flow, modify the metadata, then save with `update_flow`. This works on active flows — the Metadata API creates a new version automatically. You do NOT need to deactivate a flow before updating it.
- Activate and deactivate existing Flows
- Delete Flows (must be deactivated first)
- Answer questions about what a Flow does based on its metadata

---

## CRITICAL: Creating Flows — Use the Simplified flow_definition Format

When calling `create_flow`, use the `flow_definition` parameter (NOT `metadata`). The tool builds all Salesforce metadata automatically. You only describe the intent.

### flow_definition structure

```json
{
  "type": "record_triggered",
  "trigger": {
    "object": "Contact",
    "when": "after_save",
    "record_events": "update",
    "entry_conditions": [
      { "field": "Email", "operator": "is_changed", "value": true }
    ]
  },
  "steps": [ ... ],
  "resources": [ ... ]
}
```

**type** — `"record_triggered"`, `"screen"`, `"autolaunched"`, or `"scheduled"`

**trigger** — required for record_triggered and scheduled:
- Record triggered: `{ object, when: "before_save"|"after_save", record_events: "create"|"update"|"create_and_update"|"delete", entry_conditions?, entry_condition_logic? }`
- Scheduled: `{ frequency: "once"|"daily"|"weekly", start_date, start_time, object?, filters?, filter_logic? }`

### Step types

Steps are an ordered array. **Connectors are auto-generated from the array order** — you never specify targetReference.

| Step type | Description |
|-----------|-------------|
| `get_records` | Query records. Fields: `object`, `filters`, `filter_logic?`, `first_record_only?`, `fields?` |
| `create_records` | Insert records. Fields: `object`, `field_values` |
| `update_records` | Update records. Fields: `target` (`"$Record"` or `{ object, filters }`), `field_values` |
| `delete_records` | Delete records. Fields: `object`, `filters` |
| `decision` | Branch logic. Fields: `rules` (array of `{ name, conditions, steps }`) + `default_steps?`, `default_label?` |
| `assignment` | Set variables. Fields: `assignments` (array of `{ target, operator, value/reference }`) |
| `loop` | Iterate collection. Fields: `collection`, `order?`, `loop_steps` |
| `send_email` | Send email (handles all emailSimple ceremony automatically). Fields: `to`, `subject`, `body` |
| `subflow` | Call another flow. Fields: `flow_name`, `inputs?`, `outputs?` |
| `custom_error` | Block save with error (before-save only). Fields: `message`, `field?` |
| `action_call` | Generic action. Fields: `action_name`, `action_type`, `input_parameters` |

### Fault handling

Add `handle_faults: true` to any step to auto-generate a fault handler that sends an error email. Or use `fault_target: "StepName"` to route to a specific step.

### Values and references

In filters, conditions, and field_values:
- Literal: `"value": "Closed Won"` or `"value": true` or `"value": 42`
- Reference: `"reference": "$Record.AccountId"` or `"reference": "Get_Account.Website"`
- In field_values: `{ "StageName": "Closed Won" }` for literal, `{ "OwnerId": { "ref": "Get_Queue.Id" } }` for reference

### Operators

Use simplified names — the tool maps them automatically:
`equals`, `not_equals`, `greater_than`, `less_than`, `greater_or_equal`, `less_or_equal`, `contains`, `starts_with`, `ends_with`, `is_null`, `is_changed`, `was_set`

### Resources

```json
"resources": [
  { "type": "formula", "name": "emailDomain", "data_type": "string", "expression": "..." },
  { "type": "variable", "name": "myVar", "data_type": "string", "is_collection": false },
  { "type": "text_template", "name": "emailBody", "text": "Hello {!$Record.Name}..." }
]
```

### Example: After-Save flow with email notification (DEV-10 pattern)

```json
{
  "type": "record_triggered",
  "trigger": {
    "object": "Contact",
    "when": "after_save",
    "record_events": "update",
    "entry_conditions": [
      { "field": "Email", "operator": "is_changed", "value": true }
    ]
  },
  "steps": [
    {
      "type": "get_records",
      "name": "Get_Account",
      "object": "Account",
      "filters": [{ "field": "Id", "operator": "equals", "reference": "$Record.AccountId" }],
      "handle_faults": true
    },
    {
      "type": "decision",
      "name": "Check_Domains",
      "rules": [
        {
          "name": "Domains_Match",
          "conditions": [
            { "left": "emailDomain", "operator": "equals", "reference": "websiteDomain" }
          ],
          "steps": []
        }
      ],
      "default_steps": [
        {
          "type": "send_email",
          "name": "Alert_Owner",
          "to": [{ "ref": "Get_Owner.Email" }],
          "subject": "Contact Email Domain Mismatch",
          "body": "Contact {!$Record.FirstName} {!$Record.LastName} email changed to {!$Record.Email}.\nEmail domain: {!emailDomain}\nAccount: {!Get_Account.Name}\nWebsite domain: {!websiteDomain}",
          "handle_faults": true
        }
      ],
      "default_label": "Domains Don't Match"
    }
  ],
  "resources": [
    {
      "type": "formula",
      "name": "emailDomain",
      "data_type": "string",
      "expression": "LOWER(RIGHT({!$Record.Email}, LEN({!$Record.Email}) - FIND('@', {!$Record.Email})))"
    },
    {
      "type": "formula",
      "name": "websiteDomain",
      "data_type": "string",
      "expression": "IF(NOT(ISBLANK({!Get_Account.Website})), LOWER(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE({!Get_Account.Website}, 'https://', ''), 'http://', ''), 'www.', '')), '')"
    }
  ]
}
```

### Example: Before-Save field update

```json
{
  "type": "record_triggered",
  "trigger": {
    "object": "Opportunity",
    "when": "before_save",
    "record_events": "update",
    "entry_conditions": [
      { "field": "StageName", "operator": "equals", "value": "Closed Won" },
      { "field": "StageName", "operator": "is_changed", "value": true }
    ]
  },
  "steps": [
    {
      "type": "update_records",
      "name": "Set_Close_Date",
      "target": "$Record",
      "field_values": { "CloseDate": { "ref": "$Flow.CurrentDate" } }
    }
  ]
}
```

### Example: Before-Save validation with custom error

```json
{
  "type": "record_triggered",
  "trigger": {
    "object": "Account",
    "when": "before_save",
    "record_events": "update",
    "entry_conditions": [
      { "field": "Status__c", "operator": "is_changed", "value": true },
      { "field": "Status__c", "operator": "equals", "value": "Churned" }
    ]
  },
  "steps": [
    {
      "type": "get_records",
      "name": "Get_Open_Opps",
      "object": "Opportunity",
      "filters": [
        { "field": "AccountId", "operator": "equals", "reference": "$Record.Id" },
        { "field": "IsClosed", "operator": "equals", "value": false }
      ]
    },
    {
      "type": "decision",
      "name": "Has_Open_Opps",
      "rules": [
        {
          "name": "Open_Opps_Found",
          "conditions": [
            { "left": "Get_Open_Opps", "operator": "is_null", "value": false }
          ],
          "steps": [
            {
              "type": "custom_error",
              "name": "Block_Churn",
              "message": "Cannot change Status to Churned — there are open Opportunities on this Account.",
              "field": "Status__c"
            }
          ]
        }
      ]
    }
  ]
}
```

### What you DON'T need to provide

The tool handles ALL of the following automatically:
- `locationX` / `locationY` coordinates
- `connector` / `defaultConnector` / `faultConnector` wiring
- `processMetadataValues` (BuilderType, CanvasMode, OriginBuilderType)
- `apiVersion`, `environments`, `interviewLabel`, `status`, `fullName`
- emailSimple ceremony (collection variable, assignment, text template, correct parameter names)
- Fault handler email actions (just set `handle_faults: true`)

### Before Save vs After Save

This is a Salesforce constraint — pick the right one:

- **Before Save**: Can update `$Record` fields directly. CANNOT send emails, post to Chatter, make callouts, create/update/delete other records via DML. Use for field defaults, validations, and same-record updates.
- **After Save**: Can do everything — email, Chatter, DML on other records, callouts. CANNOT use `$Record` directly for updates (must use filter-based update). Use for notifications, cross-object operations, and anything that needs external calls.

---

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

## CRITICAL: Flow Variable and Element Naming Rules

All element names, variable names, formula names, and decision names in Flow metadata MUST follow these rules:
- Only alphanumeric characters and underscores
- Must start with a letter
- No spaces, no special characters (no `$`, no `-`, no `.`)
- No double underscores (`__`)
- Cannot end with an underscore

**NEVER declare system variables as flow variables.** `$Record`, `$Record__Prior`, `$Flow.CurrentDate`, `$Flow.CurrentDateTime`, etc. are automatically available — do NOT add them to the `variables` array. Adding `$Record__Prior` as a variable will fail deployment.

---

## CRITICAL: locationX and locationY are REQUIRED on every element

Every flow element — `decisions`, `recordLookups`, `recordCreates`, `recordUpdates`, `assignments`, `actionCalls`, `loops`, `screens`, `customErrors`, `subflows` — **MUST** include `locationX` and `locationY` as integer fields. Omitting them causes: `Required field is missing: locationX`.

The only elements that do NOT take locationX/locationY are: `formulas`, `variables`, `textTemplates`, `choices`, `constants`, and `stages`.

Use these values for Auto-Layout flows (the exact numbers don't matter for Auto-Layout, but they must be present):
- First element after start: `"locationX": 176, "locationY": 134`
- Increment `locationY` by ~108 for each subsequent element on the main path
- Branching elements (fault paths, decision outcomes): offset `locationX` by ~264

Example:
```json
{ "name": "Get_Account", "locationX": 176, "locationY": 134, ... },
{ "name": "Check_Domain",  "locationX": 176, "locationY": 242, ... },
{ "name": "Send_Email",    "locationX": 176, "locationY": 350, ... },
{ "name": "Error_Handler", "locationX": 440, "locationY": 242, ... }
```

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

## CRITICAL: Before Save vs After Save — pick the right trigger FIRST

This is the #1 source of wasted retries on flow builds. Choose the trigger type during planning, not after Salesforce rejects the save.

**Before Save (`RecordBeforeSave`) — the ONLY things allowed:**
- Update fields on `$Record` (the triggering record)
- Decision elements
- Assignment elements
- Formula resources
- Get Records (read-only lookups)
- Loops over in-memory collections

**Before Save cannot contain ANY of these — Salesforce will reject the save at build time:**
- ❌ Action Calls of ANY kind (email, Slack, subflow, Apex invocable, MuleSoft, external service, emailAlert, emailSimple)
- ❌ Screen elements
- ❌ Pause / Wait elements
- ❌ Create Records / Update Records on OTHER objects (only `$Record` itself can be updated)
- ❌ Delete Records
- ❌ Roll-back on error (fault paths that transition to action calls)
- ❌ `scheduledPaths`

The exact Salesforce errors you'll see if you get it wrong:
- `A flow can't include Action elements when TriggerType is set to Record—Run Before Save`
- `You can't use the Send Email action type in flows with the Record—Run Before Save trigger type`
- `ACTIONCALL_NOT_SUPPORTED_FOR_TRIGGERTYPE`

**Decision rule — apply during planning, before writing metadata:**

> If the flow needs to do ANYTHING other than set fields on the triggering record, it MUST be After Save.

Specific scenarios and the required trigger type:

| Requirement | Trigger |
|---|---|
| Set a field value on the same record being saved | **Before Save** |
| Send an email (alert, emailSimple, template) | **After Save** |
| Create/update a related Task, Case, Opportunity, or any record other than `$Record` | **After Save** |
| Post to Slack, call an external API, invoke a MuleSoft process | **After Save** |
| Call a subflow that does any of the above | **After Save** |
| Run Apex via invocable action | **After Save** |
| Validate and block the save with a user-visible error | **Before Save** (use `customErrors`) |
| Look up data (Get Records) and store in a variable for downstream logic | Either — choose based on what the downstream logic does |
| Mix: update the same record AND send an email | **After Save** (you can still update `$Record` from After Save; it just uses a DML statement) |

**When in doubt: pick After Save.** The only penalty for After Save over Before Save is minor (uses a DML statement for same-record updates). The penalty for wrongly picking Before Save is a hard Salesforce build-time rejection and a wasted turn.

---

## CRITICAL: NEVER hardcode record IDs in flow metadata

This rule has ZERO exceptions. When a flow needs to reference a queue, user, record type, profile, custom metadata record, or any other record by ID, you MUST look up the ID at runtime via a `recordLookups` (Get Records) element. Never embed a literal Salesforce ID string in the metadata, even if you just created the record and know the ID from a previous tool call.

**Why:**
- IDs are per-org — they are different in every sandbox, in production, in every scratch org
- A flow built with hardcoded IDs is impossible to deploy between environments
- IDs change when records are deleted and recreated (queue renamed, user deactivated and restored, etc.)
- Hardcoded IDs make flows invisible to metadata dependency analysis, impact assessments, and change sets
- When a hardcoded ID breaks, the flow fails silently in production with no obvious fix

**Wrong (NEVER DO THIS):**
```json
{
  "name": "Assign_to_Enterprise_Inbound",
  "object": "Lead",
  "filters": [{ "field": "Id", "operator": "EqualTo", "value": { "elementReference": "$Record.Id" } }],
  "inputAssignments": [
    { "field": "OwnerId", "value": { "stringValue": "00GcX000003o2GEUAY" } }
  ]
}
```

**Right — look up the queue first, reference the result:**

1. Add a `recordLookups` element to get the queue by its stable identifier (queues are stored as `Group` records with `Type = 'Queue'`):

```json
{
  "name": "Get_Enterprise_Inbound_Queue",
  "label": "Get Enterprise Inbound Queue",
  "object": "Group",
  "filterLogic": "and",
  "filters": [
    { "field": "DeveloperName", "operator": "EqualTo", "value": { "stringValue": "Enterprise_Inbound" } },
    { "field": "Type", "operator": "EqualTo", "value": { "stringValue": "Queue" } }
  ],
  "getFirstRecordOnly": true,
  "storeOutputAutomatically": true,
  "connector": { "targetReference": "Assign_to_Enterprise_Inbound" }
}
```

2. Reference the looked-up Id in the assignment:

```json
{
  "name": "Assign_to_Enterprise_Inbound",
  "object": "Lead",
  "filters": [{ "field": "Id", "operator": "EqualTo", "value": { "elementReference": "$Record.Id" } }],
  "inputAssignments": [
    { "field": "OwnerId", "value": { "elementReference": "Get_Enterprise_Inbound_Queue.Id" } }
  ]
}
```

### Lookup patterns for common record types

| What you need | Query | Stable identifier |
|---|---|---|
| Queue | `Group WHERE Type = 'Queue' AND DeveloperName = '<name>'` | `DeveloperName` |
| User by username | `User WHERE Username = '<email>'` | `Username` |
| User by name (less stable) | `User WHERE Name = '<full name>' AND IsActive = true` | `Name` |
| Record Type | `RecordType WHERE DeveloperName = '<name>' AND SobjectType = '<object>'` | `DeveloperName` + `SobjectType` |
| Profile | `Profile WHERE Name = '<name>'` | `Name` |
| Custom Metadata record | `<Type>__mdt WHERE DeveloperName = '<name>'` | `DeveloperName` |
| Custom Setting | `<Setting>__c WHERE Name = '<name>'` | `Name` |

### Efficiency tip

If the flow needs to route to multiple queues, add ONE `recordLookups` per queue up front (before the decision). Reference each by its Get Records output downstream. Don't bury lookups inside decision branches — it makes the flow harder to follow and can cause SOQL limit issues if the branches are inside a loop.

### When a model just created the records

If you used `execute_anonymous_apex` to create queues earlier in the same conversation and got the IDs back in the output, **DO NOT embed those IDs in the flow**. The flow must still query for them via Get Records — because the flow runs at runtime in the user's production org eventually, not in the conversation context.

---

## CRITICAL: ALWAYS add fault paths to every DML and callout element

Every `recordCreates`, `recordUpdates`, `recordDeletes`, `actionCalls` (email, Slack, Apex invocable, subflow), and `recordLookups` MUST have a `faultConnector` pointing to an error-handling element. No exceptions. This rule applies to EVERY flow you build or update.

**Why:**
- Without a fault path, any DML or callout failure throws an unhandled exception — the flow silently errors out mid-execution and leaves data in an inconsistent state
- The user will see cryptic flow error emails from Salesforce with no context about what happened
- Downstream logic never runs, but the record has been partially modified — hard to debug and harder to undo
- In production, unhandled flow errors become noisy enough that flows get deactivated in frustration

**Minimum pattern — email the user who was running the flow when something breaks:**

```json
{
  "actionCalls": [
    {
      "name": "Handle_Flow_Error",
      "label": "Handle Flow Error",
      "actionName": "emailSimple",
      "actionType": "emailSimple",
      "flowTransactionModel": "CurrentTransaction",
      "nameSegment": "emailSimple",
      "versionString": "1.0.1",
      "inputParameters": [
        { "name": "emailAddressesArray", "value": { "elementReference": "ErrorRecipients" } },
        { "name": "emailSubject", "value": { "stringValue": "Flow Error: <flow name>" } },
        { "name": "emailBody", "value": { "elementReference": "Error_Email_Template" } },
        { "name": "sendRichBody", "value": { "booleanValue": false } }
      ]
    }
  ],
  "textTemplates": [
    {
      "name": "Error_Email_Template",
      "isViewedAsPlainText": true,
      "text": "A flow failure occurred.\n\nRecord ID: {!$Record.Id}\nRecord Name: {!$Record.Name}\nError: {!$Flow.FaultMessage}\n\nPlease investigate."
    }
  ],
  "variables": [
    {
      "name": "ErrorRecipients",
      "dataType": "String",
      "isCollection": true,
      "isInput": false,
      "isOutput": false
    }
  ]
}
```

Then on EVERY DML / callout element, add the fault connector:

```json
{
  "name": "Assign_to_Enterprise_Inbound",
  "object": "Lead",
  "connector": { "targetReference": "Next_Step" },
  "faultConnector": { "targetReference": "Handle_Flow_Error" },
  "filters": [...],
  "inputAssignments": [...]
}
```

### Where to send fault emails

- **If the account has custom instructions specifying a recipient** (e.g. admin email for flow errors), use that address
- Otherwise, default to the record owner's email via a User lookup (Get Records on User filtered by Id = `$Record.OwnerId`, then add `{!Get_Owner.Email}` to the ErrorRecipients collection)
- **NEVER hardcode a specific email address unless the account's custom instructions explicitly provide one** — and even then, the address itself should be treated as configuration, not as "the model's choice"

### Populating the ErrorRecipients collection

Use an `Assignment` element with operator `Add` to push the email onto the collection variable before the error path runs. See the emailSimple canonical pattern in this document.

### When fault paths CAN be omitted

Almost never. The only legitimate exception is a Before Save flow that only updates `$Record` — because Before Save updates happen in-memory and Salesforce rolls back the whole save on exception automatically. For everything else (After Save DML, any action call, any record lookup that might fail), always include a fault path.

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
  }]
}
```

### CRITICAL — there is NO "End" element in flows

**Do NOT invent `End_Flow`, `End_No_Account`, `End_Domain_Match`, or any other terminator element.** Flows have no explicit end node — a path ends by simply **omitting the connector** on the last element, or by omitting a `defaultConnector` / the rule-level `connector` where you want the path to stop.

Wrong (causes `Invalid element reference End_Flow not found for target`):
```json
{
  "name": "Check_Stage",
  "rules": [{ "connector": { "targetReference": "Update_Record" } }],
  "defaultConnector": { "targetReference": "End_Flow" }  // ← End_Flow doesn't exist anywhere
}
```

Right — just omit `defaultConnector` entirely when that path should terminate:
```json
{
  "name": "Check_Stage",
  "rules": [{ "connector": { "targetReference": "Update_Record" } }]
  // no defaultConnector → default path ends the flow
}
```

Same applies to action calls and record operations: if the action is the last step, simply don't add a `connector` field. The flow terminates naturally. This is the #1 cause of wasted retries on `create_flow`.

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

For before-save flows, use `inputReference: "$Record"` to update fields on the triggering record:
```json
{
  "name": "Set_Close_Date",
  "label": "Set Close Date",
  "locationX": 0,
  "locationY": 0,
  "inputReference": "$Record",
  "inputAssignments": [{
    "field": "CloseDate",
    "value": { "elementReference": "$Flow.CurrentDate" }
  }]
}
```

### Record update elements (after-save — ANY record, including the triggering one)

**CRITICAL:** In After Save flows, you MUST use the filter-based pattern for every record update — even when updating the triggering record itself. The `inputReference: "$Record"` shortcut is a **Before Save only** pattern. Using it in an After Save flow causes Salesforce to return the useless error:
> *An unexpected error occurred. Please include this ErrorId if you contact support: ...*

Use the `object` + `filters` + `inputAssignments` pattern in After Save flows:

**Updating the triggering record (After Save):**
```json
{
  "name": "Assign_Owner",
  "label": "Assign Owner",
  "object": "Lead",
  "filterLogic": "and",
  "filters": [{
    "field": "Id",
    "operator": "EqualTo",
    "value": { "elementReference": "$Record.Id" }
  }],
  "inputAssignments": [{
    "field": "OwnerId",
    "value": { "stringValue": "00GXXXXXXXXXXXX" }
  }]
}
```

**Updating a related record (After Save):**
```json
{
  "name": "Update_Parent_Account",
  "label": "Update Parent Account",
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

**Why this quirk exists:** Before Save flows modify the triggering record in memory before it's saved — there's nothing to query. After Save flows run after the record is already in the database, so every update (including the triggering record itself) must go through a filtered DML operation. The `inputReference: "$Record"` shortcut doesn't apply because there's no in-memory record to write to directly.

**Rule of thumb:** if `triggerType: "RecordAfterSave"`, you should have ZERO occurrences of `inputReference` in your recordUpdates. Every element needs `object` + `filters` + `inputAssignments`.

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

**CRITICAL — formulas do NOT support a `label` field.** The only valid top-level fields on a formula are `name`, `dataType`, `expression`, `scale` (optional), and `description` (optional). Adding `label`, `locationX`, or `locationY` causes: `Element {http://soap.sforce.com/2006/04/metadata}<field> invalid at this location in type FlowFormula`. Use only the `name` for identification.

### Flow dataType enum values — MUST use these exact strings

Flow variables, formulas, and constants use the Metadata API's `FlowDataType` enum. The valid values are:

- `"String"` — for any text. **NEVER use `"Text"` — that is a field type, NOT a Flow dataType.** Using `"Text"` causes `'Text' is not a valid value for the enum 'FlowDataType'`.
- `"Number"` — for numeric values (integer or decimal)
- `"Currency"` — for currency amounts
- `"Boolean"` — for true/false
- `"Date"` — for dates (no time component)
- `"DateTime"` — for date + time
- `"Picklist"` — for picklist values
- `"Multipicklist"` — for multi-select picklists
- `"SObject"` — for record variables (requires `objectType` field)
- `"Apex"` — for Apex-defined types (requires `apexClass` field)

**Common mistake:** using `"Text"` for a String variable. Salesforce field types use "Text" (as in a Text field on an object), but Flow variables use "String" for the same concept. This is a naming inconsistency in the Salesforce platform — remember: **field type = "Text", flow dataType = "String"**.

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
- `$Record__Prior` — the record's values BEFORE the update (only in update-triggered flows). **NEVER declare `$Record` or `$Record__Prior` as variables in the flow metadata** — they are system-provided automatically. If you add them to the `variables` array, the deploy will fail with "Variable Name: The Flow Variable API Name can only contain underscores and alphanumeric characters." Variables starting with `$` are reserved system variables.
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

## Sending Email from a Flow — `emailSimple` action (READ BEFORE USING)

Sending an email via the `emailSimple` core action has strict requirements. Get them wrong and you'll hit one of these infinite-loop errors:
- `Provide at least one email recipient.` → wrong parameter name
- `The input parameter "Recipient Addresses" can accept multiple values, so the assigned value must be a flow variable with the isCollection property set to true.` → you passed a `stringValue` instead of a collection variable reference

### The four things you MUST get right

1. **Parameter name is `emailAddressesArray`** (not `emailAddresses`, not `recipientAddresses`, not `emailAddressesString`).
2. **The value MUST be an `elementReference` to a String variable with `isCollection: true`** — NOT a `stringValue`. Even if you only want to send to one address, it still must be a collection.
3. **Populate the collection** via an Assignment element that uses operator `Add` to push the email string onto the variable BEFORE the `Send_Email` action runs.
4. **Use `emailBody` with a `textTemplates` reference**, not a raw string. The template name goes in `elementReference`.

### Full working pattern (JSON for `create_flow`)

```json
{
  "variables": [
    {
      "name": "EmailRecipients",
      "dataType": "String",
      "isCollection": true,
      "isInput": false,
      "isOutput": false
    }
  ],
  "assignments": [
    {
      "name": "Add_Recipient",
      "label": "Add Recipient",
      "locationX": 176,
      "locationY": 300,
      "assignmentItems": [
        {
          "assignToReference": "EmailRecipients",
          "operator": "Add",
          "value": { "stringValue": "owner@example.com" }
        }
      ],
      "connector": { "targetReference": "Send_Email" }
    }
  ],
  "textTemplates": [
    {
      "name": "Email_Body_Template",
      "isViewedAsPlainText": true,
      "text": "Contact {!$Record.Name} had their email domain changed to {!$Record.Email}."
    }
  ],
  "actionCalls": [
    {
      "name": "Send_Email",
      "label": "Send Email",
      "locationX": 176,
      "locationY": 500,
      "actionName": "emailSimple",
      "actionType": "emailSimple",
      "flowTransactionModel": "CurrentTransaction",
      "nameSegment": "emailSimple",
      "versionString": "1.0.1",
      "inputParameters": [
        { "name": "emailAddressesArray", "value": { "elementReference": "EmailRecipients" } },
        { "name": "emailSubject", "value": { "stringValue": "Contact Email Changed" } },
        { "name": "emailBody", "value": { "elementReference": "Email_Body_Template" } },
        { "name": "sendRichBody", "value": { "booleanValue": false } }
      ]
    }
  ]
}
```

### Common mistakes the model makes (DO NOT DO THESE)

| Wrong | Why it fails | Right |
|---|---|---|
| Omitting `locationX`/`locationY` on an element | `Required field is missing: locationX` | Add `"locationX": 176, "locationY": <value>` to every element (decisions, recordLookups, assignments, actionCalls, etc.) |
| `"name": "emailAddresses"` | Not a valid param name | `"name": "emailAddressesArray"` |
| `"name": "recipientAddresses"` | Not a valid param name | `"name": "emailAddressesArray"` |
| `{ "stringValue": "a@b.com" }` for recipients | Must be a collection | `{ "elementReference": "EmailRecipients" }` pointing to a `isCollection: true` String var |
| Omit the Assignment that populates the collection | Collection is empty → "Provide at least one email recipient" | Add an Assignment with operator `Add` to push the address onto the collection first |
| `emailBody: { "stringValue": "..." }` | Body must reference a text template | `emailBody: { "elementReference": "Email_Body_Template" }` |

### Dynamic recipients (e.g. record owner's email)

If you want to send to the record owner, add a Get Records element for the User by Id = `$Record.OwnerId`, then assign `{!Get_Owner.Email}` into the collection via the Assignment:

```json
{
  "assignmentItems": [
    {
      "assignToReference": "EmailRecipients",
      "operator": "Add",
      "value": { "elementReference": "Get_Owner.Email" }
    }
  ]
}
```

### When to use `emailSimple` vs `create_email_alert`

- **`emailSimple` action in a flow** — ad-hoc email from a flow, body defined inline via text template. Use this when the recipient list is dynamic or computed at runtime.
- **`create_email_alert` (WorkflowAlert)** — reusable alert tied to an EmailTemplate. Use when you want a named alert that can be invoked from multiple flows or workflow rules. Requires the template to already exist.

If the model is stuck in a retry loop on `emailSimple`, DO NOT pivot to `create_email_alert` as a workaround — fix the `emailSimple` payload using the pattern above. Pivoting buries the root cause and usually fails too (EmailTemplate body parsing is separately strict).

---

## Posting to Chatter from a Flow — `chatterPost` action

The `chatterPost` core action posts a Chatter feed item to a record. **It only works if Chatter is enabled in the org.** If Chatter is disabled, the deploy will fail with:
> *"We can't find an action with the name and action type that you specified."*

### Working pattern

```json
{
  "name": "Post_Chatter_Update",
  "label": "Post Chatter Update",
  "actionName": "chatterPost",
  "actionType": "chatterPost",
  "flowTransactionModel": "CurrentTransaction",
  "nameSegment": "chatterPost",
  "versionString": "1",
  "inputParameters": [
    { "name": "text", "value": { "stringValue": "Deal closed! Handoff record created." } },
    { "name": "subjectNameOrId", "value": { "elementReference": "$Record.Id" } }
  ]
}
```

**Input parameters:**
- `text` (required) — the post body. Can use flow variable references like `{!MyVariable}` inside text templates.
- `subjectNameOrId` (required) — the record ID to post on (usually `$Record.Id` or another record's Id from a lookup).

**Parameters that DO NOT exist** (common model mistakes):
- ❌ `mentionedUsers` — not a valid input parameter for `chatterPost`
- ❌ `visibility` — not available
- ❌ `communityId` — not available in the standard chatterPost action

To @mention users in a Chatter post, include the mention syntax in the `text` body: `@[005XXXXXXXXXXXX]` (user Id). But note this requires hardcoding the user Id, which violates the "never hardcode IDs" rule — consider looking up the user and building the mention string dynamically.

### CRITICAL: Correct `chatterPost` action structure

The `chatterPost` action has a very specific structure that differs from `emailSimple`. Getting any field wrong causes "can't find an action with the name and action type" errors. Use this EXACT pattern:

**Post to a record's Chatter feed:**

```json
{
  "name": "Post_Chatter_Record",
  "label": "Post to Chatter Record",
  "locationX": 176,
  "locationY": 539,
  "actionName": "chatterPost",
  "actionType": "chatterPost",
  "connector": { "targetReference": "Next_Element" },
  "flowTransactionModel": "CurrentTransaction",
  "inputParameters": [
    { "name": "text", "value": { "elementReference": "MyTextTemplate" } },
    { "name": "subjectNameOrId", "value": { "elementReference": "$Record.Id" } }
  ],
  "nameSegment": "chatterPost",
  "offset": 0,
  "storeOutputAutomatically": true
}
```

**Post to a user's Chatter feed (add `type: "user"` input parameter):**

```json
{
  "name": "Post_Chatter_User",
  "label": "Post to Chatter User",
  "locationX": 176,
  "locationY": 647,
  "actionName": "chatterPost",
  "actionType": "chatterPost",
  "connector": { "targetReference": "Next_Element" },
  "flowTransactionModel": "CurrentTransaction",
  "inputParameters": [
    { "name": "text", "value": { "elementReference": "MyTextTemplate" } },
    { "name": "subjectNameOrId", "value": { "elementReference": "$Record.OwnerId" } },
    { "name": "type", "value": { "stringValue": "user" } }
  ],
  "nameSegment": "chatterPost",
  "offset": 0,
  "storeOutputAutomatically": true
}
```

**CRITICAL rules for `chatterPost`:**
- MUST include `"offset": 0` and `"storeOutputAutomatically": true` — omitting these causes deploy failures
- Do NOT include `"versionString"` on chatterPost actions — unlike `emailSimple` which uses `"versionString": "1.0.1"`, chatterPost does NOT have a versionString. Including one causes "can't find action" errors
- `subjectNameOrId` is the record ID or user ID to post on
- To post on a user's feed instead of a record, add the `type` input parameter with `"stringValue": "user"`

### When `chatterPost` fails

If the deploy fails with "can't find an action with the name and action type" after using the exact pattern above, Chatter is likely disabled in this org. Do NOT retry — instead:

1. Tell the user: *"The Chatter post action isn't available in this org — Chatter may not be enabled."*
2. Offer alternatives:
   - **Create a Task** instead (`recordCreates` with object `Task`) — visible in the record's activity timeline
   - **Send an email notification** — use `emailSimple` (already documented above)

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

### CRITICAL — state "create new" vs "update existing" unambiguously in the plan

Users get confused when plans use ambiguous phrases like *"this new flow will add to that automation"*, *"I'll extend the existing flow"*, or *"this will be part of the Lead automation"*. These readings are ambiguous — they can mean either "create a separate flow" or "modify the existing flow", and a user reading the plan may assume the opposite of what you intend.

**Every flow-related plan MUST include one of these two explicit statements, verbatim or close to it:**

- ✅ **"I will CREATE A NEW flow called `<API_Name>`"** — followed by why you're creating a new one instead of updating an existing one (e.g. *"the existing `Lead_After_Insert_Update` flow handles different logic — keeping this separate for clarity"*, or *"the existing flow is too large to edit in-chat"*, or *"no existing flow on this object matches this use case"*)
- ✅ **"I will UPDATE the existing flow `<API_Name>`"** — followed by what elements you're adding/modifying

Never use these ambiguous phrasings:
- ❌ "This new flow will add to that automation" (add to WHAT — the collection, or the flow?)
- ❌ "I'll extend the Lead automation with this logic"
- ❌ "I'll build on top of the existing flow"
- ❌ "This flow will work alongside the existing one" (clearer, but still worth stating "create new" explicitly)
- ❌ "Let me incorporate this into the existing flow" (unless you actually will — then also say "UPDATE the existing flow X")

**When an existing flow is present on the same trigger object + trigger type:** Check the existing flow's purpose FIRST. If your new requirement genuinely belongs in the existing flow (related logic, same trigger, reasonable combined size), offer to UPDATE it. If it's genuinely separate (different concerns, or the existing flow is too large to edit safely — see `get_flow_definition` size warning), CREATE NEW and explain why. Either way, say which one explicitly in the plan.

**When you commit in the plan to updating an existing flow, you MUST use `update_flow` in the build turn.** Never say "I'll update the existing flow" and then call `create_flow` with a new API name. That's a contract violation and will confuse the user.

## Flow best practices

1. **Before Save vs After Save** — see the "CRITICAL: Before Save vs After Save" section near the top of this doc. Before Save is a hard Salesforce constraint, not a preference: Action Calls, email sends, cross-record DML, and Custom Errors are forbidden in Before Save flows. When in doubt, pick After Save.
2. **Always add entry conditions** via `filters` on the `start` element to prevent unnecessary runs
3. **Use `IsChanged` operator** in entry conditions to only fire when specific fields change:
   ```json
   { "field": "StageName", "operator": "IsChanged", "value": { "booleanValue": true } }
   ```
4. **Set `locationX` and `locationY` to 0** for all elements — the Flow Builder auto-layout will position them
5. **Use descriptive element names** with underscores (e.g., `Check_Stage_Is_Closed_Won`)
6. **Always include `processMetadataValues`** for BuilderType, CanvasMode, and OriginBuilderType
7. **Use `apiVersion: "62.0"`** for compatibility

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
| Polymorphic reference syntax like `$Record.Owner:User.Email` | Not valid in flow elements — causes `Invalid element reference` error | Add a `recordLookups` on User filtered by `Id = $Record.OwnerId`, then reference `Get_Owner.Email` |
| Cross-object fields through Lookups (`$Record.Account.Website` inside a formula or condition) | Flows cannot traverse lookups from `$Record` in most contexts | Add a `recordLookups` to Get the related Account, then reference `Get_Account.Website` |
| Inventing "End" terminator elements like `End_Flow`, `End_No_Account` | No such element type exists; causes `Invalid element reference X not found for target` | Omit the `connector` / `defaultConnector` to end a path |
| `TEXT()` called on a value that is already Text | `Incorrect parameter type for function 'TEXT()'. Expected Number, Date, Date/Time, Picklist, received Text` | Don't wrap strings in `TEXT()` — it only converts Number/Date/DateTime/Picklist → Text. Reference the value directly. |
| `inputReference: "$Record"` on recordUpdates in an After Save flow | Silent failure: Salesforce returns `An unexpected error occurred. Please include this ErrorId if you contact support: ...` | `inputReference: "$Record"` is Before Save only. In After Save, use `object: "Lead" + filters: [{field: "Id", operator: "EqualTo", value: {elementReference: "$Record.Id"}}] + inputAssignments` even when updating the triggering record itself. See the "Record update elements (after-save)" section. |
| `apiVersion` sent as a number like `62` instead of string `"62.0"` | Tooling API silently rejects with generic `unexpected error` | Always use `"apiVersion": "62.0"` — string, with `.0` suffix. |
| `environments` sent as array `["Default"]` instead of string `"Default"` | Tooling API silently rejects | Always use `"environments": "Default"` — plain string. |
| `filterLogic: "or"` with only 0 or 1 filter | Nonsense — OR needs at least 2 operands | Use `"filterLogic": "and"` for single-filter lookups. The value doesn't matter when there's one filter, but `and` is the safe default. |
| Element ordering in XML | Root-level elements must be in alphabetical order | Sort: `actionCalls`, `assignments`, `decisions`, `formulas`, `recordCreates`, `recordLookups`, `recordUpdates`, `start`, `variables` |
| Missing `processMetadataValues` | Flow Builder won't render properly | Always include BuilderType, CanvasMode, OriginBuilderType |

### Accessing related record fields — ALWAYS use a Get Records element

Flow elements cannot traverse lookup relationships from `$Record` the way formula fields or SOQL can. You cannot write `$Record.Account.Website`, `$Record.Owner.Email`, `$Record.Owner:User.Email`, or any polymorphic reference inside a decision condition, formula expression, assignment, or action input parameter. These all fail with `Invalid element reference ... not found for target`.

The correct pattern is always **Get Records → reference the output**:

```json
{
  "recordLookups": [
    {
      "name": "Get_Contact_Owner",
      "label": "Get Contact Owner",
      "object": "User",
      "filterLogic": "and",
      "filters": [
        {
          "field": "Id",
          "operator": "EqualTo",
          "value": { "elementReference": "$Record.OwnerId" }
        }
      ],
      "getFirstRecordOnly": true,
      "storeOutputAutomatically": true,
      "connector": { "targetReference": "Next_Element" }
    }
  ]
}
```

Then reference the owner's email anywhere in the flow as `Get_Contact_Owner.Email`. Same pattern for Account (Get Records on Account filtered by `Id = $Record.AccountId`, then use `Get_Account.Website`).

**Common IDs to look up:** `$Record.OwnerId` → User, `$Record.AccountId` → Account, `$Record.ContactId` → Contact, `$Record.CreatedById` / `$Record.LastModifiedById` → User.

## Subflow patterns

### CRITICAL — NEVER invent subflow references

Only reference a subflow via the `subflows` element if you have **verified** the subflow exists in the org. Invented subflow references cause the deploy to fail with *"The flow X doesn't exist"* and waste a turn.

**Default behavior: inline the logic.** When you need reusable behavior like "send an email with error details" or "log a failure", write the action calls and assignments DIRECTLY in the main flow — do NOT create or reference a subflow. Subflows add complexity without benefit for single-use logic.

**Use subflows ONLY when one of these is true:**
1. The user has explicitly asked you to create or reuse a subflow
2. You have verified via `list_flows` or `query_salesforce` on `FlowDefinitionView` that the subflow already exists AND confirmed its purpose matches your need
3. You are building the subflow FIRST (via create_flow with `processType: "AutoLaunchedFlow"` and no trigger), activating it, and THEN referencing it from the parent flow in a follow-up step

**Never do this:**
- Add a `subflows` element with a flowName you made up based on "what seems like a reasonable subflow name"
- Reference a subflow you've seen in a documentation example (the examples below are illustrative patterns, not real flows in your org)
- Speculate that a "Sub_SendEmailAlert" or "Sub_LogError" exists because it would be convenient

The pre-deploy validator will reject any flow that references a non-existent subflow.

### Calling an existing, verified subflow

If you've confirmed the subflow exists, call it like this:

```json
{
  "name": "Log_Error",
  "label": "Log Error",
  "flowName": "Verified_Existing_Subflow_Name",
  "connector": { "targetReference": "Next_Element" },
  "inputAssignments": [
    { "name": "ErrorMessage", "value": { "elementReference": "$Flow.FaultMessage" } },
    { "name": "RecordId", "value": { "elementReference": "$Record.Id" } }
  ]
}
```

Note: in the Flow metadata XML, subflow elements live in the top-level `subflows` array (not `actionCalls`). The element's `flowName` field references the API name of another flow. Do NOT put subflow calls in `actionCalls`.

### Example subflow purposes (illustrative only — do NOT reference these names)

These are ideas for what kinds of reusable logic make good subflows **if the user explicitly asks you to build them**. The names in this list are just examples — they don't exist in any org by default and must not be referenced from your flow unless you have built them yourself or the user has confirmed they exist:

- Error logging to a custom object
- Sending notification emails with a consistent template
- Validating required fields across multiple objects
- Looking up the right approver for an approval chain

## Screen Flows — interactive wizard flows (processType: "Flow")

Screen Flows are interactive flows launched via buttons, links, or Lightning pages. They present one or more screens where the user fills out information, then the flow processes the data (creates records, sends emails, updates fields, etc.). They are fundamentally different from record-triggered flows.

### Key differences from record-triggered flows

| | Record-Triggered | Screen Flow |
|---|---|---|
| `processType` | `AutoLaunchedFlow` | `Flow` |
| `start` element | Has `triggerType`, `object`, `recordTriggerType`, `filters` | Has only `connector` pointing to the first element — **no trigger config** |
| `$Record` | Available (the triggering record) | **NOT available** — use a `recordId` input variable + Get Records |
| Screens | Not allowed | Required — at least one `screens` element |
| User interaction | None — runs in background | User sees screens, fills inputs, clicks Next/Finish |
| Launch method | Automatic on record save | Button, Quick Action, Lightning page, URL |

### Start element for Screen Flows

Screen Flows have a minimal `start` element — just a connector:

```json
{
  "start": {
    "locationX": 50,
    "locationY": 0,
    "connector": { "targetReference": "First_Element" }
  }
}
```

**No `object`, no `triggerType`, no `recordTriggerType`, no `filters`.** If you include any of these, Salesforce will reject the flow.

### The `recordId` input variable pattern

Most Screen Flows are launched from a record page and need to know which record to work with. Use an input variable named `recordId`:

```json
{
  "variables": [
    {
      "name": "recordId",
      "dataType": "String",
      "isCollection": false,
      "isInput": true,
      "isOutput": false
    }
  ]
}
```

Salesforce automatically populates `recordId` when the flow is launched from a record page button/action. Then use it in a Get Records lookup to fetch the record:

```json
{
  "recordLookups": [
    {
      "name": "Get_Account",
      "label": "Get Account",
      "object": "Account",
      "filterLogic": "and",
      "filters": [{ "field": "Id", "operator": "EqualTo", "value": { "elementReference": "recordId" } }],
      "getFirstRecordOnly": true,
      "storeOutputAutomatically": true,
      "connector": { "targetReference": "Screen_1" }
    }
  ]
}
```

### Screen element structure

Each screen is a `screens` array entry with fields, navigation, and a connector:

```json
{
  "screens": [
    {
      "name": "Confirm_Details",
      "label": "Confirm Details",
      "locationX": 176,
      "locationY": 200,
      "allowBack": false,
      "allowFinish": true,
      "allowPause": false,
      "showFooter": true,
      "showHeader": true,
      "connector": { "targetReference": "Next_Element" },
      "fields": [
        {
          "name": "WelcomeText",
          "fieldText": "<p><b>Account:</b> {!Get_Account.Name}</p>",
          "fieldType": "DisplayText"
        },
        {
          "name": "BillingCity",
          "fieldText": "Billing City",
          "fieldType": "InputField",
          "dataType": "String",
          "isRequired": false,
          "defaultValue": { "elementReference": "Get_Account.BillingCity" }
        }
      ]
    }
  ]
}
```

**Navigation rules:**
- `allowBack` + `allowFinish` — at least one MUST be `true`. Setting both to `false` is rejected.
- `allowPause` — independent; can be `true` or `false` regardless.
- The last screen in a wizard should have `allowFinish: true`.
- Middle screens typically have `allowBack: true, allowFinish: false`.

### Screen field types — CRITICAL reference

Every `fields` entry in a screen MUST have a `fieldType`. These are the valid types:

#### DisplayText — read-only HTML text

```json
{
  "name": "InfoMessage",
  "fieldText": "<p><b>Account:</b> {!Get_Account.Name}</p>",
  "fieldType": "DisplayText"
}
```

- `fieldText` contains HTML. Flow variable references use `{!VarName}` syntax.
- **No `dataType` needed** — display-only.
- **No `name` attribute is technically needed** for display text, but include one for clarity.

#### InputField — user text/number/date/boolean input

```json
{
  "name": "UserCity",
  "fieldText": "City",
  "fieldType": "InputField",
  "dataType": "String",
  "isRequired": false,
  "defaultValue": { "elementReference": "Get_Account.BillingCity" }
}
```

**CRITICAL: `dataType` is REQUIRED on every InputField.** Without it, Salesforce errors with *"must have a data type"*. Valid values:
- `"String"` — text input (NOT "Text" — same rule as flow variables)
- `"Number"` — numeric input (add `scale` for decimal places)
- `"Currency"` — currency input (add `scale` for decimal places)
- `"Boolean"` — checkbox/toggle. **Do NOT set `isRequired: false` on Boolean InputFields** — Salesforce rejects it. Omit `isRequired` entirely (checkboxes are inherently optional: unchecked = false).
- `"Date"` — date picker
- `"DateTime"` — date+time picker

**For Currency/Number InputFields**, also include `scale`:
```json
{
  "name": "Amount",
  "fieldText": "Amount",
  "fieldType": "InputField",
  "dataType": "Currency",
  "isRequired": true,
  "scale": 2,
  "defaultValue": { "elementReference": "Get_Opportunity.Amount" }
}
```

#### ObjectProvided — display/edit a field from a record variable

Shows a Salesforce field from a Get Records result, with the field's native UI (lookup picker, picklist dropdown, etc.):

```json
{
  "fieldType": "ObjectProvided",
  "isRequired": false,
  "objectFieldReference": "Get_Opportunity.StageName",
  "inputsOnNextNavToAssocScrn": "UseStoredValues"
}
```

- **No `name` needed** — the field reference identifies it.
- **No `dataType` needed** — inherited from the referenced field.
- `inputsOnNextNavToAssocScrn: "UseStoredValues"` — preserves user input when navigating back.

#### LargeTextArea — multi-line text input

```json
{
  "name": "Notes",
  "fieldText": "Notes",
  "fieldType": "LargeTextArea",
  "isRequired": false
}
```

- LargeTextArea **does NOT need an explicit `dataType`** — it's implicitly String.
- Do NOT add `dataType: "String"` on LargeTextArea — it's unnecessary and can cause errors in some contexts.

### Layout: RegionContainer and Region (two-column layouts)

To create side-by-side columns on a screen:

```json
{
  "name": "Details_Section",
  "fieldType": "RegionContainer",
  "regionContainerType": "SectionWithoutHeader",
  "isRequired": false,
  "fields": [
    {
      "name": "Left_Column",
      "fieldType": "Region",
      "isRequired": false,
      "inputParameters": [{ "name": "width", "value": { "stringValue": "6" } }],
      "fields": [
        { "fieldType": "ObjectProvided", "objectFieldReference": "Get_Account.Name", "isRequired": false },
        { "fieldType": "ObjectProvided", "objectFieldReference": "Get_Account.Industry", "isRequired": false }
      ]
    },
    {
      "name": "Right_Column",
      "fieldType": "Region",
      "isRequired": false,
      "inputParameters": [{ "name": "width", "value": { "stringValue": "6" } }],
      "fields": [
        { "fieldType": "ObjectProvided", "objectFieldReference": "Get_Account.Phone", "isRequired": false },
        { "fieldType": "ObjectProvided", "objectFieldReference": "Get_Account.Website", "isRequired": false }
      ]
    }
  ]
}
```

- `regionContainerType`: `"SectionWithoutHeader"` or `"SectionWithHeader"`
- Column `width`: `"6"` = half width (12-column grid). Two columns at `"6"` = side by side.
- `isRequired: false` is needed on the container, each region, and each field.

### Referencing screen inputs in downstream elements

Screen input values are referenced by their `name`, not by a variable:

```json
{
  "decisions": [
    {
      "name": "Check_Send_Email",
      "rules": [{
        "conditions": [{
          "leftValueReference": "SendEmailCheckbox",
          "operator": "EqualTo",
          "rightValue": { "booleanValue": true }
        }],
        "connector": { "targetReference": "Send_Email" }
      }]
    }
  ]
}
```

Where `SendEmailCheckbox` is the `name` of a Boolean InputField on a previous screen.

**CRITICAL: when referencing a screen input in a decision condition, that screen input MUST have a `dataType` set.** If the InputField doesn't have `dataType`, the condition fails with *"Screen Component X must have a data type"*.

### Screen input → record update mapping

When updating a record with values the user entered on a screen:

```json
{
  "recordUpdates": [
    {
      "name": "Update_Account",
      "object": "Account",
      "filterLogic": "and",
      "filters": [{ "field": "Id", "operator": "EqualTo", "value": { "elementReference": "recordId" } }],
      "inputAssignments": [
        { "field": "BillingCity", "value": { "elementReference": "UserCity" } },
        { "field": "BillingState", "value": { "elementReference": "UserState" } }
      ]
    }
  ]
}
```

**The `elementReference` uses the screen field's `name` directly** — `UserCity` references the InputField named `UserCity` on a previous screen.

**IMPORTANT for record updates using screen inputs:** the screen field and the target Salesforce field must have compatible types. If you map a String screen input to a Number field, Salesforce will reject it at runtime. Use `describe_object` to check the target field type before building the mapping.

### Visibility rules on screen fields — what works and what doesn't

Screen fields support visibility conditions that show/hide the field based on runtime values:

**Works:**
```json
{
  "visibilityRule": {
    "conditionLogic": "and",
    "conditions": [{
      "leftValueReference": "ShowDetailsCheckbox",
      "operator": "EqualTo",
      "rightValue": { "booleanValue": true }
    }]
  }
}
```

**Does NOT work — checking if a Get Records result is null:**
```json
{
  "visibilityRule": {
    "conditionLogic": "and",
    "conditions": [{
      "leftValueReference": "Get_Primary_Contact",
      "operator": "IsNull",
      "rightValue": { "booleanValue": false }
    }]
  }
}
```

This fails with: *"In a Screen Component, a condition doesn't support 'Get_Primary_Contact' Is null."*

**Fix:** instead of checking `IsNull` on the entire record variable, check a specific field:
```json
{
  "leftValueReference": "Get_Primary_Contact.Id",
  "operator": "IsNull",
  "rightValue": { "booleanValue": false }
}
```

Or use a formula/variable that evaluates to Boolean and check that:
```json
{
  "leftValueReference": "HasPrimaryContact",
  "operator": "EqualTo",
  "rightValue": { "booleanValue": true }
}
```

### Validation rules on screen fields

Screen InputFields support inline validation:

```json
{
  "name": "KickoffDate",
  "fieldText": "Kickoff Call Date",
  "fieldType": "InputField",
  "dataType": "Date",
  "isRequired": true,
  "validationRule": {
    "errorMessage": "Date must be in the future",
    "formulaExpression": "{!KickoffDate} > {!$Flow.CurrentDate}"
  }
}
```

The validation runs when the user clicks Next/Finish. If it fails, the error message appears below the field.

### Error handling in Screen Flows

Screen Flows can show error screens instead of sending emails (since the user is present):

```json
{
  "screens": [
    {
      "name": "Error_Screen",
      "label": "Error",
      "allowBack": true,
      "allowFinish": true,
      "showFooter": true,
      "showHeader": true,
      "fields": [{
        "name": "ErrorText",
        "fieldType": "DisplayText",
        "fieldText": "<p style=\"color: red;\"><b>An error occurred:</b> {!$Flow.FaultMessage}</p>"
      }]
    }
  ]
}
```

Use `faultConnector` on DML elements to route to the error screen:
```json
{
  "recordCreates": [{
    "name": "Create_Record",
    "faultConnector": { "targetReference": "Error_Screen" },
    "connector": { "targetReference": "Success_Screen" },
    ...
  }]
}
```

### COMPLETE EXAMPLE: Simple Screen Flow launched from Account record

This flow is launched from a button on the Account record page. It shows the account name, lets the user enter notes, and creates a Task.

```json
{
  "processType": "Flow",
  "apiVersion": "62.0",
  "status": "Active",
  "label": "Create Follow-up Task",
  "interviewLabel": "Create Follow-up Task {!$Flow.CurrentDateTime}",
  "environments": "Default",
  "processMetadataValues": [
    { "name": "BuilderType", "value": { "stringValue": "LightningFlowBuilder" } },
    { "name": "CanvasMode", "value": { "stringValue": "AUTO_LAYOUT_CANVAS" } },
    { "name": "OriginBuilderType", "value": { "stringValue": "LightningFlowBuilder" } }
  ],
  "start": {
    "locationX": 50,
    "locationY": 0,
    "connector": { "targetReference": "Get_Account" }
  },
  "variables": [
    { "name": "recordId", "dataType": "String", "isCollection": false, "isInput": true, "isOutput": false }
  ],
  "recordLookups": [
    {
      "name": "Get_Account",
      "label": "Get Account",
      "object": "Account",
      "filterLogic": "and",
      "filters": [{ "field": "Id", "operator": "EqualTo", "value": { "elementReference": "recordId" } }],
      "getFirstRecordOnly": true,
      "storeOutputAutomatically": true,
      "connector": { "targetReference": "Task_Screen" }
    }
  ],
  "screens": [
    {
      "name": "Task_Screen",
      "label": "Create Follow-up Task",
      "locationX": 176,
      "locationY": 200,
      "allowBack": false,
      "allowFinish": true,
      "allowPause": false,
      "showFooter": true,
      "showHeader": true,
      "connector": { "targetReference": "Create_Task" },
      "fields": [
        {
          "name": "AccountInfo",
          "fieldType": "DisplayText",
          "fieldText": "<p><b>Account:</b> {!Get_Account.Name}</p>"
        },
        {
          "name": "TaskSubject",
          "fieldText": "Task Subject",
          "fieldType": "InputField",
          "dataType": "String",
          "isRequired": true,
          "defaultValue": { "stringValue": "Follow-up" }
        },
        {
          "name": "TaskDueDate",
          "fieldText": "Due Date",
          "fieldType": "InputField",
          "dataType": "Date",
          "isRequired": true
        },
        {
          "name": "TaskNotes",
          "fieldText": "Notes",
          "fieldType": "LargeTextArea",
          "isRequired": false
        }
      ]
    },
    {
      "name": "Success_Screen",
      "label": "Success",
      "locationX": 176,
      "locationY": 600,
      "allowBack": false,
      "allowFinish": true,
      "allowPause": false,
      "showFooter": true,
      "showHeader": true,
      "fields": [{
        "name": "SuccessText",
        "fieldType": "DisplayText",
        "fieldText": "<p><b>Task created successfully.</b></p>"
      }]
    },
    {
      "name": "Error_Screen",
      "label": "Error",
      "locationX": 400,
      "locationY": 400,
      "allowBack": true,
      "allowFinish": true,
      "allowPause": false,
      "showFooter": true,
      "showHeader": true,
      "fields": [{
        "name": "ErrorText",
        "fieldType": "DisplayText",
        "fieldText": "<p style=\"color: red;\">Error: {!$Flow.FaultMessage}</p>"
      }]
    }
  ],
  "recordCreates": [
    {
      "name": "Create_Task",
      "label": "Create Follow-up Task",
      "locationX": 176,
      "locationY": 400,
      "object": "Task",
      "connector": { "targetReference": "Success_Screen" },
      "faultConnector": { "targetReference": "Error_Screen" },
      "inputAssignments": [
        { "field": "Subject", "value": { "elementReference": "TaskSubject" } },
        { "field": "ActivityDate", "value": { "elementReference": "TaskDueDate" } },
        { "field": "Description", "value": { "elementReference": "TaskNotes" } },
        { "field": "WhatId", "value": { "elementReference": "recordId" } },
        { "field": "OwnerId", "value": { "elementReference": "$User.Id" } },
        { "field": "Status", "value": { "stringValue": "Not Started" } }
      ]
    }
  ]
}
```

### Launching a Screen Flow from a record page

Screen Flows need a Quick Action to be launchable from a record page button. Use the `create_quick_action` tool:

```
create_quick_action(
  object_name="Account",
  action_name="Start_Onboarding",
  label="Start Onboarding",
  type="Flow",
  flow_definition="Account_Onboarding_Screen_Flow",
  description="Launch the customer onboarding wizard"
)
```

**Quick Actions CANNOT be created via Apex** — do NOT use `execute_anonymous_apex` for this. The `create_quick_action` tool uses the Metadata API.

After creating the Quick Action, **add it to the relevant page layout(s)** using `update_page_layout` with `action: "add_action"`:

```
update_page_layout(
  layout_full_name="Account-Account Layout",
  action="add_action",
  field_api_name="Account.Start_Onboarding"
)
```

This adds the button to the layout's Quick Actions section so it's visible on record pages. Do this for each layout the user wants the button on. Use `list_page_layouts` first to see available layouts.

For **Lightning Record Pages** (FlexiPages), the button appears automatically if the page has a Highlights Panel or Actions component — no additional configuration needed beyond the page layout.

### Common Screen Flow mistakes — DO NOT make these

| Mistake | Error message | Fix |
|---|---|---|
| Missing `dataType` on InputField | `"X" must have a data type` | Always include `dataType: "String"` (or Number, Boolean, Date, etc.) on every InputField |
| Using `dataType: "Text"` | `'Text' is not a valid value for the enum 'FlowDataType'` | Use `"String"` (same rule as flow variables) |
| `allowBack: false` AND `allowFinish: false` | `You can set either allowFinish or allowBack to false, but not both` | At least one must be `true` |
| `isRequired: false` on a Boolean InputField | `isRequired can't be set to false for screen input fields of type boolean` | Omit `isRequired` entirely on Boolean InputFields, or set it to `true`. Checkboxes are inherently optional (unchecked = false). |
| `IsNull` on a Get Records result in a visibility rule | `condition doesn't support "X" Is null` | Check a specific field: `Get_X.Id IsNull` instead of `Get_X IsNull` |
| Referencing screen input in decision without `dataType` | `Screen Component "X" must have a data type` | Add `dataType` to the InputField definition |
| Duplicate screen field names across flows in the org | `Duplicate developer name: X` | Use unique, descriptive names: `Scr1_BillingCity` not `BillingCity` |
| Collection variable with `value` and `isCollection: true` | `The value field isn't supported when isCollection is set to true` | Don't set `value`/`defaultValue` on collection variables — populate via Assignment elements |
| `$Record` reference in a Screen Flow | `$Record` is not available | Use `recordId` input variable + Get Records lookup |

---

## Flow testing checklist

Before activating any flow, verify:

- [ ] **Path coverage** — test every decision branch (every outcome, including the default)
- [ ] **Bulk test** — trigger with 200+ records at once (e.g., bulk data load or mass update)
- [ ] **Edge cases** — null values, empty collections, blank text fields, date boundaries
- [ ] **User context** — test with different profiles (admin, standard user, community user)
- [ ] **Error handling** — verify fault paths fire correctly when DML fails
- [ ] **Entry conditions** — verify the flow does NOT fire when conditions are not met
- [ ] **Before-save only updates $Record** — verify no DML elements exist in before-save flows (they'll fail)

## Scheduled Flow structure (CRITICAL — read before building any scheduled flow)

**MANDATORY RULE: When a user asks for a "scheduled flow", ALWAYS create a native Scheduled Flow using `triggerType: "Scheduled"` with a `schedule` object on the `start` element. NEVER create an Autolaunched Flow + Schedulable Apex class combo. The Apex scheduler approach is over-engineered and unnecessary — Salesforce natively supports scheduled flows via the Metadata API.**

Scheduled flows run on a recurring schedule (daily, weekly, etc.) and process a batch of records or perform background work. They use `processType: "AutoLaunchedFlow"` and `triggerType: "Scheduled"`.

### The `start` element for scheduled flows

The `start` element MUST include a `schedule` object. The schedule object has exactly these properties:

```json
"start": {
  "locationX": 50,
  "locationY": 0,
  "triggerType": "Scheduled",
  "connector": {
    "targetReference": "First_Element_Api_Name"
  },
  "schedule": {
    "frequency": "Weekly",
    "startDate": "2026-04-14",
    "startTime": "08:00:00.000Z"
  }
}
```

### `schedule.frequency` valid values

| Value | Meaning |
|-------|---------|
| `Once` | Run once at the specified date/time |
| `Daily` | Run every day at the specified time |
| `Weekly` | Run every week on the day of `startDate` at the specified time |

**CRITICAL rules:**
- `frequency`, `startDate`, and `startTime` are the ONLY valid properties inside `schedule`
- There is NO `daysOfWeek`, `weekdays`, `weeklyDayOfWeek`, `weeklyRecurrence`, `monthlyRecurrence`, or `cronExpression` property — these do NOT exist in the Metadata API and will cause deployment errors
- Do NOT use `scheduledPaths` for scheduled flows. `scheduledPaths` is for record-triggered flows with async scheduled paths (e.g., "run 1 hour after save"). Scheduled flows use `schedule` directly on `start` — these are completely different things
- For weekly flows, the day-of-week is determined by the `startDate` — if `startDate` falls on a Monday, the flow runs every Monday
- `startDate` format: `YYYY-MM-DD` (ISO date, no time component)
- `startTime` format: `HH:MM:SS.000Z` (UTC time with milliseconds)
- After activation, admins can modify the schedule in the Flow Builder UI, but the metadata API only supports the three fields above

### How to calculate `startDate` for a specific day of the week

If the user asks "run every Monday at 8am", find the next Monday from today and use that as `startDate`. The flow will then recur weekly on that same day.

If the user asks "run every day at midnight", use tomorrow's date as `startDate` with `frequency: "Daily"` and `startTime: "00:00:00.000Z"`.

### Two patterns for scheduled flows

**Pattern 1: Plain scheduled (no object on start)** — The flow runs on a schedule and the body uses `recordLookups` to query whatever records it needs. Good for complex queries with custom filter logic, multiple objects, or aggregate operations.

**Pattern 2: Scheduled with object + filters on start** — The `start` element includes `object`, `filters`, and optionally `filterLogic`. Salesforce automatically queries matching records and runs the flow once per record (like a record-triggered flow on a schedule). Good for simple "find records matching criteria and do something to each" scenarios.

#### Pattern 2 start element example (object + filters on start):

```json
"start": {
  "locationX": 56,
  "locationY": 0,
  "triggerType": "Scheduled",
  "connector": { "targetReference": "First_Element" },
  "object": "Task",
  "filterLogic": "and",
  "filters": [
    { "field": "Status", "operator": "NotEqualTo", "value": { "stringValue": "Completed" } },
    { "field": "ActivityDate", "operator": "LessThanOrEqualTo", "value": { "elementReference": "$Flow.CurrentDate" } }
  ],
  "schedule": {
    "frequency": "Daily",
    "startDate": "2026-04-14",
    "startTime": "05:00:00.000Z"
  }
}
```

When `object` is specified on start, each matching record is available as `$Record` inside the flow — the same as record-triggered flows. You do NOT need a separate `recordLookups` element.

When `object` is NOT specified on start, there is no `$Record`. Use `recordLookups` in the flow body to query whatever data you need.

### Complete scheduled flow example (Pattern 1) — weekly task creation

This flow runs every Monday at 8am, finds open Opportunities closing within 7 days with no recent activity, and creates follow-up Tasks:

```json
{
  "apiVersion": "62.0",
  "processType": "AutoLaunchedFlow",
  "environments": "Default",
  "interviewLabel": "Opp Follow Up Tasks {!$Flow.CurrentDateTime}",
  "processMetadataValues": [
    { "name": "BuilderType", "value": { "stringValue": "LightningFlowBuilder" } },
    { "name": "CanvasMode", "value": { "stringValue": "AUTO_LAYOUT_CANVAS" } },
    { "name": "OriginBuilderType", "value": { "stringValue": "LightningFlowBuilder" } }
  ],
  "start": {
    "locationX": 50,
    "locationY": 0,
    "triggerType": "Scheduled",
    "connector": { "targetReference": "Get_Opps" },
    "schedule": {
      "frequency": "Weekly",
      "startDate": "2026-04-13",
      "startTime": "08:00:00.000Z"
    }
  },
  "formulas": [
    { "name": "SevenDaysFromNow", "dataType": "Date", "expression": "{!$Flow.CurrentDate} + 7" },
    { "name": "FourteenDaysAgo", "dataType": "Date", "expression": "{!$Flow.CurrentDate} - 14" }
  ],
  "variables": [
    { "name": "TasksToCreate", "dataType": "SObject", "objectType": "Task", "isCollection": true, "isInput": false, "isOutput": false },
    { "name": "CurrentTask", "dataType": "SObject", "objectType": "Task", "isCollection": false, "isInput": false, "isOutput": false },
    { "name": "FaultEmailRecipients", "dataType": "String", "isCollection": true, "isInput": false, "isOutput": false }
  ],
  "textTemplates": [
    { "name": "FaultEmailBody", "isViewedAsPlainText": true, "text": "The weekly Opportunity follow-up flow failed.\\nError: {!$Flow.FaultMessage}" }
  ],
  "recordLookups": [
    {
      "name": "Get_Opps",
      "label": "Get Opps Closing Soon",
      "object": "Opportunity",
      "locationX": 176,
      "locationY": 134,
      "getFirstRecordOnly": false,
      "storeOutputAutomatically": true,
      "filterLogic": "1 AND 2 AND 3 AND (4 OR 5)",
      "filters": [
        { "field": "IsClosed", "operator": "EqualTo", "value": { "booleanValue": false } },
        { "field": "CloseDate", "operator": "GreaterThanOrEqualTo", "value": { "elementReference": "$Flow.CurrentDate" } },
        { "field": "CloseDate", "operator": "LessThanOrEqualTo", "value": { "elementReference": "SevenDaysFromNow" } },
        { "field": "LastActivityDate", "operator": "LessThanOrEqualTo", "value": { "elementReference": "FourteenDaysAgo" } },
        { "field": "LastActivityDate", "operator": "IsNull", "value": { "booleanValue": true } }
      ],
      "connector": { "targetReference": "Check_Results" }
    }
  ],
  "decisions": [
    {
      "name": "Check_Results",
      "label": "Any Opps Found?",
      "locationX": 176,
      "locationY": 254,
      "defaultConnectorLabel": "No Records",
      "rules": [
        {
          "name": "Has_Records",
          "label": "Has Records",
          "conditionLogic": "and",
          "conditions": [
            { "leftValueReference": "Get_Opps", "operator": "IsNull", "rightValue": { "booleanValue": false } }
          ],
          "connector": { "targetReference": "Loop_Opps" }
        }
      ]
    }
  ],
  "loops": [
    {
      "name": "Loop_Opps",
      "label": "Loop Opps",
      "locationX": 264,
      "locationY": 374,
      "collectionReference": "Get_Opps",
      "iterationOrder": "Asc",
      "nextValueConnector": { "targetReference": "Assign_Task" },
      "noMoreValuesConnector": { "targetReference": "Create_All_Tasks" }
    }
  ],
  "assignments": [
    {
      "name": "Assign_Task",
      "label": "Assign Task Fields",
      "locationX": 352,
      "locationY": 494,
      "assignmentItems": [
        { "assignToReference": "CurrentTask.OwnerId", "operator": "Assign", "value": { "elementReference": "Loop_Opps.OwnerId" } },
        { "assignToReference": "CurrentTask.WhatId", "operator": "Assign", "value": { "elementReference": "Loop_Opps.Id" } },
        { "assignToReference": "CurrentTask.Subject", "operator": "Assign", "value": { "stringValue": "Follow up required — closing soon" } },
        { "assignToReference": "CurrentTask.ActivityDate", "operator": "Assign", "value": { "elementReference": "$Flow.CurrentDate" } },
        { "assignToReference": "CurrentTask.Priority", "operator": "Assign", "value": { "stringValue": "High" } }
      ],
      "connector": { "targetReference": "Add_To_Collection" }
    },
    {
      "name": "Add_To_Collection",
      "label": "Add Task to Collection",
      "locationX": 352,
      "locationY": 614,
      "assignmentItems": [
        { "assignToReference": "TasksToCreate", "operator": "Add", "value": { "elementReference": "CurrentTask" } }
      ],
      "connector": { "targetReference": "Loop_Opps" }
    },
    {
      "name": "Set_Fault_Recipients",
      "label": "Set Fault Recipients",
      "locationX": 594,
      "locationY": 494,
      "assignmentItems": [
        { "assignToReference": "FaultEmailRecipients", "operator": "Add", "value": { "stringValue": "admin@example.com" } }
      ],
      "connector": { "targetReference": "Send_Fault_Email" }
    }
  ],
  "recordCreates": [
    {
      "name": "Create_All_Tasks",
      "label": "Create All Tasks",
      "locationX": 264,
      "locationY": 814,
      "inputReference": "TasksToCreate",
      "faultConnector": { "targetReference": "Set_Fault_Recipients" }
    }
  ],
  "actionCalls": [
    {
      "name": "Send_Fault_Email",
      "label": "Send Fault Email",
      "locationX": 594,
      "locationY": 614,
      "actionType": "emailSimple",
      "actionName": "emailSimple",
      "nameSegment": "emailSimple",
      "versionString": "1.0.1",
      "flowTransactionModel": "CurrentTransaction",
      "inputParameters": [
        { "name": "emailAddressesArray", "value": { "elementReference": "FaultEmailRecipients" } },
        { "name": "emailSubject", "value": { "stringValue": "Flow Error: Opp Follow Up Tasks" } },
        { "name": "emailBody", "value": { "elementReference": "FaultEmailBody" } },
        { "name": "sendRichBody", "value": { "booleanValue": true } }
      ]
    }
  ]
}
```

### Key patterns in the example above

1. **Pattern 1 (no object on `start`)** — the `recordLookups` element queries Opportunity, not the start trigger. Use this when you need complex filter logic or multiple objects.
2. **Collection pattern** — uses a loop + assignment + `Add` operator to build a Task collection, then a single `recordCreates` to bulk-insert all tasks
3. **Fault handling** — `faultConnector` on the DML element routes to an email notification via `emailSimple`
4. **Formula fields for date math** — `SevenDaysFromNow` and `FourteenDaysAgo` computed with `$Flow.CurrentDate`
5. **`iterationOrder: "Asc"`** — the only valid values are `Asc` and `Desc` (NOT `Ascending`, `Descending`, `FirstItemIn`, or `LastItemIn`)
6. **When to use Pattern 2 instead** — if the requirement is simply "find all records matching X and do Y to each", use `object` + `filters` on start. The flow runs per-record with `$Record` available, and you don't need a `recordLookups` or loop.

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
