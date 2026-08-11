# Plan — the right model per stage and agent

Status: **proposed, not implemented.** Written 2026-08-11.

## The thesis

> Invest heavily in analysis; with a solid plan, execution does not need the same horsepower.

Analysis and verification decide *what* gets built and whether it holds up. That judgment is the expensive thing to get wrong, and it should run on the strongest model available. Documentation, test writing and implementation-against-an-approved-plan are bounded transformation work with a checkable result — a smaller model is not a compromise there, it is the adequate choice.

This is a design principle, not a cost cut. Spend on the analysis stages goes **up**.

---

## 1. The obstacle, and the way around it

Only 4 of 15 commands spawn an `Agent`, and those are the only ones with a `model` parameter. The rest — including `wf-implement`, `wf-test`, `wf-mr-desc` and `wf-commit` — run in the user's session, and no command can change the model of the session running it.

Stating that is not an answer, so here is the actual one. **A main-context command becomes routable by moving its bounded work into an Agent.** Every one of these commands is a mix of two things:

| | Needs the session | Can be an Agent |
|---|---|---|
| `wf-mr-desc` | showing and adjusting the result with you | writing the description from plan + diff |
| `wf-commit` | confirming before committing | generating the message from the diff |
| `wf-test` | deciding *which* gaps matter | writing the tests once the gaps are decided |
| `wf-implement` | checkpoints, decisions, iterating with you | — (see 2.4) |

Splitting them that way delivers the routing **and** a second benefit worth as much: the bounded work stops consuming the session's context window. Generating an MR description today burns main-context tokens on a task that never needed to be there.

### 1.2 The defect that exists today

The four Agent-spawning commands pass **no `model`**, so their agent inherits the session's. `plan.md` — the artifact every later stage consumes — is produced by whatever model the session happens to be set to. Run with `/fast` or on Sonnet and the analysis everything is built on came from there.

Under this plan's own thesis that is the worst possible failure: it is precisely the investment that must not be skimped, and it is currently decided by an unrelated toggle.

---

## 2. Proposed assignment

### 2.1 Analysis and verification → Opus, explicit

| Command | Today | Proposed |
|---|---|---|
| `wf-analyze` | inherits the session | **Opus** |
| `wf-review-plan` | inherits the session | **Opus** |
| `wf-validate` | inherits the session | **Opus** |
| `wf-mr-review` | inherits the session | **Opus** |

`analyze` and `review-plan` are the thesis itself: everything downstream is only as good as they are.

`validate` and `mr-review` stay on Opus for a different reason — they are what makes the rest of the plan safe. If implementation runs on a smaller model, the checks that catch its mistakes are the last thing to weaken. Cheapening both ends at once is how a cost decision turns into a quality decision without anyone noticing.

### 2.2 Documentation → delegate to Sonnet

| Command | Change |
|---|---|
| `wf-mr-desc` | Step 2 (writing the description) becomes an Agent call with `model: sonnet`. Steps 0/1/3 — context, showing, adjusting — stay in the session. |
| `wf-commit` | Step 4 (generating the message) becomes an Agent call with `model: sonnet`. The confirmation before committing stays in the session. |

Both take structured input (plan, refinement, diff) and produce prose in a fixed format. There is no open-ended judgment; there is a template and a diff to describe faithfully.

Haiku was considered and rejected for these: an MR description that misreads *why* a change was made is worse than no description, because a reviewer trusts it. Sonnet is the adequate floor, not the cheapest one.

### 2.3 Tests → split by what the step actually does

| Step | Model | Why |
|---|---|---|
| `wf-test` Step 2 — gap analysis | session (unchanged) | Deciding which uncovered cases *matter* is judgment, and it is interactive with you. |
| `wf-test` Step 3 — writing the tests | **Agent, `rn-testing` / `ml-testing`** (already `sonnet`) | Once the gaps are agreed, writing them is pattern-following against sister tests, and the result is checkable by running it. |

The tests agents already exist and are already Sonnet. This just routes the work to them instead of writing tests inline.

### 2.4 Implementation → cannot be routed, but the thesis can be supported and tested

