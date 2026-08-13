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

**Language:** address the user in the language reported as `lang` by `context` (`en` by default). The MR description file itself is also written in that language — it's read by the same team the chat addresses. Code, commit messages, and identifiers stay English regardless of `lang`; only prose docs (this file, plan.md, refinement-summary.md, etc.) follow it.

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
- Open with a TL;DR: 1-3 lines, what this MR does and why, in plain terms — this is the only part most reviewers read before opening the diff
- Be brief. Don't cut content, but don't narrate — one line per change beats a paragraph. If a bullet needs more than ~2 lines to state, it's explaining instead of stating; trim it
- Don't list modified files (reviewers can see the diff)
- Don't repeat the diff or the commit log
- Group changes by behavior/flow, not by file
- Mention non-obvious technical decisions and their rationale, briefly — this is the one place verbosity is earned, and only for the specific decision being explained, not a recap of the change
- **Omit any section below that would be empty or redundant with the TL;DR.** A template header with nothing under it is worse than no header — don't emit "### Technical decisions" or "### Infrastructure" just to leave them thin or unchecked

**Structure:**

```markdown
## TL;DR
[1-3 lines: what this does and why. If this alone covers it, later sections can be short or skipped.]

## Context
[Why this change exists, if it needs more than the TL;DR already gave. Skip this section
if the TL;DR already covers it — don't restate the same thing twice.]

## Changes made
[One line per behavior change. "The X flow now does Y when Z" — not a walkthrough of the diff.]

### Technical decisions
[Omit this section entirely if every choice was obvious. Include only the decisions
a reviewer would otherwise question — why this approach, what trade-off was made.]

### Infrastructure
[Omit this section entirely if none apply. Only include the items that are actually true:
new env vars, migrations, feature flags — don't list an unchecked box for something that didn't happen.]

## Testing
[What was tested and how, briefly. Mention covered edge cases only if non-obvious.]
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
