#!/bin/bash
#
# wf-probe — sonda temporal para resolver H1 (docs/plan-harness-migration.md).
#
# PREGUNTA QUE RESPONDE: cuando el ruteo de una etapa ocurre vía `/wf` en vez de
# tipear `/wf-analyze`, ¿qué ve un hook? El hook de telemetría solo matchea el
# comando tipeado en UserPromptSubmit, así que hoy todo el camino del
# orquestador es invisible y events.jsonl queda vacío.
#
# Había tres candidatos y NINGUNO estaba verificado:
#   (a) que /wf escriba stage antes de rutear   → depende del modelo
#   (b) PreToolUse sobre Read de wf-*.md        → depende del modelo
#   (c) PostToolUse con tool_name "Skill"       → mecánico, si es que ocurre así
#
# Esta sonda vuelca el JSON crudo para decidir con un dato en vez de una apuesta.
# NO bloquea, NO modifica estado, solo escribe un archivo.
#
# Uso:
#   ./scripts/wf-probe.sh --install    registra la sonda en ~/.claude/settings.json
#   ./scripts/wf-probe.sh --remove     la desregistra (y deja el log)
#   ./scripts/wf-probe.sh --report     resume qué capturó
#   ./scripts/wf-probe.sh <evento>     modo hook (lo invoca Claude Code)

PROBE_LOG="$HOME/.claude/workflow/probe.jsonl"
SETTINGS="$HOME/.claude/settings.json"
SELF="$HOME/.claude/hooks/wf-probe.sh"

case "${1:-}" in
  --install)
    command -v jq >/dev/null 2>&1 || { echo "❌ Hace falta jq"; exit 1; }
    mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/workflow"
    cp "$0" "$SELF" 2>/dev/null; chmod +x "$SELF"
    [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    jq -e . "$SETTINGS" >/dev/null 2>&1 || { echo "❌ settings.json inválido"; exit 1; }
    TMP="$(mktemp)"
    jq --arg h "$SELF" '
      def strip:
        map(.hooks |= map(select((.command // "") | contains("wf-probe.sh") | not)))
        | map(select((.hooks | length) > 0));
      def add($m): . + [{hooks: [{type: "command", command: ($h + " " + $m)}]}];
      .hooks                    //= {}
      | .hooks.UserPromptSubmit //= [] | .hooks.UserPromptSubmit |= (strip | add("prompt"))
      | .hooks.PreToolUse       //= [] | .hooks.PreToolUse       |= (strip | add("pre-tool"))
      | .hooks.PostToolUse      //= [] | .hooks.PostToolUse      |= (strip | add("post-tool"))
    ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
    : > "$PROBE_LOG"
    echo "✅ Sonda instalada. Log: $PROBE_LOG"
    echo ""
    echo "Ahora, en un proyecto con workflow:"
    echo "  1. Corré /wf con una descripción que rutee a una etapa"
    echo "     (ej: /wf necesito un plan para el ticket X)"
    echo "  2. Volvé acá y corré: ./scripts/wf-probe.sh --report"
    echo "  3. Desinstalá con: ./scripts/wf-probe.sh --remove"
    exit 0 ;;

  --remove)
    command -v jq >/dev/null 2>&1 || { echo "❌ Hace falta jq"; exit 1; }
    TMP="$(mktemp)"
    jq '
      def strip:
        map(.hooks |= map(select((.command // "") | contains("wf-probe.sh") | not)))
        | map(select((.hooks | length) > 0));
      .hooks.UserPromptSubmit //= [] | .hooks.UserPromptSubmit |= strip
      | .hooks.PreToolUse     //= [] | .hooks.PreToolUse       |= strip
      | .hooks.PostToolUse    //= [] | .hooks.PostToolUse      |= strip
    ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
    rm -f "$SELF"
    echo "✅ Sonda desregistrada. El log queda en $PROBE_LOG"
    exit 0 ;;

  --report)
    [ -s "$PROBE_LOG" ] || { echo "El log está vacío — ¿corriste /wf con la sonda instalada?"; exit 1; }
    echo "═══ Eventos capturados ($(wc -l < "$PROBE_LOG" | tr -d ' ') líneas) ═══"
    echo ""
    echo "── Por evento y tool ──"
    jq -r '"\(.probe_event)\t\(.tool_name // "-")"' "$PROBE_LOG" 2>/dev/null | sort | uniq -c | sort -rn
    echo ""
    echo "── ¿Se invocó el tool Skill? (candidato c) ──"
    jq -r 'select(.tool_name == "Skill") | "  \(.probe_event): \(.tool_input // {} | tostring)"' "$PROBE_LOG" 2>/dev/null | head -10 || true
    grep -q '"tool_name":"Skill"' "$PROBE_LOG" 2>/dev/null || echo "  (ninguno)"
    echo ""
    echo "── ¿Se leyó algún wf-*.md? (candidato b) ──"
    jq -r 'select((.tool_input.file_path // "") | test("wf-[a-z-]*\\.md"))
           | "  \(.probe_event) \(.tool_name): \(.tool_input.file_path)"' "$PROBE_LOG" 2>/dev/null | head -10
    echo ""
    echo "── Prompts que empiezan con /wf ──"
    jq -r 'select((.prompt // "") | test("^\\s*/wf")) | "  \(.prompt[0:80])"' "$PROBE_LOG" 2>/dev/null | head -5
    exit 0 ;;
esac

# ---------------------------------------------------------------------------
# Modo hook: volcar el input crudo con la etiqueta del evento. Nunca bloquea.
# ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0
mkdir -p "$(dirname "$PROBE_LOG")" 2>/dev/null || exit 0
printf '%s' "$INPUT" \
  | jq -c --arg e "${1:-unknown}" '. + {probe_event: $e}' >> "$PROBE_LOG" 2>/dev/null
exit 0
