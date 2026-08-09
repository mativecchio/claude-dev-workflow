#!/bin/bash
#
# wf-gate — el checkpoint de review-plan, como mecanismo.
#
# wf-review-plan.md dice "NUNCA pasar a implementación sin respuesta explícita".
# Eso es una instrucción: se cumple casi siempre. Este hook lo hace cumplir.
#
# ⚠️  ESTE ES EL ÚNICO HOOK DEL SISTEMA QUE PUEDE BLOQUEAR.
# wf-telemetry.sh tiene como principio inviolable no interrumpir nunca. Acá
# interrumpir ES la función. Por eso el radio de explosión está acotado:
#
#   1. Los hooks se registran en ~/.claude/settings.json → corren en TODOS los
#      proyectos. Sin .claude/workflow/state.json, este sale en silencio.
#   2. Fail-open: cualquier error (sin jq, JSON corrupto, sin git) sale 0.
#      El único camino que bloquea es la condición evaluada con éxito.
#      Bloquear por un bug es peor que no bloquear.
#   3. Arranca en modo observe: registra qué HABRÍA bloqueado, sin impedir nada.
#
# Modos (WF_GATE):
#   observe   (default) registra en events.jsonl, no bloquea
#   enforce   bloquea de verdad
#   off       no hace nada
#
# Para activar el bloqueo, después de revisar los eventos gate_would_block:
#   export WF_GATE=enforce     (o ponerlo en env de ~/.claude/settings.json)

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
[ -f "$STATE" ] || exit 0                       # proyecto sin workflow: no es asunto nuestro

TICKET="$(jq -r '.activeTicket // empty' "$STATE" 2>/dev/null)"
[ -n "$TICKET" ] || exit 0

TSTATE="$ROOT/.claude/workflow/$TICKET/state.json"
[ -f "$TSTATE" ] || exit 0
jq -e . "$TSTATE" >/dev/null 2>&1 || exit 0     # state corrupto: fail-open

STAGE="$(jq -r '.stage // empty' "$TSTATE" 2>/dev/null)"
[ "$STAGE" = "review-plan" ] || exit 0          # solo esta etapa bloquea

APPROVED="$(jq -r '.approved // false' "$TSTATE" 2>/dev/null)"
[ "$APPROVED" = "true" ] && exit 0              # el usuario ya dijo que sí

# Artefactos del propio workflow y documentación: siempre permitidos. Ajustar
# el plan durante su review es parte del trabajo de esta etapa, no una fuga.
FILE="$(jget '.tool_input.file_path')"
case "$FILE" in
  */.claude/workflow/*|*/.claude/*|*/docs/*|*.md) exit 0 ;;
esac

REL="${FILE#"$ROOT"/}"

# Registrar el evento en la misma telemetría que el resto del sistema.
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
⛔ Gate de review-plan: $TICKET todavía no está aprobado.

Intentaste modificar: $REL

El plan está en review y no hubo aprobación explícita. Terminá
/wf-review-plan y confirmá, o si necesitás tocar código para verificar
una hipótesis del review, corré con WF_GATE=off.
EOF
exit 2
