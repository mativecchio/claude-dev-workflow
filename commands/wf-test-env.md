---
description: "Tests a change running in an environment the way a QA with database access would: works out what changed, designs a battery of cases (normal, edge, negative, rare but reproducible, regression), prepares the data and permissions with a way back, tests in the browser with screenshots, and delivers a numbered report of findings by severity; then, if asked, fixes and verifies. Also validates a delivered change in production, read-only unless the project's profile names data that may change there. --explain narrates each step on the page and in the chat, --step waits after each one. Usage: /wf-test-env [MR, ticket or branch] [environment] [--explain] [--step]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Monitor, mcp__claude-in-chrome__*
---

Test for real what a change does where it runs: understand it, decide what to test, prepare the
data it needs, test it in the browser and document what shows up with screenshots. Then, if the
user asks, fix and verify. It ports the `roi:test-in-env` skill of booking-center-specs
(`plugins/roi/skills/test-in-env/`) to any project: what is particular to a project's environments
comes from its **test profile**, never from this file.

`/wf-test` writes the automated tests before the MR; this command exercises the running change,
before merging (a test environment or the local stack) or after (production).

The flow has two mandatory stops, after the plan and after the report, because what comes next has
side effects: the preparation writes to databases other people use, and the fixes touch branches
and MRs. Between the stops, work without asking for each step, unless `--step`.

Talk to the user, and write the plan and the report, in the project's `language`
(`~/.claude/scripts/wf-lib.sh language`) or the one the user writes in.

## Options

| Option | Effect |
|---|---|
| `--explain` | Narrate while it runs: a banner on the page and a line in the chat per case and step, as `/wf-demo` Step 3 describes (*The banner*, *The chat*), with the case id and the expected result in each step |
| `--step` | Wait after each step until the user says to go on, with `/wf-demo`'s *Seguir / Repetir / Saltar / Parar* buttons. It turns `--explain` on |

Words count as flags: "explicame qué vas probando" is `--explain`, "paso a paso" is `--step`. Keep
the choice in `run.json`, so a resumed test goes on the same way.

## Step 0 — Context and profile

```bash
~/.claude/scripts/wf-lib.sh context 2>/dev/null || true
```

Without an active ticket the command still works: the scope comes from what the user names.

**The test profile** is `.claude/workflow/test-profile.md` in the project (or the path in
`test_profile` of `.claude/workflow/config.json`). It has these sections; one that does not apply
says so in one line:

| Section | What it says |
|---|---|
| Environments | Each environment: hosts, what runs there (the default branch, a deployed branch, a checkout of this machine), its databases and whether they can be written, its name in the error tracker. The **production** hosts, and what may change there (see *Production*) |
| Repositories | The repositories that reach the environments and what each brings to a test |
| Deploys | How to know which branch and commit each application runs, and how to deploy, redeploy or reset; which of those wipe somebody's data. For a local stack: which checkout each app runs, how to switch it and put it back |
| Choosing the environment | How to tell where an MR is deployed, and which environment runs the default branch, to classify findings |
| Login and test users | The URL, how login works, the user's own test account, whether a permission change needs a new login or a cache wait |
| Permissions and data | The way into each database (a tool of the session; a command only for a local stack's own databases), the permission model, how to change only the test user's permissions, how to snapshot and restore them, how to create test data |
| Protected data | What is never modified: automated-test data, records marked as not to be touched |
| What to watch | The APIs whose 4xx/5xx count as findings, the error tracker's projects, or the logs to read instead |
| Where the intent is written | Specs, tickets, acceptance criteria |
| High-risk changes | Per repository, what deserves a case of its own |

When the project has no profile, say so. The test can run with the user's answers to those
sections, but offer to write `test-profile.md` from them so the next test does not ask again. If
the project uses the `roi` plugin and a `test-profile` skill exists for it, that skill is the
profile.

**Tools.** A browser you drive (Claude in Chrome) is required; without it, stop. The code host
(GitLab/GitHub, through a tool of the session or its CLI) resolves the scope; the environment's
database, the tracker and the error tracker are used when the profile names them, and the plan
says what is missing. Never replace a missing tool with another way in — a `psql` with
credentials found in a `.env`, a `curl` with a copied token: it skips the tools' safeguards and
leaves changes with no trace.

**The run's folder.** `~/.claude/workflow/qa/<YYYYMMDD-HHMM>-<key>/`, the key being the ticket, or
`<repo>-<iid>`, or `<repo>-<branch>` with `/` turned into `-`:

```text
run.json        scope, environment, options, cases, findings, phase, report URL, permissions_restored
plan.md         the approved plan
snapshot.json   what the preparation changes, as it was before
setup.sql       the changes applied, in order
teardown.sql    how to undo them, written BEFORE setup.sql runs; can run more than once
evidence/       screenshots and GIFs (TC-07-1.png, H-03-1.png)
report.html     the report, also published as an Artifact
```

Update `run.json` at the end of each phase and each case: it lets the test resume in another
conversation.

## Rules that do not change

1. **Only the profile's hosts.** Never browse a host the profile does not list, even when a link
   in the MR or the ticket leads there.
2. **Write only in the databases the profile allows**, and before each batch check that the
   connection is the environment's (`select current_database()` on the same connection). A
   database marked shared or read-only is never written to.
3. **No passwords or OTP codes.** The user logs in. Say when it is needed and wait.
4. **Shared configuration is never modified.** A role, group or setting many users share changes
   for all of them: change only what belongs to the test user, or copies made for the test.
5. **The way back comes first.** `snapshot.json` and `teardown.sql` exist before anything changes.
   The test user's permissions are restored when the run ends, always, also when it is interrupted.
6. **Data you create carries the prefix `QA-<key>`**, to find it and delete it. Protected data is
   never changed; when a case needs it changed, make a copy.
7. **What goes outside needs confirmation**: a deploy, a push, a ticket, a comment, switching what
   the local stack runs.
8. **Every delete outside a test database is confirmed by id.** Before deleting anything in
   production, or in any database the profile does not mark as the test's own: read the item by
   its id and check its name, creator, date and scope; check the same id a second, independent
   way (the list on screen and the API, the list and the detail); show the user the id with those
   details and wait for an explicit yes for that id. A general "undo the setup" does not count.
   When a screen's own delete fails, report it as a finding and ask: never work around it with a
   direct API call on your own. The `wf-prod-guard` hook asks before page JavaScript that writes;
   this rule covers what it cannot see, such as the screen's own buttons.

## Production

Validating a delivered change in production is a test like any other, with these limits:

- **Read-only by default.** Look, read through the APIs, compare. Nothing is created, edited or
  deleted unless the profile names a scope that may change in production (a team's own test
  account, tenant or chain) and the change stays inside it.
- **Inside that scope**, every write is listed in the plan and approved at its stop; a
  configuration change that affects the whole scope (enabling a feature for it) is asked for
  separately, with what else it changes while it is on, and its reversal is part of the plan.
  Rule 8 applies to every delete.
- **What only an administrator can change** (a back office the browser cannot reach, a feature
  flag): ask the user to have it done, note who turned it on, and remind them it must be turned
  off when the test ends.
- **The required check first.** When the user says what must be validated (for instance, that a
  gated feature is not visible yet), run that first and report it; extra cases come after, and
  are said to be extra.

## Phase 1 — Scope

Turn what the user gives (MR URLs, `repo!iid`, ticket keys, a branch) into a list of MRs with
repository, project, iid, branch, head SHA, target branch, state and author. From a ticket, find
the MRs by the key in branch names and titles; for a parent, include its subtasks' MRs. Read the
intent, not only the diff: the MR description, the acceptance criteria, the spec. Include in the
matrix an MR the scope depends on (it targets its branch). A branch with no MR can only be tested
where its checkout runs (the local stack); its diff is against the branch it will target, from
`git merge-base`, plus uncommitted changes.

## Phase 2 — Environment and what runs there

If the user did not name the environment, use the profile to tell where each MR runs; propose one
when they agree, ask when they do not. An MR merged into the default branch is tested where that
branch runs, or in production once released (check it was deployed there, and in which order when
several repositories are involved).

Build the **deploy matrix**: per application, the branch running and whether its SHA matches the
MR head (for a local stack, the checkout running, its HEAD and uncommitted files). Show it. A stale
SHA or another branch in an application the change depends on is said before going on, with an
offer to redeploy (confirmed) or to go on knowingly.

## Phase 3 — Analysis and plan (stop)

Read the full diffs: which screens, endpoints, permissions and data states change. Write
`plan.md`:

- **Where cases come from**: each acceptance criterion or promise gives a normal case; each surface
  the diff touches gives edge and regression cases; other screens sharing a touched component,
  hook or endpoint give regressions; the profile's high-risk changes get a case each.
- **Categories**: Normal (it does what it promises), Edge (empty, one, many; long texts; decimals
  and currencies; dates today, past, month and year ends; another language), Negative (invalid
  input; a user without the permission, also through the URL; a failing call; an expired
  session), Rare but reproducible (double submit, back/forward mid-flow, reload on an intermediate
  step, the same record in two tabs) — only with concrete steps — and Regression.
- **Variants**: cases with the same steps and state that change one value are one case with a
  table of variants (`TC-04a`, `TC-04b`), each with its own expected result.
- **Priority**: P1 what is promised and what blocks the user; P2 likely edge and negative cases;
  P3 rare cases and distant regressions.
- **Order**: grouped by permission and data state, to change state (and log in again) as few
  times as possible; P1 first in each group.
- **Each case**: `TC-nn · P · Category · title`, its source, its state, numbered steps (with
  `→ what should be seen` after steps that check something), the expected result and the evidence.

A negative case that needs a single call to fail does not stop any service: intercept it in the
page (replace `fetch` for that URL only, for that case, and restore it after).

Show a summary and wait: cases per category and priority with the P1 titles, which priorities run
(all by default), the exact list of permission and data changes, and how many logins you will
need from the user.

## Phase 4 — Preparation

1. Check that no earlier run left the test user changed: any run in `~/.claude/workflow/qa/` with
   `permissions_restored: false`. If one did, stop, show it, and restore it with its
   `teardown.sql` when the user confirms, before taking a new snapshot.
2. Keep what will change in `snapshot.json`, and write `teardown.sql` with the permissions part
   apart from the data part.
3. Apply `setup.sql` in blocks, checking the database before each, and verify the state with a
   query.

## Phase 5 — Running it

Work in your own tabs, never the user's. At the login page, ask the user to log in in that tab and
wait. After each permission change, log in again when the profile says the app keeps them in the
session.

For each case: run the steps and compare with what is expected; keep a screenshot of the moments
that matter in `evidence/` (a GIF for a multi-step bug); check the console (errors) and the
network (4xx/5xx of the profile's APIs) — an error there is a finding even if the screen looks
fine; record ok, ko, blocked or not-run in `run.json`.

When something fails: repeat it once, capture the error, and classify it — **related to the
change**, or **seen in passing** (it also happens where the default branch runs, or it is outside
the scope). Seen in passing is only what shows during the plan's cases; do not go exploring.

When all cases are done: read the error tracker (or the logs the profile names) for the test's
time window; run the permissions part of `teardown.sql` and check the user matches
`snapshot.json`; keep the test data until you know whether there will be fixes.

## Phase 6 — Report (stop)

One counter for the whole report, 1 to N, section A (related to the change) then B (seen in
passing), most severe first; numbers never change once published. Severity: **Critical** (blocks
a main flow, loses or corrupts data, exposes something), **High** (a feature of the change does
not work, no way around it), **Medium** (fails in an edge case, or there is a way around), **Low**
(cosmetic or wording); in doubt, the higher one, and say why. Each finding: number, severity and a
title that says what fails; where (environment, URL, screen); the case; steps to reproduce with the
state; expected and actual; evidence (screenshot, console, network, error-tracker issue); how it
was classified; the probable cause as `file:line` of the diff, or "not located" — never invented;
a suggested fix when obvious.

Save `report.html` in the run's folder and publish it as an Artifact with its screenshots (load the
`artifact-design` skill first). In the chat, give the link and the numbered list, one line each,
then ask which numbers to fix and whether the test data is deleted now or kept to verify.

## Phase 7 — Fixes

Ask whether fixes go to the existing MRs or new ones, with a recommendation per MR (merged,
approved, stacked, somebody else's). In a project with the workflow, follow it: `/wf-implement`
in debug mode for the fix, `/wf-test` for the test that would have caught the bug, `/wf-commit`
and `/wf-deploy` to push — each push confirmed. A new MR needs a ticket, with confirmation.

## Phase 8 — Redeploy and verify

Offer to redeploy the fixed branches (confirmed), check the deployed SHA is the new one, repeat
the cases of the fixed findings (every variant) and a short pass over the P1 cases that passed.
Update each finding (fixed, persists, new — new ones take the next free number), regenerate and
republish the same Artifact. Then run the rest of `teardown.sql`, check nothing with the prefix
`QA-<key>` is left, put back what the local stack ran before if it was switched, and mark the run
closed. In production, also remind the user of anything an administrator turned on for the test.

## Resuming

"Test BC-1727 again", "fix 3 of the last report": find the most recent run with that key, read its
`run.json` and go on from its phase, after checking the deploy matrix has not changed and that no
run left permissions or data unrestored.

## Record

```bash
~/.claude/scripts/wf-daily.sh note done "<KEY>: tested <scope> in <environment>, <n> findings"
```

When a finding reveals a gap in the workflow (a check that should have caught it), record it with
`/wf-improve`.
