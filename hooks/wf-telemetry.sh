#!/bin/bash
#
# wf-telemetry — mechanical capture of the development cycle.
#
# Implements the hook layer described in docs/brainstorm-metrics-and-complexity.md §3.2.
# Appends events to ~/.claude/workflow/events.jsonl.
#
# Usage (from ~/.claude/settings.json):
#   wf-telemetry.sh prompt   < hook JSON   # UserPromptSubmit
#   wf-telemetry.sh tool     < hook JSON   # PostToolUse
#   wf-telemetry.sh stop     < hook JSON   # Stop
#   wf-telemetry.sh session-end < hook JSON  # SessionEnd
#
# INVIOLABLE PRINCIPLE: this script never blocks or breaks the user's flow.
# Any error is swallowed and it exits 0. Losing an event is acceptable;
# interrupting a work session is not.

WF_DIR="$HOME/.claude/workflow"
EVENTS="$WF_DIR/events.jsonl"
SESSIONS_DIR="$WF_DIR/sessions"

# Without jq there's no telemetry, but there's no noise either.
command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$SESSIONS_DIR" 2>/dev/null || exit 0

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

MODE="${1:-}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

jget() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

SESSION_ID="$(jget '.session_id')"
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"
CWD="$(jget '.cwd')"
[ -z "$CWD" ] && CWD="$PWD"

STATE_FILE="$SESSIONS_DIR/${SESSION_ID}.json"

repo_root() {
  local root
  root="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$root" ] && printf '%s' "$root" || printf '%s' "$CWD"
}

project_name() { basename "$(repo_root)"; }

# The project's active ticket (it may not exist yet).
active_ticket() {
  local f
  f="$(repo_root)/.claude/workflow/state.json"
  [ -f "$f" ] && jq -r '.activeTicket // empty' "$f" 2>/dev/null
}

# Increments the entry counter for a stage in the TICKET's state.json, not the
# session's — that way the count survives closing and reopening Claude Code.
# Prints the resulting counter (1 = first entry); empty if there's no ticket.
#
# It writes conservatively: it never overwrites a corrupt state.json nor drops
# fields the commands manage (stage, branch, notes, subtasks).
bump_ticket_stage() {
  local stage="$1" ticket dir f tmp
  ticket="$(active_ticket)"
  [ -z "$ticket" ] && return 0

  dir="$(repo_root)/.claude/workflow/$ticket"
  f="$dir/state.json"
  mkdir -p "$dir" 2>/dev/null || return 0
  [ -f "$f" ] || echo '{}' > "$f" 2>/dev/null
  jq -e . "$f" >/dev/null 2>&1 || return 0

  tmp="$(mktemp)" || return 0
  if jq --arg s "$stage" \
       '.iterations //= {} | .iterations[$s] = ((.iterations[$s] // 0) + 1)' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$f" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
    return 0
  fi

  jq -r --arg s "$stage" '.iterations[$s] // empty' "$f" 2>/dev/null
}

# Stage order — defines the leak distance (§2.2).
#
# mr-desc and retro are NOT part of the axis: they aren't stages where a defect
# originates or is detected (one describes the MR, the other closes the cycle).
# They map to 0 just like an unknown value, but explicitly, so that a 0 in the
# data isn't confused with "the stage vocabulary broke" — which is what happened
# when wf-refine wrote "refinement" instead of "refine".
stage_index() {
  case "$1" in
    refine)      echo 1 ;;
    analyze)     echo 2 ;;
    review-plan) echo 3 ;;
    implement)   echo 4 ;;
    validate)    echo 5 ;;
    test)        echo 6 ;;
    mr-review)   echo 7 ;;
    mr-desc)     echo 0 ;;  # off the axis, on purpose
    retro)       echo 0 ;;  # off the axis, on purpose
    *)           echo 0 ;;
  esac
}

# Appends an event. Arguments: stage, event, data (JSON), [subtask]
emit() {
  local stage="$1" event="$2" data="$3" subtask="${4:-}"
  local ticket
  [ -z "$data" ] && data='{}'
  ticket="$(active_ticket)"

  jq -cn \
    --arg ts "$(now_iso)" \
    --arg project "$(project_name)" \
    --arg ticket "$ticket" \
    --arg subtask "$subtask" \
    --arg stage "$stage" \
    --arg event "$event" \
    --argjson data "$data" \
    '{ts:$ts, project:$project,
      ticket:(if $ticket == "" then null else $ticket end),
      subtask:(if $subtask == "" then null else $subtask end),
      stage:$stage, event:$event, source:"hook", data:$data}' \
    >> "$EVENTS" 2>/dev/null
}

read_state() {
  [ -f "$STATE_FILE" ] && cat "$STATE_FILE" 2>/dev/null || echo '{}'
}

# Closes the active stage by emitting stage_end with its accumulated counters.
close_open_stage() {
  local st prev turns tools started elapsed
  st="$(read_state)"
  prev="$(printf '%s' "$st" | jq -r '.stage // empty')"
  [ -z "$prev" ] && return 0

  turns="$(printf '%s' "$st" | jq -r '.turns // 0')"
  tools="$(printf '%s' "$st" | jq -r '.tool_calls // 0')"
  started="$(printf '%s' "$st" | jq -r '.stage_start_epoch // 0')"
  elapsed=$(( $(date -u +%s) - started ))
  [ "$started" -eq 0 ] 2>/dev/null && elapsed=0

  emit "$prev" "stage_end" \
    "$(jq -cn --argjson t "$turns" --argjson c "$tools" --argjson d "$elapsed" \
        '{turns:$t, tool_calls:$c, duration_s:$d}')"
}

