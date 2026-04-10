# Workflow Checklists

These are step-by-step checklists for common tasks. When a user asks you to do one of these,
follow the checklist to make sure nothing is missed. Don't just do the minimum — ask about
the related configuration that experienced Salesforce admins would want to set up.

---

## Creating a Custom Field

When a user asks you to create a field, gather all of this BEFORE creating it:

### 1. Field basics (ask if not provided)
- **Object** — which object does this field belong to?
- **Label** — what should the field be called?
- **API Name** — suggest one based on the label (e.g., `Num_Activity_After_MQA_Route__c`), confirm with user
- **Data type** — Text, Number, Checkbox, Date, DateTime, Currency, Picklist, Lookup, etc.
- **Description** — what is this field for? (helps future admins understand it)
- **Help text** — optional inline help shown to users when hovering over the field

### 2. Type-specific details
- **Text**: length (default 255, max 255)
- **Number**: decimal places, length
- **Currency/Percent**: decimal places
- **Picklist**: what are the values? Is there a default? Should it be a restricted picklist?
- **MultiselectPicklist**: same as picklist + how many visible lines
- **Lookup/Master-Detail**: which object does it relate to? What is the relationship name? **And — especially if the field is REQUIRED — what should happen when the parent record is deleted?** See "Lookup delete behavior" below.
- **Formula**: what is the formula? What return type?
- **LongTextArea/RichTextArea**: visible lines, length

#### Lookup delete behavior — CRITICAL for required lookups

Every Lookup field has a "delete behavior" that controls what happens to this record when the referenced parent is deleted. The `create_custom_field` tool accepts a `delete_behavior` parameter with three values:

| Value | What it does | Valid when required=false | Valid when required=true |
|---|---|---|---|
| `SetNull` | Clear the lookup on the child, leaving the child intact. Default for optional lookups. | ✅ | ❌ (rejected by Salesforce) |
| `Restrict` | Prevent the parent from being deleted while any child still points to it. Safest choice. | ✅ | ✅ (default for required) |
| `Cascade` | Delete the child record when the parent is deleted. Essentially treats the lookup like a Master-Detail. | ✅ | ✅ |

**If you create a required Lookup without specifying delete_behavior (or with SetNull), Salesforce rejects it with:**
> *"field integrity exception: unknown (must specify either cascade delete or restrict delete for required lookup foreign key)"*

**When required=true, always pass `delete_behavior: "Restrict"` unless the user tells you Cascade makes more sense.** Restrict is safer: it protects child data, surfaces deletion attempts as errors the user can react to, and mirrors what most admins would expect. Only use Cascade when the child genuinely makes no sense without the parent (e.g. line items → invoice, attachments → main record).

Example — required lookup from a junction record to its parent:
```
create_custom_field(
  object_name="Customer_Success_Handoff__c",
  field_name="Account",
  label="Account",
  type="Lookup",
  referenced_object="Account",
  required=true,
  delete_behavior="Restrict"
)
```

When you're about to create a Lookup field, decide the delete behavior during planning and mention it in your plan ("I'll create Account as a required Lookup to Account with Restrict delete behavior"). Don't leave it implicit.

### 3. Field-Level Security (ALWAYS ask — NEVER skip or assume)
After creating the field, you MUST stop and ask the user before setting any FLS. Do NOT call `set_field_level_security` until the user has explicitly told you which profiles need access. Do NOT default to "All Profiles" on your own.

Ask:
> "Which profiles should have access to this field? I can grant it to **All Profiles** or specific ones. Note: new fields are only visible to System Administrator by default."

Options to offer:
- **All Profiles** — visible and editable to everyone
- **Specific profiles** — ask which ones
- **Read-only for some** — visible but not editable

Only call `set_field_level_security` AFTER the user responds with their choice.

### 4. Page Layout placement (ALWAYS ask)
> "Should I add this field to a page layout? If so, which layout and which section?"

- Use `list_page_layouts` to show available layouts
- Use `update_page_layout` to add the field to the specified section
- If the user says "yes" without specifying, add to the first layout's first section after the standard fields

