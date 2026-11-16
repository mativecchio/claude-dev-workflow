---
description: "Stand-up summary. With an argument: records a note (done, plan, doubt, blocker or decision) or a capture of a visible change in today's daily log. Without one: builds what to say at the daily — yesterday, today, doubts and blockers, and, only when there are any, the technical decisions to share and the changes to show — from the notes, Jira, the merge requests and the commits since the last working day."
allowed-tools: Read, Write, Bash, Glob, Grep, Artifact, mcp__claude_ai_Atlassian_MCP__*
---

What the user says at the daily, ready to read aloud in about a minute: what they did since
the last working day, what they do today, and what blocks them or what they are waiting on.
When the work moves faster than the team can follow, two optional blocks help it keep up: the
technical decisions worth sharing or deciding together, and the visible changes worth showing.
Neither is forced: a day with nothing for them leaves them out.

**Language:** the summary is in the language the user writes in (for Spanish, the variant
their `CLAUDE.md` asks for). Notes on disk are in English, one line each.

The notes live in `~/.claude/workflow/daily/YYYY-MM-DD.md`, across every project, written by
`~/.claude/scripts/wf-daily.sh`; the captures of `show` are copied to its `media/` folder, so
they outlive the worktree they were taken in.

---

## Note mode — `/wf-daily <text>`

When `$ARGUMENTS` has text, record it and stop.

1. The kind, from the text: `done` (something finished or delivered), `plan` (something to do
   next), `doubt` (a question open, to someone or to the team), `blocker` (something that stops
   the work), `decision` (a technical decision taken, or one the team should take), `show` (a
   visible change to show, with its screenshot or GIF). An explicit prefix (`done:`, `plan:`,
   `doubt:`, `blocker:`, `decision:`, `show:`, or the user's language's word for it) wins.
2. One line, ticket key first when there is one, who it waits on when it waits on someone:
   `BC-1905: MR !65 has 5 review threads to answer`, `BC-1903: design questions to Pablo, no answer yet`.
   A decision says what was chosen, over what and why in a few words, and ends with
   `needs the team` when the user wants the team to weigh in:
   `BC-1903: the voucher recipients come from the payment methods, not a new endpoint, needs the team`.
3. `~/.claude/scripts/wf-daily.sh note <kind> "<line>"` and confirm in one line.
4. For `show`, the capture is a file: `~/.claude/scripts/wf-daily.sh show <file> "<line>"`, where the
   line says, for someone who does not follow the ticket, where in the product it is, what is on
   screen and what changed from before:
   `BC-1938: checkout, payment step: the agent types the card here, or sends the guest an email to enter it; before, only by email`. Without a file, ask for one: a GIF from `/wf-demo` or
   `/wf-test-env`'s evidence, or a screenshot the user takes.

---

## Summary mode — `/wf-daily` (no arguments)

### Step 1 — The window

`~/.claude/scripts/wf-daily.sh since` → the last working day (Friday on a Monday). The window
runs from that day's start to now. The user can name another start (`/wf-daily since 2026-10-20`
is a summary, not a note).

### Step 2 — Gather, in parallel when the tools allow

Each source is optional: when one is missing or fails, go on and say which in one line at the end.

- **Notes**: `~/.claude/scripts/wf-daily.sh notes` — the backbone. Doubts and blockers come only
  from here and from the evidence below, never invented; decisions and things to show only from
  here (`[decision]` and `[show]` notes, the latter with the path of their capture under `media/`).
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
- what a later note supersedes (a `plan` that got `done`, a `doubt` that got its answer, a
  decision changed by a later one);
- decisions a teammate would not notice: only those that change how something is built or
  behaves, or that the team should take;
- duplicates across sessions: one line per ticket and block, merging what they say.

### Step 4 — Write it

Group by ticket (or by epic when several tickets of one feature moved), and keep it to what
is said at a daily, with the headings in the user's language:

```
**Yesterday**
- <KEY> "<ticket title>": <what got done, in plain words — the outcome, not the steps>

**Today**
- <KEY> "<ticket title>": <what comes next>

**Blockers and doubts**
- <KEY> "<ticket title>": <what stops or is pending>, waiting on <who>, since <when>

**Technical decisions**                       ← only when there are any
- <KEY>: <what was decided and why, in plain words>
- <KEY>: <the question>, I'd go for <option>: to decide together

**To show**                                   ← only when there are captures
- <KEY>: <where it is and what changed, in a few words>
```

Every ticket goes with its title as Jira has it (read it when the sources did not bring it),
the first time it appears in the summary; later mentions take the key alone.

- Brief: the whole summary fits in about six lines, at most three per block; one line each; no links, no MR numbers unless the team says
  them aloud. A block with nothing says so in a few words ("nothing blocking me").
- *Today* comes from `plan` notes, from yesterday's *Today* not done, and from what the evidence
  leaves pending (threads to answer, an MR ready to merge, the next slice). Say it as intent, not
  as a list of chores.
- *Blockers and doubts*: `blocker` and `doubt` notes still open, questions to someone with no
  answer, MRs waiting on review for more than a day, a red pipeline that is not the user's to fix.
  A doubt that got its answer in the window is not listed.
- *Technical decisions*: the `decision` notes left after step 3, at most three, the ones that
  `need the team` last and said as a question with the user's preference. They are not part of the
  six-line budget, and the block is left out, heading included, when there are none.
- *To show*: the `show` notes of the window, at most two, the newest first when there are more.
  A capture tied to a decision of the same ticket is shown next to it and said as one item.
  Left out, heading included, when there are none. Never take a capture at this point: the daily
  only shows what was recorded during the work.

Under the summary, separated by a rule, **For you** (not to read aloud): the pending items with
their links — threads to answer, MRs to merge, questions waiting — and the sources that were
not available. When a visible change went to review in the window with no capture, say there that
`/wf-daily show <file> "<line>"` would let the team see it; a suggestion, never a gap to fill.

### Step 5 — Keep it

Write the summary (without *For you*) to `~/.claude/workflow/daily/<today>-summary.md`, so the
next daily can compare. Offer to copy it with `~/.claude/scripts/wf-clip.sh` for Slack.

**The week's page**, only when *Technical decisions* or *To show* has something. It is what the
team reads to catch up, so it stays short enough to be read:

- Only decisions and captures. *Yesterday*, *Today* and *Blockers and doubts* are said aloud and
  never written there.
- One section per day that had something, the newest on top, with at most three items: a decision
  in two lines (what was decided and why), a capture with one line (its ticket, where in the
  product it is, what is on screen and what changed) and the capture itself. A capture tied to a
  decision of the same ticket goes under it. Days with nothing get no section.
- At the very top, one line with the decisions that `need the team` and are still open, only when
  there are any.
- The earlier days of the week collapsed, one line each.
- A day already on the page is rewritten with what the notes say now, never added twice.

Where it goes comes from `daily` in `~/.claude/workflow/config.json`:

- `"publish": "confluence"`, with `site`, `space_id` and `parent_id` (the page every week hangs
  from): one page per week under the parent, titled `Daily · semana del <Monday's date>` in the
  user's language, created by the week's first daily and updated by the rest; its id is kept in
  `~/.claude/workflow/daily/confluence.json` by ISO week. Through the Atlassian connector: read
  the format guide once, upload each capture of `media/` as an attachment of the week's page
  (`createConfluenceAttachment`, then its upload command), and write the page in HTML with a
  decision list for the decisions, the media nodes for the captures and `<details>` for the
  earlier days, re-reading the page and its snapshot token before each update. Give the user the
  week's link: it is the one to pass on, and it stays the same until Friday.
- Otherwise, or when the connector is missing: one Artifact with the same content, whose URL is
  kept in `~/.claude/workflow/daily/page-url` (read it first and publish to that URL when the file
  exists). Load the `artifact-design` skill before writing it; the captures go as `files` from
  `media/`. An Artifact is private to the user's account, which may not reach the team: say so.

## Rules

- Nothing the sources do not show. A guess about the plan is said as a suggestion in *For you*,
  not put in the user's mouth.
- Never post the summary anywhere: the user says it or pastes it. The week's page is the only
  thing published, and only where `daily` says.
