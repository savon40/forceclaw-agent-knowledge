# Email Templates and Email Alerts

## When this applies

This skill applies whenever the user asks about Salesforce **EmailTemplate** records or **Email Alerts** (`WorkflowAlert` metadata) — finding them, identifying which alert fires which template, locating the alert that owns a given subject line, etc. It applies in both production (read-only) and sandbox.

## TL;DR — use the dedicated tools, not raw queries

| Goal | Tool to call |
|---|---|
| Find templates by subject (exact or partial) | `find_email_templates` |
| Find templates by name | `find_email_templates` (with `name_contains`) |
| Find alerts that use a specific template | `find_email_alerts` |
| Find alerts on a specific object | `find_email_alerts` (with `entity_name`) |
| Answer "what alert sends the email with subject X?" | `find_email_templates` first, then `find_email_alerts` with `template_subject_contains` |

Do NOT try to do these with raw `query_salesforce` or `query_tooling` calls — there are footguns documented below that the tools handle for you.

## The footguns these tools exist to avoid

### EmailTemplate.Subject is NOT SOQL-filterable

Salesforce will reject this query at runtime:

```sql
SELECT Id, DeveloperName FROM EmailTemplate WHERE Subject = 'Some subject'
-- ERROR: field 'Subject' can not be filtered in a query call
```

`Subject` is **selectable** but not **filterable**. You can put it in the SELECT list, you cannot put it in the WHERE clause. There's no LIKE alternative either. The only way to find a template by subject is to fetch all templates and filter in memory — which is exactly what `find_email_templates` does.

If the user gives you a subject line, **always go through `find_email_templates`**. Do not try to be clever with `query_salesforce`.

### WorkflowAlert is Tooling API only — and joins by TemplateId, not TemplateName

`WorkflowAlert` (the API name for Email Alerts) is metadata, not a data sObject. It is **not queryable via standard SOQL** (`query_salesforce` will fail). It is queryable via the Tooling API (`query_tooling`).

When querying it, the field that joins to EmailTemplate is **`TemplateId`** (a 15/18-char Id reference), NOT `TemplateName`. A common mistake:

```sql
-- WRONG — TemplateName does not exist on WorkflowAlert
SELECT DeveloperName FROM WorkflowAlert WHERE TemplateName = 'Some_Template_DevName'

-- CORRECT — resolve the template's Id first, then filter by TemplateId
SELECT DeveloperName, EntityDefinition.QualifiedApiName, TemplateId
FROM WorkflowAlert
WHERE TemplateId = '00X5Y000002bUiAUAU'
```

The full queryable column list on `WorkflowAlert` is: `Id, DeveloperName, FullName, Description, EntityDefinitionId, TemplateId, SenderType, CcEmails, NamespacePrefix, ManageableState, Metadata, CreatedById, CreatedDate, LastModifiedById, LastModifiedDate`.

`find_email_alerts` handles the template-name → template-id resolution and the join back to template Subject for you.

### Don't SELECT or ORDER BY EntityDefinition.QualifiedApiName from WorkflowAlert

`EntityDefinition.QualifiedApiName` is the cross-object relationship to the parent object's API name. On WorkflowAlert it works **only in the WHERE clause**. Putting it in SELECT or ORDER BY can fail with a generic Salesforce internal error on production orgs:

```
An unexpected error occurred. Please include this ErrorId if you contact support: <opaque-id>
```

The error gives you nothing to debug — there's no "field not found" or "permission denied" message. The fix: select `EntityDefinitionId` (the raw FK) instead, then resolve to the parent object's API name with a separate Tooling query:

```sql
-- WRONG — cross-object SELECT/ORDER BY can throw generic SF error
SELECT Id, DeveloperName, EntityDefinition.QualifiedApiName, TemplateId
FROM WorkflowAlert
WHERE EntityDefinition.QualifiedApiName = 'Contact'
ORDER BY EntityDefinition.QualifiedApiName, DeveloperName

-- CORRECT — keep cross-object filter in WHERE, resolve names separately
SELECT Id, DeveloperName, EntityDefinitionId, TemplateId
FROM WorkflowAlert
WHERE EntityDefinition.QualifiedApiName = 'Contact'
ORDER BY DeveloperName

-- Then a follow-up to resolve the IDs:
SELECT Id, QualifiedApiName FROM EntityDefinition WHERE Id IN ('01I...', '01I...')
```

