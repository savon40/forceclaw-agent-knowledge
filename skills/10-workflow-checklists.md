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
- **Lookup/Master-Detail**: which object does it relate to? What is the relationship name?
- **Formula**: what is the formula? What return type?
- **LongTextArea/RichTextArea**: visible lines, length

### 3. Field-Level Security (ALWAYS ask)
After creating the field, ask:
> "Which profiles should have access to this field? I can grant it to **All Profiles** or specific ones. Note: new fields are only visible to System Administrator by default."

Options to offer:
- **All Profiles** — visible and editable to everyone
- **Specific profiles** — ask which ones
- **Read-only for some** — visible but not editable

Use `set_field_level_security` to apply.

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

## Creating a Validation Rule

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
- Specific permission set (by ID): `{BASE}/lightning/setup/PermSets/page?address=/{PermSetId}`

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
