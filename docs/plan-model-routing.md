# Plan — the right model per stage and agent

Status: **proposed, not implemented.** Written 2026-08-11.

Goal: every stage runs on the model its work actually demands, chosen deliberately and stated explicitly.

**This is not a cost plan.** Token spend is not the criterion and no phase here is justified by savings. The criterion is fitness: the analysis stages carry the judgment the whole cycle rests on, and they should run on the strongest model available regardless of what that costs. Where a smaller model is proposed, it is because it is *adequate for that task*, never because it is cheaper.

---

## 1. The actual problem: nothing is chosen

Two findings, and the first is the reason this plan is worth doing even with zero measurement behind it.

### 1.1 `plan.md` is produced by whatever model the session happens to be set to

The four Agent-spawning commands (`wf-analyze`, `wf-review-plan`, `wf-validate`, `wf-mr-review`) invoke the Agent tool with **no `model` and no `subagent_type`**. That means a general-purpose agent that **inherits the parent session's model**.

So the quality of `plan.md` — the artifact `review-plan`, `implement`, `validate`, `test` and `mr-review` all consume — depends on an unrelated UI toggle. Run a session on Sonnet, or with fast mode on, and the analysis that everything else is built on came from there. Nobody decided that; it is what inheritance does when no one states a preference.

**This is a consistency defect, not an optimization opportunity.** The same ticket analyzed on two different days can get two different qualities of plan for reasons invisible in the output.

### 1.2 The architecture agents are Sonnet by an unreviewed default

All 15 language agents declare `model: sonnet`. That includes `typescript-architect`, `rn-architect`, `react-architect` and `ml-architect` — the four whose job is open-ended design with an unbounded search space, and whose output other code is then written against.

Uniform is not the same as decided. `rn-uiux` arranging a StyleSheet and `typescript-architect` resolving conditional generics are not the same class of problem, and they should not resolve to the same model by accident.

---

## 2. Proposed assignment

### 2.1 The four Agent-spawning commands

| Command | Today | Proposed | Reasoning |
|---|---|---|---|
| `wf-analyze` | inherits the session | **Opus, explicit** | Produces `plan.md`. Every later stage consumes it, and a weak plan is not visible as a weak plan — it surfaces later as rework nobody attributes to the analysis. The most important thing in this document. |
| `wf-review-plan` | inherits the session | **Opus, explicit** | Verifies the plan against the real codebase and holds the only hard gate in the system. A gate that misses things is worse than no gate, because it grants confidence. |
| `wf-validate` | inherits the session | **Opus, explicit** | Its job is finding what the implementation got wrong. Anything it misses reaches the MR, and the cost of a miss is not the tokens saved. |
| `wf-mr-review` | inherits the session | **Opus, explicit** | Last line before merge. Its scope narrowed in 0.5.0 (the generic pass went to `/code-review`), but what remains is the judgment part: contract verification against another repo's real source, and contrast against the plan. |

**All four end up on Opus, so where is the routing?** There isn't any, and that is the honest answer: under a fitness criterion these four are all judgment work and they all warrant the strongest model. The change is that it becomes **explicit and guaranteed** instead of inherited and accidental.

That is worth doing on its own. Today all four are Opus *only if* the session happens to be. Tomorrow they are Opus because the command says so.

### 2.2 The 15 language agents

Here differentiation is real, because the tasks genuinely differ.

| Model | Agents | Why this is the adequate one |
|---|---|---|
| **Opus** | `typescript-architect`, `rn-architect`, `react-architect`, `ml-architect` | Open-ended design. No single correct answer to check against, and later code is written against their output — a mediocre abstraction propagates. |
| **Sonnet** | `rn-debugger`, `rn-performance`, `rn-bridge`, `python-architect`, `laravel-architect`, `backend-api`, `cv-engineer`, `ml-evaluator`, `rn-uiux`, `rn-testing`, `ml-testing` | Bounded work against a known stack with a checkable answer: a stack trace has a cause, a test either passes, a StyleSheet either lays out. These agents are already instructed to read a sister file and match it — recognition and transformation, not design. |

Sonnet stays for eleven agents because it is **sufficient** for them, which is a different claim from cheap. Promoting `rn-uiux` to Opus would not produce a better StyleSheet.

### 2.3 Haiku: dropped entirely

The earlier draft of this plan proposed Haiku for the pattern-following agents. Removed, for two reasons:

1. The work Haiku would suit is no longer model work. `wf-checks.sh`, `wf-diff.sh` and `wf-stats.sh` do it deterministically, for zero tokens and with no chance of a false positive. The harness migration consumed that niche.
2. What is left in every seat is judgment of some kind, and under a fitness criterion the burden of proof for the smallest model is not met anywhere in this system.

### 2.4 Complexity-driven routing: dropped

The earlier draft proposed using the §5.2 complexity score to downgrade simple tickets. Removed: it optimizes for spend, which is not the goal, and it introduces a failure mode where an underestimated ticket silently gets weaker review — the exact case where review matters most.

The score keeps its existing job (flagging split candidates). It does not choose models.

---

## 3. Phases

### Phase 1 — Make the choice explicit

1. The four commands pass `model: "opus"` on their Agent invocation.
2. `models` block in `config.json` so a project can override, with these as defaults:

```json
"models": {
  "analyze": "opus",
  "review-plan": "opus",
  "validate": "opus",
  "mr-review": "opus"
}
```

3. `WF_MODEL` as a per-invocation escape hatch, for deliberately running a cheap pass on a trivial ticket.

**Acceptance:** the model each stage runs on no longer depends on the session. Verifiable by reading the command; no data required.

### Phase 2 — Promote the four architecture agents

`model: opus` in the frontmatter of `typescript-architect`, `rn-architect`, `react-architect`, `ml-architect`. One line each, trivially reversible.

The other eleven stay on Sonnet, now as a recorded decision rather than a default — worth writing down in the agent files themselves so the next person does not read uniformity as intent.

### Phase 3 — Verify it did what it should (not a gate on 1 and 2)

Phases 1 and 2 stand on their own argument and do not need to wait. This phase checks the result rather than authorizing it:

1. Add `model` to the `data` of the events the four commands emit.
2. `wf-stats.sh models` — per stage and model: tickets, mean re-entries, findings originating there, mean leak distance.

**What would falsify the plan:** if findings originating in `analyze` do not fall after Phase 1 on projects where the session used to be Sonnet, then the model was not the binding constraint and the prompt or the rubric is. That is worth knowing, and it is the kind of thing that stays invisible without the instrumentation.

---

## 4. Is it worth it?

**Yes, and the reason is consistency, not spend.**

The strongest argument is 1.1: right now the most important artifact in the system is produced by an unstated setting. Two runs of the same ticket can differ for a reason that appears nowhere in the output, which makes every downstream comparison — including the metrics this system just built — noisier than it needs to be.

Phase 1 costs four lines and removes that variable. Phase 2 costs four more and fixes a default that nobody chose. Neither needs data to justify, which is unusual here and worth naming: they are not behavioral bets like the runtime validator, they are corrections to something that was never decided.

Token spend will go **up**, not down, on sessions that were running Sonnet. That is the intended direction.

---

## 5. Explicitly out of scope

| Item | Why |
|---|---|
| Routing the main-context commands (`wf-implement`, `wf-commit`, `wf-mr-desc`, …) | Not possible: they run in the user's session, and no command can change the model of the session running it |
| Haiku anywhere | See 2.3 |
| Complexity-driven model selection | See 2.4 |
| Estimating token cost | Not the criterion |
