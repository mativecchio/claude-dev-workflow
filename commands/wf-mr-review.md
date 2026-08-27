---
description: "Full MR/PR review. Runs in an isolated context via the Agent tool. Given an MR link it reads the real MR from GitLab/GitHub (MCP or CLI) and falls back to the local git diff. Structured output: critical, important, suggestions."
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

## Step 1 — Get the MR

### 1a — If `$ARGUMENTS` carries an MR/PR reference, read the real MR first

A link (`https://gitlab.com/.../merge_requests/123`, `https://github.com/.../pull/123`) or a bare
`!123` / `#123` means the MR exists on the host. **Go to the host before touching the local diff.**
In order:

1. **MCP for that host**, if this session has one (`mcp__gitlab__*`, `mcp__github__*`). Add the tools
   you use to `allowed-tools` for the session; the frontmatter can't list servers that may not exist.
2. **CLI**, otherwise:
   ```bash
   glab mr view <ref> --comments   &&  glab mr diff <ref>    # GitLab
   gh pr view <ref> --comments     &&  gh pr diff <ref>      # GitHub
   ```
3. **Neither reachable** (no MCP, CLI missing or unauthenticated, host unreachable) → fall back to
   `wf-diff.sh` below and **say so in the Step 4 output**: the review ran against the local branch,
   not against the published MR.

From the MR, carry into Step 3: **title and description, target branch, source branch and its head
SHA, state, CI/pipeline status, and existing review comments**.

**Then compare the MR's head SHA against the local branch.** If they differ, say which way and review
the MR's diff — the local tree may hold unpushed commits, or the MR may be ahead of it. Same for the
target branch: if the MR targets something other than the project's base branch, the MR's target
wins.

**Why the host first:** the link is not a label. Without it the review is blind to the MR's real
state — a wrong target branch, a red pipeline, unpushed local work, and comments other reviewers
already left (which it will then repeat back at the author).

### 1b — The diff

```bash
~/.claude/scripts/wf-diff.sh --log --fetch
~/.claude/scripts/wf-diff.sh --stat
~/.claude/scripts/wf-diff.sh
```

**The first `wf-diff.sh` call of the stage carries `--fetch`.** It refreshes `origin/<base>` (the
remote-tracking ref only — no local branch, no merge, no working-tree change) so the fork point is
computed against the real base rather than a stale local one. If it warns that the local base is
behind, **that warning is the whole point** — without the refresh the diff would have carried other
tickets' merged commits as if this feature had written them. Do not silence it and do not "fix" it
by pulling the base branch.

If `$ARGUMENTS` carries a specific branch, add `--branch [branch]` to each call. If 1a resolved an
MR whose source branch is not the current one, pass that branch here.

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

Two reviewers exist because they cover different things, not because two passes are safer:

| | `/code-review` (this step) | Step 3 Agent |
|---|---|---|
| Bugs, security, performance | ✅ | excluded |
| Simplification, reuse, efficiency | ✅ | excluded |
| Contrast against `plan.md` + acceptance criteria | can't — doesn't read them | ✅ |
| `related_projects` contracts against the other repo's real source | can't | ✅ |
| Project conventions, sister feature, existing helpers | can't | ✅ |
| Recorded tech debt and deviations from the plan | can't | ✅ |

Each one catches findings the other structurally cannot. Running both is right for a diff with new
logic. Running both on *every* diff is not.

**Decide which ones run, and say which you chose in the output:**

- **New or changed behaviour** → both. The Agent alone will not find a race in an abort path.
- **Pure structural change** — verified move, rename, extraction with no behaviour delta and no test
  edits → **Agent only**. There is no new logic for a generic reviewer to find bugs in.
- **No `plan.md` / no `refinement-summary.md`** (a retroactive ticket, an ad-hoc MR) →
  **`/code-review` only**. The Agent has nothing to contrast against; its whole remaining scope is
  the part that needs those files.
- MR focused on security → add `/security-review`.

