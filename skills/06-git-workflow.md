# Git Workflow

You can commit the work you do in a sandbox to the connected Git repository as a single pull request using the `commit_and_open_pr` tool. The tool does not exist in production-org conversations — refuse to attempt any Git write if the user asks while working against a production org.

Before you have access to this tool, the account must have a repository connected at /app/git and the active org must be a sandbox or scratch org. Both conditions are already enforced by the tool filter — if you don't see `commit_and_open_pr` in your available tools, it's because one of those isn't true. Don't try to synthesise a git commit through any other tool.

## When to commit

The default flow for any change the agent makes:

1. Build and deploy the metadata in the sandbox first. Verify the change works (validate-only deploy, test classes pass, Flow activated, etc.).
2. **Ask the user** whether to open a pull request. Phrase it plainly: "Want me to open a PR with this change?" Wait for an explicit yes.
3. Only after a clear yes, call `commit_and_open_pr` with the final file contents.

Exception: if the user's original request already pre-approved a PR ("build this flow and open a PR", "commit this to `release/q2-2026`", "ship it", etc.), you may skip step 2 and commit immediately after the sandbox work succeeds. Don't interpret ambiguous signals as pre-approval — when in doubt, ask.

Never call `commit_and_open_pr` before the sandbox work has succeeded. A failed deploy or failed test run is not a PR candidate.

## Two flavors of commit — CRITICAL

Not every modification tool gives you the resulting XML directly. Before committing, classify what you just did:

### Flavor A — Build tools (you already have the content)

These tools accept the full file contents as input, so the content is already in your conversation context. You can commit it directly without retrieving anything.

- `create_apex_class`, `update_apex_class` — you passed the `body`
- `create_apex_trigger`, `update_apex_trigger` — you passed the `body`
- `create_flow`, `update_flow` — you passed the flow XML
- `create_email_template` — you passed the body
- `create_lwc`, `update_lwc` — you passed `js_source` / `html_source` / `css_source` / `xml_source`

For these, just pass the same content you used as input to `commit_and_open_pr.files`, paired with the correct Salesforce DX path (see "What to commit" below).

### Flavor B — Modify-in-place tools (you need to retrieve the XML first)

These tools modify metadata server-side via the Salesforce Metadata API. They return a success message, not XML. To commit the result, you MUST call `retrieve_metadata` to fetch the canonical XML and then pass the returned files to `commit_and_open_pr`.

Common Flavor B tools and the matching Metadata API type to retrieve:

| Tool you used | retrieve_metadata `type` | `full_name` shape |
|---|---|---|
| `create_custom_field`, `update_custom_field` | `CustomField` | `Object.Field__c` |
| `create_validation_rule`, `update_validation_rule` | `ValidationRule` | `Object.RuleName` |
| `update_page_layout` | `Layout` | `Object-Layout Name` |
| `update_compact_layout` | `CompactLayout` | `Object.LayoutName` |
| `update_flexipage` | `FlexiPage` | `FlexiPageDevName` |
| `set_field_level_security` | `Profile` | profile API name (one per profile granted) |
| `create_permission_set`, `update_permission_set_*` | `PermissionSet` | permission set API name |
| `update_profile_object_permissions`, `update_profile_field_permissions`, `update_profile_system_permissions`, `update_profile_tab_visibility`, `update_profile_record_type_defaults` | `Profile` | profile API name (one per profile updated) |
| `create_record_type`, `create_business_process` | `RecordType` / `BusinessProcess` | `Object.RecordTypeName` / `Object.ProcessName` |
| `create_email_alert` | `WorkflowAlert` | `Object.AlertDevName` |
| `add_picklist_values`, `deactivate_picklist_values` | `CustomField` (or `StandardValueSet` for standard picklists) | as above |

The success message of every Flavor B tool now ends with a one-line hint that lists the exact `retrieve_metadata` call to make. Read it.

**Always batch your retrieve_metadata calls.** If you modified a custom field plus four page layouts in one turn, retrieve them all in a single `retrieve_metadata` call by passing every component in the `components` array. One retrieve call → one commit call.

### Mixed flavors

If a job touched both flavors (e.g. you built a flow AND modified a page layout), prepare the files for both in a single `commit_and_open_pr` call:

1. Construct the flow file in memory from what you built.
2. Call `retrieve_metadata` for the layout(s).
3. Concat the in-memory file(s) and the retrieved files into one `files` array.
4. Call `commit_and_open_pr` once.

## What to commit

The tool expects the final file contents as Salesforce DX would lay them out on disk. One commit = one logical change.

