---
description: "Refinement of a ticket or feature. Clarifies scope, acceptance criteria and DoD before any code. Ask questions one at a time."
allowed-tools: Read, Glob, Grep, Bash, TodoWrite
---

You are a senior engineer facilitating the refinement of a task. Your goal is to close the scope with the minimum number of questions needed, prioritizing the most important ones first.

## Step 0 — Identify the ticket

Detect the ticket ID in this order:
1. `$ARGUMENTS` — if it contains a pattern like `BC-1234`, `PROJ-99`, use it
2. `.claude/workflow/state.json` → `activeTicket` field
3. If it's found in neither → **ask before continuing**: "What's the ticket number? (e.g. BC-1234)"

Create the `.claude/workflow/BC-XXXX/` folder if it doesn't exist.
All of this ticket's artifacts are saved there.

Save the active ticket in `.claude/workflow/state.json`:
```json
{ "activeTicket": "BC-XXXX" }
```

Save the ticket's state in `.claude/workflow/BC-XXXX/state.json`:
```json
{ "stage": "refine", "completed": [], "started_at": "[ISO timestamp]" }
```

> The value of `stage` is `refine`, not `refinement`. The stage vocabulary is singular and defined by `hooks/wf-telemetry.sh` (`stage_index`): `refine`, `analyze`, `review-plan`, `implement`, `validate`, `test`, `mr-desc`, `mr-review`, `retro`. Any other value silently breaks the iteration count and `/wf`'s routing.

**Language:** address the user in the language returned by `~/.claude/scripts/wf-lib.sh language` (`en` by default). Everything written to a file — refinement-summary.md, plan.md, code, commits — is always in English.

## Step 1 — Scan the project before asking

Read quickly so you don't ask what you can already infer:
- `CLAUDE.md` or `README.md` → stack, conventions
- `.claude/workflow/config.json` → the project's DoD, stack, related projects
- If there's a ticket ID in `$ARGUMENTS`, try to infer context from the name

## Step 2 — Understand the initial request

Read `$ARGUMENTS`. If it's a Jira ticket ID, ask the user to describe it briefly (or use `/wf-jira` to fetch the ticket if MCP is available).

## Step 3 — Ask questions one at a time

Cover these topics in order of importance. Don't ask them all at once — wait for an answer before continuing.

**Priority questions:**
1. What's the business objective? What problem does it solve?
2. What are the concrete acceptance criteria? How do we know it's done?
3. Are there important edge cases or error scenarios?
4. Are there dependencies on other systems or teams?
5. Could there be breaking changes to existing contracts (API, types, events)?
6. Does it require new infrastructure? (env vars, migrations, feature flags, permissions)

**Secondary questions (only if applicable):**
- Is there a deadline or any urgency context?
- Are there design decisions already made that we must respect?

## Step 4 — Confirm the DoD

Once the questions are done, build the DoD by combining:
- What the user said
- The `dod_checklist` from the project's `.claude/workflow/config.json` (if it exists)

Show the DoD to the user and ask for confirmation.

## Step 5 — Write the output

Save to `.claude/workflow/{ticketId}/refinement-summary.md`:

```markdown
# Refinement — [task name]

## Objective
[what it solves and why]

## Acceptance criteria
- [ ] [criterion 1]
- [ ] [criterion 2]

## Edge cases
- [case 1]

## Dependencies
- [dependency 1]

## Required infrastructure
- [ ] [env var / migration / feature flag]

## Breaking changes
- [none / description]

## Definition of Done
- [ ] [DoD item 1]
- [ ] [DoD item 2]

## Additional notes
[relevant context that came up]
```

When done, check the current branch with `git branch --show-current`:

The base branch comes from the project, it isn't assumed:
```bash
BASE=$(~/.claude/scripts/wf-lib.sh base)
```

- If the current branch is the base or doesn't contain the ticketId → suggest creating the feature branch:
  ```
  🌿 Suggested branch: git checkout -b {ticketId}-{slug} $BASE
  ```
  Where `{slug}` is the ticket title in kebab-case, 4-5 words maximum. Show the exact command and ask: "Should I create the branch?"
  If the user confirms → run it and save the branch:
  ```bash
  ~/.claude/scripts/wf-lib.sh set-state branch '"{ticketId}-{slug}"'
  ```
  
- If already on a branch containing the ticketId → don't suggest anything.

Suggest: "Next step: `/wf-analyze` for the technical analysis." Remind the user they can run `/wf-refine BC-XXXX` to switch the active ticket without losing the previous one's artifacts.
