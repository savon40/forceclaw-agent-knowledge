# Git Workflow

## Current capabilities

- Commit Salesforce metadata changes to connected Git repositories
- Track changes as an audit trail of what the bot did and when

## Branch strategy

### Recommended branch naming
| Branch type | Pattern | Example |
|---|---|---|
| Feature | `feature/[ticket-or-description]` | `feature/add-invoice-custom-object` |
| Bug fix | `fix/[ticket-or-description]` | `fix/opportunity-validation-rule` |
| Hotfix | `hotfix/[description]` | `hotfix/apex-null-pointer` |
| Release | `release/[version]` | `release/v1.2.0` |

### Standard flow
```
main (production)
  └── develop (integration)
       ├── feature/add-invoice-object
       ├── feature/update-lead-flow
       └── fix/case-trigger-bug
```

## Salesforce DX project structure

### sfdx-project.json
The project manifest that defines package directories and API version:
```json
{
  "packageDirectories": [
    {
      "path": "force-app",
      "default": true
    }
  ],
  "namespace": "",
  "sfdcLoginUrl": "https://login.salesforce.com",
  "sourceApiVersion": "62.0"
}
```

### Standard directory layout
```
force-app/
  main/
    default/
      classes/          ← Apex classes + test classes (.cls + .cls-meta.xml)
      triggers/         ← Apex triggers (.trigger + .trigger-meta.xml)
      flows/            ← Flow definitions (.flow-meta.xml)
      objects/          ← Custom objects and fields
        Account/
          fields/       ← Custom fields on Account
        Invoice__c/
          fields/       ← Custom fields on Invoice__c
      permissionsets/   ← Permission set definitions (.permissionset-meta.xml)
      layouts/          ← Page layouts
      profiles/         ← Profile metadata (minimize — use permission sets instead)
      lwc/              ← Lightning Web Components
      aura/             ← Aura components (legacy)
      staticresources/  ← Static resources
      customMetadata/   ← Custom Metadata Type records
```

### .forceignore patterns
Exclude noisy or irrelevant metadata from version control:
```
# Common .forceignore entries
**/profiles/Admin.profile-meta.xml
**/profiles/Standard*.profile-meta.xml
**/jsconfig.json
**/__tests__/**
**/settings/
```

## Source tracking

### Key concepts
- **Source tracking** monitors differences between your local project and a connected org
- **Retrieve** pulls metadata from org to local: `sf project retrieve start`
- **Deploy** pushes metadata from local to org: `sf project deploy start`
- **Conflict detection**: if both local and org changed the same component, you'll get a conflict

### Common commands
```bash
# Retrieve all changed metadata from org
sf project retrieve start --target-org my-sandbox

# Deploy all local changes to org
sf project deploy start --target-org my-sandbox

# Deploy specific components
sf project deploy start --source-dir force-app/main/default/classes/AccountService.cls

# Deploy with manifest (package.xml)
sf project deploy start --manifest manifest/package.xml

# Validate only (dry run — doesn't actually deploy)
sf project deploy start --target-org my-sandbox --dry-run

# Check deployment status
sf project deploy report
```

## Commit best practices

1. **Commit after each logical change** — one feature/fix per commit, not a dump of 50 files
2. **Write descriptive commit messages** — explain WHAT changed and WHY
3. **Include all dependent metadata** — if you add a custom field, include the object definition too
4. **Review before committing** — check `git diff` to make sure no secrets, hardcoded IDs, or test artifacts are included
5. **Never commit** `.env` files, credentials, Salesforce session tokens, or hardcoded org-specific IDs