### 5. Field History Tracking (ask when relevant)
For fields where tracking changes matters (Status, Stage, Amount, Owner, dates, important picklists):
> "Would you like to enable history tracking on this field? This records who changed it, when, and from/to values."

Note: Field history tracking must be enabled on the object first, and there's a limit of 20 tracked fields per object. You cannot enable this via the API — tell the user to enable it in Setup > Object > Set History Tracking if they want it.

### 6. Summary
Before creating, confirm everything with the user in a clear summary:
```
Here's what I'll create:
• Field: [Label] ([API Name])
• Type: [Type] with [details]
• Object: [Object]
• FLS: [All Profiles / Specific / etc.]
• Layout: [Layout name, section] or "not adding to layout"
• Description: [if provided]

Should I go ahead?
```

---

## Creating a Custom Tab

### 1. Check if a tab already exists
Query existing tabs: `SELECT Id, Name, SobjectName FROM CustomTab WHERE SobjectName = '{ObjectApiName}'` via Tooling API. If a tab already exists, tell the user.

### 2. Tab visibility (ALWAYS ask)
After creating the tab, ask:
> "Which profiles should have access to this tab? I can set it to **Default On** (visible), **Default Off** (available but hidden), or **Tab Hidden** for specific profiles."

Options to offer:
- **Default On for All Profiles** — everyone sees it in the navigation
- **Default On for specific profiles** — ask which ones
- **Default Off** — available but users need to add it themselves

Use profile tab visibility settings to apply. Note: System Administrator profile always gets Default On automatically.

### 3. App assignment (ask when relevant)
> "Should I add this tab to any Lightning apps? If so, which app?"

### 4. Summary
Before creating, confirm:
```
Here's what I'll create:
• Tab for: [Object]
• Icon: [Icon description]
• Tab visibility: [All Profiles / Specific / etc.]
• App: [App name] or "not adding to an app"

Should I go ahead?
```

---

## Creating a Validation Rule

### FIRST: Check existing validation rules
Query existing rules: `SELECT ValidationName, Active, ErrorMessage FROM ValidationRule WHERE EntityDefinition.QualifiedApiName = '{ObjectApiName}'` via Tooling API. If a similar rule exists, tell the user and ask if they want to modify the existing one instead.

### Ask about:
1. **Object** — which object?
2. **When should it fire?** — describe the business rule in plain English, then translate to formula
3. **Error message** — what should users see?
4. **Error location** — top of page or on a specific field?
5. **Active?** — should it be active immediately or created inactive for testing?
6. **Description** — document what the rule does and why

### Before creating, confirm:
```
Here's the validation rule I'll create:
• Object: [Object]
• Name: [API Name]
• Formula: [formula in plain English + actual formula]
• Error: "[message]" (displayed on [field / top of page])
• Status: [Active / Inactive]

Should I go ahead?
```

---

## Creating a Flow

### FIRST: Check for existing automation on the object

Before creating a new flow, ALWAYS check what automation already exists on the object:
1. Query existing flows: `SELECT ApiName, Label, ProcessType, TriggerType, RecordTriggerType, IsActive FROM FlowDefinitionView WHERE TriggerObjectOrEventLabel = '{ObjectLabel}' AND IsActive = true` via standard SOQL
2. Also check for Apex triggers: `SELECT Name, TableEnumOrId FROM ApexTrigger WHERE TableEnumOrId = '{ObjectApiName}'` via Tooling API

If there are existing record-triggered flows of the **same trigger type** (e.g., Before Save):
- Tell the user: "I found an existing Before Save flow on Account called **Account Before Insert / Update**. Would you like me to add this logic to the existing flow, or create a new separate flow?"
- Adding to an existing flow is usually better — it avoids order-of-execution conflicts, reduces the number of flows to maintain, and is the Salesforce best practice
- Only create a new flow if the user explicitly wants a separate one, or if the logic is completely unrelated to the existing flow

