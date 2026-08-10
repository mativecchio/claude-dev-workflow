---
description: "Post-implementation validation gate. The user chooses which validators to enable. Runs in an isolated context. Loops up to 3 iterations before escalating."
allowed-tools: Read, Glob, Grep, Bash, Agent, TodoWrite, TodoRead
---

Your role is to run automated validations over the implementation's diff. The user chooses which validators to enable.

## Step 0 — Ticket context

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage validate
```

If `context` fails, ask for the ticket and write `.claude/workflow/state.json` before retrying.

**Language:** address the user in the language reported as `lang` by `context` (`en` by default). Everything written to a file — validation reports, plan.md, code — is always in English.

## Step 1 — Validator selection

Ask the user which validators to enable:

```
What do you want to validate? (pick one or more)

1. 🏛️  Architecture — consistency with the project's patterns
2. 🧪 Tests — coverage of critical cases
3. ⚡ Performance — unnecessary re-renders, N+1 queries, expensive operations
4. 🔒 Security — unsanitized inputs, auth, exposed data
5. ♿ Accessibility — basic a11y (UI changes only)
6. 📱 Runtime — bring the app up and verify the real flow
7. ✅ All
```

Wait for an answer before continuing.

**About 6 (Runtime):** offer it proactively when the diff touches UI, navigation or shared state — those are the cases where reading the diff isn't enough. It requires the app to be running and an MCP to be available (`metro` for React Native, `claude-in-chrome` for web). If there's neither, say so and continue without that validator instead of pretending it was validated.

## Step 2 — Deterministic checks (before any agent)

```bash
~/.claude/scripts/wf-checks.sh
```

Runs lint, types and tests from `config.json`. **If any of them fails, stop here:** show what failed and go back to `/wf-implement`. Don't launch the Agent.

The reason is economy and precision: a linter answers "is there a console.log?" exactly and for free, while an agent opines on the same thing with a chance of a false positive. The agent is reserved for what only it can do — architecture, external contracts, security.

Exit 2 means the project has no `checks` configured: report it once, suggest adding them with `/wf-init`, and continue.

## Step 2.5 — Get the diff

```bash
~/.claude/scripts/wf-diff.sh --stat
~/.claude/scripts/wf-diff.sh
```

It resolves the merge-base against the project's base branch on its own, plus the uncommitted-work case. There's no need to reason about the range.

## Step 3 — Launch the validation Agent

Use the **Agent tool** with the following prompt (adapted to the chosen validators):

---
**AGENT PROMPT:**

You are a senior engineer doing a quality review on freshly implemented code. Iteration [N] of a maximum of 3.

**Diff to review:**
[full diff]

**Original plan:**
[contents of {workflowDir}/plan.md]

**Stack:** [stack from the config]

**Active validators:** [list of chosen validators]

## Instructions per validator

**🏛️ Architecture:**
- Does the code follow the project's patterns (sister feature)?
- Were existing helpers used instead of reimplementing?
- Is the separation of concerns correct?

**🧪 Tests:**
- Are the happy paths covered?
- Do the critical error cases have tests?
- Are the tests sociable (they don't mock child components, only external services)?

**⚡ Performance:**
- Are there unnecessary re-renders in components?
- Are there N+1 queries or API calls inside loops?
- Are expensive operations memoized where appropriate?

**🔒 Security:**
- Are user inputs sanitized?
- Is sensitive data exposed in logs or responses?
- Do the endpoints have the right auth?

**🔗 External integration (always run, independent of the chosen validators):**
- Does the diff touch state/storage/a contract that a `related_project` (config.json) also reads or writes? If so, and that project has a local `path`, was the real behavior verified by grepping/reading that path (merge vs replace, types, format) instead of assuming it?
- This CANNOT be approved from the diff alone — if an external integration is involved and it wasn't verified against the real source code, flag it explicitly as an unverifiable risk, not as approved.

**♿ Accessibility:**
- Do images have alt text?
- Do interactive elements have accessible labels?
- Is the contrast adequate?

## Required output

```markdown
## Validation — Iteration [N]

### ❌ Failed
#### [Validator]
- **File:** [path]
- **Problem:** [description]
- **Correction:** [what to do]
- **Severity:** [high/medium]

### ⚠️ Warnings
[minor warnings]

