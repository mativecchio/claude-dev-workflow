#!/bin/bash
#
# Validates wf-lib.sh, wf-diff.sh, wf-checks.sh and wf-gate.sh against a
# temporary git repo. It touches no real project.
#
# Usage:  ./tests/test-scripts.sh

REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/scripts"
SB="$(mktemp -d)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1 — got: '$3', expected: '$2'"; FAIL=$((FAIL+1)); }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()  { if printf '%s' "$3" | grep -q "$2"; then ok "$1"; else bad "$1" "contains $2" "$3"; fi; }

# --- test repo -------------------------------------------------------------
cd "$SB" || exit 1
SB="$(pwd -P)"   # on macOS /var is a symlink to /private/var and git resolves the real one
git init -q -b develop .
git config user.email t@t.t; git config user.name t
mkdir -p .claude/workflow/MA-100 src
echo "base" > src/a.js
git add -A >/dev/null; git commit -qm "base"
git checkout -qb MA-100-feature
echo '{"activeTicket":"MA-100"}' > .claude/workflow/state.json
cat > .claude/workflow/config.json << 'EOF'
{ "base_branch": "develop",
  "checks": { "ok": "true", "fails": "echo 'boom' >&2; exit 1" } }
EOF
echo '{}' > .claude/workflow/MA-100/state.json

echo "═══ wf-lib ═══"
eq "wf_ticket"  "MA-100"  "$(bash "$S/wf-lib.sh" ticket)"
eq "wf_base (from config)" "develop" "$(bash "$S/wf-lib.sh" base)"
eq "wf_dir"     "$SB/.claude/workflow/MA-100" "$(bash "$S/wf-lib.sh" dir)"

# Output language: English unless the project overrides it.
eq "wf_language defaults to en" "en" "$(bash "$S/wf-lib.sh" language)"
jq '.language="es"' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
eq "wf_language honors the config" "es" "$(bash "$S/wf-lib.sh" language)"
has "context exposes lang" "lang=es" "$(bash "$S/wf-lib.sh" context)"
jq 'del(.language)' .claude/workflow/config.json > t && mv t .claude/workflow/config.json

bash "$S/wf-lib.sh" enter-stage analyze >/dev/null
eq "enter_stage writes stage"        "analyze" "$(jq -r .stage .claude/workflow/MA-100/state.json)"
eq "enter_stage appends to completed" "analyze" "$(jq -r '.completed[0]' .claude/workflow/MA-100/state.json)"

bash "$S/wf-lib.sh" enter-stage analyze >/dev/null
eq "completed does not duplicate" "1" "$(jq -r '.completed | length' .claude/workflow/MA-100/state.json)"

# Fields the commands manage must not be lost.
jq '.branch="MA-100-feature" | .notes="something" | .iterations={"analyze":2}' \
   .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
bash "$S/wf-lib.sh" enter-stage review-plan >/dev/null
eq "preserves branch"      "MA-100-feature" "$(jq -r .branch .claude/workflow/MA-100/state.json)"
eq "preserves notes"       "something"      "$(jq -r .notes .claude/workflow/MA-100/state.json)"
eq "preserves iterations"  "2"              "$(jq -r '.iterations.analyze' .claude/workflow/MA-100/state.json)"

OUT="$(bash "$S/wf-lib.sh" enter-stage refinement 2>&1)"; RC=$?
eq "invalid stage fails"            "1" "$RC"
has "invalid stage explains why"    "invalid stage\|valid:" "$OUT"

cp .claude/workflow/MA-100/state.json /tmp/wf-good.json
echo 'broken{' > .claude/workflow/MA-100/state.json
bash "$S/wf-lib.sh" enter-stage test >/dev/null 2>&1
eq "does not overwrite a corrupt state" "broken{" "$(cat .claude/workflow/MA-100/state.json)"
cp /tmp/wf-good.json .claude/workflow/MA-100/state.json

echo "═══ wf-diff ═══"
echo "change" >> src/a.js; echo "new" > src/b.js
git add -A >/dev/null; git commit -qm "feature"
# The base advances AFTER the branch was created: the case that breaks `base..HEAD`.
git checkout -q develop; echo "foreign" > src/third-party.js
git add -A >/dev/null; git commit -qm "someone else's commit"
git checkout -q MA-100-feature

FILES="$(bash "$S/wf-diff.sh" --files)"
has "includes the feature's files"  "src/b.js"       "$FILES"
if printf '%s' "$FILES" | grep -q "third-party"; then
  bad "excludes commits foreign to the branch" "no src/third-party.js" "$FILES"
else ok "excludes commits foreign to the branch"; fi
has "--base reports the range"        "merge_base="  "$(bash "$S/wf-diff.sh" --base)"
has "--log lists the branch's commits" "feature"     "$(bash "$S/wf-diff.sh" --log)"

mkdir -p src/__tests__; echo "test" > src/__tests__/a.test.js
git add -A >/dev/null; git commit -qm "tests"
W="$(bash "$S/wf-diff.sh" --weight)"
has "separates test weight" "weight_tests=1" "$W"
has "production weight kept apart" "weight_prod=" "$W"

