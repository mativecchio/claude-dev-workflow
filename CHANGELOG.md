# Changelog

Notable changes to `claude-workflow`. Format follows [Keep a Changelog](https://keepachangelog.com/); versioning is [semver](https://semver.org/) applied to the *workflow contract* — the commands, the config schema, and the scripts commands call.

- **major** — a change that breaks an existing project's `config.json` or removes a command
- **minor** — new commands, scripts, config keys, or events
- **patch** — fixes and docs

Versions 0.1.0–0.4.0 are reconstructed from git history: they were never tagged at the time, and the dates are the commit dates.

This file records *releases*. It is not the same as `~/.claude/workflow/improvements.md`, which records individual workflow changes with the evidence that justified them (brainstorm §0) and lives per-machine.

---

## 0.6.0 — 2026-08-11

Phases 1 and 2 of `docs/plan-model-routing.md`. Both correct values nobody chose, rather than making a behavioural bet — so neither needed data to justify.

### Added
- `wf-lib.sh model <stage>` and a `models` block in `config.json`. `WF_MODEL` overrides per invocation. An unknown model name falls back to `opus` with a warning instead of being passed through, since a typo would otherwise route a stage somewhere unintended.
- `context` now prints `model=` alongside `stage=` and `lang=`.

### Changed
- **The four Agent-spawning commands now pass `model` explicitly, defaulting to `opus`.** They passed nothing before, so the agent inherited the session's model — which made `plan.md`, the artifact every later stage consumes, a product of whatever the session happened to be set to. Running with fast mode on, or on Sonnet, silently produced the analysis everything else was built on. The same ticket could get two different qualities of plan on two different days for a reason invisible in the output.

  `validate` and `mr-review` are on `opus` for a distinct reason from `analyze`/`review-plan`: they catch what implementation got wrong, so they are the last thing to weaken if execution ever moves to a smaller model.
- **Language agents are tiered instead of uniform.** `typescript-architect`, `rn-architect`, `react-architect` and `ml-architect` move to `opus` — open-ended design whose output later code is written against. The other eleven stay on `sonnet`, now as a recorded decision: bounded work against a known stack with a checkable result. All 15 declared `sonnet` before, which read as intent but was a default nobody revisited.
- `/wf-init` writes the `models` block without asking.

### Fixed
- `tests/test-scripts.sh` read the real `~/.claude` config in one assertion, so the update notice could leak into it and the result depended on the machine running the suite.

Spend goes **up**, not down. That is the intended direction: four stages move from possibly-Sonnet to definitely-Opus, and four agents are promoted.

## 0.5.2 — 2026-08-10

### Changed
- The update notice moved out of a `SessionStart` hook and into `wf_version_notice` in `wf-lib.sh`, printed by `context` at the top of every stage command.

  **Why: the hook was verified not to work.** A logging probe confirmed it fires on session start, but its stdout never reaches the terminal — so the notice existed and nobody could see it. The alternative, letting it land in the model's context and trusting the model to mention it, is the prose-as-mechanism pattern this whole migration removes. The tradeoff is deliberate: no coverage outside the workflow, in exchange for a notice that is actually visible.

  It keeps the hook's containment rules: no network call on the path, no output unless there is something to do, silent and exit 0 on every error, `WF_VERSION_CHECK=off` to disable.

### Removed
- `hooks/wf-version.sh`. Reinstalling deletes the file and strips its `SessionStart` registration from `settings.json` — a `SessionStart` hook belonging to anyone else is left untouched.

## 0.5.1 — 2026-08-10

Findings from reviewing 0.5.0 before merging it to `main`.

### Removed
- `scripts/wf-probe.sh`. It was a temporary diagnostic for the H1 experiment, which concluded — but it was still being installed on every machine, and it dumps the raw JSON of every tool call (including tool inputs) to disk. Dead code with a privacy footprint is worse than dead code. It stays in git history if the experiment ever needs repeating.
- `--json` from `wf-stats.sh`. It was advertised in the usage text and accepted as an argument, but never implemented — so it silently produced normal output. An option that lies is worse than a missing one.

### Fixed
- `install.sh --check` aborted with exit 127 and no message on a machine without `jq`: the version lookup failed under `set -e`. It now degrades with an explicit warning and, importantly, stops reporting a false divergence. This is the machine that most needs a clear diagnosis, since without `jq` the hooks also silently record nothing.
- `CHANGELOG` claimed 96 tests when there were 107.

## 0.5.0 — 2026-08-10

The harness migration: rules that used to live as prose in `.md` files, obeyed almost always, become scripts and hooks that cannot be skipped. Plan and diagnosis in `docs/plan-harness-migration.md`.

### Added
- `scripts/wf-lib.sh` — shared context resolution (`ticket`, `dir`, `base`, `state`, `enter-stage`, `language`). Replaces the "Step 0" block that was copied verbatim into 8 commands.
- `scripts/wf-diff.sh` — merge-base diffing, plus `--weight` (production vs test lines counted separately).
- `scripts/wf-checks.sh` — runs the project's `checks`. `/wf-validate` runs it *before* spawning an agent.
- `scripts/wf-event.sh` — semantic events, built with `jq` from named flags rather than assembled as JSON in a prompt.
- `scripts/wf-stats.sh` — one subcommand per §10 question, plus `coverage` to audit the log itself. Always reports sample size; refuses to conclude below §0's three-ticket minimum.
- `hooks/wf-gate.sh` — the review-plan checkpoint as a mechanism. Ships in `observe` mode. **Verified to actually block**: the harness honors `exit 2`.
- `install.sh --check` — reports drift between repo and installed copy, including orphans.
- Runtime validator in `/wf-validate` (option 6), over the `metro` / `claude-in-chrome` MCPs.
- `/wf-mr-review` delegates the generic pass to `/code-review high`.
- `/wf-init` generates `AGENTS.md` and the `checks` / `base_branch` / `language` config keys.
- `commands/wf-commit.md` and `commands/wf-deploy.md` adopted into the repo (they were installed with no source). `wf-deploy` is now toolchain-agnostic and reports missing CI/branching practices instead of assuming them.
- `tests/` — 107 checks across install, scripts and events.

### Changed
- Stage vocabulary unified on `refine` (was `refinement` in one place, which silently broke re-entry counting).
- Every stage command now registers its entry via `wf_enter_stage`; previously only `/wf` and `/wf-refine` did.
- `install.sh` merges `repo_path` into an existing global config instead of skipping the file, and regenerates the `CLAUDE.md` block between its markers instead of leaving it stale forever.
- The whole repo is in English; `language` in a project's `config.json` controls only what's spoken on screen.

### Fixed
- `/wf-refine` had `develop` hardcoded as the base branch, breaking any repo on `main`.
- `/wf-jira` and `/wf-commit` used pre-multi-ticket flat paths.
- `/wf.md` had "Step 1" before "Step 0".
- Findings against an always-empty `flow-history.json` were downgraded from blocking to advisory.

### Known limitations
- `events.jsonl` starts empty, so `wf-stats.sh` has nothing to report until real stages accumulate.
- The `flow-history` gate and wiring `/wf-retro` to the stats are deliberately deferred until there are ~10 recorded tickets.
- Complexity and MR-weight thresholds are provisional and unvalidated (§5.4, §6.4).

---

## 0.4.0 — 2026-08-07

### Added
- `hooks/wf-telemetry.sh` — mechanical capture of the cycle into `events.jsonl` on four hook events.
- `docs/brainstorm-metricas-y-complejidad.md` — the measurement design: metrics, event schema, complexity rubric, MR weight, and the §0 grounding rule.

### Fixed
- Stage re-entries are counted on the ticket's `state.json`, not per session, so a ticket re-analyzed days later still counts as a re-entry.

## 0.3.0 — 2026-08

### Added
- `related_projects` contract verification: commands grep the sibling repo's real source instead of assuming its behavior, and block "APPROVED" when that check wasn't done.
- Per-finding picker in `/wf-validate` (implement / ignore / tech-debt) replacing all-or-nothing.
- Shared-storage race detection in `/wf-analyze`.

### Changed
- Diffs resolve against `merge-base(HEAD, base)` instead of `base..HEAD`, which broke silently when the base advanced after the branch was created.
- Retroactive-ticket mode: tickets with commits but no `plan.md` skip refine/analyze/review-plan.

## 0.2.0 — 2026-06

### Added
- Multi-ticket state: root `state.json` tracks only `activeTicket`; everything else is per-ticket.
- Branch validation on `/wf` start, with concrete checkout/create actions.
- `/wf-init` for automatic project config detection.
- `/wf-improve` and the ML/CV agents.

## 0.1.0 — 2026-05

Initial system: 11 commands and 11 language agents.