### 🔗 Risk not verifiable from the diff
[if the diff touches an integration with a related_project and it couldn't be verified against its real source code: what remains unconfirmed and why. If not applicable: "None" / "N/A — no external integration in this diff"]

### ✅ OK (don't touch)
[what's fine]

### Verdict
[APPROVED / APPROVED WITH UNVERIFIABLE RISK / CHANGES REQUIRED]
```

A verdict of "APPROVED" never implies that behavior against an external system is confirmed — if there's a non-empty "🔗 Risk not verifiable from the diff" section, use "APPROVED WITH UNVERIFIABLE RISK", not a bare "APPROVED".

---

## Step 3.5 — Runtime validation (only if validator 6 was chosen)

**Runs in the main context, not inside the Agent.** Subagents aren't guaranteed access to MCP tools, and this validation depends on them. Run it here, after the Agent returns, and add the findings to the output.

The other validators reason about the diff. This one observes the app running, which is the only way to catch a certain class of defect: an execution order between effects, state left inconsistent when returning to a screen, a request that fires twice. `wf-analyze` tries to cover that by asking the user the expected order — here it's observed directly.

**React Native (MCP `metro`):**
```
1. mcp__metro__list_devices        → confirm there's a connected target
2. mcp__metro__get_bundle_errors   → if there are bundle errors, stop and report
3. mcp__metro__list_routes / get_current_route → locate the screen affected by the diff
4. mcp__metro__open_deeplink or tap_element → navigate to it
5. mcp__metro__take_screenshot     → visual evidence of the final state
6. Depending on the kind of change:
   - state:      mcp__metro__get_redux_state, get_redux_actions
   - network:    mcp__metro__get_network_requests, get_response_body
   - errors:     mcp__metro__get_errors, get_console_logs
   - re-renders: mcp__metro__get_react_renders
   - a11y:       mcp__metro__audit_accessibility
```

**Web (MCP `claude-in-chrome`):** navigate to the affected route, `read_console_messages` and `read_network_requests`, screenshot of the final state.

**What to look for**, in order:
1. Does the changed flow complete without an error?
2. Is the state consistent after leaving and returning to the screen?
3. Are there duplicate requests, or requests firing when they shouldn't?
4. Are there new console errors or warnings compared to before the change?

**Rules:**
- If the app isn't running, ask the user to bring it up. Do **not** try to build from here.
- If something couldn't be verified, say so explicitly. "The app couldn't be brought up" is an honest result; declaring validated what wasn't observed is not.
- Don't touch elements that trigger native dialogs or confirmation modals: they block the automation session.

**Output**, to be added to Step 3's output:
```markdown
### 📱 Runtime
- **Flow verified:** [what was navigated, with what data]
- **Observed:** [state, requests, errors — with concrete evidence]
- **Screenshot:** [path]
- **Not verifiable:** [what couldn't be observed and why]
```

> **Explicit hypothesis** (`docs/plan-harness-migration.md` Phase 3): this validator isn't grounded in data. The bet is that races and state defects are better caught by observing the runtime than by reasoning over the diff. If that difference doesn't show up at 15-20 tickets, it gets removed.

## Step 4 — Post-validation decision

**If APPROVED:**
Show the result and suggest: "Next: `/wf-test`"

**If CHANGES REQUIRED:**
Show the full structured feedback, and for each "❌ Failed" finding (and optionally each "⚠️ Warning" if the user wants to review those too) offer an individual picker:
```
[N]. [file:line] — [problem summary] (severity: [high/medium])
    What do we do?
    a) Implement the fix
    b) Ignore (with a reason)
    c) Mark as tech debt (record in plan.md, don't implement now)
```
Wait for the decision on each item (they can be answered all at once, e.g. "1a, 2c, 3b") before moving to `/wf-implement`. Don't assume "implement everything" by default.

**Record each finding and its decision.** The picker already produced the data; this only writes it down:

```bash
# one per "❌ Failed"
~/.claude/scripts/wf-event.sh finding \
  --category [slug] --severity [high|medium] \
  --stage_origin [analyze|implement] --stage_detected validate \
  --detected_by [gate|user] --summary "[one line]"

# and the decision the user made for that finding
~/.claude/scripts/wf-event.sh finding_decision \
  --finding_ref "[same slug or index]" --decision [implement|ignore|tech-debt]
```

`stage_origin` is where the defect was **introduced**: a guard missing because of an incomplete plan originated in `analyze`, not in `implement`, even though the symptom shows up in the code. That's the difference between "the implementer got it wrong" and "the plan didn't ask for it", which are different problems with different gates.

`finding_decision` is what later lets you tell a real finding from a noisy one: a category that's systematically ignored is a validator shouting too much, and that's only visible if the decisions are recorded.

Move to `/wf-implement` **only with the list already decided** (the items marked "a"), so that command skips its starting checkpoint (see `wf-implement` Step 2) — the decision about what to implement was already made here, no need to ask "Shall we start?" again.

Keep track of iterations. If 3 are reached without approval, escalate:
**"⚠️ 3 iterations reached without approval. Manual review required before continuing."**
