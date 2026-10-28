---
description: "Stand-up summary. With an argument: records a note (done, plan, doubt or blocker) in today's daily log. Without one: builds what to say at the daily — yesterday, today, doubts and blockers — from the notes, Jira, the merge requests and the commits since the last working day."
allowed-tools: Read, Write, Bash, Glob, Grep
---

What the user says at the daily, ready to read aloud in about a minute: what they did since
the last working day, what they do today, and what blocks them or what they are waiting on.

**Language:** the summary is in the language the user writes in (for Spanish, the variant
their `CLAUDE.md` asks for). Notes on disk are in English, one line each.

The notes live in `~/.claude/workflow/daily/YYYY-MM-DD.md`, across every project, written by
`~/.claude/scripts/wf-daily.sh`.

---

## Note mode — `/wf-daily <text>`

When `$ARGUMENTS` has text, record it and stop.

1. The kind, from the text: `done` (something finished or delivered), `plan` (something to do
   next), `doubt` (a question open, to someone or to the team), `blocker` (something that stops
   the work). An explicit prefix (`done:`, `plan:`, `doubt:`, `blocker:`, or the user's language's
   word for it) wins.
2. One line, ticket key first when there is one, who it waits on when it waits on someone:
   `BC-1905: MR !65 has 5 review threads to answer`, `BC-1903: design questions to Pablo, no answer yet`.
3. `~/.claude/scripts/wf-daily.sh note <kind> "<line>"` and confirm in one line.

---

## Summary mode — `/wf-daily` (no arguments)

### Step 1 — The window

`~/.claude/scripts/wf-daily.sh since` → the last working day (Friday on a Monday). The window
runs from that day's start to now. The user can name another start (`/wf-daily since 2026-10-20`
is a summary, not a note).

### Step 2 — Gather, in parallel when the tools allow

Each source is optional: when one is missing or fails, go on and say which in one line at the end.

- **Notes**: `~/.claude/scripts/wf-daily.sh notes` — the backbone. Doubts and blockers come only
  from here and from the evidence below, never invented.
- **Yesterday's summary**: `~/.claude/workflow/daily/<since>-summary.md`, if it exists. Its *Today*
  is what the user said they would do: say what of it got done and what moved to today.
- **Jira** (Atlassian connector): `assignee = currentUser() AND updated >= "<since>" ORDER BY updated DESC`,
  and the issues the user commented on or reported in the window. Keep status changes, new
  subtasks, comments that ask the user something, and questions the user asked that nobody answered.
- **Merge requests** (GitLab MCP, or `gh`/`glab`): the user's MRs updated in the window —
  opened, merged, ready, with unresolved threads (whose), with a failed pipeline — and MRs where
  the user is reviewer and reviewed or still has to.
- **Commits**: `git log --all --since=<since> --author="$(git config user.email)" --oneline` in the
  current repository, in the `related_projects` of its `.claude/workflow/config.json`, and in every
  repository a note names. Commits only fill gaps: a ticket with commits and no note or MR.
- **This session**: what the conversation already did or decided, when it fits the window.

### Step 3 — Keep only what matters

Many notes are written automatically by `wf-daily-hook.sh` at the end of each session, so
there are more than a daily needs. Before writing, drop:

- what a teammate would not care about: routine steps, tooling, small fixes inside a bigger task;
- what a later note supersedes (a `plan` that got `done`, a `doubt` that got its answer);
- duplicates across sessions: one line per ticket and block, merging what they say.

### Step 4 — Write it

Group by ticket (or by epic when several tickets of one feature moved), and keep it to what
is said at a daily, with the headings in the user's language:

```
**Yesterday**
- <ticket>: <what got done, in plain words — the outcome, not the steps>

**Today**
- <ticket>: <what comes next>

**Blockers and doubts**
- <what stops or is pending>, waiting on <who>, since <when>
```

- Brief: the whole summary fits in about six lines, at most three per block; one line each; no links, no MR numbers unless the team says
  them aloud. A block with nothing says so in a few words ("nothing blocking me").
- *Today* comes from `plan` notes, from yesterday's *Today* not done, and from what the evidence
  leaves pending (threads to answer, an MR ready to merge, the next slice). Say it as intent, not
  as a list of chores.
- *Blockers and doubts*: `blocker` and `doubt` notes still open, questions to someone with no
  answer, MRs waiting on review for more than a day, a red pipeline that is not the user's to fix.
  A doubt that got its answer in the window is not listed.

Under the summary, separated by a rule, **For you** (not to read aloud): the pending items with
their links — threads to answer, MRs to merge, questions waiting — and the sources that were
not available.

### Step 5 — Keep it

Write the summary (without *For you*) to `~/.claude/workflow/daily/<today>-summary.md`, so the
next daily can compare. Offer to copy it with `~/.claude/scripts/wf-clip.sh` for Slack.

## Rules

- Nothing the sources do not show. A guess about the plan is said as a suggestion in *For you*,
  not put in the user's mouth.
- Never post the summary anywhere: the user says it or pastes it.
