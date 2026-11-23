# Which ticket a piece of work belongs to

Several tickets run in parallel — in different branches, worktrees and sessions — and the user
may ask for two of them in the same session. A command must know which ticket it is working on
from facts about the checkout, not from a memory written earlier.

## How the ticket is resolved

`wf-lib.sh context [ticket]` resolves it, in this order, and prints the result as `ticket=` and
`ticket_source=`:

| Source | What it is | Trust |
|---|---|---|
| `arg` | The ticket given to the command (`context MA-123`, or `WF_TICKET=MA-123`) | The user said so |
| `state` | A ticket whose `state.json` records the current branch | A fact recorded for this branch |
| `branch` | The ticket key in the branch name (`fix/MA-801` → `MA-801`; pattern `ticket_pattern` in `config.json`) | Read from git, always current |
| `pointer` | `activeTicket` in the root `state.json` | A memory: confirm it with the user before writing anything |

No source → `context` fails and asks for the ticket. Never guess one.

Until a new ticket has its branch, pass it explicitly: `wf-lib.sh context <ticket>`, and prefix
the later `wf-lib.sh` calls with `WF_TICKET=<ticket>`. Once the branch exists, record it with
`wf-lib.sh set-state branch '"<branch>"'`; from then on any checkout of that branch resolves the
ticket on its own.

## Where the work happens

- The workflow lives in the **main checkout** (`.claude/workflow/`), shared by every worktree.
  `specs_root` in `config.json` moves the ticket directories elsewhere (for example a checkout of
  a central specs repository). They are keyed by ticket, never by project.
- The user remembers the ticket, not the folder. `wf-lib.sh worktree <ticket>` gives the checkout
  its code is in. Run the ticket's commands **from that checkout** (`cd` there first): every
  script resolves the ticket, the branch and the diff from the directory it runs in, and a
  session sitting in another checkout would describe the wrong one.
- `context` warns when the ticket records a branch other than the one checked out, and names the
  ticket's worktree.

## Before writing code

1. **Say where the work goes**, in one line, before the first edit:
   `→ MA-803 (branch MA-803-release-tag-guard)`. If it is not what the user meant, they can stop
   it before any code exists.
2. **Check the request against the ticket's spec.** If what is asked does not fit the spec — it
   belongs to another ticket's scope, or no spec covers it — ask which ticket it is for before
   choosing. When in doubt, ask; do not drop the change into whichever ticket is open.
3. **Files outside the spec.** `wf-lib.sh scope-check <file>...` lists the files that are not in
   the spec's file table (`## Files` of `quick.md`, `## Files to modify/create` of `plan.md`);
   tests, docs and workflow artifacts never count. `hooks/wf-gate.sh` runs it before every edit
   and asks the user when the file is outside (`WF_SCOPE=ask`, the default; `observe` only
   records `scope_outside`; `off` disables it). The hook resolves the ticket from the checkout
   of the file being edited, not from the session's.
