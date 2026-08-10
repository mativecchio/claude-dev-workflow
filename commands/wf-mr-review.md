---
description: "Full MR/PR review. Runs in an isolated context via the Agent tool. Supports local git as the diff source. Structured output: critical, important, suggestions."
allowed-tools: Read, Bash, Glob, Grep, Agent, TodoWrite
---

Your role is to prepare the context and launch a full MR review in an agent with a clean context.

## Step 0 — Ticket context

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage mr-review
```

If `context` fails, ask for the ticket and write `.claude/workflow/state.json` before retrying.

**Language:** address the user in the language reported as `lang` by `context` (`en` by default). Everything written to a file — the review, plan.md, code — is always in English.

## Step 1 — Get the diff

```bash
~/.claude/scripts/wf-diff.sh --log
~/.claude/scripts/wf-diff.sh --stat
~/.claude/scripts/wf-diff.sh
```

If `$ARGUMENTS` carries a specific branch, add `--branch [branch]` to each call.

The script resolves the merge-base against the project's base branch. This matters: `[base]..HEAD` breaks if the base advanced through a pull or fast-forward after the feature branch was created, and ends up showing other people's changes as if they belonged to the MR.

If the diff is very large (>500 lines), show the `--stat` to the user and ask whether to continue or narrow the scope. To size it properly:
```bash
~/.claude/scripts/wf-diff.sh --weight
```
`weight_prod` is what matters — `weight_tests` is kept separate, because a 300-line MR where 220 are tests isn't a big MR, it's a well-covered one.

## Step 2 — Gather context

Read:
- `{workflowDir}/plan.md` → context of what was implemented
- `{workflowDir}/refinement-summary.md` → acceptance criteria
- `CLAUDE.md` or `README.md` → stack and conventions
- `.claude/workflow/config.json` → the project's stack

## Step 2.5 — Delegate the generic review

Before launching our own Agent, run the harness's reviewer:

```
/code-review high
```

It covers correctness bugs, simplification, reuse and efficiency over the diff — and it does it better than an instruction of ours, because it maintains itself. For an MR focused on security, `/security-review` instead of or in addition.

**What's left for the Step 3 Agent**, and it's what no generic reviewer can do:
- Contrast against the ticket's `plan.md` and acceptance criteria: does the MR do what was agreed, and only that?
- Contracts with `related_projects`: verify against the other repo's real source code, don't assume it.
- Project-specific conventions (sister feature, existing helpers).
- Recorded tech debt and deviations from the plan.

If `/code-review` already reported a finding, **don't repeat it** in Step 3's output. Reference it and move on.

If the command isn't available in this environment, continue to Step 3 with the full scope (the prompt's "Line-by-line review" section) and note it in the output.

## Step 3 — Launch the review Agent

Use the **Agent tool** with the following prompt:

---
**AGENT PROMPT:**

You are a senior engineer doing a code review of an MR. Your goal is to find real problems — not to give generic feedback.

**MR context:**
[contents of refinement-summary.md and plan.md]

**Stack:** [stack from the config]
**Project conventions:** [summary of CLAUDE.md]

**Full diff:**
[diff]

## Your review process

### 1. Context first (before reviewing line by line)
- What does this MR solve?
- Does the chosen solution make sense architecturally?
- Are there unaccounted-for side effects?

### 2. Line-by-line review
**If Step 2.5 ran `/code-review`, skip bullets 1-3:** it already covered them, and repeating them produces duplicate output the MR author has to discard by hand.

Evaluate in order of importance:
- Bugs and incorrect logic *(covered by `/code-review`)*
- Security — inputs, auth, exposed data *(covered by `/code-review`)*
- Performance — N+1, re-renders, expensive operations *(covered by `/code-review`)*
- **Tests: coverage gaps against the refinement's edge cases** — not generic, but against the cases the ticket identified
- **Modified contracts and their consumers**, including those in other repos

### 3. Side effects
- Are there contracts (API, types, events) being modified that have consumers?
- Are there migrations that could affect existing data?
- Does the diff touch state/storage/a contract shared with some `related_project` (config.json)? If so: does the plan/diff document what was verified against that project's real source code (grep/read of its local `path`), or is it an unconfirmed assumption? A diff that's correct in *this* repo's logic can still be broken if the other side of the contract (an external system) does something different from what was assumed — that point can't be approved by looking at this diff alone.

## Required output

```markdown
## Code review — [MR name]

### 📋 Executive summary
[1-2 lines: what the MR does and the overall verdict]

### 🔴 Critical (blocking)
- **[file:line]** — [problem] → [required correction]

### 🟠 Important
- **[file:line]** — [problem] → [suggestion]

### 💡 Suggestions
- **[file:line]** — [optional improvement]

### 🔗 Side effects
- [modified contracts and affected consumers]
- [if applicable: risk not verifiable against a related_project — what was assumed without confirming against its real source code]

### ❓ Questions for the author
- [question 1]

### ✅ Prioritized action list
1. [critical action 1]
2. [important action 1]
```

---

## Step 4 — Show the review

Read the agent's output and present it to the user.

If there are 🔴 Critical findings, ask: **"Do you want me to tackle any of these items now with `/wf-implement`?"**

## Step 5 — Record findings and the MR's weight

```bash
# one per 🔴 and 🟠
~/.claude/scripts/wf-event.sh finding \
  --category [slug] --severity [high|medium] \
  --stage_origin [refine|analyze|implement] --stage_detected mr-review \
  --detected_by [gate|user] --summary "[one line]"

# the weight, taken from wf-diff.sh --weight (Step 1)
~/.claude/scripts/wf-event.sh mr_opened \
  --weight_prod [N] --weight_tests [N] \
  --branch "[branch]" --target "[base branch]"
```

This stage's findings weigh the most in the leak metric: a defect that made it all the way to the MR passed through `review-plan`, `validate` and `test` without any of them catching it. `stage_origin` is what says which of those three gates to look at.

Mark `detected_by gate` only for what the review found (ours or `/code-review`'s). What you spotted yourself reading the diff goes as `user` — that's exactly the signal that the gates are falling short.
