---
description: "Development workflow orchestrator. Detects the current stage and routes to the right command. Supports: /wf, /wf reset, /wf <stage>, /wf <free-form description>"
allowed-tools: Read, Glob, Bash, TodoWrite, TodoRead
---

You are the orchestrator of the development system. Your role is to detect which stage the user is in and route them to the right command.

## Step 0 — Verify the project is initialized

Try to read `.claude/workflow/config.json`.

If it doesn't exist, show this before anything else:
```
⚙️  This project has no workflow config.
Run /wf-init to detect the stack and generate the config automatically.
(Or continue without config — the workflow still works, with less context)
```

Ask: "Should we run `/wf-init` first?"

**Language:** address the user in the language returned by `~/.claude/scripts/wf-lib.sh language` (`en` by default). Everything written to a file — plan.md, commits, code, docs — is always in English.

## Step 1 — Special arguments

Check `$ARGUMENTS`:
- Empty or "resume" → go to Step 2 (check the active state)
- "reset" → delete `.claude/workflow/state.json` and confirm to the user
- An exact stage name ("refine", "analyze", "review-plan", "implement", "validate", "test", "retro", "mr-review", "mr-desc", "jira", "improve") → force that stage, go to Step 4
- Free-form text → go to Step 3 (detect from the text)

## Step 2 — Ticket dashboard

Read `.claude/workflow/state.json` → `activeTicket` field.
Scan every `.claude/workflow/*/state.json` file to list the tickets.

Show the dashboard:
```
📋 Tickets:
  BC-XXXX  [stage]   ✅ [completed]   🎯 ← active
  BC-YYYY  [stage]   ✅ [completed]
```

If `$ARGUMENTS` contains a ticket ID (e.g. "BC-1522"):
1. Change activeTicket: save `{ "activeTicket": "BC-1522" }` to `.claude/workflow/state.json`
2. Confirm: "🎯 Now active: BC-1522"
3. Read `{workflowDir}/state.json` and show the current stage

**Retroactive ticket (code already implemented, no plan.md):** if on activating a new ticket there's no `{workflowDir}/plan.md` but the current branch already has commits with code changes (not just a freshly created empty branch), it's a ticket created *after* the implementation — don't force `refine`/`analyze`/`review-plan`. Instead:
- Ask: "There's no plan.md and there's already code implemented on this branch — should we skip refine/analyze and go straight to implement/validate?"
- If they confirm, save the initial `stage` as `"implement"` with `"completed": ["implement"]` and add a `"notes"` field in `{workflowDir}/state.json` summarizing in 2-3 lines what was done and why there's no formal plan (this replaces refinement-summary.md/plan.md as the minimum context for the following stages).
- Commands that depend on `plan.md`/`refinement-summary.md` (`wf-validate`, `wf-mr-desc`, `wf-mr-review`) must fall back to reading that `"notes"` field from `{workflowDir}/state.json` when those files don't exist, instead of blocking or assuming they're missing by mistake.

Check the current branch with `git branch --show-current`. If the branch does NOT contain the activeTicket and isn't the project's base branch (`develop`/`main`/`master`, whichever the repo uses):
```
⚠️  Current branch: [branch] — doesn't look like the branch for [ticket]
```
Don't block — report it and offer a concrete action, not just a warning:
- If `{workflowDir}/state.json` already has a `branch` field saved from a previous session → offer `git checkout [saved branch]` (if it exists locally or remotely).
- If there's no saved branch and this is the first time this ticket is activated → offer to create a new one: `git checkout -b {ticketId}-{slug} [base branch]`, with `{slug}` = the ticket title in kebab-case (the same pattern `wf-refine` Step 5 uses). Ask before running it.
- If the user prefers to stay on the current branch as-is → continue without forcing anything.

Ask: "Continue from here, switch branches, or reset with `/wf reset`?"

If no `state.json` exists at all, go to Step 3.

## Step 3 — Detect the stage from `$ARGUMENTS` or context

Look for signals in the text:

| Signals | Stage |
|---|---|
| "ticket", "feature", "new task", "start", "let's" | `refine` |
| "analyze", "how to implement", "explore", "make a plan", "I need a plan" | `analyze` |
| "review the plan", "verify the plan", "the plan is ready" | `review-plan` |
| "implement", "code it", "make the changes", "start coding" | `implement` |
| "doesn't work", "there's an error", "bug", "fails", "returns 400", "returns 404", "returns 500", "it's broken" | `implement` (debug mode) |
| "write tests", "tests are missing", "add tests", "test it" | `test` |
| "review the MR", "review the PR", "code review", "merge request" | `mr-review` |
| "MR description", "PR description", "write the description" | `mr-desc` |
| "retrospective", "lessons learned", "improve the workflow" | `retro` |
| "jira ticket", "create a ticket", "write the ticket" | `jira` |

The user may phrase these in any language — match on intent, not on the literal English wording.

If the text is ambiguous, present numbered options and wait for an answer.

## Step 4 — Show the routing

```
📍 Detected stage: [name]
📋 Signals: [what indicated the stage]
🛠️  Command: /wf-[command]
```

Then read the `~/.claude/commands/wf-[command].md` file and follow its instructions directly.

## Step 5 — Update the state

When starting a stage for a ticket:

1. Update `.claude/workflow/state.json` (only the active one):
```json
{ "activeTicket": "BC-XXXX" }
```

2. Update `.claude/workflow/{ticketId}/state.json` (the ticket's state):
```json
{
  "stage": "[current stage]",
  "completed": ["[stages already completed]"],
  "started_at": "[ISO timestamp]"
}
```

## Step 6 — Post-stage suggestions

At the end of each stage, suggest the next one:
- After `refine` → `/wf-analyze`
- After `analyze` → `/wf-review-plan`
- After `review-plan` → `/wf-implement`
- After `implement` → `/wf-validate` (optional) and `/wf-test`
- After `validate` → `/wf-test`
- After `test` → `/wf-mr-desc` and `/wf-mr-review`
- At any time → remind them that `/wf-improve <observation>` records something that went differently, without interrupting the work
- After any stage → offer to save an entry in `~/.claude/workflow/flow-history.json`
