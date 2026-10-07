---
description: "Generates the MR/PR description aimed at technical reviewers. Given an MR link it reads the real MR from GitLab/GitHub (MCP or CLI) first. No title at the top, context first, doesn't repeat the diff."
allowed-tools: Read, Bash, Glob, TodoWrite
---

Your role is to generate a clear, useful MR description for reviewers, based on the plan's context and the real diff.

## Step 0 — Ticket context

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage mr-desc
```

If `context` fails, ask for the ticket and write `.claude/workflow/state.json` before retrying.

**Language:** address the user in the language reported as `lang` by `context` (`en` by default). The MR description file itself is also written in that language — it's read by the same team the chat addresses. Code, commit messages, and identifiers stay English regardless of `lang`; only prose docs (this file, plan.md, refinement-summary.md, etc.) follow it.

## Step 1 — Gather context

Read:
- `{workflowDir}/plan.md` → technical solution and decisions taken
- `{workflowDir}/refinement-summary.md` → objective and acceptance criteria
- `{workflowDir}/review-findings.md` → whether there were significant adjustments to the plan

### If `$ARGUMENTS` carries an MR/PR reference, read the real MR first

A link (`https://gitlab.com/.../merge_requests/123`, `https://github.com/.../pull/123`) or a bare
`!123` / `#123` means the MR already exists on the host. **Go there before touching the local diff.**
In order:

1. **MCP for that host**, if this session has one (`mcp__gitlab__*`, `mcp__github__*`). Add the tools
   you use to `allowed-tools` for the session; the frontmatter can't list servers that may not exist.
2. **CLI**, otherwise:
   ```bash
   glab mr view <ref> --comments   # GitLab
   gh pr view <ref> --comments     # GitHub
   ```
3. **Neither reachable** (no MCP, CLI missing or unauthenticated, host unreachable) → continue with
   the local diff and **say so in Step 3**: the description was written blind to the published MR.

What the MR gives that the local branch cannot:
- **Its current description** — this is a rewrite, not a first draft. Anything the author already
  wrote there that the plan doesn't cover (a rollout note, a linked incident, a reviewer instruction)
  is content to keep, not to drop.
- **Its target branch** — if it targets something other than the project's base branch, that target
  wins, and `--branch`/base assumptions taken from the local repo are wrong.
- **Its source branch head SHA** — if it differs from the local branch, the description must describe
  what is published, not unpushed local work.
- **Reviewer comments** — a question asked twice in the thread is a gap the description should close.

Get the summarized diff:
```bash
~/.claude/scripts/wf-diff.sh --stat --fetch
~/.claude/scripts/wf-diff.sh --log
```

**The first `wf-diff.sh` call of the stage carries `--fetch`.** It refreshes `origin/<base>` (the
remote-tracking ref only — no local branch, no merge, no working-tree change) so the fork point is
computed against the real base rather than a stale local one. If it warns that the local base is
behind, **that warning is the whole point** — without the refresh the diff would have carried other
tickets' merged commits as if this feature had written them. Do not silence it and do not "fix" it
by pulling the base branch.

## Step 2 — Generate the description (delegated)

**Use the Agent tool**, with `model` from `~/.claude/scripts/wf-lib.sh model mr-desc` (default `sonnet`).

Two reasons, and the second matters as much as the first. Writing an MR description from a plan and a diff is bounded work against a fixed template — there is no open-ended judgment, so the strongest model buys nothing. And delegating keeps the plan, the refinement and the full diff out of the session's context window, where they were being loaded for a task that never needed to be there.

Pass the Agent everything it needs, because it starts with no context: the contents of `plan.md`, `refinement-summary.md`, `review-findings.md`, the `--stat` and `--log` output from Step 1, and the structure below. If Step 1 resolved a published MR, pass its current description and its reviewer comments too, with the instruction to preserve what the plan doesn't cover and to answer what the thread keeps asking. Ask it to return the finished markdown and nothing else.

**Principles** (include these in the Agent's prompt):
- The reader is a reviewer about to open the diff. The description gives them the context and the reason for the change, so the diff makes sense when they get to it. The diff already says how it was done
- Don't start with the title
- **As short as it can be.** Ten lines is a good description, and it never needs more than one screen. If it does, the MR is too big or the text is explaining the diff
- **One line per bullet.** A bullet that needs more is explaining instead of stating
- No files, paths, classes, functions or tests by name, unless one is the point of the change (a removed client, a new migration). That is what the diff is for
- **No testing or verification section.** CI runs the tests: an MR that passes it has passed them. No test counts, no list of new or fixed tests, no "lint and typecheck green". The one exception is a check CI does not run (an e2e against a real environment, a manual check of a migration): one bullet under *Worth knowing*, never a section
- No story of how it was built: no review rounds, no merge or conflict resolutions, no "first I tried"
- Don't repeat the commit log, and don't restate the spec or the ticket: link them
- **Omit any section below that would be empty or redundant with the context.** A header with nothing under it, or with "N/A", is noise

**Structure** (headings in the description's language):

```markdown
[TICKET](jira-url) · [related links, if any]

## Context
[1-3 lines: the problem or need behind the change, and why it is solved this way.
The one section that is always there.]

## What changes
[What a user or the next team will notice, in plain words. Four bullets at most.
Leave it out when the context already says it.]

## Worth knowing
[Only what the reviewer cannot see in the diff and needs to know: a decision they would
question, a migration or env var, a merge order, a flag that hides the work, a check CI
does not run. Leave it out when there is nothing to warn about.]
```

## Step 3 — Show and adjust

**Read what came back before showing it.** A description can be fluent and still misstate *why* a change was made, and a reviewer will trust it — that is the specific failure to watch for when this step is delegated. If the intent is wrong, the Agent's input was underspecified, not its model: add what was missing and re-run, rather than reaching for a stronger model.

This step stays in the session: adjusting the wording with you is a conversation, not a generation task.

Show the generated description to the user. If the MR was resolved from the host, say so; if it was
not reachable and the description came from the local branch alone, say that instead. Instead of an open question, offer the two exits directly and show right away what the next steps are:

```
Adjust anything, or move on?
a) Adjust something in the description
b) It's ready — next: `/wf-mr-review` for the final MR review
```

If the user asks for changes (a), apply them until they're satisfied and offer the same two options again. If they choose to move on (b), don't ask again — go straight to suggesting `/wf-mr-review`.
