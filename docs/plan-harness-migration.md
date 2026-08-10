# Plan — Migration to a harness layer

> Status: **proposal, pending review**. Do not implement without going through plan review.
> Rule applied: `docs/brainstorm-metrics-and-complexity.md` §0 — every item cites evidence (`file:line`) or is explicitly marked as a hypothesis.

---

## 1. Diagnosis

### 1.1 Thesis

Today the system enforces its rules by **writing prose into `.md` files that the model reads and almost always obeys**. A harness enforces rules with **mechanisms that can't be skipped**: hooks, scripts, permissions, executable checks.

The repo already has proof that the mechanical approach works: telemetry was implemented as a hook (`hooks/wf-telemetry.sh`) instead of asking each command to record events, precisely because §3.1 of the brainstorm documents that the previous opt-in mechanism (`flow-history.json` via `/wf-retro` step 4) never ran even once.

This plan applies that same criterion to the rest of the system.

### 1.2 Verified findings

Each with its evidence. Ordered by severity.

| # | Finding | Evidence | Impact |
|---|---|---|---|
| H1 | Telemetry doesn't observe the main entry path | `hooks/wf-telemetry.sh:172-186` only matches a typed `/wf-<stage>`; `/wf` falls into `*) exit 0`. `README.md`: "the entry point is always `/wf`" | Every stage entered through the orchestrator is invisible. `events.jsonl` = 0 lines since 08/07 |
| H2 | The repo is not the source of truth | `wf-commit.md` and `wf-deploy.md` exist in `~/.claude/commands/`, not in `commands/`. `install.sh:24` only copies repo→home. `wf-retro.md:83` and `wf-improve.md:113` edit `~/.claude/commands/` and delegate the copy-back to the user | 2 commands were already lost. Every `/wf-retro` that applies an improvement widens the divergence |
| H3 | Gate evaluating against a structurally empty file | `wf-review-plan.md:60` raises a finding if the plan didn't cross-reference `flow-history.json`; `wf-analyze.md` step 6 likewise. The file sits at `{"entries": []}` | A gate that can never contribute signal, but can contribute noise |
| H4 | `base_branch` hardcoded to `develop` | `wf-refine.md:101,104` run `git checkout -b {branch} develop`. `config.json` has no base branch field (`wf-init.md` step 5 doesn't generate it) | Breaks in any repo on `main`. The other 3 commands say "develop/main/master, depending on the project" — i.e. they ask the model every time |
| H5 | `wf-jira` was left on the pre-multi-ticket schema | `wf-jira.md:31-33` reads `.claude/workflow/refinement-summary.md` and `plan.md` (flat paths), but the current schema is `.claude/workflow/{ticketId}/` | It never finds the context; it generates the ticket without enriching it |
| H6 | `wf.md` has its steps out of order | `wf.md`: "## Step 1 — Special arguments" appears **before** "## Step 0 — Verify initialization" | The init check runs after routing, or doesn't run at all |
| H7 | `stage_index()` doesn't cover every stage the hook itself emits | `hooks/wf-telemetry.sh:97-107`: there's no case for `mr-desc` or `retro`, both emitted at `:180-182`. They fall into `*) echo 0` | `leak_distance` (§2.2) miscalculates for findings detected in those stages |
| H8 | The global config is dead code | `config/workflow.json` has `projects`/`preferences`; no command or hook reads it (grep returns nothing outside `install.sh:36`) | Confusion: there are two configs and only one is used |
| H9 | None of the brainstorm's semantic layer was implemented | §3.3 lists 7 commands that should emit events; none do. §5 (rubric), §6 (MR weight), §7 (trip wire) neither | The "detect that the log is incomplete" design (§3.1) can't work: there's nothing to cross-reference against |
| H10 | `improvements.md` doesn't exist | §0 and §8 require it as a mandatory logbook; `install.sh` doesn't create it | The grounding rule has nowhere to be recorded |
| H11 | The ticket's `stage` field goes stale from the first command onward | Only `wf-refine.md:25` and `wf.md:105` write `stage`. Neither `wf-review-plan`, nor `wf-implement`, nor `wf-validate`, nor `wf-test` update it on entry | The state machine only exists if you always go through `/wf`. Invoking commands directly — a usage the README presents as valid — freezes the stage at the refinement one |
| H12 | The value written to `stage` isn't the one any consumer expects | `wf-refine.md:25` writes `"stage": "refinement"`; `hooks/wf-telemetry.sh:163`, the routing table in `wf.md` step 3 and `stage_index()` all use `refine` | Every stage comparison fails today, silently |

### 1.3 Note on §0 and this plan's scope

§0 requires 3 tickets with the same pattern before proposing a workflow change. **Today there are 0 events**, so no *flow policy* proposal can be grounded in data yet.

That's why this plan deliberately limits itself to two classes of change, both admissible under §0 via the "task in progress" source (`file:line`):

- **Fixes** to broken or divergent behavior (H1-H8, H10).
- **Mechanism changes with no policy change**: the rule being enforced is the same one already written in the `.md`; only *who enforces it* changes. A gate that is an instruction today and becomes a hook is not a new policy.

Everything that would be new policy (thresholds, additional gates, task partitioning) is out of scope for this plan and waits for data — which is exactly what §11 of the brainstorm mandates in its steps 5-6.

**One declared exception:** Phase 3 adds new opt-in capabilities (runtime validator, worktrees). They change no existing rule and don't activate on their own, but they aren't grounded in data either. They are marked as hypotheses and left at the end, separable from the rest.

---

## 2. Inventory: prose → mechanism

The core of the plan. Each row is a rule that lives as text today and could live as a mechanism.

| Rule | Today | Proposed | Phase |
|---|---|---|---|
| "Read `activeTicket` from `state.json`" | Identical prose repeated in 10 commands (`wf-analyze.md:12`, `wf-review-plan.md:12`, `wf-validate.md:12`, `wf-implement.md:38`, `wf-test.md:12`, `wf-mr-desc.md:12`, `wf-mr-review.md:12`, `wf-retro.md:12`, `wf-improve.md:20`, `wf-refine.md:12`) | `scripts/wf-lib.sh` → `wf_ticket`, `wf_dir` | 2 |
| "Diff against merge-base, not against the base" | Explanatory paragraph repeated in 4 commands (`wf-validate.md:36`, `wf-mr-review.md:18`, `wf-mr-desc.md:24`, + `wf-implement` implicitly) | `scripts/wf-diff.sh` | 2 |
| "The base branch is develop/main/master depending on the project" | The model is asked every time; hardcoded at `wf-refine.md:104` | `base_branch` in `config.json` + `wf_base` in `wf-lib.sh` | 2 |
| "When entering a stage, update `stage` in the ticket state" | Only `/wf` step 5 does it; directly invoked commands don't (H11) | `wf_enter_stage <stage>` in `wf-lib.sh`, called by every command on its first line | 2 |
| "NEVER move to implementation without an explicit answer" | `wf-review-plan.md:96` — an instruction in capitals | A `PreToolUse` hook that rejects `Edit`/`Write` when `stage == review-plan` and `approved != true`. **Depends on H11/H12** | 2 |
| DoD checklist | A list of prose strings (`config.json` → `dod_checklist`), evaluated by the model's judgment | Executable `checks` in `config.json`, run before invoking any agent | 2 |
| "Verify the related_project contract before approving" | Prose in 4 commands; impossible to verify after the fact | Mandatory artifact `{workflowDir}/contract-verification.md`; the gate checks existence, not intent | 2 |
| "Don't touch files outside the plan" | Doesn't exist as a rule; only measured as `scope_drift` after the fact (§2.3 #1) | Out of scope — it would be new policy | — |

---

## 3. Phases

Each phase is independent and separately shippable. Order matters: Phase 0 is a prerequisite for everything else, because without it any change is lost in the next divergence.

### Phase 0 — Close the installation loop

**Problem:** H2. The repo is not the source of truth.

1. Adopt `wf-commit.md` into the repo as-is. **Note:** it carries the same flat-path bug as H5 (`.claude/workflow/plan.md` instead of `{ticketId}/`); it is adopted with the bug and fixed in Phase 1, so adoption isn't mixed with correction.
2. Adopt `wf-deploy.md` in a **generic version**: it detects the method (CI vs local) and the branching model from `config.json` instead of assuming fastlane/GitLab. When the project has no CI/CD, no defined release branches and no deploy scripts, the command **says so and offers to set it up** instead of proceeding as if it existed. The current fastlane-bound version stays as an override in the `.claude/commands/` of the project that uses it.
3. `install.sh`: add a `--check` mode that compares repo vs installed and lists divergences without writing.
4. `install.sh`: create `~/.claude/workflow/improvements.md` if it doesn't exist (H10).
5. `wf-retro.md` step 5 and `wf-improve.md` step 4: change the edit target from `~/.claude/commands/wf-*.md` to `$WF_REPO/commands/wf-*.md` + run `install.sh` at the end. Resolve `$WF_REPO` from `repo_path` in `~/.claude/workflow/config.json` (which thereby gains a real use — H8).
6. Remove `projects`/`preferences` from `config/workflow.json` (dead code) and leave `{ "repo_path": "..." }`.
7. `install.sh`: **merge** `repo_path` into the existing global config with `jq`, don't preserve it untouched. The current block (`install.sh:34-40`) skips if the file already exists, so a previous installation — like this user's, from May — would never receive the key.

**Acceptance criterion:** after a `/wf-retro` that applies an improvement, `install.sh --check` reports no divergences.

---

### Phase 1 — Fix what's broken

Targeted fixes, no architectural change.

1. **H12 first** — unify the stage vocabulary on `refine` (the value already used by the hook, `stage_index()` and the routing table). Fix `wf-refine.md:25`. It's a prerequisite for H11 and for the Phase 2 gate: there's no point building on a field whose vocabulary isn't unified.
2. **H11** — every stage command writes its `stage` on entry. It's implemented in Phase 2 via `wf_enter_stage`, but the targeted fix goes here because the gate depends on it.
3. **H1 — start with an experiment, not a design.** Routing through `/wf` can't be detected from `UserPromptSubmit`: the prompt says `/wf analyze this`, not the stage. There were three candidates, and **none was verified**:
   - (a) Have `/wf` write `stage` before routing and let the hook derive it from there — depends on the model writing, which is what we want to avoid.
   - (b) `PreToolUse` on the `Read` of `~/.claude/commands/wf-*.md` (`wf.md:79`) — **discarded as "mechanical"**: it also depends on the model running a `Read` it was told about in prose.
   - (c) `PostToolUse` filtering `tool_name: "Skill"` — in this harness the `wf-*` are exposed as skills, so routing could be resolved there and (b) would never fire.

   **Procedure:** install a temporary logging hook that dumps the raw JSON of `PostToolUse` and `UserPromptSubmit` to a file, run `/wf` once, inspect what actually arrives. Decide from that data. Without the experiment, all three are a bet.

   **✅ RESOLVED — 2026-08-10.** `/wf` was run in `PrositeMobile` with the probe installed (205 events captured). **All three candidates were ruled out by observation:**
   - (b) **never fired.** There was no `Read` of `wf-*.md` at all: the harness injects the command body straight into the context, the model never reads the file. *(Note: `wf-probe.sh --report` shows false positives here — its grep matches any tool, and it listed `Edit`s made on this very repo. The correct conclusion is zero reads.)*
   - (c) **the `Skill` tool was never invoked.**
   - The `UserPromptSubmit` payload carries a literal `prompt` of `"/wf"` — unexpanded, with no stage. The hook can know `/wf` was invoked, not where it routed. H1 confirmed, no longer assumed.

   **Adopted way out — (d), which wasn't in the original list and only exists thanks to Phase 2:** `wf_enter_stage` is a `Bash` call, and `PreToolUse` on `Bash` includes `tool_input.command` in the payload. Telemetry detects stage entry by matching `enter-stage (\w+)` in the command, regardless of whether it was reached via `/wf` or by direct invocation.

   It's better than (a) for a structural reason: there, the state write and the telemetry event were two actions that could diverge. Here **they are the same action** — if step 0 ran, there is state *and* there is an event; if it didn't, there is neither. The class of bug where the state says one thing and `events.jsonl` another disappears.

   **Remaining limit:** it isn't fully mechanical — it still depends on the command running its step 0. But that dependency already existed for the state; now there is **one** instead of two.

   **Bonus:** the payload carries `cwd` on every event, so telemetry can segment by project at no extra cost.
4. **H7** — add `mr-desc` and `retro` to `stage_index()`, or exclude them explicitly from the leak calculation with a comment.
5. **H5** — `wf-jira.md:31-33` and `wf-commit.md` step 1: migrate to `{workflowDir}/`, with the standard step 0.
6. **H6** — `wf.md`: move "Step 0" before "Step 1".
7. **H3** — `wf-analyze.md` step 6 and `wf-review-plan.md:60`: downgrade the `flow-history.json` cross-reference from "raise a finding" to "if the file has entries, cross-reference it". Re-enable the gate when Phase 4 fills it.

---

### Phase 2 — Prose → mechanism migration

The core. Implements the table in §2.

1. **`scripts/wf-lib.sh`** — sourceable functions:
   - `wf_ticket` → activeTicket, or fail with a clear message
   - `wf_dir` → `.claude/workflow/{ticketId}`
   - `wf_base` → `base_branch` from the config, with a fallback detecting `develop`/`main`/`master` in the repo
   - `wf_config <key>` → typed config read
   - `wf_enter_stage <stage>` → writes `stage` and appends to `completed` in the ticket state (H11). Single vocabulary, the one from `stage_index()`
2. **`scripts/wf-diff.sh`** — encapsulates the merge-base; supports the "no commits, everything in the working tree" case that today is described in prose at `wf-validate.md:48`.
3. **`scripts/wf-checks.sh`** — runs the config's `checks` and returns JSON with the results. New field in `config.json`:
   ```json
   "base_branch": "develop",
   "checks": {
     "lint":  "npm run lint",
     "types": "tsc --noEmit",
     "test":  "npm test"
   }
   ```
   `wf-init.md` now detects and generates them (today it detects the linter in step 2 but only to write a prose string into the DoD).
4. **`hooks/wf-gate.sh`** (`PreToolUse`) — blocks `Edit`/`Write` on code files when the active ticket is at `stage: review-plan` without `approved: true`. Excludes `.claude/workflow/**` and `docs/**`.
   - `wf-review-plan.md` step 3 writes `approved: true` into the ticket state when the user confirms.
   - The hook **is allowed to block** — it's the sole exception to the telemetry hook's "never blocks" principle, and it's deliberate: here blocking is the function, not a side effect. Escape hatch: `WF_GATE=off`.
   - **Blast-radius containment (mandatory).** Hooks are registered in `~/.claude/settings.json`, meaning they run in *every* project, workflow or not. Non-negotiable requirements:
     1. Early exit (exit 0) if the repo has no `.claude/workflow/state.json`.
     2. Fail-open on any error — `jq` missing, corrupt JSON, git missing; the only blocking path is the explicit condition evaluated successfully.
     3. **One week in logging-only mode before enabling blocking.** It records what it *would* have blocked in `events.jsonl` without preventing anything. A requirement, not a suggestion: it's the system's first hook capable of stopping work, and it deliberately breaks `wf-telemetry.sh`'s "never interrupts" principle.
5. **Rewrite the 8 "Step 0" blocks** (13 lines each) as a single line calling `wf-lib.sh`, and the 4 merge-base blocks (12 lines) as a call to `wf-diff.sh`. `wf-refine` and `wf-improve` have their own step 0 variants and are migrated separately.
6. **`wf-validate.md` step 2.5** — run `wf-checks.sh` before launching the Agent. If something mechanical fails, return that and don't spend the agent.

**Estimated savings:** ~150 lines of repeated prose (8 × 13 + 4 × 12).

**Actual result: +119 / −102, net +17 lines.** The estimate didn't hold. What was deleted from repeated prose was consumed explaining what each script does and why (plus the gate's `approved` and the new `wf-init` fields, which are new capability, not replacement).

