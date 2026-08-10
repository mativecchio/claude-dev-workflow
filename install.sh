#!/bin/bash

# claude-workflow — install script
# Copies commands and agents into ~/.claude/ for global use

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
AGENTS_DIR="$CLAUDE_DIR/agents"
WORKFLOW_DIR="$CLAUDE_DIR/workflow"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
SETTINGS="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

# --- --check mode: report divergences without writing anything -------------
# The repo is the source of truth. /wf-retro and /wf-improve edit the repo and
# reinstall; this mode verifies that discipline hasn't been broken.
if [ "${1:-}" = "--check" ]; then
  echo "🔍 Comparing repo vs installed..."
  DIVERGENCES=0

  for f in "$REPO_DIR/commands/"*.md; do
    b="$(basename "$f")"
    if [ ! -f "$COMMANDS_DIR/$b" ]; then
      echo "  ✗ missing from install: $b"
      DIVERGENCES=$((DIVERGENCES + 1))
    elif ! diff -q "$f" "$COMMANDS_DIR/$b" >/dev/null 2>&1; then
      echo "  ✗ differs: $b"
      DIVERGENCES=$((DIVERGENCES + 1))
    fi
  done

  # Installed wf-* commands with no origin in the repo: the failure mode that
  # left wf-commit and wf-deploy orphaned.
  for f in "$COMMANDS_DIR/"wf-*.md; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    if [ ! -f "$REPO_DIR/commands/$b" ]; then
      echo "  ✗ orphan (installed with no origin in the repo): $b"
      DIVERGENCES=$((DIVERGENCES + 1))
    fi
  done

  while IFS= read -r f; do
    b="$(basename "$f")"
    if [ ! -f "$AGENTS_DIR/$b" ] || ! diff -q "$f" "$AGENTS_DIR/$b" >/dev/null 2>&1; then
      echo "  ✗ agent differs or is missing: $b"
      DIVERGENCES=$((DIVERGENCES + 1))
    fi
  done < <(find "$REPO_DIR/agents" -name "*.md")

  for h in "$REPO_DIR/hooks/"*.sh; do
    [ -e "$h" ] || continue
    b="$(basename "$h")"
    if [ ! -f "$HOOKS_DIR/$b" ] || ! diff -q "$h" "$HOOKS_DIR/$b" >/dev/null 2>&1; then
      echo "  ✗ hook differs or is missing: $b"
      DIVERGENCES=$((DIVERGENCES + 1))
    fi
  done

  for s in "$REPO_DIR/scripts/"*.sh; do
    [ -e "$s" ] || continue
    b="$(basename "$s")"
    if [ ! -f "$SCRIPTS_DIR/$b" ] || ! diff -q "$s" "$SCRIPTS_DIR/$b" >/dev/null 2>&1; then
      echo "  ✗ script differs or is missing: $b"
      DIVERGENCES=$((DIVERGENCES + 1))
    fi
  done

  if [ "$DIVERGENCES" -eq 0 ]; then
    echo "✅ No divergences — the repo and the installed copy match"
    exit 0
  fi
  echo ""
  echo "⚠️  $DIVERGENCES divergence(s). Run install.sh to sync,"
  echo "    or port back to the repo whatever was edited in $CLAUDE_DIR."
  exit 1
fi

echo "📦 Installing claude-workflow from $REPO_DIR..."

# Create directories if they don't exist
mkdir -p "$COMMANDS_DIR"
mkdir -p "$AGENTS_DIR"
mkdir -p "$WORKFLOW_DIR"

# Copy wf-* commands
echo "→ Copying commands..."
cp "$REPO_DIR/commands/"*.md "$COMMANDS_DIR/"
echo "  ✓ $(ls "$REPO_DIR/commands/"*.md | wc -l | tr -d ' ') commands installed in $COMMANDS_DIR"

# Copy scripts (wf-lib, wf-diff, wf-checks): the commands call them by a fixed
# path, so they have to be installed before any command runs.
echo "→ Copying scripts..."
mkdir -p "$SCRIPTS_DIR"
cp "$REPO_DIR/scripts/"*.sh "$SCRIPTS_DIR/"
chmod +x "$SCRIPTS_DIR/"*.sh
echo "  ✓ $(ls "$REPO_DIR/scripts/"*.sh | wc -l | tr -d ' ') scripts installed in $SCRIPTS_DIR"

