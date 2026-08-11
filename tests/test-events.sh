#!/bin/bash
#
# Tests for wf-event.sh and wf-stats.sh against a temp repo and a synthetic
# events file. Never touches the real ~/.claude/workflow/events.jsonl.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; echo "     $2"; FAIL=$((FAIL+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "did not find '$3' in: $(echo "$2"|head -3)";; esac; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export WF_EVENTS_FILE="$TMP/events.jsonl"

echo "═══ wf-event.sh ═══"

# A git repo with an active ticket, which is the context the script infers on its own.
PROJ="$TMP/proj"; mkdir -p "$PROJ/.claude/workflow/T-1"
cd "$PROJ" || exit 1
git init -q . 2>/dev/null
echo '{"activeTicket":"T-1"}' > .claude/workflow/state.json
echo '{"stage":"review-plan"}'  > .claude/workflow/T-1/state.json

# wf-event writes to $HOME/.claude/workflow/events.jsonl, not to WF_EVENTS_FILE:
# it is isolated with its own HOME so the real one is never touched.
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/workflow"
EV="$HOME/.claude/workflow/events.jsonl"

E="$REPO/scripts/wf-event.sh"

"$E" finding --category logic --severity high --stage_origin analyze \
     --detected_by gate --summary "missing guard" >/dev/null 2>&1
check "finding gets written" "$(wc -l < "$EV" | tr -d ' ')" "1"

L="$(tail -1 "$EV")"
check "ticket inferred from state"  "$(echo "$L" | jq -r '.ticket')" "T-1"
check "stage inferred from state"   "$(echo "$L" | jq -r '.stage')"  "review-plan"
check "source=command"             "$(echo "$L" | jq -r '.source')" "command"
check "project = repo basename" "$(echo "$L" | jq -r '.project')" "proj"
check "data.category"              "$(echo "$L" | jq -r '.data.category')" "logic"
check "line is valid JSON"       "$(echo "$L" | jq -e . >/dev/null 2>&1 && echo ok)" "ok"

# Typing: numbers have to stay numbers, not strings, or wf-stats means break
# without warning.
"$E" complexity_estimate --raw_score 21 --points 8 --split_recommended true >/dev/null 2>&1
L="$(tail -1 "$EV")"
check "number stays a number"   "$(echo "$L" | jq -r '.data.points|type')" "number"
check "boolean stays a boolean" "$(echo "$L" | jq -r '.data.split_recommended|type')" "boolean"

# A numeric-looking summary must NOT become a number if it is text with spaces.
"$E" finding --category x --severity low --stage_origin refine \
     --detected_by user --summary "8 affected files" >/dev/null 2>&1
check "string starting with a number stays a string" "$(tail -1 "$EV" | jq -r '.data.summary|type')" "string"

# Usage errors
"$E" nonexistent_event >/dev/null 2>&1; check "unknown event → exit 1" "$?" "1"
"$E" finding --category only >/dev/null 2>&1; check "missing required → exit 1" "$?" "1"
N_BEFORE="$(wc -l < "$EV" | tr -d ' ')"
"$E" finding --category only >/dev/null 2>&1
check "an invalid event writes nothing" "$(wc -l < "$EV" | tr -d ' ')" "$N_BEFORE"

# No active ticket: exit 2, writing nothing.
rm -f "$PROJ/.claude/workflow/state.json"
"$E" finding --category a --severity b --stage_origin refine --detected_by user --summary s >/dev/null 2>&1
check "no ticket → exit 2" "$?" "2"
check "no ticket writes nothing" "$(wc -l < "$EV" | tr -d ' ')" "$N_BEFORE"
echo '{"activeTicket":"T-1"}' > "$PROJ/.claude/workflow/state.json"

# Explicit stage override
"$E" finding --_stage implement --category c --severity low \
     --stage_origin refine --detected_by user --summary s >/dev/null 2>&1
check "--_stage overrides" "$(tail -1 "$EV" | jq -r '.stage')" "implement"

echo
echo "═══ wf-stats.sh ═══"
S="$REPO/scripts/wf-stats.sh"

# Empty file: it reports, it does not fail.
: > "$WF_EVENTS_FILE"
OUT="$("$S" 2>&1)"; check "empty → exit 0" "$?" "0"
has "empty is reported" "$OUT" "empty or missing"

cat > "$WF_EVENTS_FILE" <<'EOF'
{"ts":"2026-08-01T10:00:00Z","project":"p","ticket":"A-1","stage":"analyze","event":"complexity_estimate","source":"command","data":{"points":8,"dimensions":{"sister_feature":{"value":"none"}}}}
{"ts":"2026-08-01T11:00:00Z","project":"p","ticket":"A-1","stage":"review-plan","event":"finding","source":"command","data":{"category":"guard","severity":"high","stage_origin":"analyze","stage_detected":"review-plan","detected_by":"gate","summary":"x"}}
{"ts":"2026-08-01T12:00:00Z","project":"p","ticket":"A-1","stage":"mr-review","event":"finding","source":"command","data":{"category":"guard","severity":"high","stage_origin":"analyze","stage_detected":"mr-review","detected_by":"user","summary":"y"}}
{"ts":"2026-08-01T13:00:00Z","project":"p","ticket":"A-1","stage":"retro","event":"ticket_closed","source":"command","data":{"iterations_total":5,"complexity_actual":13}}
{"ts":"2026-08-02T11:00:00Z","project":"p","ticket":"A-2","stage":"validate","event":"finding","source":"command","data":{"category":"guard","severity":"medium","stage_origin":"implement","stage_detected":"validate","detected_by":"gate","summary":"z"}}
{"ts":"2026-08-03T10:00:00Z","project":"q","ticket":"A-3","stage":"validate","event":"finding","source":"command","data":{"category":"guard","severity":"low","stage_origin":"analyze","stage_detected":"validate","detected_by":"gate","summary":"w"}}
{"ts":"2026-08-04T10:00:00Z","project":"p","ticket":"A-4","stage":"implement","event":"stage_reentry","source":"hook","data":{"iteration_n":3}}
this is not json
EOF

