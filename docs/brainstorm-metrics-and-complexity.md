# Measurement, complexity and task partitioning system

> Design document that came out of a brainstorm. It defines **what to measure**, **how to capture it without depending on the model's memory**, **how to estimate complexity** and **how to split large tasks**.
> Status: design agreed, pending implementation.

---

## 0. Grounding rule

**No change is proposed or applied without explicit evidence.** This applies to changes in a project's code and to changes in the workflow itself.

Every suggestion must cite one of these two sources:

| Source | Acceptable form of the citation |
|---|---|
| **Task in progress** | `file:line` from the codebase, a concrete section of `plan.md`, a finding from `review-findings.md`, or the output of a command (test, grep, diff) |
| **Measurements** | a concrete query over `events.jsonl` — event category, number of tickets involved, period |

Formulations forbidden on their own: "it would be better", "it's best practice", "it's advisable", "this tends to happen". They are admissible **after** the evidence, never in its place.

Minimum threshold for proposing a workflow change from data: **3 distinct tickets** with the same pattern. Below that it's an anecdote and gets recorded as an observation, not a proposal.

Every change applied to the workflow is recorded in `improvements.md` with its evidence. If the evidence can't be written down, the change isn't applied.

---

## 1. Goal

Reduce the **number of iterations needed to close a task**.

Motivating case: a ticket that took 7-8 rounds until analyze, implement, test and validate all closed without failures. The hypothesis to validate with data is that these weren't 8 independent defects, but 1-2 defects with a **long leak** (originated early, detected late) plus their cascading rework.

Operating principle: **instrument first, diagnose later.** The flow isn't changed on intuition. Evidence accumulates and only then is something proposed.

---

## 2. Metrics

### 2.1 Primary metric

**Iterations to closure**, broken down by ticket and by command.

An *iteration* is a **re-entry** into a stage already visited. They're counted separately:
- `iterations.total` — re-entries across all stages
- `iterations.by_stage` — `{"analyze": 2, "implement": 3, "validate": 3}`

### 2.2 Leak distance

Raw, the iteration count mixes two opposite phenomena:

- **Cheap iteration** — a stage catches a defect originated in that same stage. The system working.
- **Expensive iteration** — the defect originated in `refine` and `/wf-test` caught it. Four stages built on a broken premise.

Stage order for the calculation:

| Stage | Index |
|---|---|
| refine | 1 |
| analyze | 2 |
| review-plan | 3 |
| implement | 4 |
| validate | 5 |
| test | 6 |
| mr-review | 7 |

`leak_distance = idx(stage_detected) - idx(stage_origin)`

It's directly actionable: high leak from `refine` → the problem is the DoD, not the model implementing. High leak from `analyze` → the analysis isn't mapping impact. Those are fixes in different files.

### 2.3 Full catalog

Ordered by value/effort ratio. The ones marked **derived** don't depend on the model reporting honestly — they're computed from files and git.

| # | Metric | Source | What it detects |
|---|---|---|---|
| 1 | **Scope drift** *(derived)* | `git diff --name-only` vs the table in `plan.md` | "a change was made that nobody asked for" |
| 2 | **Plan churn** *(derived)* | edits to `plan.md` after approval in `/wf-review-plan` | analyze missed something |
| 3 | **Detector: gate vs user** | `detected_by` field on each finding | gate health — if the user's share rises, the gates are degrading |
| 4 | **Signed calibration error** | `complexity_estimate` vs actual iterations | systematic underestimation bias (fixed with a constant, not by redesigning the rubric) |
| 5 | **Recurrence by category** | `category` of findings across tickets | systemic problem → grounded input for `/wf-improve` |
| 6 | **Abandoned tickets** *(derived)* | ticket with no events for N days and no `mr_opened` | invisible today; probably the worst cases |
| 7 | **Cost per stage** *(derived)* | turns + tool calls per stage | which step actually costs |
| 8 | **MR weight** *(derived)* | see §6 | real review size |

### 2.4 On measuring time

