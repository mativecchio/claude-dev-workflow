# Architecture

## Overview

`claude-workflow` is a two-layer system:

1. **Workflow commands** (`~/.claude/commands/wf-*.md`) — orchestrate the development lifecycle, language-agnostic
2. **Language agents** (`~/.claude/agents/`) — domain experts for specific stacks, invoked on demand

Both layers only load context when invoked — no baseline token cost.

## Component types

### Slash commands (skill-style)
Run in the main conversation context. Used for stages that need multi-turn dialogue and accumulated session context.

`/wf`, `/wf-refine`, `/wf-implement`, `/wf-test`, `/wf-retro`, `/wf-mr-desc`, `/wf-jira`

### Slash commands (agent-style)
Run in the main context, but internally spawn a subagent via the `Agent` tool for isolated execution. The subagent writes output to `.claude/workflow/` files; the command reads and presents the result.

`/wf-analyze`, `/wf-review-plan`, `/wf-validate`, `/wf-mr-review`

### Language agents
Invoked by workflow commands (or directly by the user) for domain-specific decisions. They have no project-specific context by default — that lives in per-project `.claude/agents/` overrides.

## State management

Multi-ticket: the root state only tracks which ticket is active, everything else is per-ticket.

| Layer | Storage | Scope |
|---|---|---|
| In-stage tracking | `TodoWrite` | Current command execution |
| Active-ticket pointer | `.claude/workflow/state.json` → `{ "activeTicket": "BC-XXXX" }` | Persists across commands within a project |
| Per-ticket state | `.claude/workflow/{ticketId}/state.json` | Stage, progress, saved branch, optional `notes` (retroactive tickets) |
| Cross-session artifacts | `.claude/workflow/{ticketId}/plan.md`, `refinement-summary.md`, `review-findings.md` | Handoff between stages, scoped to one ticket |
| Historical log | `~/.claude/workflow/flow-history.json` | Cross-project, used by retrospective and by contract-risk checks in `wf-analyze` |

Every subcommand's "Paso 0" reads `activeTicket` from the root file, then reads/writes its per-ticket state under `.claude/workflow/{ticketId}/`.

**Retroactive tickets:** when a ticket is activated with implementation commits already on the branch but no `plan.md`, per-ticket `state.json` starts at stage `"implement"` with a `notes` field summarizing what was done and why there's no formal plan. Commands that normally require `plan.md`/`refinement-summary.md` (`wf-validate`, `wf-mr-desc`, `wf-mr-review`) fall back to reading `notes` instead of blocking.

## Handoff between stages

All stage handoffs happen through files in `.claude/workflow/{ticketId}/`:

```
/wf-refine  → writes → refinement-summary.md
/wf-analyze → reads  → refinement-summary.md
            → writes → plan.md
            → asks for expected execution order/race cases when effects read/write the same
              shared-storage key (race conditions only show up at runtime otherwise)
            → verifies related_project contracts (greps sibling repo path from config.json,
              cross-checks flow-history.json) when the diff touches shared state
/wf-review-plan → reads  → plan.md + refinement-summary.md
                → writes → review-findings.md
                → blocks approval if a shared-state risk was flagged but not verified
/wf-implement → reads → plan.md + review-findings.md
/wf-validate  → reads → plan.md (for diff context, against merge-base(HEAD, base) — not a plain
                two-dot diff, which breaks silently if base advanced past the fork point)
              → same related_project verification gate as review-plan
              → REQUIERE CAMBIOS gives a per-finding picker (implement/ignore/tech-debt) instead
                of all-or-nothing; the decided list flows to wf-implement, which skips its own
                "¿Arrancamos?" checkpoint when arriving pre-decided
/wf-test      → adds a manual-verification checklist item, gated on user confirmation, when a
                related_project risk exists (no in-repo test can confirm external-system behavior)
/wf-mr-review → reads → plan.md + refinement-summary.md (injects into agent prompt)
              → diffs against merge-base(HEAD, base); same related_project verification gate
/wf-mr-desc   → reads → plan.md + refinement-summary.md
              → diffs against merge-base(HEAD, base)
```

The Memory system is **not** used for workflow state — it's unreliable across project directory switches. It's only used for global path registry (external project paths).

## Checkpoint model

Each stage has checkpoints at different risk levels:

| Stage | Checkpoint type |
|---|---|
| `wf-analyze` | Soft — shows analysis, asks if correct before proceeding |
| `wf-review-plan` | **Hard block** — explicit "sí" required before implementation; also blocks on unverified shared-state risk |
| `wf-implement` | Before each file group (high-risk changes) — skipped on explicit invocation or when arriving with a pre-decided finding list from `wf-validate` |
| `wf-validate` | After each iteration — per-finding picker (implement/ignore/tech-debt) instead of all-or-nothing; also blocks on unverified shared-state risk |
| `wf-test` | After gap analysis — confirms before writing tests; adds manual-verification item for unverified external-project risk |

Before adding a validation guard for a value, `wf-implement` greps all call sites of that value first — a guard added to only one of several call sites is a common miss (e.g. BC-1529's `isValidDate` gap, present in 4 places but found across two review rounds instead of one).

## Project-level overrides

Projects can override global agents by placing agent files in `.claude/agents/`. Claude Code will prefer the project-local agent when both exist.

```
.claude/
├── agents/
│   └── rn-architect.md   ← overrides ~/.claude/agents/rn-architect.md
│                            with project-specific context
└── workflow/
    ├── config.json        ← stack, DoD, related projects
    ├── state.json         ← current workflow state
    ├── refinement-summary.md
    ├── plan.md
    └── review-findings.md
```

## Adding new agents

1. Create the agent file in the appropriate `agents/` subdirectory
2. Add the agent name to the `install.sh` copy step (it uses `find`, so no change needed)
3. Reference the agent in the relevant workflow command if it should be auto-suggested
4. Run `install.sh` to deploy