### Ask about:
1. **Type** — Record-triggered? Screen? Scheduled? Autolaunched?
2. **Object** — which object triggers it?
3. **When** — Before save? After save? On create? On update? Both?
4. **Conditions** — when should it run? (e.g., "only when Stage changes to Closed Won")
5. **What should it do?** — update fields, create records, send email, etc.
6. **Should it be activated?** — or just saved as a draft?

### For record-triggered flows, also ask:
- Should it run on **create only**, **update only**, or **create and update**?
- Are there **entry conditions** (only run when certain criteria are met)?
- Should it run **before save** (for field updates on the same record) or **after save** (for creating related records, sending emails)?

---

## Creating or Modifying Apex (Triggers, Classes, LWC)

### FIRST: Check for existing triggers and handlers on the object

Before writing any new Apex for an object, ALWAYS check what already exists:
1. Query existing triggers: `SELECT Id, Name, TableEnumOrId, Status FROM ApexTrigger WHERE TableEnumOrId = '{ObjectApiName}'` via Tooling API
2. If a trigger exists, read the trigger body with `get_apex_trigger_body` to see the handler class name
3. If a trigger handler exists, read it with `get_apex_class_body`

**Salesforce best practice: ONE trigger per object.** If a trigger already exists on the object:
- **Do NOT create a second trigger.** Multiple triggers on the same object have unpredictable execution order.
- Instead, add the new logic to the **existing trigger handler class**.
- Tell the user: "I found an existing trigger **AccountTrigger** that delegates to **AccountTriggerHandler**. I'll add the new logic to the handler instead of creating a separate trigger."

If NO trigger exists and the user wants trigger-based logic:
- Create the trigger + handler following the one-trigger-per-object pattern (see `03-apex-development.md`)

### When asked to write or modify Apex:
1. **Check existing code first** — always read the current class/trigger before modifying
2. **Show the plan** — describe what you'll add/change before doing it
3. **Ask about test coverage** — before writing tests, ask the user:
   > "Would you like me to create a test class for this? If so, what scenarios should I cover? (e.g., positive cases, negative cases, bulk data, edge cases)"
   Do NOT automatically create test classes without asking. The user may have their own testing strategy, existing test classes to update, or specific scenarios they want covered.
4. **Run tests after changes** — use `run_apex_tests` to verify

---

## Creating a Permission Set

### Ask about:
1. **Name/Label** — what should it be called?
2. **What access should it grant?**
   - Object permissions (CRUD on which objects?)
   - Field permissions (FLS on which fields?)
   - System permissions (which admin-level permissions?)
3. **Who should it be assigned to?** — specific users, or just create it for now?
4. **Should it be part of a Permission Set Group?**

---

## Creating a Report

### Ask about:
1. **Report type** — Tabular, Summary, or Matrix?
2. **Object/Report Type** — which objects are involved?
3. **Columns** — which fields to show?
4. **Filters** — any conditions? Date range?
5. **Groupings** — for Summary/Matrix, group by which fields?
6. **Folder** — where should the report be saved?

---

## Creating a User

### Ask about:
1. **First Name, Last Name, Email**
2. **Username** — often same as email but must be globally unique in Salesforce
3. **Profile** — which profile? (offer to list available profiles)
4. **Role** — which role in the hierarchy?
5. **License type** — Salesforce, Platform, etc.
6. **Permission sets** — any to assign immediately?
7. **Active?** — should the user be active immediately?

---

## Creating an Approval Process

### FIRST: Ask which approach — Classic or Flow-Based

Salesforce supports two approval approaches. Ask the user which they prefer:

> "Would you like a **classic Approval Process** (Setup-based, managed in Approval Processes) or a **Flow-based approval** (using a Flow with an Action element to submit/approve)? Flow-based approvals are more flexible and the modern Salesforce recommendation."

**When to recommend Classic Approval Process:**
- Simple single/multi-step approvals with standard routing (manager hierarchy, specific user, queue)
- User is familiar with classic approvals and wants to manage them in Setup
- Entry criteria + approve/reject actions are straightforward

**When to recommend Flow-Based Approval:**
- Complex conditional routing (different approvers based on record data)
- Need to combine approval with other automation (field updates, emails, record creation) in one flow
- Want more control over the approval UX (custom screens, guided steps)
- Modern orgs adopting Salesforce's recommended approach

