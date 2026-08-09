#!/bin/bash
#
# Valida wf-lib.sh, wf-diff.sh, wf-checks.sh y wf-gate.sh contra un repo git
# temporal. No toca ningún proyecto real.
#
# Uso:  ./tests/test-scripts.sh

REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO/scripts"
SB="$(mktemp -d)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1 — obtuve: '$3', esperaba: '$2'"; FAIL=$((FAIL+1)); }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()  { if printf '%s' "$3" | grep -q "$2"; then ok "$1"; else bad "$1" "contiene $2" "$3"; fi; }

# --- repo de prueba --------------------------------------------------------
cd "$SB" || exit 1
SB="$(pwd -P)"   # en macOS /var es symlink a /private/var y git resuelve el real
git init -q -b develop .
git config user.email t@t.t; git config user.name t
mkdir -p .claude/workflow/MA-100 src
echo "base" > src/a.js
git add -A >/dev/null; git commit -qm "base"
git checkout -qb MA-100-feature
echo '{"activeTicket":"MA-100"}' > .claude/workflow/state.json
cat > .claude/workflow/config.json << 'EOF'
{ "base_branch": "develop",
  "checks": { "ok": "true", "falla": "echo 'boom' >&2; exit 1" } }
EOF
echo '{}' > .claude/workflow/MA-100/state.json

echo "═══ wf-lib ═══"
eq "wf_ticket"  "MA-100"  "$(bash "$S/wf-lib.sh" ticket)"
eq "wf_base (del config)" "develop" "$(bash "$S/wf-lib.sh" base)"
eq "wf_dir"     "$SB/.claude/workflow/MA-100" "$(bash "$S/wf-lib.sh" dir)"

bash "$S/wf-lib.sh" enter-stage analyze >/dev/null
eq "enter_stage escribe stage"      "analyze" "$(jq -r .stage .claude/workflow/MA-100/state.json)"
eq "enter_stage appendea completed" "analyze" "$(jq -r '.completed[0]' .claude/workflow/MA-100/state.json)"

bash "$S/wf-lib.sh" enter-stage analyze >/dev/null
eq "completed no duplica" "1" "$(jq -r '.completed | length' .claude/workflow/MA-100/state.json)"

# Campos que manejan los comandos no se pueden perder.
jq '.branch="MA-100-feature" | .notes="algo" | .iterations={"analyze":2}' \
   .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
bash "$S/wf-lib.sh" enter-stage review-plan >/dev/null
eq "preserva branch"      "MA-100-feature" "$(jq -r .branch .claude/workflow/MA-100/state.json)"
eq "preserva notes"       "algo"           "$(jq -r .notes .claude/workflow/MA-100/state.json)"
eq "preserva iterations"  "2"              "$(jq -r '.iterations.analyze' .claude/workflow/MA-100/state.json)"

OUT="$(bash "$S/wf-lib.sh" enter-stage refinement 2>&1)"; RC=$?
eq "stage inválido falla"           "1" "$RC"
has "stage inválido explica por qué" "vocabulario\|inválido" "$OUT"

cp .claude/workflow/MA-100/state.json /tmp/wf-good.json
echo 'roto{' > .claude/workflow/MA-100/state.json
bash "$S/wf-lib.sh" enter-stage test >/dev/null 2>&1
eq "no pisa un state corrupto" "roto{" "$(cat .claude/workflow/MA-100/state.json)"
cp /tmp/wf-good.json .claude/workflow/MA-100/state.json

echo "═══ wf-diff ═══"
echo "cambio" >> src/a.js; echo "nuevo" > src/b.js
git add -A >/dev/null; git commit -qm "feature"
# La base avanza DESPUÉS de crear el branch: el caso que rompe `base..HEAD`.
git checkout -q develop; echo "ajeno" > src/tercero.js
git add -A >/dev/null; git commit -qm "commit de otro"
git checkout -q MA-100-feature