echo "═══ wf-checks ═══"
J="$(bash "$S/wf-checks.sh" --json)"
eq "detects that checks exist"  "true"  "$(printf '%s' "$J" | jq -r .configured)"
eq "reports the global failure" "false" "$(printf '%s' "$J" | jq -r .passed)"
eq "check that passes"          "true"  "$(printf '%s' "$J" | jq -r '.results[] | select(.name=="ok") | .passed')"
has "captures the failing check's output" "boom" "$(printf '%s' "$J" | jq -r '.results[] | select(.name=="fails") | .output')"
bash "$S/wf-checks.sh" >/dev/null 2>&1
eq "exit 1 if any fails" "1" "$?"

jq 'del(.checks)' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
bash "$S/wf-checks.sh" >/dev/null 2>&1
eq "exit 2 with no checks configured" "2" "$?"

echo "═══ wf-gate ═══"
G="$REPO/hooks/wf-gate.sh"
gate() { echo "{\"tool_name\":\"$1\",\"cwd\":\"$SB\",\"tool_input\":{\"file_path\":\"$2\"}}" | \
         WF_GATE="${3:-observe}" HOME="$SB" bash "$G" >/dev/null 2>&1; echo $?; }

jq '.stage="review-plan" | .approved=false' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
eq "observe does not block"              "0" "$(gate Edit "$SB/src/a.js" observe)"
eq "enforce blocks in review-plan"       "2" "$(gate Edit "$SB/src/a.js" enforce)"
eq "enforce allows .claude/workflow"     "0" "$(gate Edit "$SB/.claude/workflow/MA-100/plan.md" enforce)"
eq "enforce allows docs/"                "0" "$(gate Edit "$SB/docs/x.md" enforce)"
eq "does not apply to Read"              "0" "$(gate Read "$SB/src/a.js" enforce)"
eq "WF_GATE=off never blocks"            "0" "$(gate Edit "$SB/src/a.js" off)"

jq '.approved=true' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
eq "approved lets it through"            "0" "$(gate Edit "$SB/src/a.js" enforce)"

jq '.approved=false | .stage="implement"' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
eq "other stages do not block"           "0" "$(gate Edit "$SB/src/a.js" enforce)"

jq '.stage="review-plan"' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
echo 'broken{' > .claude/workflow/MA-100/state.json
eq "fail-open with a corrupt state"      "0" "$(gate Edit "$SB/src/a.js" enforce)"

NOWF="$(mktemp -d)"; git -C "$NOWF" init -q .
eq "project without a workflow: stays out" "0" \
   "$(echo "{\"tool_name\":\"Edit\",\"cwd\":\"$NOWF\",\"tool_input\":{\"file_path\":\"$NOWF/x.js\"}}" | \
      WF_GATE=enforce bash "$G" >/dev/null 2>&1; echo $?)"

echo "═══ update notice (wf-lib) ═══"
# Lives here rather than in a hook because a SessionStart hook fires but its
# stdout never reaches the terminal — an unseen notice is not a notice.
VH="$(mktemp -d)"; mkdir -p "$VH/.claude/workflow"
FAKE="$(mktemp -d)"; git init -q "$FAKE"; echo "9.9.9" > "$FAKE/VERSION"
jq -n --arg p "$FAKE" '{repo_path:$p, installed_version:"0.0.1"}' > "$VH/.claude/workflow/config.json"

OUT="$(HOME="$VH" "$S/wf-lib.sh" version-notice 2>&1)"
has "warns when installed is behind the repo" "v9.9.9 available (v0.0.1 installed)" "$OUT"

jq '.installed_version="9.9.9"' "$VH/.claude/workflow/config.json" > "$VH/c" && mv "$VH/c" "$VH/.claude/workflow/config.json"
OUT="$(HOME="$VH" "$S/wf-lib.sh" version-notice 2>&1)"
eq "silent when up to date"          "" "$OUT"

OUT="$(HOME="$VH" WF_VERSION_CHECK=off "$S/wf-lib.sh" version-notice 2>&1)"
eq "silent when disabled"            "" "$OUT"

# Fail-silent: this runs at the top of every stage command, so a broken global
# config must never produce noise, let alone a non-zero exit.
echo 'not json' > "$VH/.claude/workflow/config.json"
OUT="$(HOME="$VH" "$S/wf-lib.sh" version-notice 2>&1)"; RC=$?
eq "silent on corrupt global config"  "" "$OUT"
eq "exit 0 on corrupt global config"  "0" "$RC"

OUT="$(HOME="$VH/nope" "$S/wf-lib.sh" version-notice 2>&1)"
eq "silent with no global config"     "" "$OUT"

# repo_path pointing somewhere that no longer exists is a real case: the repo
# gets moved or deleted, and every stage command would start erroring.
jq -n '{repo_path:"/nonexistent/repo", installed_version:"0.0.1"}' > "$VH/.claude/workflow/config.json"
OUT="$(HOME="$VH" "$S/wf-lib.sh" version-notice 2>&1)"
eq "silent when repo_path is gone"    "" "$OUT"
rm -rf "$VH" "$FAKE"

echo ""
echo "═══════════════════════════"
echo "  ✅ $PASS   ❌ $FAIL"
cd /; rm -rf "$SB" "$NOWF" /tmp/wf-good.json
[ "$FAIL" -eq 0 ]
