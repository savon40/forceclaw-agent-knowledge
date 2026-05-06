# Deployment

## How ForceClaw deploys (read first)

ForceClaw's job ends at **validation**. The user does the actual production deploy.

The only production-touching tool is `validate_deploy_to_production`, which retrieves metadata from the connected sandbox, runs Metadata API `deploy()` with `checkOnly: true` against production, and returns the validation Deploy ID. The user then Quick Deploys from Salesforce Setup > Deployment Status. ForceClaw never promotes a change to production itself.

This is a load-bearing rule, not a default. Even if the user says "go ahead and deploy it," reply that the bot validates and they Quick Deploy.

## Current capabilities

- **Sandbox edits** — create/update flows, Apex, custom objects/fields, permission sets, validation rules, page layouts, etc. against a connected sandbox via the Metadata, Tooling, and REST APIs
- **Validate-only deploy from sandbox to production** — `validate_deploy_to_production` retrieves the specified metadata from sandbox and runs `checkOnly: true` deploy against production
- **Activate/deactivate Flows**

## Evidence hierarchy — what counts as "it worked"

When reporting an outcome to the user, use the **highest level of evidence actually reached** — never one above. Each level is stronger than the one below it.

| Level | What proves it | What it does NOT prove |
|---|---|---|
| 1. Source review | The generated XML/Apex/JSON parses and looks correct | Nothing about org state |
| 2. Compile pass | Apex compiled in the org (Tooling API save returned success) | Nothing about runtime, FLS, or other components |
| 3. Targeted tests pass | Specified Apex tests ran green with sufficient coverage on the touched classes | Nothing about deployability of the broader package |
| 4. Validate-only deploy pass | Metadata API `deploy()` with `checkOnly: true` returned success against the target org | The change is **not live** — the user still must Quick Deploy |

### Rules of evidence

- ForceClaw's ceiling is level 4. Slack summaries say *"validated successfully — Quick Deploy from Setup > Deployment Status"*. Never *"deployed"*, *"live"*, or *"shipped"*.
- A success that ignored warnings is a **risk state**, not a clean pass. List the warnings in the Slack summary.
- A `checkDeployStatus` poll timeout is **neither** success nor failure. Surface the Deploy ID and ask the user to check Setup > Deployment Status — do not claim either outcome.
- Compile pass on a single Apex class is not validate-only pass on a deploy package. Don't conflate the two.
- Heroku server logs get the full SOAP envelopes, error stacks, and raw XML. The Slack thread gets the human summary. Never leak SOAP/internals into user-facing messages.
- Never claim something "isn't deployed yet" without first checking `git status`. Recent ForceClaw changes are usually already live on Heroku.

## Deployment ordering — CRITICAL

When deploying multiple components, they MUST be in this order. Out-of-order deploys cause `INVALID_CROSS_REFERENCE_KEY`, `FIELD_NOT_FOUND`, and similar errors.

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

## Pre-validation checklist

### Before any production validation
- [ ] **Identify the touched Apex classes** — coverage is gated on touched classes, not org-wide
- [ ] **Ask the user which test classes to run** — never default to `RunLocalTests`. Use `RunSpecifiedTests` with classes that actually cover the change. `validate_deploy_to_production` defaults to `NoTestRun`, which production policy may reject — be ready to retry with tests.
- [ ] **Check for hardcoded IDs** — surface as a warning even if the validation passes (they break between orgs)
- [ ] **Verify FLS on new fields** — new fields are hidden by default; include the relevant permission sets in the package
- [ ] **Keep the package narrow** — only what changed. Broad packages cause unrelated failures and slower validations
- [ ] **For destructive changes** — validate-only first, list what's being removed in the Slack summary, confirm a rollback plan with the user before any Quick Deploy

## Common deployment errors and fixes

