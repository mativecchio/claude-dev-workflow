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

Three layers, each with a distinct purpose:

| Layer | Storage | Scope |
|---|---|---|
| In-stage tracking | `TodoWrite` | Current command execution |
| Workflow state | `.claude/workflow/state.json` | Persists across commands within a project |
| Cross-session artifacts | `.claude/workflow/plan.md`, `refinement-summary.md`, `review-findings.md` | Handoff between stages |
| Historical log | `~/.claude/workflow/flow-history.json` | Cross-project, used by retrospective |

## Handoff between stages

All stage handoffs happen through files in `.claude/workflow/`:

```
/wf-refine  → writes → refinement-summary.md
/wf-analyze → reads  → refinement-summary.md
            → writes → plan.md
/wf-review-plan → reads  → plan.md + refinement-summary.md
                → writes → review-findings.md
/wf-implement → reads → plan.md + review-findings.md
/wf-validate  → reads → plan.md (for diff context)
/wf-mr-review → reads → plan.md + refinement-summary.md (injects into agent prompt)
/wf-mr-desc   → reads → plan.md + refinement-summary.md
```

The Memory system is **not** used for workflow state — it's unreliable across project directory switches. It's only used for global path registry (external project paths).

## Checkpoint model

Each stage has checkpoints at different risk levels:

| Stage | Checkpoint type |
|---|---|
| `wf-analyze` | Soft — shows analysis, asks if correct before proceeding |
| `wf-review-plan` | **Hard block** — explicit "sí" required before implementation |
| `wf-implement` | Before each file group (high-risk changes) |
| `wf-validate` | After each iteration — shows feedback before next loop |
| `wf-test` | After gap analysis — confirms before writing tests |

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