The important conclusion isn't the number but what justifies the phase: **it wasn't the line count.** It's that the rule now exists in a single place and stops depending on the model interpreting it the same way all 8 times. `wf_base` is the clear case: it used to be different prose in 4 files, one of them with `develop` hardcoded (H4); now it's a function with a test-verified fallback. The line count was a convenient metric, not the reason.

**Verification:** `tests/test-scripts.sh` — 34 checks against a temporary git repo, including the case that motivated `wf-diff` (a base that advances after the branch was created) and the gate's six fail-open paths.

---

### Phase 3 — New capabilities (opt-in, marked as hypotheses)

> None of these is grounded in data. They are explicit bets, separable from the rest of the plan. If review rejects them, Phases 0/1/2/4 remain valid.

1. **Runtime validator** — new item `7. 📱 Runtime` in the `wf-validate.md` step 1 picker. For UI/navigation changes: bring the app up via the Metro MCP, navigate to the affected screen, read state and network, screenshot. Hypothesis: the races that `wf-analyze`'s §"expected execution order" tries to cover by asking the user are better caught by observing the runtime than by reasoning over the diff.
2. ~~**One worktree per ticket**~~ — **moved out of this plan.** It collides with the multi-ticket dashboard: `wf.md` step 2 scans `.claude/workflow/*/state.json` to list every ticket, and with one worktree per ticket each one sees only its own folder. That isn't an implementation detail — it forces a decision on whether state moves to `~/.claude/workflow/{project}/`, which also touches Phases 2 and 4. It needs its own plan.
3. ~~**Model routing per stage**~~ — **not applicable.** The point assumed `wf-mr-desc`, `wf-jira` and `wf-commit` invoked Agents that could be given `model: sonnet`. They don't: `grep -l "Agent tool" commands/*.md` returns exactly `wf-analyze`, `wf-review-plan`, `wf-validate` and `wf-mr-review`, and those four are precisely the judgment-heavy ones worth leaving on Opus. The other three run in the main context, where the model is chosen by the user in the session, not by the command. There's nothing to route.
4. **Delegate the generic review** — `wf-mr-review.md` now assembles context + invokes `/code-review`, and keeps as its own only the contract check against `related_projects`, which no generic reviewer does.
5. **`AGENTS.md`** — `wf-init` also generates `AGENTS.md` with stack and conventions, in addition to `config.json`.

