# Report Building

## Current capabilities

- **Create reports** via the `create_report` tool (Metadata API)
- **Edit existing reports** via the `update_report` tool (Metadata API — reads existing metadata, merges your changes, writes back)
- **Move reports** between folders via the `move_report` tool
- **Create dashboards** via the `create_dashboard` tool
- Answer questions about existing reports (suggest SOQL alternatives)
- Help users understand report types and filters
- Generate SOQL queries that answer reporting questions directly

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

### 2. `timeFrameFilter.interval` must be a valid `UserDateInterval` enum value

Salesforce's `UserDateInterval` enum has a fixed set of values. **Do not invent new ones.** Common mistakes that DO NOT exist: `INTERVAL_LASTYEAR`, `INTERVAL_LAST12`, `INTERVAL_LAST365`, `INTERVAL_ROLLING12`.

**Valid values:**

| Value | Meaning |
|---|---|
| `INTERVAL_CUSTOM` | Custom date range — requires `startDate` and `endDate` in YYYY-MM-DD format |
| `INTERVAL_YESTERDAY` | Yesterday |
| `INTERVAL_TODAY` | Today |
| `INTERVAL_CURRENT` / `INTERVAL_CURRENTNEXT1` / `INTERVAL_CURRENTPREV1` | Current period |
| `INTERVAL_THISWEEK` / `INTERVAL_LASTWEEK` / `INTERVAL_NEXTWEEK` | Weekly |
| `INTERVAL_THISMONTH` / `INTERVAL_LASTMONTH` / `INTERVAL_NEXTMONTH` / `INTERVAL_CURNEXTMONTH` / `INTERVAL_CURPREVMONTH` | Monthly |
| `INTERVAL_THISQUARTER` / `INTERVAL_LASTQUARTER` / `INTERVAL_NEXTQUARTER` / `INTERVAL_CURNEXTQUARTER` / `INTERVAL_CURPREVQUARTER` | Calendar quarter |
| `INTERVAL_THISYEAR` / `INTERVAL_LASTYEAR_AGO` / `INTERVAL_NEXTYEAR` | Calendar year (note: for "last year" prefer `INTERVAL_CUSTOM`) |
| `INTERVAL_THISFISCALQUARTER` / `INTERVAL_LASTFISCALQUARTER` / `INTERVAL_NEXTFISCALQUARTER` / `INTERVAL_CURNEXTFQ` / `INTERVAL_CURPREVFQ` | Fiscal quarter |
| `INTERVAL_THISFISCALYEAR` / `INTERVAL_LASTFISCALYEAR` / `INTERVAL_NEXTFISCALYEAR` | Fiscal year |
| `INTERVAL_LAST7` / `INTERVAL_LAST30` / `INTERVAL_LAST60` / `INTERVAL_LAST90` / `INTERVAL_LAST120` | Last N days (rolling) |
| `INTERVAL_NEXT7` / `INTERVAL_NEXT30` / `INTERVAL_NEXT60` / `INTERVAL_NEXT90` / `INTERVAL_NEXT120` | Next N days (rolling) |
| `INTERVAL_WEEKTODATE` / `INTERVAL_MONTHTODATE` / `INTERVAL_QUARTERTODATE` / `INTERVAL_YEARTODATE` / `INTERVAL_FISCALQUARTERTODATE` / `INTERVAL_FISCALYEARTODATE` | Period-to-date |

**When in doubt, use `INTERVAL_CUSTOM` with explicit dates.** It always works and expresses exactly what the user asked for:

```json
{
  "timeFrameFilter": {
    "interval": "INTERVAL_CUSTOM",
    "dateColumn": "CREATED_DATE",
    "startDate": "2025-04-11",
    "endDate": "2026-04-11"
  }
}
```

For "within the last year," compute `endDate = today` and `startDate = today minus 365 days` and pass them directly. Do not guess at rolling enum values.

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
