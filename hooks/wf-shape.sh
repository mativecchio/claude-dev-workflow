#!/bin/bash
#
# wf-shape — tells the agent, at the moment it happens, that a production file
# just grew past the size R1 of guides/responsibilities.md asks to justify.
#
# /wf-implement says to stop and report a file that crosses ~300 lines. That is
# an instruction, read once at the start of the stage and easy to lose forty
# edits later. This hook runs after every Edit/Write and says it right then.
#
# It never blocks: the edit already happened (PostToolUse). Exit 2 only hands the
# message to the agent, which then stops and asks the user. Blast radius, as in
# wf-gate.sh:
#
#   1. Registered globally, it exits silently in a project without
#      .claude/workflow/state.json.
#   2. Fail-open: any error (no jq, no git, unreadable file) exits 0.
#   3. It speaks once per crossing, not on every edit: a file that was already
#      over the limit at HEAD is reported only when it grows by another
#      WF_SHAPE_STEP lines, and each warning raises the bar by that much again.
#
# Settings: WF_SHAPE=off disables it. The limit is `max_file_lines` in the
# project's .claude/workflow/config.json, else WF_SHAPE_MAX_LINES, else 300.

[ "${WF_SHAPE:-on}" = "off" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"; [ -z "$INPUT" ] && exit 0

jget() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

case "$(jget '.tool_name')" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

FILE="$(jget '.tool_input.file_path')"
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

CWD="$(jget '.cwd')"; [ -n "$CWD" ] || CWD="$PWD"
ROOT="$(git -C "$(dirname "$FILE")" rev-parse --show-toplevel 2>/dev/null)" ||
  ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$ROOT/.claude/workflow/state.json" ] || exit 0

REL="${FILE#"$ROOT"/}"

# Production code only: tests, fixtures, stories, generated and vendored files
# are allowed to be long, and they are not what a reviewer has to understand.
case "$REL" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.vue|*.py|*.php|*.rb|*.go|*.java|*.kt|*.swift) ;;
  *) exit 0 ;;
esac
case "$REL" in
  */tests/*|tests/*|*/test/*|test/*|*/__tests__/*|*.test.*|*.spec.*|*.specs.js|\
  *_test.py|*/test_*.py|test_*.py|*/fixtures/*|*fixtures.*|*/__snapshots__/*|\
  *.stories.*|cypress/*|*/cypress/*|*/migrations/*|*/vendor/*|*/node_modules/*|\
  *.d.ts|*.min.js|*.generated.*) exit 0 ;;
esac

LIMIT="$(jq -r '.max_file_lines // empty' "$ROOT/.claude/workflow/config.json" 2>/dev/null)"
[ -n "$LIMIT" ] || LIMIT="${WF_SHAPE_MAX_LINES:-300}"
STEP="${WF_SHAPE_STEP:-50}"
case "$LIMIT$STEP" in *[!0-9]*) exit 0 ;; esac

NOW="$(wc -l < "$FILE" 2>/dev/null | tr -d ' ')"
[ -n "$NOW" ] || exit 0
[ "$NOW" -gt "$LIMIT" ] || exit 0

BEFORE="$(git -C "$ROOT" show "HEAD:$REL" 2>/dev/null | wc -l | tr -d ' ')"
[ -n "$BEFORE" ] || BEFORE=0

# The bar this file has to pass before it is reported (again).
SEEN="$HOME/.claude/workflow/shape-warned.tsv"
mkdir -p "$(dirname "$SEEN")" 2>/dev/null
LAST="$(awk -F'\t' -v f="$FILE" '$1 == f { n = $2 } END { print n + 0 }' "$SEEN" 2>/dev/null)"
[ -n "$LAST" ] || LAST=0

if [ "$LAST" -gt 0 ]; then
  BAR=$((LAST + STEP))
elif [ "$BEFORE" -gt "$LIMIT" ]; then
  BAR=$((BEFORE + STEP))
else
  BAR=$((LIMIT + 1))
fi
[ "$NOW" -ge "$BAR" ] || exit 0

printf '%s\t%s\n' "$FILE" "$NOW" >> "$SEEN" 2>/dev/null

TICKET="$(jq -r '.activeTicket // empty' "$ROOT/.claude/workflow/state.json" 2>/dev/null)"
EVENTS="$HOME/.claude/workflow/events.jsonl"
jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg project "$(basename "$ROOT")" \
  --arg ticket "$TICKET" \
  --arg file "$REL" \
  --argjson lines "$NOW" --argjson before "$BEFORE" --argjson limit "$LIMIT" \
  '{ts:$ts, project:$project, ticket:(if $ticket == "" then null else $ticket end),
    subtask:null, stage:null, source:"hook", event:"shape_warning",
    data:{file:$file, lines:$lines, lines_at_head:$before, limit:$limit}}' \
  >> "$EVENTS" 2>/dev/null

cat >&2 << EOF
📏 R1 (guides/responsibilities.md): $REL now has $NOW lines of production code
(it had $BEFORE at HEAD; the limit to justify is $LIMIT).

Before writing more to it: stop this group and tell the user. Say which
responsibilities the file now holds (list the clusters of functions with their
line ranges), propose how to split it, and let the user decide. If the plan's
Responsibilities table already justified this size, say so and carry on.
EOF
exit 2