`wf-implement` cannot become an Agent without losing what makes it work: checkpoints before each file group, debug mode, and iterating with you. That interactivity is the point, and it lives in the session.

What can be done instead, and it is not a consolation prize:

1. **Tell you when the plan is strong enough to downshift.** At Step 0, `wf-implement` reports whether the conditions for your thesis hold, and recommends a model:

```
📋 Plan: BC-1429 — complexity 3, sister feature found, review-plan approved
   with no blocking findings.
   → Sonnet is adequate for this implementation. Switch with /model sonnet.
```

versus

```
📋 Plan: BC-1429 — complexity 8, no sister feature, 2 unresolved findings
   from review-plan.
   → Stay on Opus. There is no pattern to follow here and the plan has
     open questions.
```

The switch is yours to make; the recommendation is mechanical, derived from `complexity.json` and `review-findings.md`.

2. **Record which model implemented, and test the thesis.** Emit the session model with the implement-stage events. Then the claim "Sonnet is fine when analysis was strong" becomes a query:

> re-entries to `implement`, grouped by model, conditioned on complexity score and whether a sister feature was found.

If Sonnet-implemented tickets with a strong plan re-enter no more often than Opus-implemented ones, the thesis holds and it is written down with the query behind it. If they re-enter more, the condition was wrong and we learn where the line actually is.

### 2.5 Language agents

| Model | Agents | Why |
|---|---|---|
| **Opus** | `typescript-architect`, `rn-architect`, `react-architect`, `ml-architect` | Open-ended design with no single correct answer, and later code is written against their output. Currently Sonnet by an unreviewed default — all 15 agents declare the same model, which is uniformity, not a decision. |
| **Sonnet** | the other 11 | Bounded work against a known stack with a checkable answer: a stack trace has a cause, a test passes or not, a layout works or not. |

---

## 3. Phases

### Phase 1 — Fix what is currently accidental
The four Agent-spawning commands pass `model: "opus"` explicitly. A `models` block in `config.json` allows per-project override; `WF_MODEL` overrides per invocation.

**No data needed:** this corrects a value nobody chose.

### Phase 2 — Promote the four architecture agents
`model: opus` in their frontmatter, and a line in the other eleven recording that Sonnet is deliberate rather than default.

### Phase 3 — Delegate documentation
`wf-mr-desc` Step 2 and `wf-commit` Step 4 become Agent calls with `model: sonnet`. Both keep their confirmation step in the session.

**Watch for:** a description that reads fluently but misstates the intent. If that appears, the input is underspecified, not the model — fix the prompt before moving the model back.

### Phase 4 — Delegate test writing
`wf-test` Step 3 routes to `rn-testing` / `ml-testing`. Gap analysis stays interactive.

### Phase 5 — Support and test the implementation thesis
The Step 0 recommendation, plus `model` on implement-stage events and a `wf-stats.sh models` query. This is the only phase that needs accumulated tickets, and it is the one that turns the thesis into something known rather than believed.

---

## 4. Is it worth it?

**Yes, and phases 1-4 do not need data to justify.**

Phase 1 removes a real defect: the most important artifact in the system is currently produced by an unstated session setting. Phase 2 corrects a default. Phases 3 and 4 move bounded work off the session, which routes it *and* stops it consuming the context window — two benefits from one change.

Phase 5 is the interesting one, because your thesis is genuinely testable and currently untested. "Sonnet is enough for implementation when the analysis was strong" is either true, true under conditions, or false, and the system now records enough to tell which.

Net token spend is not the goal and probably goes up: four stages move from possibly-Sonnet to definitely-Opus, four agents get promoted, and the savings are confined to documentation and test writing.

---

## 5. Explicitly out of scope

| Item | Why |
|---|---|
| Making `wf-implement` an Agent | Would cost the checkpoints, debug mode and interactivity that are the point of the stage |
| Haiku anywhere | Considered for documentation and rejected in 2.2. The work it would suit is already done by scripts, for zero tokens |
| Complexity-driven model selection for review stages | Weakens review exactly on tickets whose complexity was underestimated — the case where it matters most. The score recommends, it does not decide |
