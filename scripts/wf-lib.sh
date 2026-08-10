#!/bin/bash
#
# wf-lib — shared workflow functions.
#
# Replaces the prose repeated across the wf-*.md commands. "Step 0 — Identify
# the active ticket" was copied verbatim into 8 files: changing anything there
# meant touching all 8 and remembering every one of them.
#
# Usage from a command:
#   source ~/.claude/scripts/wf-lib.sh
#   TICKET="$(wf_ticket)" || exit 1
#   DIR="$(wf_dir)"
#
# PRINCIPLE: degrade, don't break. A function that can't resolve something
# returns empty and exits != 0; it never leaves state half-written.

WF_STAGES="refine analyze review-plan implement validate test mr-desc mr-review retro"

# ---------------------------------------------------------------------------
# Project context
# ---------------------------------------------------------------------------

wf_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

wf_workflow_root() { printf '%s/.claude/workflow' "$(wf_repo_root)"; }

# Active ticket. Empty + exit 1 if there is none: the caller decides whether to
# ask the user or carry on without a ticket.
wf_ticket() {
  local f t
  f="$(wf_workflow_root)/state.json"
  [ -f "$f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  t="$(jq -r '.activeTicket // empty' "$f" 2>/dev/null)"
  [ -n "$t" ] || return 1
  printf '%s' "$t"
}

# The active ticket's directory, created if it doesn't exist.
wf_dir() {
  local t d
  t="$(wf_ticket)" || return 1
  d="$(wf_workflow_root)/$t"
  mkdir -p "$d" 2>/dev/null || return 1
  printf '%s' "$d"
}

# Reads a key from the project config. Usage: wf_config '.base_branch'
wf_config() {
  local f
  f="$(wf_workflow_root)/config.json"
  [ -f "$f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -r "${1:-.} // empty" "$f" 2>/dev/null
}

# The project's base branch. Precedence: config > existing branch > main.
# This used to be prose ("develop/main/master, depending on the project") that
# the model re-resolved on every run, and wf-refine hardcoded develop outright.
wf_base() {
  local b
  b="$(wf_config '.base_branch')"
  if [ -n "$b" ]; then printf '%s' "$b"; return 0; fi
  for b in develop main master; do
    if git show-ref --verify --quiet "refs/heads/$b" 2>/dev/null ||
       git show-ref --verify --quiet "refs/remotes/origin/$b" 2>/dev/null; then
      printf '%s' "$b"; return 0
    fi
  done
  printf 'main'
}

# The language the commands address the user in. Artifacts written to disk
# (plan.md, commit messages, code, docs) are always English regardless of this;
# this only governs what gets spoken on screen.
#
# Set it per project with "language": "es" in .claude/workflow/config.json.
wf_language() {
  local l
  l="$(wf_config '.language')"
  [ -n "$l" ] && printf '%s' "$l" || printf 'en'
}

# ---------------------------------------------------------------------------
# Ticket state
# ---------------------------------------------------------------------------

wf_state() {
  local d
  d="$(wf_dir)" || return 1
  [ -f "$d/state.json" ] || return 1
  jq -r "${1:-.} // empty" "$d/state.json" 2>/dev/null
}

# Writes a key, preserving the rest of the file.
# Usage: wf_set_state approved true   |   wf_set_state branch '"MA-123-fix"'
wf_set_state() {
  local d f tmp key="$1" val="$2"
  [ -n "$key" ] || return 1
  d="$(wf_dir)" || return 1
  f="$d/state.json"
  [ -f "$f" ] || echo '{}' > "$f"
  jq -e . "$f" >/dev/null 2>&1 || return 1   # never overwrite a corrupt state
  tmp="$(mktemp)" || return 1
  if jq --arg k "$key" --argjson v "$val" '.[$k] = $v' "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$f"; return 0
  fi
  rm -f "$tmp"; return 1
}

# Records entry into a stage: writes stage and appends to completed, preserving
# branch, notes, iterations, subtasks and approved.
#
# This used to be a prose instruction that only wf-refine and /wf honored (H11),
# with a vocabulary that didn't match the consumers' (H12). Here the vocabulary
# is validated: an invalid stage fails loudly instead of being written and
# silently breaking the counts.
wf_enter_stage() {
  local stage="$1" d f tmp
  [ -n "$stage" ] || return 1

  case " $WF_STAGES " in
    *" $stage "*) ;;
    *) echo "wf-lib: invalid stage '$stage' (valid: $WF_STAGES)" >&2; return 1 ;;
  esac

  d="$(wf_dir)" || return 1
  f="$d/state.json"
  [ -f "$f" ] || echo '{}' > "$f"
  jq -e . "$f" >/dev/null 2>&1 || return 1

  tmp="$(mktemp)" || return 1
  if jq --arg s "$stage" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .stage = $s
      | .completed = ((.completed // []) + [$s] | unique)
      | .started_at //= $ts
      | .updated_at = $ts
     ' "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$f"
    printf '%s' "$stage"
    return 0
  fi
  rm -f "$tmp"; return 1
}

# ---------------------------------------------------------------------------
# CLI: lets it be used without sourcing — `wf-lib.sh ticket`, `wf-lib.sh base`, etc.
# ---------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    ticket)      wf_ticket ;;
    dir)         wf_dir ;;
    base)        wf_base ;;
    language)    wf_language ;;
    config)      wf_config "${2:-.}" ;;
    state)       wf_state "${2:-.}" ;;
    set-state)   wf_set_state "$2" "$3" ;;
    enter-stage) wf_enter_stage "$2" ;;
    context)
      # Everything a command needs at startup, in one call.
      t="$(wf_ticket)" || { echo "❌ No active ticket in $(wf_workflow_root)/state.json" >&2; exit 1; }
      printf 'ticket=%s\ndir=%s\nbase=%s\nstage=%s\nbranch=%s\nlang=%s\n' \
        "$t" "$(wf_dir)" "$(wf_base)" "$(wf_state '.stage')" "$(git branch --show-current 2>/dev/null)" "$(wf_language)"
      ;;
    *)
      echo "usage: wf-lib.sh {ticket|dir|base|language|config <path>|state <path>|set-state <k> <v>|enter-stage <s>|context}" >&2
      exit 1 ;;
  esac
fi