**Phase result:** 1, 4 and 5 implemented. 2 moved to its own plan. 3 discarded as not applicable. Of the three implemented, only 4 has a solid basis (`/code-review` exists and maintains itself); 1 and 5 remain hypotheses with a declared discard criterion.

---

### Phase 4 — Close the data loop

Implements §11 steps 2-4 and 6 of the brainstorm, which were left pending (H9).

1. ✅ **Semantic events in the commands** (§3.3). They are emitted via `scripts/wf-event.sh`, not by writing JSON from prose: asking the model to assemble the object by hand is the same rule-as-prose pattern this migration removes, and it fails silently — one malformed line breaks every downstream query and nobody notices until the stats come back wrong. Covers `complexity_estimate` (`wf-analyze`), `finding` (`review-plan`, `validate`, `test`, `mr-review`), `finding_decision` (`validate`) and `ticket_closed` (`wf-retro`).
2. ✅ **`scripts/wf-stats.sh`** — one subcommand per question in §10, plus `coverage` to audit the health of the log itself. It enforces two rules: it always reports the sample size, and it refuses to conclude below the 3 tickets of §0.
3. ⏸️ **Deferred — `wf-improve`/`wf-retro` querying stats.** `events.jsonl` is empty (the hook was installed on 2026-08-10 and `/wf` emits nothing by design). Changing those commands to reason over nonexistent data leaves them **worse** than today: today they at least analyze the session, which is real information. Re-enable when `wf-stats.sh` reports ≥ 10 tickets with recorded stages.
4. ⏸️ **Deferred — `flow-history.json` gate.** Same reason: the file has 1 entry.

