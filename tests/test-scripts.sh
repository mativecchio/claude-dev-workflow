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

Z="$(bash "$S/wf-diff.sh" --size 2>/dev/null)"; ZX=$?
P0="$(printf '%s\n' "$Z" | sed -n 's/^weight_prod=//p')"
F0="$(printf '%s\n' "$Z" | sed -n 's/^files_prod=//p')"
T0="$(printf '%s\n' "$Z" | sed -n 's/^weight_tests=//p')"
has "--size reports production files" "files_prod=" "$Z"
has "--size defaults to 400 lines"   "max_prod_lines=400" "$Z"
eq  "--size under the limit exits 0" "0" "$ZX"

mkdir -p src/locales/es src/fixtures
seq 1 900 > src/locales/es/translation.json; seq 1 900 > src/fixtures/big.js
git add -A >/dev/null; git commit -qm "translations and fixtures"
Z="$(bash "$S/wf-diff.sh" --size 2>/dev/null)"
eq "translations do not count"          "weight_prod=$P0 files_prod=$F0" \
   "$(printf '%s\n' "$Z" | grep -E '^(weight_prod|files_prod)=' | paste -sd' ' -)"
eq "fixtures go with the tests"         "weight_tests=$((T0 + 900))" "$(printf '%s\n' "$Z" | grep '^weight_tests=')"

seq 1 401 > src/big.js; git add -A >/dev/null; git commit -qm "big"
Z="$(bash "$S/wf-diff.sh" --size)"; ZX=$?
has "--size reports over" "over=true" "$Z"
eq  "--size over the limit exits 3" "3" "$ZX"
jq '.mr_size={"max_prod_lines":1000,"max_prod_files":10}' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
bash "$S/wf-diff.sh" --size >/dev/null; eq "the project's mr_size wins" "0" "$?"
jq 'del(.mr_size)' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
git rm -q -r src/big.js src/locales src/fixtures >/dev/null; git commit -qm "drop size fixtures"

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
rm -f .claude/workflow/MA-100/plan.md
eq "implement without a plan: no block"  "0" "$(gate Edit "$SB/src/a.js" enforce)"

printf '# Plan\n\n## Files to modify/create\n| File | Change | Reason |\n|---|---|---|\n| src/a.js | new | x |\n\n## Suggested implementation order\n1. a\n' \
  > .claude/workflow/MA-100/plan.md
eq "implement, files but no Responsibilities: blocks" "2" "$(gate Edit "$SB/src/a.js" enforce)"
eq "implement, no Responsibilities, observe: passes"  "0" "$(gate Edit "$SB/src/a.js" observe)"
eq "implement, no Responsibilities: plan.md editable"  "0" "$(gate Edit "$SB/.claude/workflow/MA-100/plan.md" enforce)"
eq "the would-block event names its reason" "1" \
   "$(grep -c '"event":"gate_would_block".*"reason":"no-responsibilities"' "$SB/.claude/workflow/events.jsonl")"

printf '\n## Responsibilities\nApproach: x\n\n| File | Its one responsibility | New functions / hooks it holds | Why here |\n|---|---|---|---|\n' \
  >> .claude/workflow/MA-100/plan.md
eq "an empty Responsibilities table still blocks" "2" "$(gate Edit "$SB/src/a.js" enforce)"
printf '| src/a.js | storage of the tab state | readA | R3 |\n' >> .claude/workflow/MA-100/plan.md
eq "a filled Responsibilities table lets it through" "0" "$(gate Edit "$SB/src/a.js" enforce)"

printf '# Plan\n\n## Files to modify/create\n| File | Change | Reason |\n|---|---|---|\n' > .claude/workflow/MA-100/plan.md
eq "a plan with no files to place: no block" "0" "$(gate Edit "$SB/src/a.js" enforce)"
rm -f .claude/workflow/MA-100/plan.md

jq '.stage="test"' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
eq "other stages do not block"           "0" "$(gate Edit "$SB/src/a.js" enforce)"

jq '.stage="review-plan"' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
echo 'broken{' > .claude/workflow/MA-100/state.json
eq "fail-open with a corrupt state"      "0" "$(gate Edit "$SB/src/a.js" enforce)"

