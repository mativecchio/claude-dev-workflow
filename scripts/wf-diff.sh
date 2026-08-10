#!/bin/bash
#
# wf-diff — the feature's diff, computed correctly, in one place.
#
# Replaces the paragraph repeated across wf-validate, wf-mr-review and
# wf-mr-desc explaining why not to use `base..HEAD`. The reason is real:
# if someone advances the base with a pull --ff-only after the branch was
# created, the naive diff shows other people's changes as if they were the
# feature's. The correct rule is to diff against merge-base(HEAD, base).
#
# Usage:
#   wf-diff.sh              full diff
#   wf-diff.sh --stat       summary
#   wf-diff.sh --files      paths only (feeds scope drift)
#   wf-diff.sh --log        the branch's commits
#   wf-diff.sh --base       prints the detected base and the merge-base
#   wf-diff.sh --weight     production and test weight (brainstorm §6)
#
# Optional: --branch <branch> to diff another branch instead of HEAD.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$DIR/wf-lib.sh" ] && . "$DIR/wf-lib.sh"

MODE="${1:---full}"
REF="HEAD"
[ "${2:-}" = "--branch" ] && [ -n "${3:-}" ] && REF="$3"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "wf-diff: not a git repo" >&2; exit 1; }

BASE="$(wf_base 2>/dev/null)"
[ -n "$BASE" ] || BASE="main"

MB="$(git merge-base "$REF" "$BASE" 2>/dev/null)"

# No merge-base (nonexistent base) or no commits of our own: the work is in the
# working tree. That case was described in prose in wf-validate and resolved at
# the model's discretion.
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
    if [ -n "$RANGE" ]; then git log --oneline "$RANGE"; else echo "(no commits on top of $BASE)"; fi ;;
  --base)
    printf 'base=%s\nmerge_base=%s\nrange=%s\n' "$BASE" "${MB:-none}" "${RANGE:-working-tree}" ;;
  --weight)
    # Review weight, not raw lines: renames and whitespace don't count, and
    # tests are counted separately so good coverage isn't penalized.
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
      [ "$add" = "-" ] && continue          # binary
      case "$path" in
        *test*|*spec*|*__tests__*) tests=$((tests + add + del)) ;;
        *)                         prod=$((prod + add + del)) ;;
      esac
    done <<< "$STATS"
    printf 'weight_prod=%s\nweight_tests=%s\n' "$prod" "$tests" ;;
  *)
    echo "usage: wf-diff.sh [--full|--stat|--files|--log|--base|--weight] [--branch <branch>]" >&2
    exit 1 ;;
esac
