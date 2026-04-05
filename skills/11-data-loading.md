# CSV Data Loading (Bulk API 2.0)

You can load data into Salesforce from CSV files that the user attaches in Slack. This skill covers the workflow: parse → map → plan → confirm → load → report results.

## When to use this skill

When the user attaches a `.csv` file and asks to:
- Load / import / upload / push data
- Insert new records in bulk
- Update existing records in bulk
- Upsert (match + update existing, insert new) based on an external ID
- Delete records by Id

## Tools you have

| Tool | Purpose |
|---|---|
| `parse_csv_attachment` | Read an attached CSV. Returns filename, column headers, row count, and the first 5 sample rows. ALWAYS call this first. |
| `bulk_load_records` | Execute the load via Bulk API 2.0. Returns success.csv + error.csv to the Slack thread. Requires field_mapping and confirmation from user. |

## The workflow — plan, confirm, load

**Turn 1: read + propose plan (end turn here, wait for confirmation)**
1. Call `parse_csv_attachment` to see what's in the file. Review the columns and sample rows.
2. Call `describe_object` on the target Salesforce object to get the real field API names and types.
3. Build a proposed field mapping. For each CSV column, identify the matching Salesforce field:
   - Exact matches are easy: `Email` → `Email`, `FirstName` → `FirstName`
   - Label-ish matches need judgment: `Phone Number` → `Phone`, `Company` → `Company` on Lead but might be `AccountId` lookup on Contact
   - Ambiguous columns should be CALLED OUT, not guessed. Example: "I see a column called 'Revenue' — should this map to `AnnualRevenue` on Account, or a custom field? What's your intent?"
   - Columns with no obvious match should be flagged as "I'm not sure what to do with `X` — should I skip it, or does it map to a custom field I don't see?"
4. Determine the operation:
   - **insert** — user wants all rows created as new records. No Id column needed.
   - **update** — user wants existing records modified. CSV MUST have an Id column mapped to `Id`.
   - **upsert** — user wants "update if exists by external key, otherwise insert". Requires a field marked as External Id on the target object (or you can use `Id` itself if the CSV has record Ids).
   - **delete** — user wants records deleted by Id. CSV MUST have an Id column mapped to `Id`.
5. Present the full plan to the user:
   - Filename and row count
   - Target object
   - Operation (with external id field if upsert)
   - The proposed field mapping as a readable table
   - Any ambiguities you're flagging for confirmation
   - Ask "Should I go ahead?"
6. **STOP the turn here.** Do NOT call `bulk_load_records` in the same response as the plan.

**Turn 2: load (after user confirms)**
Call `bulk_load_records` with the same filename, object, operation, field_mapping, and (if upsert) external_id_field. The tool will:
- Parse the CSV
- Apply the field mapping
- Submit to Salesforce Bulk API 2.0
- Wait for completion
- Generate and upload `success_<object>_<timestamp>.csv` (loaded rows with assigned Ids) and `error_<object>_<timestamp>.csv` (failed rows with failure reasons) to the Slack thread
- Return a summary: success count, failure count, top error categories

## Operation reference

### insert

Creates new records from every CSV row. No Id column needed.

Required:
- `object_name`
- `operation: "insert"`
- `field_mapping` — every CSV column that should become a field on the new record

Not required:
- `external_id_field`

Example plan:
> *Filename: `leads.csv` (500 rows)*
> *Object: Lead*
> *Operation: INSERT (create 500 new leads)*
> *Mapping:*
> - *First Name → FirstName*
> - *Last Name → LastName*
> - *Email Address → Email*
> - *Company Name → Company*
> - *Phone → Phone*
>
> *Should I go ahead?*

### update

Modifies existing records. CSV must have an Id column.

Required:
- `object_name`
- `operation: "update"`
- `field_mapping` — must include a mapping for the `Id` field
- At least one other field to actually update

### upsert

Matches existing records by the external id field, updates matches, inserts non-matches. Best for sync-style loads where you don't know which records already exist.

Required:
- `object_name`
- `operation: "upsert"`
- `field_mapping`
- `external_id_field` — the name of the field to match on. Must be either `Id` (for matching by Salesforce Id) or a field marked as "External Id" on the target object.

**Important:** not every field can be used as an external id. For example, `Email` on Contact is NOT marked as External Id by default — you'd have to flag it in Setup first, or upsert by `Id` instead. If the user wants to upsert by a field that isn't marked External Id, tell them they need to either (a) mark that field as External Id in Setup first, or (b) query Salesforce to resolve matches client-side and use update/insert separately.

### delete

Deletes records by Id. CSV must have an Id column.

**EXTRA CAREFUL** — deletes are destructive and rarely reversible. Always:
- Confirm the exact row count with the user
- Show the user 5 sample rows that will be deleted
- Require an explicit "yes, delete these N records" from the user, not just "go ahead"

## Field mapping patterns

### Direct field mapping

The simplest case — CSV column name differs slightly from the Salesforce field name:
```json
{
  "First Name": "FirstName",
  "Last Name": "LastName",
  "Email Address": "Email",
  "Mobile Phone": "MobilePhone"
}
```

