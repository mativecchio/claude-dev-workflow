---
description: "Full MR/PR review. Runs in an isolated context via the Agent tool. Given an MR link it reads the real MR from GitLab/GitHub (MCP or CLI) and falls back to the local git diff. Structured output: critical, important, suggestions. Takes prior threads into account and drafts replies where it disagrees. Detects spec MRs (Spec Kit repos) and reviews them with a spec checklist instead of /code-review; --spec / --code force the mode. With --followup <MR> it only checks the answers to your own comments; add --code-review to also run /code-review on what changed since your last review."
allowed-tools: Read, Bash, Glob, Grep, Agent, TodoWrite
---

Your role is to prepare the context and launch a full MR review in an agent with a clean context.

## Step 0 — Ticket context

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage mr-review
```

If `context` fails, ask for the ticket and write `.claude/workflow/state.json` before retrying.

**Exception — reviewing someone else's MR.** When the MR's ticket has no workflow directory in this
repo (a teammate's MR, a ticket this machine never worked on), do not write `state.json`: it would
replace the active ticket of whoever is working in this checkout. Take the ticket from the MR title,
skip `enter-stage` and Step 5, and carry on. `lang` then comes from `.claude/workflow/config.json`.

**Language:** address the user in the language reported as `lang` by `context` (`en` by default). Everything written to a file — the review, plan.md, code — is always in English.

## Follow-up mode — `$ARGUMENTS` carries `--followup`

Checks how the author answered **the current user's own comments**, without running a new review.
It needs an MR reference; without one, ask for it. Do Step 0 as usual. From Step 1, run only 1a
(host, ledger) and 1c (read the code at `origin/<source-branch>`). Then go straight to the steps
below: no Step 3 Agent and no Step 5 events. `/code-review` does not run either, unless
`$ARGUMENTS` also carries `--code-review` (step 5). The threads are judged inline, one by one,
because the work is small.

1. **Select the threads.** From the ledger, keep the threads whose first note is the current user's
   (`whoami`) that have something new since the user's last note: a reply from someone else, or a
   commit on the source branch after it (`list_commits` / `git log origin/<source-branch>
   --since=<note date>`). Also keep open threads with no answer, because they are still pending. Skip
   threads the user already answered last.
2. **Judge each one against the code at the MR head**, not only against the reply text:
   - `fixed`: the change the comment asked for is at the head (cite the `file:line` and the commit).
   - `answered, holds`: no change, but the author's reasoning holds. Say why in one line.
   - `answered, does not hold`: the reply misses the point, or contradicts the code, the spec or a
     contract. Give the evidence.
   - `partially fixed`: some of it is done. Say what is still missing.
   - `no answer`: open and untouched.
   - `new problem`: the fix itself introduces a defect. Report it at its line.
3. **Show a table** with thread id, `file:line`, your comment in one line, the author's answer in one
   line, the verdict, and the proposed action: *resolve*, *reply* or *wait*.
4. **Offer the drafts.** Ask: **"Do you want me to add the replies as drafts?"** On yes, follow the
   Step 6 rules: one reply draft per `answered, does not hold` / `partially fixed` / `new problem`
   thread, in the MR's language, two or three lines with the evidence. Use `in_reply_to_discussion_id`
   on GitLab, or the pending review on GitHub. For `fixed` and `answered, holds`, a short
   acknowledgement draft is added only if the user asks for it. **Never resolve a thread and never
   publish.** List which threads look ready for the user to resolve themselves after publishing.
   With `--code-review`, step 5's findings are offered in the same question.
5. **Only with `--code-review`: generic pass on what changed since the user's last review.**
   - **Since point.** Use the MR's head SHA at the user's most recent note on this MR: on GitLab,
     the newest entry of `list_merge_request_versions` created before that note (`head_commit_sha`),
     or that note's `position.head_sha` when it is a diff note; on GitHub, the `commit_id` of the
     user's last review. Not reachable from the head (rebase and force push) → use the merge-base of
     that SHA with the head and say so. The user has no note on this MR → there is nothing to follow
     up; say so and suggest the full review instead.
   - **Increment.** `git diff <since>..origin/<source-branch>`. Empty → skip this step and say so.
   - **Run** `/code-review high origin/<source-branch>` and wait for it. Keep only the findings whose
     lines fall inside the increment's hunks. Drop the rest: they were already in front of the user
     in the previous round. If `/code-review` is not available, review the increment inline for the
     same scope (bugs, security, performance, simplification) and say so. In spec mode (Step 1d),
     `/code-review` does not run: apply the spec checklist (Step 3, section 2b) inline to the
     increment instead, and say so.
   - **Deduplicate** each finding against the ledger and against the `new problem` verdicts from
     step 2. The same defect counts once, in the thread where it belongs.
   - **Show** the findings as a second block below the table, in the 🔴 / 🟠 / 💡 format of the full
     review, headed with the since SHA and the number of commits in the increment.
   - **Drafts** follow Step 6: one inline draft per finding, anchored to a line of the increment.
6. Finish with Step 7.

## Step 1 — Get the MR

### 1a — If `$ARGUMENTS` carries an MR/PR reference, read the real MR first

A link (`https://gitlab.com/.../merge_requests/123`, `https://github.com/.../pull/123`) or a bare
`!123` / `#123` means the MR exists on the host. **Go to the host before touching the local diff.**
In order:

1. **MCP for that host**, if this session has one (`mcp__gitlab__*`, `mcp__github__*`). Add the tools
   you use to `allowed-tools` for the session; the frontmatter can't list servers that may not exist.
2. **CLI**, otherwise:
   ```bash
   glab mr view <ref> --comments   &&  glab mr diff <ref>    # GitLab
   gh pr view <ref> --comments     &&  gh pr diff <ref>      # GitHub
   ```
3. **Neither reachable** (no MCP, CLI missing or unauthenticated, host unreachable) → fall back to
   `wf-diff.sh` below and **say so in the Step 4 output**: the review ran against the local branch,
   not against the published MR.

From the MR, carry into Step 3: **title and description, target branch, source branch and its head
SHA, state, and existing review comments**.

**Pipeline and rebase state are not findings.** CI gates the merge: a red, missing or running
pipeline, or a branch that needs a rebase, cannot be merged anyway, so the author already sees it.
Never list it in the review, the executive summary, the action list or the drafts. Open a failed
job's log only if the failure may reveal a defect in the diff itself; if it does, report the defect
at its line, not the pipeline.

**An empty or `null` comment list is not proof there are none.** The GitLab MCP's `mr_discussions`
wraps its answer as `{items: [...], pagination: {...}}`. A `jmespath` filter written as if the answer
were a bare list (`[].{…}`, `[?…]`) returns `null`, and that `null` once passed for "no threads" on MRs
with eleven and eighteen reviewer notes. Filter from `items[]`, and check `pagination.x_total` against
the number of threads you got. Before writing "no previous comments", cross-check with
`get_merge_request_notes` (filter `system == false`); if the two disagree, trust the one that
returned notes. Resolved threads count too: a suggestion the author already answered and deferred
is covered, not a new finding.

**The flat notes are not a ledger.** `get_merge_request_notes` returns no discussion ids, so a review
built only on it cannot reply inside a thread, and tends to post a new comment beside an existing one.
When the notes show threads, `mr_discussions` has to return them too before the ledger is complete.

**Build the prior-comments ledger.** Read every thread, resolved or not, with all its replies
(`mr_discussions`, paginated with `per_page: 100` until a page comes back short; `gh pr view --comments`
plus `gh api repos/{owner}/{repo}/pulls/{n}/comments` on GitHub). Also read the drafts that already
exist (`list_draft_notes`) and the current user (`whoami`): drafts from an earlier run of this review
are invisible to everyone else but count as already said. For each thread record:

