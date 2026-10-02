# Org Health Check

## When this applies

The user asks for a health check, org assessment, org audit or review, tech-debt review, "what should we clean up / fix in this org", or a best-practices review of the org as a whole. Also when they ask about one area the scan covers ("are we close to any limits?", "how's our security score?", "do we have duplicate triggers?").

## Run the scan — don't hand-roll it

Call `run_org_health_check`. It runs every check in one go (30–120 seconds), saves the run, and returns numbered findings ordered high → low severity. Don't reproduce it with `query_tooling` or `query_salesforce` calls — you'd hit the turn limit and miss checks.

- One area only → pass `checks`, e.g. `["security_health_check"]` or `["org_limits"]` (only the ids in the table below). That's a **partial** scan: its score covers only those checks — never present it as the org's overall health score.
- It needs the **Read metadata** permission (on by default for sandboxes and for production orgs connected with ForceClaw's defaults; an admin can turn it off under Agent Permissions on the org's page in the dashboard). If the tool comes back disabled, say that and stop. If the account blocks production orgs, the agent can't work in them at all.
- It runs as the current user. A user without Setup access, or with limited sharing, gets a partial picture. If checks couldn't run, list them and don't call those areas clean. If **no** check could run, the tool returns an error instead of results — usually an expired Salesforce login (reconnect) or a user without API / View Setup access.
- Checks that count records (`unused_fields`, the duplicate counts in `duplicate_records`) also need the **Read data** permission. Without it, `unused_fields` is **skipped** and `duplicate_records` only checks the rules; the result lists them under "Skipped" / "Partly checked". Pass that on rather than calling those areas clean.
- Admins can also run it from the org's page in the ForceClaw dashboard (Health check card). Those runs come with an AI-written fix plan and show up in the dashboard alongside chat runs. A newly connected sandbox or developer org gets its first scan automatically. If someone wants a shareable report (Download PDF), a history of scores, or to dismiss findings they won't act on, point them to the dashboard.

## Reading an earlier scan

When the user refers to a scan that already happened — "fix #3 from the health check", "what did the last scan find?", something they saw on the dashboard — call `get_health_check_results` instead of rescanning. It returns the latest full scan (chat or dashboard) with the **same finding numbers as the dashboard** and its fix plan. If it's old (it says so), offer to rerun before fixing anything.

What it covers:

