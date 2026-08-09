#!/bin/bash
#
# wf-diff — el diff del feature, calculado bien, en un solo lugar.
#
# Reemplaza el párrafo que estaba repetido en wf-validate, wf-mr-review y
# wf-mr-desc explicando por qué no usar `base..HEAD`. El motivo es real:
# si alguien avanza la base con un pull --ff-only después de crear el branch,
# el diff naive muestra cambios de terceros como si fueran del feature.
# La regla correcta es diffear contra merge-base(HEAD, base).
#
# Uso:
#   wf-diff.sh              diff completo
#   wf-diff.sh --stat       resumen
#   wf-diff.sh --files      solo paths (alimenta scope drift)
#   wf-diff.sh --log        commits del branch
#   wf-diff.sh --base       imprime la base detectada y el merge-base
#   wf-diff.sh --weight     peso de producción y de tests (brainstorm §6)
#
# Opcional: --branch <rama> para diffear otra rama en vez de HEAD.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$DIR/wf-lib.sh" ] && . "$DIR/wf-lib.sh"

MODE="${1:---full}"
REF="HEAD"
[ "${2:-}" = "--branch" ] && [ -n "${3:-}" ] && REF="$3"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "wf-diff: no es un repo git" >&2; exit 1; }

BASE="$(wf_base 2>/dev/null)"
[ -n "$BASE" ] || BASE="main"

MB="$(git merge-base "$REF" "$BASE" 2>/dev/null)"

# Sin merge-base (base inexistente) o sin commits propios: el trabajo está en
# el working tree. Ese caso estaba descrito en prosa en wf-validate y se
# resolvía a criterio del modelo.
if [ -z "$MB" ] || [ "$MB" = "$(git rev-parse "$REF" 2>/dev/null)" ]; then
  RANGE=""
else
  RANGE="$MB..$REF"
fi

run_diff() {
  if [ -n "$RANGE" ]; then git diff "$@" "$RANGE"; else git diff "$@" HEAD; fi
}

case "$MODE" in
  --full)  run_diff ;;
  --stat)  run_diff --stat ;;
  --files) run_diff --name-only ;;
  --log)
    if [ -n "$RANGE" ]; then git log --oneline "$RANGE"; else echo "(sin commits sobre $BASE)"; fi ;;
  --base)
    printf 'base=%s\nmerge_base=%s\nrange=%s\n' "$BASE" "${MB:-none}" "${RANGE:-working-tree}" ;;
  --weight)
    # Peso de revisión, no líneas crudas: renames y whitespace no cuentan,
    # y los tests se contabilizan aparte para no penalizar la buena cobertura.
    EXCL="$(wf_config '.weight_exclude[]?' 2>/dev/null)"
    [ -n "$EXCL" ] || EXCL=$'*.lock\npackage-lock.json\nyarn.lock\npnpm-lock.yaml\n*.snap\ndist/*\nbuild/*\n*.generated.*'
    STATS="$(if [ -n "$RANGE" ]; then
               git diff --ignore-all-space --find-renames --numstat "$RANGE"
             else
               git diff --ignore-all-space --find-renames --numstat HEAD
             fi)"
    prod=0; tests=0
    while IFS=$'\t' read -r add del path; do
      [ -n "$path" ] || continue
      skip=0
      while IFS= read -r pat; do
        [ -n "$pat" ] || continue
        # shellcheck disable=SC2254
        case "$path" in $pat) skip=1; break ;; esac
      done <<< "$EXCL"
      [ "$skip" -eq 1 ] && continue
      [ "$add" = "-" ] && continue          # binario
      case "$path" in
        *test*|*spec*|*__tests__*) tests=$((tests + add + del)) ;;
        *)                         prod=$((prod + add + del)) ;;
      esac
    done <<< "$STATS"
    printf 'weight_prod=%s\nweight_tests=%s\n' "$prod" "$tests" ;;
  *)
    echo "uso: wf-diff.sh [--full|--stat|--files|--log|--base|--weight] [--branch <rama>]" >&2
    exit 1 ;;
esac
