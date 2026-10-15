# Checks — the catalogue every stage selects from

One list of checks, picked by **what the change touches**, never by language or framework.
`/wf-analyze` answers the plan side of the checks that apply, `/wf-review-plan` verifies those
answers, and `/wf-validate` and `/wf-mr-review` check the diff. Adding a concern is adding an
entry here, never a new command or a new validator.

When the repo's own rules say something more specific (its guidelines, ADRs, lint), the written rule
wins and the finding cites it (`path#section`).

## Surfaces

A check runs only when the change touches one of the surfaces it lists. Read them from the plan's
*Surfaces* line or from the diff: what changed, not which repo or folder it is in. A backend that
renders an email touches `ui`.

| Surface | The change… |
|---|---|
| `code` | adds or changes production code. Every change that is not only documentation. |
| `ui` | changes something a person sees or operates: a screen, a component, a template, an email. |
| `text` | adds or changes a text the user reads, in a project that translates. |
| `entry-point` | accepts input from outside its process: an endpoint, a form handler, a webhook, a queue consumer, a command. |
| `data` | changes what is stored: a schema, a migration, a backfill, a cache or browser-storage layout. |
| `boundary` | changes what another repo or service relies on: a payload, a published package's API, a token claim (the entries of `contracts.md`). |
| `auth` | changes who may do what: login, tokens, sessions, roles, permissions. |
| `personal-data` | reads, stores, shows or sends data about a person. |

A check that applies to no surface of the change is reported `N/A` with that reason, never left out:
an absent line and a skipped check look the same.

## Weight

- **blocks** — a finding goes to the ❌ *Failed* block of `/wf-validate` and is Important in
  `/wf-mr-review`: fixed, or ignored or recorded as tech debt by an explicit decision of the user.
- **warns** — a finding goes to ⚠️ *Warnings* in `/wf-validate` and is a Suggestion in
  `/wf-mr-review`, unless a written rule of the repo covers it; then it weighs as `blocks` and cites
  that rule.

## Checks

### `responsibilities` — blocks

**Applies when** `code`, a refactor included: moving code is when it is cheapest to put it where it
belongs. **Plan:** the *Responsibilities* table. **Diff:** `R1`–`R7` of `responsibilities.md`, which
are SOLID at the scale of a feature — one responsibility per file (S), extend instead of copy (O),
narrow interfaces (I), rules apart from effects so the rules depend on no storage, network or render
(D); a variant that extends a piece keeps what that piece's callers rely on (L), or it is a new
piece. **How:** judgement, plus `wf-shape.sh` (file size) and `wf-gate.sh` (no table, no code).

### `size` — blocks

**Applies when** `code`. **Diff:** `wf-diff.sh --size` against `mr_size`: production code only;
over the limit, the reason is in `mr-size.md`. **How:** script.

### `tests` — blocks

**Applies when** `code`. **Plan:** the tests each group needs, written with it, never deferred.
**Diff:** every new function and every new branch of behaviour is exercised by a test in the same
change, error paths included; tests are sociable (only external services mocked); the checks of
`wf-checks.sh` are green. **How:** script for green, judgement for coverage.

### `translations` — blocks

**Applies when** `text`. **Diff:** every text the change adds or changes is filled in every language
the project already carries: none empty, fuzzy, holding the source language, or describing a source
text that has since changed; the words match the ones the project already uses for the same concept.
**How:** judgement over the translation files.

### `release-safety` — blocks

**Applies when** `entry-point`, `data`, `boundary`, or behaviour already in production changes.
**Plan:** what happens if this change reaches production before or without its counterpart, and how
partial behaviour is kept from the user (unreachable, or behind a named gate). **Diff:** nothing a
deployed consumer still reads is removed, renamed or tightened in the same change that adds its
replacement; a migration is additive and runs against the code currently deployed; a consumer
tolerates the new field or endpoint being absent. **How:** judgement.

### `contracts` — blocks

**Applies when** `boundary`. **Plan:** `contracts.md` records both sides with `file:line`. **Diff:**
names, casing, types, optionality, status codes and error cases match the real other side, read at
its path; what could not be read is an unverifiable risk, never approved. **How:** judgement, against
the related project's source.

### `security` — warns

**Applies when** `entry-point`, `auth`, `personal-data`. **Plan:** every new or changed entry point
says who may call it (how the caller is authenticated, which permission is checked) and what input it
rejects; every piece of personal data is listed with where it is stored and for how long. **Diff:**
- the permission is checked where the entry point runs, not only hidden in the interface;
- input is validated where it enters, before it is used;
- queries and commands are built with parameters, never by joining input into them;
- text that came from a user is escaped where it is rendered;
- secrets and personal data stay out of logs, error reports, URLs and browser storage, beyond what
  the plan lists;
- no secret is written in code or committed configuration.

**How:** judgement.

### `accessibility` — warns

**Applies when** `ui`. Target: WCAG 2.2 AA. **Plan:** every new interactive element has its
accessible name and keyboard behaviour, and an existing component that already has them is reused
before one is built. **Diff:**
- every interactive element can be reached and operated with the keyboard alone, in visual order,
  with its focus visible;
- every control has an accessible name: a visible label, never only a placeholder or an icon;
- an informative image has a text alternative, a decorative one is hidden from assistive technology;
- a state or an error is never told by colour alone, and an error is announced and tied to its field;
- text and controls meet AA contrast, which holds when their colours come from the design system;
- a dialog takes the focus when it opens and gives it back when it closes.

**How:** judgement; an accessibility audit of the running app when the runtime validator is on.

### `performance` — warns

**Applies when** `entry-point`, `data`, `ui`. **Plan:** every list that grows with the data is
paginated or bounded at its source; a new query on a large table names the index it relies on.
**Diff:**
- no query or remote call inside a loop over a collection the data sizes;
- nothing fetches more than the consumer uses;
- no costly computation is repeated while its inputs have not changed (in a UI, on every render);
- nothing new waits on a remote call it could have started earlier or in parallel.

**How:** judgement.