| Error / Symptom | Likely Cause | Fix |
|---|---|---|
| `FIELD_CUSTOM_VALIDATION_EXCEPTION` | Validation rule blocks the test data | Create test data that satisfies all validation rules, or temporarily deactivate the rule |
| `INVALID_CROSS_REFERENCE_KEY` | Reference to a component that doesn't exist in the target org | Check deployment order — deploy dependencies first |
| `CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY` | Trigger/Flow error during test execution | Check debug logs for the specific trigger/flow that failed |
| `Test coverage < 75%` | Insufficient Apex coverage on touched classes | Add tests for the modified classes — coverage is gated per touched class, not org-wide |
| `Field does not exist` | Apex references a field not in the target org | Include the custom field in the package |
| `Invalid type` | Apex references a class that doesn't exist yet | Deploy the referenced class first |
| `Insufficient access` | Missing permissions for the integration user | Verify the integration user has Modify All Data and the relevant deploy permissions |
| `Subflow not found` | Parent flow references a subflow that isn't deployed/active | Deploy and activate subflows before parent flows |
| Production rejects `NoTestRun` | Production org policy requires tests even on metadata-only changes | Re-run with `RunSpecifiedTests`. Ask the user which test classes cover the change. |
| Validation succeeded but the change isn't live | Validate-only ≠ deployed. The user hasn't Quick-Deployed yet | Tell the user to Quick Deploy from Setup > Deployment Status using the Deploy ID. ForceClaw never promotes the change itself. |
| Selected tests pass but validation fails on coverage | One or more touched Apex classes are below the per-class coverage threshold | Add branch and negative-path tests for the touched classes; don't rely on overall org coverage |
| `checkDeployStatus` poll timed out | Validation job is still running on the org | Surface the Deploy ID; do not claim success or failure; ask the user to monitor Setup > Deployment Status |
| Validation includes unrelated metadata | Retrieve scope was too broad | Narrow the retrieve manifest to the components actually being modified |
| Destructive change validated "with warnings" | Warnings on a destructive deploy were not surfaced | Treat as a risk state — list the warnings in the Slack summary, do not call it a clean pass |
| Destructive deploy would remove the wrong metadata | Destructive manifest or dependencies were not reviewed narrowly | Use a separate destructive manifest, validate-only first, document the rollback plan with the user before Quick Deploy |
| `UNABLE_TO_LOCK_ROW` during test execution | Parallel tests contending on the same records (often `ContentVersion` or shared setup data) | Narrow the test scope; for stubborn cases mark `@isTest(isParallel=false)` |
| `Too many SOQL queries: 101` in an unrelated test | Test selection is too broad and pulls in legacy classes | Narrow tests to those that actually cover the changed classes; treat the legacy SOQL issue as a separate ticket |

## Deployment method

ForceClaw uses the **Metadata API SOAP endpoint** for retrieves and validations:

- Retrieve: `${instanceUrl}/services/Soap/m/<apiVersion>` with `SOAPAction: "retrieve"`, polled via `checkRetrieveStatus`
- Validate: same endpoint with `SOAPAction: "deploy"` and `<checkOnly>true</checkOnly>`, polled via `checkDeployStatus`
- `singlePackage: false` because retrieve zips put files under `unpackaged/`

Sandbox edits go through the Tooling API or component-specific Metadata API calls (e.g., `update_flow` deploys a Flow XML zip directly to the sandbox). The validate-only path is reserved for the sandbox → production handoff.

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

1. **Build in sandbox, validate against production** — never validate untested changes against production
2. **Keep the package narrow** — only what changed. Broad packages cause unrelated failures and slower validation
3. **Use `RunSpecifiedTests`, not `RunLocalTests`** — ask the user which test classes cover the change
4. **Document what's validated** — every job already commits to Git with a descriptive message; reinforce that in the Slack summary along with the Deploy ID
5. **Time production validations carefully** — heavy validation traffic during peak hours can interfere with org performance
6. **Confirm a rollback plan** before the user Quick Deploys to production, especially for destructive changes
7. **Report only the evidence you have** — if the validation timed out, say so. If warnings were ignored, say so. Match the Slack summary to the highest evidence level reached, never above.
