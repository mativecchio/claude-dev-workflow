#!/bin/bash
#
# wf-version — tells you a newer workflow is available, at session start.
#
# ⚠️  THIS RUNS IN EVERY PROJECT ON THE MACHINE, workflow or not. It was chosen
# over a per-command check deliberately, but that choice sets the constraints:
#
#   1. NEVER block or slow down session start. No network call on this path.
#      `git fetch` happens in the background, at most once a day, and only ever
#      reports from cache. A session start must not wait on a remote.
#   2. Fail silent. No git, no repo, no jq, unreadable cache → exit 0, print
#      nothing. A version notice is the least important thing in any session.
#   3. Print at most one short block, and only when there is actually something
#      to do. A notice that appears every time is a notice you stop reading.
#   4. Be disableable: WF_VERSION_CHECK=off.
#
# Two independent signals, because they need different fixes:
#
#   installed  <  repo      → you changed or pulled the repo and didn't install
#   repo       <  origin    → someone pushed; you haven't pulled
#
# The first is free and always accurate. The second needs the network, so it is
# cached and may be up to a day stale — which is fine for "there's a new version".

[ "${WF_VERSION_CHECK:-on}" = "off" ] && exit 0

CFG="$HOME/.claude/workflow/config.json"
CACHE="$HOME/.claude/workflow/.version-check"
MAX_AGE=86400          # one day between fetches

command -v jq  >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
[ -f "$CFG" ] || exit 0

REPO="$(jq -r '.repo_path // empty' "$CFG" 2>/dev/null)"
[ -n "$REPO" ] && [ -d "$REPO/.git" ] || exit 0

INSTALLED="$(jq -r '.installed_version // empty' "$CFG" 2>/dev/null)"
CURRENT="$(cat "$REPO/VERSION" 2>/dev/null | tr -d '[:space:]')"

MSG=""

# --- signal 1: installed vs repo (free, exact) ---------------------------------
if [ -n "$CURRENT" ] && [ -n "$INSTALLED" ] && [ "$CURRENT" != "$INSTALLED" ]; then
  MSG="  claude-workflow v$CURRENT is in the repo, v$INSTALLED is installed
  → $REPO/install.sh"
fi

# --- signal 2: repo vs origin (cached, may be a day stale) ---------------------
NOW="$(date +%s)"
LAST=0
[ -f "$CACHE" ] && LAST="$(jq -r '.last_fetch // 0' "$CACHE" 2>/dev/null)"
case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac

BEHIND="$( [ -f "$CACHE" ] && jq -r '.behind // 0' "$CACHE" 2>/dev/null )"
case "$BEHIND" in ''|*[!0-9]*) BEHIND=0 ;; esac

if [ $(( NOW - LAST )) -gt "$MAX_AGE" ]; then
  # Refresh in the background and report from the cache we already have. The
  # next session sees the new number; this one never waits on the network.
  (
    git -C "$REPO" fetch --quiet origin 2>/dev/null
    b="$(git -C "$REPO" rev-list --count HEAD..@{u} 2>/dev/null)"
    case "$b" in ''|*[!0-9]*) b=0 ;; esac
    tmp="$(mktemp)" || exit 0
    if jq -cn --argjson last "$NOW" --argjson behind "$b" \
         '{last_fetch:$last, behind:$behind}' > "$tmp" 2>/dev/null; then
      mv "$tmp" "$CACHE" 2>/dev/null || rm -f "$tmp"
    else
      rm -f "$tmp"
    fi
  ) >/dev/null 2>&1 &
fi

if [ "$BEHIND" -gt 0 ]; then
  [ -n "$MSG" ] && MSG="$MSG
"
  MSG="$MSG  $BEHIND commit(s) behind origin
  → git -C $REPO pull && $REPO/install.sh"
fi

[ -n "$MSG" ] || exit 0

printf '\n⬆️  Workflow update available\n%s\n\n' "$MSG"
exit 0
