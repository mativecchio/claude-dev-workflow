# Changelog

Notable changes to `claude-workflow`. Format follows [Keep a Changelog](https://keepachangelog.com/); versioning is [semver](https://semver.org/) applied to the *workflow contract* — the commands, the config schema, and the scripts commands call.

- **major** — a change that breaks an existing project's `config.json` or removes a command
- **minor** — new commands, scripts, config keys, or events
- **patch** — fixes and docs

Versions 0.1.0–0.4.0 are reconstructed from git history: they were never tagged at the time, and the dates are the commit dates.

This file records *releases*. It is not the same as `~/.claude/workflow/improvements.md`, which records individual workflow changes with the evidence that justified them (brainstorm §0) and lives per-machine.

---

## Unreleased

### Added
- `/wf-mr-review` prior-comments ledger (Step 1a). The review reads every thread, resolved or not, and the user's existing drafts. It classifies each thread as `addressed`, `unaddressed` or `deferred` against the code at the MR head, not against the resolved flag. Findings already in the ledger are dropped and drafts are never duplicated. `unaddressed` threads go to a new *Existing threads* section instead of being restated as new findings. When the review disagrees with a comment, with evidence, it drafts a reply inside that thread. It never resolves a thread and never publishes.
- `/wf-mr-review --followup <MR>`: checks how the author answered the user's own comments, without a full review (no `/code-review`, no Agent). Each thread is judged against the code at the head (`fixed`, `answered, holds`, `answered, does not hold`, `partially fixed`, `no answer`, `new problem`), shown as a table, and offered as reply drafts.
- `/wf-mr-review --followup --code-review <MR>`: also runs `/code-review high` and keeps only the findings inside what changed since the user's last review. The since point is the MR version current at the user's last note, or the merge-base after a force push. The findings are deduplicated against the ledger and the threads' `new problem` verdicts, then offered as inline drafts.
- `/wf-mr-review` Step 2.2 — design reference for MRs that change the UI. The review looks for the design (spec `**Design**` + Design Study, MR description, ticket, plan) and asks the user when none is found, with the same four answers as constitution VIII in `booking-center-specs` (Figma URL, `None`, `[NEEDS DESIGN]`, `Agent-proposed`). The Agent compares against the Design Study when one exists, otherwise against the frame read through the Figma MCP, and reports design-fidelity findings. It also runs when there is no `plan.md` if a design reference exists. Found on booking-center-app !492: the Figma links were in the MR description and the review never opened them.
- `/wf-mr-review` Step 6: offer to add the review to the MR as draft comments. There is one per finding, anchored with `diff_refs` to a verified line, plus one general draft. They are written in the MR's language and never published by the agent.
- `/wf-mr-review` Step 7: the last step lists anything the review created locally and offers to remove it. Before removing anything, it checks for unpushed commits or uncommitted changes.

### Changed
- `/wf-mr-review` Step 6: each point is said once. The general draft keeps only the verdict, the findings that cannot be anchored and the questions no inline draft already asks; it is skipped when nothing is left. Found on booking-center-app !497, where the general draft repeated the question of the inline one.
- `/wf-mr-review` reads the MR's code from `origin/<source-branch>` (`git show`, `wf-diff.sh --branch`) and never creates a worktree, branch or clone (Step 1c). Reviewing a teammate's MR no longer writes `state.json` over the checkout's active ticket (Step 0). Found on booking-center-app !488: the review created a detached worktree and wrote a ticket state that had to be cleaned up by hand. An older review clone sat next to a worktree with unpushed commits and uncommitted changes, so deleting the "leftovers" blindly would have lost work.

## 0.9.1 — 2026-08-28

### Fixed
- The update notice never reached `/wf` or `/wf-refine`. `wf_version_notice` is printed by `context`, and those two run before an active ticket exists — `context` exits 1 there — so the two commands people actually start a session with were the only ones that stayed quiet about a stale install. Both now call `wf-lib.sh version-notice` directly in Step 0. Found by a user asking why `/wf` had not mentioned a new version; it had nothing to mention that time, but it could not have.

### Tests
- `tests/test-scripts.sh` asserts that all ten pipeline commands surface the notice, through `context` or directly. The wiring is a one-line call in a markdown file, which is exactly the kind of thing a refactor drops without a failing test.

### Docs
- `docs/architecture.md` claimed `context` printed the notice "at the top of every stage command". It described the intent, not the wiring, and the two commands it was wrong about were the entry points.

## 0.9.0 — 2026-08-27

Came out of a `/wf-retro` on BC-1624. Every item below carries its evidence in `improvements.md`.

### Added
- `wf-lib.sh related-check` — verifies each `related_projects[].path` resolves, and that the checkout it points at is the repo the entry claims (via its `origin` remote; `remote` overrides `name`). Runs inside `context`, so a broken path surfaces at the start of every stage instead of as a review finding three stages later.
- `wf-lib.sh commits [ticket]` — resolves a ticket's commits with `git log --grep`. Paired with a rule in `wf-commit` never to store a hash in a workflow artifact: a rebase turns every stored hash into a pointer to nothing while the content ships unchanged under a new one.
- `wf-lib.sh repo-check` and `relocate [ticket]` — a ticket may declare `"repo"` in its state; when it names another project, stages refuse to advance and `relocate` moves it into that repo's workflow. Each repo already runs its own workflow, so this is a guard that keeps a ticket in the right one, not multi-repo support.
- `wf-diff.sh --fetch` — refreshes `origin/<base>` through an explicit refspec before resolving the fork point. Remote-tracking ref only: no local branch moves, no merge, no working-tree change.
- `contracts.md`, written by `/wf-analyze` when `related_projects` is non-empty and the change touches a shared surface. Records both sides of each cross-repo contract with `file:line`; `review-plan`, `mr-review` and `validate` read it instead of re-deriving the same check.
- `/wf-implement` step 3.6: a new test must be proven to fail against the pre-change source. One that passes both before and after may stand as a non-regression guard but cannot be cited as an acceptance criterion's coverage.

### Changed
- **`related_projects` has a schema.** Entries are local checkouts addressed by a path relative to the project root: `{name, path, description?}`. URLs and entries with no `path` are now rejected loudly instead of skipped — a skipped entry made a broken config indistinguishable from an empty one. `/wf-init` populates the field from what it finds on disk (Step 3 already detected them; Step 5's template discarded them) and verifies it with `related-check` before writing. The `env_var` key is gone: nothing ever read it, and where a project is deployed says nothing about its source on disk.
- `wf-diff.sh` resolves the fork point against the tightest of `<base>` and `origin/<base>`. merge-base alone was not enough: a local base behind origin yields a fork point *earlier* than the real one. Measured on a real branch with a local base 12 commits behind — 31 files / 1165 lines / 20 commits against the local ref, versus 4 / 685 / 8 against origin's.
- `/wf-mr-review` runs `/code-review` sequentially and feeds its findings to the Step 3 Agent, with a rule for which reviewers run at all. In parallel the "don't repeat a finding" instruction was unenforceable — neither can see the other's output — and both had independently reported the same race in different words.
- `/wf-validate` requires a clean working tree, gains a scoped-checks mode for re-runs, reads `mr-review.md` and cuts the validators it already covers (skipping the Agent entirely is a valid outcome), and forbids its Agent from writing to the repo.
- `wf_model` resolves the model before judging the name, so `commit` — which carries a default without being a pipeline stage — still resolves. Exit codes now distinguish a resolved model (0), a real stage with no Agent (1, silent), and a name that exists nowhere (2, loud).

### Fixed
- `set-state stage` validated nothing, so any string could reach `.stage` through it and bypass `enter-stage`'s guard. Both doors now validate and suggest the closest real stage on a near-miss, ignoring separators and case.
- `wf_relocate_ticket` reported success it had not achieved: with a corrupt destination `state.json` it moved the directory, printed every success line and returned 0, leaving the ticket with no active pointer on either side. It now announces the move when it happens, names exactly what is left half-done, and returns non-zero. New `wf_json_update` performs each rewrite atomically and never leaks its temp file.
- `wf-diff.sh --fetch` degraded silently when the fetch failed. It now distinguishes "keeping the origin ref already on disk, which may be stale" from "no origin ref at all, falling back to the local branch" — and keeps the remote ref either way, because falling back to local is the defect `--fetch` exists to prevent.

### Tests
- `tests/test-scripts.sh` grew from 65 to 98 assertions, covering the stage vocabulary and its exit codes, `related_projects` validation, ticket-repo ownership, and both the failing and clean paths of `relocate` including the temp-file check.

---

## 0.8.0 — 2026-08-11

Phase 5 of `docs/plan-model-routing.md`, which completes it. This phase does not change any model — it makes the premise the rest of the plan rests on checkable.

### Added
- `wf-lib.sh implement-advice` — reads `complexity.json` and the ticket state and recommends a model for the implementation. `wf-implement` runs in the user's session, so nothing can switch anything: the recommendation is mechanical, the decision is the user's, and the command shows it without blocking.

  Conservative by construction. Approved plan, complexity ≤ 3, and a sister feature to follow recommends the smaller model; anything missing recommends staying strong. Advising a downgrade on a plan that was never verified is a worse failure than not advising one.

  It reads only structured data. Parsing prose out of `review-findings.md` was the obvious alternative and was rejected: a recommendation derived from a regex over markdown is wrong in ways nobody can predict, and this one has to be trustworthy or it will be ignored.
- `implement_started` event carrying `model_recommended` and `model_used`.
- `wf-stats.sh models` — re-entries to `implement` grouped by model, **restricted to strong plans**. The unconditional aggregate mixes in hard tickets implemented on a small model against advice, which buries the signal the query exists to find. It also counts how often the advice was followed.

### Notes
`model_used` is **self-reported**: no environment variable exposes the session's model, so it is the one field in the system a script cannot verify. `wf-implement` is instructed to report it accurately even when it contradicts the recommendation, because a disagreement between the two is the most informative row in the table.

The thesis — "a smaller model is fine for implementation when the analysis was strong" — is still a claim. This release is what will eventually confirm or refute it; `events.jsonl` needs accumulated tickets first.

## 0.7.0 — 2026-08-11

Phases 3 and 4 of `docs/plan-model-routing.md`: the bounded half of three commands moves into an Agent so it can be routed at all.

### Changed
- **`wf-mr-desc` Step 2, `wf-commit` Step 4 and `wf-test` Step 3 are delegated to an Agent** (`sonnet` by default; `wf-test` prefers the stack's testing agent, which declares its own model).

  These commands run in the user's session, where a command cannot choose the model. Moving their bounded half into an Agent is what makes routing possible — and it has a second payoff worth as much: the plan, the refinement and the full diff stop being loaded into the session's context window for work that never needed to be there.

  The split is between deciding and producing, not between important and unimportant. Choosing which gaps matter, adjusting the wording, and confirming before committing all stay in the session.
- `models` gains `mr-desc`, `commit` and `test`, all `sonnet`. Bounded transformation with a checkable result: sonnet is the adequate model there, not merely the cheaper one.
- `/wf-init` writes all seven keys.

### Notes
Each delegated step names the failure it has to watch for, because a smaller model fails quietly here: a description that reads well but misstates *why* a change was made, and a test that passes while asserting nothing. Both are usually input problems, and the instruction is to fix the prompt before reaching for a stronger model.

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
