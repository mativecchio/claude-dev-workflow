# Plan — model routing per stage and agent

Status: **proposed, not implemented.** Written 2026-08-11.

Goal: spend the cheapest model that does the job, without paying for it in rework.

---

## 0. Grounding

Per brainstorm §0, a workflow change needs evidence. This one has **none yet**: `events.jsonl` is empty, so there is no measurement of what any stage currently costs or how often it iterates.

That does not block the plan, but it dictates its shape. This is written as **an experiment with a rollback criterion**, not as an optimization. Phase 1 is instrumentation, and no routing decision is made permanent until there are numbers behind it.

The counter-hypothesis is taken seriously throughout:

> A cheaper model on a judgment stage does not save tokens — it moves them. A weak `plan.md` is paid for in re-entries to `implement`, findings at `mr-review`, and rework. The net can easily be negative.

The whole point of measuring is that this is checkable, not arguable.

---

## 1. What can actually be routed

Three surfaces, only two of which are controllable.

| Surface | Count | Routable | Today |
|---|---|---|---|
| Commands that spawn an `Agent` | 4 | ✅ via the `model` param on the Agent call | nothing specified → inherits the session model |
| Language agents (`agents/*.md`) | 15 | ✅ via `model:` in frontmatter | **all `sonnet`**, uniformly |
| Commands in the main context | 11 | ❌ | the user's session model |

**The main-context commands are not routable, and they are the expensive ones.** `wf-implement` runs dozens of turns reading, writing and iterating; `wf-mr-desc` and `wf-commit` write prose. All three run in the session, and no command can change the model of the session it is running in. Any estimate of savings has to exclude them.

So the addressable surface is: **4 Agent invocations per ticket, plus whichever language agents get used.**

That is a minority of total spend. It is also all we control.

### Why Haiku has almost no place here

The obvious Haiku candidates — run the linter, compute the diff, count MR weight, answer "is there a `console.log`" — are no longer model work at all. `wf-checks.sh`, `wf-diff.sh` and `wf-stats.sh` do them deterministically, for zero tokens and with no chance of a false positive.

The harness migration consumed the cheap-model niche by making it mechanical. What remains for a model is judgment, and judgment is where downgrading is riskiest. Haiku is proposed in exactly one place below, and only where the output is structured and verifiable.

---

## 2. Proposed routing

### 2.1 The four Agent-spawning commands

| Command | Today | Proposed | Reasoning |
|---|---|---|---|
| `wf-analyze` | inherits (Opus) | **Opus, always** | It produces `plan.md`, which every later stage consumes. It is the cheapest possible place to overspend and the most expensive place to be wrong. Explicitly excluded from routing. |
| `wf-review-plan` | inherits (Opus) | **Opus** below complexity 5, **Opus** above — i.e. unchanged | It is the system's only hard gate. Weakening the gate to save tokens inverts the purpose of having one. |
| `wf-validate` | inherits (Opus) | **Sonnet** by default, **Opus** when the architecture or security validators are selected, or complexity ≥ 8 | The tests/a11y/performance validators check against stated patterns. The architecture and security ones require judgment about things not in the diff. |
| `wf-mr-review` | inherits (Opus) | **Sonnet** | Its scope shrank in 0.5.0: `/code-review high` now does the generic correctness pass. What is left is contrast against `plan.md` and `related_projects` contracts — bounded, well-specified work. |

Two of four stay on Opus deliberately. **A routing plan that downgrades everything is a cost plan, not an engineering one.**

### 2.2 The 15 language agents

Currently all `sonnet`. Proposed tiering by what the task actually demands:

| Tier | Agents | Why |
|---|---|---|
| **Opus** | `typescript-architect`, `ml-architect`, `rn-architect`, `react-architect` | Type-level programming and architecture decisions: unbounded search space, expensive to get wrong, and the output is consumed by everything downstream. |
| **Sonnet** (unchanged) | `rn-debugger`, `rn-performance`, `rn-bridge`, `python-architect`, `laravel-architect`, `backend-api`, `cv-engineer`, `ml-evaluator` | Diagnosis and framework-idiomatic work against a known stack. |
| **Haiku** | `rn-uiux`, `rn-testing`, `ml-testing` | Pattern-following against an existing example in the repo. All three are instructed to read a sister file first and match it — that is closer to transformation than to design, and the output is immediately verifiable by running it. |

