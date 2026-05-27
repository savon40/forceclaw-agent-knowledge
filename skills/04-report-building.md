# Report Building

## Current capabilities

- **Create reports** via the `create_report` tool (Metadata API)
- **Edit existing reports** via the `update_report` tool (Metadata API — reads existing metadata, merges your changes, writes back)
- **Move reports** between folders via the `move_report` tool
- **Create dashboards** via the `create_dashboard` tool
- **Create custom report types** via the `create_custom_report_type` tool (Metadata API) — required when the user wants a report that joins objects no standard report type covers
- **Enable reporting on a custom object** via the `enable_object_reporting` tool (sets "Allow Reports") — `create_report` also calls this automatically when an object has reporting turned off
- **Run a saved report** via the `run_report` tool — returns grand totals, per-group breakdowns, or detail rows (read-only; works on any org)
- Answer questions about existing reports (suggest SOQL alternatives)
- Help users understand report types and filters
- Generate SOQL queries that answer reporting questions directly

## Choosing the right report type

Every report runs on a **report type**. Decide which one applies before calling `create_report`:

| What the user wants | `report_type` to pass | Notes |
|---|---|---|
| A single **standard** object — Accounts, Contacts, Opportunities, Cases, Leads, etc. | The built-in standard report type: `AccountList`, `ContactList`, `OpportunityList`, `CaseList`, `LeadList`, … | These always exist. |
| A single **custom** object (`Foo__c`) **with reporting enabled** | The object's API name — `report_type: "Foo__c"`. The tool resolves it to the object's auto-generated report type. | Requires reporting enabled on the object (see pre-flight check 1). |
| **Multiple objects** / a cross-object join no standard type covers — e.g. Contact + SurveyInvitation + SurveyResponse, Account + custom children | A **Custom Report Type** you build first — pass its `developer_name`. | See "Custom Report Types — when and how" below. |

If more than one object is involved and you're unsure a standard report type exists for that combination, **build a CRT** — don't guess at a standard report-type name.

## Before you build: two pre-flight checks

`create_report` enforces these for single-object custom-object reports and returns a clear, **non-retryable** error when either fails. Understand them so you take the right next step instead of retrying the call.

### 1. Is reporting enabled on the object?

A custom object only has a report type when **"Allow Reports" is enabled** on it. If it isn't, Salesforce exposes no report type and the report cannot be built — the tool returns *"this custom object does not have reporting enabled"*.

**What to do — this is mostly handled for you now:**
- `create_report` detects a reporting-disabled custom object and **enables reporting automatically** (via `enable_object_reporting`) before building, so the report just works. You usually don't need to do anything.
- To make an object reportable on its own — e.g. the user asks "let me report on this object" — call **`enable_object_reporting`** directly. It sets "Allow Reports" via the Metadata API and is a no-op if reporting is already on.
- **Creating the object in this same task?** `create_custom_object` enables reports by default (`allow_reports` defaults to `true`) — leave it on for objects users will report on.
- Only if auto-enable **fails** (e.g. a permissions issue) does `create_report` stop and ask the user to enable "Allow Reports" manually (*Setup → Object Manager → `<Object>` → Edit → check "Allow Reports" → Save*). In that case, **do NOT retry** until it's on, and never invent a report-type name to work around it.

### 2. Does the running user have access to the fields?

A report silently hides fields the running user can't see, so `create_report` checks **field-level read access** for every requested column first. If the user lacks FLS read on a field — or a named field doesn't exist — the tool names exactly which ones.

**What to do:** fix the column list. Drop the fields the user can't see, or ask an admin to grant FLS read where appropriate; correct any API names flagged as missing. **Do NOT retry with the same columns** — it fails the same way.

> ForceClaw runs as the requesting user (per-user OAuth). "The user can't access this field" means the actual person who asked — not the bot or an admin.

## Column field tokens — they differ by report type

The token you put in each `metadata.columns[].field` depends on the report type. Getting this wrong fails the deploy with "Invalid field name" or "no CustomField named … found":

