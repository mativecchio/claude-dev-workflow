---
description: "Retrospective of the completed development cycle. Analyzes the session, extracts lessons and proposes workflow improvements. Saves to flow-history.json."
allowed-tools: Read, Write, Edit, Bash, Glob, TodoRead
---

Your role is to analyze how the development cycle went, extract lessons and propose concrete improvements to the workflow system.

## Step 0 — Ticket context

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage retro
```

If `context` fails, ask for the ticket and write `.claude/workflow/state.json` before retrying.

**Language:** address the user in the language reported as `lang` by `context` (`en` by default). Everything written to a file — flow-history.json, improvements.md, command edits — is always in English.

## Step 1 — Gather session data

Read:
- `{workflowDir}/state.json` → stages visited
- `{workflowDir}/plan.md` → what was implemented and recorded deviations
- `{workflowDir}/review-findings.md` → findings from the plan review
- `~/.claude/workflow/flow-history.json` → history of previous sessions (if it exists)

## Step 2 — Session analysis

Evaluate:
- **Completed stages** and how many iterations each one took
- **Detected rework**: stages that repeated, mid-stage corrections
- **Friction**: moments where the flow was interrupted or unclear
- **Deviations from the plan**: what changed versus the original plan and why
- **Recorded tech debt**: what was left pending

If there are 3+ entries in `flow-history.json`, cross-reference the history:
- Which stages always require multiple iterations?
- Are there recurring anomalies?
- Are there findings repeating across different tickets?

## Step 3 — Retrospective report

Show the user:

```
## Retrospective — [ticket/task]

### Session summary
- Stages visited: [list]
- Rework: [description or "none"]
- Friction detected: [description or "none"]

### Lessons
1. [lesson 1]
2. [lesson 2]

### Patterns from history (if applicable)
- [recurring pattern detected]

### Proposed workflow improvements
| Component | Problem | Proposed change |
|---|---|---|
| [wf-analyze] | [description] | [concrete change] |
```

## Step 4 — Save to flow-history

Ask the user whether they want to save this session to the history.

If they accept, append an entry to `~/.claude/workflow/flow-history.json`:
```json
{
  "date": "[ISO date]",
  "project": "[project name]",
  "ticket": "[ID or description]",
  "stages_completed": ["[list]"],
  "iterations": {"[stage]": "[N]"},
  "key_findings": ["[up to 3 findings]"],
  "anomalies": ["[deviations or friction detected]"]
}
```

## Step 4.5 — Close the ticket in telemetry

**This step is what gives everything above its point.** `/wf-analyze` recorded an estimated score; without the actual one, that score can never be calibrated and the rubric stays decorative forever.

Read `{workflowDir}/complexity.json` (written by `/wf-analyze`) and the real iterations from the ticket's `state.json`:

```bash
~/.claude/scripts/wf-lib.sh state '.iterations'
~/.claude/scripts/wf-event.sh ticket_closed \
  --iterations_total [N] \
  --complexity_actual [the points you'd give it today, with the ticket finished] \
  --iterations_by_stage '{"analyze":2,"implement":3}'
```

`complexity_actual` is scored with **the same §5.2 rubric**, now with the real data: the files actually touched, the layers that turned out to be involved, whether shared state showed up that hadn't been anticipated. It isn't "how expensive it felt" — it's the same table, with the values you only know at the end.

Scoring it from memory or rounding it toward the estimate ruins the data: the calibration error is precisely the difference between the two, and if the actual is adjusted to match, the metric measures zero by construction.

After closing, see what the history says:
```bash
~/.claude/scripts/wf-stats.sh
```

## Step 5 — Apply improvements (with approval)

If there are proposed workflow improvements, ask:
**"Do you want me to apply any of these improvements to the system's commands?"**

If the user accepts an improvement:

1. **Resolve the source repo.** Read `repo_path` from `~/.claude/workflow/config.json`.
   - If it exists and the directory is present → `{repoPath}` is the edit target.
   - If not → warn: "There's no `repo_path` in the global config. Run the repo's `install.sh` to configure it." and edit `~/.claude/commands/` only as a fallback, noting that the change will be lost on the next install.
2. Identify the file under **`{repoPath}/commands/wf-*.md`** — never under `~/.claude/commands/`, which is an installation target, not the source.
3. Show the proposed change before applying it.
4. Ask for a final confirmation.
5. Apply it with the Edit tool on the repo's file.
6. **Record the evidence** in `~/.claude/workflow/improvements.md` (format in the file's header). Rule §0 of the brainstorm: if the evidence can't be written down — `file:line` or the concrete query over `events.jsonl` — the change isn't applied.
7. **Reinstall** so the change takes effect:
   ```bash
   "{repoPath}/install.sh"
   ```
8. Verify it's in sync:
   ```bash
   "{repoPath}/install.sh" --check
   ```

Remind the user that the change is in the repo's working tree, uncommitted.