| Component | Path | Notes |
|---|---|---|
| Flow | `force-app/main/default/flows/<ApiName>.flow-meta.xml` | Include the XML declaration and the `http://soap.sforce.com/2006/04/metadata` namespace exactly as Salesforce expects |
| Apex class | `force-app/main/default/classes/<ApiName>.cls` + `force-app/main/default/classes/<ApiName>.cls-meta.xml` | Always include the `-meta.xml` sidecar with the `<apiVersion>` and `<status>` |
| Apex trigger | `force-app/main/default/triggers/<ApiName>.trigger` + `.trigger-meta.xml` | Same sidecar rule as classes |
| LWC | `force-app/main/default/lwc/<bundle>/<bundle>.js` + `.html` + `.css` + `.js-meta.xml` | All files for the bundle, one commit |
| Custom object | `force-app/main/default/objects/<ApiName>/<ApiName>.object-meta.xml` | Include any new fields under `.../fields/<FieldApiName>.field-meta.xml` |
| Custom field | `force-app/main/default/objects/<Object>/fields/<Field>.field-meta.xml` | |
| Validation rule | `force-app/main/default/objects/<Object>/validationRules/<Name>.validationRule-meta.xml` | |
| Permission set | `force-app/main/default/permissionsets/<ApiName>.permissionset-meta.xml` | |
| Profile | `force-app/main/default/profiles/<ApiName>.profile-meta.xml` | |
| Page layout | `force-app/main/default/layouts/<Object>-<LayoutName>.layout-meta.xml` | |
| FlexiPage | `force-app/main/default/flexipages/<DevName>.flexipage-meta.xml` | |
| Compact layout | `force-app/main/default/objects/<Object>/compactLayouts/<Name>.compactLayout-meta.xml` | |
| Record type | `force-app/main/default/objects/<Object>/recordTypes/<Name>.recordType-meta.xml` | |
| Email template | `force-app/main/default/email/<Folder>/<ApiName>.email-meta.xml` (+ `.email`) | |
| Email alert | `force-app/main/default/workflows/<Object>.workflow-meta.xml` | All alerts/rules for the object live in one workflow file |
| Report | `force-app/main/default/reports/<Folder>/<ApiName>.report-meta.xml` | |

`retrieve_metadata` already returns paths in this layout — you can pass its output straight to `commit_and_open_pr.files` without renaming.

Only include files that genuinely changed in this job. Don't pad the PR with unchanged content — a focused diff is the point of the workflow.

Never include secrets, session tokens, hardcoded org IDs, or `.env` files.

## End-to-end example: page layout modification + PR

User says: "Add the Test_Description__c field to all four Contact page layouts and open a PR."

```
1. create_custom_field(object_name="Contact", field_name="Test_Description", label="Test Description", field_type="Text")
   → success message ends with: "...call retrieve_metadata with [{type: \"CustomField\", full_name: \"Contact.Test_Description__c\"}]..."

2. update_page_layout(action="add", layout_full_name="Contact-Partnerships Layout", section_label="Contact Information", field_api_name="Test_Description__c")
   → success, hint: retrieve [{type: "Layout", full_name: "Contact-Partnerships Layout"}]

3. update_page_layout(...) for each of the other 3 layouts
   → 3 more success messages with retrieve hints

4. ask user: "Want me to open a PR with this change?" → user says yes

5. retrieve_metadata(components=[
     {type: "CustomField", full_name: "Contact.Test_Description__c"},
     {type: "Layout", full_name: "Contact-Partnerships Layout"},
     {type: "Layout", full_name: "Contact-Client Services Layout"},
     {type: "Layout", full_name: "Contact-Contact Layout"},
     {type: "Layout", full_name: "Contact-Corporate Development Layout"}
   ])
   → returns 5 files, each {path, content}

6. commit_and_open_pr(files=<the 5 files from step 5>, commit_message="feat(contact): add Test Description field to all layouts")
   → returns PR URL
```

That is the entire workflow. One retrieve call. One commit call. No XML reconstruction. No guessing.

## Branch names, PR titles, and PR bodies

The per-org settings at /app/git define three templates:

- **Branch name template** — e.g. `feature/{job_type}-{mmddyyyy}-{job_id_short}`
- **PR title template** — e.g. `[{job_type}] {title}`
- **PR body template** — e.g. `{description}`

`commit_and_open_pr` renders these automatically. You don't substitute the variables yourself — pass omitted parameters and let the tool render them. The available variables are `{job_type}`, `{slug}`, `{title}`, `{description}`, `{job_id}`, `{job_id_short}`, `{mmddyyyy}`, `{yyyymmdd}`, `{username}`, `{org_name}`.

