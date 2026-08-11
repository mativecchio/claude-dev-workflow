---
description: "Technical analysis of the codebase to plan the implementation. Runs in an isolated context via the Agent tool. Reads refinement-summary.md as input, generates plan.md as output."
allowed-tools: Read, Glob, Grep, Bash, Agent, TodoWrite
---

Your role is to prepare the technical analysis and launch a specialized agent to explore it in depth without polluting the main context.

## Step 0 — Ticket context

```bash
~/.claude/scripts/wf-lib.sh context          # ticket, dir, base, stage, branch, lang
~/.claude/scripts/wf-lib.sh enter-stage analyze
```

`context` creates the ticket's directory and returns `{ticketId}` and `{workflowDir}`. `enter-stage` records the entry while preserving `branch`, `notes`, `iterations` and `subtasks`, and validates the stage name against the system's single vocabulary.

If `context` fails there's no active ticket: ask "What's the ticket number? (e.g. BC-1234)", write `{ "activeTicket": "BC-XXXX" }` to `.claude/workflow/state.json` and retry.

**Language:** address the user in the language reported as `lang` by `context` (`en` by default). Everything written to a file — plan.md, design-decisions.md, code — is always in English.

## Step 1 — Gather context for the Agent

Read the following files (they'll be part of the Agent's prompt):
- `{workflowDir}/refinement-summary.md` → objective and DoD
- `.claude/workflow/config.json` → stack, related projects, DoD
- `CLAUDE.md` or `README.md` → project summary
- The project's top-level structure (a quick `ls`)

If `refinement-summary.md` doesn't exist, ask the user for a description of the task before continuing.

## Step 2 — Launch the analysis Agent

Use the **Agent tool** with the following prompt (interpolating the context you read):

**Pass `model` explicitly**, taking it from the `model=` line that `context` printed in Step 0 (or `~/.claude/scripts/wf-lib.sh model analyze`):

```
Agent(model: "<value from wf-lib>", prompt: ...)
```

Without it the agent inherits the session's model, which makes this stage's output depend on an unrelated setting rather than on a decision. The default is `opus`: this stage carries judgment the rest of the cycle rests on. A project can override it with a `models` block in `config.json`.


---
**AGENT PROMPT:**

You are a senior engineer doing the technical analysis to implement the following task.

**Task:** [contents of refinement-summary.md]

**Project stack:** [stack from the config]
**Working directory:** [cwd]
**Project summary:** [contents of CLAUDE.md/README.md]

## Your analysis process

### 1. Find the "sister feature"
Search the codebase for an implementation similar to what needs to be done. If you find an analogous pattern, use it as the primary reference. Show the path you found.

### 2. Map the impact by layer
Identify which files/modules need to be touched in each layer:
- UI / components
- Hooks / services / business logic  
- State (Redux / Context / Zustand)
- API / endpoints
- Database / migrations
- Tests

### 3. Design the solution
Base it on the codebase's existing patterns (don't invent new conventions).

### 4. Identify risks
- Breaking changes to contracts
- Dependencies between subtasks
- Tech debt that must be recorded but NOT implemented now
- If 2+ effects/observers read and write the same shared storage/state, document the expected execution order and the possible race conditions between them

### 5. Verify contracts with related projects (if applicable)
If the plan touches state, storage, or a contract that another project listed in `related_projects` (config.json) also reads/writes — e.g. shared sessionStorage, a field another repo also persists, an endpoint consumed by another frontend — **don't assume the behavior**: if that project has a local `path`, use Grep/Read to inspect its real source code (how it writes/reads that structure: merge or replace, which types, which format) before designing the solution. Treat the external project as a black box only if its `path` doesn't exist on disk or isn't accessible. Record in the plan what was confirmed this way (with file:line from the external repo) or what remains an unverified risk.

Before assuming a risk is "can't be confirmed, it's an external repo", run something like:
```bash
grep -rln "<relevant key or symbol>" <path of the related_project>
```