# Copy agents
echo "→ Copying agents..."
find "$REPO_DIR/agents" -name "*.md" -exec cp {} "$AGENTS_DIR/" \;
echo "  ✓ $(find "$REPO_DIR/agents" -name "*.md" | wc -l | tr -d ' ') agents installed in $AGENTS_DIR"

# Global config. `repo_path` is ALWAYS merged, not only when creating the file:
# leaving the config untouched meant every previous installation never got the
# key, and /wf-retro and /wf-improve need it to edit the repo instead of ~/.claude.
if [ ! -f "$WORKFLOW_DIR/config.json" ]; then
  cp "$REPO_DIR/config/workflow.json" "$WORKFLOW_DIR/config.json"
  echo "  ✓ Config initialized at $WORKFLOW_DIR/config.json"
fi

if command -v jq >/dev/null 2>&1 && jq -e . "$WORKFLOW_DIR/config.json" >/dev/null 2>&1; then
  TMP="$(mktemp)"
  if jq --arg p "$REPO_DIR" '.repo_path = $p' "$WORKFLOW_DIR/config.json" > "$TMP" 2>/dev/null; then
    mv "$TMP" "$WORKFLOW_DIR/config.json"
    echo "  ✓ repo_path points to $REPO_DIR"
  else
    rm -f "$TMP"
    echo "  ⚠ Could not write repo_path into the global config"
  fi
else
  echo "  ⚠ Global config.json missing or invalid — repo_path NOT configured."
  echo "    /wf-retro and /wf-improve will fall back to manual mode."
fi

# Initialize flow-history if it doesn't exist
if [ ! -f "$WORKFLOW_DIR/flow-history.json" ]; then
  echo '{"entries": []}' > "$WORKFLOW_DIR/flow-history.json"
  echo "  ✓ flow-history.json initialized"
fi

# Logbook of workflow changes (brainstorm §0 and §8): every applied change is
# recorded here with its evidence. Without this, the grounding rule has nowhere
# to be written down.
if [ ! -f "$WORKFLOW_DIR/improvements.md" ]; then
  cat > "$WORKFLOW_DIR/improvements.md" << 'IMPEOF'
# Improvements — logbook of workflow changes

> Rule (`docs/brainstorm-metrics-and-complexity.md` §0): no change is recorded
> here without its evidence. If the evidence can't be written down, the change
> isn't applied.

Format of each entry:

```
## [date] — [affected component]
**Change:** what was modified
**Evidence:** file:line, or the concrete query over events.jsonl
  (event category, number of tickets, period)
**Expected result:** which metric should move
```

---
IMPEOF
  echo "  ✓ improvements.md initialized"
fi

# --- Telemetry (docs/brainstorm-metrics-and-complexity.md §3.2) --------------
echo "→ Installing hooks..."
mkdir -p "$HOOKS_DIR"
cp "$REPO_DIR/hooks/wf-telemetry.sh" "$REPO_DIR/hooks/wf-gate.sh" "$HOOKS_DIR/"
chmod +x "$HOOKS_DIR/wf-telemetry.sh" "$HOOKS_DIR/wf-gate.sh"
touch "$WORKFLOW_DIR/events.jsonl"

if ! command -v jq >/dev/null 2>&1; then
  echo "  ⚠ jq is not installed — the hooks will exit without recording anything."
  echo "    Install it with: brew install jq"