**Why 3 and 4 are left out, and it isn't laziness:** they are the only two points that *consume* data. 1 and 2 produce it and query it on demand; enabling automatic consumers over an empty file produces recommendations with zero evidence behind them, which is exactly what §0 forbids.

**Prerequisite:** ~~Phase 1 point 1 (H1)~~ — **unblocked.** The experiment was run and the path is `PreToolUse` on `Bash` matching `enter-stage (\w+)`. See Phase 1 point 3.

**First concrete step:** `hooks/wf-telemetry.sh` also registers on `PreToolUse`, and derives `stage_start` / `stage_reentry` from the `enter-stage` command instead of parsing the prompt. Parsing `UserPromptSubmit` remains as a fallback for direct invocation without step 0.

---

## 4. Order and dependencies

```
Phase 0 (installation loop)
   └── prerequisite for everything: without it, changes get lost
        │
        ├── Phase 1 (fixes)
        │      └── H1 ── prerequisite for ── Phase 4
        │
        ├── Phase 2 (prose → mechanism)   ← the core of the change
        │
        └── Phase 3 (new capabilities)    ← independent, discardable
```

## 5. What is explicitly out of scope

| Item | Why |
|---|---|
| Complexity thresholds (§5.4) and MR weight (§6.4) | Provisional by design; §12 leaves them for 15-20 tickets |
| Partitioning into subtasks (§7) | §11 step 5: "the first one that alters how you work, and it arrives deliberately late" |
| Size trip wire (§7.2) | Depends on uncalibrated thresholds |
| The "don't touch files outside the plan" rule | Would be new policy with no evidence |
| Worktree per ticket | Forces moving state out of the repo so as not to break the multi-ticket dashboard. Its own plan |