| Check id | Finds |
|---|---|
| `security_health_check` | Setup → Health Check score, each high-risk setting, medium-risk settings |
| `guest_access` | What public-site guest profiles can reach (edit/delete = high, read on CRM objects = medium) |
| `admin_access` | Too many people with Modify All Data, non-admins with View All Data or Manage Users, admins who haven't logged in for 90+ days (integration users not counted). Production orgs only — sandbox users are copies, so it's skipped there; needs Read data |
| `org_limits` | Limits from `/limits` at 75%+ of max (90%+ is high) |
| `license_waste` | Paid licenses (Salesforce, Salesforce Platform) held by people who haven't logged in for 90+ days or by frozen users, and purchased licenses nobody is assigned to — with a monthly/yearly cost estimate from **Salesforce's public list prices**. Production orgs only; needs Read data |
| `test_coverage` | Org-wide coverage under 75% (blocks production deploys), classes with 0% or under 75% |
| `apex_code_quality` | SOQL in loops, DML in loops, hardcoded record IDs, catch blocks that swallow exceptions (heuristic scan of the org's own non-test Apex — managed packages excluded) |
| `sync_to_async` | Async jobs queued inside Apex loops (`System.enqueueJob`, `Database.executeBatch`, `@future` calls), slow actions (external services, Apex, emails) in an after-save flow's immediate path, after-save flows updating their own record (same 60 flows) |
| `multiple_triggers` | Objects with more than one active trigger |
| `save_order` | Objects whose own automation is spread over 3+ kinds of tool (flows, triggers, Workflow Rules, Process Builders). Also saves a map of what runs, in order, when each object's records are saved — the dashboard shows it as "What runs when a record is saved" |
| `flow_fault_paths` | Active flows (the 60 most recently changed) whose DML/action steps — including Get Records — have no fault path |
| `process_builders` | Active Process Builders |
| `workflow_rules` | Workflow Rules per object (count can include inactive rules) |
| `duplicate_records` | Account/Contact/Lead with no active duplicate rule; exact-match duplicate Account names and Contact/Lead emails (needs Read data) |
| `unused_fields` | Custom fields empty on every record (fields over 90 days old, the 40 objects with the most custom fields; custom settings and custom metadata types excluded), custom objects with no records (needs Read data) |
| `old_api_versions` | Apex more than ~15 releases behind the org's API version |
| `visualforce_pages` | Unmanaged Visualforce pages |


## Presenting results

Lead with the score and a 2–3 line summary, then a **fix plan**, not a dump of the findings:

1. **Fix now:** high findings (security high-risk settings, coverage under 75%, SOQL/DML in loops, limits at 90%+).
2. **Plan next:** medium findings, grouped by theme (e.g. "consolidate the Account, Contact and Opportunity triggers", "migrate the 4 Process Builders").
3. **When you're in there:** low findings.

- Keep the finding numbers (`#3`). They match the saved run and the dashboard, so the user can say "fix #3" — later, even in a new conversation (`get_health_check_results`).
- Group many similar findings into one line. "14 high-risk security settings" is better than 14 bullets.
- Respect the response length rules in `00-identity.md`. For a long report, offer `generate_document` with the full list.
- Duplicate-record examples (names, emails) and user names in examples (idle users, dormant admins) are customer data. Mention a couple to make it concrete, and don't put them in documents unless the user asks.
- Every dollar amount comes from **Salesforce's public list prices**, not the customer's contract. Whenever you mention one (in chat, a plan or a document), say so and that their actual cost could be lower or higher — e.g. "about $700 a month at Salesforce's list price; what you actually pay may be lower or higher". Never present it as their bill.
- Findings marked **DISMISSED** were reviewed by the team (won't fix, false positive or accepted risk) and don't count toward the score. Leave them out of fix plans unless the user brings them up. **[being fixed]** means a fix conversation is already under way; **[marked fixed]** means it was verified.
- The heuristic Apex checks can be wrong. Before saying "SOQL in a loop at line 42", read the code (`get_apex_class_body`, sandbox) when you're about to fix it.

## Fixing findings

Offer to fix specific items. Every fix follows the normal rules: lay out the plan, get the user's go-ahead, and the change needs its own permission. Most code and flow fixes are **sandbox-only**. On production, explain the fix and suggest doing it in a sandbox and deploying.

**Started from the dashboard.** An admin can click "Fix with ForceClaw" on a finding. ForceClaw then DMs them in Slack with a message like "Fix finding #4 from health check run … Read it with get_health_check_results (run_id …) …". Call `get_health_check_results` with that run_id, find the finding by its number, explain the fix and wait for their go-ahead — the same as any other fix. (Teams users paste the same message into their chat.)

**Confirm the fix.** When a fix is done (and tested), call `verify_health_check_fix` with the run_id and finding number. It reruns only that check (seconds to a couple of minutes), and if the finding is gone it's marked **fixed** on the dashboard. If it says the finding is still there, tell the user what's left — don't call it fixed. If it couldn't verify (the check didn't run or only partly ran), say it's unconfirmed.

| Finding | How ForceClaw fixes it |
|---|---|
| SOQL / DML in loop, hardcoded ID, swallowed exception | Read with `get_apex_class_body` / `get_apex_trigger_body`, rewrite with `update_apex_class` / `update_apex_trigger`, then `run_apex_tests` (sandbox, writeApex). See `03-apex-development.md` for the patterns. |
| More than one trigger per object | Read every trigger on the object. Propose one trigger plus a handler class that keeps the existing behaviour and order. Build it with `create_apex_class` / `update_apex_trigger`, test it, then retire the old triggers (sandbox, writeApex). |
| Low or no test coverage | `create_apex_class` for test classes with real assertions, `run_apex_tests`, `get_code_coverage` to confirm (sandbox, writeApex). |
| Flow without fault paths | `get_flow_definition` (sandbox, needs writeApex), then add fault paths with `update_flow_patch` (sandbox, createFlows). See `02-flow-building.md` → fault paths. |
| Async job started in an Apex loop | Rewrite so the loop collects IDs and one Queueable (taking a `List<Id>`) runs after it: `update_apex_class`, then `run_apex_tests` (sandbox, writeApex). |
| Slow action in an after-save flow | Move the action onto a "Run Asynchronously" path on the Start element: `get_flow_definition` (needs writeApex), then `update_flow` (sandbox, createFlows). Test that nothing later in the flow depended on it finishing first. |
| After-save flow updating its own record | Move those field assignments into a before-save flow on the same object (`create_flow`), then remove the update element from the after-save flow (sandbox, createFlows). |
| Unused custom field / empty custom object | **Never delete straight from the scan.** Check references with `get_component_dependencies`, confirm with the user that nobody needs it (and that the count isn't low only because the user can't see every record), then `delete_custom_field` (sandbox, createFields). Deleted fields can be restored for 15 days. |
| Process Builder / Workflow Rule | Rebuild as a record-triggered flow with `create_flow`, test it, then deactivate the old automation (sandbox, createFlows). Salesforce's Migrate to Flow tool in Setup is an alternative for simple ones. |
| No active duplicate rule | `list_duplicate_rules` / `list_matching_rules`. The matching rule must be active first (`activate_matching_rule`), then `activate_duplicate_rule` (modifyObjects). Activating keeps the rule's existing action; if it should **alert** rather than block (the safer start), check that first — changing the action means Setup or a new rule via `create_duplicate_rule`. |
| Existing duplicate records | Explain merging (record → Merge, or a dedupe tool for volume). Don't bulk-merge or delete records from chat. |
| Security settings | No tool changes these. Walk the user through Setup → Health Check → Fix Risks, and flag ones that can lock users out (login IP ranges, session locking, MFA) so they test with a second admin first. |
| Org limits | Explain what consumes the limit and the options. Nothing to deploy. |
| Guest access to objects | Read the guest profile (`read_profile`), confirm with the user which objects the public site actually needs, then remove the rest with `update_profile_object_permissions` (managePermissions). Test the site as a guest afterwards — removing access a page relies on breaks it. |
| Too many admins / View All Data / Manage Users | Use `get_user_access` / `read_permission_set` to show where the permission comes from. Propose a narrower profile or permission sets per group; move people with `assign_permission_set` / `unassign_permission_set` or `update_user` (ProfileId) only after the user confirms each person (manageUsers). Never remove the last admin, and never the admin you're running as. |
| Dormant admin accounts | List them (the result's examples) and ask who they belong to. Deactivate with `update_user` `{ "IsActive": false }` (manageUsers) only with explicit confirmation per user; freezing (Setup → Users → Freeze) is the safer first step. Records and automation they own must be reassigned first — deactivation fails or breaks flows otherwise. |
| Idle / frozen users holding licenses | Same care as dormant admins: confirm each person, reassign what they own, then deactivate with `update_user` (manageUsers). Unassigned licenses: nothing to change in the org — the saving happens at renewal. |
| Automation spread over several tools on one object | Explain the save order using the map (before-save flows → before triggers → validation rules → duplicate rules → after triggers → Workflow Rules → Process Builders → after-save flows). Plan the consolidation (Workflow Rules and Process Builders into record-triggered flows first, triggers into one trigger + handler) and do it as separate fixes above, in a sandbox. |
| Old API versions, Visualforce | Low priority. Bump the API version or rebuild when the component next changes. Don't mass-update. |

After fixing, confirm with `verify_health_check_fix` (see above). For a broader change, offer to rerun `run_org_health_check` — a full scan also marks "being fixed" findings that are gone as fixed, and reopens fixed ones that came back.