**The clock lies in interactive sessions.** If `/wf-analyze` reports 4 hours, the likeliest explanation is that the laptop was closed.

`ts` is recorded on every event — it's free and useful for ordering — but the *stage cost* metric is **turns + tool calls + re-entries**, never minutes. Minutes are kept as secondary data and interpreted only in aggregate, discarding outliers.

---

## 3. Data capture

### 3.1 Why two layers

Precedent: `flow-history.json` sits at `{"entries": []}`. The existing mechanism (step 4 of `/wf-retro`, opt-in and manual at the end of the cycle) **never ran even once**. Repeating that pattern produces another empty file.

| Layer | Captures | Strength | Limit |
|---|---|---|---|
| **Hooks** | mechanical skeleton: which command started, when, turns, tool calls, re-entries | deterministic, can't be skipped, doesn't lie about counts | doesn't understand semantics |
| **`wf-*` commands** | semantic fields: why there was a re-entry, which defect it was, where it originated | it's the information that matters | it's an instruction in a prompt; the model can skip it |

**The real reason for using both:** it's the only combination that lets you **detect that the log is incomplete**. If the hook records a re-entry into `analyze` and there's no semantic event explaining it, that itself is data — you know you lost the cause. With only the semantic layer you never know whether a clean cycle was genuinely clean or the model simply didn't log.

### 3.2 Hooks

| Hook | Function |
|---|---|
| `UserPromptSubmit` | detects `/wf-*` in the prompt → emits `stage_start`; if the stage was already marked as visited in the ticket state → emits `stage_reentry` |
| `Stop` | closes the turn → increments `turns` for the active stage |
| `PostToolUse` (Write/Edit) | if the path is `plan.md` and the ticket state is at `review-plan` or later → emits `plan_edit` (feeds plan churn) |
| `PostToolUse` (any) | increments `tool_calls` for the active stage |

The hooks append directly to `~/.claude/workflow/events.jsonl`. They neither read nor block anything in the flow.

### 3.3 Commands

Each `wf-*` command appends its semantic events in its last step:

| Command | Event(s) |
|---|---|
| `wf-analyze` | `complexity_estimate` (§5), `split_suggested` when applicable |
| `wf-review-plan` | `finding` × N (with `stage_origin`, `detected_by`) |
| `wf-implement` | `size_check` at each checkpoint, `size_exceeded` if it trips |
| `wf-validate` | `finding` × N, `finding_decision` (implement/ignore/tech-debt) |
| `wf-test` | `finding` × N |
| `wf-mr-review` | `finding` × N, `mr_opened` with weight |
| `wf-retro` | `ticket_closed` with actual iterations |

---

## 4. `events.jsonl` schema

Append-only. One line = one event. JSONL so it can be appended from a shell hook without parsing the whole file.

```json
{"ts":"2026-08-07T15:32:10Z","project":"bc-app","ticket":"BC-1234","subtask":null,"stage":"analyze","event":"stage_start","source":"hook","data":{}}
```

### Common fields

| Field | Type | Notes |
|---|---|---|
| `ts` | ISO 8601 UTC | |
| `project` | string | project directory name |
| `ticket` | string | e.g. `BC-1234` |
| `subtask` | string \| null | e.g. `sub-1` |
| `stage` | string | `refine`\|`analyze`\|`review-plan`\|`implement`\|`validate`\|`test`\|`mr-review`\|`retro` |
| `event` | string | see the next table |
| `source` | `hook` \| `command` | allows auditing the log's coverage |
| `data` | object | event-specific payload |

### Event types