NOWF="$(mktemp -d)"; git -C "$NOWF" init -q .
eq "project without a workflow: stays out" "0" \
   "$(echo "{\"tool_name\":\"Edit\",\"cwd\":\"$NOWF\",\"tool_input\":{\"file_path\":\"$NOWF/x.js\"}}" | \
      WF_GATE=enforce bash "$G" >/dev/null 2>&1; echo $?)"

echo "═══ wf-shape ═══"
H="$REPO/hooks/wf-shape.sh"
shape() { echo "{\"tool_name\":\"${3:-Edit}\",\"cwd\":\"$SB\",\"tool_input\":{\"file_path\":\"$1\"}}" | \
          HOME="$SB" WF_SHAPE="${2:-on}" bash "$H" >/dev/null 2>&1; echo $?; }
lines() { seq 1 "$2" > "$1"; }

lines src/grow.js 10; git add src/grow.js >/dev/null; git commit -qm grow
lines src/grow.js 300
eq "at the limit: silent"                      "0" "$(shape "$SB/src/grow.js")"
lines src/grow.js 301
eq "crossing the limit: speaks"                "2" "$(shape "$SB/src/grow.js")"
eq "the warning is recorded as an event"       "1" "$(grep -c '"event":"shape_warning".*"file":"src/grow.js"' "$SB/.claude/workflow/events.jsonl")"
lines src/grow.js 330
eq "growing a little more: silent"             "0" "$(shape "$SB/src/grow.js")"
lines src/grow.js 351
eq "another step past the warning: speaks"     "2" "$(shape "$SB/src/grow.js")"

lines src/legacy.js 400; git add src/legacy.js >/dev/null; git commit -qm legacy
lines src/legacy.js 420
eq "big at HEAD, small growth: silent"         "0" "$(shape "$SB/src/legacy.js")"
lines src/legacy.js 450
eq "big at HEAD, grows a step: speaks"         "2" "$(shape "$SB/src/legacy.js")"

mkdir -p src/tests; lines src/tests/huge.test.js 900
eq "tests are not production"                  "0" "$(shape "$SB/src/tests/huge.test.js")"
lines src/notes.md 900
eq "non-code files are ignored"                "0" "$(shape "$SB/src/notes.md")"
lines src/new.ts 500
eq "WF_SHAPE=off stays quiet"                  "0" "$(shape "$SB/src/new.ts" off)"
eq "a new file over the limit speaks"          "2" "$(shape "$SB/src/new.ts")"
eq "Read is not its business"                  "0" "$(shape "$SB/src/new.ts" on Read)"

jq '.max_file_lines=1000' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
lines src/configured.ts 600
eq "the project's max_file_lines wins"         "0" "$(shape "$SB/src/configured.ts")"
jq 'del(.max_file_lines)' .claude/workflow/config.json > t && mv t .claude/workflow/config.json

NOWF2="$(mktemp -d)"; git -C "$NOWF2" init -q .; seq 1 900 > "$NOWF2/x.js"
eq "project without a workflow: stays out"     "0" \
   "$(echo "{\"tool_name\":\"Edit\",\"cwd\":\"$NOWF2\",\"tool_input\":{\"file_path\":\"$NOWF2/x.js\"}}" | \
      HOME="$SB" bash "$H" >/dev/null 2>&1; echo $?)"
rm -rf "$NOWF2" src/grow.js src/legacy.js src/tests src/notes.md src/new.ts src/configured.ts
git rm -q --cached src/grow.js src/legacy.js >/dev/null 2>&1; git commit -qm "drop shape fixtures" >/dev/null 2>&1

echo "═══ model selection ═══"
# The gate section deliberately left a corrupt state behind; restore it so
# enter-stage can write (it correctly refuses to touch unparseable JSON).
cp /tmp/wf-good.json .claude/workflow/MA-100/state.json
# The four Agent-spawning stages used to pass no model, so the agent inherited
# the session's — making plan.md a product of an unrelated setting.
eq "analyze defaults to opus"       "opus" "$(bash "$S/wf-lib.sh" model analyze)"
eq "review-plan defaults to opus"   "opus" "$(bash "$S/wf-lib.sh" model review-plan)"
eq "validate defaults to opus"      "opus" "$(bash "$S/wf-lib.sh" model validate)"
eq "mr-review defaults to opus"     "opus" "$(bash "$S/wf-lib.sh" model mr-review)"

