#!/bin/bash
#
# wf-stats — answers the §10 questions over events.jsonl.
#
# Without this, telemetry only accumulates. The brainstorm lists seven questions
# the schema is supposed to answer; each one is a subcommand here, so a proposal
# can cite the exact query that produced it (§0: no evidence, no change).
#
# TWO RULES THIS SCRIPT ENFORCES, because they are what makes the output
# trustworthy rather than merely available:
#
#   1. It always reports the sample size. A percentage over 2 tickets is noise,
#      and printing it bare invites acting on it.
#   2. It refuses to conclude below §0's minimum of 3 tickets, printing the
#      numbers with an explicit "not enough evidence" instead. The failure mode
#      this system is built against is a confident change backed by one bad day.
#
# Usage:
#   wf-stats.sh                 summary of everything with enough data
#   wf-stats.sh origins         Q1 — which stage originates most defects
#   wf-stats.sh leak            Q2 — mean leak distance by origin stage
#   wf-stats.sh detection       Q3 — share of findings caught by user vs gate
#   wf-stats.sh calibration     Q4 — estimated vs actual complexity
#   wf-stats.sh sister          Q5 — sister_feature:none vs iterations
#   wf-stats.sh split           Q6 — did splitting reduce iterations
#   wf-stats.sh categories      Q7 — finding categories repeated in 3+ tickets
#   wf-stats.sh coverage        log health: hook events with no semantic event
#
# Options: --project <name>  --ticket <id>  --since <YYYY-MM-DD>  --json

set -uo pipefail

EVENTS="${WF_EVENTS_FILE:-$HOME/.claude/workflow/events.jsonl}"
MIN_TICKETS=3          # §0: minimum sample before a pattern counts as evidence
STAGES='["refine","analyze","review-plan","implement","validate","test","mr-desc","mr-review","retro"]'

command -v jq >/dev/null 2>&1 || { echo "wf-stats: jq not available" >&2; exit 1; }

CMD="summary"; P_PROJECT=""; P_TICKET=""; P_SINCE=""; AS_JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) P_PROJECT="${2:-}"; shift 2 ;;
    --ticket)  P_TICKET="${2:-}"; shift 2 ;;
    --since)   P_SINCE="${2:-}"; shift 2 ;;
    --json)    AS_JSON=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    --*)       echo "wf-stats: unknown option $1" >&2; exit 1 ;;
    *)         CMD="$1"; shift ;;
  esac
done

if [ ! -f "$EVENTS" ] || [ ! -s "$EVENTS" ]; then
  echo "📭 events.jsonl is empty or missing ($EVENTS)"
  echo "   Telemetry fills itself in as you run stages. Nothing to report yet."
  exit 0
fi

# Filter once. Malformed lines are dropped and counted, never allowed to abort
# the run — a single bad row must not make the whole history unreadable.
# Read line-by-line with -R and `fromjson?`, so one unparseable row is skipped
# instead of aborting the run. Reading the file as a JSON stream can't do this:
# jq bails on the bad line and leaves the rest unread, which is the difference
# between "one lost event" and "no history at all".
TOTAL_LINES="$(grep -c . "$EVENTS" 2>/dev/null || echo 0)"

