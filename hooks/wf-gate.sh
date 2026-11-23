#!/bin/bash
#
# wf-gate — the plan checkpoints, as a mechanism.
#
# wf-review-plan.md says "NEVER move to implementation without an explicit
# answer". That's an instruction: it's honored almost always. This hook enforces it.
#
# It holds a second one: during `implement`, code is not written for a plan that
# lists files but never decided what each one is responsible for (the
# Responsibilities section of /wf-analyze, guides/responsibilities.md). Without
# it, where each function goes is decided while typing, which is how a 526-line
# util and a 21-input hook reached review on booking-center-app !505 and !507.
#
# ⚠️  THIS IS THE ONLY HOOK IN THE SYSTEM THAT CAN BLOCK.
# wf-telemetry.sh holds as an inviolable principle that it never interrupts. Here
# interrupting IS the function. That's why the blast radius is bounded:
#
#   1. Hooks are registered in ~/.claude/settings.json → they run in EVERY
#      project. Without .claude/workflow/state.json, this one exits silently.
#   2. Fail-open: any error (no jq, corrupt JSON, no git) exits 0.
#      The only blocking path is the condition evaluated successfully.
#      Blocking because of a bug is worse than not blocking.
#   3. It starts in observe mode: it records what it WOULD have blocked, without
#      preventing anything.
#
# Modes (WF_GATE):
#   observe   (default) records to events.jsonl, doesn't block
#   enforce   really blocks
#   off       does nothing
#
# To enable blocking, after reviewing the gate_would_block events:
#   export WF_GATE=enforce     (or put it in the env of ~/.claude/settings.json)

MODE="${WF_GATE:-observe}"
[ "$MODE" = "off" ] && [ "${WF_SCOPE:-ask}" = "off" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"; [ -z "$INPUT" ] && exit 0

jget() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

TOOL="$(jget '.tool_name')"
case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

CWD="$(jget '.cwd')"; [ -n "$CWD" ] || CWD="$PWD"
FILE="$(jget '.tool_input.file_path // .tool_input.notebook_path')"

# Resolve the ticket from the checkout the FILE is in, not the session's: a
# session can edit another worktree, and that worktree's branch says which
# ticket the edit belongs to.
HERE="$CWD"
if [ -n "$FILE" ]; then
  d="$(dirname "$FILE")"
  while [ -n "$d" ] && [ "$d" != "/" ] && [ ! -d "$d" ]; do d="$(dirname "$d")"; done
  git -C "$d" rev-parse --show-toplevel >/dev/null 2>&1 && HERE="$d"
fi
cd "$HERE" 2>/dev/null || exit 0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

LIB="$(dirname "$0")/../scripts/wf-lib.sh"
[ -f "$LIB" ] || exit 0
# shellcheck source=../scripts/wf-lib.sh
. "$LIB" || exit 0

WROOT="$(wf_workflow_root)"
[ -f "$WROOT/state.json" ] || [ -f "$WROOT/config.json" ] || exit 0   # project without a workflow

TICKET="$(wf_ticket 2>/dev/null)" || exit 0
[ -n "$TICKET" ] || exit 0
SOURCE="$(wf_ticket_source 2>/dev/null)"
TDIR="$(wf_tickets_root)/$TICKET"

TSTATE="$TDIR/state.json"
[ -f "$TSTATE" ] || exit 0
jq -e . "$TSTATE" >/dev/null 2>&1 || exit 0     # corrupt state: fail-open

STAGE="$(jq -r '.stage // empty' "$TSTATE" 2>/dev/null)"
PLAN="$TDIR/plan.md"
REL="${FILE#"$ROOT"/}"

record() {  # record <event> <reason> [extra-json]
  local events="$HOME/.claude/workflow/events.jsonl"
  mkdir -p "$(dirname "$events")" 2>/dev/null
  jq -cn \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg project "$(basename "$(wf_main_root)")" \
    --arg ticket "$TICKET" --arg file "$REL" --arg tool "$TOOL" \
    --arg mode "$2" --arg stage "$STAGE" --arg event "$1" --arg reason "$3" \
    '{ts:$ts, project:$project, ticket:$ticket, subtask:null,
      stage:$stage, source:"hook", event:$event,
      data:{file:$file, tool:$tool, mode:$mode, reason:$reason}}' >> "$events" 2>/dev/null
}