# Bounded transformation with a checkable result: sonnet is adequate, and
# delegating also keeps the diff out of the session's context window.
eq "mr-desc defaults to sonnet"     "sonnet" "$(bash "$S/wf-lib.sh" model mr-desc)"
eq "commit defaults to sonnet"      "sonnet" "$(bash "$S/wf-lib.sh" model commit)"
eq "test defaults to sonnet"        "sonnet" "$(bash "$S/wf-lib.sh" model test)"

# Stages that run in the user's session have no model to choose.
bash "$S/wf-lib.sh" model implement >/dev/null 2>&1
eq "main-context stage has no model" "1" "$?"

jq '.models={"validate":"sonnet"}' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
eq "config overrides the default"   "sonnet" "$(bash "$S/wf-lib.sh" model validate)"
eq "unconfigured stage keeps default" "opus" "$(bash "$S/wf-lib.sh" model analyze)"
eq "WF_MODEL overrides everything"  "haiku"  "$(WF_MODEL=haiku bash "$S/wf-lib.sh" model validate)"

# A typo must not silently route a stage somewhere unintended.
jq '.models={"analyze":"gtp-4"}' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
eq "unknown model falls back to opus" "opus" "$(bash "$S/wf-lib.sh" model analyze 2>/dev/null)"
has "unknown model warns"  "unknown model" "$(bash "$S/wf-lib.sh" model analyze 2>&1 >/dev/null)"

jq 'del(.models)' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
# HOME is redirected so the update notice — which reads the real global config —
# can't leak into this assertion. A suite must not depend on the machine it runs on.
bash "$S/wf-lib.sh" enter-stage analyze >/dev/null
has "context exposes the model" "model=opus" "$(HOME="$SB/nohome" bash "$S/wf-lib.sh" context)"

echo "═══ implement advice ═══"
# Conservative by construction: anything missing means "stay on the strong
# model". Advising a downgrade on an unverified plan is the worse failure.
adv() { bash "$S/wf-lib.sh" implement-advice | sed -n '1s/recommended_model=//p'; }
CX=.claude/workflow/MA-100/complexity.json

jq '.approved=true' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
rm -f "$CX"
eq "no estimate → strong model"        "opus" "$(adv)"

echo '{"points":2,"dimensions":{"sister_feature":{"value":"found"}}}' > "$CX"
eq "simple + sister + approved → sonnet" "sonnet" "$(adv)"

echo '{"points":2,"dimensions":{"sister_feature":{"value":"none"}}}' > "$CX"
eq "no sister feature → strong model"  "opus" "$(adv)"

echo '{"points":8,"dimensions":{"sister_feature":{"value":"found"}}}' > "$CX"
eq "high complexity → strong model"    "opus" "$(adv)"

echo '{"points":2,"dimensions":{"sister_feature":{"value":"found"}}}' > "$CX"
jq '.approved=false' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
eq "plan not approved → strong model"  "opus" "$(adv)"

echo 'broken{' > "$CX"
jq '.approved=true' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
eq "corrupt complexity.json → strong model" "opus" "$(adv)"
has "advice explains itself" "reason=" "$(bash "$S/wf-lib.sh" implement-advice)"
rm -f "$CX"

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

# Every way into the pipeline has to surface the notice, or it reaches nobody:
# `/wf` and `/wf-refine` run before a ticket exists and call `version-notice`
# directly, the rest inherit it from `context`. This asserts the wiring in the
# command files, which is the part a refactor silently drops.
for c in wf wf-refine wf-analyze wf-review-plan wf-implement wf-validate wf-test wf-mr-desc wf-mr-review wf-retro; do
  if grep -qE 'wf-lib\.sh (context|version-notice)' "$REPO/commands/$c.md"; then
    ok "/$c surfaces the update notice"
  else
    bad "/$c surfaces the update notice" "a context or version-notice call" "neither"
  fi
done

