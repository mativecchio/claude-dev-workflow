---
description: "Generates the MR/PR description aimed at technical reviewers. No title at the top, context first, doesn't repeat the diff."
allowed-tools: Read, Bash, Glob, TodoWrite
---

Your role is to generate a clear, useful MR description for reviewers, based on the plan's context and the real diff.

## Step 0 — Ticket context

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage mr-desc
```

If `context` fails, ask for the ticket and write `.claude/workflow/state.json` before retrying.

**Language:** address the user in the language reported as `lang` by `context` (`en` by default). Everything written to a file — the MR description, plan.md, code, docs — is always in English.

## Step 1 — Gather context

Read:
- `{workflowDir}/plan.md` → technical solution and decisions taken
- `{workflowDir}/refinement-summary.md` → objective and acceptance criteria
- `{workflowDir}/review-findings.md` → whether there were significant adjustments to the plan

Get the summarized diff:
```bash
~/.claude/scripts/wf-diff.sh --stat
~/.claude/scripts/wf-diff.sh --log
```

## Step 2 — Generate the description

**Principles:**
- Don't start with the title
- Start with the context: why this MR exists
- Don't list modified files (reviewers can see the diff)
- Don't repeat the diff or the commit log
- Group changes by behavior/flow, not by file
- Mention non-obvious technical decisions and their rationale

**Structure:**

```markdown
## Context
[Why this change exists. The problem it solves or the feature it adds.
2-4 lines maximum.]

## Objective
[What this MR does, in one sentence.]

## Changes made
[Describe the solution grouped by behavior, not by file.
For example: "The X flow now does Y when Z" instead of "Modified file.ts".]

### Technical decisions
[Only if there's something non-obvious: why this approach was chosen, trade-offs considered.]

### Infrastructure (if applicable)
- [ ] New environment variables: `[NAME]`
- [ ] Migrations: [description]
- [ ] Feature flags: [description]

## Testing
[What was tested and how. Mention covered edge cases if they're relevant.]
```

## Step 3 — Show and adjust

Show the generated description to the user. Instead of an open question, offer the two exits directly and show right away what the next steps are:

```
Adjust anything, or move on?
a) Adjust something in the description
b) It's ready — next: `/wf-mr-review` for the final MR review
```

If the user asks for changes (a), apply them until they're satisfied and offer the same two options again. If they choose to move on (b), don't ask again — go straight to suggesting `/wf-mr-review`.
