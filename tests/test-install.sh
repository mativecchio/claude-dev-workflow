#!/bin/bash
#
# Validates install.sh against a sandbox HOME. It never touches the real ~/.claude.
#
# Usage:  ./tests/test-install.sh
#
# Covers the failure modes that motivated Phase 0 of the harness migration
# (docs/plan-harness-migration.md): orphaned commands, a global config that
# never received repo_path, and the CLAUDE.md block that stayed frozen.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

echo "═══ CASE 1 — clean install ═══"
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1 || echo "  (install returned $?)"
C="$SB/.claude"
check "commands installed (15)"          "[ \$(ls $C/commands/wf*.md | wc -l) -eq 15 ]"
check "wf-commit.md installed"           "[ -f $C/commands/wf-commit.md ]"
check "wf-deploy.md installed"           "[ -f $C/commands/wf-deploy.md ]"
check "improvements.md created"          "[ -s $C/workflow/improvements.md ]"
check "repo_path written"                "[ \"\$(jq -r .repo_path $C/workflow/config.json)\" = \"$REPO\" ]"
check "telemetry hook copied"            "[ -x $C/hooks/wf-telemetry.sh ]"
check "hooks registered in settings"     "[ \$(jq '[.hooks[][].hooks[].command] | map(select(contains(\"wf-telemetry\"))) | length' $C/settings.json) -eq 4 ]"
check "CLAUDE.md lists wf-deploy"        "grep -q 'wf-deploy' $C/CLAUDE.md"
check "CLAUDE.md lists wf-init"          "grep -q 'wf-init' $C/CLAUDE.md"

echo "═══ CASE 2 — --check after a clean install ═══"
OUT="$(HOME="$SB" "$REPO/install.sh" --check 2>&1)"; RC=$?
check "--check exits 0"                  "[ $RC -eq 0 ]"
check "--check reports no divergences"   "echo \"\$OUT\" | grep -q 'No divergences'"

echo "═══ CASE 3 — preexisting global config WITHOUT repo_path (the real case) ═══"
echo '{"preferences":{"language":"es"},"my_key":42}' > "$C/workflow/config.json"
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1
check "repo_path was merged"             "[ \"\$(jq -r .repo_path $C/workflow/config.json)\" = \"$REPO\" ]"
check "preexisting keys preserved"       "[ \$(jq -r .my_key $C/workflow/config.json) -eq 42 ]"

echo "═══ CASE 4 — CLAUDE.md with an old block + the user's own content ═══"
cat > "$C/CLAUDE.md" << 'EOD'
# My personal notes
This is my own content that must NOT be touched.

<!-- claude-workflow -->
## Dev Workflow System
| `/wf-refine` | old |
<!-- /claude-workflow -->

## Another section of mine
This must survive too.
EOD
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1
check "preceding content preserved"      "grep -q 'my own content that must NOT be touched' $C/CLAUDE.md"
check "following content preserved"      "grep -q 'This must survive too' $C/CLAUDE.md"
check "block regenerated (wf-deploy)"    "grep -q 'wf-deploy' $C/CLAUDE.md"
check "no duplicated block"              "[ \$(grep -c '^<!-- claude-workflow -->' $C/CLAUDE.md) -eq 1 ]"
check "single closing marker"            "[ \$(grep -c '^<!-- /claude-workflow -->' $C/CLAUDE.md) -eq 1 ]"

echo "═══ CASE 5 — settings.json with third-party hooks ═══"
jq '.hooks.Stop += [{"hooks":[{"type":"command","command":"afplay /System/Library/Sounds/Ping.aiff"}]}]' \
   "$C/settings.json" > "$C/s.tmp" && mv "$C/s.tmp" "$C/settings.json"
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1
check "third-party hook preserved"       "grep -q 'afplay' $C/settings.json"
check "telemetry not duplicated"         "[ \$(jq '[.hooks[][].hooks[].command] | map(select(contains(\"wf-telemetry\"))) | length' $C/settings.json) -eq 4 ]"

