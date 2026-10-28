#!/bin/bash
#
# wf-daily-hook — notes for the daily without anyone remembering to take them.
#
# At the end of a session, before a compaction, and at most once an hour on
# Stop, it reads what the conversation said since the last time it looked,
# asks a small model for the milestones worth saying at the stand-up, and
# appends them to today's notes with wf-daily.sh. /wf-daily keeps the
# important ones when it writes the summary.
#
# Usage (from ~/.claude/settings.json):
#   wf-daily-hook.sh stop | pre-compact | session-end   < hook JSON
#
# Never blocks or breaks the session: the extraction runs detached and every
# error is swallowed. WF_DAILY=off turns it off. WF_DAILY_HOOK is set on the
# model call it makes, so that session never feeds the hooks back.

[ "${WF_DAILY:-on}" = "off" ] && exit 0
[ -n "${WF_DAILY_HOOK:-}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v claude >/dev/null 2>&1 || exit 0

MODE="${1:-}"
INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0
jget() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

SESSION="$(jget '.session_id')"
TRANSCRIPT="$(jget '.transcript_path')"
CWD="$(jget '.cwd')"
[ -n "$SESSION" ] && [ -f "$TRANSCRIPT" ] || exit 0

DIR="${WF_DAILY_DIR:-$HOME/.claude/workflow/daily}"
STATE="$DIR/.sessions/$SESSION"
INTERVAL="${WF_DAILY_INTERVAL:-3600}"
mkdir -p "$DIR/.sessions" 2>/dev/null || exit 0

LAST_LINE=0; LAST_AT=0
[ -f "$STATE" ] && read -r LAST_LINE LAST_AT < "$STATE"
NOW="$(date +%s)"
[ "$MODE" = "stop" ] && [ $((NOW - LAST_AT)) -lt "$INTERVAL" ] && exit 0

TOTAL="$(wc -l < "$TRANSCRIPT" | tr -d ' ')"
[ "$TOTAL" -gt "$LAST_LINE" ] || exit 0

# What the user asked and what the assistant answered, without tool output:
# that is where milestones, questions and blockers are said in words.
EXCERPT="$(tail -n +"$((LAST_LINE + 1))" "$TRANSCRIPT" | head -n "$((TOTAL - LAST_LINE))" | jq -r '
  select(.type == "user" or .type == "assistant")
  | select((.isMeta // false) | not)
  | .type as $who
  | (.message.content
     | if type == "string" then .
       else (map(select(.type == "text") | .text) | join("\n")) end) as $text
  | select(($text | length) > 0)
  | select($text | test("^<(system-reminder|command-|local-command|task-notification)") | not)
  | "\($who | ascii_upcase): \($text[0:800])"
' 2>/dev/null | tail -c 40000)"

echo "$TOTAL $NOW" > "$STATE"
# A short exchange says nothing worth a stand-up.
[ "$(printf '%s\n' "$EXCERPT" | grep -c '^USER: ')" -ge 2 ] || exit 0

TODAY_NOTES="$(cat "$DIR/$(date +%F).md" 2>/dev/null)"

(
  cd "${CWD:-$HOME}" 2>/dev/null || cd "$HOME"
  PROMPT="You extract stand-up notes from a work session between a developer and an AI assistant.

From the excerpt below, list only what the developer would say at tomorrow's daily:
- done: work finished or delivered (MR opened or merged, spec or plan written, ticket moved, bug fixed, decision taken)
- plan: what they said they will do next
- doubt: a question sent to someone, or left open, still unanswered
- blocker: something that stops the work, and who or what it waits on

Rules: at most 3 lines, and 0 is the usual answer: only what a teammate would care about. Skip routine steps (reading files, running tests,
small edits), anything already in the existing notes, and anything about the AI tooling itself unless
it was the work. Each line: kind, a tab, then one English sentence starting with the ticket key when
there is one. Output only the lines, no other text.

Existing notes for today:
${TODAY_NOTES:-(none)}

Excerpt:
$EXCERPT"
  WF_DAILY_HOOK=1 timeout 120 claude -p --model "${WF_DAILY_MODEL:-haiku}" \
      --no-session-persistence --tools "" "$PROMPT" 2>/dev/null \
    | while IFS=$'\t' read -r kind text; do
        kind="$(printf '%s' "$kind" | tr -d '[:space:]-' | tr '[:upper:]' '[:lower:]')"
        case "$kind" in done|plan|doubt|blocker) ;; *) continue ;; esac
        [ -n "$text" ] && "${WF_DAILY_BIN:-$HOME/.claude/scripts/wf-daily.sh}" note "$kind" "$text" >/dev/null 2>&1
      done
) </dev/null >/dev/null 2>&1 &
# Tests wait for it; a real session never does.
if [ -n "${WF_DAILY_SYNC:-}" ]; then wait; else disown 2>/dev/null; fi

exit 0
