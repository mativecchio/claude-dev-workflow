---
description: "Initializes the workflow in the current project. Scans the codebase, auto-detects the stack and DoD, and generates .claude/workflow/config.json. Run once per project from its root."
allowed-tools: Read, Write, Bash, Glob, Grep
---

You initialize the workflow system for this project. Your goal is to generate a useful `.claude/workflow/config.json` by scanning the project — without asking what you can infer.

**Language:** address the user in the language returned by `~/.claude/scripts/wf-lib.sh language` (`en` by default — this command usually runs before any project config exists). Everything written to a file — config.json, AGENTS.md, docs — is always in English.

## Step 1 — Detect the stack

Look for the following files at the project root:

**JavaScript / TypeScript:**
- `package.json` → read `dependencies` and `devDependencies` to detect:
  - React Native: `react-native` present
  - React (web): `react` present without `react-native`
  - Next.js: `next` present
  - Vue: `vue` present
  - Testing: `jest`, `vitest`, `cypress`, `playwright`
  - State: `redux`, `zustand`, `jotai`, `mobx`

**Python:**
- `pyproject.toml` or `setup.py` → detect FastAPI, Django, Flask, pytest
- `requirements.txt` → same

**PHP:**
- `composer.json` → detect Laravel, Symfony

**Multiple stacks:** if there's both a `package.json` AND a `composer.json`, it's a full-stack project — record both.

## Step 2 — Detect quality conventions

Look for:
- `.eslintrc*` or `eslint.config.*` → linter active → add "Linter passes with no errors" to the DoD
- `.prettierrc*` → formatter → add "Prettier passes" to the DoD
- `jest.config.*` or `vitest.config.*` → testing configured
- `cypress/` or `e2e/` → E2E available
- `.github/workflows/` → read the CI to understand what runs on each PR
- `phpunit.xml` or `pest.config.php` → PHP testing
- `pytest.ini` or `pyproject.toml [tool.pytest]` → Python testing

## Step 3 — Detect related projects

Look in:
- `.env` or `.env.example` → variables pointing at other services (API URLs, service names)
- `README.md` → mentions of other repos or services
- `package.json` → workspaces if it's a monorepo

## Step 4 — Detect structure and patterns

Scan the top-level structure to see whether there's:
- `docs/` → likely tech_debt_log at `docs/tech-debt.md`
- `src/i18n/` or `locales/` → i18n active → add "i18n keys added" to the DoD
- `migrations/` → migrations active → add "Migrations included" to the DoD

## Step 5 — Build the proposed config

Generate the config from what you detected and show it to the user before writing:

```
📦 Detected stack: [stack]
🧪 Test runner: [jest/pytest/pest/none]
🔍 Linter: [eslint/none]
🌿 Base branch: [develop/main/master]

📋 Proposed config:

{
  "stack": "[detected stack]",
  "base_branch": "[detected base branch]",
  "language": "en",
  "models": {
    "analyze": "opus",
    "review-plan": "opus",
    "validate": "opus",
    "mr-review": "opus"
  },
  "related_projects": [],
  "checks": {
    "lint": "[the project's real command]",
    "types": "[the real command, if applicable]",
    "test": "[the real command]"
  },
  "dod_checklist": [
    "Tests written and passing",
    "[items detected from the project]"
  ],
  "tech_debt_log": "[path if docs/ exists]"
}

Adjust it, or write it as-is?
```

**`base_branch`** — detect it with `git branch -a`: whichever of `develop`, `main`, `master` exists. If several do, ask which one is the integration branch. Without this field, every command that needs a diff has to guess it.

**`models`** — which model runs each of the four stages that spawn an Agent. Write it with these defaults and don't ask: analysis and verification carry the judgment the rest of the cycle rests on, so they get the strongest model. The point of writing it out is that it stops being inherited from whatever the session happens to be set to. The other eleven commands run in the user's session and have no model to set.

**`language`** — the language the commands address the user in (`en` by default). Files written to disk are always in English regardless of this value; it only governs what's spoken on screen. Ask only if the user brings it up — don't add a question for it to the flow.

**`checks`** — the highest-impact change in this config. These are the project's **real** commands, taken from the `package.json` scripts, the `Makefile`, or the CI: don't invent `npm run lint` if the script doesn't exist. Verify each one runs before writing it.

What goes in here stops depending on an agent's judgment: `/wf-validate` runs them before spending an Agent, and `/wf-test` uses them as the final run. A `dod_checklist` item that can be expressed as a command should live in `checks`, not in the prose list.

Ask only one thing if something remained unclear:
- If the stack wasn't detected → "What stack is this project?"
- If there are related projects it couldn't infer → "Are there related repos this project uses?"

## Step 6 — Write the files

If the user confirms (or adjusts):

1. Create `.claude/workflow/` if it doesn't exist
2. Write `.claude/workflow/config.json`
3. Create an empty `.claude/workflow/improvement-log.md`:
```markdown
# Improvement Log

_Record observations during the session with `/wf-improve <observation>`_
```

4. **`AGENTS.md` at the project root.** `config.json` is specific to this system; `AGENTS.md` is the format other tools read (Cursor, Codex, Copilot). Ask before creating it, and if it already exists, offer to update it instead of overwriting.

```markdown
# [Project name]

[One line: what it is.]

## Stack
[detected stack]

## Commands
- Install: `[command]`
- Tests: `[command from checks.test]`
- Lint: `[command from checks.lint]`
- Types: `[command from checks.types]`
- Build: `[command]`

## Conventions
[What was detected from the project: folder structure, test pattern,
state management, i18n. Only what was verified in the codebase, not assumed.]

## Base branch
`[base_branch]`
```

Keep `AGENTS.md` short and verified: the commands must be the real ones, the same as in `checks`. An `AGENTS.md` with invented commands is worse than not having one.

Confirm:
```
✅ Project initialized

Files created:
- .claude/workflow/config.json
- .claude/workflow/improvement-log.md
- AGENTS.md [if confirmed]

Ready to use. Start with /wf when you have a task.
```

## Note if a config already exists

If `.claude/workflow/config.json` already exists, show the current contents and ask:
**"A config already exists. Update it with what I detected, or leave it as-is?"**
