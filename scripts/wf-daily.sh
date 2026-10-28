#!/bin/bash
#
# Daily notes: what got done, what comes next, the doubts and the blockers,
# kept across every project so /wf-daily can say what to tell at the stand-up.
# One file per day in $WF_DAILY_DIR (~/.claude/workflow/daily by default).
#
# Usage:
#   wf-daily.sh note <done|plan|doubt|blocker> <text...>   append a note to today
#   wf-daily.sh since [YYYY-MM-DD]     the last working day before that date (today by default)
#   wf-daily.sh notes [YYYY-MM-DD]     every note from that date (default: since) up to today
#   wf-daily.sh path [YYYY-MM-DD]      the file of that day (today by default)

DIR="${WF_DAILY_DIR:-$HOME/.claude/workflow/daily}"
KINDS="done plan doubt blocker"

# GNU date first, BSD date (macOS) as the fallback.
day_shift() {  # <YYYY-MM-DD> <days, may be negative>
  date -d "$1 $2 day" +%F 2>/dev/null || date -j -v"${2}d" -f %F "$1" +%F
}
weekday() {    # <YYYY-MM-DD> → 1 (Monday) … 7 (Sunday)
  date -d "$1" +%u 2>/dev/null || date -j -f %F "$1" +%u
}

today() { echo "${WF_DAILY_TODAY:-$(date +%F)}"; }

since() {
  local d
  d="$(day_shift "${1:-$(today)}" -1)"
  while [ "$(weekday "$d")" -gt 5 ]; do d="$(day_shift "$d" -1)"; done
  echo "$d"
}

note() {
  local kind="$1"; shift
  case " $KINDS " in
    *" $kind "*) ;;
    *) echo "wf-daily: kind must be one of: $KINDS" >&2; return 2 ;;
  esac
  [ -n "$*" ] || { echo "wf-daily: empty note" >&2; return 2; }

  local where="" top branch
  top="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$top" ]; then
    branch="$(git branch --show-current 2>/dev/null)"
    where=" ($(basename "$top")${branch:+@$branch})"
  fi

  mkdir -p "$DIR"
  local f="$DIR/$(today).md"
  [ -f "$f" ] || echo "# $(today)" > "$f"
  echo "- $(date +%H:%M) [$kind] $*$where" >> "$f"
  echo "$f"
}

notes() {
  local from="${1:-$(since)}" d to
  to="$(today)"
  d="$from"
  while [[ ! "$d" > "$to" ]]; do
    [ -f "$DIR/$d.md" ] && { cat "$DIR/$d.md"; echo; }
    d="$(day_shift "$d" 1)"
  done
}

case "${1:-}" in
  note)  shift; note "$@" ;;
  since) since "${2:-}" ;;
  notes) notes "${2:-}" ;;
  path)  echo "$DIR/${2:-$(today)}.md" ;;
  *)
    echo "usage: wf-daily.sh {note <$(echo $KINDS | tr ' ' '|')> <text>|since [date]|notes [from]|path [date]}" >&2
    exit 2 ;;
esac
