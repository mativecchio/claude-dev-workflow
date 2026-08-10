#!/bin/bash
#
# wf-probe — temporary probe to resolve H1 (docs/plan-harness-migration.md).
#
# QUESTION IT ANSWERS: when a stage is routed via `/wf` instead of typing
# `/wf-analyze`, what does a hook see? The telemetry hook only matches the typed
# command in UserPromptSubmit, so today the whole orchestrator path is invisible
# and events.jsonl stays empty.
#
# There were three candidates and NONE was verified:
#   (a) /wf writing stage before routing     → depends on the model
#   (b) PreToolUse on a Read of wf-*.md      → depends on the model
#   (c) PostToolUse with tool_name "Skill"   → mechanical, if it happens that way
#
# This probe dumps the raw JSON so the decision rests on data instead of a bet.
# It does NOT block, does NOT modify state, it only writes a file.
#
# Usage:
#   ./scripts/wf-probe.sh --install    registers the probe in ~/.claude/settings.json
#   ./scripts/wf-probe.sh --remove     unregisters it (and leaves the log)
#   ./scripts/wf-probe.sh --report     summarizes what it captured
#   ./scripts/wf-probe.sh <event>      hook mode (invoked by Claude Code)

PROBE_LOG="$HOME/.claude/workflow/probe.jsonl"
SETTINGS="$HOME/.claude/settings.json"
SELF="$HOME/.claude/hooks/wf-probe.sh"

case "${1:-}" in
  --install)
    command -v jq >/dev/null 2>&1 || { echo "❌ jq is required"; exit 1; }
    mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/workflow"
    cp "$0" "$SELF" 2>/dev/null; chmod +x "$SELF"
    [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    jq -e . "$SETTINGS" >/dev/null 2>&1 || { echo "❌ invalid settings.json"; exit 1; }
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
    echo "✅ Probe installed. Log: $PROBE_LOG"
    echo ""
    echo "Now, in a project with a workflow:"
    echo "  1. Run /wf with a description that routes to a stage"
    echo "     (e.g. /wf I need a plan for ticket X)"
    echo "  2. Come back here and run: ./scripts/wf-probe.sh --report"
    echo "  3. Uninstall with: ./scripts/wf-probe.sh --remove"
    exit 0 ;;

  --remove)
    command -v jq >/dev/null 2>&1 || { echo "❌ jq is required"; exit 1; }
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
    echo "✅ Probe unregistered. The log stays at $PROBE_LOG"
    exit 0 ;;

  --report)
    [ -s "$PROBE_LOG" ] || { echo "The log is empty — did you run /wf with the probe installed?"; exit 1; }
    echo "═══ Captured events ($(wc -l < "$PROBE_LOG" | tr -d ' ') lines) ═══"
    echo ""
    echo "── By event and tool ──"
    jq -r '"\(.probe_event)\t\(.tool_name // "-")"' "$PROBE_LOG" 2>/dev/null | sort | uniq -c | sort -rn
    echo ""
    echo "── Was the Skill tool invoked? (candidate c) ──"
    jq -r 'select(.tool_name == "Skill") | "  \(.probe_event): \(.tool_input // {} | tostring)"' "$PROBE_LOG" 2>/dev/null | head -10 || true
    grep -q '"tool_name":"Skill"' "$PROBE_LOG" 2>/dev/null || echo "  (none)"
    echo ""
    echo "── Was any wf-*.md read? (candidate b) ──"
    jq -r 'select((.tool_input.file_path // "") | test("wf-[a-z-]*\\.md"))
           | "  \(.probe_event) \(.tool_name): \(.tool_input.file_path)"' "$PROBE_LOG" 2>/dev/null | head -10
    echo ""
    echo "── Prompts starting with /wf ──"
    jq -r 'select((.prompt // "") | test("^\\s*/wf")) | "  \(.prompt[0:80])"' "$PROBE_LOG" 2>/dev/null | head -5
    exit 0 ;;
esac

# ---------------------------------------------------------------------------
# Hook mode: dump the raw input tagged with the event name. Never blocks.
# ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0
mkdir -p "$(dirname "$PROBE_LOG")" 2>/dev/null || exit 0
printf '%s' "$INPUT" \
  | jq -c --arg e "${1:-unknown}" '. + {probe_event: $e}' >> "$PROBE_LOG" 2>/dev/null
exit 0
