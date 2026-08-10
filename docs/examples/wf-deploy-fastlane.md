---
description: "Example of a per-project override of /wf-deploy — React Native with fastlane and GitLab CI."
allowed-tools: Read, Bash, Glob
---

> **Example, not an active command.** This is the project-specific version for a
> React Native project (fastlane, GitLab CI, `pnpm`, branches `development`/`staging`/`master`).
> The generic command lives in `commands/wf-deploy.md` and detects the toolchain
> instead of assuming it.
>
> To use this version in the project that needs it: copy it to
> `.claude/commands/wf-deploy.md` at that project's root. Claude Code prefers
> the local command over the global one.

Your role is to prepare the git environment and guide the deploy according to the current branch and the available method.

## Step 0 — Parse arguments

Read `$ARGUMENTS` and extract:
- **TARGET** (`staging` | `production`) — if either word appears
- **METHOD** (`local` | `ci`) — if either word appears

Examples:
- `/wf-deploy staging` → TARGET=staging, METHOD=auto-detect
- `/wf-deploy local production` → METHOD=local, TARGET=production
- `/wf-deploy ci staging` → METHOD=ci, TARGET=staging
- `/wf-deploy` → both are determined later

## Step 1 — Verify git state

```bash
git status --short
git log origin/$(git branch --show-current)..HEAD --oneline 2>/dev/null || echo "(no remote tracking)"
git branch --show-current
```

Show:
```
📦 Git state:
  Current branch: [name]
  Uncommitted changes: [N files / none]
  Unpushed commits: [N / none]
```

## Step 2 — Detect the phase from the branch

| Current branch | Phase |
|---|---|
| Ticket branch (`MA-XXX`, `feature/*`, `fix/*`, any name that isn't protected) | **Phase 1** — prepare the MR |
| `development` | **Phase 2a** — create a release branch for staging |
| `staging` | **Phase 2b** — create a release branch for production |
| `release/*` | **Phase 2** — deploy directly |
| `master` / `qa` | ⛔ Blocked — the script rejects these branches |

---

## PHASE 1 — Prepare the MR (ticket branch)

### Commit + push if there are pending changes

If there are uncommitted changes, show the files and ask: **"Shall we commit? Which files do we include?"**

Once the files are confirmed, invoke the `wf-commit` skill to generate the message. Show it and ask for confirmation.

```bash
git add [confirmed files]   # never -A
git commit -m "[approved message]"
```

If there are unpushed commits:
```bash
git push origin $(git branch --show-current)
```
If the push fails due to divergence → show the error, ask for instructions. Do NOT force push.

### Report and stop

```
✅ Branch ready: [name]
📋 MR: [MR URL if it's in the push output, or tell them to create it in GitLab]

🔜 Next step (after the MR is approved):
   If it's a feature → merge to development → /wf-deploy staging
   If it's a fix on a deployed version → merge to staging → /wf-deploy production
```

Stop here. Do not continue to the deploy.

---

## PHASE 2 — Deploy (release branch)

### Step 2.1 — Determine TARGET if it wasn't passed as an argument

- If the branch is `development` → TARGET=staging
- If the branch is `staging` → TARGET=production
- If the branch is `release/*` → ask for TARGET if it wasn't passed as an argument

### Step 2.2 — Detect the available method

```bash
cat package.json 2>/dev/null | grep -E '"deploy:'
ls .gitlab-ci.yml .github/workflows/ 2>/dev/null
```

| Signal | Method |
|---|---|
| `deploy:*` scripts in package.json + a `Fastfile` | ✅ Local |
| `.gitlab-ci.yml` / `.github/workflows/` | ✅ CI |
| Both | Ask the user |

If METHOD already came as an argument, skip the question.

### Step 2.3 — Create the release branch (if we're on development or staging)

If the current branch is `development` or `staging`:
```
📦 You're on [branch]. To deploy, a release branch has to be created.

What will the version be? (e.g. 1.3.1)
```
Wait for the answer. Then:
```bash
git checkout -b release/[version]
git push -u origin release/[version]
```

### Step 2.4 — Run the deploy

#### METHOD = local

Before running the deploys, ask:
**"Which version do we use? (versionName and versionCode)"**

Show the current values for reference:
```bash
grep -E "versionName|versionCode" android/app/build.gradle | grep -v suffix | head -2
```

Wait for the answer. Resolve `VERSION_NAME` and `VERSION_CODE`.

**Android:**

Run it directly (non-interactive thanks to the parameters):
```bash
bundle exec fastlane android local_[TARGET] version_name:[VERSION_NAME] version_code:[VERSION_CODE] skip_confirm:true
```

Show the output in real time. Wait for it to finish.

**iOS** (after Android finishes):
```bash
bundle exec fastlane ios local_[TARGET] version_name:[VERSION_NAME] version_code:[VERSION_CODE] skip_confirm:true
```

Show the output. A 409 on the MR is normal — iOS prints the existing URL.

#### METHOD = ci

**GitLab CI:**
```
📋 Trigger the pipeline:
  1. GitLab → CI/CD → Pipelines → Run pipeline
  2. Branch: [current branch]
  3. Variables:
       VERSION_CODE = [integer, higher than the last published one]
       VERSION_NAME = [semver, e.g. 1.3.1]
  4. Click "Run pipeline"
```
Ask: "Have you triggered it? Let me know when it finishes."

### Step 2.5 — Final summary

```
✅ Deploy completed

  Method: [local / CI]
  Target: [TARGET]
  Android: [result]
  iOS: [result / 409 is normal]
  Branch: [release/x.y.z]
  Release MR: [URL]
```

If there were errors → help diagnose them.

---

## Quick reference

```
Feature flow:
  MA-XXX → /wf-deploy           → commit+push+MR → merge to development
            → /wf-deploy staging → from development → release/x.y.z → deploy staging → MR → staging

Fix flow (version already deployed):
  fix/MA-XXX → /wf-deploy            → commit+push+MR → merge to staging
               → /wf-deploy production → from staging → release/x.y.z → deploy production → MR → master
```

| Environment | Android local                    | iOS local                    |
|-------------|----------------------------------|------------------------------|
| staging     | `pnpm deploy:android:staging`    | `pnpm deploy:ios:staging`    |
| production  | `pnpm deploy:android:production` | `pnpm deploy:ios:production` |