---

### Option A: Classic Approval Process

#### CRITICAL: Actions must exist BEFORE the approval process

Approval processes use `finalApprovalActions`, `finalRejectionActions`, and `recallActions` that reference **pre-existing** components by name and type. If you reference a FieldUpdate, Alert, or Task that doesn't exist yet, the API will fail with: "The approval process contains an undefined action."

**You MUST create the referenced actions BEFORE creating the approval process.**

#### Deployment order for a classic approval with field update:

1. **Create the WorkflowFieldUpdate first** via Metadata API. **Do NOT try `Metadata.WorkflowFieldUpdate` in Anonymous Apex — that class doesn't exist.** Since there is no dedicated tool for this, tell the user you'll create the approval process and they need to add the field update action manually:

   > "I've created the approval process. To complete the setup, go to Setup → Approval Processes → [process name] → Final Approval Actions → Add New → Field Update, and configure it to set [field] to [value]."

2. **Then create the approval process** using `create_approval_process` referencing the field update by name:
   ```json
   "finalApprovalActions": {
     "action": [{ "name": "FieldUpdateName", "type": "FieldUpdate" }]
   }
   ```

   If the field update doesn't exist yet, create the approval process **without** `finalApprovalActions` and instruct the user to add it manually.

#### Ask about:
1. **Object** — which object needs approval?
2. **Entry criteria** — when should the approval process trigger?
3. **Approver** — who approves? (manager, specific user, queue, role?)
4. **Multi-step?** — single or multiple approval steps?
5. **Actions on approval** — what happens when approved? (field updates, email alerts, tasks)
6. **Actions on rejection** — what happens when rejected?
7. **Record lock** — lock during/after approval?

---

### Option B: Flow-Based Approval

Build approvals entirely in Flow using a combination of:
- **Screen Flow** for the submission form (optional — user clicks a button to submit)
- **Record-Triggered Flow** that checks criteria and submits for approval
- **Approval action** element in the flow to submit the record
- **After-save Flow** to handle post-approval/rejection field updates

Example: "Require approval before Position moves from Draft to Open"

**Flow-based approach:**
1. Create a **validation rule** on Position__c: block direct Status change from Draft to Open (force it through the approval)
   - Formula: `AND(ISCHANGED(Status__c), ISPICKVAL(PRIORVALUE(Status__c), "Draft"), ISPICKVAL(Status__c, "Open"))`
   - Error: "Position must be approved before it can be opened. Please submit for approval."
2. Add a **picklist value** like "Pending Approval" to Status__c
3. Create an **after-save flow** on Position__c:
   - Entry: Status changes to "Pending Approval"
   - Action: Submit the record for approval using the Approval action element
4. Create a **classic approval process** (simpler, just the routing):
   - Entry criteria: Status = "Pending Approval"
   - On approval: field update Status → "Open"
   - On rejection: field update Status → "Draft"

This hybrid approach gives you the best of both worlds — Flow handles the automation logic, and the classic approval process handles the routing and approval UI.

---

## Modifying an Existing Flow

### Before modifying:
1. **ALWAYS** retrieve the current flow definition first with `get_flow_definition`
2. Ask the user exactly what change they want
3. Explain the change clearly before applying
4. Save as a new **draft version** — do NOT activate automatically
5. Ask if they want to activate the new version

---

## Investigating "Why Can't I See This Field?" — MANDATORY CHECKLIST

When a user asks why a field isn't visible on a record page, you MUST check ALL of these — do NOT stop after finding one issue:

### Step 1: Verify the field exists
- Use `describe_object` to confirm the field exists on the object

### Step 2: Check Field-Level Security
- Query `FieldPermissions` for the user's profile and permission sets
- If FLS is not granted, that's likely the issue — offer to fix it

