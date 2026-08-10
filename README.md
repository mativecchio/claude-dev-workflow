# claude-workflow

Automation system for the full development cycle in Claude Code. It covers everything from refining a ticket to reviewing the MR, with specialized agents per tech stack.

## Installation

```bash
git clone <repo-url> ~/claude-workflow
chmod +x ~/claude-workflow/install.sh
~/claude-workflow/install.sh
```

This installs:
- `wf-*` commands into `~/.claude/commands/` (available in any project)
- Language agents into `~/.claude/agents/`
- Base config into `~/.claude/workflow/`
- A reference to the system in `~/.claude/CLAUDE.md`

To reinstall after changing the repo:
```bash
~/claude-workflow/install.sh
```

---

## Usage

### Full flow from scratch

The entry point is always `/wf`. It detects which stage you're in from what you describe:

```
/wf I have ticket BC-1429, we need to add a date filter to the bookings list
→ detects: Refinement
→ runs: /wf-refine

/wf the plan is ready, it's already been reviewed
→ detects: Implementation
→ runs: /wf-implement
```

### Calling a stage directly

You can also invoke each command directly if you already know what you need:

| Command | When to use it |
|---|---|
| `/wf-refine` | Starting a new feature or ticket |
| `/wf-analyze` | When you need the technical plan |
| `/wf-review-plan` | To verify the plan before writing code |
| `/wf-implement` | To implement (also handles bugs/debugging) |
| `/wf-validate` | Post-implementation, before tests (includes a runtime validator over MCP) |
| `/wf-test` | To write tests and run the pre-MR checklist |
| `/wf-commit` | To generate the commit message with ticket context |
| `/wf-deploy` | For commit+push, release branch and deploy |
| `/wf-mr-desc` | To generate the MR description |
| `/wf-mr-review` | To code review an MR |
| `/wf-retro` | When closing a ticket, to extract lessons learned |
| `/wf-jira` | To generate or enrich a Jira ticket |

### Typical flow

```
/wf-refine   → defines scope and DoD
     ↓
/wf-analyze  → explores the codebase, generates plan.md
     ↓
/wf-review-plan  → verifies the plan → CHECKPOINT (explicit approval)
     ↓
/wf-implement    → implements in groups, with checkpoints
     ↓
/wf-validate     → (optional) validation gate per category
     ↓
/wf-test         → tests + pre-MR checklist
     ↓
/wf-mr-desc  → MR description
/wf-mr-review → code review
     ↓
/wf-retro    → (optional) retrospective → improves the workflow
```

### Runtime validation

`/wf-validate` offers a `📱 Runtime` validator alongside the ones that reason over the diff. It brings the app up over MCP (`metro` for React Native, `claude-in-chrome` for web), navigates to the affected screen and observes state, network and console.

It's for what a diff can't show: an ordering between effects, state left inconsistent when returning to a screen, a request that fires twice. It requires the app to be running — if no MCP is available it says so, rather than declaring validated something it never observed.

### Code review

`/wf-mr-review` delegates the generic pass to `/code-review high` (bugs, simplification, reuse, efficiency) and keeps what no generic reviewer can do: contrasting against `plan.md` and the acceptance criteria, contracts with `related_projects` verified against the other repo's actual code, and project conventions.

### Debug mode

`/wf-implement` automatically detects when there's a bug or error:

```
/wf-implement there's a 500 on the login endpoint when the email doesn't exist
→ debug mode activated
→ diagnosis first, then a plan, then a checkpoint before touching code
```

---

## Language agents

Agents are domain experts invoked on demand. They don't load context automatically — zero cost in projects that don't use them.

### React Native

| Agent | When to use |
|---|---|
| `rn-architect` | Component design, structure, refactors |
| `rn-debugger` | Errors in hooks, sagas, components (JS/TS) |
| `rn-performance` | Re-renders, memoization, FlatList, selectors |
| `rn-testing` | Unit tests (slices), integration tests (sagas) |
| `rn-uiux` | Layout, styling, accessibility, StyleSheet |
| `rn-bridge` | Native crashes (iOS/Android), NativeModules |

### React

| Agent | When to use |
|---|---|
| `react-architect` | Components, hooks, state management, Next.js |

### Shared

| Agent | When to use |
|---|---|
| `typescript-architect` | Complex types, generics, Zod, narrowing |
| `backend-api` | REST contract design, auth, responses |

### Python

