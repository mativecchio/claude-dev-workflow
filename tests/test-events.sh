#!/bin/bash
#
# Tests for wf-event.sh and wf-stats.sh against a temp repo and a synthetic
# events file. Never touches the real ~/.claude/workflow/events.jsonl.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; echo "     $2"; FAIL=$((FAIL+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "esperaba '$3', obtuve '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "no encontré '$3' en: $(echo "$2"|head -3)";; esac; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export WF_EVENTS_FILE="$TMP/events.jsonl"

echo "═══ wf-event.sh ═══"

# Un repo git con ticket activo, que es el contexto que el script deduce solo.
PROJ="$TMP/proj"; mkdir -p "$PROJ/.claude/workflow/T-1"
cd "$PROJ" || exit 1
git init -q . 2>/dev/null
echo '{"activeTicket":"T-1"}' > .claude/workflow/state.json
echo '{"stage":"review-plan"}'  > .claude/workflow/T-1/state.json

# wf-event escribe a $HOME/.claude/workflow/events.jsonl, no a WF_EVENTS_FILE:
# se aísla con un HOME propio para no tocar el real.
export HOME="$TMP/home"; mkdir -p "$HOME/.claude/workflow"
EV="$HOME/.claude/workflow/events.jsonl"

E="$REPO/scripts/wf-event.sh"

"$E" finding --category logic --severity high --stage_origin analyze \
     --detected_by gate --summary "guard faltante" >/dev/null 2>&1
check "finding se escribe" "$(wc -l < "$EV" | tr -d ' ')" "1"

L="$(tail -1 "$EV")"
check "ticket deducido del state"  "$(echo "$L" | jq -r '.ticket')" "T-1"
check "stage deducido del state"   "$(echo "$L" | jq -r '.stage')"  "review-plan"
check "source=command"             "$(echo "$L" | jq -r '.source')" "command"
check "project = basename del repo" "$(echo "$L" | jq -r '.project')" "proj"
check "data.category"              "$(echo "$L" | jq -r '.data.category')" "logic"
check "línea es JSON válido"       "$(echo "$L" | jq -e . >/dev/null 2>&1 && echo ok)" "ok"

# Tipado: los números tienen que quedar números, no strings, o las medias
# de wf-stats se rompen sin avisar.
"$E" complexity_estimate --raw_score 21 --points 8 --split_recommended true >/dev/null 2>&1
L="$(tail -1 "$EV")"
check "número queda número"   "$(echo "$L" | jq -r '.data.points|type')" "number"
check "booleano queda booleano" "$(echo "$L" | jq -r '.data.split_recommended|type')" "boolean"

# Un summary numérico NO debe convertirse en número si es texto con espacios.
"$E" finding --category x --severity low --stage_origin refine \
     --detected_by user --summary "8 archivos afectados" >/dev/null 2>&1
check "string con número queda string" "$(tail -1 "$EV" | jq -r '.data.summary|type')" "string"

# Errores de uso
"$E" evento_inexistente >/dev/null 2>&1; check "evento desconocido → exit 1" "$?" "1"
"$E" finding --category solo >/dev/null 2>&1; check "faltan requeridos → exit 1" "$?" "1"
N_BEFORE="$(wc -l < "$EV" | tr -d ' ')"
"$E" finding --category solo >/dev/null 2>&1
check "un evento inválido no escribe nada" "$(wc -l < "$EV" | tr -d ' ')" "$N_BEFORE"

# Sin ticket activo: exit 2, sin escribir.
rm -f "$PROJ/.claude/workflow/state.json"
"$E" finding --category a --severity b --stage_origin refine --detected_by user --summary s >/dev/null 2>&1
check "sin ticket → exit 2" "$?" "2"
check "sin ticket no escribe" "$(wc -l < "$EV" | tr -d ' ')" "$N_BEFORE"
echo '{"activeTicket":"T-1"}' > "$PROJ/.claude/workflow/state.json"

# Override explícito de etapa
"$E" finding --_stage implement --category c --severity low \
     --stage_origin refine --detected_by user --summary s >/dev/null 2>&1
check "--_stage overridea" "$(tail -1 "$EV" | jq -r '.stage')" "implement"

echo
echo "═══ wf-stats.sh ═══"
S="$REPO/scripts/wf-stats.sh"

# Archivo vacío: informa, no falla.
: > "$WF_EVENTS_FILE"
OUT="$("$S" 2>&1)"; check "vacío → exit 0" "$?" "0"
has "vacío se informa" "$OUT" "vacío o inexistente"