| `event` | `data` |
|---|---|
| `stage_start` | `{}` |
| `stage_end` | `{turns, tool_calls, duration_s}` |
| `stage_reentry` | `{iteration_n, scope, reason?}` — `scope` is `ticket` (counter persisted in the ticket's `state.json`) or `session` (fallback, lost when the session closes) |
| `complexity_estimate` | see §5 |
| `finding` | `{category, severity, stage_origin, stage_detected, detected_by, summary}` |
| `finding_decision` | `{finding_ref, decision}` — `implement`\|`ignore`\|`tech-debt` |
| `plan_edit` | `{lines_changed, post_approval: true}` |
| `scope_drift` | `{planned_files[], actual_files[], unplanned[], missing[]}` |
| `size_check` | `{weight_prod, weight_tests, threshold}` |
| `size_exceeded` | `{weight_prod, threshold, action}` — `carve`\|`continue` |
| `split_suggested` | `{reason, proposed_subtasks[]}` |
| `split_applied` | `{subtasks[]}` |
| `mr_opened` | `{branch, target, weight_prod, weight_tests}` |
| `ticket_closed` | `{iterations_total, iterations_by_stage, complexity_actual}` |
| `ticket_abandoned` | `{last_stage, days_idle}` |

`detected_by` is `gate` (a workflow command found it) or `user` (you found it). It's the input for metric 3.

---

## 5. Complexity rubric

### 5.1 Why a rubric and not intuition

Asking the model to "estimate complexity from 1 to 13" produces 5 almost every time. The score comes from dimensions that **`/wf-analyze` already computes** in its steps 1-5. It adds no analysis work: it only formalizes what was already produced.

### 5.2 Dimensions and weights

| Dimension | Where it comes from | Values → points |
|---|---|---|
| **Is there a sister feature?** | step 1 | found `0` / partial `3` / **none `6`** |
| Files to touch | table in `plan.md` | 1-3 `0` / 4-8 `2` / 9-15 `4` / >15 `6` |
| Layers crossed (0-6) | step 2 | 0-1 `0` / 2-3 `2` / 4-5 `4` / 6 `5` |
| External projects touched | step 5 | 0 `0` / 1 `3` / 2+ `5` |
| Shared state / races | step 4 | no `0` / yes `4` |
| Gaps in the DoD | `refinement-summary.md` | none `0` / minor `2` / major `5` |
| Infra (migration, env var, feature flag) | Infrastructure section | no `0` / yes `3` |

**Range: 0-34.**

### 5.3 The bet on "sister feature"

This dimension carries disproportionate weight on purpose. Explicit hypothesis, to be validated with data:

> When `/wf-analyze` finds no analogous pattern in the codebase, the model has nothing to copy and starts inventing conventions. That's where the "changes nobody asked for" and the long iteration chains appear.

If at 15-20 tickets the correlation between `sister_feature: none` and iterations doesn't show up, **the weight gets lowered and it's recorded in `improvements.md` with the evidence**. The rubric is a hypothesis, not dogma.

### 5.4 Mapping to Fibonacci points

| Raw score | Points |
|---|---|
| 0-4 | 1 |
| 5-8 | 2 |
| 9-13 | 3 |
| 14-19 | 5 |
| 20-26 | 8 |
| 27+ | 13 |

**Partition threshold: ≥ 8 points → suggest splitting.**

> ⚠️ Every number in §5.2 and §5.4 is **provisional**. They were chosen without data. Their only purpose today is to generate (estimated, actual) pairs to calibrate them later. Revisit at 15-20 closed tickets.

### 5.5 Emitted event

```json
{"event":"complexity_estimate","data":{
  "raw_score": 21,
  "points": 8,
  "dimensions": {
    "sister_feature": {"value":"none","pts":6},
    "files": {"value":11,"pts":4},
    "layers": {"value":4,"pts":4},
    "external_projects": {"value":1,"pts":3},
    "shared_state": {"value":true,"pts":4},
    "dod_gaps": {"value":"none","pts":0},
    "infra": {"value":false,"pts":0}
  },
  "split_recommended": true
}}
```

It's also saved to `{workflowDir}/complexity.json` so later commands can read it without parsing the JSONL.

**The essential part: estimated and actual are stored together.** Without the pair, the score is decorative.

---

## 6. MR weight

### 6.1 Why not "lines changed"

A massive rename is zero review risk. A 40-line change in shared-state logic can be fatal. The metric must approximate **review cognitive load**.

### 6.2 Calculation

```bash
git diff --ignore-all-space --find-renames --numstat <merge-base>..HEAD
```

| Change type | Weight |
|---|---|
| Rename / file moved with no content change | `1` |
| Reindentation, whitespace | `0` (via `--ignore-all-space`) |
| Lockfiles, generated files, snapshots | `0` |
| Production code | actual lines |
| Tests | actual lines, **counted separately** |

Excluded patterns (configurable in `config.json`):
`*.lock`, `package-lock.json`, `yarn.lock`, `*.snap`, `dist/`, `build/`, `*.generated.*`

### 6.3 Tests kept separate: why

A 300-line MR where 220 are tests isn't a big MR, it's a well-covered one. Summing them together makes the system penalize exactly the behavior it wants to reward.

**The threshold applies only to `weight_prod`.**

### 6.4 Threshold

**300 points of production weight.** Provisional, same as §5.4.

---

## 7. Task partitioning

### 7.1 Two decision points, not one

Central observation from the brainstorm:

> *Sometimes the task becomes big once you start developing it and you can't avoid it, because not everything comes out in the first analyses.*

This invalidates the design of deciding only once. If partitioning is evaluated only in analyze, the system catches just the easy cases — the ones you could already see coming. The 7-8 iteration cycles aren't those.

| Moment | Mechanism | Nature |
|---|---|---|
| **analyze** | rubric §5, threshold ≥8 points | a priori, cheap, incomplete by definition |
| **implement** | trip wire §7.2 | a posteriori, over the real diff |

### 7.2 Trip wire

At each file-group checkpoint, `/wf-implement` recomputes `weight_prod` for the accumulated diff. If it projects past the threshold:

**Agreed behavior: (c) + (a).**

- **(c) Record and continue — default.** Appends `size_exceeded`, shows it on screen, **doesn't block**.
- **(a) Cut and stack — offered option.** Closes what's done as a sub-MR against the integration branch and continues on a new branch. Requires what's done so far to be coherent and not broken on its own.

**(b) pause and go back to analyze** is discarded for now: it's the cleanest but it stops everything dead and would apply a hard policy based on a threshold invented without data.

**Reason for the default:** it's consistent with "instrument first". After 15-20 tickets we'll know whether 300 was the right number, whether the trip wire fires too late to be useful, and whether splitting actually reduces iterations or just relocates them. Tightening happens with evidence, per §0.

### 7.3 The trip wire as a calibration instrument

Each firing generates an **(estimated, actual)** pair with the concrete cause of the divergence. It isn't just a size control: it's the mechanism that produces the data currently missing to know whether the rubric works.

### 7.4 Unit of partitioning: nested subtasks

**Subtasks nested under a parent ticket** are chosen, not sibling sub-tickets.

- They share the parent's `refinement-summary.md` and DoD — the requirement isn't fragmented.
- Each subtask runs `analyze → implement → validate` separately.
- Each subtask produces a small MR against the integration branch.

The split happens where it hurts — the analyze/implement/validate cycle, where iterations accumulate — without fragmenting the requirement.

### 7.5 Branching model

```
develop
  └── feature/BC-1234                    ← integration branch
        ├── feature/BC-1234/sub-1        ← small MR → integration branch
        ├── feature/BC-1234/sub-2        ← small MR → integration branch
        └── feature/BC-1234/sub-3        ← small MR → integration branch
  ← one single final MR: feature/BC-1234 → develop
```

It resolves the tension between "small MRs get approved and merged faster" and "the team expects one MR per ticket": develop sees a single merge, while each piece is reviewed small and separately.

---

## 8. Folder structure

### Per project

```
.claude/workflow/
├── state.json                    # { "activeTicket": "BC-1234" }
├── config.json                   # stack, DoD, related_projects, weight exclusions, thresholds
└── BC-1234/
    ├── state.json                # stage, progress, branch, iterations
    ├── refinement-summary.md     # shared by every subtask
    ├── plan.md                   # parent plan / subtask index
    ├── design-decisions.md
    ├── complexity.json           # estimate §5.5
    ├── sub-1/
    │   ├── state.json
    │   ├── plan.md
    │   ├── review-findings.md
    │   └── complexity.json
    └── sub-2/
        └── ...
```

Without partitioning, the ticket has no `sub-N/` subfolders and everything lives at the root of `BC-1234/` — identical to the current behavior.

The ticket's `state.json` adds:

```json
{
  "stage": "implement",
  "branch": "feature/BC-1234",
  "subtasks": ["sub-1", "sub-2"],
  "active_subtask": "sub-1",
  "iterations": {"analyze": 2, "implement": 3, "validate": 1}
}
```

### Global

```
~/.claude/workflow/
├── config.json
├── events.jsonl        # append-only, permanent — the raw truth
├── flow-history.json   # compacted summaries per closed ticket
└── improvements.md     # logbook of changes applied to the workflow, with evidence
```

---

## 9. Retention

Three levels with different lifespans:

| Artifact | Lifespan | Policy |
|---|---|---|
| `events.jsonl` | **permanent** | append-only, never pruned |
| `{ticketId}/` in the project | until merge | on merge it's compacted into an entry in `flow-history.json` and the folder is deleted |
| `improvements.md` | **permanent** | only changes applied to the workflow, with their evidence |

**Hard rule: compaction never deletes from `events.jsonl`.** If in six months a question comes up that we can't think of today, the raw data is needed. The file is plain text and a few lines per ticket — the cost of keeping it forever is negligible against the cost of not being able to answer.

Suggested compaction at merge time:

```json
{
  "date": "2026-08-07",
  "project": "bc-app",
  "ticket": "BC-1234",
  "complexity_estimated": 8,
  "iterations_total": 5,
  "iterations_by_stage": {"analyze": 2, "implement": 2, "validate": 1},
  "leak_distances": [4, 1, 1],
  "detected_by": {"gate": 4, "user": 1},
  "scope_drift": {"unplanned": 2, "missing": 0},
  "mr_weight_prod": 240,
  "split": false
}
```

---

## 10. How the data is used

`/wf-retro` and `/wf-improve` shift to querying `events.jsonl` instead of reasoning over the loose session. Questions the schema answers:

1. Which stage originates the most defects? → `group by stage_origin`
2. What's the mean leak per originating stage? → where to put the next gate
3. Is my `detected_by: user` percentage rising? → the gates are degrading
4. Do I systematically underestimate? → sign of the calibration error
5. Does `sister_feature: none` correlate with more iterations? → validate §5.3
6. Did splitting reduce iterations, or just relocate them? → compare tickets with and without `split_applied`
7. Which finding categories repeat across 3+ tickets? → grounded candidates for a workflow change

Every proposal derived from these queries must satisfy §0: minimum 3 tickets, a citation of the concrete query, and a record in `improvements.md`.

---

## 11. Suggested implementation order

1. **Hooks + `events.jsonl`** — the mechanical skeleton. Immediate value, zero changes to commands.
2. **Complexity rubric in `/wf-analyze`** — starts generating the "estimated" side of the pair.
3. **MR weight + trip wire (c) in `/wf-implement`** — generates the "actual" side.
4. **Semantic events in the rest of the commands** — `finding`, `detected_by`, `stage_origin`.
5. **Subtasks and branching** — only once there's data saying whether the partition threshold works.
6. **Analysis queries in `/wf-retro` and `/wf-improve`** — at 15-20 tickets.

Steps 1-4 change no decision in the flow: they only observe. Step 5 is the first one that alters how you work, and it arrives deliberately late.

---

## 12. Open points

- **Thresholds in §5.4 and §6.4** — provisional, with no empirical basis. Calibrate at 15-20 tickets.
- **Rubric weights §5.2** — especially `sister_feature`; it's an explicit hypothesis.
- **"Abandoned" detection** — N days of inactivity still to be defined.
- **A finding's `stage_origin`** — the model determines it and it's subjective. Risk of noise; evaluate whether to restrict it to a short enum of causes.
- **Multi-project** — `events.jsonl` is global and mixes projects. It works for workflow patterns, but complexity comparisons across different codebases may not be valid.
