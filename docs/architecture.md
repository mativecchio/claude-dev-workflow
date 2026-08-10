# Architecture

## Overview

`claude-workflow` is a two-layer system:

1. **Workflow commands** (`~/.claude/commands/wf-*.md`) — orchestrate the development lifecycle, language-agnostic
2. **Language agents** (`~/.claude/agents/`) — domain experts for specific stacks, invoked on demand

Both layers only load context when invoked — no baseline token cost.

## Component types

### Slash commands (skill-style)
Run in the main conversation context. Used for stages that need multi-turn dialogue and accumulated session context.

`/wf`, `/wf-init`, `/wf-refine`, `/wf-implement`, `/wf-test`, `/wf-commit`, `/wf-deploy`, `/wf-retro`, `/wf-improve`, `/wf-mr-desc`, `/wf-jira`

`/wf-deploy` is toolchain-agnostic: it detects CI vs local from what's present in the repo and reads the branch model from `config.json`. When a project lacks CI, protected branches, versioning, or a documented rollback, it names the specific risk and offers to set it up before deploying. Projects with a specific toolchain override it with a local `.claude/commands/wf-deploy.md` — see `docs/examples/wf-deploy-fastlane.md`.

### Slash commands (agent-style)
Run in the main context, but internally spawn a subagent via the `Agent` tool for isolated execution. The subagent writes output to `.claude/workflow/` files; the command reads and presents the result.

`/wf-analyze`, `/wf-review-plan`, `/wf-validate`, `/wf-mr-review`

These four are the only commands that spawn an `Agent` — the rest run entirely in the main context. That's also why per-stage model routing isn't a thing here: the commands that would benefit from a cheaper model have no Agent to route, and the four that do are the judgment-heavy ones.

`/wf-mr-review` delegates the generic pass (correctness bugs, simplification, reuse, efficiency) to `/code-review high` before spawning its own agent, and keeps for itself only what a generic reviewer can't do: contrast against `plan.md` and the acceptance criteria, `related_projects` contracts verified against the other repo's real source, project conventions, and registered tech debt.

### Language agents
Invoked by workflow commands (or directly by the user) for domain-specific decisions. They have no project-specific context by default — that lives in per-project `.claude/agents/` overrides.

## State management

Multi-ticket: the root state only tracks which ticket is active, everything else is per-ticket.

| Layer | Storage | Scope |
|---|---|---|
| In-stage tracking | `TodoWrite` | Current command execution |
| Active-ticket pointer | `.claude/workflow/state.json` → `{ "activeTicket": "BC-XXXX" }` | Persists across commands within a project |
| Per-ticket state | `.claude/workflow/{ticketId}/state.json` | Stage, progress, saved branch, optional `notes` (retroactive tickets) |
| Cross-session artifacts | `.claude/workflow/{ticketId}/plan.md`, `refinement-summary.md`, `review-findings.md` | Handoff between stages, scoped to one ticket |
| Historical log | `~/.claude/workflow/flow-history.json` | Cross-project, used by retrospective and by contract-risk checks in `wf-analyze` |
| Telemetry | `~/.claude/workflow/events.jsonl` | Append-only, cross-project, never pruned |
| Workflow changelog | `~/.claude/workflow/improvements.md` | Every change applied to the workflow, with its evidence (brainstorm §0) |
| Source-of-truth pointer | `~/.claude/workflow/config.json` → `repo_path` | Where `/wf-retro` and `/wf-improve` write their changes |

Every subcommand's "Paso 0" reads `activeTicket` from the root file, then reads/writes its per-ticket state under `.claude/workflow/{ticketId}/`.

**Retroactive tickets:** when a ticket is activated with implementation commits already on the branch but no `plan.md`, per-ticket `state.json` starts at stage `"implement"` with a `notes` field summarizing what was done and why there's no formal plan. Commands that normally require `plan.md`/`refinement-summary.md` (`wf-validate`, `wf-mr-desc`, `wf-mr-review`) fall back to reading `notes` instead of blocking.

## Handoff between stages

All stage handoffs happen through files in `.claude/workflow/{ticketId}/`:

```
/wf-refine  → writes → refinement-summary.md
/wf-analyze → reads  → refinement-summary.md
            → writes → plan.md
            → asks for expected execution order/race cases when effects read/write the same
              shared-storage key (race conditions only show up at runtime otherwise)
            → verifies related_project contracts (greps sibling repo path from config.json,
              cross-checks flow-history.json) when the diff touches shared state
/wf-review-plan → reads  → plan.md + refinement-summary.md
                → writes → review-findings.md
                → blocks approval if a shared-state risk was flagged but not verified
/wf-implement → reads → plan.md + review-findings.md
/wf-validate  → reads → plan.md (for diff context, against merge-base(HEAD, base) — not a plain
                two-dot diff, which breaks silently if base advanced past the fork point)
              → same related_project verification gate as review-plan
              → REQUIERE CAMBIOS gives a per-finding picker (implement/ignore/tech-debt) instead
                of all-or-nothing; the decided list flows to wf-implement, which skips its own
                "¿Arrancamos?" checkpoint when arriving pre-decided
/wf-test      → adds a manual-verification checklist item, gated on user confirmation, when a
                related_project risk exists (no in-repo test can confirm external-system behavior)
/wf-mr-review → reads → plan.md + refinement-summary.md (injects into agent prompt)
              → diffs against merge-base(HEAD, base); same related_project verification gate
/wf-mr-desc   → reads → plan.md + refinement-summary.md
              → diffs against merge-base(HEAD, base)
```

The Memory system is **not** used for workflow state — it's unreliable across project directory switches. It's only used for global path registry (external project paths).

## Checkpoint model

Each stage has checkpoints at different risk levels:

| Stage | Checkpoint type |
|---|---|
| `wf-analyze` | Soft — shows analysis, asks if correct before proceeding |
| `wf-review-plan` | **Hard block** — explicit "sí" required before implementation; also blocks on unverified shared-state risk |
| `wf-implement` | Before each file group (high-risk changes) — skipped on explicit invocation or when arriving with a pre-decided finding list from `wf-validate` |
| `wf-validate` | After each iteration — per-finding picker (implement/ignore/tech-debt) instead of all-or-nothing; also blocks on unverified shared-state risk |
| `wf-test` | After gap analysis — confirms before writing tests; adds manual-verification item for unverified external-project risk |

### Runtime validation

`wf-validate` option 6 (`📱 Runtime`) is the only validator that doesn't reason about the diff — it observes the app running, via the `metro` MCP for React Native or `claude-in-chrome` for web. It runs in the **main context**, not inside the Agent, because subagents have no guaranteed MCP access.

It exists for a class of defect a diff can't show: an ordering between effects, state left inconsistent on returning to a screen, a request fired twice. `wf-analyze` approximates this by asking the user for the expected execution order; this looks directly.

Declared as a hypothesis (`docs/plan-harness-migration.md` Fase 3), not grounded in data. If it doesn't surface defects the other validators miss within 15-20 tickets, it comes out. When no MCP is available, it reports that it couldn't verify rather than passing silently.

