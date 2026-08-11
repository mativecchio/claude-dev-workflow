#!/bin/bash
#
# wf-event — emits semantic events to events.jsonl.
#
# The hook layer (wf-telemetry.sh) captures the mechanical skeleton: which stage
# started, how many turns, how many tool calls. It cannot know *why* a stage was
# re-entered, what the defect was, or where it originated. That is what the wf-*
# commands know, and this is how they record it.
#
# WHY A SCRIPT AND NOT A JSON LINE IN THE PROMPT:
# the obvious alternative is telling the command "append this object to
# events.jsonl". That reintroduces exactly what this migration removes — a rule
# living as prose. Worse, it fails silently: one malformed line corrupts the
# parse for every later query, and nothing surfaces it until wf-stats.sh returns
# nonsense. Here the line is built with jq or not written at all.
#
# Common fields (ts, project, ticket, stage, source) are filled in from the
# workflow state, so a caller cannot get them wrong or forget them.
#
# Usage:
#   wf-event.sh finding --category logic --severity high \
#       --stage_origin analyze --detected_by gate --summary "guard missing"
#   wf-event.sh finding_decision --finding_ref f3 --decision tech-debt
#   wf-event.sh complexity_estimate --raw_score 21 --points 8 --split_recommended true
#
# Everything after the event name lands in `data`. Values that look like a
# number, a boolean, null, or JSON are stored as such; the rest as strings.
#
# Exit: 0 written, 1 usage error, 2 no context (no ticket). Never writes a
# partial or malformed line.

set -uo pipefail

LIB="$(dirname "${BASH_SOURCE[0]}")/wf-lib.sh"
[ -f "$LIB" ] || LIB="$HOME/.claude/scripts/wf-lib.sh"
# shellcheck source=/dev/null
. "$LIB" 2>/dev/null || { echo "wf-event: cannot find wf-lib.sh" >&2; exit 1; }

EVENTS="$HOME/.claude/workflow/events.jsonl"

# Vocabulary. An unknown event is a caller bug: reject it loudly instead of
# writing a row that no query will ever match.
WF_EVENTS="complexity_estimate finding finding_decision scope_drift size_check
size_exceeded split_suggested split_applied mr_opened ticket_closed
ticket_abandoned contract_verified implement_started"

# Required data keys per event, so a half-filled event fails at the call site
# rather than showing up as a hole in the stats weeks later.
req_for() {
  case "$1" in
    finding)             echo "category severity stage_origin detected_by summary" ;;
    finding_decision)    echo "finding_ref decision" ;;
    complexity_estimate) echo "raw_score points" ;;
    mr_opened)           echo "weight_prod" ;;
    ticket_closed)       echo "iterations_total" ;;
    size_check)          echo "weight_prod" ;;
    implement_started)   echo "model_used" ;;
    *)                   echo "" ;;
  esac
}

usage() {
  cat >&2 <<EOF
usage: wf-event.sh <event> [--key value ...]

events: $(echo $WF_EVENTS)

  finding              --category --severity --stage_origin --detected_by --summary
  finding_decision     --finding_ref --decision (implement|ignore|tech-debt)
  complexity_estimate  --raw_score --points [--split_recommended]
  mr_opened            --weight_prod [--weight_tests --branch --target]
  ticket_closed        --iterations_total [--complexity_actual]
  implement_started    --model_used [--model_recommended]

overrides: --_stage --_ticket --_subtask
EOF
  exit 1
}

EVENT="${1:-}"; [ -n "$EVENT" ] || usage
shift
case " $(echo $WF_EVENTS) " in
  *" $EVENT "*) ;;
  *) echo "wf-event: unknown event '$EVENT'" >&2; usage ;;
esac

command -v jq >/dev/null 2>&1 || { echo "wf-event: jq not available" >&2; exit 1; }

# --- parse args into a jq-built data object ------------------------------------
DATA='{}'
O_STAGE=""; O_TICKET=""; O_SUBTASK=""
KEYS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --_stage)   O_STAGE="${2:-}"; shift 2 ;;
    --_ticket)  O_TICKET="${2:-}"; shift 2 ;;
    --_subtask) O_SUBTASK="${2:-}"; shift 2 ;;
    --*)
      k="${1#--}"; v="${2:-}"
      [ -n "$k" ] || usage
      # Typed if it parses as JSON scalar/array/object, string otherwise. This is
      # what keeps `--points 8` a number and `--summary "8 files"` a string.
      if printf '%s' "$v" | jq -e . >/dev/null 2>&1; then
        DATA="$(printf '%s' "$DATA" | jq --arg k "$k" --argjson v "$v" '.[$k]=$v' 2>/dev/null)" \
          || DATA="$(printf '%s' "$DATA" | jq --arg k "$k" --arg v "$v" '.[$k]=$v')"
      else
        DATA="$(printf '%s' "$DATA" | jq --arg k "$k" --arg v "$v" '.[$k]=$v')"
      fi
      KEYS="$KEYS $k"
      shift 2 ;;
    *) echo "wf-event: stray argument '$1'" >&2; usage ;;
  esac
done

# --- required keys -------------------------------------------------------------
MISSING=""
for r in $(req_for "$EVENT"); do
  case " $KEYS " in *" $r "*) ;; *) MISSING="$MISSING --$r" ;; esac
done
if [ -n "$MISSING" ]; then
  echo "wf-event: missing required fields for '$EVENT':$MISSING" >&2
  exit 1
fi

# --- context -------------------------------------------------------------------
TICKET="$O_TICKET"; [ -n "$TICKET" ] || TICKET="$(wf_ticket 2>/dev/null)"
if [ -z "$TICKET" ]; then
  echo "wf-event: no active ticket — the event is not recorded" >&2
  exit 2
fi
STAGE="$O_STAGE"; [ -n "$STAGE" ] || STAGE="$(wf_state '.stage' 2>/dev/null)"
PROJECT="$(basename "$(wf_repo_root)")"

# --- write ---------------------------------------------------------------------
mkdir -p "$(dirname "$EVENTS")" 2>/dev/null

LINE="$(jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg project "$PROJECT" \
  --arg ticket "$TICKET" \
  --arg subtask "$O_SUBTASK" \
  --arg stage "$STAGE" \
  --arg event "$EVENT" \
  --argjson data "$DATA" \
  '{ts:$ts, project:$project, ticket:$ticket,
    subtask:(if $subtask == "" then null else $subtask end),
    stage:(if $stage == "" then null else $stage end),
    event:$event, source:"command", data:$data}' 2>/dev/null)"

# Only append if jq produced a line that parses. A corrupt events.jsonl is worse
# than a lost event: it breaks every query, not just this row.
if [ -z "$LINE" ] || ! printf '%s' "$LINE" | jq -e . >/dev/null 2>&1; then
  echo "wf-event: could not build the event; nothing was written" >&2
  exit 1
fi

printf '%s\n' "$LINE" >> "$EVENTS" || { echo "wf-event: could not write $EVENTS" >&2; exit 1; }
printf '✓ %s recorded (%s/%s)\n' "$EVENT" "$TICKET" "${STAGE:-no-stage}"