### 6. Cross-reference the session history
Read `~/.claude/workflow/flow-history.json`. **If the `entries` array is empty, skip this step without comment** — that's the normal state until Phase 4 of `docs/plan-harness-migration.md` starts populating it, and it says nothing about this ticket.

If there are entries, look for ones whose `key_findings`/`anomalies` mention the same `related_projects` or the same kind of integration this ticket touches. If there are matches, cite them explicitly in the plan (risks section) — they're already-known bugs at that integration point, no need to rediscover them.

## Required output

Write TWO files in `{workflowDir}/`:

**`plan.md`** — only what the implementer needs to know:
```markdown
# Implementation plan — [task name]

## Reference sister feature
[path and brief description]

## Files to modify/create
| File | Change | Reason |
|---|---|---|

## API contract (if applicable)
[endpoint, method, request/response]

## Contracts with related projects (if applicable)
[what was verified against the real source code of each related_project touched, with file:line — or "no shared contracts" if not applicable]

## Infrastructure
- [ ] [env var / migration / feature flag]

## Suggested implementation order
1. [step 1]
2. [step 2]

## Risks and dependencies
- [risk 1]

## Tech debt detected (do not implement)
- [debt 1]
```

**`design-decisions.md`** — context for the MR reviewer:
```markdown
# Design decisions — [task name]

## [Decision 1]
**Alternatives considered:** [A, B, C]
**Chosen:** [A]
**Why:** [reason]

## [Decision 2]
...
```

When you're done, say: "Plan written to {workflowDir}/plan.md and design-decisions.md"

---

## Step 3 — Checkpoint before closing

Read the generated `plan.md` and summarize it for the user.

Before considering the analysis finished, ask:
**"Does the analysis make sense? Is there anything to correct before moving to the plan review?"**

Wait for an explicit answer before suggesting the next step.

## Step 3.5 — Record the complexity estimate

Score the plan with the rubric in `docs/brainstorm-metrics-and-complexity.md` §5.2. **This is not new analysis work:** the seven dimensions were already resolved in the Agent's steps 1-5, this only formalizes them.

| Dimension | Values → points |
|---|---|
| Sister feature | found `0` / partial `3` / none `6` |
| Files to touch | 1-3 `0` / 4-8 `2` / 9-15 `4` / >15 `6` |
| Layers crossed | 0-1 `0` / 2-3 `2` / 4-5 `4` / 6 `5` |
| External projects | 0 `0` / 1 `3` / 2+ `5` |
| Shared state / races | no `0` / yes `4` |
| Gaps in the DoD | none `0` / minor `2` / major `5` |
| Infra (migration, env var, flag) | no `0` / yes `3` |

Mapping to points: 0-4→`1`, 5-8→`2`, 9-13→`3`, 14-19→`5`, 20-26→`8`, 27+→`13`.

```bash
~/.claude/scripts/wf-event.sh complexity_estimate \
  --raw_score [sum] --points [fibonacci] \
  --split_recommended [true if points >= 8] \
  --dimensions '{"sister_feature":{"value":"none","pts":6},"files":{"value":11,"pts":4},"layers":{"value":4,"pts":4},"external_projects":{"value":1,"pts":3},"shared_state":{"value":true,"pts":4},"dod_gaps":{"value":"none","pts":0},"infra":{"value":false,"pts":0}}'
```

Save the same thing to `{workflowDir}/complexity.json` so `/wf-retro` can close the (estimated, actual) pair without re-reading the JSONL.

Show the score to the user. **If it's ≥ 8, say so**: that's the threshold where the ticket becomes a candidate for splitting. Don't split automatically — just flag it.

> The thresholds are provisional and were chosen without data (§5.4). Today their only purpose is to generate the "estimated" side of the pair, to calibrate them at 15-20 tickets. Don't treat them as truth.

## Step 4 — Next step

If the user confirms, suggest: "Next: `/wf-review-plan` to verify the plan against the real codebase."