- **Standard object report types** (`AccountList`, `OpportunityList`, …): dotted standard names — `ACCOUNT.NAME`, `Account.Industry`, and `Account.My_Field__c` for custom fields.
- **Single custom-object report** (you pass `Foo__c`; the tool resolves it to `CustomEntity$Foo__c`): the record name column is **`CUST_NAME`**, and custom fields use **dot notation** — `Foo__c.My_Field__c`. Do **not** use the `$` form here.
- **Custom Report Type** (multi-object): fields use the **`$`** form — `Object$Field`, e.g. `Opportunity$Monthly_Fee__c`.

The running user must have **field-level read access** to every column field — a report hides fields the viewer can't see, and an unreadable custom field won't even deploy onto the report. `create_report` pre-checks this and tells you which fields are blocked.

## Custom Report Types — when and how

Every report runs on a Report Type. Salesforce ships standard report types for single-object cases (`ContactList`, `AccountList`, `OpportunityList`, etc.) and a handful of pre-built joins (`AccountsWithContacts`, `AccountsWithOpportunities`). Custom objects with reports enabled get an auto-generated single-object report type using the object's plural label.

**When the user describes a multi-object report that no standard or auto-generated report type covers — e.g. "Contact + SurveyInvitation + SurveyResponse", "Account + custom-object children + grandchildren" — you MUST build a Custom Report Type (CRT) first.** Then build the report on top of that CRT.

### Workflow

1. `describe_object` the base object (e.g. Contact) — note its child relationship names from the child relationships list. The relationship name (e.g. `SurveyInvitations`) is what the CRT needs, **not** the child object's API name (e.g. `SurveyInvitation`).
2. If a grandchild is involved, `describe_object` the child (e.g. SurveyInvitation) and find that relationship name too (e.g. `Responses`).
3. Call `create_custom_report_type` with the base object, child relationship name, and optional grandchild relationship name. The tool builds the join structure and deploys via Metadata API.
4. Call `create_report` with `report_type` set to the CRT's `developer_name`.

### Common false beliefs to avoid

- **"CRTs are Setup-UI-only and can't be deployed via Metadata API."** False. The metadata type is `ReportType` (sometimes called `CustomReportType`); the `create_custom_report_type` tool deploys it. If you find yourself telling the user a CRT requires manual Setup work, you are about to hallucinate — call `create_custom_report_type` instead.
- **"I'll query existing CRTs with `SELECT ... FROM ReportType`."** Wrong API. `ReportType` is not an SObject and cannot be queried with standard SOQL. There is no clean Tooling API equivalent either. Don't bother checking first — call `create_custom_report_type` directly. If a CRT with that developer_name already exists, the tool returns a duplicate-name response and the report build can proceed.
- **"`CustomObject.Label` will tell me what's there."** The Tooling API `CustomObject` entity uses `MasterLabel`, not `Label`. But again, you don't need to query — just call the create tool.

## Editing an existing report — use `update_report`, NOT `create_report`

**This is critical. When the user says "edit this report", "filter this report", "add a column to the report", "change the grouping", "rename the report", or any other modify-in-place request, you MUST use `update_report`.** Do NOT call `create_report` with a new name — that produces a duplicate report and leaves the original unchanged, which is a product failure.

### How `update_report` works

The tool reads the current report metadata from Salesforce, **shallow-merges** your `metadata` patch onto it, and writes it back. Any top-level key you include in `metadata` REPLACES the corresponding key on the existing report. Keys you omit are preserved. This means:

- **Changing the date filter**: pass `metadata: { timeFrameFilter: { ... } }` — the existing columns/filters/groupings/etc. are untouched.
- **Replacing all columns**: pass `metadata: { columns: [...] }` with the full new array.
- **Adding one column to the existing list**: you must pass the FULL new columns array (existing entries + the new one). Shallow merge replaces arrays wholesale — it does not append.
- **Replacing all filters**: pass `metadata: { filters: [...] }` with the full new array.
- **Renaming**: pass `new_label: "New Display Label"` (not `metadata.name`).
- **Changing the description**: pass `description: "..."`.

### Required arguments

- `report_name` — the developer name (API name) of the existing report. Find it with `SELECT Id, Name, DeveloperName, FolderName FROM Report WHERE DeveloperName = '...'`.
- `folder_name` — the developer name of the folder the report lives in. Defaults to `unfiled$public` (My Personal Custom Reports). Use the `FolderName` field from the SOQL query above.
- `metadata` — partial Report metadata object with the fields you want to change.

### Example: adding a date filter to an existing report

