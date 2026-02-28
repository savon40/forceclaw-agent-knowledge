# forceclaw-agent-knowledge

Knowledge base for the ForceClaw Salesforce AI assistant. Markdown skill files and example code in this repo get injected into the agent's system prompt at runtime, making the bot smarter without code changes.

**Edit a markdown file, redeploy, done.**

## How it works

1. `forceclaw-api` reads files from this repo at startup (or on reload)
2. Skill files (`skills/*.md`) are concatenated and injected into the system prompt
3. Example files (`examples/**/*`) are available as reference patterns the agent can draw from
4. The numbered prefix on skill files controls load order

## Directory structure

```
skills/                  ← Markdown skill files injected into the system prompt
  00-identity.md         ← Persona, tone, Slack formatting rules
  01-salesforce-metadata.md  ← SOQL patterns, Tooling API reference
  02-flow-building.md    ← Flow reading/building knowledge
  03-apex-development.md ← Apex patterns, naming, governor limits
  04-report-building.md  ← Report/dashboard knowledge
  05-permissions.md      ← Permissions, profiles, sharing rules
  06-git-workflow.md     ← Git/branching conventions
  07-deployment.md       ← SF deployment patterns
  08-integrations.md     ← External integrations

examples/
  apex/                  ← Reference Apex code (triggers, handlers, tests)
  flows/                 ← Reference Flow definitions
  reports/               ← Reference report configs
  objects/               ← Reference object/field definitions
```

## File conventions

- **Skill files** are numbered `XX-name.md` — the number sets load order
- Use gaps in numbering (00, 01, 03, 05…) so new files can be inserted without renaming
- Each skill file should be **self-contained** — paste it into a system prompt and the agent gets meaningfully better at that topic
- Keep files focused. One capability domain per file
- Use `<!-- TODO -->` to mark sections that need content

## Adding a new skill

1. Pick the right number slot (or use the next available)
2. Create `skills/XX-topic-name.md`
3. Write the content — think "what would make a Claude agent better at this?"
4. Add examples to `examples/` if relevant
5. Redeploy the API

## Adding examples

- Put example files in the appropriate `examples/` subdirectory
- Use real Salesforce file extensions (`.cls`, `.trigger`, `.xml`)
- Include comments explaining the pattern and why it's recommended
- Examples should follow Salesforce best practices and compile on a standard org