Before adding a validation guard for a value, `wf-implement` greps all call sites of that value first — a guard added to only one of several call sites is a common miss (e.g. BC-1529's `isValidDate` gap, present in 4 places but found across two review rounds instead of one).

## Telemetry (hook layer)

`hooks/wf-telemetry.sh` is installed to `~/.claude/hooks/` and registered in `~/.claude/settings.json` on four events. It appends to `~/.claude/workflow/events.jsonl`. Design and event schema: `docs/brainstorm-metricas-y-complejidad.md`.

| Hook | Mode | Captures |
|---|---|---|
| `UserPromptSubmit` | `prompt` | `/wf-*` invocation → `stage_start`, or `stage_reentry` with `iteration_n` |
| `PostToolUse` | `tool` | per-stage `tool_calls`; `plan_edit` when `plan.md` is written at `review-plan` or later (plan churn) |
| `Stop` | `stop` | per-stage `turns` |
| `SessionEnd` | `session-end` | flushes `stage_end` with `turns`, `tool_calls`, `duration_s` |

Stage entry counts are persisted to the **ticket's** `state.json` under `iterations`, so a ticket re-analyzed days later still counts as a re-entry — session-scoped counting would undercount exactly the long-running tickets that matter most. The hook merges that key with `jq` and refuses to write if the file doesn't parse, so command-managed fields (`stage`, `branch`, `notes`, `subtasks`) are never lost.

With no `activeTicket`, or an unparseable ticket state, it falls back to session-scoped counting and stamps `"scope": "session"` on the event — the count is still emitted, but marked as unreliable rather than silently wrong. Turn and tool-call counters remain per-session in `~/.claude/workflow/sessions/{session_id}.json`, deleted on `SessionEnd`.

This layer is mechanical only — it cannot know *why* a stage was re-entered. Semantic events (`finding`, `complexity_estimate`, `scope_drift`) are emitted by the `wf-*` commands themselves and carry `"source": "command"`. The `source` field is what makes it possible to detect gaps: a hook-recorded `stage_reentry` with no command-recorded `finding` explaining it means the cause was lost. `wf-stats.sh coverage` reports exactly that number.

### Semantic events

Commands emit them through `wf-event.sh`, never by writing JSON themselves. Handing the model a JSON object to assemble in a prompt is the same prose-as-rule pattern this migration removes, and it fails silently: one malformed line breaks every later query, and nothing surfaces it until the stats come back wrong.

| Command | Emits | Carries |
|---|---|---|
| `wf-analyze` | `complexity_estimate` | §5.2 rubric score + per-dimension breakdown; the *estimated* half of the pair |
| `wf-review-plan` | `finding` × N | `stage_origin`, `detected_by` |
| `wf-validate` | `finding` × N, `finding_decision` | the picker's implement/ignore/tech-debt outcome |
| `wf-test` | `finding` × N | coverage gaps, usually originating in `refine`/`analyze` |
| `wf-mr-review` | `finding` × N, `mr_opened` | MR weight, prod vs tests separately |
| `wf-retro` | `ticket_closed` | real iterations + `complexity_actual`; the *actual* half of the pair |

Two fields carry most of the value and cannot be reconstructed afterwards:

- **`stage_origin`** — where the defect was *introduced*, not where it surfaced. A missing guard caused by an incomplete plan originates in `analyze`, even though the symptom is in the code. Getting this wrong turns the leak metric into noise.
- **`detected_by`** — `gate` if a workflow command found it, `user` if the person did. A rising `user` share means the gates are degrading; marking user-found defects as `gate` hides precisely that.

`complexity_estimate` without a matching `ticket_closed` is decorative: calibration is the difference between the two, so `wf-retro` closing the pair is what makes the rubric improvable rather than merely present.

The script never blocks: missing `jq`, missing `state.json`, or malformed input all exit 0 silently. Losing an event is acceptable; interrupting a work session is not.

Non-stage commands (`/wf`, `/wf-init`, `/wf-jira`, `/wf-improve`) emit nothing.

## Project-level overrides

Projects can override global agents by placing agent files in `.claude/agents/`. Claude Code will prefer the project-local agent when both exist.

```
.claude/
├── agents/
│   └── rn-architect.md   ← overrides ~/.claude/agents/rn-architect.md
│                            with project-specific context
└── workflow/
    ├── config.json        ← stack, DoD, related projects
    ├── state.json         ← current workflow state
    ├── refinement-summary.md
    ├── plan.md
    └── review-findings.md
```

## Shared scripts

Installed to `~/.claude/scripts/`; commands invoke them by fixed path. Each replaces prose that was duplicated across commands and re-interpreted on every run.

| Script | Replaces | Notes |
|---|---|---|
| `wf-lib.sh` | The "Paso 0 — Identificar ticket activo" block, copied verbatim in 8 commands | `context`, `enter-stage`, `set-state`, `base`. `enter-stage` validates against the single stage vocabulary — an invalid stage fails loudly instead of silently breaking the iteration count (H12) |
| `wf-diff.sh` | The merge-base explanation, duplicated in 4 commands | Also handles the uncommitted-working-tree case, and `--weight` for review load (prod vs tests counted separately) |
| `wf-checks.sh` | DoD items that a command can answer exactly | Runs `checks` from `config.json`. `/wf-validate` runs it *before* spawning an agent — a linter answers "any console.log?" exactly and for free |
| `wf-event.sh` | "Append this JSON object to `events.jsonl`" as a prompt instruction | Builds the line with `jq` from named flags, filling `ts`/`project`/`ticket`/`stage`/`source` from state. Rejects unknown events and missing required fields |
| `wf-stats.sh` | Reasoning over the raw log by hand | One subcommand per §10 question, so a proposal can cite the query that produced it |

`wf_base` is the clearest case for why this matters: it used to be different prose in four files, one of which hardcoded `develop` regardless of the project's actual base branch.

## The review-plan gate

`hooks/wf-gate.sh` (`PreToolUse`) is the first mechanism in the system that can block. `wf-review-plan.md` says "NUNCA pasar a implementación sin respuesta explícita" — that's an instruction, obeyed nearly always. The hook enforces it: while a ticket sits at `stage: review-plan` without `approved: true`, edits to code are recorded or refused.

It deliberately breaks `wf-telemetry.sh`'s "never interrupt" principle, so its blast radius is contained by design — hooks live in the global `settings.json` and run in *every* project:

1. Exits silently when the repo has no `.claude/workflow/state.json`.
2. Fails **open** on any error (no `jq`, corrupt JSON, no git). Blocking because of a bug is worse than not blocking.
3. Ships in `observe` mode: emits `gate_would_block` to `events.jsonl` without preventing anything. `WF_GATE=enforce` turns on blocking; `off` disables it.

**Blocking is verified, not assumed** (2026-08-10). The unit tests only prove the script returns 2; whether the harness *honors* that was an open question. Confirmed end to end: with a ticket at `stage: review-plan` and `approved: false`, a `Write` to a non-excluded path was refused by the harness with the hook's stderr surfaced as the tool error. So `enforce` is a real gate, not a decorative one.

It stays in `observe` regardless until real `gate_would_block` events show it fires where intended and nowhere else — the risk was never that it fails to block, it's that it blocks the wrong thing across every project on the machine.

Artifacts of the workflow itself (`.claude/**`, `docs/**`, `*.md`) are always allowed — adjusting the plan during its own review is the work of that stage, not an escape from it.

## Install circuit

`install.sh` copies repo → `~/.claude/`. The reverse direction does not exist, so anything edited under `~/.claude/` is lost on the next install. Two commands used to edit there (`/wf-retro`, `/wf-improve`), which is how `wf-commit.md` and `wf-deploy.md` ended up installed with no source in the repo.

The circuit is now closed in three places:

| Mechanism | What it guarantees |
|---|---|
| `repo_path` in the global config, merged on every install (not skipped when the file exists) | `/wf-retro` and `/wf-improve` know where the source lives and edit there, then reinstall |
| `install.sh --check` | Reports drift without writing: differing files, missing files, and `wf-*` installed with no source in the repo |
| The `CLAUDE.md` block is regenerated between its markers on every install | The global command list can't go stale forever. Content outside the markers is never touched |

Every workflow change is recorded in `~/.claude/workflow/improvements.md` with its evidence. Per brainstorm §0: no evidence, no change.

`tests/test-install.sh` exercises all three against a sandbox `HOME`, so the real `~/.claude` is never touched: clean install, drift detection, `repo_path` merged into a pre-existing config, `CLAUDE.md` regenerated without disturbing content outside the markers, and third-party hooks in `settings.json` surviving reinstall.

## `AGENTS.md`

`/wf-init` offers to generate an `AGENTS.md` at the project root alongside `config.json`. They're not redundant: `config.json` is this system's format, `AGENTS.md` is what other tools read (Cursor, Codex, Copilot). The commands section is generated from `checks`, so both stay on the same real commands — an `AGENTS.md` with invented commands is worse than none. If the file already exists, `/wf-init` offers to update it rather than overwrite.

## Adding new agents

1. Create the agent file in the appropriate `agents/` subdirectory
2. Add the agent name to the `install.sh` copy step (it uses `find`, so no change needed)
3. Reference the agent in the relevant workflow command if it should be auto-suggested
4. Run `install.sh` to deploy
