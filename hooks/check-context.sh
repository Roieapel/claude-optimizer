#!/usr/bin/env bash
# check-context.sh — PostToolUse hook
#
# Fires after every tool call. Reads context fill % AND waste factor, then:
#
#   Waste factor = current_turn_tokens / first_turn_tokens
#   This matches Claude Code's native compaction metric.
#
#   GREEN  (waste < WASTE_WARN, pct < CTX_WARN)  → compact single-line status
#   YELLOW (waste >= WASTE_WARN OR pct >= CTX_WARN) → advisory warning
#   RED    (waste >= WASTE_ACT  OR pct >= CTX_ACT)  → block + prompt action
#
# Env overrides:
#   CTX_WARN=40       fill % warning threshold
#   CTX_ACT=60        fill % action threshold
#   CTX_WINDOW=200000 total context window (auto-detected from model when possible)
#   WASTE_WARN=2.0    waste factor warning threshold
#   WASTE_ACT=3.0     waste factor action threshold

set -euo pipefail

CTX_WARN=${CTX_WARN:-40}
CTX_ACT=${CTX_ACT:-60}
WASTE_WARN=${WASTE_WARN:-2.0}
WASTE_ACT=${WASTE_ACT:-3.0}

STATE_DIR="$HOME/.claude-optimizer"
TRIGGER_FLAG="$STATE_DIR/trigger.flag"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READ_CONTEXT="$SCRIPT_DIR/../scripts/read-context.js"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Progress bar builder ──────────────────────────────────────────────────────
build_bar() {
  local pct=$1 width=${2:-20} filled=$(( $1 * ${2:-20} / 100 )) bar=""
  local empty=$(( ${2:-20} - filled ))
  for (( i=0; i<filled; i++ )); do bar+="█"; done
  for (( i=0; i<empty;  i++ )); do bar+="░"; done
  echo "$bar"
}

# ── Read transcript path from hook stdin ──────────────────────────────────────
STDIN_DATA=$(cat)
TRANSCRIPT_PATH=$(echo "$STDIN_DATA" | node -e "
  const d=require('fs').readFileSync('/dev/stdin','utf8');
  try { const j=JSON.parse(d); process.stdout.write(j.transcript_path||''); } catch(_) {}
" 2>/dev/null || true)

# ── Run parser ────────────────────────────────────────────────────────────────
RESULT=""
if [[ -n "$TRANSCRIPT_PATH" ]]; then
  RESULT=$(node "$READ_CONTEXT" "$TRANSCRIPT_PATH" 2>/dev/null || true)
fi
if [[ -z "$RESULT" ]]; then
  RESULT=$(node "$READ_CONTEXT" 2>/dev/null || true)
fi

# No data yet (first turn)
if [[ -z "$RESULT" ]]; then
  exit 0
fi

PCT=$(echo "$RESULT" | cut -d' ' -f1)
WASTE=$(echo "$RESULT" | cut -d' ' -f2)

if [[ -z "$PCT" || "$PCT" == "0" ]]; then
  exit 0
fi

# ── Integer waste for bash comparison (multiply by 10, compare as int) ────────
WASTE_INT=$(echo "$WASTE" | awk '{printf "%d", $1 * 10}')
WASTE_WARN_INT=$(echo "$WASTE_WARN" | awk '{printf "%d", $1 * 10}')
WASTE_ACT_INT=$(echo "$WASTE_ACT"  | awk '{printf "%d", $1 * 10}')

# ── Determine state ───────────────────────────────────────────────────────────
IS_RED=false
IS_YELLOW=false

if (( PCT >= CTX_ACT )) || (( WASTE_INT >= WASTE_ACT_INT )); then
  IS_RED=true
elif (( PCT >= CTX_WARN )) || (( WASTE_INT >= WASTE_WARN_INT )); then
  IS_YELLOW=true
fi

# ── Status bar ────────────────────────────────────────────────────────────────

if $IS_RED; then
  mkdir -p "$STATE_DIR"
  touch "$TRIGGER_FLAG"

  BAR=$(build_bar "$PCT" 20)
  printf >&2 "\n${RED}${BOLD}┌─────────────────────────────────────────┐${RESET}\n"
  printf >&2 "${RED}${BOLD}│  ⚠  claude-optimizer                    │${RESET}\n"
  printf >&2 "${RED}${BOLD}│  Context: [%-20s] %3d%%     │${RESET}\n" "$BAR" "$PCT"
  printf >&2 "${RED}${BOLD}│  Waste:   %.1fx (threshold: %.1fx)        │${RESET}\n" "$WASTE" "$WASTE_ACT"
  printf >&2 "${RED}${BOLD}│  ACTION REQUIRED — run /summarize-session│${RESET}\n"
  printf >&2 "${RED}${BOLD}└─────────────────────────────────────────┘${RESET}\n\n"
  exit 2

elif $IS_YELLOW; then
  BAR=$(build_bar "$PCT" 20)
  printf >&2 "\n${YELLOW}${BOLD}┌─────────────────────────────────────────┐${RESET}\n"
  printf >&2 "${YELLOW}${BOLD}│  ⚡ claude-optimizer                    │${RESET}\n"
  printf >&2 "${YELLOW}${BOLD}│  Context: [%-20s] %3d%%     │${RESET}\n" "$BAR" "$PCT"
  printf >&2 "${YELLOW}${BOLD}│  Waste:   %.1fx (threshold: %.1fx)        │${RESET}\n" "$WASTE" "$WASTE_ACT"
  printf >&2 "${YELLOW}${BOLD}│  Wrapping up soon?                      │${RESET}\n"
  printf >&2 "${YELLOW}${BOLD}└─────────────────────────────────────────┘${RESET}\n\n"
  exit 0

else
  BAR=$(build_bar "$PCT" 20)
  printf >&2 "${GREEN}│ claude-optimizer  [%-20s] %3d%%  %.1fx${RESET}\n" "$BAR" "$PCT" "$WASTE"
  exit 0
fi