FILES="$(bash "$S/wf-diff.sh" --files)"
has "incluye archivos del feature"  "src/b.js"       "$FILES"
if printf '%s' "$FILES" | grep -q "tercero"; then
  bad "excluye commits ajenos a la rama" "sin src/tercero.js" "$FILES"
else ok "excluye commits ajenos a la rama"; fi
has "--base reporta el rango"       "merge_base="    "$(bash "$S/wf-diff.sh" --base)"
has "--log lista commits del branch" "feature"       "$(bash "$S/wf-diff.sh" --log)"

mkdir -p src/__tests__; echo "test" > src/__tests__/a.test.js
git add -A >/dev/null; git commit -qm "tests"
W="$(bash "$S/wf-diff.sh" --weight)"
has "separa peso de tests" "weight_tests=1" "$W"
has "peso de producción aparte" "weight_prod=" "$W"

echo "═══ wf-checks ═══"
J="$(bash "$S/wf-checks.sh" --json)"
eq "detecta que hay checks"   "true"  "$(printf '%s' "$J" | jq -r .configured)"
eq "reporta el fallo global"  "false" "$(printf '%s' "$J" | jq -r .passed)"
eq "check que pasa"           "true"  "$(printf '%s' "$J" | jq -r '.results[] | select(.name=="ok") | .passed')"
has "captura el output del que falla" "boom" "$(printf '%s' "$J" | jq -r '.results[] | select(.name=="falla") | .output')"
bash "$S/wf-checks.sh" >/dev/null 2>&1
eq "exit 1 si alguno falla" "1" "$?"

jq 'del(.checks)' .claude/workflow/config.json > t && mv t .claude/workflow/config.json
bash "$S/wf-checks.sh" >/dev/null 2>&1
eq "exit 2 sin checks configurados" "2" "$?"

echo "═══ wf-gate ═══"
G="$REPO/hooks/wf-gate.sh"
gate() { echo "{\"tool_name\":\"$1\",\"cwd\":\"$SB\",\"tool_input\":{\"file_path\":\"$2\"}}" | \
         WF_GATE="${3:-observe}" HOME="$SB" bash "$G" >/dev/null 2>&1; echo $?; }

jq '.stage="review-plan" | .approved=false' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
eq "observe no bloquea"                 "0" "$(gate Edit "$SB/src/a.js" observe)"
eq "enforce bloquea en review-plan"     "2" "$(gate Edit "$SB/src/a.js" enforce)"
eq "enforce permite .claude/workflow"   "0" "$(gate Edit "$SB/.claude/workflow/MA-100/plan.md" enforce)"
eq "enforce permite docs/"              "0" "$(gate Edit "$SB/docs/x.md" enforce)"
eq "no aplica a Read"                   "0" "$(gate Read "$SB/src/a.js" enforce)"
eq "WF_GATE=off nunca bloquea"          "0" "$(gate Edit "$SB/src/a.js" off)"

jq '.approved=true' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
eq "aprobado deja pasar"                "0" "$(gate Edit "$SB/src/a.js" enforce)"

jq '.approved=false | .stage="implement"' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
eq "otras etapas no bloquean"           "0" "$(gate Edit "$SB/src/a.js" enforce)"

jq '.stage="review-plan"' .claude/workflow/MA-100/state.json > t && mv t .claude/workflow/MA-100/state.json
echo 'roto{' > .claude/workflow/MA-100/state.json
eq "fail-open con state corrupto"       "0" "$(gate Edit "$SB/src/a.js" enforce)"

NOWF="$(mktemp -d)"; git -C "$NOWF" init -q .
eq "proyecto sin workflow: no interviene" "0" \
   "$(echo "{\"tool_name\":\"Edit\",\"cwd\":\"$NOWF\",\"tool_input\":{\"file_path\":\"$NOWF/x.js\"}}" | \
      WF_GATE=enforce bash "$G" >/dev/null 2>&1; echo $?)"

echo ""
echo "═══════════════════════════"
echo "  ✅ $PASS   ❌ $FAIL"
cd /; rm -rf "$SB" "$NOWF" /tmp/wf-good.json
[ "$FAIL" -eq 0 ]