**Run it and wait for it to finish before launching Step 3.** Then paste its findings into the Step 3
prompt under `**Already reported by /code-review:**`.

```
/code-review high
```

**Why sequential:** the "if `/code-review` already reported a finding, don't repeat it" rule is
unenforceable when the two run in parallel — neither can see the other's output. It has already
failed in practice: both reviewers independently reported the same abort race in different words,
and the author had to reconcile them by hand. Waiting costs wall-clock time once; deduplicating two
reports by hand costs it every round.

The scope exclusion below (bullets 1-3 of the line-by-line review) is static and applies regardless.
It has also been violated in practice — the Agent reported a correctness bug it was told to skip —
so it is restated as a hard rule in the Step 3 prompt, not as a hint.

If `/code-review` isn't available in this environment, continue to Step 3 with the full scope (the
prompt's "Line-by-line review" section) and note it in the output.

## Step 3 — Launch the review Agent

Use the **Agent tool** with the following prompt:

**Pass `model` explicitly**, taking it from the `model=` line that `context` printed in Step 0 (or `~/.claude/scripts/wf-lib.sh model mr-review`):

```
Agent(model: "<value from wf-lib>", prompt: ...)
```

Without it the agent inherits the session's model, which makes this stage's output depend on an unrelated setting rather than on a decision. The default is `opus`: this stage carries judgment the rest of the cycle rests on. A project can override it with a `models` block in `config.json`.


---
**AGENT PROMPT:**

You are a senior engineer doing a code review of an MR. Your goal is to find real problems — not to give generic feedback.

**MR context:**
[contents of refinement-summary.md and plan.md]

**Published MR** (from Step 1a; omit this block if the MR was not reachable and the diff is local):
- Title / description / target branch / state / pipeline status
- **Comments already left by other reviewers** — treat each as covered. Do not re-report it. Where
  the diff does not address one, flag it as unaddressed instead of restating it as your own finding.

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
**If Step 2.5 ran `/code-review`, bullets 1-3 are OUT OF YOUR SCOPE.** Not "avoid duplicating" —
do not report them at all, even if you find something real there, and even if you reached it from
the acceptance-criteria angle rather than by reading for bugs. If you believe a bug in that band is
severe and `/code-review` missed it, add it under a single `⚠️ Outside my scope, reported anyway`
heading with one line of justification. Anything else in bullets 1-3 gets dropped.

Evaluate in order of importance:
- ~~Bugs and incorrect logic~~ *(`/code-review`'s — do not report)*
- ~~Security — inputs, auth, exposed data~~ *(`/code-review`'s — do not report)*
- ~~Performance — N+1, re-renders, expensive operations~~ *(`/code-review`'s — do not report)*
- **Tests: coverage gaps against the refinement's edge cases** — not generic, but against the cases the ticket identified
- **Modified contracts and their consumers**, including those in other repos

### 3. Side effects
- Are there contracts (API, types, events) being modified that have consumers?
- Are there migrations that could affect existing data?
- Does the diff touch state/storage/a contract shared with some `related_project` (config.json)?
  **Read `{workflowDir}/contracts.md` first** — `/wf-analyze` already resolved this and recorded both
  sides with `file:line`. Re-verify only the entries the diff actually touches; do not re-derive the
  whole thing. If the file says `No shared surfaces`, skip this bullet entirely. If it does not exist
  (the ticket predates it, or analyze never ran), do the verification and **write the file** so the
  next stage inherits it instead of paying for it again. If `related-check` reported a broken path,
  every claim about that repo is `NOT VERIFIABLE` — say so, don't fill it from notes. A diff that's correct in *this* repo's logic can still be broken if the other side of the contract (an external system) does something different from what was assumed — that point can't be approved by looking at this diff alone.

## Required output

```markdown
## Code review — [MR name]

### 📋 Executive summary
[1-2 lines: what the MR does and the overall verdict]
[source: published MR (host) or local diff — and, if local, why the host was not reachable]

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