EV="$(jq -cR --arg p "$P_PROJECT" --arg t "$P_TICKET" --arg s "$P_SINCE" '
        fromjson? // empty
      | select(type=="object")
      | select($p == "" or .project == $p)
      | select($t == "" or .ticket == $t)
      | select($s == "" or (.ts // "") >= $s)
     ' "$EVENTS" 2>/dev/null)"

GOOD="$(jq -cR 'fromjson? // empty | select(type=="object")' "$EVENTS" 2>/dev/null | grep -c . || true)"
[ -n "$GOOD" ] || GOOD=0
PARSED="$(printf '%s' "$EV" | grep -c . || true)"
[ -n "$PARSED" ] || PARSED=0
BAD=$(( TOTAL_LINES - GOOD ))

n_tickets() { printf '%s' "$EV" | jq -s '[.[].ticket] | unique | length'; }
# All args go straight to jq, so call sites can pass -r / --argjson.
q() { printf '%s' "$EV" | jq -s "$@"; }

# Prints the numbers, then whether they may be acted on. Keeping these together
# is the point: a caller that sees the table must also see the verdict.
evidence_note() {
  local n="$1"
  if [ "$n" -lt "$MIN_TICKETS" ]; then
    printf '\n   ⚠️  %s ticket(s) in the sample — below the minimum of %s (§0).\n' "$n" "$MIN_TICKETS"
    printf '   The numbers are above, but they are NOT enough to justify a workflow change.\n'
  else
    printf '\n   ✅ %s tickets in the sample — meets the §0 minimum.\n' "$n"
  fi
}

hdr() { printf '\n═══ %s ═══\n' "$1"; }

# --- Q1 ------------------------------------------------------------------------
origins() {
  hdr "Q1 — Which stage originates the most defects?"
  q -r '[.[] | select(.event=="finding")] as $f
     | if ($f|length)==0 then "  (no findings recorded)"
       else ($f | group_by(.data.stage_origin)
             | map({stage:(.[0].data.stage_origin // "?"),
                    n:length,
                    tickets:([.[].ticket]|unique|length),
                    high:([.[]|select(.data.severity=="high")]|length)})
             | sort_by(-.n)
             | map("  \(.stage|tostring): \(.n) findings, \(.tickets) tickets, \(.high) high severity")
             | join("\n"))
       end'
  evidence_note "$(q '[.[]|select(.event=="finding").ticket]|unique|length')"
}

# --- Q2 ------------------------------------------------------------------------
# Leak distance = idx(stage_detected) - idx(stage_origin). A defect born in
# analyze and caught in mr-review leaked further than one caught in review-plan;
# the mean tells you where the next gate belongs.
leak() {
  hdr "Q2 — Mean leak by origin stage"
  q -r --argjson st "$STAGES" '
      [ .[] | select(.event=="finding")
      | . as $e
      | ($st | index($e.data.stage_origin)) as $o
      | ($st | index($e.data.stage_detected // $e.stage)) as $d
      | select($o != null and $d != null)
      | {origin:$e.data.stage_origin, ticket:$e.ticket, dist:($d - $o)} ] as $f
    | if ($f|length)==0 then "  (no findings with resolvable stages)"
      else ($f | group_by(.origin)
            | map({stage:.[0].origin, n:length,
                   avg:((map(.dist)|add)/length*100|round/100),
                   max:(map(.dist)|max)})
            | sort_by(-.avg)
            | map("  \(.stage): mean leak \(.avg) stages (max \(.max), n=\(.n))")
            | join("\n"))
      end'
  printf '\n   High leak = the gate that should have caught it is too late or missing.\n'
  evidence_note "$(q '[.[]|select(.event=="finding").ticket]|unique|length')"
}

# --- Q3 ------------------------------------------------------------------------
detection() {
  hdr "Q3 — Is the detected_by: user share rising?"
  q -r '[.[] | select(.event=="finding")] as $f
     | if ($f|length)==0 then "  (no findings recorded)"
       else ([$f[]|select(.data.detected_by=="user")]|length) as $u
            | ([$f[]|select(.data.detected_by=="gate")]|length) as $g
            | "  gate: \($g)   user: \($u)   total: \($f|length)\n  ratio user: \(if ($f|length)>0 then (($u/($f|length))*100|round) else 0 end)%"
       end'
  printf '\n   A rising user ratio means the gates are degrading:\n'
  printf '   you are the one finding the defects, not the workflow.\n'
  evidence_note "$(q '[.[]|select(.event=="finding").ticket]|unique|length')"
}

# --- Q4 ------------------------------------------------------------------------
calibration() {
  hdr "Q4 — Do I systematically underestimate?"
  q -r '[.[]|select(.event=="complexity_estimate")] as $e
     | [.[]|select(.event=="ticket_closed")] as $c
     | if ($e|length)==0 then "  (no complexity_estimate recorded)"
       else ([ $e[] | . as $x | ($c[]|select(.ticket==$x.ticket)) as $y
               | select($y.data.complexity_actual != null)
               | {ticket:$x.ticket, est:$x.data.points, act:$y.data.complexity_actual,
                  err:($y.data.complexity_actual - $x.data.points)} ]) as $pairs
            | if ($pairs|length)==0
              then "  \($e|length) estimates, 0 with complexity_actual to compare against.\n  Without the (estimated, actual) pair the score is decorative — wf-retro has to close it."
              else ($pairs|map("  \(.ticket): est \(.est) → actual \(.act) (err \(.err))")|join("\n"))
                   + "\n  mean error: \((($pairs|map(.err)|add)/($pairs|length))*100|round/100)"
              end
       end'
  printf '\n   Positive mean error = you underestimate. Negative = you overestimate.\n'
  evidence_note "$(q '[.[]|select(.event=="complexity_estimate").ticket]|unique|length')"
}

# --- Q5 ------------------------------------------------------------------------
# The §5.3 bet: no sister feature → the model invents conventions → more churn.
sister() {
  hdr "Q5 — Does sister_feature:none correlate with more iterations?"
  q -r '[.[]|select(.event=="complexity_estimate")] as $e
     | [.[]|select(.event=="ticket_closed")] as $c
     | if ($e|length)==0 then "  (no complexity_estimate recorded)"
       else ([ $e[] | . as $x
               | {ticket:$x.ticket,
                  sis:($x.data.dimensions.sister_feature.value // "?"),
                  it:(($c[]|select(.ticket==$x.ticket)|.data.iterations_total) // null)}
               | select(.it != null) ]) as $p
            | if ($p|length)==0 then "  (no closed tickets with iterations to cross-reference)"
              else ($p|group_by(.sis)
                    |map("  sister_feature=\(.[0].sis): \(length) tickets, mean iterations \(((map(.it)|add)/length)*100|round/100)")
                    |join("\n"))
              end
       end'
  printf '\n   §5.3 is a hypothesis: if the correlation does not show up, weight 6 drops\n'
  printf '   and it is recorded in improvements.md with this query as evidence.\n'
  evidence_note "$(q '[.[]|select(.event=="complexity_estimate").ticket]|unique|length')"
}

# --- Q6 ------------------------------------------------------------------------
split() {
  hdr "Q6 — Did splitting reduce iterations or just relocate them?"
  q -r '([.[]|select(.event=="split_applied")|.ticket]|unique) as $s
     | [.[]|select(.event=="ticket_closed")] as $c
     | if ($c|length)==0 then "  (no closed tickets)"
       else ([$c[]|select(.ticket as $t|$s|index($t))]) as $with
            | ([$c[]|select(.ticket as $t|($s|index($t))==null)]) as $without
            | "  with split:    \($with|length) tickets" +
              (if ($with|length)>0 then ", mean iterations \((($with|map(.data.iterations_total)|add)/($with|length))*100|round/100)" else "" end) +
              "\n  without split: \($without|length) tickets" +
              (if ($without|length)>0 then ", mean iterations \((($without|map(.data.iterations_total)|add)/($without|length))*100|round/100)" else "" end)
       end'
  printf '\n   Careful: add up the subtasks iterations. If the total does not drop,\n'
  printf '   splitting only moved the work around.\n'
  evidence_note "$(q '[.[]|select(.event=="ticket_closed").ticket]|unique|length')"
}

# --- Q7 ------------------------------------------------------------------------
categories() {
  hdr "Q7 — Finding categories across 3+ tickets"
  q -r --argjson min "$MIN_TICKETS" '
      [.[]|select(.event=="finding")] as $f
    | if ($f|length)==0 then "  (no findings recorded)"
      else ($f|group_by(.data.category)
            |map({cat:(.[0].data.category // "?"), n:length,
                  tickets:([.[].ticket]|unique|length),
                  stages:([.[].data.stage_origin]|unique|join(","))})
            |sort_by(-.tickets)
            |map(if .tickets >= $min
                 then "  ✅ \(.cat): \(.tickets) tickets, \(.n) findings — origin: \(.stages)  ← grounded candidate"
                 else "  ·  \(.cat): \(.tickets) ticket(s), \(.n) findings — insufficient" end)
            |join("\n"))
      end'
  printf '\n   Only the ✅ ones satisfy §0 and can justify a workflow change.\n'
}

# --- log health ----------------------------------------------------------------
# The whole reason for two layers: a hook-recorded re-entry with no semantic
# event explaining it means the cause was lost. That gap is itself the signal.
coverage() {
  hdr "Log health — is the cause being lost?"
  printf '  total lines: %s   parsed: %s   unreadable: %s\n' "$TOTAL_LINES" "$PARSED" "$BAD"
  q -r '  ([.[]|select(.source=="hook")]|length) as $h
     | ([.[]|select(.source=="command")]|length) as $c
     | "  hook events: \($h)   command events: \($c)"'
  q -r '[.[]|select(.event=="stage_reentry")] as $r
     | [.[]|select(.event=="finding")] as $f
     | if ($r|length)==0 then "  (no re-entries recorded)"
       else ([ $r[] | . as $x
               | select( [ $f[] | select(.ticket == $x.ticket) ] | length == 0 ) ]) as $orphan
            | "  re-entries: \($r|length), of which \($orphan|length) with no finding explaining them"
       end'
  printf '\n   A re-entry with no associated finding is a lost cause: the hook saw\n'
  printf '   that you went back to the stage, but no command recorded why.\n'
}

case "$CMD" in
  origins)     origins ;;
  leak)        leak ;;
  detection)   detection ;;
  calibration) calibration ;;
  sister)      sister ;;
  split)       split ;;
  categories)  categories ;;
  coverage)    coverage ;;
  summary)
    printf '📊 wf-stats — %s events, %s tickets\n' "$PARSED" "$(n_tickets)"
    [ "$BAD" -gt 0 ] && printf '⚠️  %s unreadable line(s), ignored\n' "$BAD"
    origins; leak; detection; categories; coverage
    printf '\nDetail: wf-stats.sh {calibration|sister|split}\n' ;;
  *) echo "wf-stats: unknown subcommand '$CMD'" >&2; exit 1 ;;
esac