# ---------------------------------------------------------------------------
# UserPromptSubmit — detects /wf-* and opens a stage
# ---------------------------------------------------------------------------

handle_prompt() {
  local prompt cmd stage st seen n scope
  prompt="$(jget '.prompt')"

  # We only care about a workflow slash command at the start of the prompt.
  cmd="$(printf '%s' "$prompt" | sed -n 's|^[[:space:]]*/\(wf[a-z-]*\).*|\1|p' | head -1)"
  [ -z "$cmd" ] && exit 0

  case "$cmd" in
    wf-refine)      stage="refine" ;;
    wf-analyze)     stage="analyze" ;;
    wf-review-plan) stage="review-plan" ;;
    wf-implement)   stage="implement" ;;
    wf-validate)    stage="validate" ;;
    wf-test)        stage="test" ;;
    wf-mr-review)   stage="mr-review" ;;
    wf-mr-desc)     stage="mr-desc" ;;
    wf-retro)       stage="retro" ;;
    # /wf, /wf-init, /wf-jira and /wf-improve aren't measured stages of the cycle.
    *) exit 0 ;;
  esac

  st="$(read_state)"

  # Stage change: close the previous one before opening the new one.
  if [ "$(printf '%s' "$st" | jq -r '.stage // empty')" != "$stage" ]; then
    close_open_stage
  else
    # Re-invocation of the same command without having left the stage.
    st="$(printf '%s' "$st" | jq -c 'del(.stage)')"
  fi

  # Persistent count on the ticket. If there's no active ticket yet, it falls
  # back to a per-session count, which is lost when the session closes — hence
  # the `scope` field: it marks how trustworthy this number is when the data is
  # analyzed later.
  scope="ticket"
  n="$(bump_ticket_stage "$stage")"
  if [ -z "$n" ]; then
    scope="session"
    seen="$(printf '%s' "$st" | jq -c '.stages_seen // []')"
    n=$(( $(printf '%s' "$seen" | jq --arg s "$stage" \
            '[.[] | select(. == $s)] | length') + 1 ))
  fi

  if [ "$n" -gt 1 ] 2>/dev/null; then
    emit "$stage" "stage_reentry" \
      "$(jq -cn --argjson n "$n" --arg sc "$scope" '{iteration_n:$n, scope:$sc}')"
  else
    emit "$stage" "stage_start" "$(jq -cn --arg sc "$scope" '{scope:$sc}')"
  fi

  printf '%s' "$st" | jq -c \
    --arg stage "$stage" \
    --argjson epoch "$(date -u +%s)" \
    '. + {stage:$stage, stage_start_epoch:$epoch, turns:0, tool_calls:0,
          stages_seen:((.stages_seen // []) + [$stage])}' \
    > "$STATE_FILE" 2>/dev/null

  exit 0
}

# ---------------------------------------------------------------------------
# PostToolUse — counts tool calls and detects plan churn
# ---------------------------------------------------------------------------

handle_tool() {
  local st stage tool path
  st="$(read_state)"
  stage="$(printf '%s' "$st" | jq -r '.stage // empty')"
  [ -z "$stage" ] && exit 0

  printf '%s' "$st" | jq -c '.tool_calls = ((.tool_calls // 0) + 1)' \
    > "$STATE_FILE" 2>/dev/null

  # Plan churn (§2.3 #2): an edit to plan.md once the plan has been approved.
  tool="$(jget '.tool_name')"
  case "$tool" in
    Write|Edit|MultiEdit) ;;
    *) exit 0 ;;
  esac

  path="$(jget '.tool_input.file_path')"
  case "$path" in
    */plan.md) ;;
    *) exit 0 ;;
  esac

  # It only counts as churn if the plan already went through review-plan.
  [ "$(stage_index "$stage")" -ge 3 ] 2>/dev/null &&
    emit "$stage" "plan_edit" \
      "$(jq -cn --arg p "$path" '{path:$p, post_approval:true}')"

  exit 0
}

# ---------------------------------------------------------------------------
# Stop — one completed turn
# ---------------------------------------------------------------------------

handle_stop() {
  local st
  st="$(read_state)"
  [ -z "$(printf '%s' "$st" | jq -r '.stage // empty')" ] && exit 0
  printf '%s' "$st" | jq -c '.turns = ((.turns // 0) + 1)' \
    > "$STATE_FILE" 2>/dev/null
  exit 0
}

# ---------------------------------------------------------------------------
# SessionEnd — closes the stage that was left open
# ---------------------------------------------------------------------------

handle_session_end() {
  close_open_stage
  rm -f "$STATE_FILE" 2>/dev/null
  exit 0
}

case "$MODE" in
  prompt)      handle_prompt ;;
  tool)        handle_tool ;;
  stop)        handle_stop ;;
  session-end) handle_session_end ;;
esac

exit 0