OUT="$("$S" origins 2>&1)"
has "Q1 groups by stage_origin" "$OUT" "analyze: 3 findings, 2 tickets"
has "Q1 counts high severity"    "$OUT" "2 high severity"
has "Q1 with 3 tickets meets §0"  "$OUT" "meets the §0 minimum"

# Leak: analyze→review-plan = 1, analyze→mr-review = 6, analyze→validate = 3 ⇒ 3.33
OUT="$("$S" leak 2>&1)"
has "Q2 computes the mean leak" "$OUT" "analyze: mean leak 3.33"
has "Q2 reports the max"        "$OUT" "max 6"

OUT="$("$S" detection 2>&1)"
has "Q3 separates gate from user" "$OUT" "gate: 3   user: 1"
has "Q3 computes the ratio"       "$OUT" "ratio user: 25%"

OUT="$("$S" calibration 2>&1)"
has "Q4 builds the est/actual pair" "$OUT" "A-1: est 8 → actual 13"
has "Q4 flags the small sample"     "$OUT" "below the minimum"

OUT="$("$S" categories 2>&1)"
has "Q7 flags a category with 3+ tickets" "$OUT" "✅ guard: 3 tickets"

OUT="$("$S" coverage 2>&1)"
has "health counts unreadable lines"    "$OUT" "unreadable: 1"
has "health detects the orphan re-entry" "$OUT" "1 with no finding"

# One corrupt line must not take down the rest of the history.
OUT="$("$S" origins 2>&1)"
has "a corrupt line does not break the query" "$OUT" "analyze: 3 findings"

# Filters
OUT="$("$S" origins --ticket A-1 2>&1)"
has "--ticket filters" "$OUT" "analyze: 2 findings, 1 tickets"
OUT="$("$S" origins --project q 2>&1)"
has "--project filters" "$OUT" "analyze: 1 findings"
OUT="$("$S" origins --since 2026-08-03 2>&1)"
has "--since filters" "$OUT" "analyze: 1 findings"

# The summary has to run end to end with no jq errors.
OUT="$("$S" 2>&1)"
if echo "$OUT" | grep -qi "jq: error\|syntax error\|unbound variable"; then
  bad "summary runs clean" "$(echo "$OUT" | grep -i 'error' | head -2)"
else ok "summary runs clean"; fi

# The model thesis. The aggregate is misleading on purpose here: T-3 was a hard
# ticket implemented on sonnet against advice, and lumping it in buries the signal.
cat >> "$WF_EVENTS_FILE" <<'EOJ'
{"ts":"2026-08-05T10:00:00Z","project":"p","ticket":"T-1","stage":"analyze","event":"complexity_estimate","source":"command","data":{"points":2,"dimensions":{"sister_feature":{"value":"found"}}}}
{"ts":"2026-08-05T11:00:00Z","project":"p","ticket":"T-1","stage":"implement","event":"implement_started","source":"command","data":{"model_used":"sonnet","model_recommended":"sonnet"}}
{"ts":"2026-08-06T10:00:00Z","project":"p","ticket":"T-2","stage":"analyze","event":"complexity_estimate","source":"command","data":{"points":3,"dimensions":{"sister_feature":{"value":"found"}}}}
{"ts":"2026-08-06T11:00:00Z","project":"p","ticket":"T-2","stage":"implement","event":"implement_started","source":"command","data":{"model_used":"opus","model_recommended":"sonnet"}}
{"ts":"2026-08-06T12:00:00Z","project":"p","ticket":"T-2","stage":"implement","event":"stage_reentry","source":"hook","data":{"iteration_n":2}}
{"ts":"2026-08-07T10:00:00Z","project":"p","ticket":"T-3","stage":"analyze","event":"complexity_estimate","source":"command","data":{"points":8,"dimensions":{"sister_feature":{"value":"none"}}}}
{"ts":"2026-08-07T11:00:00Z","project":"p","ticket":"T-3","stage":"implement","event":"implement_started","source":"command","data":{"model_used":"sonnet","model_recommended":"opus"}}
{"ts":"2026-08-07T12:00:00Z","project":"p","ticket":"T-3","stage":"implement","event":"stage_reentry","source":"hook","data":{"iteration_n":2}}
EOJ
OUT="$("$S" models 2>&1)"
has "models groups by model used"      "$OUT" "sonnet: 2 tickets"
has "models restricts to strong plans" "$OUT" "Restricted to strong plans"
has "restricted view separates signal" "$OUT" "sonnet: 1 tickets, mean re-entries 0"
has "models counts advice followed"    "$OUT" "Advice followed: 1/3"

OUT="$("$S" does_not_exist 2>&1)"; check "invalid subcommand → exit 1" "$?" "1"

echo
echo "═══════════════════════════"
echo "  ✅ $PASS   ❌ $FAIL"
[ "$FAIL" -eq 0 ]
