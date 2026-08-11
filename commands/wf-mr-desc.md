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

## Step 2 — Generate the description (delegated)

**Use the Agent tool**, with `model` from `~/.claude/scripts/wf-lib.sh model mr-desc` (default `sonnet`).

Two reasons, and the second matters as much as the first. Writing an MR description from a plan and a diff is bounded work against a fixed template — there is no open-ended judgment, so the strongest model buys nothing. And delegating keeps the plan, the refinement and the full diff out of the session's context window, where they were being loaded for a task that never needed to be there.

Pass the Agent everything it needs, because it starts with no context: the contents of `plan.md`, `refinement-summary.md`, `review-findings.md`, the `--stat` and `--log` output from Step 1, and the structure below. Ask it to return the finished markdown and nothing else.

**Principles** (include these in the Agent's prompt):
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

**Read what came back before showing it.** A description can be fluent and still misstate *why* a change was made, and a reviewer will trust it — that is the specific failure to watch for when this step is delegated. If the intent is wrong, the Agent's input was underspecified, not its model: add what was missing and re-run, rather than reaching for a stronger model.

This step stays in the session: adjusting the wording with you is a conversation, not a generation task.

Show the generated description to the user. Instead of an open question, offer the two exits directly and show right away what the next steps are:

```
Adjust anything, or move on?
a) Adjust something in the description
b) It's ready — next: `/wf-mr-review` for the final MR review
```

If the user asks for changes (a), apply them until they're satisfied and offer the same two options again. If they choose to move on (b), don't ask again — go straight to suggesting `/wf-mr-review`.