User: *"filter this report to only show accounts created within the last year"*

```
update_report({
  report_name: "All_Accounts_with_Industry_Revenue",
  folder_name: "unfiled$public",
  metadata: {
    timeFrameFilter: {
      interval: "INTERVAL_CUSTOM",
      dateColumn: "CREATED_DATE",
      startDate: "2025-04-11",
      endDate: "2026-04-11"
    }
  }
})
```

### Example: renaming a report

```
update_report({
  report_name: "Q1_Pipeline",
  new_label: "Q1 Pipeline Review"
})
```

### Example: adding a column

The existing report has `[ACCOUNT.NAME, INDUSTRY, SALES]`. User asks to add Phone.
You must pass the FULL new columns list, not just the one to add:

```
update_report({
  report_name: "All_Accounts_with_Industry_Revenue",
  metadata: {
    columns: [
      { field: "ACCOUNT.NAME" },
      { field: "INDUSTRY" },
      { field: "SALES" },
      { field: "ACCOUNT.PHONE" }
    ]
  }
})
```

If you don't know the existing columns, query the report first or call `update_report` once just to read the current state — the tool returns a summary of the post-merge metadata so you can see what's there.

## Report metadata rules — avoid these failure modes

### 1. Report label max length is 40 characters

Salesforce caps the `name` field (the display label) at **40 characters**. Both `create_report` and `update_report` will reject longer values client-side with a clear error, but you should count before calling the tool.

- `"Accounts Created Last Year - Industry & Revenue"` → **47 chars, rejected**
- `"Accounts Created Last Year"` → 26 chars, OK
- `"Q1 2026 Pipeline Review"` → 23 chars, OK

If the user asks for a report with a long descriptive label, shorten it and mention the 40-char limit.

The **developer name** (`report_name`) is also capped at 40 characters.

### 2. `timeFrameFilter.interval` — default to `INTERVAL_CUSTOM`; relative enums are a trap

`UserDateInterval` has a fixed, non-obvious set of values, and many plausible-looking names **do not exist** and fail the deploy with `'INTERVAL_X' is not a valid value for the enum 'UserDateInterval'`. Verified-INVALID (do **not** use): `INTERVAL_THISYEAR`, `INTERVAL_LASTYEAR`, `INTERVAL_THISMONTH`, `INTERVAL_THISQUARTER`, `INTERVAL_LAST30`, `INTERVAL_ROLLING12`.

**Default to `INTERVAL_CUSTOM` with explicit dates you compute yourself.** It is verified to work, expresses exactly the user's intent, and avoids the enum guessing game:

```json
{
  "timeFrameFilter": {
    "interval": "INTERVAL_CUSTOM",
    "dateColumn": "CLOSE_DATE",
    "startDate": "2025-01-01",
    "endDate": "2025-12-31"
  }
}
```

For "this year," "last 30 days," "last quarter," etc. — compute `startDate`/`endDate` and use `INTERVAL_CUSTOM`. `dateColumn` is the report column token of the date field (e.g. `CLOSE_DATE`, `CREATED_DATE`).

**Verified relative intervals** (the only ones safe to use by name — anything else → `INTERVAL_CUSTOM`): `INTERVAL_CUSTOM`, `INTERVAL_CURRENT` (current period), `INTERVAL_CURFY` (current fiscal year), `INTERVAL_PREVFY` (previous fiscal year).

### 3. Column field names use report API-name format

Report columns use UPPERCASE names with dot notation, not the normal SOQL field names:

- `ACCOUNT.NAME` — Account Name
- `ACCOUNT.INDUSTRY` — Industry
- `ACCOUNT.PHONE` — Phone
- `SALES` — Annual Revenue (report-type-specific)
- `CREATED_DATE` / `LAST_MODIFIED_DATE` — system dates

These are report-type-dependent. If you're unsure, create a minimal report first and read its columns back via SOQL on the `Report` object, or inspect a similar existing report to see the exact field identifiers.

### 4. Pick a sensible format

`format` must be `"Tabular"`, `"Summary"`, `"Matrix"`, or `"Joined"`. `Tabular` supports columns + filters only. `Summary` requires `groupingsDown`. `Matrix` requires both `groupingsDown` and `groupingsAcross`.