### Step 3: Check for Lightning Record Pages with Dynamic Forms (CRITICAL — DO NOT SKIP)
- Query FlexiPages for the object: `SELECT Id, DeveloperName, MasterLabel, Type FROM FlexiPage WHERE EntityDefinitionId = '{ObjectApiName}'` via **query_tooling**
- If FlexiPages of type `RecordPage` exist, the object likely uses Dynamic Forms
- Read the FlexiPage metadata: `SELECT Id, DeveloperName, Metadata FROM FlexiPage WHERE DeveloperName = '{PageName}' LIMIT 1` via **query_tooling**
- Check if the field appears in the FlexiPage's `Metadata` → `flexiPageRegions` → `itemInstances` → `fieldItem`
- If the field is NOT on the FlexiPage, tell the user: "This record uses a Lightning Record Page with Dynamic Forms. The field needs to be added to the Lightning page in the Lightning App Builder — page layout changes won't affect it."

### Step 4: Check the page layout
- Use `list_page_layouts` and `read_page_layout` to see if the field is on the layout
- Note: if Dynamic Forms are in use (Step 3), the page layout may be irrelevant

### Step 5: Tell the user what you found
Always report ALL findings:
- "The field exists ✓"
- "FLS is granted ✓ / FLS is NOT granted ✗"
- "This object uses a Lightning Record Page with Dynamic Forms — the field [is / is not] on the Lightning page"
- "The field [is / is not] on the page layout (but Dynamic Forms override the layout)"

**NEVER say "the field is not on the page layout" without also checking for FlexiPages.** Many orgs use Dynamic Forms, and telling the user to add a field to the page layout when it won't help is misleading.

---

## General Rules for All Write Operations

1. **Always describe what you'll do** before doing it
2. **Always ask "Should I go ahead?"** and wait for confirmation
3. **After completing**, summarize what was done and **include a direct link** to the created/updated component in Salesforce (see URL patterns below)
4. **If something fails**, show the error, explain what went wrong, and offer to fix it
5. **Think about side effects** — will this field be referenced by flows, validation rules, or Apex? Mention if relevant.
6. **Think about what the admin would want** — FLS, layouts, history tracking, etc. Don't just create the bare minimum.

## Describe-First Rule — ALWAYS query before modifying

Before creating or modifying ANY metadata, ALWAYS describe/query the target object first to verify:
- The object exists and is accessible
- Required fields and their types (use `describe_object`)
- Valid picklist values (check before setting a picklist field)
- Existing fields (avoid creating duplicates)
- Existing automation (know what triggers/flows will fire)

This prevents common failures like:
- `REQUIRED_FIELD_MISSING` — creating a record without a required field
- Invalid picklist values — setting a value that doesn't exist
- Non-writeable fields — trying to set a formula or auto-number field
- Duplicate field names — creating a field that already exists

## Safety Guardrails

Before executing any write operation, check for these dangerous patterns:

| Pattern | Risk | Action |
|---|---|---|
| DELETE without a WHERE clause | Deletes ALL records of that type | BLOCK — always require specific criteria |
| UPDATE without a WHERE clause | Updates ALL records | BLOCK — always require specific criteria |
| Hardcoded Salesforce IDs | Break between orgs/sandboxes | WARN — suggest using queries or Custom Metadata instead |
| Deploying directly to production | Untested changes | WARN — suggest sandbox first |
| Creating a field without FLS | Field invisible to users | REMIND — always ask about field-level security |

## Deployment Ordering

When a task requires creating multiple components, deploy in this order:
```
1. Custom Objects & Fields
2. Permission Sets (with FLS for new fields)
3. Apex Classes & Triggers
4. Flows (as Draft first)
5. Flow Activation
```
See `07-deployment.md` for details.

---

## Salesforce URL Patterns for Links

After creating or updating any metadata, **always include a clickable link** so the user can go directly to it in Salesforce Setup. Use the instance URL from your org context.

Replace `{BASE}` with the Salesforce instance URL from your org context.

**IMPORTANT URL conversion:** The instance URL in org context uses `.my.salesforce.com`, but Lightning pages use `.lightning.force.com`. You MUST convert the URL:
- `https://myorg.my.salesforce.com` → `https://myorg.lightning.force.com`
- `https://myorg--sandbox.sandbox.my.salesforce.com` → `https://myorg--sandbox.sandbox.lightning.force.com`
- Simply replace `.my.salesforce.com` with `.lightning.force.com` in the URL