### Repo language — done

User convention: code, comments, commits and documentation in English.

**Translated on 2026-08-10** (this branch): every `.md`, `.sh` and `.json` in the repo — `README.md`, all of `docs/`, `install.sh`, `hooks/`, `scripts/`, `tests/`, `agents/` and `commands/`. `docs/architecture.md` was already in English. `docs/brainstorm-metricas-y-complejidad.md` was renamed to `docs/brainstorm-metrics-and-complexity.md`.

The `commands/wf-*.md` case, previously flagged as needing its own decision: they were translated in full, including the literal blocks displayed on screen. The user chose English output over preserving the Spanish UX, on the grounds that the result is verifiable rather than dependent on a prose directive being honored.

**The output language became configurable instead of hardcoded.** `wf_language` in `wf-lib.sh` reads `.language` from the project's `config.json` and defaults to `en`; `wf-lib.sh context` exposes it as `lang`, and every conversational command carries one line telling it to address the user in that language while always writing files in English. That keeps a Spanish-speaking user reachable per project without putting Spanish back into the source.

**TODO — what is still in Spanish:**

| Item | Why it wasn't done |
|---|---|
| Commits `ebf5973`..`f9dc8ce` | Already pushed; rewriting them requires a force-push over a published branch |

## 6. Risks