If you need to add a grouping to a Tabular report, you must also change the format to `Summary` in the same `update_report` call.

### 5. Do not pass `create_report` as a workaround for `update_report`

If `update_report` fails for any reason, **do not** fall back to `create_report` with a different name. That silently creates a duplicate report and leaves the original broken. Instead, report the error to the user, explain what you tried, and ask how to proceed.

## Report types

| Type | What it does | When to use |
|---|---|---|
| **Tabular** | Flat list of records, no grouping | Simple record lists, data exports |
| **Summary** | Groups rows by one or more fields | Most common — group by Stage, Owner, Region, etc. |
| **Matrix** | Groups by rows AND columns (pivot table) | Cross-tabulation — e.g., pipeline by Stage x Quarter |
| **Joined** | Multiple report blocks side by side | Comparing different objects or views together |

## Advanced report features (verified syntax)

All of these deploy via the `metadata` object on `create_report` / `update_report`. Use these exact shapes — they're verified against a live org.

### Filter logic (AND / OR / mixed)
Multiple `criteriaItems` default to AND. For OR or mixed logic, add a `booleanFilter` string referencing the 1-based filter positions:
```json
"filter": {
  "booleanFilter": "1 OR 2",
  "criteriaItems": [
    { "column": "STAGE_NAME", "operator": "equals", "value": "Closed Won" },
    { "column": "STAGE_NAME", "operator": "equals", "value": "Closed Lost" }
  ]
}
```

### Cross-filters (WITH / WITHOUT related records)
For "Accounts **without** Opportunities", "Contacts **with** Cases", etc. `relatedTableJoinColumn` (the foreign-key field on the related object) is **required**:
```json
"crossFilters": [{
  "operation": "without",                 // or "with"
  "primaryTableColumn": "Account",        // the report's primary object
  "relatedTable": "Opportunity",          // the related object
  "relatedTableJoinColumn": "AccountId"   // FK field on the related object
}]
```

