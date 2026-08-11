---
description: "Writes missing tests, assesses coverage and prepares the pre-MR checklist."
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, TodoWrite
---

Your role is to review the existing tests, identify gaps and write the missing ones. At the end, the pre-MR checklist.

## Step 0 — Ticket context

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage test
```

If `context` fails, ask for the ticket and write `.claude/workflow/state.json` before retrying.

**Language:** address the user in the language reported as `lang` by `context` (`en` by default). Everything written to a file — tests, code, comments — is always in English.

## Step 1 — Review the existing tests

Read `{workflowDir}/plan.md` to know which files were modified.

For each modified module:
- Find the corresponding test file
- Read the existing tests to understand the project's pattern

## Step 2 — Gap analysis

Identify what's missing:

**Happy paths:** is the main flow tested?
**Error cases:** do the critical errors have a test?
**Edge cases:** are the edge cases identified in refinement covered?

Show the gap analysis to the user before starting to write:
```
📊 Gap analysis:
✅ Covered: [list]
❌ Missing: [list]
```

Ask: "Shall we start writing the missing tests?"

## Step 3 — Write the tests (delegated)

Step 2 decided *which* gaps matter — that is judgment, and it stayed with you. Writing the tests once the gaps are agreed is pattern-following against the project's existing tests, and the result is checkable by running it in Step 5. Delegate it.

**Pick the agent by stack** (`config.json` → `stack`):

| Stack | Agent |
|---|---|
| React Native | `rn-testing` |
| ML / CV | `ml-testing` |
| anything else | a general Agent with `model` from `~/.claude/scripts/wf-lib.sh model test` (default `sonnet`) |

The dedicated agents already declare their own model and carry the stack's testing conventions, so don't override `model` when using them — that is what their frontmatter is for.

Give the agent the agreed gap list from Step 2, the paths of the existing tests to mirror, and the principles below. It has no context otherwise.

**A delegated test that passes is not automatically a good test.** Read what comes back before Step 5, and check the two things a green run does not: that it asserts the behavior the gap described, and that it fails for the right reason. A test written to match a pattern can pass while asserting nothing.

**Principles** (include these in the agent's prompt):
- Read the project's existing tests before writing (follow the same pattern)
- Sociable tests: don't mock child components, only external services and APIs
- Use the project's test utilities (existing factories, helpers, fixtures)
- One test per behavior, not per function

**Order:**
1. Happy path of the main flow
2. Critical error cases
3. Edge cases from refinement

## Step 4 — E2E (optional assessment)

Once the unit/integration tests are done, assess whether E2E coverage applies:

**E2E applies when:**
- It's a business-critical flow (login, checkout, booking)
- It's a chained multi-screen flow
- It's a regression that already happened in production

**E2E doesn't apply when:**
- They're minor visual changes
- It's internal logic with no user flow
- The flow is already covered by existing E2E

Report the assessment to the user and ask whether they want the E2E written if it applies.

## Step 5 — Run the tests

While writing, run only what you're touching (adapt to the stack: `npm test -- --testPathPattern=X`, `pytest tests/X -v`, `php artisan test --filter=X`).

When finished, the full run comes from the project's config:

```bash
~/.claude/scripts/wf-checks.sh
```

If any test fails, diagnose and fix it before continuing. This is the same gate `/wf-validate` runs: if it passes here, it won't be a problem there.

## Step 6 — Pre-MR checklist

```
✅ Pre-MR checklist:

Project DoD:
[items from dod_checklist in config.json]

Tests:
- [ ] Unit/integration tests written and passing
- [ ] E2E assessed ([applies/doesn't apply] — [reason])
- [ ] No tests in skip/xdescribe without justification

Code:
- [ ] No debug console.log / print / dd()
- [ ] Linter passes with no errors
- [ ] Build passes with no errors

Other:
- [ ] Tech debt recorded in plan.md
- [ ] Breaking changes documented
```

If the ticket touches state/storage/a contract shared with some `related_project` (config.json) — check `plan.md`/`review-findings.md`/`validation-*.md` to confirm it — add to the checklist:
```
- [ ] Manually validated in a browser/real environment against the real external system ([related_project]), not just unit tests/mocks
```
The agent cannot tick this one itself: it's a gate requiring explicit confirmation from the user, because no in-repo test or diff review can verify the real behavior of a system outside this repo.

## Step 7 — Record the gaps found

For each gap the coverage analysis exposed that was **not** a trivial missing test — an uncovered edge case, a behavior the plan didn't account for:

```bash
~/.claude/scripts/wf-event.sh finding \
  --category [slug] --severity [high|medium] \
  --stage_origin [refine|analyze|implement] --stage_detected test \
  --detected_by gate --summary "[one line]"
```

An edge case that only shows up here almost always originated in `refine` (nobody asked for it) or in `analyze` (the plan didn't account for it). Attributing it to `implement` because that's where the symptom appears is the mistake that makes the origin metric useless.

When done, suggest: "Next: `/wf-mr-desc` for the MR description and `/wf-mr-review` for the final review."