cat > "$WF_EVENTS_FILE" <<'EOF'
{"ts":"2026-08-01T10:00:00Z","project":"p","ticket":"A-1","stage":"analyze","event":"complexity_estimate","source":"command","data":{"points":8,"dimensions":{"sister_feature":{"value":"none"}}}}
{"ts":"2026-08-01T11:00:00Z","project":"p","ticket":"A-1","stage":"review-plan","event":"finding","source":"command","data":{"category":"guard","severity":"high","stage_origin":"analyze","stage_detected":"review-plan","detected_by":"gate","summary":"x"}}
{"ts":"2026-08-01T12:00:00Z","project":"p","ticket":"A-1","stage":"mr-review","event":"finding","source":"command","data":{"category":"guard","severity":"high","stage_origin":"analyze","stage_detected":"mr-review","detected_by":"user","summary":"y"}}
{"ts":"2026-08-01T13:00:00Z","project":"p","ticket":"A-1","stage":"retro","event":"ticket_closed","source":"command","data":{"iterations_total":5,"complexity_actual":13}}
{"ts":"2026-08-02T11:00:00Z","project":"p","ticket":"A-2","stage":"validate","event":"finding","source":"command","data":{"category":"guard","severity":"medium","stage_origin":"implement","stage_detected":"validate","detected_by":"gate","summary":"z"}}
{"ts":"2026-08-03T10:00:00Z","project":"q","ticket":"A-3","stage":"validate","event":"finding","source":"command","data":{"category":"guard","severity":"low","stage_origin":"analyze","stage_detected":"validate","detected_by":"gate","summary":"w"}}
{"ts":"2026-08-04T10:00:00Z","project":"p","ticket":"A-4","stage":"implement","event":"stage_reentry","source":"hook","data":{"iteration_n":3}}
esto no es json
EOF

OUT="$("$S" origins 2>&1)"
has "Q1 agrupa por stage_origin" "$OUT" "analyze: 3 findings, 2 tickets"
has "Q1 cuenta severidad alta"   "$OUT" "2 severidad alta"
has "Q1 con 3 tickets cumple §0"  "$OUT" "cumple el mínimo"

# Fuga: analyze→review-plan = 1, analyze→mr-review = 6, analyze→validate = 3 ⇒ 3.33
OUT="$("$S" leak 2>&1)"
has "Q2 calcula fuga media" "$OUT" "analyze: fuga media 3.33"
has "Q2 reporta el máximo"  "$OUT" "máx 6"

OUT="$("$S" detection 2>&1)"
has "Q3 separa gate de user" "$OUT" "gate: 3   user: 1"
has "Q3 calcula el ratio"    "$OUT" "ratio user: 25%"

OUT="$("$S" calibration 2>&1)"
has "Q4 arma el par est/real" "$OUT" "A-1: est 8 → real 13"
has "Q4 marca muestra chica"  "$OUT" "por debajo del mínimo"

OUT="$("$S" categories 2>&1)"
has "Q7 marca categoría con 3+ tickets" "$OUT" "✅ guard: 3 tickets"

OUT="$("$S" coverage 2>&1)"
has "salud cuenta líneas ilegibles"   "$OUT" "ilegibles: 1"
has "salud detecta reentrada huérfana" "$OUT" "1 sin ningún finding"

# Una línea corrupta no puede tumbar el resto del historial.
OUT="$("$S" origins 2>&1)"
has "línea corrupta no rompe la consulta" "$OUT" "analyze: 3 findings"

# Filtros
OUT="$("$S" origins --ticket A-1 2>&1)"
has "--ticket filtra" "$OUT" "analyze: 2 findings, 1 tickets"
OUT="$("$S" origins --project q 2>&1)"
has "--project filtra" "$OUT" "analyze: 1 findings"
OUT="$("$S" origins --since 2026-08-03 2>&1)"
has "--since filtra" "$OUT" "analyze: 1 findings"

# El summary tiene que correr entero sin errores de jq.
OUT="$("$S" 2>&1)"
if echo "$OUT" | grep -qi "jq: error\|syntax error\|unbound variable"; then
  bad "summary corre limpio" "$(echo "$OUT" | grep -i 'error' | head -2)"
else ok "summary corre limpio"; fi

OUT="$("$S" no_existe 2>&1)"; check "subcomando inválido → exit 1" "$?" "1"

echo
echo "═══════════════════════════"
echo "  ✅ $PASS   ❌ $FAIL"
[ "$FAIL" -eq 0 ]
