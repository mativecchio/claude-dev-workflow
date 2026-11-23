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

WF_STAGES="quick refine analyze review-plan implement validate test mr-desc mr-review retro"

# ---------------------------------------------------------------------------
# Project context
# ---------------------------------------------------------------------------

wf_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# The main checkout of the repo, shared by all its worktrees. The workflow lives
# there: .claude/workflow is gitignored, so a worktree resolved through its own
# top level had no config and no state, and work done in a worktree had to be
# recorded in the main checkout by hand.
wf_main_root() {
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { wf_repo_root; return; }
  case "$common" in
    */.git) printf '%s' "${common%/.git}" ;;
    *)      wf_repo_root ;;
  esac
}

wf_workflow_root() { printf '%s/.claude/workflow' "$(wf_main_root)"; }

# Where the ticket directories live. Defaults to the workflow root; "specs_root"
# in config.json moves them (absolute, ~/..., or relative to the main checkout),
# e.g. to a checkout of a central specs repository. Directories are keyed by
# ticket, never by project, so one ticket that spans repos has one home.
wf_tickets_root() {
  local r main
  r="$(wf_config '.specs_root')"
  main="$(wf_main_root)"
  case "$r" in
    '')   printf '%s' "$(wf_workflow_root)" ;;
    /*)   printf '%s' "$r" ;;
    "~"/*) printf '%s/%s' "$HOME" "${r#"~/"}" ;;
    *)    printf '%s/%s' "$main" "$r" ;;
  esac
}

wf_ticket_pattern() {
  local p
  p="$(wf_config '.ticket_pattern')"
  printf '%s' "${p:-[A-Z][A-Z0-9]+-[0-9]+}"
}

# The ticket this checkout is working on, and how it was found, as
# "<ticket> <source>". In order:
#   arg      WF_TICKET (the command was given the ticket)
#   state    a ticket whose state.json records the current branch
#   branch   the ticket key in the branch name (fix/MA-801 → MA-801)
#   pointer  activeTicket in the root state.json — the last resort
# The branch is read from git, so it is always current; the pointer is a memory
# written earlier and goes stale the moment someone switches branch or opens a
# worktree. It used to be the only source, so two tickets in parallel overwrote
# each other's pointer and a command could write into the wrong ticket silently.
wf_ticket_resolve() {
  local t branch root f key
  if [ -n "${WF_TICKET:-}" ]; then printf '%s arg' "$WF_TICKET"; return 0; fi
  command -v jq >/dev/null 2>&1 || return 1
  root="$(wf_tickets_root)"
  branch="$(git branch --show-current 2>/dev/null)"
  if [ -n "$branch" ]; then
    for f in "$root"/*/state.json; do
      [ -f "$f" ] || continue
      if [ "$(jq -r '.branch // empty' "$f" 2>/dev/null)" = "$branch" ]; then
        t="$(basename "$(dirname "$f")")"
        printf '%s state' "$t"; return 0
      fi
    done
    key="$(printf '%s' "$branch" | grep -oE "$(wf_ticket_pattern)" | head -1)"
    if [ -n "$key" ]; then printf '%s branch' "$key"; return 0; fi
  fi
  f="$(wf_workflow_root)/state.json"
  [ -f "$f" ] || return 1
  t="$(jq -r '.activeTicket // empty' "$f" 2>/dev/null)"
  [ -n "$t" ] || return 1
  printf '%s pointer' "$t"
}

# The ticket alone. Empty + exit 1 if there is none: the caller decides whether
# to ask the user or carry on without a ticket.
wf_ticket() {
  local r
  r="$(wf_ticket_resolve)" || return 1
  printf '%s' "${r%% *}"
}

wf_ticket_source() {
  local r
  r="$(wf_ticket_resolve)" || return 1
  printf '%s' "${r##* }"
}

# The active ticket's directory, created if it doesn't exist.
wf_dir() {
  local t d
  t="$(wf_ticket)" || return 1
  d="$(wf_tickets_root)/$t"
  mkdir -p "$d" 2>/dev/null || return 1
  printf '%s' "$d"
}

