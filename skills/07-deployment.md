# Deployment

## Current capabilities

- Deploy individual metadata components (Flows, Apex, Custom Objects/Fields, Permission Sets, Validation Rules)
- Activate/deactivate Flows
- Create and manage Change Sets

## Deployment ordering — CRITICAL

When deploying multiple components, they MUST be deployed in this order. Deploying out of order causes `INVALID_CROSS_REFERENCE_KEY`, `FIELD_NOT_FOUND`, and similar errors.

### Standard deployment order
```
1. Custom Objects & Fields     ← foundation, referenced by everything else
2. Permission Sets             ← require objects/fields to exist
3. Apex Classes & Triggers     ← may reference objects/fields
4. Flows (as Draft)            ← reference objects, fields, and may call Apex
5. Flow Activation             ← activate after verifying everything deployed
6. Test Data / Validation      ← confirm it all works
```

### Why this order matters
| Component | Depends on |
|---|---|
| Custom Fields | Custom Objects must exist first |
| Permission Sets | Objects and fields must exist for FLS grants |
| Apex Classes | Custom objects/fields referenced in SOQL/DML must exist |
| Flows | Objects, fields, Apex classes (if using InvocableMethod) must exist |
| Subflows | Child subflows must be deployed AND activated before parent flows |
| Validation Rules | Referenced fields must exist |

## Pre-deployment checklist

### Before any deployment
- [ ] **Run all tests** — verify 75% minimum code coverage (90%+ recommended)
- [ ] **Check for hardcoded IDs** — these break between orgs/sandboxes
- [ ] **Verify code coverage** — check with `SELECT ApexClass.Name, NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverage`
- [ ] **Validate against target org** — use validation-only deployment to catch errors before committing
- [ ] **Check entry conditions on Flows** — ensure record-triggered flows have proper filters
- [ ] **Verify FLS on new fields** — new fields are hidden by default; confirm permission sets are included in the deployment

### Deployment validation
Always do a dry-run first:
- Deploy as **validation only** (check-only deployment) to verify everything compiles and tests pass in the target org
- Review the validation results for errors
- Only proceed with the actual deployment after validation passes

## Common deployment errors and fixes

| Error | Cause | Fix |
|---|---|---|
| `FIELD_CUSTOM_VALIDATION_EXCEPTION` | Validation rule blocking the test data | Create test data that satisfies all validation rules, or temporarily deactivate the rule |
| `INVALID_CROSS_REFERENCE_KEY` | Reference to a component that doesn't exist in the target org | Check deployment order — deploy dependencies first |
| `CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY` | Trigger/Flow error during test execution | Check debug logs for the specific trigger/flow that failed |
| `Test coverage < 75%` | Insufficient Apex test coverage | Write more tests or fix failing tests |
| `Field does not exist` | Apex references a field not in the target org | Include the custom field in the deployment |
| `Invalid type` | Apex references a class that doesn't exist yet | Deploy the referenced class first |
| `Insufficient access` | Missing permissions for the deploying user | Verify the user has Modify All Data or deploy permissions |
| `Subflow not found` | Parent flow references a subflow that isn't deployed/active | Deploy and activate subflows before parent flows |

## Deployment methods

### Metadata API (what the bot uses)
- Deploys individual components via API calls
- Best for: single-component changes, automated deployments
- Used by: `create_flow`, `create_custom_field`, `create_permission_set`, etc.

### Change Sets
- Salesforce-native deployment between connected orgs (sandbox → production)
- Best for: admin-friendly deployments, organizations without CI/CD
- Limitation: one-way, can't delete components, no version control

### Salesforce CLI (`sf project deploy start`)
- Command-line deployment from local source
- Best for: developer workflows, CI/CD pipelines
- Supports: source format, manifest-based deploys, selective deploys

### Unlocked/Managed Packages
- Best for: distributing to multiple orgs, ISV products
- Supports: versioning, dependency management, upgrade paths

## Rollback strategies

### Flows
- Flows are versioned — rollback by activating the previous version
- Use `get_flow_definition` to list versions, then activate the prior version

### Apex
- No built-in rollback — must redeploy the previous version
- Best practice: keep previous versions in source control

### Custom Fields/Objects
- Cannot be "undeployed" — must manually delete or deactivate
- Deleting a field moves it to the Deleted Fields section (recoverable for 15 days)
- Before deleting: check for references in Flows, Apex, Validation Rules, Reports

### General rollback approach
1. Identify what changed (compare metadata between orgs)
2. Redeploy the previous version of changed components
3. If a Flow is causing issues, deactivate it immediately (fastest fix)
4. If Apex is causing issues, deploy a hotfix or the previous version

## Deployment best practices

1. **Deploy to sandbox first, then production** — never deploy untested changes directly to production
2. **Use validation-only deployments** to verify before committing
3. **Deploy in small batches** — easier to identify and fix issues
4. **Include test data setup in your test classes** — don't rely on existing data in the target org
5. **Document what's being deployed** — maintain a deployment log for audit trail
6. **Time production deployments carefully** — avoid peak usage hours
7. **Have a rollback plan** before every production deployment