### Scope (whose records) — values are report-type-specific
`scope` valid values: `organization` (All), `user` (My), `team` (My Team's). Do **NOT** use `my` or `mine` — they fail. `organization` works on every report type; for "my records" either use `user` or add a filter on the owner column.

### Matrix format and date groupings
`format: "Matrix"` requires **both** `groupingsDown` and `groupingsAcross`; `Summary` requires `groupingsDown`. A date grouping's `dateGranularity` must be one of `None`, `Day`, `Week`, `Month`, `Quarter`, `Year` — **not** "Calendar Quarter" or similar.

### Custom summary formula
```json
"aggregates": [{
  "calculatedFormula": "AMOUNT:SUM",      // use Field:SUM / :AVG — not report column tokens
  "datatype": "currency",                 // currency | number | percent
  "developerName": "FORMULA1",
  "isActive": true,
  "isCrossBlock": false,
  "masterLabel": "Total",
  "scale": 2
}]
```
A formula has **no** `scope` element — including one fails the deploy.

### Not available via report metadata
- **Row limit / Top-N** (the "limit rows" setting on tabular reports) cannot be set through metadata. Use `sortColumn` + `sortOrder` to order, and tell the user to set the row limit in the report builder, or use a filter to narrow the results.

## Running an existing report

To execute a saved report and get its numbers, use `run_report` with the report's developer name (or 15/18-char Id). It returns grand totals, per-group breakdowns (summary/matrix), or detail rows (tabular) — you don't need to rebuild the report's logic in SOQL.

- Use it when the user says "run the X report", "what does X show", "what's the total in X", or "pull the numbers from X".
- The output includes the report's **scope** and **date filter**. Many report types apply a default date filter — e.g. Opportunity reports default to *Close Date = current fiscal quarter*. **If a report returns empty or smaller than expected, check that date filter first** — the report is likely just scoped to the current period, not broken.
- Read-only and safe on production.

## SOQL alternatives for common report needs

Many reporting questions can be answered directly with SOQL, which is faster than building a report. Use these patterns when the user asks "how many", "show me", "what's the total", etc.

### Pipeline summary by stage
```sql
SELECT StageName, COUNT(Id) oppCount, SUM(Amount) totalAmount
FROM Opportunity
WHERE IsClosed = false
GROUP BY StageName
ORDER BY SUM(Amount) DESC
```

### Revenue by quarter
```sql
SELECT CALENDAR_YEAR(CloseDate) yr, CALENDAR_QUARTER(CloseDate) qtr,
       SUM(Amount) totalRevenue, COUNT(Id) dealCount
FROM Opportunity
WHERE StageName = 'Closed Won'
GROUP BY CALENDAR_YEAR(CloseDate), CALENDAR_QUARTER(CloseDate)
ORDER BY CALENDAR_YEAR(CloseDate) DESC, CALENDAR_QUARTER(CloseDate) DESC
```

### Top accounts by opportunity value
```sql
SELECT Account.Name, COUNT(Id) oppCount, SUM(Amount) totalValue
FROM Opportunity
WHERE StageName = 'Closed Won' AND CloseDate = THIS_YEAR
GROUP BY Account.Name
HAVING SUM(Amount) > 0
ORDER BY SUM(Amount) DESC
LIMIT 20
```

### Activity by owner
```sql
SELECT Owner.Name, COUNT(Id) taskCount
FROM Task
WHERE CreatedDate = THIS_MONTH AND Status = 'Completed'
GROUP BY Owner.Name
ORDER BY COUNT(Id) DESC
```

### Case volume by status and priority
```sql
SELECT Status, Priority, COUNT(Id) caseCount
FROM Case
WHERE CreatedDate = LAST_N_DAYS:30
GROUP BY Status, Priority
ORDER BY COUNT(Id) DESC
```

### Lead conversion rates
```sql
SELECT LeadSource, COUNT(Id) totalLeads,
       SUM(CASE WHEN IsConverted = true THEN 1 ELSE 0 END) converted
FROM Lead
WHERE CreatedDate = THIS_YEAR
GROUP BY LeadSource
ORDER BY COUNT(Id) DESC
```
Note: The `SUM(CASE...)` pattern doesn't work in SOQL. Instead, run two queries:
```sql
-- Total leads by source
SELECT LeadSource, COUNT(Id) FROM Lead WHERE CreatedDate = THIS_YEAR GROUP BY LeadSource

-- Converted leads by source
SELECT LeadSource, COUNT(Id) FROM Lead WHERE CreatedDate = THIS_YEAR AND IsConverted = true GROUP BY LeadSource
```

### Duplicate detection
```sql
SELECT Email, COUNT(Id) dupeCount
FROM Contact
WHERE Email != null
GROUP BY Email
HAVING COUNT(Id) > 1
ORDER BY COUNT(Id) DESC
LIMIT 50
```

### Records created over time (trend)
```sql
SELECT CALENDAR_MONTH(CreatedDate) month, CALENDAR_YEAR(CreatedDate) year, COUNT(Id)
FROM Opportunity
WHERE CreatedDate = THIS_YEAR
GROUP BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate)
ORDER BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate)
```

## Date filters for reports

When users ask for time-based reports, use Salesforce date literals:

| Period | Literal | Example use |
|---|---|---|
| Today | `TODAY` | Tasks due today |
| This week | `THIS_WEEK` | Activities created this week |
| This month | `THIS_MONTH` | Opportunities closing this month |
| This quarter | `THIS_QUARTER` | Pipeline for current quarter |
| This year | `THIS_YEAR` | YTD revenue |
| Last 30 days | `LAST_N_DAYS:30` | Recent cases |
| Last 90 days | `LAST_N_DAYS:90` | Quarterly activity |
| Last quarter | `LAST_QUARTER` | QoQ comparison |
| Next 30 days | `NEXT_N_DAYS:30` | Upcoming renewals |

## Tips for report-related questions

1. **Try SOQL first** — for simple questions ("how many", "total by", "top 10"), a SOQL query is faster and more direct than building a report
2. **Use aggregate functions** — `COUNT()`, `SUM()`, `AVG()`, `MIN()`, `MAX()` with `GROUP BY` cover most summary needs
3. **Date functions for trending** — `CALENDAR_YEAR()`, `CALENDAR_QUARTER()`, `CALENDAR_MONTH()`, `DAY_IN_MONTH()` for time-based groupings
4. **Combine with diagrams** — when the user wants a visual, run the SOQL query and then generate a Mermaid chart from the results
5. **Respect governor limits** — aggregate queries are limited to 2,000 grouped rows. Add a `LIMIT` for large datasets
