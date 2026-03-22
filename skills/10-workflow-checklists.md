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

## General Rules for All Write Operations

1. **Always describe what you'll do** before doing it
2. **Always ask "Should I go ahead?"** and wait for confirmation
3. **After completing**, summarize what was done and **include a direct link** to the created/updated component in Salesforce (see URL patterns below)
4. **If something fails**, show the error, explain what went wrong, and offer to fix it
5. **Think about side effects** — will this field be referenced by flows, validation rules, or Apex? Mention if relevant.
6. **Think about what the admin would want** — FLS, layouts, history tracking, etc. Don't just create the bare minimum.

---

## Salesforce URL Patterns for Links

After creating or updating any metadata, **always include a clickable link** so the user can go directly to it in Salesforce Setup. Use the instance URL from your org context.

Replace `{BASE}` with the Salesforce instance URL (e.g., `https://myorg.my.salesforce.com`).

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
- Specific flow (by Flow Definition ID or version ID): `{BASE}/builder_platform_interaction/flowBuilder.app?flowId={FlowId}`

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
- Always present links in Slack/Teams markdown format: `<{URL}|View in Salesforce>`