echo ""
echo "═══ stage vocabulary ═══"
# `commit` carries a model default without being a pipeline stage; validating
# model lookups against WF_STAGES alone used to reject it.
eq "commit resolves a model without being a stage" "sonnet" "$(bash "$S/wf-lib.sh" model commit 2>/dev/null)"
bash "$S/wf-lib.sh" model implement >/dev/null 2>&1
eq "a stage with no agent exits 1, silently" "1" "$?"
eq "a stage with no agent prints nothing" "" "$(bash "$S/wf-lib.sh" model implement 2>/dev/null)"
bash "$S/wf-lib.sh" model testing >/dev/null 2>&1
eq "an unknown stage exits 2" "2" "$?"
has "an unknown stage suggests the closest one" "Did you mean 'test'" "$(bash "$S/wf-lib.sh" model testing 2>&1)"
has "separators are ignored when suggesting" "Did you mean 'mr-review'" "$(bash "$S/wf-lib.sh" enter-stage mrreview 2>&1)"
eq "a name close to nothing gets no suggestion" "" "$(bash "$S/wf-lib.sh" enter-stage zzz 2>&1 | grep -o "Did you mean")"
bash "$S/wf-lib.sh" set-state stage '"testing"' >/dev/null 2>&1
eq "set-state refuses an invalid stage" "1" "$?"
eq "set-state left the state untouched" "analyze" "$(bash "$S/wf-lib.sh" state '.stage')"

echo "═══ related_projects ═══"
mkdir -p "$SB/../sibling" && (cd "$SB/../sibling" && git init -q . && git remote add origin git@x:g/sibling.git)
jq '.related_projects=[{"name":"sibling","path":"../sibling"}]' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
has "a resolvable entry is reported" "related_project=sibling" "$(bash "$S/wf-lib.sh" related-check 2>&1)"
bash "$S/wf-lib.sh" related-check >/dev/null 2>&1
eq "a valid config exits 0" "0" "$?"
jq '.related_projects=["https://example.com/org/repo"]' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
has "a URL entry is rejected, not skipped" "not an object" "$(bash "$S/wf-lib.sh" related-check 2>&1)"
bash "$S/wf-lib.sh" related-check >/dev/null 2>&1
eq "a malformed config exits 1" "1" "$?"
jq '.related_projects=[{"name":"nopath"}]' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
has "an entry with no path is rejected" 'has no' "$(bash "$S/wf-lib.sh" related-check 2>&1)"
jq '.related_projects=[{"name":"sibling","path":"../does-not-exist"}]' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
has "a broken path is reported" "DOES NOT RESOLVE" "$(bash "$S/wf-lib.sh" related-check 2>&1)"
jq '.related_projects=[{"name":"wrongname","path":"../sibling"}]' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
has "a path pointing at another repo is caught" "DIFFERENT repo" "$(bash "$S/wf-lib.sh" related-check 2>&1)"

echo "═══ ticket repo ownership ═══"
jq '.related_projects=[{"name":"sibling","path":"../sibling"}]' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
# The guard compares this checkout's identity against the ticket's `repo`, so it
# is deliberately inert until the repo has an origin to be identified by.
bash "$S/wf-lib.sh" repo-check >/dev/null 2>&1
eq "without an origin the guard stays silent" "0" "$?"
git remote add origin "git@x:g/$(basename "$SB").git"
jq --arg n "$(basename "$SB")" '.related_projects=[{"name":"sibling","path":"../sibling"}]' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
bash "$S/wf-lib.sh" repo-check >/dev/null 2>&1
eq "a ticket with no repo field is fine" "0" "$?"
jq '.repo="sibling"' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
bash "$S/wf-lib.sh" repo-check >/dev/null 2>&1
eq "a ticket belonging elsewhere is refused" "1" "$?"
has "the refusal names the relocate command" "relocate MA-100" "$(bash "$S/wf-lib.sh" repo-check 2>&1)"
bash "$S/wf-lib.sh" enter-stage implement >/dev/null 2>&1
eq "enter-stage refuses a misfiled ticket" "1" "$?"
eq "the refused stage was not written" "analyze" "$(bash "$S/wf-lib.sh" state '.stage')"
jq '.repo="ghost"' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
has "a repo absent from config is refused on that ground" "related_project in config.json" "$(bash "$S/wf-lib.sh" repo-check 2>&1)"