| Risk | Mitigation |
|---|---|
| **`wf-gate.sh` blocks work in projects unrelated to the workflow.** Hooks are global (`~/.claude/settings.json`): they run in every repo you open. A bug blocks `Edit`/`Write` in all of them, not just here | The three requirements of Phase 2 point 4: early exit without `state.json`, fail-open on any error, and a mandatory logging-only week. **This is the highest risk in the plan** |
| The gate blocks legitimate work (e.g. touching code during `review-plan` to verify a hypothesis) | Escape hatch `WF_GATE=off`; exclude `.claude/workflow/**` and `docs/**` |
| The gate is built on `stage`, a field that is stale today (H11) and has broken vocabulary (H12) | H12 and H11 are explicit prerequisites, in Phase 1, before writing a line of the gate |
| The scripts break in a project without `jq` or without git | Same principle as `wf-telemetry.sh`: degrade to a fallback, never break. Except `wf-gate.sh`, where failing **open** is the right call — blocking by mistake is worse than not blocking |
| Phase 2 touches the commands all at once → regression hard to isolate | Migrate command by command, verifying with `install.sh --check` and the smoke test between each one |
| The H1 experiment concludes nothing (none of the three hooks captures the routing) | ✅ **Resolved** — none of the three captured it, but a fourth path appeared (`PreToolUse` on `Bash` + `enter-stage`). See Phase 1 point 3 |
| **`exit 2` might not block anything.** The tests only prove the script returns 2, not that the harness honors it. If it doesn't, the gate is decorative | ✅ **Verified end-to-end (2026-08-10)** — with a ticket in `review-plan` and unapproved, a `Write` to a non-excluded path was rejected by the harness, with the hook's stderr as the tool error. The gate really does block |
| **Phase 4 has no data to report on.** As of 2026-08-10 `events.jsonl` is empty: the hook was installed that same day and `/wf` emits nothing by design | `wf-stats.sh` can be built anyway, but you have to assume it says nothing useful until real stages accumulate. Wiring `wf-retro`/`wf-improve` to the data only makes sense after that |