# ── Scope: an edit outside the files the ticket's spec lists ─────────────────
# Two specs in one session are easy to mix up: the request lands in whatever
# ticket is open. When the spec has a file table and this file is not in it,
# ask the user instead of writing (WF_SCOPE=ask, the default), only record it
# (observe), or do nothing (off). It asks, it never blocks: a spec's file list
# can be incomplete, and the user's yes is the answer.
SCOPE_MODE="${WF_SCOPE:-ask}"
if [ "$SCOPE_MODE" != "off" ] && [ -n "$FILE" ]; then
  case "$FILE" in
    */.claude/*) ;;
    *)
      if ! wf_scope_check "$FILE" >/dev/null 2>&1; then
        record "scope_outside" "$SCOPE_MODE" "outside-spec"
        if [ "$SCOPE_MODE" = "ask" ]; then
          why="$REL is not in the files of $TICKET's spec ($TDIR)"
          [ "$SOURCE" = "pointer" ] && why="$why; and $TICKET was taken from the activeTicket pointer, not from the branch"
          jq -cn --arg r "$why. Is this edit part of $TICKET? If it belongs to another ticket, stop and switch to that ticket's worktree." \
            '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"ask", permissionDecisionReason:$r}}'
          exit 0
        fi
      fi ;;
  esac
fi

# Table rows of a `## <heading>` section of the plan, header row included and
# separator rows left out: 2 or more means the table has at least one entry.
table_rows() {
  awk -v h="## $1" '
    index($0, h) == 1 { s = 1; next }
    /^## /            { s = 0 }
    s && /^\|/ && $0 !~ /^\|[ :|-]+\|[ ]*$/ { n++ }
    END { print n + 0 }' "$PLAN" 2>/dev/null || echo 0
}

REASON=""
case "$STAGE" in
  review-plan)
    APPROVED="$(jq -r '.approved // false' "$TSTATE" 2>/dev/null)"
    [ "$APPROVED" = "true" ] && exit 0          # the user already said yes
    REASON="unapproved" ;;
  implement)
    [ -f "$PLAN" ] || exit 0
    [ "$(table_rows 'Files to modify/create')" -ge 2 ] || exit 0   # nothing planned to place
    [ "$(table_rows 'Responsibilities')" -ge 2 ] && exit 0         # placed: nothing to stop
    REASON="no-responsibilities" ;;
  *) exit 0 ;;                                  # only these two stages block
esac

[ "$MODE" = "off" ] && exit 0                    # WF_GATE=off silences the stage gate only

# The workflow's own artifacts and documentation: always allowed. Adjusting the
# plan while reviewing it is part of this stage's work, not a leak.
case "$FILE" in
  */.claude/workflow/*|*/.claude/*|*/docs/*|*.md) exit 0 ;;
esac

record "$(if [ "$MODE" = "enforce" ]; then echo gate_blocked; else echo gate_would_block; fi)" "$MODE" "$REASON"

[ "$MODE" != "enforce" ] && exit 0

if [ "$REASON" = "unapproved" ]; then
cat >&2 << EOF
⛔ review-plan gate: $TICKET is not approved yet.

You tried to modify: $REL

The plan is under review and there was no explicit approval. Finish
/wf-review-plan and confirm, or if you need to touch code to verify a
hypothesis from the review, run with WF_GATE=off.
EOF
else
cat >&2 << EOF
⛔ responsibilities gate: the plan of $TICKET lists files to change but has no
Responsibilities section.

You tried to modify: $REL

Nobody decided what each file is responsible for or where each new function
goes (guides/responsibilities.md). Stop, tell the user, and propose the
section for plan.md; once the user agrees it is written, the code can follow.
A plan made before this check existed can be let through with WF_GATE=off.
EOF
fi
exit 2