### Skipping columns

Columns not in `field_mapping` are ignored. If the CSV has a "Notes" column you don't want to import, simply leave it out of the mapping.

### Lookup fields

Lookup fields (e.g. `AccountId` on Contact) store a Salesforce record Id, not a name. When the CSV has a lookup like `Company Name` that should resolve to an Account, you have two choices:

1. **Pre-resolve the lookup** (recommended): before the load, query Salesforce to get all matching Account Ids, then transform the CSV to include the AccountId column directly. Describe this approach to the user so they understand what will happen to companies that don't match any Account.

2. **Use External Id upsert on the lookup target**: if the target object's lookup field has an External Id field, you can pass the external value and Salesforce resolves the lookup. This is more advanced — only suggest it if the user explicitly asks.

For the MVP, prefer pre-resolving lookups and flagging any misses to the user.

### Picklist values

Picklist fields require the value to match an existing picklist entry EXACTLY (case-sensitive for API values, though the UI is usually case-insensitive). If the CSV has values that might not match:
- Run `describe_object` to see the actual picklist values
- Compare against what's in the CSV
- Flag mismatches to the user BEFORE loading — they need to either fix the CSV, add the values to the picklist, or accept that those rows will fail

### Required fields

If the target object has required fields (e.g. `LastName` on Contact, `Company` on Lead), the CSV must have those columns mapped. Check via `describe_object` before the load and warn the user if any required field is missing from the CSV.

## Safety rules

1. **NEVER skip the plan → confirm step.** Even for small files. The user needs to approve the field mapping before you load anything.

2. **ALWAYS run `parse_csv_attachment` first.** Don't guess at what's in the file.

3. **For delete operations, require explicit count confirmation.** Not just "go ahead" — ask the user to acknowledge the exact number of records that will be deleted.

4. **For updates to 100+ records on a production org, recommend a dry_run first.** (Pass `dry_run: true` to `bulk_load_records` to validate without loading.)

5. **Flag ambiguous columns BEFORE the load, not after.** A load that succeeds with wrong mappings is worse than a load that was clarified in advance.

6. **Never load into production without explicit confirmation and manageData permission.** The permission guard handles this at the tool level, but you should also verify the user understands they're loading to production.

7. **Warn about non-writable fields.** Formula fields, auto-number fields, system fields (CreatedDate, CreatedById, LastModifiedDate, etc.) cannot be set via the Bulk API. If the user's field mapping tries to include them, flag it.

## After the load

The `bulk_load_records` tool automatically uploads two result files:
- `success_<object>_<timestamp>.csv` — every row that loaded successfully, with the assigned Salesforce Id
- `error_<object>_<timestamp>.csv` — every row that failed, with the failure reason

Your summary response should:
1. State success count and failure count
2. Highlight the top error categories (which will be in the tool result)
3. Tell the user both files have been uploaded to the Slack thread
4. Offer to help diagnose common errors (e.g. "Looks like 50 rows failed because of missing required fields — want me to look at the error CSV and suggest fixes?")

## Common errors and how to explain them

| Error | Cause | How to explain |
|---|---|---|
| `REQUIRED_FIELD_MISSING` | CSV row lacks a value for a required field | "Row X is missing <field>, which is required on <object>. Either add values to the CSV or remove those rows." |
| `INVALID_FIELD` | Field API name in mapping doesn't exist on the object | "Your mapping references a field that doesn't exist on <object>. Did you mean <similar field>?" |
| `INVALID_CROSS_REFERENCE_KEY` | Lookup field value doesn't match any record | "The AccountId value '<value>' doesn't match any existing Account. Either create the Account first or fix the CSV." |
| `MALFORMED_ID` | Id field has an invalid format (wrong length, wrong prefix) | "The Id '<value>' isn't a valid Salesforce Id format. Salesforce Ids are 15 or 18 chars and start with a 3-char object prefix." |
| `FIELD_CUSTOM_VALIDATION_EXCEPTION` | Validation rule blocked the save | "A validation rule on <object> rejected these rows: <message>. Either fix the data or ask an admin to adjust the rule." |
| `DUPLICATE_VALUE` | Unique constraint violated | "A field with unique/external id constraint has duplicate values. Each row needs a unique value for <field>." |
| `STORAGE_LIMIT_EXCEEDED` | Org data storage is full | "The org has hit its data storage limit. Old records need to be archived or deleted before new ones can be added." |

## Size limits

- Max file size: 50 MB per CSV
- Max rows per load: 100,000 (the tool will reject larger files and ask the user to split)
- For very large loads, consider splitting the CSV and running multiple sequential `bulk_load_records` calls — each one returns its own success.csv and error.csv

## What you do NOT need to worry about

- **Batching**: Bulk API 2.0 handles internal chunking automatically. You just pass the records and it figures out the optimal batch size.
- **Polling**: `bulk_load_records` waits for completion internally (up to 10 minutes). No need to manually poll.
- **Progress updates**: the tool prints internal progress to the server logs, and the agent loop's progress messages ("Still working...") fire automatically while the load runs.
