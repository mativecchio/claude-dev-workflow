#!/bin/bash
#
# wf-telemetry — captura mecánica del ciclo de desarrollo.
#
# Implementa la capa de hooks descrita en docs/brainstorm-metricas-y-complejidad.md §3.2.
# Appendea eventos a ~/.claude/workflow/events.jsonl.
#
# Uso (desde ~/.claude/settings.json):
#   wf-telemetry.sh prompt   < hook JSON   # UserPromptSubmit
#   wf-telemetry.sh tool     < hook JSON   # PostToolUse
#   wf-telemetry.sh stop     < hook JSON   # Stop
#   wf-telemetry.sh session-end < hook JSON  # SessionEnd
#
# PRINCIPIO INVIOLABLE: este script nunca bloquea ni rompe el flujo del usuario.
# Cualquier error se traga y sale 0. Perder un evento es aceptable;
# interrumpir una sesión de trabajo no lo es.

WF_DIR="$HOME/.claude/workflow"
EVENTS="$WF_DIR/events.jsonl"
SESSIONS_DIR="$WF_DIR/sessions"

# Sin jq no hay telemetría, pero tampoco hay ruido.
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

# Nombre de proyecto: raíz del repo git si existe, si no el basename del cwd.
project_name() {
  local root
  root="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$root" ] && basename "$root" || basename "$CWD"
}

# Ticket activo del proyecto (puede no existir todavía).
active_ticket() {
  local root f
  root="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"
  [ -z "$root" ] && root="$CWD"
  f="$root/.claude/workflow/state.json"
  [ -f "$f" ] && jq -r '.activeTicket // empty' "$f" 2>/dev/null
}

# Orden de etapas — define la distancia de fuga (§2.2).
stage_index() {
  case "$1" in
    refine)      echo 1 ;;
    analyze)     echo 2 ;;
    review-plan) echo 3 ;;
    implement)   echo 4 ;;
    validate)    echo 5 ;;
    test)        echo 6 ;;
    mr-review)   echo 7 ;;
    *)           echo 0 ;;
  esac
}

# Appendea un evento. Argumentos: stage, event, data (JSON), [subtask]
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

# Cierra la etapa activa emitiendo stage_end con sus contadores acumulados.
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
# UserPromptSubmit — detecta /wf-* y abre etapa
# ---------------------------------------------------------------------------

handle_prompt() {
  local prompt cmd stage st seen n
  prompt="$(jget '.prompt')"

  # Sólo nos interesa un slash command de workflow al inicio del prompt.
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
    # /wf, /wf-init, /wf-jira, /wf-improve no son etapas medidas del ciclo.
    *) exit 0 ;;
  esac

  st="$(read_state)"

  # Cambio de etapa: cerrar la anterior antes de abrir la nueva.
  if [ "$(printf '%s' "$st" | jq -r '.stage // empty')" != "$stage" ]; then
    close_open_stage
  else
    # Reinvocación del mismo comando sin haber salido de la etapa.
    st="$(printf '%s' "$st" | jq -c 'del(.stage)')"
  fi

  seen="$(printf '%s' "$st" | jq -c '.stages_seen // []')"
  n="$(printf '%s' "$seen" | jq --arg s "$stage" '[.[] | select(. == $s)] | length')"

  if [ "$n" -gt 0 ]; then
    emit "$stage" "stage_reentry" \
      "$(jq -cn --argjson n "$((n + 1))" '{iteration_n:$n}')"
  else
    emit "$stage" "stage_start" '{}'
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
# PostToolUse — cuenta tool calls y detecta plan churn
# ---------------------------------------------------------------------------

handle_tool() {
  local st stage tool path
  st="$(read_state)"
  stage="$(printf '%s' "$st" | jq -r '.stage // empty')"
  [ -z "$stage" ] && exit 0

  printf '%s' "$st" | jq -c '.tool_calls = ((.tool_calls // 0) + 1)' \
    > "$STATE_FILE" 2>/dev/null

  # Plan churn (§2.3 #2): edición de plan.md una vez aprobado el plan.
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

  # Sólo cuenta como churn si el plan ya pasó por review-plan.
  [ "$(stage_index "$stage")" -ge 3 ] 2>/dev/null &&
    emit "$stage" "plan_edit" \
      "$(jq -cn --arg p "$path" '{path:$p, post_approval:true}')"

  exit 0
}

# ---------------------------------------------------------------------------
# Stop — un turno completado
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
# SessionEnd — cierra la etapa que quedó abierta
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
