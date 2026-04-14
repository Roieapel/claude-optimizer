#!/usr/bin/env bash
# check-context.sh — PostToolUse hook
#
# Runs after every tool call. Reads context fill % from the JSONL log and:
#   0–39%   → green status bar (always visible so you know the tool is running)
#   40–59%  → yellow warning bar
#   60%+    → red alert, creates trigger.flag, exits 2 (blocks tool, prompts action)
#
# Claude Code PostToolUse exit codes:
#   0   = allow tool result through unchanged
#   2   = block tool result; stderr message shown to Claude as an error
#
# Env overrides: CTX_WARN (default 40), CTX_ACT (default 60), CTX_WINDOW (default 200000)

set -euo pipefail

CTX_WARN=${CTX_WARN:-40}
CTX_ACT=${CTX_ACT:-60}

STATE_DIR="$HOME/.claude-optimizer"
TRIGGER_FLAG="$STATE_DIR/trigger.flag"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READ_CONTEXT="$SCRIPT_DIR/../scripts/read-context.js"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
RESET='\033[0m'
BOLD='\033[1m'

# ── Progress bar builder ──────────────────────────────────────────────────────
# build_bar PCT FILLED_CHAR EMPTY_CHAR WIDTH
build_bar() {
  local pct=$1 filled_char=$2 empty_char=$3 width=${4:-20}
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""
  for (( i=0; i<filled; i++ )); do bar+="$filled_char"; done
  for (( i=0; i<empty;  i++ )); do bar+="$empty_char";  done
  echo "$bar"
}

# ── Run parser ────────────────────────────────────────────────────────────────

PCT=$(node "$READ_CONTEXT" 2>/dev/null || true)

# No data yet — skip silently (first turn, no usage recorded yet)
if [[ -z "$PCT" || "$PCT" == "0" ]]; then
  exit 0
fi

# ── Status bar ────────────────────────────────────────────────────────────────

if (( PCT >= CTX_ACT )); then
  # ── RED: action required ──────────────────────────────────────────────────
  mkdir -p "$STATE_DIR"
  touch "$TRIGGER_FLAG"

  BAR=$(build_bar "$PCT" "█" "░" 20)
  printf >&2 "\n${RED}${BOLD}┌─────────────────────────────────────────┐${RESET}\n"
  printf >&2 "${RED}${BOLD}│  ⚠  claude-optimizer                    │${RESET}\n"
  printf >&2 "${RED}${BOLD}│  Context: [%-20s] %3d%%     │${RESET}\n" "$BAR" "$PCT"
  printf >&2 "${RED}${BOLD}│  ACTION REQUIRED — run /summarize-session│${RESET}\n"
  printf >&2 "${RED}${BOLD}└─────────────────────────────────────────┘${RESET}\n\n"
  # Exit 2 blocks the current tool call and surfaces this message
  exit 2

elif (( PCT >= CTX_WARN )); then
  # ── YELLOW: warning ───────────────────────────────────────────────────────
  BAR=$(build_bar "$PCT" "█" "░" 20)
  printf >&2 "\n${YELLOW}${BOLD}┌─────────────────────────────────────────┐${RESET}\n"
  printf >&2 "${YELLOW}${BOLD}│  ⚡ claude-optimizer                    │${RESET}\n"
  printf >&2 "${YELLOW}     Context: [%-20s] %3d%%     ${RESET}\n" "$BAR" "$PCT"
  printf >&2 "${YELLOW}     Warn threshold: %d%% — wrapping up soon?${RESET}\n" "$CTX_WARN"
  printf >&2 "${YELLOW}${BOLD}└─────────────────────────────────────────┘${RESET}\n\n"
  exit 0

else
  # ── GREEN: healthy ────────────────────────────────────────────────────────
  BAR=$(build_bar "$PCT" "█" "░" 20)
  printf >&2 "\n${GREEN}│ claude-optimizer  [%-20s] %3d%%${RESET}\n\n" "$BAR" "$PCT"
  exit 0
fi