| Field | Content |
|---|---|
| `id` | discussion id (GitLab) / thread or comment id (GitHub) |
| `who` | author of the first note, and whether it is the current user |
| `where` | `file:line`, or `general` |
| `claim` | one line: what the comment asks for |
| `state` | `resolved` / `open`, and the last reply (author's answer, deferral, "won't fix") |
| `status` | `addressed` (the diff at the MR head fixes it, or the reviewer accepted the answer) · `unaddressed` (still open and the head does not fix it) · `deferred` (author answered with a reason and a follow-up) |

Decide `addressed` against the code at the MR head (`git show origin/<source-branch>:<path>`), not
against the thread's resolved flag: a thread resolved without a change is not addressed, and an open
thread whose line was already fixed is.

Pass the ledger to the Step 3 Agent. **Why:** each round of review on an MR that already has
comments has repeated them back at the author in new words, and the author then answers the same
point twice.

**Then compare the MR's head SHA against the local branch.** If they differ, say which way and review
the MR's diff — the local tree may hold unpushed commits, or the MR may be ahead of it. Same for the
target branch: if the MR targets something other than the project's base branch, the MR's target
wins.

**Why the host first:** the link is not a label. Without it the review is blind to the MR's real
state — a wrong target branch, unpushed local work, and comments other reviewers
already left (which it will then repeat back at the author).

### 1b — The diff

```bash
~/.claude/scripts/wf-diff.sh --log --fetch
~/.claude/scripts/wf-diff.sh --stat
~/.claude/scripts/wf-diff.sh
```

**The first `wf-diff.sh` call of the stage carries `--fetch`.** It refreshes `origin/<base>` (the
remote-tracking ref only — no local branch, no merge, no working-tree change) so the fork point is
computed against the real base rather than a stale local one. If it warns that the local base is
behind, **that warning is the whole point** — without the refresh the diff would have carried other
tickets' merged commits as if this feature had written them. Do not silence it and do not "fix" it
by pulling the base branch.

If `$ARGUMENTS` carries a specific branch, add `--branch [branch]` to each call. If 1a resolved an
MR whose source branch is not the current one, pass that branch here.

The script resolves the merge-base against the project's base branch. This matters: `[base]..HEAD` breaks if the base advanced through a pull or fast-forward after the feature branch was created, and ends up showing other people's changes as if they belonged to the MR.

If the diff is very large (>500 lines), show the `--stat` to the user and ask whether to continue or narrow the scope. To size it properly:
```bash
~/.claude/scripts/wf-diff.sh --weight
```

`weight_prod` is what matters — `weight_tests` is kept separate, because a 300-line MR where 220 are tests isn't a big MR, it's a well-covered one.

### 1c — Read the code without checking it out

A review never creates a worktree, a branch or a clone, and never switches the current checkout.
When the MR's source branch is not the one checked out, read it from the remote-tracking ref:

```bash
git fetch origin <source-branch>
~/.claude/scripts/wf-diff.sh --branch origin/<source-branch>
git show origin/<source-branch>:<path>          # any file, at the MR's head
```

Pass the same ref to `/code-review` in Step 2.5 and to the Step 3 Agent, so both read the MR's code
rather than whatever the checkout holds.

**Why:** a review is read-only work. A worktree per review leaves a directory, a `.git/worktrees`
entry and possibly a `state.json` behind on every run, and the user has to find and delete them by
hand. If something local is ever unavoidable, note its path and offer to remove it in Step 7.

### 1d — Review mode: code, spec or mixed

A spec MR and a code MR are reviewed with different checklists. Everything else in this command is
the same for both: the ledger, the drafts, the tone, and leaving nothing behind.

**Detect the mode from the changed files** (`list_merge_request_changed_files`, or
`wf-diff.sh --stat`):

- **spec**: the repo uses Spec Kit (`.specify/` exists at `origin/<target-branch>`), and every
  changed file is a feature artefact or a document: `specs/**`, or `*.md` outside source folders.
- **code**: no changed file is a spec artefact. This is the default for any repo without `.specify/`.
- **mixed**: both kinds of file change. Each part is reviewed with its own checklist, and the output
  says which files went to which side.

**`$ARGUMENTS` may override the detection**: `--spec` forces spec mode, for example for a design
document in a code repo that should be reviewed as a spec. `--code` forces code mode. An override
applies to the whole diff.

**Say which mode ran and why** in the executive summary (`mode: spec — .specify/ present, only
specs/** changed`), so a wrong detection is visible at once.

**Why:** the code checklist (bugs, tests against the refinement, design fidelity) found nothing in
spec MRs, and `/code-review` has no bugs to look for in markdown. On booking-center-specs !28 and !30,
the findings came from checks the command did not have. A plan said "Pass" on a constitution
principle it broke. Untouched artefacts (`tasks.md`, `deployment.md`) contradicted the new plan.
A contract made a claim about an error that the real code did not do. Two open MRs described the
same endpoint differently.

## Step 2 — Gather context

Read:
- `{workflowDir}/plan.md` → context of what was implemented
- `{workflowDir}/refinement-summary.md` → acceptance criteria
- `CLAUDE.md` or `README.md` → stack and conventions
- `.claude/workflow/config.json` → the project's stack

## Step 2.1 — Architecture and scaffolding rules

Every review checks the diff against the repo's own written rules on where code goes and what it is
called. A summary of `CLAUDE.md` is not enough: in many repos `CLAUDE.md` is only a pointer, and the
rules live in other files.

**Collect the rules from the MR's target branch** (`git show origin/<target-branch>:<path>`), not
from the source branch, so that an MR cannot pass review by changing the rules it is judged against.
If the diff itself edits one of these files, review that edit as a change to the rules and say so.

1. **Agent instructions, following pointers.** Start at `CLAUDE.md` / `AGENTS.md`. When one says the
   instructions live elsewhere (`.github/copilot-instructions.md`, `docs/…`), read that file too.
   Stop at the file that holds the content.
2. **Architecture documents** named by those instructions, plus the usual places when they exist:
   `docs/project-architecture-guidelines.md`, `docs/architecture*.md`, `ARCHITECTURE.md`.
3. **ADRs** (`docs/adr/`, `adr/`): read the index or the titles. Read in full only those that cover
   what the diff touches (state management, testing, naming, a layer the diff adds files to).
4. **Lint rules that encode structure**, when the repo has them: import boundaries, custom rules
   such as `eslint-rules/`. A rule the linter already enforces is not a review finding. Only note
   what the linter cannot see.

**Extract the rules the diff can break**, each with its source (`path#section`):
- layers and what each one may import or contain;
- folder and scaffolding structure: the layout of a page or container, what lives inside a container
  and what goes in a global folder, where tests and fixtures go;
- naming of files, components, hooks and modules;
- "reuse first" rules, together with the global folders they point to (hooks, utils, components),
  so the Agent can check whether an existing helper already covers the new code;
- decisions recorded in the ADRs that apply.

**Nothing found** → say so in the executive summary ("no written architecture rules found; checked
<paths>"), and the Agent reviews architecture only for consistency with the sibling code around the
diff.

**Why:** the review only asked whether the solution "made sense architecturally", and gave the Agent
a summary of `CLAUDE.md`. In booking-center-app, `CLAUDE.md` and `AGENTS.md` only point to
`.github/copilot-instructions.md`, and the layer, container and reuse-first rules sit in
`docs/project-architecture-guidelines.md` and `docs/adr/`. No step read any of them, so whether a
review caught a file in the wrong layer, or a hook that already existed, depended on luck.

**In spec mode the rules are the Spec Kit ones**, collected the same way, from the target branch:
- the constitution (`.specify/memory/constitution.md`), every principle;
- the repository registry and delivery rules (`.specify/memory/repos.md`, `delivery.json`), when
  the repo has them;
- the workflow and delivery docs the agent instructions point to (`docs/workflow.md`,
  `docs/delivery.md`, or their equivalent): when a change amends a spec, and when it has to be a
  new one; how deferred decisions are recorded and resumed;
- the templates and their overrides (`.specify/templates/`): the sections a spec and a plan must
  have;
- the annotation conventions, read from the specs already on the target branch (`git grep` for
  `Superseded` and similar notes): their exact format, and what each note must name.

## Step 2.2 — Design reference (MRs that change the UI)

**Applies when** the diff changes what the user sees: components, pages, templates, styles,
SVG/image assets, visible copy (locale files). A backend-only or test-only diff skips this step.
So does spec mode: the spec carries its own design reference, and the spec checklist checks it
against the design principle of the constitution. Nothing is asked of the user.

**Look for the design, in order**, and stop at the first hit:
1. A spec for the feature (Spec Kit repos: `specs/<feature>/spec.md`) — its `**Design**` header
   line and, if it exists, the **Design Study** in its `plan.md`.
2. The MR description (from Step 1a) — Figma URLs.
3. The ticket (Jira via MCP, when available) — Figma URLs.
4. `{workflowDir}/plan.md` and `refinement-summary.md`.

**Nothing found → ask the user before launching Step 3.** Do not infer the interface from the diff
or from screenshots in the MR. Accept the same four answers as the Spec Kit rule (constitution
VIII in `booking-center-specs`):
- a Figma frame URL with its `node-id`;
- `None` — nothing visual actually changes;
- `[NEEDS DESIGN]` — the design does not exist; the review goes on, and adds to *Questions for the
  author*: "This MR changes the UI and links no design. Which design was it built against?";
- `Agent-proposed` — only if the author asked for that in so many words; review for internal
  consistency and against the design system only.

**What the Step 3 Agent compares against:**
- A **Design Study** exists → compare the diff against the Design Study, not against Figma. The study
  is the frozen reading; re-reading Figma at review time is how the review and the implementation
  reach two different conclusions about the same frame.
- Only a **Figma URL** → read the frame(s) through the Figma MCP, in this order of authority:
  `get_context_for_code_connect`, `get_variable_defs`, `get_design_context`, and `get_screenshot` for
  the visual check only. Pass the extracted values, not the raw dump, into the Step 3 prompt. One
  frame per breakpoint when the MR says it covers more than one (e.g. desktop and mobile).
- **Figma MCP unavailable or the frame not readable** → say so in the executive summary and review
  without it. Never estimate measurements from a screenshot.

**Why:** a UI MR reviewed without its design can only check that the code is internally consistent.
Whether the spacing, copy, breakpoints and pieces on screen match what was designed goes unreviewed.
In practice the Figma links sat in the MR description and the review never opened them.

## Step 2.5 — Delegate the generic review

Two reviewers exist because they cover different things, not because two passes are safer:

| | `/code-review` (this step) | Step 3 Agent |
|---|---|---|
| Bugs, security, performance | ✅ | excluded |
| Simplification, reuse, efficiency | ✅ | excluded |
| Contrast against `plan.md` + acceptance criteria | can't — doesn't read them | ✅ |
| `related_projects` contracts against the other repo's real source | can't | ✅ |
| Project conventions, sister feature, existing helpers | can't | ✅ |
| Architecture and scaffolding rules from Step 2.1 (layers, folders, naming, reuse first, ADRs) | can't — doesn't read them | ✅ |
| Recorded tech debt and deviations from the plan | can't | ✅ |

Each one catches findings the other structurally cannot. Running both is right for a diff with new
logic. Running both on *every* diff is not.

**Decide which ones run, and say which you chose in the output:**

- **New or changed behaviour** → both. The Agent alone will not find a race in an abort path.
- **Pure structural change** — verified move, rename, extraction with no behaviour delta and no test
  edits → **Agent only**. There is no new logic for a generic reviewer to find bugs in.
- **No `plan.md` / no `refinement-summary.md`** (a retroactive ticket, an ad-hoc MR, a teammate's
  MR) → **both, with a narrower Agent**. With no plan, the Agent's scope is the Step 2.1 rules, plus
  design fidelity when Step 2.2 produced a design reference. Those are the things it can still
  contrast the diff against. It skips the plan and acceptance-criteria checks and says so. Only when
  Step 2.1 found no written rules *and* there is no design reference does the review run
  `/code-review` alone.
- MR focused on security → add `/security-review`.
- **Spec mode** (Step 1d) → **Agent only**, with the spec checklist. `/code-review` does not run,
  because there is no code for it to find bugs in. The output says so.
- **Mixed** → `/code-review` on the code files only (`/code-review high <ref> -- <code paths>`, or by
  telling it which paths to review), then the Agent with both checklists, each on its own files.

**Run it and wait for it to finish before launching Step 3.** Then paste its findings into the Step 3
prompt under `**Already reported by /code-review:**`.

```
/code-review high
```

**Why sequential:** the "if `/code-review` already reported a finding, don't repeat it" rule is
unenforceable when the two run in parallel — neither can see the other's output. It has already
failed in practice: both reviewers independently reported the same abort race in different words,
and the author had to reconcile them by hand. Waiting costs wall-clock time once; deduplicating two
reports by hand costs it every round.

The scope exclusion below (bullets 1-3 of the line-by-line review) is static and applies regardless.
It has also been violated in practice — the Agent reported a correctness bug it was told to skip —
so it is restated as a hard rule in the Step 3 prompt, not as a hint.

If `/code-review` isn't available in this environment, continue to Step 3 with the full scope (the
prompt's "Line-by-line review" section) and note it in the output.

## Step 2.6 — Related MRs in flight (spec and mixed mode)

A spec MR is rarely alone. Before launching Step 3, list:
- the open MRs of the same repo whose changed files touch the same spec, the same contract file, or
  a contract for the same endpoint (`list_merge_requests` with `state: opened`, then
  `list_merge_request_changed_files` on each);
- the code MRs the diff names (`!123` references, MR links), with their source and **target**
  branches. A code MR that targets another feature branch rather than the base branch adds a
  dependency that the plan has to record.

Pass the list to the Agent with each MR's branch and head SHA, so it can read them with `git show`.

**Why:** on booking-center-specs, !28 extended an endpoint whose contract !30 was writing at the
same time, with "Nothing else differs". The two merged without a textual conflict and would have left
two specs describing one response differently. The backend MR both plans depended on targeted another
open MR, not `develop`, and neither plan recorded it.

When one run reviews several MRs at once, tell each Agent about the others.

## Step 3 — Launch the review Agent

Use the **Agent tool** with the following prompt:

**Pass `model` explicitly**, taking it from the `model=` line that `context` printed in Step 0 (or `~/.claude/scripts/wf-lib.sh model mr-review`):

```
Agent(model: "<value from wf-lib>", prompt: ...)
```

Without it the agent inherits the session's model, which makes this stage's output depend on an unrelated setting rather than on a decision. The default is `opus`: this stage carries judgment the rest of the cycle rests on. A project can override it with a `models` block in `config.json`.


---
**AGENT PROMPT:**

You are a senior engineer doing a code review of an MR. Your goal is to find real problems — not to give generic feedback.

**MR context:**
[contents of refinement-summary.md and plan.md]

**Published MR** (from Step 1a; omit this block if the MR was not reachable and the diff is local):
- Title / description / target branch / state
- **Prior-comments ledger** (Step 1a: every thread, resolved or not, plus existing drafts):
  [the ledger table]
  Rules:
  - A finding whose substance matches a ledger entry — same defect, even at another line or in other
    words — is **covered**. Do not report it as yours.
  - **Same root cause, new consequence → `extend`, not a new finding.** When your finding sits on the
    same lines as an open thread, comes from the same cause, or would be fixed by the same change, it
    belongs in that thread even if it describes a different effect: the deploy that succeeds where
    the thread covered the one that fails, a second caller of the same broken function. It goes to
    *Existing threads* as `extend`, with what the thread misses and, if the thread's suggested fix
    does not cover it, the fix that covers both. Before you file anything as new, ask whether the
    author would answer it in an existing thread. If they would, it is `extend`.
  - `unaddressed` entries go to *Existing threads*, not to Critical/Important, citing the thread id.
  - `deferred` entries with a reasonable answer are closed. Do not reopen them.
  - **You may disagree with a comment** — its claim is wrong, the suggested fix would introduce a
    defect, it contradicts `plan.md` / the acceptance criteria / the design, or the author's answer
    does not hold. Disagree only with evidence (`file:line`, a spec line, a contract on the other side);
    "I'd do it differently" is not a disagreement. Each one goes to *Existing threads* as `disagree`.
  - Agreeing with a comment adds nothing: do not echo it ("+1").

**Design reference** (from Step 2.2; omit this block if the diff does not change the UI):
- Source: Design Study / Figma URL(s) with `node-id` / `None` / `[NEEDS DESIGN]` / `Agent-proposed` / Figma not reachable
- [the Design Study table, or the values extracted from each frame: layout, spacing, typography,
  colours as design-system variables, copy, breakpoints, which pieces the frame contains]

**Already reported by /code-review** (Step 2.5; omit this block if it did not run, and then the
line-by-line review below has its full scope):
[its findings, as it reported them]
  Rules:
  - A finding whose substance matches one of these — same defect, even at another line or in other
    words — is **covered**. Do not report it as yours.
  - `/code-review` also looks for reuse and simplification, without the repo's rules. When one of
    its findings breaks a Step 2.1 rule (it points out a duplicated hook, and the guidelines say
    "reuse first"), do not report it again. List it under *Rules behind /code-review findings*,
    giving the finding and the rule (`path#section`), so that Step 4 shows them as one finding.

**Stack:** [stack from the config]
**Project conventions:** [summary of CLAUDE.md]
**Architecture and scaffolding rules** (Step 2.1, read from `origin/<target-branch>`):
- [rule, one line] — source: [path#section]
- [global folders that "reuse first" points to, with the helpers already there that the diff's area may need]
[or: "No written architecture rules found; checked <paths>"]

**Review mode** (Step 1d): [code / spec / mixed, and why; for mixed, which files are on each side]
**Related MRs in flight** (Step 2.6; omit in code mode): [each MR with its title, branch, head SHA,
target branch, and the files it shares with this one]

**Full diff:**
[diff]

## Your review process

### 1. Context first (before reviewing line by line)
- What does this MR solve?
- Does the chosen solution make sense architecturally?
- Are there unaccounted-for side effects?

### 2. Line-by-line review
**In spec mode, skip this section and use 2b. In mixed mode, apply it to the code files only.**

**If Step 2.5 ran `/code-review`, bullets 1-3 are OUT OF YOUR SCOPE.** Not "avoid duplicating" —
do not report them at all, even if you find something real there, and even if you reached it from
the acceptance-criteria angle rather than by reading for bugs. If you believe a bug in that band is
severe and `/code-review` missed it, add it under a single `⚠️ Outside my scope, reported anyway`
heading with one line of justification. Anything else in bullets 1-3 gets dropped.

**The one exception is a written rule.** A finding that breaks a Step 2.1 rule is yours even when
the topic falls inside bullets 1-3, for example a state-management ADR that says how to read from
the store to avoid re-renders, or a security rule in the guidelines. `/code-review` does not read
those files, so nobody else checks them. Report it under *Architecture and scaffolding*, citing the
rule. It goes through the same deduplication as any other finding: if `/code-review` already
reported that defect, list it under *Rules behind /code-review findings* instead.

Evaluate in order of importance:
- ~~Bugs and incorrect logic~~ *(`/code-review`'s — do not report)*
- ~~Security — inputs, auth, exposed data~~ *(`/code-review`'s — do not report)*
- ~~Performance — N+1, re-renders, expensive operations~~ *(`/code-review`'s — do not report)*
- **Tests: coverage gaps against the refinement's edge cases** — not generic, but against the cases the ticket identified
- **Modified contracts and their consumers**, including those in other repos
- **Architecture and scaffolding** — against the Step 2.1 rules, file by file: is each new or moved
  file in the layer and folder the rules give it, does it import only what its layer may import, does
  its name follow the naming rules, does a container hold something the rules say is global (or the
  reverse), does the change go against an ADR. For "reuse first", open the global folders the rules
  name and check whether a hook, util or component already does what the diff adds. Report it only
  with the path of the existing piece. **Every finding cites the rule it breaks** (`path#section`).
  With no written rule, a structural remark goes to *Suggestions* as consistency with the sibling
  code, citing the sibling files, never as a rule. Generic simplification without a rule behind it
  belongs to `/code-review`, not here.
- **Design fidelity** — only when a design reference was provided. Compare against it, not against
  your taste: missing or extra pieces, copy that differs, spacing/typography/colour that does not map
  to the design's variables, a breakpoint the design does not have. Cite the frame or the Design
  Study row for each finding. A deviation the MR description explains and justifies is not a
  finding; one it does not mention goes to *Questions for the author*.

### 2b. Spec review (spec mode, or the spec files of a mixed MR)
You have the full scope here, correctness of the claims included: `/code-review` did not read these
files. Every finding cites its evidence: a spec line, a rule (`path#section`), or a `file:line` in a
real repo.

- **The Constitution Check tells the truth.** For each principle the plan marks "Pass", look for
  anything in the plan or in the code MRs it names that breaks it: a slice that says it is not safe
  alone under a "no deploy order may break a screen" rule, a design element the design principle
  does not allow. A breach is reported even when the plan marks it "Pass". The way out is either to
  change the approach or to record the deviation in Complexity Tracking.
- **The artefacts agree with each other, the untouched ones too.** spec ↔ plan ↔ contracts ↔
  data-model ↔ research ↔ tasks ↔ quickstart ↔ any deployment notes. When the MR changes one of
  them, read the others at the head even if the diff does not touch them, and report what now
  contradicts the change (a task that says the opposite, a count of MRs that is no longer right).
  Leftovers from an earlier version of the same MR (an old field name, an old count) count too.
- **Claims about real code are true.** Paths, classes, functions, endpoints, fields, status codes and
  error bodies that the plan or a contract says exist, or will change, are checked against the
  repos of the registry (`repos.md`, or `related_projects` in config.json) on their base branch, or
  on the branch of the code MR that adds them. Check the claims the plan rests on first. A claim
  you could not verify goes to *Questions*, not to findings.
- **Contracts have one owner.** An endpoint, event or shared state is defined in one contract. A
  second spec that extends it annotates the owner or references it, rather than redefining it. Check
  against the related MRs in flight as well as the target branch.
- **Every requirement has a home.** Each FR, acceptance scenario, edge case and SC maps to a slice,
  a test or a quickstart scenario. List the ones that map to nothing.
- **The delivery plan is complete.** Producers ship before consumers. Every dependency outside the
  feature is recorded, including a code MR that targets another feature branch instead of the base
  branch. Each slice's visibility and way back are stated and consistent with what it does.
- **Changes to a spec follow the rules for changing it.** Annotations have the format of the notes
  already on the target branch, sit right after what they change, and name their source. A change
  that the workflow docs send to a new spec, or to a resume of a deferred decision, is not made as
  an in-place amendment unless the exception is recorded.
- **Each requirement can be turned into a test** from what the spec says. Edge cases the contract
  implies (a field that can be null, a partial value) are in the spec, not only in a reply on the MR.

### 3. Side effects
- Are there contracts (API, types, events) being modified that have consumers?
- Are there migrations that could affect existing data?
- Does the diff touch state/storage/a contract shared with some `related_project` (config.json)?
  **Read `{workflowDir}/contracts.md` first** — `/wf-analyze` already resolved this and recorded both
  sides with `file:line`. Re-verify only the entries the diff actually touches; do not re-derive the
  whole thing. If the file says `No shared surfaces`, skip this bullet entirely. If it does not exist
  (the ticket predates it, or analyze never ran), do the verification and **write the file** so the
  next stage inherits it instead of paying for it again. If `related-check` reported a broken path,
  every claim about that repo is `NOT VERIFIABLE` — say so, don't fill it from notes. A diff that's correct in *this* repo's logic can still be broken if the other side of the contract (an external system) does something different from what was assumed — that point can't be approved by looking at this diff alone.

## Required output

```markdown
## Code review — [MR name]

### 📋 Executive summary
[1-2 lines: what the MR does and the overall verdict]
[source: published MR (host) or local diff — and, if local, why the host was not reachable]
[design: what the UI was compared against (Design Study / Figma node-ids / none, and why) — omit for non-UI diffs]
[architecture: the rule files checked (Step 2.1), or "no written rules found; checked <paths>"]
[mode: code / spec / mixed, and why (Step 1d); for spec and mixed, the related MRs checked (Step 2.6)]

### 🔴 Critical (blocking)
- **[file:line]** — [problem] → [required correction]

### 🟠 Important
- **[file:line]** — [problem] → [suggestion]

### 💡 Suggestions
- **[file:line]** — [optional improvement]

### 🔗 Side effects
- [modified contracts and affected consumers]
- [if applicable: risk not verifiable against a related_project — what was assumed without confirming against its real source code]

### 📐 Rules behind /code-review findings
[omit if `/code-review` did not run or none of its findings breaks a Step 2.1 rule]
- **[file:line]** — [/code-review finding, one line] → breaks [path#section]

### 💬 Existing threads
[omit if the MR had no prior comments]
- **[thread id] [file:line or general]** — `unaddressed` — [what is still missing at the head]
- **[thread id] [file:line or general]** — `extend` — [what the thread misses] → [fix that covers both, if the thread's does not]
- **[thread id] [file:line or general]** — `disagree` — [why the comment or the answer does not hold] → [evidence]
[closing line: N threads checked, N covered, N extended, N already addressed]

### ❓ Questions for the author
- [question 1]

### ✅ Prioritized action list
1. [critical action 1]
2. [important action 1]
```

---

## Step 4 — Show the review

Read the agent's output and present it to the user, together with `/code-review`'s findings, as
one review. Each point appears once. A `/code-review` finding listed under *Rules behind /code-review
findings* is shown a single time, with the rule appended (`— breaks path#section`). That section
does not appear on its own.

If there are 🔴 Critical findings, ask: **"Do you want me to tackle any of these items now with `/wf-implement`?"**

## Step 5 — Record findings and the MR's weight

```bash
# one per 🔴 and 🟠
~/.claude/scripts/wf-event.sh finding \
  --category [slug] --severity [high|medium] \
  --stage_origin [refine|analyze|implement] --stage_detected mr-review \
  --detected_by [gate|user] --summary "[one line]"

# the weight, taken from wf-diff.sh --weight (Step 1)
~/.claude/scripts/wf-event.sh mr_opened \
  --weight_prod [N] --weight_tests [N] \
  --branch "[branch]" --target "[base branch]"
```

This stage's findings weigh the most in the leak metric: a defect that made it all the way to the MR passed through `review-plan`, `validate` and `test` without any of them catching it. `stage_origin` is what says which of those three gates to look at.

Mark `detected_by gate` only for what the review found (ours or `/code-review`'s). What you spotted yourself reading the diff goes as `user` — that's exactly the signal that the gates are falling short.

## Step 6 — Offer the review as draft comments on the MR

Only when Step 1a read the MR from the host. Ask: **"Do you want me to add the review to the MR as
draft comments?"** On yes:

- **One draft per 🔴 / 🟠 / 💡 finding, anchored to its line** (`create_draft_note` on GitLab, a
  pending review on GitHub). Anchor with the MR's `diff_refs` (`base_sha`, `start_sha`, `head_sha`)
  and a `new_line` that is an added or changed line in the diff; verify the number against
  `git show origin/<source-branch>:<path>` first. An added or changed line (`+` in the hunk) takes
  `new_line` only; `old_line` + `new_line` is for unchanged context lines alone. Mixing them on a
  changed line leaves the draft without a `line_code`, and GitLab renders it repeated across the file.
- **One general draft** with the summary and the *Questions for the author*. No pipeline or rebase
  state (see Step 1a).
- **Each point is said once, in one draft.** The general draft carries only what has no line of its
  own: a one- or two-line verdict, the findings that cannot be anchored to a changed line, and the
  questions that no inline draft already asks. A finding or question that has an inline draft does
  not appear again in the general one — not restated, not summarised, not as a "see the thread on …"
  pointer list. If nothing is left after that, skip the general draft. Before creating it, reread the
  inline drafts of this run and strike every sentence that repeats one of them.
  **Why:** the author got the same request twice — inline, and again as the question in the general
  draft — and had to answer it in two places.
- Write them in the language the MR itself is written in, not the session's `lang`. Prefix each
  inline one with its weight (**Important** / **Suggestion** / **Nit**).
- **Propose, never impose.** Every draft, whatever its weight, opens a conversation with the author.
  It does not hand down a verdict.
  - First describe what you saw and what it causes, concretely, with the evidence (`file:line`,
    the scenario). Do not judge the code: no "this is wrong", "this is fine", "this must".
  - Then offer one option or several, as ideas. Vary the wording across drafts instead of opening
    every one the same way:
    - Spanish: "podríamos probar con…", "a lo mejor haciendo…", "¿qué te parece si…?",
      "propongo…", "sugiero…", "se me ocurre…", "una opción sería…", "otra alternativa es…",
      "capaz que conviene…", "quizás sirva…", "¿y si…?", "¿te parece bien si…?", "una idea:…".
    - English: "one option could be…", "what if we…", "I'd suggest…", "maybe we could…",
      "another option is…", "how about…", "it might help to…", "one idea:…".

    When there is more than one reasonable way out, list them with their trade-off and let the
    author choose. A finding that only describes a problem, with no way out, is incomplete.
  - **The exception is a plain mismatch whose way out is obvious**, such as a code comment or the MR
    description saying the opposite of what the code does. Pointing out the difference is enough,
    because the author only has to update one side. Do not pad it with options.
  - Never present a fix as required ("hay que", "you need to", "change X to Y"), not even for
    **Important**. The weight says how much it matters. The wording still leaves the decision to
    the author.
  - When you are not sure the problem is real, ask it as a question.
  - Keep it friendly and short. The weight prefix and the evidence carry the seriousness, so the
    tone does not have to.

  **Why:** the user wants the review to start a discussion with the author, not to dictate fixes.
  A draft that read as a bare statement left the author without a proposal, and one that read as
  an order closed the discussion before it started.
- **Every reference must be something the reader can follow without the review's context.** The
  author and the other reviewers see only the draft and the one line it is anchored to.
  - A reference to code or a document in the repo is a link, never a bare `file:line` in
    backticks. Point it at the reviewed commit, not the branch, and use the full path:
    `[service.ts:42](<project web_url>/-/blob/<head_sha>/src/orders/service.ts#L42)` on GitLab,
    `…/blob/<head_sha>/<path>#L42` on GitHub, and `#L12-17` (GitHub: `#L12-L17`) for a range. The
    link text can be the short name, but the URL carries the whole path. Take `web_url` from the
    project, not the MR. Never use relative links, because the host resolves them against the MR
    page and they end in a 404. A link to the branch moves to another line after the next push or
    rebase.
  - A line number on its own ("L39", "line 99", "see L12-17") is never enough, not even for the
    file the draft is anchored to. Name what the line says, and quote it when the argument depends
    on its wording: `the rule «Never retry a failed payment» ([rules.md:16](…))`. Quote one or two
    lines at most, and summarise a longer passage.
  - Before creating the drafts, open every link you built (`get_file_contents` at `head_sha`, or
    `git show <head_sha>:<path>`) and check that the file exists and that the line says what the
    draft claims.
  - **Nothing in the text may turn into a link that leads nowhere.** The host links some patterns
    on its own: with a Jira integration, every `KEY-123` becomes a link to that Jira issue, and
    `#12` / `!12` become issue and MR references in the current project. Requirement and decision
    ids that are not tickets (`FR-001`, `SC-002`, `D-001`, `R-025`, `US-3`) and numbers that are
    not this project's issues go inside backticks, which the host does not link. Real ticket keys
    (`BC-1484`) and real references (`group/project!12500`) stay bare, because their links work.

  **Why:** drafts that cited `file:line` in backticks or a bare "L12-17" left the reader with
  nothing to open: the short names had no path, and a line number in the anchored file points at
  a line the reader cannot see. On booking-center-specs !32 every `FR-0xx`, `SC-00x` and `D-00x`
  in the drafts rendered as a link to a Jira issue that does not exist.
- Drop any finding the MR description already explains and justifies — it is not a finding.
- **Drop any finding already in the ledger**, including the user's own drafts from an earlier run.
  Re-check the draft list right before creating: never create a second draft for a point that
  already has one; update the existing draft (`update_draft_note`) if the wording must change.
  On GitLab, an update of an inline draft sends `position` again together with `body`, the same
  `diff_refs` and line it was created with. A `body`-only update keeps the `line_code` but blanks
  the path and the line, so the draft no longer sits on its line, and a `position`-only update is
  rejected (400 "Missing params to modify"). After updating, list the drafts and check that each
  inline one still has its `position.new_path` and `position.new_line`.
- **One reply draft per `extend` entry, inside its thread**, the same way as `disagree` below. Never
  a new inline draft on the thread's lines. Say what the thread misses, and the fix that covers both
  cases when the thread's own fix does not.
- **One reply draft per `disagree` entry, inside its thread** — `create_draft_note` with
  `in_reply_to_discussion_id` on GitLab; on GitHub, a reply inside the pending review (GraphQL
  `addPullRequestReviewThreadReply` with the pending review's id — never the REST reply endpoint,
  which publishes at once). State the disagreement and its evidence in two or three lines, as a
  question when the evidence is not conclusive. Never set `resolve_discussion`, and never resolve or
  unresolve a thread: that is the thread owner's call.
- `unaddressed` entries get a short reply draft in their thread ("still open at `<sha>`: …") only if
  the user asks for it; by default they stay in the review output.
- **Never publish them.** Drafts are visible only to the user until they publish from the host's UI;
  that last read is theirs.

Check each created draft's `line_code`. If it is null, the anchor is wrong: delete that draft and
create it again with the corrected position before reporting. Then report the draft IDs.

## Step 7 — Leave nothing behind

Last step, always. List anything this review created locally — a worktree, a clone, a branch, a
`state.json` or ticket directory — and **offer** to remove it. Do not remove it unasked. With 1c
followed there is normally nothing to list; say so in one line.

Before removing anything, including directories the user points to, check it for work that isn't
on the remote. Compare by content, not by SHA — after a rebase and force push every local commit
looks unpushed:

```bash
git fetch origin <branch>
git cherry -v origin/<branch> HEAD     # '+' = patch not on the remote; '-' = already there
git diff origin/<branch> --stat        # working tree vs the remote head, uncommitted edits included
```

Only a `+` line or a non-empty diff is real pending work: keep it and tell the user what it is.
Otherwise the directory is safe to remove, even if `git status` shows it ahead or dirty.
