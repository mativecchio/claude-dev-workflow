---
description: "Takes a ticket's merge/pull requests out of draft and announces them in the team's chat. Checks each draft first without blocking the rest, sets the reviewers from the config or asks, moves the tickets to review, and writes one short line per MR. Code host, tracker, chat, channels, statuses and message are all configurable; whatever has no tool available is done by hand from what it prints."
allowed-tools: Read, Write, Bash, Glob, Grep, AskUserQuestion
---

Gets a ticket's merge requests ready for review and tells the reviewers, in one pass. It
names no code host, tracker or chat of its own: each comes from the config, and each is
reached through the first way that works (see *Reaching a service*).

"MR" below means a merge request or a pull request, whichever the host calls it.

`$ARGUMENTS` is a ticket key (the parent of a stack, or a single ticket), one or more MR
links, or nothing: then ask for the key.

**Language:** talk to the user in their language. The messages are written in `language`
of the config; if `style` is set, follow it.

---

## The config

Two places, merged key by key, the project's winning:

1. `~/.claude/workflow/ready.json` — personal, every project.
2. `ready` in the project's `.claude/workflow/config.json` — when one team works differently.

```json
{
  "language": "en",
  "style": "",
  "code_host": "auto",
  "tracker": {
    "kind": "jira",
    "key_pattern": "[A-Z][A-Z0-9]+-[0-9]+",
    "review_status": "In Review",
    "move_parent": "ask"
  },
  "chat": {
    "kind": "slack",
    "team_channel": "#team"
  },
  "checks": ["pipeline", "conflicts", "threads"],
  "labels": ["ready to review"],
  "message": {
    "title_words": [3, 6],
    "template": "",
    "stack_note": true
  },
  "projects": {
    "group/backend":  { "channel": "#backend", "reviewers": ["some.username"] },
    "group/frontend": { "channel": "#frontend", "language": "es" }
  }
}
```

| Key | Meaning | Without it |
|---|---|---|
| `language` | Language of the messages | The user's language |
| `style` | Free text on how the messages should sound (tone, words to avoid), or a path to a file that says it | Neutral and short |
| `code_host` | `gitlab`, `github`, `bitbucket`… or `auto`: from the MR links or the project's `origin` | `auto` |
| `tracker.kind` | `jira`, `linear`, `github`, `youtrack`… or `none` | Ask once |
| `tracker.key_pattern` | Regex of a ticket key, to find each MR's ticket in its title or branch | `[A-Z][A-Z0-9]+-[0-9]+` |
| `tracker.review_status` | Status a ticket moves to when its MR is ready | Ask once |
| `tracker.move_parent` | `ask`, `always` or `never`: move the parent when all its children are in review | `ask` |
| `chat.kind` | `slack`, `teams`, `discord`, `google-chat`, `mattermost`… or `none` (print only) | Ask once |
| `chat.team_channel` | Channel that gets the whole list | None |
| `checks` | Which of `pipeline`, `conflicts`, `threads` run before leaving draft | All three |
| `labels` | Labels an MR gets when it leaves draft, on top of the ones it has | None |
| `message.title_words` | Length range of each MR's title in the message | `[3, 6]` |
| `message.template` | The message, with `{key}`, `{summary}`, `{groups}` and `{stack_note}` | The default below |
| `message.stack_note` | Add a line on the merge order when MRs are stacked | `true` |
| `projects.<path>` | Per host project: `channel`, `reviewers` (host usernames), and any key above to override | — |

Something missing that the run needs (a channel, a status, which chat): ask once, for all
projects involved together, offer to save the answer, and never ask again for what is saved.
Each answer may be "none": that part is skipped.

## Reaching a service

For the code host, the tracker and the chat, in this order:

1. **A tool of this session for that `kind`**: an MCP server or connector (`ToolSearch` with
   the kind and the action, e.g. "gitlab merge request", "jira transition", "slack send
   message"). Prefer one the project's instructions name.
2. **Its CLI**, if installed and logged in (`glab`, `gh`, `jira`, `linear`…).
3. **By hand**: print what the user has to do, ready to copy, and carry on.

Say once, at the start, which way each service will go. A service that fails mid-run drops
to the next way for the rest of the run; it never stops the others.

---

## Step 1 — The merge requests

- From a key: the user's open MRs on the host whose title or source branch contains it.
  Leave out documentation-only MRs of a specs repository and say so in one line.
- From links: read each one.
- Per project, order the stack: the MR targeting the default branch first, then the one
  targeting its source branch, and so on. Unrelated MRs keep their own order.

MRs already out of draft stay in the list: they are announced, and only get the `labels` they
lack (step 3).

## Step 2 — Check each draft, without blocking

The checks of `checks`, for every draft MR, in parallel:

| Check | Fails when |
|---|---|
| `pipeline` | the head pipeline did not succeed; running counts as pending |
| `conflicts` | it conflicts with its target |
| `threads` | a resolvable thread is unresolved |

Show one table: MR, short title, each check, and what will happen. An MR that fails is
proposed to **stay in draft** and the rest carry on: one red MR never holds the others. The
user can override any line. A pending pipeline: offer to wait for it or to go ahead.

## Step 3 — Out of draft

After the user confirms, mark each MR ready. Where the host keeps draft state in the title
(`Draft:`, `WIP:`), set the title without the prefix too, and confirm the result reads ready.

In the same update, add `labels`, and add them as well to the MRs that were already out of
draft and lack them. Keep every label the MR has: where the host's update replaces the whole
list, send its current labels with the new ones. A label the project does not have is reported,
not created.

## Step 4 — Reviewers

- `reviewers` for that project: set them, unless the MR already has some.
- None configured: ask once, for all projects together, with **"None for now"** first.
  Skipping never stops the command. Offer to save what they choose.

## Step 5 — The tracker

Skipped when `tracker.kind` is `none`. Each MR's ticket is the `key_pattern` match in its
title (the last one, when a title carries the parent and the child) or its branch. Move it
to `review_status` unless it is already there or further. Then the parent, as
`move_parent` says, only when all its children are in review or later.

## Step 6 — The messages

Who gets what:
- Each project's `channel`: only that project's MRs.
- `team_channel`: the whole list.
- A project with no channel appears only in the team message. With no channel at all, one
  message with everything.

Default template, written in the message's language:

```
{key} MRs ({summary}), ready for review:

{groups}

{stack_note}
```

- `{summary}`: the ticket's title in a few words, from the tracker, or from the MRs.
- `{groups}`: one bullet per MR — a title within `title_words` saying what it adds, never
  the commit line, then the link — grouped under the repository name only when the message
  has more than one.
- `{stack_note}`: "Stacked: each one builds on the previous; merge bottom up." Only when some
  MR targets another MR's branch and `stack_note` is on. An empty placeholder takes its line
  with it.
- MRs left in draft are not announced. No emojis, greeting or closing unless `style` asks.

## Step 7 — Send

- **A chat tool:** find each channel, show every message with its channel, and post only
  after the user confirms (one confirmation for all is fine). Report each post's link.
- **By hand:** print each message in a code block with its channel above it, as plain text
  with bare links, which every chat pastes as it is.

## Report

MRs taken out of draft, MRs left in draft and why, labels added, reviewers set, tickets moved, and the
messages posted (links) or printed — plus anything left to do by hand.
