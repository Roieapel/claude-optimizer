#!/usr/bin/env bash
# show-status.sh — Stop hook
#
# Fires after each Claude Code response (when Claude stops generating).
# Reads state.json and displays the context status bar — always AFTER
# Claude's full response, never mixed with tool output or logs.
#
# RED state is intentionally excluded here — the blocking red alert is
# handled by check-context.sh (PostToolUse, exit 2) which fires mid-response
# so it can actually block the tool call.

set -euo pipefail

CTX_WARN=${CTX_WARN:-40}
WASTE_WARN=${WASTE_WARN:-2.0}

STATE_DIR="$HOME/.claude-optimizer"
STATE_FILE="$STATE_DIR/state.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

read -r PCT WASTE < <(node -e "
  try {
    const s = JSON.parse(require('fs').readFileSync('$STATE_FILE', 'utf8'));
    process.stdout.write((s.pct || 0) + ' ' + (s.waste_factor || 1.0));
  } catch(_) { process.stdout.write('0 1.0'); }
" 2>/dev/null) || true

if [[ -z "$PCT" || "$PCT" == "0" ]]; then
  exit 0
fi

build_bar() {
  local pct=$1 filled=$(( $1 * 20 / 100 )) bar=""
  local empty=$(( 20 - filled ))
  for (( i=0; i<filled; i++ )); do bar+="█"; done
  for (( i=0; i<empty;  i++ )); do bar+="░"; done
  echo "$bar"
}

WASTE_INT=$(echo "$WASTE" | awk '{printf "%d", $1 * 10}')
WASTE_WARN_INT=$(echo "$WASTE_WARN" | awk '{printf "%d", $1 * 10}')
BAR=$(build_bar "$PCT")

if (( PCT >= CTX_WARN )) || (( WASTE_INT >= WASTE_WARN_INT )); then
  { printf "\n${YELLOW}${BOLD}┌─────────────────────────────────────────┐${RESET}\n"
    printf "${YELLOW}${BOLD}│  ⚡ claude-optimizer                    │${RESET}\n"
    printf "${YELLOW}${BOLD}│  Context: [%-20s] %3d%%     │${RESET}\n" "$BAR" "$PCT"
    printf "${YELLOW}${BOLD}│  Waste:   %.1fx (threshold: %.1fx)        │${RESET}\n" "$WASTE" "$WASTE_WARN"
    printf "${YELLOW}${BOLD}│  Wrapping up soon?                      │${RESET}\n"
    printf "${YELLOW}${BOLD}└─────────────────────────────────────────┘${RESET}\n"
  } > /dev/tty
else
  printf "${GREEN}│ claude-optimizer  [%-20s] %3d%%  %.1fx${RESET}\n" "$BAR" "$PCT" "$WASTE" > /dev/tty
fi

exit 0