echo "═══ relocate ═══"
jq '.repo="sibling"' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
TMPBEFORE="$(ls /tmp/tmp.* 2>/dev/null | wc -l)"
# Destination state.json is corrupt, so the adopt step must fail.
mkdir -p "$SB/../sibling/.claude/workflow"
printf 'not json{{' > "$SB/../sibling/.claude/workflow/state.json"
OUT="$(bash "$S/wf-lib.sh" relocate 2>&1)"; RC=$?
eq "a half-done relocate exits non-zero" "1" "$RC"
has "it says the move happened" "moved" "$OUT"
has "it names what is left by hand" "by hand" "$OUT"
eq "it does not claim the ticket is ready" "" "$(printf '%s' "$OUT" | grep -o 'from now on')"
eq "the directory did move" "yes" "$([ -d "$SB/../sibling/.claude/workflow/MA-100" ] && echo yes || echo no)"
eq "no temp file was leaked" "$TMPBEFORE" "$(ls /tmp/tmp.* 2>/dev/null | wc -l)"
# Now the happy path. The failed run correctly cleared the pointer here before
# it hit the corrupt destination, so put both the directory and the pointer back.
mv "$SB/../sibling/.claude/workflow/MA-100" .claude/workflow/MA-100
echo '{"activeTicket":"MA-100"}' > .claude/workflow/state.json
echo '{}' > "$SB/../sibling/.claude/workflow/state.json"
OUT="$(bash "$S/wf-lib.sh" relocate 2>&1)"; RC=$?
eq "a clean relocate exits 0" "0" "$RC"
has "it says where to work from now on" "from now on" "$OUT"
eq "the destination adopted the ticket" "MA-100" "$(jq -r .activeTicket "$SB/../sibling/.claude/workflow/state.json")"
eq "the origin dropped its pointer" "" "$(jq -r '.activeTicket // empty' .claude/workflow/state.json)"
rm -rf "$SB/../sibling"

echo "═══ wf-clip ═══"
cat > clip.md << 'EOF'
## Ticket title

### Section
Two lines with `a <b>`, **bold**, *italic*, snake_case and
a [link](https://x.y/?a=1&b=2), plus https://x.y/z.

- [ ] open task
- [x] done task
- parent
  - child
    continued

1. first

```json
{ "k": 1 }
```

| A | B |
|---|---|
| `c` | d |
EOF
HTML="$(bash "$S/wf-clip.sh" --html clip.md 2>/dev/null)"
has "headings become h tags"         "<h2>Ticket title</h2>" "$HTML"
has "lines join into one paragraph"  "snake_case and a <a" "$HTML"
has "code spans are escaped"         "<code>a &lt;b&gt;</code>" "$HTML"
has "bold and italic"                "<strong>bold</strong>, <em>italic</em>" "$HTML"
has "links keep their query string"  'href="https://x.y/?a=1&amp;b=2">link</a>' "$HTML"
has "bare URLs are linked"           '<a href="https://x.y/z">https://x.y/z</a>.' "$HTML"
has "task boxes"                     "☐ open task" "$HTML"
has "checked task boxes"             "☑ done task" "$HTML"
has "nested list with continuation"  "child continued" "$HTML"
has "ordered list"                   "<ol><li>" "$HTML"
has "fenced code block"              '<pre><code>{ "k": 1 }</code></pre>' "$HTML"
has "table header"                   "<th>A</th><th>B</th>" "$HTML"
has "table cell keeps inline code"   "<td><code>c</code></td>" "$HTML"
eq  "lists are balanced" "$(printf '%s' "$HTML" | grep -o '<ul>' | wc -l)" "$(printf '%s' "$HTML" | grep -o '</ul>' | wc -l)"
TITLE="$(bash "$S/wf-clip.sh" --html --drop-title clip.md 2>&1 >/dev/null)"
HTML="$(bash "$S/wf-clip.sh" --html --drop-title clip.md 2>/dev/null)"
has "--drop-title reports the title" "Ticket title" "$TITLE"
eq  "--drop-title leaves it out"     "" "$(printf '%s' "$HTML" | grep -o '<h2>')"
eq  "stdin works" "<p>hi</p>" "$(printf 'hi\n' | bash "$S/wf-clip.sh" --html - | sed 's/<meta charset="utf-8">//')"
bash "$S/wf-clip.sh" --html missing.md >/dev/null 2>&1
eq  "a missing file exits 1" "1" "$?"
OUT="$(env -u WAYLAND_DISPLAY -u DISPLAY PATH=/usr/bin:/bin bash "$S/wf-clip.sh" clip.md 2>&1)"; RC=$?
if command -v pbcopy >/dev/null 2>&1; then
  ok "no clipboard check skipped (pbcopy present)"
else
  eq  "no clipboard tool exits 1" "1" "$RC"
  has "it suggests --html" "\-\-html" "$OUT"
fi
rm -f clip.md

echo "═══════════════════════════"
echo "  ✅ $PASS   ❌ $FAIL"
cd /; rm -rf "$SB" "$NOWF" /tmp/wf-good.json
[ "$FAIL" -eq 0 ]
