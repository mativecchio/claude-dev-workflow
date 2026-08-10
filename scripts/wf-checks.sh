#!/bin/bash
#
# wf-checks — runs the project's deterministic gates.
#
# The DoD used to live as a list of prose strings that an agent evaluated by
# judgment ("does the linter pass?", "is there a console.log?"). A command
# answers that in seconds, with no false positives and without spending an agent.
#
# Project config (.claude/workflow/config.json):
#   "checks": { "lint": "npm run lint", "types": "tsc --noEmit", "test": "npm test" }
#
# Usage:
#   wf-checks.sh            run them all, human-readable output
#   wf-checks.sh --json     JSON output for a command to consume
#   wf-checks.sh lint       run a single one
#
# Exit: 0 if all pass, 1 if any fails, 2 if no checks are configured.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$DIR/wf-lib.sh" ] && . "$DIR/wf-lib.sh"

command -v jq >/dev/null 2>&1 || { echo "wf-checks: jq is required" >&2; exit 2; }

CONFIG="$(wf_workflow_root)/config.json"
[ -f "$CONFIG" ] || { echo "wf-checks: no config at $CONFIG" >&2; exit 2; }

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
    echo "⚠️  This project has no checks configured."
    echo "   Add them in $CONFIG:"
    echo '     "checks": { "lint": "...", "types": "...", "test": "..." }'
    echo "   Without this, validation depends on an agent's judgment for"
    echo "   things a command answers exactly."
  fi
  exit 2
fi

RESULTS="[]"; FAILED=0
[ "$JSON" -eq 1 ] || echo "🔍 Deterministic checks"

for name in $NAMES; do
  [ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && continue
  cmd="$(jq -r --arg n "$name" '.checks[$n]' "$CONFIG")"
  [ -n "$cmd" ] && [ "$cmd" != "null" ] || continue

  out="$(eval "$cmd" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && FAILED=1

  # Only the tail of the output: a test failure can dump thousands of lines and
  # the consumer of this is a prompt.
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
  [ "$FAILED" -eq 0 ] && echo "✅ All checks pass" || echo "❌ Some checks are failing — fix them before semantic validation"
fi

exit "$FAILED"
