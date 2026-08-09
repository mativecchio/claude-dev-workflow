#!/bin/bash
#
# wf-lib — funciones compartidas del workflow.
#
# Reemplaza la prosa repetida en los comandos wf-*.md. El "Paso 0 — Identificar
# ticket activo" estaba copiado literal en 8 archivos: cambiar algo ahí exigía
# tocar los 8 y acordarse de todos.
#
# Uso desde un comando:
#   source ~/.claude/scripts/wf-lib.sh
#   TICKET="$(wf_ticket)" || exit 1
#   DIR="$(wf_dir)"
#
# PRINCIPIO: degradar, no romper. Una función que no puede resolver algo
# devuelve vacío y sale != 0; nunca deja el estado a medias.

WF_STAGES="refine analyze review-plan implement validate test mr-desc mr-review retro"

# ---------------------------------------------------------------------------
# Contexto del proyecto
# ---------------------------------------------------------------------------

wf_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

wf_workflow_root() { printf '%s/.claude/workflow' "$(wf_repo_root)"; }

# Ticket activo. Vacío + exit 1 si no hay ninguno: el caller decide si
# preguntarle al usuario o seguir sin ticket.
wf_ticket() {
  local f t
  f="$(wf_workflow_root)/state.json"
  [ -f "$f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  t="$(jq -r '.activeTicket // empty' "$f" 2>/dev/null)"
  [ -n "$t" ] || return 1
  printf '%s' "$t"
}

# Directorio del ticket activo, creado si no existe.
wf_dir() {
  local t d
  t="$(wf_ticket)" || return 1
  d="$(wf_workflow_root)/$t"
  mkdir -p "$d" 2>/dev/null || return 1
  printf '%s' "$d"
}

# Lee una clave del config del proyecto. Uso: wf_config '.base_branch'
wf_config() {
  local f
  f="$(wf_workflow_root)/config.json"
  [ -f "$f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -r "${1:-.} // empty" "$f" 2>/dev/null
}

# Rama base del proyecto. Prioridad: config > rama existente > main.
# Antes esto era prosa ("develop/main/master, según el proyecto") que el modelo
# resolvía de nuevo en cada corrida, y wf-refine directamente hardcodeaba develop.
wf_base() {
  local b
  b="$(wf_config '.base_branch')"
  if [ -n "$b" ]; then printf '%s' "$b"; return 0; fi
  for b in develop main master; do
    if git show-ref --verify --quiet "refs/heads/$b" 2>/dev/null ||
       git show-ref --verify --quiet "refs/remotes/origin/$b" 2>/dev/null; then
      printf '%s' "$b"; return 0
    fi
  done
  printf 'main'
}

# ---------------------------------------------------------------------------
# Estado del ticket
# ---------------------------------------------------------------------------

wf_state() {
  local d
  d="$(wf_dir)" || return 1
  [ -f "$d/state.json" ] || return 1
  jq -r "${1:-.} // empty" "$d/state.json" 2>/dev/null
}

# Escribe una clave preservando el resto del archivo.
# Uso: wf_set_state approved true   |   wf_set_state branch '"MA-123-fix"'
wf_set_state() {
  local d f tmp key="$1" val="$2"
  [ -n "$key" ] || return 1
  d="$(wf_dir)" || return 1
  f="$d/state.json"
  [ -f "$f" ] || echo '{}' > "$f"
  jq -e . "$f" >/dev/null 2>&1 || return 1   # nunca pisar un state corrupto
  tmp="$(mktemp)" || return 1
  if jq --arg k "$key" --argjson v "$val" '.[$k] = $v' "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$f"; return 0
  fi
  rm -f "$tmp"; return 1
}

# Registra la entrada a una etapa: escribe stage y appendea a completed,
# preservando branch, notes, iterations, subtasks y approved.
#
# Esto era una instrucción en prosa que solo cumplían wf-refine y /wf (H11),
# y con un vocabulario que no coincidía con el de los consumidores (H12).
# Acá el vocabulario se valida: un stage inválido falla ruidosamente en vez
# de escribirse y romper el conteo en silencio.
wf_enter_stage() {
  local stage="$1" d f tmp
  [ -n "$stage" ] || return 1

  case " $WF_STAGES " in
    *" $stage "*) ;;
    *) echo "wf-lib: stage inválido '$stage' (válidos: $WF_STAGES)" >&2; return 1 ;;
  esac

  d="$(wf_dir)" || return 1
  f="$d/state.json"
  [ -f "$f" ] || echo '{}' > "$f"
  jq -e . "$f" >/dev/null 2>&1 || return 1

  tmp="$(mktemp)" || return 1
  if jq --arg s "$stage" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .stage = $s
      | .completed = ((.completed // []) + [$s] | unique)
      | .started_at //= $ts
      | .updated_at = $ts
     ' "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$f"
    printf '%s' "$stage"
    return 0
  fi
  rm -f "$tmp"; return 1
}

# ---------------------------------------------------------------------------
# CLI: permite usarlo sin sourcear — `wf-lib.sh ticket`, `wf-lib.sh base`, etc.
# ---------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    ticket)      wf_ticket ;;
    dir)         wf_dir ;;
    base)        wf_base ;;
    config)      wf_config "${2:-.}" ;;
    state)       wf_state "${2:-.}" ;;
    set-state)   wf_set_state "$2" "$3" ;;
    enter-stage) wf_enter_stage "$2" ;;
    context)
      # Todo lo que un comando necesita al arrancar, de una.
      t="$(wf_ticket)" || { echo "❌ No hay ticket activo en $(wf_workflow_root)/state.json" >&2; exit 1; }
      printf 'ticket=%s\ndir=%s\nbase=%s\nstage=%s\nbranch=%s\n' \
        "$t" "$(wf_dir)" "$(wf_base)" "$(wf_state '.stage')" "$(git branch --show-current 2>/dev/null)"
      ;;
    *)
      echo "uso: wf-lib.sh {ticket|dir|base|config <path>|state <path>|set-state <k> <v>|enter-stage <s>|context}" >&2
      exit 1 ;;
  esac
fi