else
  # Register the hooks in settings.json, preserving any that already exist.
  # Idempotent: any previous wf-telemetry entry is stripped first.
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

  if jq -e . "$SETTINGS" >/dev/null 2>&1; then
    TMP="$(mktemp)"
    jq --arg h "$HOOKS_DIR/wf-telemetry.sh" --arg g "$HOOKS_DIR/wf-gate.sh" '
      def strip($needle):
        map(.hooks |= map(select((.command // "") | contains($needle) | not)))
        | map(select((.hooks | length) > 0));
      def add($cmd):
        . + [{hooks: [{type: "command", command: $cmd}]}];

      .hooks                    //= {}
      | .hooks.UserPromptSubmit //= [] | .hooks.UserPromptSubmit |= (strip("wf-telemetry.sh") | add($h + " prompt"))
      | .hooks.PostToolUse      //= [] | .hooks.PostToolUse      |= (strip("wf-telemetry.sh") | add($h + " tool"))
      | .hooks.Stop             //= [] | .hooks.Stop             |= (strip("wf-telemetry.sh") | add($h + " stop"))
      | .hooks.SessionEnd       //= [] | .hooks.SessionEnd       |= (strip("wf-telemetry.sh") | add($h + " session-end"))
      | .hooks.PreToolUse       //= [] | .hooks.PreToolUse       |= (strip("wf-gate.sh")      | add($g))
    ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
    echo "  ✓ Hooks registered in $SETTINGS (existing hooks preserved)"
    echo "    wf-gate.sh stays in observe mode: it records what it would have"
    echo "    blocked without preventing anything. Enable it with WF_GATE=enforce"
    echo "    once the gate_would_block events confirm it fires where it should."
  else
    echo "  ⚠ $SETTINGS is not valid JSON — hooks NOT registered."
    echo "    Fix the file and run install.sh again"
  fi
fi

# Workflow section in the global CLAUDE.md.
#
# The block between the markers is REGENERATED on every install. The previous
# version skipped if the marker existed, so an old installation kept the command
# list from that moment forever — the same failure mode that left wf-commit and
# wf-deploy orphaned, in another channel. Anything outside the markers is never
# touched.
[ -f "$CLAUDE_MD" ] || touch "$CLAUDE_MD"

BLOCK="$(mktemp)"
cat > "$BLOCK" << 'EOF'
<!-- claude-workflow -->
## Dev Workflow System

Slash commands are available for the full development cycle. Use them whenever the user is working on a development task.

### Main flow
| Command | Purpose |
|---|---|
| `/wf` | Orchestrator — detects the stage and routes |
| `/wf-init` | Initializes the workflow in a project (once per repo) |
| `/wf-refine` | Clarify scope and DoD |
| `/wf-analyze` | Technical analysis → generates plan.md |
| `/wf-review-plan` | Verifies the plan against the real codebase |
| `/wf-implement` | Implementation with checkpoints |
| `/wf-validate` | Post-implementation validation gate |
| `/wf-test` | Tests and pre-MR checklist |
| `/wf-commit` | Commit message with ticket context |
| `/wf-deploy` | Commit+push, release branch and deploy |
| `/wf-mr-desc` | MR description |
| `/wf-mr-review` | Code review of the MR |
| `/wf-retro` | Retrospective and workflow improvement |
| `/wf-improve` | Record an observation, or review everything accumulated |
| `/wf-jira` | Generate or enrich a Jira ticket |

### Available language agents
React Native: `rn-architect`, `rn-debugger`, `rn-performance`, `rn-testing`, `rn-uiux`, `rn-bridge`
React: `react-architect`
TypeScript: `typescript-architect`
Python: `python-architect`
Laravel: `laravel-architect`
ML / CV: `ml-architect`, `ml-evaluator`, `ml-testing`, `cv-engineer`
API: `backend-api`

### Workflow state
Supports multiple tickets. The root state only records which one is active:
- `.claude/workflow/state.json` — `{ "activeTicket": "BC-XXXX" }`
- `.claude/workflow/{ticketId}/state.json` — stage, progress, branch
- `.claude/workflow/{ticketId}/` — refinement-summary.md, plan.md, review-findings.md
- `.claude/workflow/config.json` — stack, DoD, related_projects

### Improving the system
The source repo (`repo_path` in `~/.claude/workflow/config.json`) is the source of truth.
Never edit `~/.claude/commands/` directly — it's lost on the next install.
Check that they're in sync: `install.sh --check`
<!-- /claude-workflow -->
EOF

if grep -q "<!-- claude-workflow -->" "$CLAUDE_MD" 2>/dev/null; then
  TMP="$(mktemp)"
  # Copies everything outside the block and injects the new version in its place.
  awk -v blockfile="$BLOCK" '
    /<!-- claude-workflow -->/ { while ((getline line < blockfile) > 0) print line; skip=1; next }
    /<!-- \/claude-workflow -->/ { skip=0; next }
    !skip { print }
  ' "$CLAUDE_MD" > "$TMP" && mv "$TMP" "$CLAUDE_MD"
  echo "  ✓ CLAUDE.md section regenerated"
else
  { echo ""; cat "$BLOCK"; } >> "$CLAUDE_MD"
  echo "  ✓ Section added to $CLAUDE_MD"
fi
rm -f "$BLOCK"

echo ""
echo "✅ claude-workflow installed successfully"
echo ""
echo "Available commands: /wf, /wf-init, /wf-refine, /wf-analyze, /wf-review-plan,"
echo "  /wf-implement, /wf-validate, /wf-test, /wf-commit, /wf-deploy,"
echo "  /wf-mr-desc, /wf-mr-review, /wf-retro, /wf-improve, /wf-jira"
echo ""
echo "To set up a new project: run /wf-init from its root."
echo "To verify that repo and installation match: install.sh --check"