# The checkout a ticket's code is in: the worktree on the branch its state
# records, else the one whose branch carries its key. The user remembers the
# ticket, not the folder. Empty + exit 1 when no worktree matches.
wf_worktree() {
  local t branch wt b
  t="${1:-}"
  [ -n "$t" ] || t="$(wf_ticket)" || return 1
  branch="$(jq -r '.branch // empty' "$(wf_tickets_root)/$t/state.json" 2>/dev/null)"
  git worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { wt = substr($0, 10) }
    /^branch /   { sub("^branch refs/heads/", ""); print wt "\t" $0 }' |
  {
    fallback=""
    while IFS="$(printf '\t')" read -r wt b; do
      if [ -n "$branch" ] && [ "$b" = "$branch" ]; then printf '%s' "$wt"; exit 0; fi
      if [ -z "$fallback" ] && printf '%s' "$b" | grep -qE "(^|[^A-Za-z0-9])$t([^0-9]|$)"; then fallback="$wt"; fi
    done
    [ -n "$fallback" ] && { printf '%s' "$fallback"; exit 0; }
    exit 1
  }
}

# Files outside the ticket's spec. Reads the file table of quick.md (## Files)
# or plan.md (## Files to modify/create): the first backticked path of each row.
# Paths are relative to the checkout; an entry ending in / covers a directory.
# Workflow artifacts, docs and tests are never out of scope. Prints one line per file
# outside the list and exits 1; exits 0 when all are inside or the spec lists
# no files (nothing to compare against).
wf_scope_check() {
  local t d spec listed="" f rel root out=""
  t="$(wf_ticket)" || return 0
  d="$(wf_tickets_root)/$t"
  for spec in "$d/plan.md" "$d/quick.md"; do
    [ -f "$spec" ] || continue
    listed="$(awk '
      /^## Files( to modify\/create)?[[:space:]]*$/ { s = 1; next }
      /^## / { s = 0 }
      s && /^\|/ { if (match($0, /`[^`]+`/)) print substr($0, RSTART + 1, RLENGTH - 2) }' "$spec")"
    [ -n "$listed" ] && break
  done
  [ -n "$listed" ] || return 0
  root="$(wf_repo_root)"
  for f in "$@"; do
    rel="${f#"$root"/}"
    case "$rel" in
      .claude/*|*.md|docs/*|*/__tests__/*|__tests__/*|*/tests/*|tests/*|*/test/*|test/*|*.test.*|*.spec.*|*_test.*) continue ;;
    esac
    if ! printf '%s\n' "$listed" | awk -v f="$rel" '
        $0 == f { found = 1 }
        /\/$/ && index(f, $0) == 1 { found = 1 }
        END { exit !found }'; then
      out="$out$rel
"
    fi
  done
  [ -n "$out" ] || return 0
  printf '%s' "$out"
  return 1
}

# Reads a key from the project config. Usage: wf_config '.base_branch'
wf_config() {
  local f
  f="$(wf_workflow_root)/config.json"
  [ -f "$f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -r "${1:-.} // empty" "$f" 2>/dev/null
}

# What repo a checkout actually is, taken from its origin remote. Two callers
# need this and they need the same answer: verifying a related_project points
# where it claims, and telling whether a ticket is filed under the project whose
# code it changes. Empty exit 1 when there is no origin — identity unknown, which
# callers must treat as "cannot tell", never as "mismatch".
wf_repo_slug() {
  local dir="${1:-}" url slug
  [ -n "$dir" ] || dir="$(wf_repo_root)"
  url="$(git -C "$dir" remote get-url origin 2>/dev/null)" || return 1
  [ -n "$url" ] || return 1
  slug="${url##*/}"
  printf '%s' "${slug%.git}"
}

# Absolute path of a related_project by name. Empty exit 1 if it is not listed
# or has no path.
wf_related_path() {
  local want="${1:-}" root n i name p abs
  [ -n "$want" ] || return 1
  root="$(wf_repo_root)"
  n="$(wf_config '.related_projects | length')"
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  i=0
  while [ "$i" -lt "$n" ]; do
    name="$(wf_config ".related_projects[$i].name")"
    p="$(wf_config ".related_projects[$i].path")"
    i=$((i + 1))
    [ "$name" = "$want" ] || continue
    [ -n "$p" ] || return 1
    case "$p" in /*) abs="$p" ;; *) abs="$root/$p" ;; esac
    # Collapse the ../ so the path in an error message is one the reader can
    # paste, not main/../other.
    if [ -d "$abs" ]; then abs="$(cd "$abs" 2>/dev/null && pwd)" || return 1; fi
    printf '%s' "$abs"
    return 0
  done
  return 1
}

# Verifies that every related_projects[].path in the project config resolves to
# a real directory. A broken path never fails loudly — it silently degrades the
# cross-repo contract check into second-hand guessing. That is exactly how the
# "verifying related_projects is mandatory" rule was defeated: the rule fired,
# the path did not resolve, and the claim was accepted from notes anyway.
# Prints one line per entry; returns 1 if any path is broken.
wf_related_projects_check() {
  local root n i idx name p abs want slug kind bad=0
  root="$(wf_repo_root)"
  n="$(wf_config '.related_projects | length')" || return 0
  case "$n" in ''|*[!0-9]*) return 0 ;; esac
  [ "$n" -eq 0 ] && return 0
  i=0
  while [ "$i" -lt "$n" ]; do
    kind="$(wf_config ".related_projects[$i] | type")"
    name="$(wf_config ".related_projects[$i].name" 2>/dev/null)"
    p="$(wf_config ".related_projects[$i].path" 2>/dev/null)"
    i=$((i + 1))

    # A malformed entry used to be skipped in silence, which made a broken
    # config indistinguishable from an empty one: the stages that consume this
    # field read .path, found nothing, and carried on as if there were nothing
    # to verify. Entries are local checkouts addressed by a path relative to
    # this project; a URL cannot be read from disk, so it verifies nothing.
    if [ "$kind" != "object" ]; then
      printf '\xe2\x9a\xa0 related_projects[%s] is a %s, not an object.\n   Entries are {\"name\": \"...\", \"path\": \"../relative/path\"} pointing at a LOCAL checkout.\n   A repository URL belongs in its own field, not here - it cannot be read from disk.\n' \
        "$((i - 1))" "${kind:-malformed}" >&2
      bad=1
      continue
    fi
    if [ -z "$p" ]; then
      printf '\xe2\x9a\xa0 related_project %s has no \"path\".\n   Without a path relative to this project nothing can be verified against it; give it one or drop the entry.\n' \
        "${name:-"[$((i - 1))]"}" >&2
      bad=1
      continue
    fi
    case "$p" in /*) abs="$p" ;; *) abs="$root/$p" ;; esac
    if [ -d "$abs" ]; then
      # Existing is not the same as correct. A path can resolve to some other
      # checkout entirely and every cross-repo claim made against it is then
      # confidently wrong, with nothing to signal it. Compare the checkout's
      # origin remote against the expected repo name; `remote` in config.json
      # overrides when the directory or the remote is named differently.
      idx=$((i - 1))
      want="$(wf_config ".related_projects[$idx].remote")"
      [ -n "$want" ] || want="$name"
      slug="$(wf_repo_slug "$abs")"
      if [ -z "$slug" ]; then
        printf 'related_project=%s:%s (not a git checkout - identity unverified)\n' "${name:-?}" "$p"
      else
        if [ -n "$want" ] && [ "$slug" != "$want" ]; then
          printf '\xe2\x9a\xa0 related_project %s -> %s resolves to a DIFFERENT repo: origin is %s, expected %s.\n   Either the path or the name is wrong. Do not make claims about %s from this checkout.\n' \
            "${name:-?}" "$p" "$slug" "$want" "${name:-?}" >&2
          bad=1
        else
          printf 'related_project=%s:%s\n' "${name:-?}" "$p"
        fi
      fi
    else
      printf '\xe2\x9a\xa0 related_project %s -> %s DOES NOT RESOLVE (%s).\n   Fix config.json before making ANY claim about that repo.\n' \
        "${name:-?}" "$p" "$abs" >&2
      bad=1
    fi
  done
  return "$bad"
}

# Resolves a ticket's commits from git rather than from a stored hash. Hashes
# written into state.json or a doc die on the first rebase and leave the reader
# with a pointer to nothing, even though the content shipped unchanged under a
# new hash. Never store a hash: resolve it here at read time.
wf_commits() {
  local t b
  t="${1:-}"
  [ -n "$t" ] || t="$(wf_ticket)" || return 1
  [ -n "$t" ] || return 1
  b="$(wf_base)"
  git log --format='%h %s' --grep="$t" "$b..HEAD" 2>/dev/null
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
# analyze/review-plan decide what gets built; validate/mr-review catch what the
# implementation got wrong, so they are the last thing to weaken. mr-desc/commit/
# test cover bounded transformation with a checkable result — sonnet is the
# adequate model there, not merely the cheaper one.
WF_MODEL_DEFAULTS="analyze:opus review-plan:opus validate:opus mr-review:opus mr-desc:sonnet commit:sonnet test:sonnet"
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
  # Resolve first, judge after. An empty result is the correct answer for the
  # stages that run in the user's own session (refine, implement, retro), and
  # the WRONG answer for a name that does not exist at all — the two used to be
  # indistinguishable from outside: same empty output, same exit 1.
  #
  # The check is "did anything claim this name", not "is it a stage": `commit`
  # carries a model default without being a pipeline stage, because /wf-commit
  # is a command and not something state.json tracks. Validating against
  # WF_STAGES alone rejected it.
  if [ -z "$m" ]; then
    wf_is_stage "$stage" || { wf_reject_stage "$stage"; return 2; }
    return 1
  fi

  # A typo here would silently route a stage somewhere unintended, so an unknown
  # model falls back to the default rather than being passed through.
  case " $WF_VALID_MODELS " in
    *" $m "*) printf '%s' "$m" ;;
    *) echo "wf-lib: unknown model '$m' for stage '$stage', using opus" >&2
       printf 'opus' ;;
  esac
}

# Whether the plan is solid enough to implement on a smaller model.
#
# The thesis this supports: invest heavily in analysis, and with a strong plan
# the implementation does not need the same model. `wf-implement` runs in the
# user's session, so nothing here can switch anything — the recommendation is
# mechanical, the decision is the user's.
#
# It reads only structured data (complexity.json, state.json). Parsing prose out
# of review-findings.md was the obvious alternative and was rejected: a
# recommendation derived from a regex over markdown would be wrong in ways
# nobody could predict, and this one has to be trustworthy or ignored.
#
# Conservative by construction: anything missing or unreadable means "stay on
# the strong model". The failure mode of advising a downgrade on a plan that was
# never verified is worse than the cost of not advising one.
wf_implement_advice() {
  local d c points sister approved rec reason
  d="$(wf_dir)" || return 1
  c="$d/complexity.json"

  points=""; sister=""
  if [ -f "$c" ] && command -v jq >/dev/null 2>&1; then
    points="$(jq -r '.points // empty' "$c" 2>/dev/null)"
    sister="$(jq -r '.dimensions.sister_feature.value // empty' "$c" 2>/dev/null)"
  fi
  approved="$(wf_state '.approved' 2>/dev/null)"

  rec="opus"
  if [ -z "$points" ]; then
    reason="no complexity estimate — /wf-analyze did not record one"
  elif [ "$approved" != "true" ]; then
    reason="the plan is not approved yet"
  elif [ "$sister" = "none" ]; then
    reason="no sister feature: there is no pattern in the codebase to follow"
  elif [ "$points" -gt 3 ] 2>/dev/null; then
    reason="complexity $points — above the threshold where a plan carries the work"
  else
    rec="sonnet"
    reason="complexity $points, sister feature found, plan approved"
  fi

  printf 'recommended_model=%s\nreason=%s\n' "$rec" "$reason"
  if [ "$rec" = "sonnet" ]; then
    printf '\n📋 %s.\n   → Sonnet is adequate here. Switch with /model sonnet.\n\n' "$reason"
  else
    printf '\n📋 %s.\n   → Stay on the strong model for this one.\n\n' "$reason"
  fi
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
  local d f tmp key="$1" val="$2" bare
  [ -n "$key" ] || return 1
  # enter-stage guards the front door; without this, any caller can write an
  # arbitrary string straight into .stage through here and bypass it entirely.
  if [ "$key" = "stage" ]; then
    bare="${val%\"}"; bare="${bare#\"}"
    wf_is_stage "$bare" || { wf_reject_stage "$bare"; return 1; }
  fi
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
# True if the name is one of the pipeline's stages.
# The repo a ticket's code lives in, declared as "repo" in its state. Empty for
# every ticket that does not say — which is the normal case and means "this one".
wf_ticket_repo() {
  local d
  d="$(wf_dir 2>/dev/null)" || return 1
  [ -f "$d/state.json" ] || return 1
  jq -r '.repo // empty' "$d/state.json" 2>/dev/null
}

# A ticket belongs in the workflow directory of the repo whose code it changes.
# That repo is where its base branch, its checks and its config.json are; filing
# it elsewhere leaves the state in one tree and the code in another, and every
# git-facing answer — branch, diff, base, checks — then describes the wrong repo
# without saying so. This is not multi-repo support: each repo already runs its
# own workflow. It is the guard that keeps a ticket in the right one.
#
# Returns 0 when the ticket is here, declares nothing, or identity cannot be
# established. Returns 1 with an actionable message otherwise.
wf_ticket_repo_check() {
  local want here t abs
  want="$(wf_ticket_repo 2>/dev/null)" || return 0
  [ -n "$want" ] || return 0

  here="$(wf_repo_slug)" || return 0     # no origin: cannot tell, do not accuse
  [ -n "$here" ] || return 0
  [ "$want" = "$here" ] && return 0

  t="$(wf_ticket 2>/dev/null)"
  if abs="$(wf_related_path "$want")"; then
    printf '\xe2\x9a\xa0 ticket %s declares repo %s but this project is %s.\n' "$t" "'$want'" "'$here'" >&2
    printf '   Its code is in %s, so its workflow belongs there too. Move it with:\n     wf-lib.sh relocate %s\n' "$abs" "$t" >&2
    printf '   Until then branch, diff, base and checks resolved here all describe the wrong repo.\n' >&2
  else
    printf '\xe2\x9a\xa0 ticket %s declares repo %s, which is neither this project (%s) nor a\n' "$t" "'$want'" "'$here'" >&2
    printf '   related_project in config.json. Add it there with its path, or fix .repo.\n' >&2
    printf '   The workflow will not drive a repo it has no record of.\n' >&2
  fi
  return 1
}

# Rewrites a JSON file through jq atomically. Never leaves the temp file behind
# and never reports a success it did not achieve — wf_set_state and
# wf_enter_stage already do this inline; this is the same contract for callers
# that need it more than once.
wf_json_update() {
  local f="$1" tmp rc=1
  shift
  [ -f "$f" ] || return 1
  tmp="$(mktemp)" || return 1
  if jq "$@" "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$f" && rc=0
  fi
  [ -f "$tmp" ] && rm -f "$tmp"
  return "$rc"
}

# Moves a ticket's workflow directory to the repo its code lives in and points
# the active-ticket pointers at the result. Only the location was wrong, so the
# ticket's own state is carried over untouched.
wf_relocate_ticket() {
  local t src want abs dest here_root there_root fail=0
  t="${1:-}"
  [ -n "$t" ] || t="$(wf_ticket)" || { echo "wf-lib: no ticket given and none active" >&2; return 1; }
  here_root="$(wf_workflow_root)"
  src="$here_root/$t"
  [ -d "$src" ] || { echo "wf-lib: no ticket directory at $src" >&2; return 1; }

  want="$(jq -r '.repo // empty' "$src/state.json" 2>/dev/null)"
  [ -n "$want" ] || { echo "wf-lib: $t declares no .repo — nothing to relocate" >&2; return 1; }
  [ "$want" != "$(wf_repo_slug)" ] || { echo "wf-lib: $t already belongs to this project" >&2; return 1; }

  abs="$(wf_related_path "$want")" || {
    echo "wf-lib: repo '$want' is not a related_project with a path in config.json — add it first" >&2; return 1; }
  [ -d "$abs/.git" ] || [ -f "$abs/.git" ] || { echo "wf-lib: $abs is not a git checkout" >&2; return 1; }

  there_root="$abs/.claude/workflow"
  dest="$there_root/$t"
  [ -e "$dest" ] && { echo "wf-lib: $dest already exists — resolve by hand, refusing to merge" >&2; return 1; }

  mkdir -p "$there_root" || return 1
  mv "$src" "$dest" || return 1

  # The move already happened, so from here a failure cannot be undone by
  # returning early: say exactly what is left half-done instead of reporting a
  # success that did not occur.
  printf 'moved %s -> %s\n' "$src" "$dest"

  # Drop the pointer here only if it named the ticket that just left.
  if [ -f "$here_root/state.json" ] && [ "$(jq -r '.activeTicket // empty' "$here_root/state.json" 2>/dev/null)" = "$t" ]; then
    if ! wf_json_update "$here_root/state.json" 'del(.activeTicket)'; then
      printf 'wf-lib: could not clear activeTicket in %s — it still names %s, which has moved. Fix it by hand.\n' \
        "$here_root/state.json" "$t" >&2
      fail=1
    fi
  fi

  # Adopt it there, preserving whatever else that state file holds.
  [ -f "$there_root/state.json" ] || echo '{}' > "$there_root/state.json"
  if wf_json_update "$there_root/state.json" --arg t "$t" '.activeTicket = $t'; then
    printf 'active ticket in %s is now %s\n' "$abs" "$t"
  else
    printf 'wf-lib: %s moved but %s could not be updated — set activeTicket to %s there by hand.\n' \
      "$t" "$there_root/state.json" "$t" >&2
    fail=1
  fi

  [ "$fail" -eq 0 ] || return 1
  printf 'run the workflow for %s from %s from now on\n' "$t" "$abs"
}

wf_is_stage() {
  case " $WF_STAGES " in *" ${1:-} "*) return 0 ;; *) return 1 ;; esac
}

# Rejects an unknown stage, pointing at the closest real one. Stage names reach
# state.json from several directions and a near-miss (`testing` for `test`) is
# not a harmless typo: it silently routes the stage to "no model", which is
# indistinguishable from a stage that legitimately spawns no Agent, so the Agent
# ends up inheriting the session's model — the exact failure wf_model exists to
# prevent.
wf_reject_stage() {
  local stage="$1" v hint="" norm vnorm
  # Compare with separators stripped so mrreview/mr_review reach mr-review, and
  # allow either side to extend the other so testing reaches test.
  norm="$(printf '%s' "$stage" | tr -d '_ -' | tr '[:upper:]' '[:lower:]')"
  for v in $WF_STAGES; do
    vnorm="$(printf '%s' "$v" | tr -d '_-')"
    case "$norm" in "$vnorm"*|*"$vnorm") hint="  Did you mean '$v'?"; break ;; esac
  done
  echo "wf-lib: invalid stage '$stage' (valid: $WF_STAGES)$hint" >&2
  return 1
}

wf_enter_stage() {
  local stage="$1" d f tmp
  [ -n "$stage" ] || return 1

  wf_is_stage "$stage" || { wf_reject_stage "$stage"; return 1; }
  # Refuse to advance a ticket whose code is not in this repo: every later step
  # of the stage would read the wrong tree.
  wf_ticket_repo_check || return 1

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
# Tracker status
# ---------------------------------------------------------------------------
#
# The ticket's status in the tracker has to follow the work: in progress when
# the code starts, in review when the MR opens, onward when it merges. The
# commands said so in prose and it was skipped anyway (PrositeMobile MA-801 and
# MA-803 stayed in To-DO through merge and deploy). A hook cannot do it: hooks
# have no MCP, and putting a tracker token in a script is worse than the gap.
# So the reminder comes out of the very command that marks the moment —
# enter-stage, and the deploy/merge steps — and stays until it is recorded.
#
# Events: start, review, merged, deployed. Their statuses come from
# "tracker": {"transitions": {"start": "In Progress", ...}} in config.json.
WF_TRACKER_EVENTS="start review merged deployed"

wf_tracker_status() {
  wf_config ".tracker.transitions[\"${1:-}\"]"
}

# Prints what to move and how to record it, once per ticket and event. Silent
# for an event already recorded, a ticket with no tracker key (QUICK-…), or a
# project that set "tracker": {"kind": "none"}.
wf_tracker_notice() {
  local ev="${1:-}" t st done
  case " $WF_TRACKER_EVENTS " in *" $ev "*) ;; *) echo "wf-lib: unknown tracker event '$ev' (valid: $WF_TRACKER_EVENTS)" >&2; return 1 ;; esac
  [ "$(wf_config '.tracker.kind')" = "none" ] && return 0
  t="$(wf_ticket)" || return 0
  case "$t" in QUICK-*) return 0 ;; esac
  done="$(wf_state ".tracker[\"$ev\"]" 2>/dev/null)"
  [ -n "$done" ] && return 0
  st="$(wf_tracker_status "$ev")"
  if [ -n "$st" ]; then
    printf '\xf0\x9f\x93\x8c Move %s to "%s" in the tracker now (tracker.transitions.%s), then record it:\n   wf-lib.sh tracker-done %s\n' "$t" "$st" "$ev" "$ev"
  else
    printf '\xf0\x9f\x93\x8c Move %s to its "%s" status in the tracker now, then record it: wf-lib.sh tracker-done %s\n   Name the status once in config.json: "tracker": {"transitions": {"%s": "<status>"}}\n' "$t" "$ev" "$ev" "$ev"
  fi
}

# Records that the ticket was moved for an event, so the notice stops.
wf_tracker_done() {
  local ev="${1:-}" d f st ts
  case " $WF_TRACKER_EVENTS " in *" $ev "*) ;; *) echo "wf-lib: unknown tracker event '$ev' (valid: $WF_TRACKER_EVENTS)" >&2; return 1 ;; esac
  d="$(wf_dir)" || return 1
  f="$d/state.json"
  [ -f "$f" ] || echo '{}' > "$f"
  st="$(wf_tracker_status "$ev")"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  wf_json_update "$f" --arg e "$ev" --arg ts "$ts" --arg st "$st" \
    '.tracker = ((.tracker // {}) + {($e): $ts}) | if $st != "" then .tracker_status = $st else . end'
}

# ---------------------------------------------------------------------------
# CLI: lets it be used without sourcing — `wf-lib.sh ticket`, `wf-lib.sh base`, etc.
# ---------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    ticket)      wf_ticket ;;
    ticket-source) wf_ticket_source ;;
    tickets-root) wf_tickets_root ;;
    worktree)    wf_worktree "${2:-}" ;;
    scope-check) shift; wf_scope_check "$@" ;;
    dir)         wf_dir ;;
    base)        wf_base ;;
    language)    wf_language ;;
    model)       wf_model "$2" ;;
    implement-advice) wf_implement_advice ;;
    config)      wf_config "${2:-.}" ;;
    commits)     wf_commits "${2:-}" ;;
    related-check) wf_related_projects_check ;;
    repo-check)  wf_ticket_repo_check ;;
    relocate)    wf_relocate_ticket "${2:-}" ;;
    state)       wf_state "${2:-.}" ;;
    set-state)   wf_set_state "$2" "$3" ;;
    enter-stage)
      wf_enter_stage "$2" || exit 1
      # The code starts here: the tracker should say so. On stderr, so the
      # stage name stays the only thing on stdout.
      case "$2" in quick|implement) wf_tracker_notice start >&2 ;; esac
      ;;
    tracker-notice) wf_tracker_notice "${2:-}" ;;
    tracker-done)   wf_tracker_done "${2:-}" ;;
    version-notice) wf_version_notice ;;
    context)
      # Printed before the ticket lookup on purpose: a stale install is worth
      # knowing about even in a project with no active ticket, where the lookup
      # below exits 1.
      wf_version_notice
      # `context <ticket>` names the ticket explicitly; it wins over the branch.
      [ -n "${2:-}" ] && export WF_TICKET="$2"
      # Everything a command needs at startup, in one call.
      r="$(wf_ticket_resolve)" || {
        echo "❌ No ticket: branch '$(git branch --show-current 2>/dev/null)' names none and no ticket records it. Ask the user which ticket, then run: wf-lib.sh context <TICKET>" >&2
        exit 1; }
      t="${r%% *}"; src="${r##* }"
      export WF_TICKET="$t"
      st="$(wf_state '.stage')"
      cur="$(git branch --show-current 2>/dev/null)"
      printf 'ticket=%s\nticket_source=%s\ndir=%s\nbase=%s\nstage=%s\nbranch=%s\nworktree=%s\nlang=%s\nmodel=%s\n' \
        "$t" "$src" "$(wf_dir)" "$(wf_base)" "$st" "$cur" "$(wf_repo_root)" "$(wf_language)" "$(wf_model "$st" 2>/dev/null)"
      # The pointer is a memory, not a fact about this checkout: say so, so the
      # ticket is confirmed instead of assumed.
      if [ "$src" = "pointer" ]; then
        printf '\xe2\x9a\xa0 ticket %s comes from the activeTicket pointer: branch %s names no ticket and no ticket records it.\n   Confirm with the user that the work is for %s before writing anything.\n' \
          "$t" "'$cur'" "$t" >&2
      fi
      # A ticket recorded on another branch: this checkout is not where its code is.
      tb="$(wf_state '.branch' 2>/dev/null)"
      if [ -n "$tb" ] && [ -n "$cur" ] && [ "$tb" != "$cur" ]; then
        wt="$(wf_worktree "$t" 2>/dev/null)"
        printf '\xe2\x9a\xa0 ticket %s records branch %s, but this checkout is on %s.%s\n' \
          "$t" "'$tb'" "'$cur'" "${wt:+ Its worktree is $wt — run the workflow from there.}" >&2
      fi
      wf_ticket_repo_check || true
      wf_is_stage "$st" || printf '\xe2\x9a\xa0 stage %s is not a pipeline stage, so no model can be resolved for it and any Agent would inherit the session model. Fix it with: wf-lib.sh set-state stage %s\n' \
        "'$st'" "'<one of: $WF_STAGES>'" >&2
      # A broken related_projects path has to surface at startup, not three
      # stages later when a cross-repo claim is already in a document.
      wf_related_projects_check || true
      ;;
    *)
      echo "usage: wf-lib.sh {ticket|ticket-source|tickets-root|worktree [ticket]|scope-check <files>|dir|base|language|model <stage>|implement-advice|config <path>|commits [ticket]|related-check|repo-check|relocate [ticket]|state <path>|set-state <k> <v>|enter-stage <s>|tracker-notice <event>|tracker-done <event>|context [ticket]}" >&2
      exit 1 ;;
  esac
fi
