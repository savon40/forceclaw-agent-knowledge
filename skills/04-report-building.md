# Report Building

## Current capabilities

- Answer questions about existing reports (suggest SOQL alternatives)
- Help users understand report types and filters
- Generate SOQL queries that answer reporting questions directly

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
