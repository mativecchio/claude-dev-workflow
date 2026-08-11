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

# The model a stage's Agent should run on.
#
# Only the four stages that spawn an Agent have a model to choose. The rest run
# in the user's session, where the model is the user's to pick — a command
# cannot change the model of the session running it.
#
# Why this exists at all: those four commands used to pass no model, so their
# agent inherited the session's. That made plan.md — the artifact every later
# stage consumes — a product of whatever the session happened to be set to. The
# same ticket analysed on two different days could get two different qualities
# of plan for a reason invisible in the output.
#
# The defaults encode a principle, not a budget: analysis and verification carry
# the judgment the whole cycle rests on, so they get the strongest model. Where
# a smaller model appears elsewhere in this system it is because it is adequate
# for that task, never because it is cheaper.
#
# Override per project with a "models" block in config.json, or per invocation
# with WF_MODEL.
WF_MODEL_DEFAULTS="analyze:opus review-plan:opus validate:opus mr-review:opus"
WF_VALID_MODELS="opus sonnet haiku fable"

wf_model() {
  local stage="$1" m d
  [ -n "$stage" ] || return 1

  if [ -n "${WF_MODEL:-}" ]; then m="$WF_MODEL"
  else
    m="$(wf_config ".models[\"$stage\"]" 2>/dev/null)"
    if [ -z "$m" ]; then
      for d in $WF_MODEL_DEFAULTS; do
        case "$d" in "$stage:"*) m="${d#*:}"; break ;; esac
      done
    fi
  fi
  [ -n "$m" ] || return 1

  # A typo here would silently route a stage somewhere unintended, so an unknown
  # model falls back to the default rather than being passed through.
  case " $WF_VALID_MODELS " in
    *" $m "*) printf '%s' "$m" ;;
    *) echo "wf-lib: unknown model '$m' for stage '$stage', using opus" >&2
       printf 'opus' ;;
  esac
}

# ---------------------------------------------------------------------------
# Update notice
# ---------------------------------------------------------------------------
#
# This lived in a SessionStart hook first. The hook fired correctly — verified
# with a logging probe — but its stdout never reached the terminal, so the whole
# point was lost: an update notice nobody sees is not a notice. Worse, relying on
# it meant depending on the model to relay what it saw in context, which is the
# prose-as-mechanism pattern this system moves away from.
#
# Here it runs inside `context`, so it lands in a Bash result the user actually
# reads, and costs nothing in projects that never invoke the workflow.
#
# Same discipline as before: never a network call on this path (the fetch is
# spawned in the background at most once a day and only cached results are read),
# never any output unless there is an action to take, and silent on every error.
wf_version_notice() {
  [ "${WF_VERSION_CHECK:-on}" = "off" ] && return 0
  command -v jq >/dev/null 2>&1 || return 0

  local cfg="$HOME/.claude/workflow/config.json"
  local cache="$HOME/.claude/workflow/.version-check"
  local repo installed current now last behind msg=""
  [ -f "$cfg" ] || return 0

  repo="$(jq -r '.repo_path // empty' "$cfg" 2>/dev/null)"
  [ -n "$repo" ] && [ -d "$repo/.git" ] || return 0

  installed="$(jq -r '.installed_version // empty' "$cfg" 2>/dev/null)"
  current="$(tr -d '[:space:]' < "$repo/VERSION" 2>/dev/null)"

  if [ -n "$current" ] && [ -n "$installed" ] && [ "$current" != "$installed" ]; then
    msg="⬆️  claude-workflow v$current available (v$installed installed)
   → $repo/install.sh"
  fi

  now="$(date +%s)"; last=0
  [ -f "$cache" ] && last="$(jq -r '.last_fetch // 0' "$cache" 2>/dev/null)"
  case "$last" in ''|*[!0-9]*) last=0 ;; esac

  behind=0
  [ -f "$cache" ] && behind="$(jq -r '.behind // 0' "$cache" 2>/dev/null)"
  case "$behind" in ''|*[!0-9]*) behind=0 ;; esac

  if [ $(( now - last )) -gt 86400 ]; then
    (
      git -C "$repo" fetch --quiet origin 2>/dev/null
      b="$(git -C "$repo" rev-list --count HEAD..@{u} 2>/dev/null)"
      case "$b" in ''|*[!0-9]*) b=0 ;; esac
      tmp="$(mktemp)" || exit 0
      if jq -cn --argjson last "$now" --argjson behind "$b" \
           '{last_fetch:$last, behind:$behind}' > "$tmp" 2>/dev/null; then
        mv "$tmp" "$cache" 2>/dev/null || rm -f "$tmp"
      else rm -f "$tmp"; fi
    ) >/dev/null 2>&1 &
  fi

  if [ "$behind" -gt 0 ]; then
    [ -n "$msg" ] && msg="$msg
"
    msg="$msg⬆️  $behind commit(s) behind origin
   → git -C $repo pull && $repo/install.sh"
  fi

  [ -n "$msg" ] || return 0
  printf '%s\n\n' "$msg"
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
    model)       wf_model "$2" ;;
    config)      wf_config "${2:-.}" ;;
    state)       wf_state "${2:-.}" ;;
    set-state)   wf_set_state "$2" "$3" ;;
    enter-stage) wf_enter_stage "$2" ;;
    version-notice) wf_version_notice ;;
    context)
      # Printed before the ticket lookup on purpose: a stale install is worth
      # knowing about even in a project with no active ticket, where the lookup
      # below exits 1.
      wf_version_notice
      # Everything a command needs at startup, in one call.
      t="$(wf_ticket)" || { echo "❌ No active ticket in $(wf_workflow_root)/state.json" >&2; exit 1; }
      st="$(wf_state '.stage')"
      printf 'ticket=%s\ndir=%s\nbase=%s\nstage=%s\nbranch=%s\nlang=%s\nmodel=%s\n' \
        "$t" "$(wf_dir)" "$(wf_base)" "$st" "$(git branch --show-current 2>/dev/null)" "$(wf_language)" "$(wf_model "$st" 2>/dev/null)"
      ;;
    *)
      echo "usage: wf-lib.sh {ticket|dir|base|language|model <stage>|config <path>|state <path>|set-state <k> <v>|enter-stage <s>|context}" >&2
      exit 1 ;;
  esac
fi
