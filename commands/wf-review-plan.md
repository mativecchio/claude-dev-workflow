---
description: "Verifies the implementation plan against the real codebase. Runs in an isolated context. BLOCKS until explicit user approval before moving to implementation."
allowed-tools: Read, Glob, Grep, Bash, Agent, TodoWrite
---

Your role is to verify that the plan is correct and complete before touching code. This is the most important checkpoint in the system.

## Step 0 — Ticket context

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage review-plan
~/.claude/scripts/wf-lib.sh set-state approved false
```

`approved` always starts false: approval of this stage is explicit and is only written in Step 4.

**This field is not decorative.** The `wf-gate.sh` hook reads it on every `Edit`/`Write`: while the ticket is in `review-plan` unapproved, the gate records the attempt (`observe` mode) or blocks it (`enforce` mode). This command's checkpoint stopped being just an instruction.

If `context` fails, ask for the ticket and write `.claude/workflow/state.json` before retrying.

**Language:** address the user in the language reported as `lang` by `context` (`en` by default). Everything written to a file — review-findings.md, plan.md, code — is always in English.

## Step 1 — Verify the plan exists

Read `{workflowDir}/plan.md`. If it doesn't exist, tell the user to run `/wf-analyze` first.

Also read:
- `{workflowDir}/refinement-summary.md` → acceptance criteria and DoD
- `.claude/workflow/config.json` → stack and project context

## Step 2 — Launch the verification Agent

Use the **Agent tool** with the following prompt:

**Pass `model` explicitly**, taking it from the `model=` line that `context` printed in Step 0 (or `~/.claude/scripts/wf-lib.sh model review-plan`):

```
Agent(model: "<value from wf-lib>", prompt: ...)
```

Without it the agent inherits the session's model, which makes this stage's output depend on an unrelated setting rather than on a decision. The default is `opus`: this stage carries judgment the rest of the cycle rests on. A project can override it with a `models` block in `config.json`.


---
**AGENT PROMPT:**

You are a senior engineer reviewing an implementation plan before development starts. Your job is to find problems, not to validate what's already fine.

**Plan to review:**
[full contents of plan.md]

**Original acceptance criteria:**
[contents of refinement-summary.md]

**Stack:** [stack from the config]

## What to verify

### Consistency with the codebase
- Do the mentioned files exist?
- Are the proposed patterns consistent with how the project does it today?
- Are there existing helpers or utilities the plan ignores and should use?

### Completeness
- Is every acceptance criterion covered by some change in the plan?
- Is any file that will clearly need changes missing?
- Is the infrastructure complete (env vars, migrations, etc.)?

### Backward compatibility
- Do the contracts being modified have consumers that would break?
- Is the implementation order correct, or does it create circular dependencies?

### Contracts with related projects
- If the plan touches state/storage/a contract shared with some `related_project` (config.json), does the plan document what was verified against that project's real source code (file:line), or does it assume the behavior without having reviewed it?
- If the `related_project` has a local `path` and the plan treats it as "can't be confirmed, it's external" without having grepped that path, flag it as a finding — the path exists and is verifiable, it isn't a real black box.
- Did the plan cross-reference `~/.claude/workflow/flow-history.json` looking for previous bugs at the same integration point? **This check only applies if the file has non-empty `entries`.** If the array is empty — its default state until Phase 4 populates it — it isn't a finding: there's no history to ignore. Flag it only when an entry exists with the same `related_project` in `key_findings`/`anomalies` and the plan doesn't mention it.

## Classify findings

**🔴 Blocking** — the plan will fail or break something if executed as-is  
**🟠 Important** — may cause problems or rework, needs adjustment  
**💡 Suggestion** — optional improvement, non-blocking  

## Required output

Write to `{workflowDir}/review-findings.md`:

```markdown
# Plan review — [task name]

## 🔴 Blocking
[if none: "None"]

## 🟠 Important
[if none: "None"]

## 💡 Suggestions
[if none: "None"]

## Verdict
[APPROVED / APPROVED WITH ADJUSTMENTS / BLOCKED]

## Required adjustments to the plan
[list of changes to make before implementing, or "None"]
```

When you're done, say: "Review written to {workflowDir}/review-findings.md"

---

## Step 3 — HARD CHECKPOINT

Read `{workflowDir}/review-findings.md` and show the result to the user.

**This is the most important checkpoint in the system. NEVER move to implementation without an explicit answer.**

Show the verdict and ask:
**"Shall we proceed to implement? Answer 'yes' to continue, or tell me what needs adjusting."**

- If there are 🔴 Blocking findings → don't offer to implement until they're resolved
- If there are 🟠 Important findings → show them and ask whether to adjust the plan first
- If the verdict is APPROVED → wait for an explicit "yes" from the user

## Step 3.5 — Record the findings

One per 🔴 and 🟠 in the review (not the 💡 ones):

```bash
~/.claude/scripts/wf-event.sh finding \
  --category [slug] --severity [high|medium] \
  --stage_origin [refine|analyze] --stage_detected review-plan \
  --detected_by [gate|user] --summary "[one line]"
```

The two fields that matter, and the only ones that can't be reconstructed later:

- **`stage_origin`** — which stage *introduced* the defect, not where it surfaced. An ambiguous requirement the plan carries along originated in `refine`, even if you catch it here. It's what answers "which stage originates the most defects?" and where the next gate belongs.
- **`detected_by`** — `gate` if the review found it, `user` if you found it reading the output. If the share of `user` rises over time, the gates are degrading. Marking it `gate` when you were the one who said it inflates the metric and makes the comparison useless.

`--category` is a short slug, **reusable** across tickets (`missing-guard`, `wrong-layer`, `contract-drift`). A different category per finding groups with nothing: the query that matters is which ones repeat across 3+ tickets.

If the command fails, continue with the checkpoint anyway. Losing an event is acceptable; halting the flow over telemetry is not.

## Step 4 — Next step (only with approval)

Only if the user confirms explicitly:

1. Record the approval:
   ```bash
   ~/.claude/scripts/wf-lib.sh set-state approved true
   ```
   This is what unlocks the gate: until now, any `Edit`/`Write` on code was recorded as an attempt to skip the checkpoint.
2. Say: "Next: `/wf-implement`"

If the user doesn't confirm, `approved` stays `false`. Don't write it "just in case" or anticipate the approval.