| Agent | When to use |
|---|---|
| `python-architect` | FastAPI, Pydantic, async, project structure |

### Laravel / PHP

| Agent | When to use |
|---|---|
| `laravel-architect` | Controllers, services, Eloquent, Form Requests |

**Decision tree for RN:**
```
Is it a crash with a native stack trace (Swift/Kotlin)?  → rn-bridge
Is it a JS error in hooks, sagas, or components?         → rn-debugger
Is it a structure or design problem?                     → rn-architect
Is it slowness or re-renders?                            → rn-performance
Is it visual, layout, or styling?                        → rn-uiux
Is it tests?                                             → rn-testing
```

---

## Per-project configuration

Create `.claude/workflow/config.json` at the project root:

```json
{
  "stack": "React Native + TypeScript",
  "base_branch": "develop",
  "language": "en",
  "related_projects": ["backend-project-name"],
  "checks": {
    "lint": "npm run lint",
    "types": "tsc --noEmit",
    "test": "npm test"
  },
  "dod_checklist": [
    "Tests written and passing",
    "i18n keys added"
  ],
  "tech_debt_log": "docs/tech-debt.md"
}
```

The commands read this file to adapt the DoD, know about related projects and understand the stack. `/wf-init` generates it by detecting all of this from the project.

`/wf-init` also offers to generate an **`AGENTS.md`** at the root. It isn't redundant with `config.json`: the latter is this system's format, while `AGENTS.md` is the one other tools read (Cursor, Codex, Copilot). The commands come from `checks`, so both files point at the same real commands.

**`checks` vs `dod_checklist`.** Every DoD item that can be expressed as a command should live in `checks`. `/wf-validate` runs them **before** launching an agent: if the linter fails, there's no point spending an agent to opine on the same thing, with a chance of a false positive on top. `dod_checklist` is left for what genuinely requires judgment.

**`language`.** The language the commands address you in (`en` by default; set `"es"` for Spanish). It governs only what's spoken on screen — **everything written to disk is always in English**, regardless of this value: commit messages, plan.md, code, docs. The two are separate on purpose: a conversation has one reader, while a file gets read by other people and other tools long after the session ends.

**`base_branch`.** Each command used to resolve it on its own, and `/wf-refine` had `develop` hardcoded, which broke in any repo on `main`.

If a change touches state shared with a `related_project` (e.g. an object in sessionStorage that an external repo also reads), `wf-analyze` greps that project's local path to confirm the real behavior instead of assuming it, and `wf-review-plan`/`wf-validate`/`wf-mr-review` block the "APPROVED" if that verification wasn't done.

### Agents with project context

To override a global agent with project-specific context, create `.claude/agents/rn-architect.md` (or whichever applies) in the project. Claude Code will use the local one instead of the global one.

---

## Workflow state

It supports multiple tickets in parallel. The root state only records which one is active; each ticket has its own folder:

```
.claude/workflow/
├── state.json                    ← { "activeTicket": "BC-XXXX" }
├── BC-XXXX/
│   ├── state.json                ← current stage, progress, saved branch
│   ├── refinement-summary.md     ← output of /wf-refine
│   ├── plan.md                   ← output of /wf-analyze
│   └── review-findings.md        ← output of /wf-review-plan
└── BC-YYYY/
    └── state.json
```

`/wf` with no arguments shows a dashboard with every active ticket and its stage:
```
📋 Tickets:
  BC-XXXX  [stage]   ✅ [completed]   🎯 ← active
  BC-YYYY  [stage]   ✅ [completed]
```

To change the active ticket:
```
/wf BC-YYYY
```

To start from scratch (deletes the root `state.json`):
```
/wf reset
```

**Retroactive ticket:** if you activate a ticket that already has code commits on the branch but no `plan.md` (a ticket created after implementing), `/wf` offers to skip refine/analyze/review-plan instead of forcing the full flow — it asks for confirmation and starts directly at `implement`/`validate`.

**Branch mismatch:** if the current branch doesn't match the active ticket, `/wf` doesn't just warn — it offers to `git checkout` the branch saved from a previous session, or to create a new one (`{ticketId}-{slug}` from the base branch), with confirmation before running anything.

---

## Continuous improvement

The system improves itself via `/wf-retro` and `/wf-improve`:

1. Analyzes the session (rework, friction, iterations)
2. Cross-references the history in `~/.claude/workflow/flow-history.json`
3. Proposes concrete changes to the commands
4. Applies the changes with your approval