Override the rendered values only when the user has given explicit instructions:
- `branch_name` override: when the user named a specific branch ("commit to `release/q2-2026`", "push it onto `staging`").
- `pr_title` / `pr_body` override: when the user dictated specific language for either.

The `commit_message` is yours to write. Make it a proper conventional-commit-style line: `feat(flow): auto-set Opportunity close date on Closed Won`, `fix(apex): null check in AccountTriggerHandler.execute`, etc. One short line, no trailing period, present tense.

## Base branch

The tool commits to a new branch cut from the per-org **default branch** (e.g. `main` or `develop` depending on what the admin configured for that org at /app/git). If the org has no default branch saved, the tool falls back to the repository's own default branch on GitHub. You don't pick the base — it's configured.

If the configured base branch doesn't exist on the repo, the tool fails with a clear error. Relay it to the user and tell them an admin needs to fix the Default branch at /app/git.

## Idempotency

If the branch the template renders already exists on the repo, the tool commits into that branch rather than failing. If a PR is already open for that branch, the tool returns the existing PR number. This matters if you retry a commit — you won't end up with duplicate PRs, but you may add extra commits to an existing branch.

## If the commit fails

Relay the exact error message to the user. Do not:

- silently retry with a different branch name or provider
- offer to "try again in a minute"
- guess at the fix

Common failure modes and what to say:

- **Invalid GitHub token (401)** — "Your Git access token is no longer valid. An admin can reconnect the repository at /app/git."
- **Repo not found / no access (404)** — "GitHub says the repository isn't accessible. The token's scopes may have changed, or the repo may have been renamed. An admin can check at /app/git."
- **Base branch missing** — "The configured default branch `<name>` doesn't exist on `<owner>/<repo>`. An admin can fix this at /app/git."
- **Production-org refusal** — do not attempt; this shouldn't happen because the tool isn't exposed in production contexts.

## If retrieve_metadata returns no files

If you call `retrieve_metadata` and Salesforce returns zero files, the most common causes are:

- **Wrong `type` name** — Metadata API type names are case-sensitive (e.g. `Layout`, not `layout`; `FlexiPage`, not `Flexipage`).
- **Wrong `full_name` shape** — Layouts use `Object-LayoutName` with a hyphen (not a dot). CustomFields use `Object.Field__c` with a dot. Permission sets use the bare API name with no prefix.
- **Component doesn't exist (yet)** — if the Salesforce write hasn't fully propagated, retry once after a short delay.

Don't fall back to "I can't commit this" if retrieve fails — diagnose, fix the args, and retry.

## After a successful PR

Summarise what shipped in the final user-facing message:

- PR URL and number
- Branch name
- List of files committed
- One-line description of the change

Keep it brief — the PR itself has the details. If the user kicked off this work from a Jira ticket, also consider adding a `jira_add_comment` so the ticket links to the PR.

## Salesforce DX reference (for context)

The agent commits files in the same layout the Salesforce CLI (`sf project deploy start`) expects, so a human reviewer can pull the branch and deploy it without reformatting. Key directory reference:

```
force-app/
  main/
    default/
      classes/          ← Apex classes + test classes (.cls + .cls-meta.xml)
      triggers/         ← Apex triggers (.trigger + .trigger-meta.xml)
      flows/            ← Flow definitions (.flow-meta.xml)
      objects/          ← Custom objects and fields
        <Object>/
          fields/       ← Custom fields
          validationRules/ ← Validation rules
          recordTypes/  ← Record types
          compactLayouts/ ← Compact layouts
      permissionsets/   ← Permission set definitions
      profiles/         ← Profile metadata (minimize — use permission sets instead)
      layouts/          ← Page layouts
      flexipages/       ← Lightning Record Pages
      lwc/              ← Lightning Web Components
      customMetadata/   ← Custom Metadata Type records
      reports/          ← Reports (grouped by folder)
      email/            ← Email templates
      workflows/        ← Workflow rules + email alerts (one file per object)
```

`sfdx-project.json` at the repo root declares `packageDirectories`, `sourceApiVersion`, and `sfdcLoginUrl`. The agent does not need to edit this file — if you ever would, confirm with the user first.

## What the agent does NOT do

- Merge pull requests. The human reviews and merges.
- Push directly to `main` / `master` / `develop` or any configured default branch — all writes land on a new feature branch and go through a PR.
- Run CI pipelines. If the repo has GitHub Actions or similar, the PR triggers them normally.
- Delete branches (yet — coming in a later milestone).
- Handle merge conflicts. If the base branch has diverged and the PR can't auto-merge, that's on the human reviewer.
