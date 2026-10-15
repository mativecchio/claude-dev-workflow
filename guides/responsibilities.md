# Responsibilities — the design checks every stage applies

SOLID, applied at the scale of a feature: where each piece of code lives, what each file and
function is responsible for, and how the pieces depend on each other. R1 is the S, R6 the O (and
the L: a variant keeps what the piece's callers rely on, or it is a new piece), R4 the I, R2 the D
(the rules depend on no storage, network or render; the effects depend on them). They are the
`responsibilities` check of `checks.md`, and they apply to refactors as much as to new code. `/wf-analyze` designs with
these checks, `/wf-review-plan` verifies the design, `/wf-implement` follows it, and `/wf-validate`
and `/wf-mr-review` check the result.

They apply **whether or not the repo has a written rule for them**. When the repo's guidelines or
ADRs say something more specific (a placement map, a layer rule), the written rule wins and the
finding cites it (`path#section`). When there is no written rule, the finding cites this guide
(`R1`…`R7`) and the evidence in the code: the functions with their line ranges, the sibling file
that already does it the other way, the existing piece that should have been reused.

## The checks

**R1 — One responsibility per file.** A file has one reason to change. Groups that change for
different reasons belong in different files: I/O (storage, network, the DOM), domain rules,
parsing and validation, presentation. Size is a symptom, not the rule. A new or grown file over
~300 lines of production code, or with two or more clusters of functions that do not call each
other, has to justify itself, and the check lists the clusters with their line ranges.

**R2 — Rules apart from effects.** The code that decides something (compares, chooses, computes the
next state) is pure: it takes inputs and returns outputs. Reading or writing storage, calling a
service, dispatching, setting UI state happen at the edges, around the pure core. The test of the
check: can the rules be tested without mocking storage, the network or a render? A test file several
times larger than the module it tests, or one that sets up storage for every rule, is the symptom.

**R3 — Every function in its place.** Place each new function by what it depends on, unless the
repo's own placement map says otherwise:
- no framework and used by one page or feature → that feature's `utils` file;
- no framework and used by two or more features → the shared utils folder;
- framework state or effects (a React hook, a Vue composable) → a hook beside its only consumer, or
  the shared hooks folder;
- rendering → a component;
- mapping between the backend's shape and the domain's → an adapter;
- generic helpers (type guards, date or string helpers) → the shared place, after checking that one
  does not exist already.

A pure function declared at the top of a hook or a component file is the most common miss.

**R4 — Narrow interfaces.** A hook, function or component that takes many inputs (more than ~7), or
several callbacks that belong to another unit, is driving that unit from outside. Prefer returning
data and letting the owner apply it, so each unit stays the only one that changes its own state.

**R5 — Programmatic paths do not reuse UI handlers.** Filling a form from data, restoring a saved
state or replaying an action does not go through the handlers built for the user's events. Those
carry side effects meant for a person (validating on each keystroke, persisting the choice,
resetting dependent fields, conflict dialogs that check one field), and a programmatic caller gets
all of them, in an order nobody designed. Apply the values once, then run the effects the
programmatic path actually needs.

**R6 — Extend, do not copy.** A new variant of something that exists (another dialog, another
kind of item) extends the existing piece with a parameter or a strategy, instead of copying it and
changing one line.

**R7 — The simplest approach that meets the requirement.** Name the alternative that was
considered and why it was not taken. When most findings of a review come from one design choice,
that choice is the finding.

## Weight and grouping

- A finding against R1–R7 is **Important** when it decides how other findings get fixed, or when it
  makes the module hard to test or to change. Otherwise it is a Suggestion. It is never demoted to
  a "consistency" remark just because no written rule covers it.
- When several findings share one design cause (R5 above produces most of them), report the cause
  once as the root finding, and have the others point to it rather than read as unrelated bugs. The
  author can then fix the cause once.

## How each stage uses it

| Stage | What it does with R1–R7 |
|---|---|
| `/wf-analyze` | `plan.md` gets a *Responsibilities* table: for each new or changed file, its one responsibility, and for each new function, where it goes and why (R3). Hooks and components list their inputs (R4). The approach names the alternative considered (R7). |
| `/wf-review-plan` | Verifies the table against R1–R7 and the repo's placement rules. A plan with new files and no table is an Important finding. |
| `/wf-implement` | Places every new function as the table says. A file that crosses ~300 lines or takes on a second responsibility, or a hook that grows past ~7 inputs, stops the group and is reported as a deviation before going on. Two hooks hold it when the instruction is forgotten: `wf-gate.sh` stops code edits while the plan has no *Responsibilities* table, and `wf-shape.sh` tells the agent the moment a production file crosses the limit (`max_file_lines` in the project config, 300 by default). |
| `/wf-validate` | The Architecture validator applies R1–R7 to the diff. |
| `/wf-mr-review` | The Agent runs a *Responsibilities* pass on every new or grown file, written rule or not, as its own output section. |
