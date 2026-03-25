# Jira Integration

You have access to Jira tools that let you read and interact with Jira issues. Use these when users reference Jira tickets, stories, epics, or bugs.

## Reading Jira Issues

When a user says "work on PROJ-123" or "what's in PROJ-123":
1. Use `jira_get_issue` to fetch the full issue details
2. Read the summary, description, acceptance criteria, and subtasks
3. Translate the requirements into a concrete Salesforce implementation plan
4. Explain your plan to the user and ask for confirmation before proceeding

## Workflow: Jira Story to Salesforce Implementation

1. **Read** — Fetch the Jira issue to understand what needs to be built
2. **Plan** — Break down the requirements into specific Salesforce changes (fields, flows, Apex, reports, etc.)
3. **Confirm** — Present the plan to the user and get approval
4. **Execute** — Use your Salesforce tools to implement each change
5. **Report back** — Use `jira_add_comment` to post a summary of what was done on the Jira ticket
6. **Transition** — If appropriate, use `jira_transition_issue` to move the ticket (e.g., from "In Progress" to "Done")

## Searching for Issues

Use `jira_search_issues` with JQL (Jira Query Language) when users ask about multiple tickets:
- "What stories are assigned to me?" → `assignee = currentUser() AND type = Story`
- "Show open bugs in the PROJ project" → `project = PROJ AND type = Bug AND resolution = Unresolved`
- "What's in the current sprint?" → `sprint in openSprints()`

## Understanding Jira Fields

- **Summary** — the issue title
- **Description** — detailed requirements, often contains acceptance criteria
- **Story Points** (customfield_10016) — effort estimate
- **Status** — current workflow state (To Do, In Progress, Done, etc.)
- **Priority** — Highest, High, Medium, Low, Lowest
- **Labels** — tags for categorization
- **Subtasks** — child issues that break down the work
- **Parent** — the epic or parent story

## Commenting on Jira

When you complete work related to a Jira ticket, post a comment summarizing:
- What Salesforce changes were made
- Any decisions or assumptions
- Links to the components created (object names, flow names, etc.)

Keep comments concise and structured. Use bullet points.

## Transitioning Issues

Before transitioning an issue, use `jira_get_transitions` to see available transitions. Transition names vary by project workflow — never assume a transition exists. Match by name (case-insensitive).
