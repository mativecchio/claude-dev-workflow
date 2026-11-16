---
description: "Quick track for small changes: triage against three criteria, a short quick.md written before the code, the fix, a test that reproduces it, and the project's checks — without refine/analyze/review-plan. Escalates to the full flow on its own when the change outgrows it. Usage: /wf-quick [ticket] [description]"
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, TodoWrite, TodoRead
---

Your role is to take a small change from problem to verified fix with the same documentation the
full flow leaves behind, only shorter. The full flow (refine → analyze → review-plan → implement)
exists to settle decisions before code; a small fix has almost none to settle, and running the
whole cycle for it costs more than the fix. What it must not lose is the record: what was wrong,
why, what changed, and how it was verified. That record is `quick.md`.

The track is only for changes that really are small. Its limits are checked twice — before the
code (triage) and after it (measured size) — and crossing them sends the change to the full flow
with `quick.md` as its starting point, never quietly keeps it here.

## Step 0 — Ticket and context

**Language:** address the user in the language returned by `~/.claude/scripts/wf-lib.sh language`
(`en` by default). Everything written to a file — `quick.md`, code, comments, commits — is always
in English.

Resolve the ticket:
- `$ARGUMENTS` starts with a ticket key (`MA-123`, `BC-1522`) → that one.
- Otherwise, the active ticket from `.claude/workflow/state.json`, **only if** its directory has no
  `plan.md` and no `refinement-summary.md` (a ticket already in the full flow is not hijacked).
- Otherwise, ask for the key once. A change with no ticket gets `QUICK-YYYYMMDD-<slug>`, with
  `<slug>` = three or four words of the description in kebab-case.

Then:

```bash
mkdir -p .claude/workflow/<ticket>
# set it active, preserving the rest of the root state
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage quick
```

Write `{ "activeTicket": "<ticket>" }` into `.claude/workflow/state.json` before `context` if it
points elsewhere. If the ticket exists in the tracker and an MCP for it is available, read it; it
is the source of the expected behaviour, not the summary in `$ARGUMENTS`.

Branch: if the current branch is the base branch (`wf-lib.sh base`) or a protected one, offer
`git checkout -b <ticket>-<slug> <base>` (or the hotfix base the project's `CLAUDE.md` names for
deployed-version fixes) and wait for the answer. Save it with
`wf-lib.sh set-state branch '"<name>"'`.

## Step 1 — Understand before judging

Read the code involved and find the root cause (for a bug) or the exact spot to change (for a
tweak). Reproduce it when the project lets you: a failing test, a log, the running app through the
tools the session has. Do not edit anything yet.

## Step 2 — Triage

Answer the three criteria with evidence from Step 1. **All three** must hold for the quick track.

| # | Criterion | Holds when |
|---|---|---|
| 1 | **No risk surface** | The change touches none of: a new screen or flow, navigation, an API or event contract with another system, the shape of shared state (store, database schema, persisted data), a new dependency, authentication/authorization, payments, personal data, real-time events. |
| 2 | **Small** | Estimated at or under the quick limit: `quick.max_prod_lines` production lines and `quick.max_prod_files` production files from the project config (100 and 3 by default). Tests, fixtures and translations do not count. |
| 3 | **Unambiguous** | The expected behaviour is already known — a bug with a clear reproduction, a copy or style fix, a one-place adjustment. If you would have to ask "what should happen when…?", it is not. |

Show it:

```
⚡ Quick triage — <ticket>

  1. Risk surface   ✅ none            | ❌ <what it touches>
  2. Size           ✅ ~N lines, M files (limit 100 / 3)
  3. Unambiguous    ✅ <expected behaviour in one line>

  → Quick track            (or)   → Full flow recommended: <criterion and why>
```

```bash
~/.claude/scripts/wf-event.sh quick_triage --verdict quick        # or: --verdict full --failed_criteria "1,3"
```

