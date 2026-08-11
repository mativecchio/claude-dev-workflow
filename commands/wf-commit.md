---
description: "Generates a commit message with the active workflow's context. Reads plan.md, refinement-summary.md and the diff to produce a Conventional Commits message scoped to the ticket."
allowed-tools: Read, Bash, Glob
---

Your role is to generate a precise commit message using the workflow's context and the real diff.

## Step 1 — Read the workflow context

Try to read (silently, no error if missing):
- `.claude/workflow/state.json` → `activeTicket`
- `{workflowDir}/refinement-summary.md` → objective of the change
- `{workflowDir}/plan.md` → what was implemented

Where `{workflowDir}` = `.claude/workflow/{activeTicket}`. If there's no active ticket or the files don't exist, continue anyway — the diff is enough.

`/wf-commit` is not a stage of the cycle: it records no `stage` and emits no telemetry.

**Language:** address the user in the language returned by `~/.claude/scripts/wf-lib.sh language` (`en` by default). The commit message itself is always in English.

## Step 2 — Get the diff

If it was called with specific files in `$ARGUMENTS`, use those. Otherwise use the staged + modified files:

```bash
# Staged files
git diff --cached --stat

# Modified files (unstaged)
git diff --stat

# Full diff (exclude lock files and binaries)
git diff HEAD -- ':!pnpm-lock.yaml' ':!*.lock' ':!*.png' ':!*.jpg' ':!*.svg'
```

## Step 3 — Determine type and scope

**Type** (Conventional Commits):

| Type | When |
|------|--------|
| `feat` | new user-visible functionality |
| `fix` | bug fix |
| `refactor` | restructuring with no behavior change |
| `style` | style/formatting changes with no logic |
| `test` | new or fixed tests |
| `chore` | tooling, config, deps, build |
| `docs` | documentation only |
| `perf` | performance improvement |

**Scope**: derive it from the ticket ID in `state.json` (e.g. `MA-770`) or from the most affected module (e.g. `PlayerControls`, `chat`, `auth`). If there's a ticket ID, use it as the scope.

## Step 4 — Generate the message (delegated)

**Use the Agent tool**, with `model` from `~/.claude/scripts/wf-lib.sh model commit` (default `sonnet`).

Turning a diff into a Conventional Commits message is a transformation with a fixed output shape and a checkable result. Delegating it also keeps the full diff out of the session's context.

Give the Agent the diff, the ticket context from Step 1, the type/scope decided in Step 3, and the rules below. Ask for the message and nothing else.

Format:
```
<type>(<scope>): <imperative description, max 72 chars>

[optional body: the why, not the what — only if the change isn't obvious from the title]
```

Rules:
- Description in the imperative, lowercase, no trailing period
- Don't repeat the scope in the description
- Body only if there are non-obvious technical decisions or workaround context
- Maximum 2 lines of body
- Don't list modified files

## Step 5 — Show and confirm

Show the proposed message:

```
📝 Proposed commit message:

  <type>(<scope>): <description>

  [body if applicable]

Use this message, adjust it, or write a different one?
```

Wait for the answer. If the user approves or adjusts → return the final message ready to use.

**Do not make the commit** — only generate the message. The caller (wf-deploy or another) runs the commit.
