# Agentforce Agents & Agent Script

## When this applies

Any request to build, change, review, explain, plan, or troubleshoot a Salesforce **Agentforce agent** — its topics / subagents, actions, instructions, routing, or Agent Script. Also "is my org ready for Agentforce?" and "what agents do we have?". Prompt templates, Prompt Flows, and the Apex / Flows behind agent actions are covered in `17-agentforce-prompts-and-actions.md` — load both for any agent build.

## What ForceClaw can do today — say this honestly

| Capability | How |
|---|---|
| Check org readiness (formats, Einstein, licenses, permission sets, existing agents, FSC data model) | `check_agentforce_readiness` — **always call first** |
| List agents, explain or review an existing agent | `retrieve_agent` (no name → list; with name → full design) |
| Raw agent XML for Git | `retrieve_metadata` (types `GenAiPlannerBundle`, `GenAiPromptTemplate`, `AiAgentDefinition`, …) |
| Build the invocable Apex behind an action (sandbox) | `create_apex_class` (+ a test class) |
| Build an autolaunched Flow behind an action (sandbox) | `create_flow` |
| **Deploy an agent, a prompt template, or a Prompt Flow** | **Not available yet.** Say so plainly. |

When the user asks you to build an agent, you can still deliver real value:
1. Run `check_agentforce_readiness` and report blockers.
2. Design the agent (subagents, actions, variables, what backs each action) and get approval.
3. Build the backing Apex and autolaunched Flows with the tools above (sandbox only).
4. Write the Agent Script and deliver it with `generate_document` as a **draft** the user pastes into Agentforce Builder. Say clearly that it is **not deployed and not tested**, and list the prompt templates / Prompt Flows they must create in Prompt Builder (give their full content).

Never claim an agent, prompt template, or Prompt Flow was deployed, activated, or tested. In a **production** org, agent building is sandbox-only — build in a sandbox, promote with `validate_deploy_to_production`.

## Two agent formats — check which one the org has

`check_agentforce_readiness` tells you. Never assume.

| | **Agent Script** (current) | **Planner bundle** (older) |
|---|---|---|
| Metadata | `AiAgentDefinition` + `AiAgentDefinitionVersion` (source: `AiAuthoringBundle`) | `GenAiPlannerBundle` |
| What you write | A `.agent` script (text DSL) | XML with embedded `localTopics` / `localActions` + `input/schema.json`, `output/schema.json` per action |
| Retrieved form | Version folder with `agentScript/<Agent>_v<n>_definition.agent` (**base64** — `retrieve_agent` decodes it), compiled `<planner>` XML, compiled `agentGraph` JSON | One `.genAiPlannerBundle` XML + schema files |

The version XML and graph JSON are **compiled from the script** — never hand-edit or generate them. `Bot` / `BotVersion` are not how agents are defined (unavailable in many orgs).

Planner-bundle facts (for reading/explaining older agents): `plannerType` `AiCopilot__ReAct`; topics have `scope`, `description`, ordered `genAiPluginInstructions`, `aiPluginUtterances`, `canEscalate`; action `invocationTargetType` is one of `flow`, `apex`, `generatePromptResponse`, `standardInvocableAction`.

## Agent Script reference

### File layout (top-level blocks, in this order)

```
config:
    developer_name: "Case_Assistant"
    agent_label: "Case Assistant"
    description: "…"
    agent_type: "AgentforceEmployeeAgent"
    enable_enhanced_event_logs: True

variables:
    record_id: mutable string = ""
        description: "SET BY / READ BY / CLEARED BY — see rule 9"
    currentRecordId: mutable string
        label: "currentRecordId"
        description: "The ID of the record on the user's screen. It may not relate to the user's input."
        visibility: "External"

language:
    default_locale: "en_US"
    additional_locales: ""
    all_additional_locales: False

system:
    instructions: |You are … Rules: …
    messages:
        welcome: |…
        error: "…"
    recommended_prompts:
        in_conversation: False
        welcome_screen: True
        starter_prompts:
            - "Summarize this record"

start_agent router:        # entry point — routes to subagents
    …

subagent case_summary:     # one per job the agent does
    …
```

- Indentation is 4 spaces and is significant. `#` starts a comment. Booleans are `True` / `False`.
- `currentRecordId` with `visibility: "External"` is how the agent receives the record the user is looking at.
- Older scripts use `topic <name>:` instead of `subagent <name>:` — read both, **write `subagent`**.

### Inside a subagent

```
subagent case_summary:
    description: "…read by the router to decide when to come here…"
    before_reasoning:                # deterministic — runs before the LLM
        set @variables.record_id = @variables.currentRecordId
        if @variables.record_id != @variables.last_record_id:
            set @variables.summary = ""
            set @variables.last_record_id = @variables.record_id
    reasoning:
        instructions: ->
            if @variables.record_id != "" and @variables.summary == "":
                run @actions.Case_Summary
                    with "Input:Case" = @variables.record_id
                    set @variables.summary = @outputs.promptResponse
            if @variables.summary != "":
                | Display exactly: {!@variables.summary}
            if @variables.summary == "":
                | I couldn't generate the summary. …
        actions:                     # what the LLM may choose this turn
            capture_question: @utils.setVariables
                description: "Use this action when … Do NOT use for …"
                available when @variables.question == ""
                with question = ...
            go_to_router: @utils.transition to @subagent.router
                description: "…"
    after_reasoning:                 # deterministic cleanup
        set @variables.summary = ""
    actions:                         # action DEFINITIONS
        Case_Summary:
            description: "…"
            label: "Case Summary"
            require_user_confirmation: False
            include_in_progress_indicator: True
            progress_indicator_message: "Summarizing"
            target: "generatePromptResponse://Case_Summary"
            inputs:
                "Input:Case": object
                    is_required: True
                    complex_data_type_name: "lightning__recordInfoType"
            outputs:
                promptResponse: string
                    is_displayable: False
                    filter_from_agent: False
```

