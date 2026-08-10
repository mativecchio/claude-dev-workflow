---
description: "Generates a copy/paste-ready Jira ticket description, or fetches an existing ticket via MCP. Pre-development perspective."
allowed-tools: Read, Bash, Glob, mcp__mcp-atlassian__jira_get_issue, mcp__mcp-atlassian__jira_search, TodoWrite
---

Your role is to generate or enrich a Jira ticket with the level of detail needed for it to be implemented clearly.

## Step 1 — Determine the mode

**If `$ARGUMENTS` contains an issue key (e.g. BC-1429, PROJ-123):**
Try to fetch the ticket via MCP:
- Use `mcp__mcp-atlassian__jira_get_issue` with the issue key
- If MCP isn't available: ask the user to paste the ticket's content

**If `$ARGUMENTS` is a free-form description:**
Use that description as the basis for generating the ticket.

**If there are no arguments:**
Ask: "Do you have a Jira issue key, or do you want to create a ticket from a description?"

## Step 2 — Enrich with project context

Resolve the active ticket: read `.claude/workflow/state.json` → `activeTicket`.
`{workflowDir}` = `.claude/workflow/{activeTicket}`. If there's no active ticket, skip this step and generate the ticket from `$ARGUMENTS` alone.

Read if they exist:
- `{workflowDir}/refinement-summary.md` → if refinement was already done, use it
- `{workflowDir}/plan.md` → if the technical plan already exists, include technical notes

`/wf-jira` is not a stage of the cycle: it records no `stage` and emits no telemetry.

**Language:** address the user in the language returned by `~/.claude/scripts/wf-lib.sh language` (`en` by default). The generated ticket is always in English.

## Step 3 — Generate the ticket

**Perspective:** write it from the point of view of before development, even if it's already implemented. No internal debates, only the agreed final state.

**Level of detail:** enough for Claude (or another engineer) to implement it without questions.

```markdown
## [Ticket title]

### Objective
[What it solves and why. 2-3 lines.]

### Acceptance criteria
- [ ] [concrete, verifiable criterion]
- [ ] [concrete, verifiable criterion]

### Technical notes
[Relevant implementation decisions, constraints, patterns to follow.
Only what isn't obvious from the acceptance criteria.]

### Endpoint contract (if applicable)
**[METHOD] /path/to/endpoint**

Request:
```json
{
  "field": "type"
}
```

Response:
```json
{
  "field": "type"
}
```

### Required infrastructure
- [ ] Environment variable: `[NAME]`
- [ ] Migration: [description]

### DoD
- [ ] Tests written and passing
- [ ] [items from the project's checklist]
```

## Step 4 — Show and adjust

Show the generated ticket and ask:
**"Do you want to adjust anything?"**

If the user confirms, ask whether they want the ticket updated in Jira via MCP (if it's available).