**If any criterion fails**, recommend the full flow and offer to start it with `/wf-refine`, taking
what Step 1 found as input. The user decides: if they keep the quick track anyway, write their
reason under *Triage override* in `quick.md` — the override is recorded, never silent. A failed
criterion 1 deserves the strongest wording: those are the changes whose mistakes reach production
data, money or other systems.

## Step 3 — `quick.md`, before the code

Write `{workflowDir}/quick.md`:

```markdown
# <ticket> — <one-line title>

**Track:** quick · **Branch:** <branch> · **Date:** <YYYY-MM-DD>

## Problem
<What the user sees or what is wrong, and how to reproduce it.>

## Expected behaviour
<One or two lines.>

## Root cause
<For a bug: the cause, with file:line. For a tweak: where the change goes and why there.>

## Fix
<The approach in two to four lines, and the alternative rejected if there was one.>

## Files
| File | Change |
|---|---|

## Tests
- Regression: <the test that fails before the fix and passes after, with its path>
- E2E: <spec added/updated in the E2E project, or why it does not apply>

## Risk
<What else could be affected and how that was checked. "None" only with a reason.>

## Triage
<The three criteria and their answers, one line each.>
<!-- Triage override: only when the user kept the quick track against a failed criterion -->

## Verification
<Filled in at Step 5.>
```

Show the Root cause and Fix sections and ask once: **"Is this right? Shall I implement it?"**
Wait for the answer. This is the only checkpoint before code, and it replaces the plan review.

## Step 4 — Implement

Follow the project's conventions (`CLAUDE.md`, `AGENTS.md`, the guides they point to) exactly as a
full-flow implementation would: the quick track shortens the process, not the standards.

After the edits, measure:

```bash
~/.claude/scripts/wf-diff.sh --quick
```

**Escalate** when it exits `3`, or when the work reveals a risk surface or an open question about
the expected behaviour that triage did not see:

1. Stop editing. Do not revert what is there.
2. Tell the user what crossed the line (`weight_prod`/`files_prod` against the limits, or the
   surface or question found).
3. ```bash
   ~/.claude/scripts/wf-event.sh quick_escalated --reason size --weight_prod N --files_prod M
   ```
4. Add an *Escalated* section to `quick.md` with that reason, and offer `/wf-refine`, which reads
   `quick.md` as its starting material. Do not continue on the quick track unless the user says so
   explicitly, and then record it under *Triage override*.

## Step 5 — Tests and checks

Every quick change leaves a test behind:
- **A bug fix** gets a regression test that fails without the fix and passes with it. Show that it
  fails first when it is cheap to do (run it before applying the fix, or with the fix stashed).
- **A tweak** gets the test that pins the new behaviour, or a reason it cannot have one.
- **E2E:** if `config.json` has an `e2e` block and the change is visible to the user, add or update
  the spec in that project (its `specs`/`pageobjects` paths and commands are in the block) for the
  platforms it lists. When it cannot be done now, say so in `quick.md` under *Tests* and add the
  pending spec to the project's `tech_debt_log` — never drop it silently.

Then run the project's checks, capping workers to the machine budget
(`~/.claude/scripts/wf-resources.sh workers`):

```bash
~/.claude/scripts/wf-checks.sh
```

A failure caused by the change is fixed here. A failure that already existed on the base branch is
reported as such (verify it on the base before saying so) and recorded in `quick.md`, not hidden.

## Step 6 — Close the record

Fill *Verification* in `quick.md`: the commands run and their result, the regression test shown
failing then passing, the E2E outcome, and anything checked by hand and how. Update *Files* with
what really changed. Do not record commit hashes (they are rewritten by rebases; see `/wf-commit`).

Then:

```
✅ Quick change ready — <ticket>
   quick.md: .claude/workflow/<ticket>/quick.md
   Size: <weight_prod> lines / <files_prod> files (limit 100 / 3)
   Tests: <regression test> · E2E: <spec or reason>
   Checks: <passed | failures and their origin>

Next: /wf-commit → /wf-deploy (or /wf-mr-desc for the MR)
```

`/wf-commit`, `/wf-mr-desc` and `/wf-mr-review` read `quick.md` when the ticket has no `plan.md`.
