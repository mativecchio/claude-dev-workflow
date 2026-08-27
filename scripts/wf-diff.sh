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
# merge-base alone is not enough, and this is the part that kept biting:
# it must be taken against the *tightest* base ref available. A local base
# branch that has fallen behind origin yields a fork point EARLIER than the
# real one, and every commit that entered the branch from origin between the
# two shows up as if the feature had written it. Measured on a real branch
# with a local base 12 commits behind: 31 files / 1165 lines / 20 commits
# against the local ref, versus 4 files / 685 lines / 8 commits against
# origin's — two unrelated tickets swept in. So: compute the merge-base
# against both `<base>` and `origin/<base>`, and keep whichever is a
# descendant of the other.
#
# Usage:
#   wf-diff.sh              full diff
#   wf-diff.sh --stat       summary
#   wf-diff.sh --files      paths only (feeds scope drift)
#   wf-diff.sh --log        the branch's commits
#   wf-diff.sh --base       prints the base ref used, the merge-base and the range
#   wf-diff.sh --weight     production and test weight (brainstorm §6)
#
# Optional: --branch <branch> to diff another branch instead of HEAD.
# Optional: --fetch  refresh origin/<base> before resolving. Only updates the
#           remote-tracking ref — it never touches the working tree or a local
#           branch, so it is safe to run while someone is working in the repo.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$DIR/wf-lib.sh" ] && . "$DIR/wf-lib.sh"

MODE="${1:---full}"
REF="HEAD"
[ "${2:-}" = "--branch" ] && [ -n "${3:-}" ] && REF="$3"

DO_FETCH=0
for a in "$@"; do [ "$a" = "--fetch" ] && DO_FETCH=1; done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "wf-diff: not a git repo" >&2; exit 1; }

BASE="$(wf_base 2>/dev/null)"
[ -n "$BASE" ] || BASE="main"

HAS_ORIGIN=0
git show-ref --verify --quiet "refs/remotes/origin/$BASE" 2>/dev/null && HAS_ORIGIN=1

if [ "$DO_FETCH" -eq 1 ]; then
  # Explicit refspec on purpose: this updates refs/remotes/origin/<base> and
  # nothing else. No local branch moves, no merge, no working-tree change.
  git fetch --quiet origin "+refs/heads/$BASE:refs/remotes/origin/$BASE" 2>/dev/null &&
    HAS_ORIGIN=1
fi

MB_LOCAL="$(git merge-base "$REF" "$BASE" 2>/dev/null)"
MB_ORIGIN=""
[ "$HAS_ORIGIN" -eq 1 ] && MB_ORIGIN="$(git merge-base "$REF" "origin/$BASE" 2>/dev/null)"

# Keep the later fork point. A stale local base gives an ancestor of the real
# one, which is precisely how other tickets' merged commits leak into the diff.
BASE_REF="$BASE"
if [ -n "$MB_LOCAL" ] && [ -n "$MB_ORIGIN" ] && [ "$MB_LOCAL" != "$MB_ORIGIN" ]; then
  if git merge-base --is-ancestor "$MB_LOCAL" "$MB_ORIGIN" 2>/dev/null; then
    MB="$MB_ORIGIN"; BASE_REF="origin/$BASE"
    printf 'wf-diff: local %s is behind origin/%s — using origin/%s as the base (local would add %s unrelated commit(s) to this diff)\n' \
      "$BASE" "$BASE" "$BASE" "$(git rev-list --count "$MB_LOCAL..$MB_ORIGIN" 2>/dev/null)" >&2
  else
    MB="$MB_LOCAL"
  fi
elif [ -n "$MB_ORIGIN" ] && [ -z "$MB_LOCAL" ]; then
  MB="$MB_ORIGIN"; BASE_REF="origin/$BASE"
else
  MB="$MB_LOCAL"
fi

if [ "$HAS_ORIGIN" -eq 0 ] && [ "$DO_FETCH" -eq 0 ]; then
  printf 'wf-diff: no origin/%s ref — the base is the local branch only. Run with --fetch if this repo has a remote.\n' "$BASE" >&2
fi

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
    printf 'base=%s\nbase_ref=%s\nmerge_base=%s\nrange=%s\n' "$BASE" "$BASE_REF" "${MB:-none}" "${RANGE:-working-tree}" ;;
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
    echo "usage: wf-diff.sh [--full|--stat|--files|--log|--base|--weight] [--branch <branch>] [--fetch]" >&2
    exit 1 ;;
esac
