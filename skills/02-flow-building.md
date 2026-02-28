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

### List all Flows
```sql
SELECT DeveloperName, ActiveVersionId, LatestVersionId, Description
FROM FlowDefinition
ORDER BY DeveloperName
LIMIT 200
```

### Check Flow status
A Flow is **active** when `ActiveVersionId` is not null. It's on the **latest version** when `ActiveVersionId = LatestVersionId`.

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
