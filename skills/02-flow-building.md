# Flow Building

<!-- TODO: Expand when the bot gains Flow creation capabilities -->

## Current capabilities

- Read and describe existing Flows via the Tooling API
- List all Flows in the org
- Check if a Flow is active (compare `ActiveVersionId` to `LatestVersionId`)
- Answer questions about what a Flow does based on its metadata

## Flow types

- **Record-Triggered Flow** — runs when a record is created/updated/deleted
- **Screen Flow** — interactive, launched by users via buttons/links/pages
- **Autolaunched Flow** — runs in the background, invoked by other automation
- **Scheduled Flow** — runs on a schedule
- **Platform Event-Triggered Flow** — runs when a platform event is published

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

**Important:** The `Flow` sObject is NOT queryable via standard SOQL — only via Tooling API.

## Future capabilities

<!-- TODO: Add content for these sections when Flow write capabilities are added -->

### Building Flows
- Flow element types and when to use each
- Decision element patterns
- Loop and collection patterns
- Error handling in Flows

### Flow best practices
- Bulkification
- Entry conditions to avoid unnecessary runs
- Before-save vs after-save triggers
- When to use a Flow vs Apex
