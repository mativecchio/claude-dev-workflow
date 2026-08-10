---
description: "Step-by-step deploy: commit+push if there are pending changes, detects the phase from the branch and runs the deploy with whatever method is available (CI or local). If the project has no CI/CD or defined branching model, it says so and offers to set it up."
allowed-tools: Read, Bash, Glob, Grep
---

Your role is to prepare the git environment and guide the deploy according to the current branch and the method available in **this** project. Don't assume any specific tool: everything is detected or read from the config.

## Step 0 — Parse arguments

Read `$ARGUMENTS` and extract:
- **TARGET** — the destination environment, if it's named (`staging`, `production`, `qa`, whatever the project uses)
- **METHOD** (`local` | `ci`) — if either word appears

Whatever isn't passed as an argument is determined later.

**Language:** address the user in the language returned by `~/.claude/scripts/wf-lib.sh language` (`en` by default). Everything written to a file — commit messages, config, docs — is always in English.

## Step 1 — Read the project's branching model

Read `.claude/workflow/config.json`:

```json
"base_branch": "develop",
"deploy": {
  "branch_model": { "integration": "develop", "staging": "staging", "production": "master" },
  "release_branch_pattern": "release/{version}",
  "protected": ["master", "qa"],
  "commands": { "staging": "...", "production": "..." }
}
```

**If the `deploy` key doesn't exist**, don't invent it: continue with the Step 3 detection and apply Step 6 (missing-practices diagnosis) before running anything.

## Step 2 — Verify git state

```bash
git status --short
git branch --show-current
git log origin/$(git branch --show-current)..HEAD --oneline 2>/dev/null || echo "(no remote tracking)"
```

Show:
```
📦 Git state:
  Current branch: [name]
  Uncommitted changes: [N files / none]
  Unpushed commits: [N / none]
```

If the current branch is in `deploy.protected` → **stop**. Nothing is deployed or committed from a protected branch.

## Step 3 — Detect the available deploy method

```bash
ls .gitlab-ci.yml .github/workflows/ .circleci/ azure-pipelines.yml 2>/dev/null
grep -oE '"deploy[^"]*"' package.json 2>/dev/null
ls Fastfile fastlane/Fastfile Makefile Dockerfile 2>/dev/null
```

| Signal found | Method |
|---|---|
| CI config (`.gitlab-ci.yml`, `.github/workflows/`, etc.) | ✅ CI available |
| Deploy scripts in `package.json`, `Makefile`, or `deploy.commands` in the config | ✅ Local available |
| Both | Ask the user which one to use |
| **Neither** | Go to Step 6 before continuing |

If METHOD came as an argument, skip the question but still record what was detected.

## Step 4 — Determine the phase from the branch

| Current branch | Phase |
|---|---|
| Ticket branch (not listed in `branch_model` or `protected`) | **Phase 1** — prepare the MR |
| Integration branch (`branch_model.integration`) | **Phase 2** — create a release branch toward the next environment |
| Branch matching `release_branch_pattern` | **Phase 2** — deploy directly |
| Branch in `protected` | ⛔ Stopped at Step 2 |

---

### PHASE 1 — Prepare the MR

**Commit and push if there are pending changes.**

If there are uncommitted changes, show the files and ask: **"Shall we commit? Which files do we include?"**

With the files confirmed, invoke `/wf-commit` to generate the message. Show it and ask for confirmation.

```bash
git add [confirmed files]   # never -A
git commit -m "[approved message]"
git push origin $(git branch --show-current)
```

If the push fails due to divergence → show the error and ask for instructions. **Never force push.**

**Report and stop:**
```
✅ Branch ready: [name]
📋 MR: [URL if it appears in the push output, or where to create it]

🔜 Next step: after the MR is approved, merge to [integration]
   and run /wf-deploy [target] again from there.
```

Do not continue to the deploy.

---

### PHASE 2 — Deploy

**Determine TARGET** if it didn't come as an argument: derive it from `branch_model` (integration branch → next environment). If the model doesn't define it, ask.

**Create the release branch** if you're on an integration branch:
```
📦 You're on [branch]. To deploy, a release branch has to be created.
Which version? (e.g. 1.3.1)
```
Then, using `release_branch_pattern`:
```bash
git checkout -b [resolved pattern]
git push -u origin [resolved pattern]
```

**Run the deploy:**

- **METHOD = local** → run the command from `deploy.commands[TARGET]`. If the project needs version data (versionName/versionCode, tag, semver), ask for it **before** executing and show the current values for reference. Show the output in real time and wait for it to finish.
- **METHOD = ci** → show the concrete steps to trigger the pipeline (provider, branch, required variables) and ask: "Have you triggered it? Let me know when it finishes."

**Final summary:**
```
✅ Deploy completed
  Method: [local / CI]
  Target: [TARGET]
  Branch: [release branch]
  Result: [per platform/service]
```

If there were errors, help diagnose them.

---

## Step 6 — Missing-practices diagnosis

Run this **whenever** any of these pieces is missing. It doesn't block the deploy, but it's reported before anything runs — a manual deploy with no safety net is a decision, not a default.

| Missing | What to flag | What to propose |
|---|---|---|
| No CI config | There's no way to reproduce the deploy off your machine, or to audit it | Minimal pipeline: install deps, run the config's `checks`, build |
| CI exists but doesn't run the `config.json` `checks` | The quality gate exists locally but isn't enforced on the MR | Add lint/types/test to the MR pipeline |
| No `deploy.branch_model` in the config | The command has to guess the branching model on every run | Define it once in `.claude/workflow/config.json` |
| No protected branches | Anyone can push straight to the production environment | Protect the release branches on the remote |
| No versioning on the release | You can't tell what's deployed or roll back | Version tags, or `release_branch_pattern` with semver |
| No documented rollback | An incident turns into improvisation | Document the procedure in the README |

Warning format:

```
⚠️  Missing practices detected in this project:

  [missing piece] → [the concrete risk it implies]
  [missing piece] → [the concrete risk it implies]

Proposal: [the most important one from the table]

Continue with the deploy anyway, or set this up first?
```

Wait for an answer. If the user chooses to set it up, the `infra-checklist` skill covers the full infrastructure checklist.

If the user chooses to continue, proceed without asking again — the warning was already given.

---

## Note on projects with their own toolchain

A project with a very specific deploy flow (fastlane, Helm, Terraform, internal scripts) should create its own `.claude/commands/wf-deploy.md`, which overrides this one. This command is the generic one: it detects what's there, it doesn't assume tools.
