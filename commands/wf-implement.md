---
description: "Implements the changes following the approved plan. Includes a debug mode for bugs/errors. Checkpoint before each group of files."
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, TodoWrite, TodoRead
---

Your role is to implement following the approved plan, respecting the project's conventions, with checkpoints before each expensive step.

## Mode detection

### Debug mode
If `$ARGUMENTS` or the context contains signals like: "doesn't work", "error", "bug", "fails", "returns 4xx/5xx", "it's broken", "doesn't render":

1. **First: diagnosis** — explore the code and understand the root cause
2. **Show the analysis** before touching anything:
   ```
   🔍 Root cause detected: [description]
   📋 Fix plan:
   1. [step 1]
   2. [step 2]
   ```
3. **Checkpoint**: "Is this analysis correct? Should I proceed with the fix?"
4. Wait for confirmation before modifying files

### Normal mode
Follow the full flow below.

---

## Step 0 — Ticket context and branch

```bash
~/.claude/scripts/wf-lib.sh context          # ticket, dir, base, stage, branch, lang
~/.claude/scripts/wf-lib.sh enter-stage implement
```

If the state's `branch` is empty, ask "Which branch are you working on?" and save it:
```bash
~/.claude/scripts/wf-lib.sh set-state branch '"[name]"'
```

If `context` fails, ask for the ticket and write `.claude/workflow/state.json` before retrying.

**Language:** address the user in the language reported as `lang` by `context` (`en` by default). Everything written to a file — code, comments, plan.md, commits — is always in English.

### Model for this implementation

```bash
~/.claude/scripts/wf-lib.sh implement-advice
```

Show the recommendation and move on — **do not wait for an answer, and do not ask them to switch.** This stage runs in the user's session, so nothing here can change the model; the recommendation is information, and stopping the flow for it would cost more than it saves.

The rule behind it: a plan that is approved, scored ≤ 3, and has a sister feature to follow carries enough of the work that a smaller model is adequate. Anything missing — no estimate, not approved, no sister feature — recommends staying on the strong model. It is conservative on purpose: advising a downgrade on a plan that was never verified is a worse failure than not advising one.

Then record what is actually being used:

```bash
~/.claude/scripts/wf-event.sh implement_started \
  --model_used "[the model you are running as]" \
  --model_recommended "[recommended_model from the command above]"
```

`model_used` is **self-reported** — no environment variable exposes the session's model, so this is the one field here that a script cannot verify. Report it accurately even when it contradicts the recommendation: a disagreement between the two is the most informative row in the table, and `wf-stats.sh models` counts exactly that.

This is what makes the whole approach checkable rather than believed. The claim "a smaller model is fine when the analysis was strong" is either true, true under conditions, or false, and only these events can tell which.

## Step 1 — Read the plan's context

Read:
- `{workflowDir}/plan.md` → what to change and in what order
- `{workflowDir}/review-findings.md` → required adjustments to the plan
- `.claude/workflow/config.json` → DoD and stack

If `plan.md` doesn't exist, tell the user to run `/wf-analyze` and `/wf-review-plan` first.

## Step 2 — Starting checkpoint

Show the user a summary of the plan:
```
📋 Approved plan: [task name]
📁 Files to modify: [count]
📍 Implementation order:
  1. [module/group 1]
  2. [module/group 2]
```

**Skip the "Shall we start?" checkpoint (go straight to Step 3) when either of these two cases applies** — there's already an explicit confirmation from the user, no need to ask for another:
- The user invoked `/wf-implement` directly (they typed the command) — that is the confirmation to start.
- You arrived from `wf-validate` with a list of findings already decided item by item (see the picker in `wf-validate` Step 4) — the decision on what to implement was already made there.

**Ask "Shall we start?" only when arriving indirectly** (routed from `/wf` or another command) and there hasn't been any explicit user action asking to implement. Wait for confirmation before touching any file in that case.

## Step 3 — Implement group by group

For each group of files in the plan:

**Before modifying:**
- Read the whole file
- Understand the context and the local conventions (naming, imports, error handling)

**Checkpoint before each group (if it has more than 1 file or is a key module):**
```
⚡ Next step: [group description]
Files: [list]
```
Ask: "Shall I continue?" — only if the user configured detailed checkpoints or if the change is high risk (contracts, auth, DB).

**During implementation:**
- Respect: naming, import structure, error handling style, i18n if applicable
- If you spot an existing helper the plan didn't account for → use it and document the deviation
- If a necessary change wasn't accounted for in the plan → report it before making it

## Step 3.5 — Heuristic: test-first for validation guards

If the group you're about to implement adds or modifies a **validation guard** (code that checks whether a value is valid/safe before using it — e.g. `isValidDate`, sanitization, defensive parsing, null/format checks), evaluate these 3 criteria:

1. The value crosses a data boundary you don't control (sessionStorage/localStorage written by another repo, an external API response, free-form user input, query params).
2. A validation helper already exists or you're adding one (`isValidDate`, `sanitize`, `parse`, etc.) — a sign that "corrupt input" is a known failure mode, not a hypothetical one.
3. The value is used in **more than one place** (grepping the state/prop/variable yields 2+ call sites/consumers).

**If 2 out of 3 hold:** before writing the fix, grep **every** call site of the value (not just the one that motivated the change) and list them:
```
🔎 Call sites of [value] without a guard: [file:line, file:line, ...]
```
Write a test forcing the corrupt/invalid input for **each** call site in the list (or explicitly confirm which ones are out of scope and why) before considering the implementation done — not just for the first place where the problem was spotted.

**Why:** a guard added in a single place (e.g. when hydrating from sessionStorage) leaves the same value unvalidated in other consumers (e.g. form validation, props passed to child components) — a real bug caught in BC-1529 via `/wf-mr-review`, two rounds after implementation, instead of at this stage.

If 2 of the 3 criteria don't hold (controlled internal value, a single call site), follow the normal flow without this extra step.

## Step 4 — Record deviations

If something during implementation is done differently from the plan:
```
⚠️  Deviation from the plan: [description]
Reason: [why]
Impact: [what changes]
```

## Step 5 — Record tech debt

If you find tech debt during implementation, append it to `{workflowDir}/plan.md`:
```markdown
## Tech debt detected (not implemented)
- [description] — detected in [file]
```

## Step 6 — Summary at the end

Once all groups are complete:
```
✅ Implementation complete
📁 Modified files: [list]
⚠️  Deviations from the plan: [list or "none"]
🔧 Tech debt recorded: [list or "none"]
```

Suggest: "Next: `/wf-validate` (optional, recommended) or `/wf-test`"