`find_email_alerts` does this split internally, so the dedicated tool is fine. Only worry about this if you're falling back to `query_tooling` directly.

### Template.Name and Template.Subject don't traverse from WorkflowAlert

The `Template` relationship on WorkflowAlert (which points to EmailTemplate) **is not traversable in SELECT** via Tooling API. This shape errors:

```sql
-- WRONG — Template.Name / Template.Subject SELECT will fail
SELECT DeveloperName, Template.Name, Template.Subject FROM WorkflowAlert WHERE ...
```

To get the template's Name and Subject, fetch the alerts first with `TemplateId`, then issue a second query for the templates by Id:

```sql
SELECT Id, Name, Subject FROM EmailTemplate WHERE Id IN ('00X...', '00X...')
```

### EmailTemplate via Tooling API: prefer `Name`, not `DeveloperName`

EmailTemplate is queryable via both standard SOQL (`query_salesforce`) and Tooling (`query_tooling`), but the available field set differs. Via Tooling, `DeveloperName` may not be selectable depending on the org's API version — selecting it can throw "No such column 'DeveloperName' on EmailTemplate". `Name` is reliably available everywhere.

```sql
-- Safer via Tooling — Name + Subject are reliable
SELECT Id, Name, Subject FROM EmailTemplate WHERE Id IN ('00X...', '00X...')

-- Risky via Tooling — may fail on DeveloperName
SELECT Id, DeveloperName, Subject FROM EmailTemplate WHERE Id IN ('00X...', '00X...')
```

If you do need `DeveloperName` and `query_salesforce` is blocked (production with `readData: false`), `find_email_templates` is the right tool — it always works because it uses the appropriate API path.

### Subjects are not unique

Two or more EmailTemplate records can have the same Subject. **Always return all matches** when answering a "which template has subject X" question — picking the first match silently can point the user at the wrong template (and then the wrong downstream alert/flow). `find_email_templates` returns all matches by design.

### Templates can be referenced from many places

Even after you've correctly identified an EmailTemplate, "which automation sends this?" is not just "which Email Alert?". A template can also be referenced from:

- **Flow** Send Email actions (`emailSimple` invocable) — these can reference a template by Id or DeveloperName
- **Apex** code calling `Messaging.SingleEmailMessage.setTemplateId(...)`
- **Approval Processes** (rare)
- **Email-to-Case** auto-response rules

So when no Email Alert uses a given template but the user is sure an email is being sent, the next steps are:
1. Check active flows on the relevant object — query for flows that contain `emailSimple` actions or reference the template Id
2. Check Apex classes/triggers — search the codebase for the template DeveloperName or Id
3. Only then conclude "the template is unused" or "the email comes from somewhere else"

## End-to-end example: "What contact email alert sends the email with subject 'X'?"

```
1. find_email_templates(subject_equals="X")
   → returns 1 or more EmailTemplate rows with Id, DeveloperName, Subject, FolderName

   If 0 matches → tell the user "no template with that subject exists" and stop.
   If 1 match → use its Id in step 2.
   If >1 match → list them all to the user, ask which one (or proceed for each).

2. find_email_alerts(template_id=<id from step 1>, entity_name="Contact")
   → returns the matching WorkflowAlert rows on Contact

   If 0 matches → the template exists but no Contact Email Alert uses it.
   Suggest checking flows / Apex (see "Templates can be referenced from many places").
   If >0 matches → report each alert's DeveloperName and the parent object.
```

You can also collapse step 1 + step 2 into a single call:

```
find_email_alerts(template_subject_contains="X", entity_name="Contact")
```

That's the most common shape of the question and is the cheapest path.

## Permission gating

Both `find_email_templates` and `find_email_alerts` are gated by the **Read metadata** permission. They never read record values from Salesforce — only template definitions and alert metadata. They're available in production read-only mode by default.

## Creating templates and alerts

For *creating* email templates and alerts, see `02-flow-building.md` (`create_email_template`, `create_email_alert`). Those tools require the **Create & modify flows** permission and are sandbox-first.
