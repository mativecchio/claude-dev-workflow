#!/bin/bash
#
# wf-gate — the review-plan checkpoint, as a mechanism.
#
# wf-review-plan.md says "NEVER move to implementation without an explicit
# answer". That's an instruction: it's honored almost always. This hook enforces it.
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
[ "$MODE" = "off" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"; [ -z "$INPUT" ] && exit 0

jget() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

TOOL="$(jget '.tool_name')"
case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

CWD="$(jget '.cwd')"; [ -n "$CWD" ] || CWD="$PWD"
ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || ROOT="$CWD"
[ -n "$ROOT" ] || exit 0

STATE="$ROOT/.claude/workflow/state.json"
[ -f "$STATE" ] || exit 0                       # project without a workflow: none of our business

TICKET="$(jq -r '.activeTicket // empty' "$STATE" 2>/dev/null)"
[ -n "$TICKET" ] || exit 0

TSTATE="$ROOT/.claude/workflow/$TICKET/state.json"
[ -f "$TSTATE" ] || exit 0
jq -e . "$TSTATE" >/dev/null 2>&1 || exit 0     # corrupt state: fail-open

STAGE="$(jq -r '.stage // empty' "$TSTATE" 2>/dev/null)"
[ "$STAGE" = "review-plan" ] || exit 0          # only this stage blocks

APPROVED="$(jq -r '.approved // false' "$TSTATE" 2>/dev/null)"
[ "$APPROVED" = "true" ] && exit 0              # the user already said yes

# The workflow's own artifacts and documentation: always allowed. Adjusting the
# plan while reviewing it is part of this stage's work, not a leak.
FILE="$(jget '.tool_input.file_path')"
case "$FILE" in
  */.claude/workflow/*|*/.claude/*|*/docs/*|*.md) exit 0 ;;
esac

REL="${FILE#"$ROOT"/}"

# Record the event in the same telemetry stream as the rest of the system.
EVENTS="$HOME/.claude/workflow/events.jsonl"
mkdir -p "$(dirname "$EVENTS")" 2>/dev/null
jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg project "$(basename "$ROOT")" \
  --arg ticket "$TICKET" \
  --arg file "$REL" \
  --arg tool "$TOOL" \
  --arg mode "$MODE" \
  '{ts:$ts, project:$project, ticket:$ticket, subtask:null,
    stage:"review-plan", source:"hook",
    event:(if $mode == "enforce" then "gate_blocked" else "gate_would_block" end),
    data:{file:$file, tool:$tool, mode:$mode}}' >> "$EVENTS" 2>/dev/null

[ "$MODE" != "enforce" ] && exit 0

cat >&2 << EOF
⛔ review-plan gate: $TICKET is not approved yet.

You tried to modify: $REL

The plan is under review and there was no explicit approval. Finish
/wf-review-plan and confirm, or if you need to touch code to verify a
hypothesis from the review, run with WF_GATE=off.
EOF
exit 2
