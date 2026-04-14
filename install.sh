#!/usr/bin/env bash
# install.sh — claude-optimizer one-command setup
#
# What this does:
#   1. Validates dependencies (node ≥18, jq)
#   2. Makes hook scripts executable
#   3. Installs the /summarize-session skill into ~/.claude/commands/
#   4. Registers hooks in ~/.claude/settings.json (PostToolUse, SessionStart, Stop)
#   5. Creates ~/.claude-optimizer/ runtime directory
#
# Usage:  bash install.sh
# Uninstall: bash install.sh --uninstall

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}✓${RESET}  $*"; }
warn() { echo -e "${YELLOW}⚠${RESET}  $*"; }
err()  { echo -e "${RED}✗${RESET}  $*" >&2; }
hdr()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Paths ─────────────────────────────────────────────────────────────────────

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
CLAUDE_COMMANDS="$CLAUDE_DIR/commands"
OPTIMIZER_DIR="$HOME/.claude-optimizer"
SKILL_SRC="$REPO_DIR/skills/summarize-session/SKILL.md"
SKILL_DEST="$CLAUDE_COMMANDS/summarize-session.md"

HOOK_CHECK="$REPO_DIR/hooks/check-context.sh"
HOOK_START="$REPO_DIR/hooks/session-start.sh"
HOOK_CAPTURE="$REPO_DIR/hooks/capture-summary.sh"

# ── Uninstall ─────────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--uninstall" ]]; then
  hdr "Uninstalling claude-optimizer…"

  # Remove skill
  if [[ -f "$SKILL_DEST" ]]; then
    rm -f "$SKILL_DEST"
    ok "Removed $SKILL_DEST"
  fi

  # Remove hooks from settings.json
  if [[ -f "$CLAUDE_SETTINGS" ]] && command -v jq &>/dev/null; then
    ESCAPED_CHECK=$(echo "$HOOK_CHECK" | sed 's/[\/&]/\\&/g')
    ESCAPED_START=$(echo "$HOOK_START" | sed 's/[\/&]/\\&/g')
    ESCAPED_CAPTURE=$(echo "$HOOK_CAPTURE" | sed 's/[\/&]/\\&/g')

    TMP=$(mktemp)
    jq --arg check "$HOOK_CHECK" \
       --arg start "$HOOK_START" \
       --arg capture "$HOOK_CAPTURE" '
      .hooks.PostToolUse  = ((.hooks.PostToolUse  // []) | map(select(.hooks[0].command != $check)))   |
      .hooks.SessionStart = ((.hooks.SessionStart // []) | map(select(.hooks[0].command != $start)))   |
      .hooks.Stop         = ((.hooks.Stop         // []) | map(select(.hooks[0].command != $capture)))
    ' "$CLAUDE_SETTINGS" > "$TMP" && mv "$TMP" "$CLAUDE_SETTINGS"
    ok "Removed hooks from $CLAUDE_SETTINGS"
  fi

  echo ""
  ok "Uninstall complete. Runtime dir $OPTIMIZER_DIR was left in place (delete manually if desired)."
  exit 0
fi

# ── Check dependencies ────────────────────────────────────────────────────────

hdr "Checking dependencies…"

# node ≥18
if ! command -v node &>/dev/null; then
  err "node is not installed. Install Node.js 18+ from https://nodejs.org"
  exit 1
fi
NODE_VER=$(node -e 'process.stdout.write(process.versions.node)')
NODE_MAJOR="${NODE_VER%%.*}"
if (( NODE_MAJOR < 18 )); then
  err "node ${NODE_VER} found but ≥18 is required."
  exit 1
fi
ok "node ${NODE_VER}"

# jq (used by install, not hooks — hooks use node)
if ! command -v jq &>/dev/null; then
  warn "jq not found — settings.json will be written with a Node.js fallback."
  USE_JQ=false
else
  ok "jq $(jq --version)"
  USE_JQ=true
fi

# ── Make scripts executable ───────────────────────────────────────────────────

hdr "Making hook scripts executable…"
chmod +x "$HOOK_CHECK" "$HOOK_START" "$HOOK_CAPTURE"
ok "hooks/check-context.sh"
ok "hooks/session-start.sh"
ok "hooks/capture-summary.sh"

# ── Install /summarize-session skill ─────────────────────────────────────────

hdr "Installing /summarize-session skill…"
mkdir -p "$CLAUDE_COMMANDS"
cp "$SKILL_SRC" "$SKILL_DEST"
ok "Installed to $SKILL_DEST"
echo "   Run it inside Claude Code with:  /summarize-session"

# ── Create runtime directory ──────────────────────────────────────────────────

hdr "Creating runtime directory…"
mkdir -p "$OPTIMIZER_DIR"
ok "$OPTIMIZER_DIR"

# ── Register hooks in settings.json ──────────────────────────────────────────

hdr "Registering hooks in $CLAUDE_SETTINGS"

# Ensure settings file exists
mkdir -p "$CLAUDE_DIR"
if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
  echo '{}' > "$CLAUDE_SETTINGS"
fi

# Build hook entries using Node (always available)
node - "$CLAUDE_SETTINGS" "$HOOK_CHECK" "$HOOK_START" "$HOOK_CAPTURE" <<'JSEOF'
const fs   = require('fs');
const path = require('path');

const [,, settingsPath, hookCheck, hookStart, hookCapture] = process.argv;

let settings = {};
try {
  settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
} catch (_) {}

if (!settings.hooks) settings.hooks = {};

// Helper: upsert a hook entry (deduplicate by command path)
function upsertHook(arr, command) {
  const entry = { matcher: '', hooks: [{ type: 'command', command }] };
  const existing = (arr || []).filter(e => {
    return !(e.hooks && e.hooks[0] && e.hooks[0].command === command);
  });
  return [...existing, entry];
}

settings.hooks.PostToolUse  = upsertHook(settings.hooks.PostToolUse,  `bash "${hookCheck}"`);
settings.hooks.SessionStart = upsertHook(settings.hooks.SessionStart, `bash "${hookStart}"`);
settings.hooks.Stop         = upsertHook(settings.hooks.Stop,         `bash "${hookCapture}"`);

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');
process.stdout.write('ok\n');
JSEOF

ok "PostToolUse  → hooks/check-context.sh"
ok "SessionStart → hooks/session-start.sh"
ok "Stop         → hooks/capture-summary.sh"

# ── Smoke-test the parser ─────────────────────────────────────────────────────

hdr "Smoke-testing read-context.js…"
PCT_OUT=$(node "$REPO_DIR/scripts/read-context.js" 2>/dev/null || true)
if [[ -z "$PCT_OUT" ]]; then
  warn "read-context.js returned no data (no active Claude Code session logs found — this is normal before first use)."
else
  ok "read-context.js returned: ${PCT_OUT}%"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${GREEN}claude-optimizer installed successfully!${RESET}"
echo ""
echo "  Warn threshold  : ${CTX_WARN:-40}%   (override: export CTX_WARN=<n>)"
echo "  Action threshold: ${CTX_ACT:-60}%   (override: export CTX_ACT=<n>)"
echo "  Context window  : ${CTX_WINDOW:-200000} tokens (override: export CTX_WINDOW=<n>)"
echo ""
echo "  Runtime files   : $OPTIMIZER_DIR"
echo "  Skill           : /summarize-session"
echo ""
echo "  To uninstall    : bash install.sh --uninstall"
echo ""
