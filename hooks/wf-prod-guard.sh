#!/bin/bash
#
# wf-prod-guard — asks before a request that writes is sent from the browser or
# the terminal, so a delete or an edit in production never goes out on the
# model's own judgement.
#
# Why: on 2026-11-12, reverting a test on a production chain, the screen's delete
# failed and the model deleted the record by calling the API straight from the
# page with fetch(..., {method: 'DELETE'}), without asking. A memory rule now says
# to double-check the id and wait for the user; this hook makes the ask mechanical
# for the paths it can see.
#
# What it catches (PreToolUse):
#   - Chrome's javascript_tool, and browser_batch steps that carry it: code with a
#     DELETE, PUT, PATCH or POST request (fetch, XMLHttpRequest, axios-style
#     helpers). The tool only gets a tab id, never the URL, so it can not tell
#     production from a test environment: every write through page JavaScript
#     asks. That is rare and worth a confirmation anywhere.
#   - Bash: curl, wget or httpie against a production host with a method or a
#     body that writes. Production hosts are per project, never in this file:
#     see below.
# What it can not catch: clicks on a screen's own buttons (it sees coordinates,
# not what the button does). Those stay under the memory rule.
#
# It never blocks: it answers "ask", so the user approves or rejects in the
# permission prompt. Fail-open: any error exits 0 and lets the call through.
#
# Modes (WF_PROD_GUARD):
#   ask   (default) asks for confirmation
#   off   does nothing
#
# Production hosts: extended regexes matched against the command, from
#   - "prod_hosts" in the project's .claude/workflow/config.json (the git root
#     of the hook's cwd),
#   - "prod_hosts" in ~/.claude/workflow/config.json, for hosts that must be
#     guarded from any checkout (worktrees have no project config),
#   - WF_PROD_HOSTS, one more regex.
# With none of them the Bash check is skipped; the JavaScript one still runs.

MODE="${WF_PROD_GUARD:-ask}"
[ "$MODE" = "off" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat)"; [ -z "$INPUT" ] && exit 0

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[ -z "$TOOL" ] && exit 0

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
ROOT="$( [ -n "$CWD" ] && git -C "$CWD" rev-parse --show-toplevel 2>/dev/null )"
prod_hosts() {
  for f in "${ROOT:+$ROOT/.claude/workflow/config.json}" "$HOME/.claude/workflow/config.json"; do
    [ -n "$f" ] && [ -f "$f" ] && jq -r '(.prod_hosts // [])[]' "$f" 2>/dev/null
  done
  [ -n "${WF_PROD_HOSTS:-}" ] && printf '%s\n' "$WF_PROD_HOSTS"
}
PROD_HOSTS="$(prod_hosts | grep -v '^$' | paste -sd'|' -)"
WRITE_METHODS='DELETE|PUT|PATCH|POST'

ask() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

case "$TOOL" in
  mcp__claude-in-chrome__javascript_tool|mcp__claude-in-chrome__browser_batch)
    # The whole input as text: browser_batch nests the code in its steps.
    CODE="$(printf '%s' "$INPUT" | jq -r '.tool_input | tostring' 2>/dev/null)" || exit 0
    # Any quoted "DELETE"/"PUT"/... (a method option, an XHR open, a helper's
    # argument such as bc(path, 'DELETE')), a lower-case method option, or an
    # axios-style .delete(/.put(/.patch(/.post( call. Quotes may arrive escaped
    # (\"), since the input is read back as JSON text.
    Q="\\\\?[\"'\`]"
    if printf '%s' "$CODE" | grep -Eq "$Q[[:space:]]*($WRITE_METHODS)[[:space:]]*$Q" \
        || printf '%s' "$CODE" | grep -Eiq "method[^:=]{0,4}[:=][[:space:]]*$Q(delete|put|patch|post)$Q" \
        || printf '%s' "$CODE" | grep -Eq "\.(delete|put|patch|post)\("; then
      ask "wf-prod-guard: this JavaScript sends a request that writes (DELETE/PUT/PATCH/POST). If the tab is production, check the id of what it changes and confirm only if the user said yes to that exact change."
    fi
    ;;
  Bash)
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
    [ -z "$CMD" ] && exit 0
    [ -z "$PROD_HOSTS" ] && exit 0
    # Only an HTTP client in command position counts: at the start of a line or
    # after ; & | ( or $(, optionally behind env assignments or sudo. A curl that
    # only appears inside a string (an echo, a test fixture, a heredoc of JSON)
    # is text, not a request, and must not ask.
    CALLS="$(printf '%s\n' "$CMD" | tr ';&|(' '\n\n\n\n' \
      | grep -E '^[[:space:]]*\$?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(sudo[[:space:]]+)?(curl|wget|http|https|xh)([[:space:]]|$)')"
    [ -z "$CALLS" ] && exit 0
    printf '%s\n' "$CALLS" | while IFS= read -r call; do
      printf '%s' "$call" | grep -Eiq "$PROD_HOSTS" || continue
      if printf '%s' "$call" | grep -Eiq \
          "(-X|--request|--method)[[:space:]]*\"?'?($WRITE_METHODS)|(^|[[:space:]])(-d|--data[a-z-]*|-F|--form|--json|--post-data|--body-data)([[:space:]=]|$)|(^|[[:space:]])($WRITE_METHODS)[[:space:]]+https?://"; then
        echo hit; break
      fi
    done | grep -q hit && ask "wf-prod-guard: this command sends a request that writes to a production host. Check the id of what it changes and confirm only if the user said yes to that exact change."
    ;;
esac

exit 0
