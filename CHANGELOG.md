# Changelog

Notable changes to `claude-workflow`. Format follows [Keep a Changelog](https://keepachangelog.com/); versioning is [semver](https://semver.org/) applied to the *workflow contract* — the commands, the config schema, and the scripts commands call.

- **major** — a change that breaks an existing project's `config.json` or removes a command
- **minor** — new commands, scripts, config keys, or events
- **patch** — fixes and docs

Versions 0.1.0–0.4.0 are reconstructed from git history: they were never tagged at the time, and the dates are the commit dates.

This file records *releases*. It is not the same as `~/.claude/workflow/improvements.md`, which records individual workflow changes with the evidence that justified them (brainstorm §0) and lives per-machine.

---

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
- `tests/` — 96 checks across install, scripts and events.

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
