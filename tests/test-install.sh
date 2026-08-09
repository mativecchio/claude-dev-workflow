#!/bin/bash
#
# Valida install.sh contra un HOME sandbox. Nunca toca el ~/.claude real.
#
# Uso:  ./tests/test-install.sh
#
# Cubre los modos de falla que motivaron la Fase 0 de la migración a harness
# (docs/plan-harness-migration.md): comandos huérfanos, config global que
# nunca recibía repo_path, y el bloque de CLAUDE.md que quedaba congelado.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

echo "═══ CASO 1 — instalación limpia ═══"
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1 || echo "  (install devolvió $?)"
C="$SB/.claude"
check "comandos instalados (15)"        "[ \$(ls $C/commands/wf*.md | wc -l) -eq 15 ]"
check "wf-commit.md instalado"          "[ -f $C/commands/wf-commit.md ]"
check "wf-deploy.md instalado"          "[ -f $C/commands/wf-deploy.md ]"
check "improvements.md creado"          "[ -s $C/workflow/improvements.md ]"
check "repo_path escrito"               "[ \"\$(jq -r .repo_path $C/workflow/config.json)\" = \"$REPO\" ]"
check "hook de telemetría copiado"      "[ -x $C/hooks/wf-telemetry.sh ]"
check "hooks registrados en settings"   "[ \$(jq '[.hooks[][].hooks[].command] | map(select(contains(\"wf-telemetry\"))) | length' $C/settings.json) -eq 4 ]"
check "CLAUDE.md lista wf-deploy"       "grep -q 'wf-deploy' $C/CLAUDE.md"
check "CLAUDE.md lista wf-init"         "grep -q 'wf-init' $C/CLAUDE.md"

echo "═══ CASO 2 — --check tras instalar limpio ═══"
OUT="$(HOME="$SB" "$REPO/install.sh" --check 2>&1)"; RC=$?
check "--check sale 0"                  "[ $RC -eq 0 ]"
check "--check reporta sin divergencias" "echo \"\$OUT\" | grep -q 'Sin divergencias'"

echo "═══ CASO 3 — config global preexistente SIN repo_path (el caso real) ═══"
echo '{"preferences":{"language":"es"},"mi_dato":42}' > "$C/workflow/config.json"
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1
check "repo_path se mergeó"             "[ \"\$(jq -r .repo_path $C/workflow/config.json)\" = \"$REPO\" ]"
check "claves preexistentes preservadas" "[ \$(jq -r .mi_dato $C/workflow/config.json) -eq 42 ]"

echo "═══ CASO 4 — CLAUDE.md con bloque viejo + contenido propio ═══"
cat > "$C/CLAUDE.md" << 'EOD'
# Mis notas personales
Esto es contenido mío que NO se debe tocar.

<!-- claude-workflow -->
## Dev Workflow System
| `/wf-refine` | viejo |
<!-- /claude-workflow -->

## Otra sección mía
También debe sobrevivir.
EOD
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1
check "contenido previo preservado"     "grep -q 'contenido mío que NO se debe tocar' $C/CLAUDE.md"
check "contenido posterior preservado"  "grep -q 'También debe sobrevivir' $C/CLAUDE.md"
check "bloque regenerado (wf-deploy)"   "grep -q 'wf-deploy' $C/CLAUDE.md"
check "sin bloque duplicado"            "[ \$(grep -c '^<!-- claude-workflow -->' $C/CLAUDE.md) -eq 1 ]"
check "marcador de cierre único"        "[ \$(grep -c '^<!-- /claude-workflow -->' $C/CLAUDE.md) -eq 1 ]"

echo "═══ CASO 5 — settings.json con hooks ajenos ═══"
jq '.hooks.Stop += [{"hooks":[{"type":"command","command":"afplay /System/Library/Sounds/Ping.aiff"}]}]' \
   "$C/settings.json" > "$C/s.tmp" && mv "$C/s.tmp" "$C/settings.json"
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1
check "hook ajeno preservado"           "grep -q 'afplay' $C/settings.json"
check "telemetría sin duplicar"         "[ \$(jq '[.hooks[][].hooks[].command] | map(select(contains(\"wf-telemetry\"))) | length' $C/settings.json) -eq 4 ]"

echo "═══ CASO 6 — --check detecta huérfanos y divergencias ═══"
echo "# comando sin origen en el repo" > "$C/commands/wf-inventado.md"
echo "modificado" >> "$C/commands/wf-test.md"
OUT="$(HOME="$SB" "$REPO/install.sh" --check 2>&1)"; RC=$?
check "--check sale 1"                  "[ $RC -eq 1 ]"
check "detecta el huérfano"             "echo \"\$OUT\" | grep -q 'huérfano.*wf-inventado'"
check "detecta el divergente"           "echo \"\$OUT\" | grep -q 'difiere: wf-test.md'"

echo ""
echo "═══════════════════════════"
echo "  ✅ $PASS   ❌ $FAIL"
rm -rf "$SB"
[ "$FAIL" -eq 0 ]