### What the data says

The commands record semantic events via `wf-event.sh` as they run: which defect appeared, which stage originated it, who caught it, what was decided. `wf-stats.sh` queries them:

```bash
~/.claude/scripts/wf-stats.sh              # summary
~/.claude/scripts/wf-stats.sh origins      # which stage originates the most defects?
~/.claude/scripts/wf-stats.sh leak         # how long does each one take to be caught?
~/.claude/scripts/wf-stats.sh detection    # are the gates degrading?
~/.claude/scripts/wf-stats.sh categories   # what repeats across 3+ tickets?
~/.claude/scripts/wf-stats.sh coverage     # is the log losing causes?
```

Two things the script does on purpose: it **always shows the sample size**, and it **refuses to conclude below 3 tickets** — it prints the numbers with an explicit warning instead of a conclusion. A percentage over 2 tickets is noise, and presenting it bare invites acting on it.

`coverage` is the one that audits the log itself: a re-entry recorded by the hook with no `finding` explaining it means the cause was lost. That number is the reason for having two capture layers.

**Wait until you have data.** At the time of writing, `events.jsonl` is empty — telemetry fills itself in as you run stages. Wiring `/wf-retro` to queries over an empty file would give a worse result than its current session analysis.

**The repo is the source of truth.** Changes are applied to `{repo_path}/commands/`, recorded with their evidence in `~/.claude/workflow/improvements.md`, and only then reinstalled. `repo_path` is written by `install.sh` into the global config.

Never edit `~/.claude/commands/` directly: it's an installation target and every change made there is lost on the next `install.sh` run.

To verify that the repo and the installed copy match:
```bash
~/claude-workflow/install.sh --check
```

---

## Versions

`VERSION` holds the current one, `CHANGELOG.md` records what changed in each. Versioning is semver applied to the *workflow contract* — commands, config schema, and the scripts commands call — so a major bump means an existing project's `config.json` needs attention.

`install.sh` stamps `installed_version` into the global config, which is what makes it possible to tell "the repo moved and I didn't reinstall" from "I'm up to date" without any network call.

**You get told automatically.** A `SessionStart` hook prints one short block when — and only when — there's something to do:

```
⬆️  Workflow update available
  claude-workflow v0.5.0 is in the repo, v0.4.0 is installed
  → ~/claude-workflow/install.sh
```

It reports two independent situations, because they need different fixes: the repo is ahead of what's installed (you edited or pulled and didn't reinstall), and origin is ahead of the repo (someone pushed and you haven't pulled).

This hook runs in **every** project on the machine, so it's built to be invisible: it never makes a network call on the session-start path (the `git fetch` runs in the background at most once a day, and the hook only ever reports from cache), and it exits silently on any error — no git, no config, unreadable cache. Disable it with `WF_VERSION_CHECK=off`.

For the full picture on demand:
```bash
~/claude-workflow/install.sh --check     # files, version, and status vs origin
```

---

## Repo structure

```
claude-workflow/
├── README.md
├── VERSION             ← current version, stamped into the global config on install
├── CHANGELOG.md        ← what changed in each release
├── install.sh          ← installs; `--check` reports divergences without writing
├── commands/           ← 15 wf-* commands
├── hooks/
│   ├── wf-telemetry.sh ← mechanical capture of the cycle → events.jsonl
│   ├── wf-gate.sh      ← the review-plan checkpoint, as a mechanism
│   └── wf-version.sh   ← SessionStart: warns when a newer version exists
├── agents/
│   ├── react-native/   ← rn-architect, rn-debugger, rn-performance, rn-testing, rn-uiux, rn-bridge
│   ├── react/          ← react-architect
│   ├── python/         ← python-architect
│   ├── laravel/        ← laravel-architect
│   └── shared/         ← typescript-architect, backend-api
├── scripts/            ← wf-lib, wf-diff, wf-checks, wf-event, wf-stats
├── tests/
│   ├── test-install.sh ← validates install.sh against a sandbox HOME
│   ├── test-scripts.sh ← validates the scripts and the gate against a temp repo
│   └── test-events.sh  ← validates wf-event and the 7 wf-stats queries
├── config/
│   └── workflow.json   ← global config template (repo_path)
└── docs/
    ├── architecture.md ← system design
    ├── brainstorm-metrics-and-complexity.md
    ├── plan-harness-migration.md   ← migration to a harness layer (in progress)
    └── examples/       ← reference per-project overrides
```
