---
description: "Continuous workflow improvement. With an argument: records an observation in the session log. Without one: full review — categorizes everything accumulated and proposes code fixes and command improvements."
allowed-tools: Read, Write, Edit, Bash, Glob, TodoRead
---

Continuous improvement command. You operate in two modes depending on whether there's an argument.

**Language:** address the user in the language returned by `~/.claude/scripts/wf-lib.sh language` (`en` by default). Everything written to a file — improvement-log.md, improvements.md, command edits — is always in English.

---

## Flag mode — `/wf-improve <observation>`

When `$ARGUMENTS` has text, record the observation without interrupting the work.

### Step 1 — Detect the current context

Read `.claude/workflow/state.json` → `activeTicket`.
Read `.claude/workflow/{activeTicket}/state.json` → current `stage`.

### Step 2 — Classify the observation

Determine which category the reported problem belongs to:

| Category | Description |
|---|---|
| `workflow` | The command behaved differently than expected — the command should be improved |
| `code` | Something ended up badly implemented in the code |
| `plan` | The analysis or plan was wrong or incomplete |
| `communication` | Claude misread the intent or didn't ask what it needed to |
| `other` | Another kind of observation |

### Step 3 — Append to the log

Create or append to `.claude/workflow/improvement-log.md`:

```markdown
---
**[timestamp] — Stage: [current stage]**
**Category:** [category]
**Observation:** [text from $ARGUMENTS]
**Context:** [what was being done when it happened]

---
```

Confirm to the user:
```
📝 Recorded in improvement-log.md
Category: [category]
You can continue — everything gets reviewed at the end with /wf-improve
```

---

## Review mode — `/wf-improve` (no arguments)

Full review of everything accumulated during the session.

### Step 1 — Gather everything

Read `.claude/workflow/state.json` → `activeTicket`.

Read:
- `.claude/workflow/improvement-log.md` → accumulated observations
- `.claude/workflow/{activeTicket}/state.json` → stages visited
- `.claude/workflow/{activeTicket}/plan.md` → to understand what was implemented
- `~/.claude/workflow/flow-history.json` → if there are 3+ entries, cross-reference patterns

### Step 2 — Show the analysis

```
## Continuous improvement review

### Accumulated observations
[list of what was recorded during the session]

### Detected patterns
[if there are 2+ observations of the same kind or component]

### Categorization
🔧 Code fixes: [N items]
⚙️  Workflow improvements: [N items]
📋 For the plan / analysis: [N items]
```

### Step 3 — Propose actions

For each item, propose a concrete action:

**Code fixes** — show which file/function needs correcting and the exact change.

**Workflow improvements** — show the affected command (`wf-*.md`) and the proposed instruction change. Example:
```
Command: wf-analyze
Problem: it doesn't ask about endpoint permissions before generating the plan
Proposed change: add to Step 2 "If the plan includes new endpoints, verify the required permissions"
```

**Plan / analysis** — note it for the history; if the ticket is still open, suggest running `/wf-analyze` again.

### Step 4 — Apply with approval

For each proposal, ask for confirmation before applying:
**"Should I apply this change?"**

- **Code fixes** → apply with the `Edit` tool on the current project.
- **Workflow improvements** → edit **`{repoPath}/commands/wf-*.md`**, where `{repoPath}` comes from `repo_path` in `~/.claude/workflow/config.json`. Never edit `~/.claude/commands/`: it's an installation target, and every change made there is lost on the next `install.sh` (that's how `wf-commit.md` and `wf-deploy.md` were lost, left installed with no origin in the repo).

  If there's no `repo_path` configured, warn and ask for the repo's `install.sh` to be run before applying workflow improvements.

After applying a workflow improvement:
1. Record the evidence in `~/.claude/workflow/improvements.md` — rule §0: without citable evidence, the change isn't applied.
2. Reinstall: `"{repoPath}/install.sh"`
3. Verify: `"{repoPath}/install.sh" --check`

The change stays in the repo's working tree, uncommitted.

### Step 5 — Clean the log

Once the review is complete, ask whether to clear `improvement-log.md` for the next session.

If they accept → replace it with:
```markdown
# Improvement Log

_Record observations during the session with `/wf-improve <observation>`_
```

### Step 6 — Offer to save to flow-history

Ask whether they want to add an entry to the global history with the improvements applied in this session.