- `run @actions.X` — deterministic call. `with <input> = <expr>` binds inputs; `set @variables.v = @outputs.<name>` stores outputs.
- `| text` — an instruction to the LLM. `{!@variables.x}` inserts a value. Continuation lines are indented.
- `with v = ...` (literal three dots) — the LLM fills the value from the conversation.
- `@utils.setVariables` — let the LLM capture values into variables. `@utils.transition to @subagent.x` — move to another subagent.
- `available when <condition>` — the action is only visible to the LLM when true.
- A reasoning action can expose a defined action to the LLM: `Lookup: @actions.Lookup` with `with p = ...`.

### Action targets and types

| Target | Backed by |
|---|---|
| `flow://Api_Name` | Active autolaunched Flow (inputs/outputs = flow variables marked input/output) |
| `apex://ClassName` | Apex class with one `@InvocableMethod` |
| `generatePromptResponse://Template_Name` | Published prompt template — output is always `promptResponse` |
| `standardInvocableAction://getDataForGrounding` | Standard action; add `source: "EmployeeCopilot__GetRecordDetails"` — returns a `snapshot` of a record |

Types: `string`, `integer`, `boolean`, `object`, `list[object]`. `complex_data_type_name`: `lightning__textType`, `lightning__recordInfoType` (a record for a prompt template), `lightning__recordIdType`, `@apexClassType/c__Class$Inner` (Apex wrapper). Prompt template inputs are quoted: `"Input:Case"`. Input flags: `is_required`, `is_user_input`, `label`, `description`. Output flags: `is_displayable`, `filter_from_agent`, `is_used_by_planner`, `label`, `description`.

## Authoring rules — what makes an agent reliable

These come from a production agent that was hardened through testing. Follow all of them; check all of them when reviewing.

1. **Deterministic first.** Anything computable without the LLM (classifying the record type, resetting state, fetching the record) goes in `before_reasoning` or a guarded `run` — e.g. classify the object from the record Id with a small Flow, not with the LLM.
2. **Reset state on record change — in every subagent.** There is no shared `before_reasoning`. Each subagent that uses record-scoped variables must clear them when `record_id != last_record_id`. Missing one subagent leaks data from the previous record.
3. **Guard every `run`.** Wrap it in an `if` that checks its inputs are present and its output is still empty, so it runs once and only with valid input.
4. **Gate LLM choices with `available when`.** If the LLM shouldn't pick an action right now, it shouldn't see it.
5. **Capture, then route.** Capture the user's question into a variable (`@utils.setVariables`) before transitioning, so the destination subagent doesn't ask again. When the record already supplies context, forbid clarifying questions explicitly.
6. **Put routing rules in action descriptions**, in the form "Use this action when … Do NOT use this action for …". Mid-turn `|` instructions about routing are advisory and were ignored in testing; action descriptions were followed.
7. **Verbatim output contract.** When a prompt template produces the answer, instruct the agent to output it character-for-character (HTML, tables, links intact) with no added questions, offers, or commentary.
8. **Error-trap every branch, plus a terminal catch-all.** Each failure path gets a message with what happened, the likely cause, and what to do. Without a final catch-all, the LLM invents a reply when every branch falls through.
9. **Document variable lifecycles** in each variable's description: SET BY, READ BY, CLEARED BY, SCOPE. Keep per-turn and cross-turn variables separate; never share one variable between two pipelines.
10. **Keep duplicated action definitions identical** across subagents (define once, copy exactly).
11. **Parenthesise mixed `and` / `or`.** `A and B or C` is evaluated as `(A and B) or C`. Write `A and (B or C)` when that is what you mean.
12. **Never fabricate.** `system.instructions` must say to use only data returned by actions, templates, or prior answers, and never invent record numbers, IDs, figures, steps, or links.

## Explaining an existing agent

`retrieve_agent` returns a lot of detail. Don't paste it back.

- **Inline reply: 200 words max** — purpose, topics/subagents, action counts, the 3–5 most important guardrails. Then offer the full breakdown; when the user wants it (or asked for "everything"), deliver it with `generate_document` (format `md`).
- **Counts:** copy the numbers from the tool's `Counts:` line. Don't recount.
- **Status:** never say an agent is live, deployed to customers, activated, or "working" unless the tool output says so. Planner-bundle metadata doesn't include activation status — say it wasn't checked.
- **No invented examples:** don't write sample conversations or example values (category names, product names, amounts, terms) unless they appear in the tool output. The agent's example utterances are fine to quote.

## Review checklist (for "review my agent" or before handing over a script)

- Every `run @actions.X` has a definition in that subagent's `actions:`; every `@variables.x` is declared; every `@subagent.x` exists.
- Every action input is bound to the variable that actually holds that value (a common bug: passing `record_subject` into a `description` input).
- Mixed `and`/`or` conditions are parenthesised.
- Every subagent that reads record-scoped variables resets them on record change.
- Every reasoning block ends with a catch-all error message.
- DML / write actions use `require_user_confirmation: True`.
- Backing Flows are active, Apex classes compile and have one `@InvocableMethod`, prompt templates are published.

## Testing

ForceClaw cannot run test conversations against an agent yet. After any build, tell the user it is untested and give 5–8 test utterances per subagent (including off-topic, missing-record, and follow-up cases) to try in Agentforce Builder's test panel.

## Examples

`examples/agentforce/` has a complete, generic Agent Script (router + case summary + follow-up + catch-alls) that demonstrates every rule above. Pattern against it.
