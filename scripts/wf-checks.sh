#!/bin/bash
#
# wf-checks — corre los gates determinísticos del proyecto.
#
# El DoD vivía como una lista de strings en prosa que un agente evaluaba con
# criterio ("¿el linter pasa?", "¿hay console.log?"). Eso lo contesta un
# comando en segundos, sin falsos positivos y sin gastar un agente.
#
# Config del proyecto (.claude/workflow/config.json):
#   "checks": { "lint": "npm run lint", "types": "tsc --noEmit", "test": "npm test" }
#
# Uso:
#   wf-checks.sh            corre todos, salida legible
#   wf-checks.sh --json     salida JSON para que la consuma un comando
#   wf-checks.sh lint       corre uno solo
#
# Exit: 0 si todos pasan, 1 si alguno falla, 2 si no hay checks configurados.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$DIR/wf-lib.sh" ] && . "$DIR/wf-lib.sh"

command -v jq >/dev/null 2>&1 || { echo "wf-checks: hace falta jq" >&2; exit 2; }

CONFIG="$(wf_workflow_root)/config.json"
[ -f "$CONFIG" ] || { echo "wf-checks: no hay config en $CONFIG" >&2; exit 2; }

JSON=0; ONLY=""
case "${1:-}" in
  --json) JSON=1 ;;
  "")     ;;
  *)      ONLY="$1" ;;
esac

NAMES="$(jq -r '.checks // {} | keys[]' "$CONFIG" 2>/dev/null)"
if [ -z "$NAMES" ]; then
  if [ "$JSON" -eq 1 ]; then
    echo '{"configured":false,"results":[],"passed":null}'
  else
    echo "⚠️  Este proyecto no tiene checks configurados."
    echo "   Agregarlos en $CONFIG:"
    echo '     "checks": { "lint": "...", "types": "...", "test": "..." }'
    echo "   Sin esto, la validación depende del criterio de un agente para"
    echo "   cosas que un comando responde de forma exacta."
  fi
  exit 2
fi

RESULTS="[]"; FAILED=0
[ "$JSON" -eq 1 ] || echo "🔍 Checks determinísticos"

for name in $NAMES; do
  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue
  cmd="$(jq -r --arg n "$name" '.checks[$n]' "$CONFIG")"
  [ -n "$cmd" ] && [ "$cmd" != "null" ] || continue

  out="$(eval "$cmd" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && FAILED=1

  # Solo la cola del output: un fallo de tests puede tirar miles de líneas y
  # el consumidor de esto es un prompt.
  tail_out="$(printf '%s' "$out" | tail -30)"
  RESULTS="$(jq -c --arg n "$name" --arg c "$cmd" --argjson rc "$rc" --arg o "$tail_out" \
    '. + [{name:$n, command:$c, exit_code:$rc, passed:($rc == 0), output:$o}]' <<< "$RESULTS")"

  if [ "$JSON" -eq 0 ]; then
    if [ "$rc" -eq 0 ]; then
      echo "  ✅ $name"
    else
      echo "  ❌ $name (exit $rc)"
      printf '%s\n' "$tail_out" | sed 's/^/       /'
    fi
  fi
done

if [ "$JSON" -eq 1 ]; then
  jq -cn --argjson r "$RESULTS" --argjson f "$FAILED" \
    '{configured:true, results:$r, passed:($f == 0)}'
else
  echo ""
  [ "$FAILED" -eq 0 ] && echo "✅ Todos los checks pasan" || echo "❌ Hay checks fallando — corregir antes de la validación semántica"
fi

exit "$FAILED"