The Haiku tier is the riskiest claim in this document and is treated as such: it is Phase 3, behind data, and reverts on the first sign of rework.

### 2.3 Complexity-driven routing

`wf-analyze` already computes a §5.2 complexity score and emits `complexity_estimate`. That score can pick the model for the stages that come *after* it:

```
points ≥ 8   → Opus for review-plan, validate, mr-review
points ≤ 3   → Sonnet for validate and mr-review; review-plan stays Opus
otherwise    → the table in 2.1
```

This is the elegant part: it reuses a number the system already produces, and it targets spend at the tickets that actually warrant it. It cannot route `wf-analyze` itself — the score does not exist until `wf-analyze` has run.

---

## 3. Phases

### Phase 1 — Make it measurable (do this first, regardless)

Nothing here changes any model. It makes the later decision evidence-based instead of a preference.

1. Add `model` to the `data` of events emitted by the four Agent-spawning commands, so a stage's outcome can be correlated with the model that produced it.
2. Add `wf-stats.sh models` — for each stage and model: number of tickets, mean re-entries, findings originating there, and mean leak distance.
3. Record the current state as the baseline: everything inherits Opus, the agents are all Sonnet.

**Acceptance:** `wf-stats.sh models` prints a table. It will say "insufficient sample" for a while, and that is the correct output.

### Phase 2 — Route the two safe ones

Only the changes with a clear argument that does not depend on unavailable data:

1. `wf-mr-review` → Sonnet. Justified by a real scope reduction already shipped in 0.5.0, not by a guess.
2. `wf-validate` → Sonnet, except architecture/security/complexity ≥ 8.
3. `models` block in `config.json` so a project can override any of it, and `WF_MODEL=opus` as a per-invocation escape hatch.

```json
"models": {
  "analyze": "opus",
  "review-plan": "opus",
  "validate": "sonnet",
  "mr-review": "sonnet"
}
```

**Rollback criterion, written before the change:** if after 10 tickets the findings originating in `validate`/`mr-review` drop (they are catching less) or re-entries to `implement` rise, revert and record it in `improvements.md` with the query that showed it.

### Phase 3 — Tier the agents (behind data)

Apply 2.2 only once Phase 1 has produced a baseline. Start with the Opus promotions, which are the safe direction; the Haiku demotions come last and one at a time.

### Phase 4 — Complexity-driven routing (behind data)

Apply 2.3 once Phase 1 shows the complexity score correlates with anything at all. If §5.3's sister-feature bet turns out not to hold, the score is not yet trustworthy enough to spend money on.

---

## 4. Is it worth it?

Honest accounting.

**In favor:**
- The lever exists, it is free to pull, and it is currently in an unconsidered default state (everything inherited, all agents Sonnet).
- `wf-mr-review` genuinely does less work than it used to. That one is under-argued only if we ignore what 0.5.0 changed.
- Tiering agents costs one line of frontmatter each and is trivially reversible.

**Against:**
- The addressable surface excludes the biggest consumer (`wf-implement`), so the ceiling on savings is modest.
- Every downgrade risks paying more in rework than it saves, and that risk is highest in exactly the stages worth routing.
- There is no measurement today, so any number in a "savings" claim would be invented.

**Verdict: worth doing, in this order, and not all of it.** Phase 1 is worth doing unconditionally — it costs nothing and turns the rest into a decision instead of a preference. Phase 2 is worth doing on its own argument. Phases 3 and 4 should not be started until Phase 1 has produced numbers.

The thing not to do is route everything down at once and declare a saving. That would be indistinguishable from degrading the system, right up until the rework shows up somewhere the routing change is no longer suspected.

---

## 5. Explicitly out of scope

| Item | Why |
|---|---|
| Routing the main-context commands | Not possible: they run in the user's session |
| Estimating token savings | No measurement exists; any figure would be fabricated |
| Routing `wf-analyze` | Its output is the input to everything else; the cheapest place to overspend |
| Weakening `wf-review-plan` | The system's only hard gate |