### Records
- Any record: `{BASE}/lightning/r/{ObjectApiName}/{RecordId}/view`
- Example: `{BASE}/lightning/r/Opportunity/006xx000001abc/view`

### Custom Fields
- Field list on an object: `{BASE}/lightning/setup/ObjectManager/{ObjectApiName}/FieldsAndRelationships/view`
- Specific field (by field ID): `{BASE}/lightning/setup/ObjectManager/{ObjectApiName}/FieldsAndRelationships/{FieldId}/view`
- To get the field ID, query: `SELECT Id, DeveloperName FROM CustomField WHERE TableEnumOrId = '{Object}' AND DeveloperName = '{FieldName}'` via Tooling API

### Validation Rules
- Validation rules list: `{BASE}/lightning/setup/ObjectManager/{ObjectApiName}/ValidationRules/view`
- Specific rule (by ID): `{BASE}/lightning/setup/ObjectManager/{ObjectApiName}/ValidationRules/{ValidationRuleId}/view`

### Flows
- All flows: `{BASE}/lightning/setup/Flows/home`
- Specific flow in Flow Builder (by Flow version ID, starts with 301): `{BASE}/builder_platform_interaction/flowBuilder.app?flowId={FlowVersionId}`
- To get the Flow version ID after creating a flow, query: `SELECT Id FROM Flow WHERE Definition.DeveloperName = '{FlowApiName}' ORDER BY VersionNumber DESC LIMIT 1` via Tooling API

### Apex Classes
- All Apex classes: `{BASE}/lightning/setup/ApexClasses/home`
- Specific class (by ID): `{BASE}/lightning/setup/ApexClasses/page?address=/{ApexClassId}`

### Apex Triggers
- All triggers: `{BASE}/lightning/setup/ApexTriggers/home`
- Specific trigger (by ID): `{BASE}/lightning/setup/ApexTriggers/page?address=/{TriggerId}`

### Permission Sets
- All permission sets: `{BASE}/lightning/setup/PermSets/home`
- Specific permission set (by ID): `{BASE}/lightning/setup/PermSets/page?address=%2F{PermSetId}`
- To get the permission set ID, query: `SELECT Id FROM PermissionSet WHERE Name = '{DeveloperName}'` via standard SOQL

### Profiles
- All profiles: `{BASE}/lightning/setup/EnhancedProfiles/home`

### Page Layouts
- Layouts for an object: `{BASE}/lightning/setup/ObjectManager/{ObjectApiName}/PageLayouts/view`

### Reports
- All reports: `{BASE}/lightning/o/Report/home`
- Specific report (by ID): `{BASE}/lightning/r/Report/{ReportId}/view`

### Dashboards
- All dashboards: `{BASE}/lightning/o/Dashboard/home`
- Specific dashboard (by ID): `{BASE}/lightning/r/Dashboard/{DashboardId}/view`

### Users
- All users: `{BASE}/lightning/setup/ManageUsers/home`
- Specific user (by ID): `{BASE}/lightning/setup/ManageUsers/page?address=/{UserId}`

### Custom Objects
- Object manager: `{BASE}/lightning/setup/ObjectManager/{ObjectApiName}/Details/view`

### Lightning Web Components
- All LWC: `{BASE}/lightning/setup/LightningComponentBundles/home`

### Email Templates
- All templates: `{BASE}/lightning/setup/CommunicationTemplatesEmail/home`

### Important notes:
- Many Salesforce IDs are returned by the tools after create/update — use them to build the URL
- If you don't have the ID, query for it using the Tooling API or SOQL after creating
- **Just output the full URL as plain text** — Slack and Teams will auto-link it. Do NOT wrap it in angle brackets or markdown link syntax. Just paste the URL directly, e.g.:
  `https://myorg.my.salesforce.com/lightning/r/Opportunity/006xx000001abc/view`