echo "═══ CASE 6 — --check detects orphans and divergences ═══"
echo "# command with no origin in the repo" > "$C/commands/wf-invented.md"
echo "modified" >> "$C/commands/wf-test.md"
OUT="$(HOME="$SB" "$REPO/install.sh" --check 2>&1)"; RC=$?
check "--check exits 1"                  "[ $RC -eq 1 ]"
check "detects the orphan"               "echo \"\$OUT\" | grep -q 'orphan.*wf-invented'"
check "detects the divergent file"       "echo \"\$OUT\" | grep -q 'differs: wf-test.md'"

echo "═══ CASE 7 — versioning ═══"
rm -f "$C/commands/wf-invented.md"
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1
V="$(cat "$REPO/VERSION" | tr -d '[:space:]')"
check "installed_version stamped"        "[ \"\$(jq -r '.installed_version' $C/workflow/config.json)\" = \"$V\" ]"
check "dead 'preferences' key removed"   "[ \"\$(jq -r '.preferences // \"gone\"' $C/workflow/config.json)\" = \"gone\" ]"
check "dead 'projects' key removed"      "[ \"\$(jq -r '.projects // \"gone\"' $C/workflow/config.json)\" = \"gone\" ]"
check "SessionStart hook not registered" "! jq -e '.hooks.SessionStart' $C/settings.json >/dev/null 2>&1"
check "stale wf-version.sh hook removed"  "[ ! -f $C/hooks/wf-version.sh ]"
check "--check reports the version"      "HOME=$SB $REPO/install.sh --check 2>&1 | grep -q 'version: repo $V'"

# Upgrade path from 0.5.1, which did register a SessionStart hook: reinstalling
# has to remove it, not leave it firing forever against a deleted script.
jq '.hooks.SessionStart = [{"hooks":[{"type":"command","command":"'"$C"'/hooks/wf-version.sh"}]}]' \
   "$C/settings.json" > "$C/s.tmp" && mv "$C/s.tmp" "$C/settings.json"
touch "$C/hooks/wf-version.sh"
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1
check "upgrade strips the old SessionStart" "! jq -e '.hooks.SessionStart' $C/settings.json >/dev/null 2>&1"
check "upgrade deletes the old hook file"   "[ ! -f $C/hooks/wf-version.sh ]"

# The same reinstall must not disturb a SessionStart hook the user owns.
jq '.hooks.SessionStart = [{"hooks":[{"type":"command","command":"my-own-thing"}]}]' \
   "$C/settings.json" > "$C/s.tmp" && mv "$C/s.tmp" "$C/settings.json"
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1
check "third-party SessionStart survives"   "grep -q 'my-own-thing' $C/settings.json"

echo "═══ CASE 8 — a machine without jq ═══"
# The one machine that most needs a clear diagnosis is the one missing jq.
# --check used to abort there with no message and exit 127, because the version
# lookup failed under `set -e`.
BIN="$(mktemp -d)"
for t in bash cat tr find basename diff git sed grep wc mktemp mv rm ls dirname sort comm awk; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$BIN/$t"
done
HOME="$SB" "$REPO/install.sh" >/dev/null 2>&1
OUT="$(PATH="$BIN" HOME="$SB" "$REPO/install.sh" --check 2>&1)"; RC=$?
check "--check without jq doesn't abort"  "[ $RC -ne 127 ]"
check "--check without jq explains why"   "echo \"\$OUT\" | grep -q 'jq is not installed'"
check "--check without jq: no false drift" "! echo \"\$OUT\" | grep -q 'installed version does not match'"
rm -rf "$BIN"

echo ""
echo "═══════════════════════════"
echo "  ✅ $PASS   ❌ $FAIL"
rm -rf "$SB"
[ "$FAIL" -eq 0 ]
