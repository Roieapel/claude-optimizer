#!/usr/bin/env bash
# check-efficiency.sh — Reports on claude-optimizer summarization efficiency
#
# Measures:
#   - Token count of the latest summary vs original conversation
#   - Compression ratio
#   - Summary structure validity (required fields present)
#   - Historical compression trend (from history.jsonl)
#
# Usage:
#   bash scripts/check-efficiency.sh           # latest summary
#   bash scripts/check-efficiency.sh --history # include all past summaries

set -euo pipefail

STATE_DIR="$HOME/.claude-optimizer"
SUMMARY_FILE="$STATE_DIR/summary.json"
STATE_FILE="$STATE_DIR/state.json"
HISTORY_FILE="$STATE_DIR/history.jsonl"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

SHOW_HISTORY=false
[[ "${1:-}" == "--history" ]] && SHOW_HISTORY=true

# ── Helpers ───────────────────────────────────────────────────────────────────

# Rough token estimate: chars / 4 (standard GPT approximation)
token_estimate() {
  local text="$1"
  echo $(( ${#text} / 4 ))
}

# Color a compression ratio: green <10%, yellow 10-25%, red >25%
ratio_color() {
  local pct=$1
  if   (( pct < 10 )); then printf "${GREEN}"
  elif (( pct < 25 )); then printf "${YELLOW}"
  else                      printf "${RED}"
  fi
}

# Check presence of required JSON keys
check_fields() {
  local json="$1"
  local missing=()
  for key in summary completed_tasks key_decisions files_modified next_action; do
    echo "$json" | jq -e "has(\"$key\")" > /dev/null 2>&1 || missing+=("$key")
  done
  echo "${missing[*]:-}"
}

# Pretty-print a single summary report
report_summary() {
  local json="$1"
  local original_tokens="${2:-unknown}"

  local summary_chars=${#json}
  local summary_tokens
  summary_tokens=$(token_estimate "$json")

  local ratio_pct="N/A"
  local ratio_bar=""
  if [[ "$original_tokens" != "unknown" && "$original_tokens" -gt 0 ]]; then
    ratio_pct=$(( summary_tokens * 100 / original_tokens ))
    local bar_filled=$(( ratio_pct * 20 / 100 ))
    bar_filled=$(( bar_filled > 20 ? 20 : bar_filled ))
    for (( i=0; i<bar_filled; i++ ));  do ratio_bar+="█"; done
    for (( i=bar_filled; i<20; i++ )); do ratio_bar+="░"; done
  fi

  local missing_fields
  missing_fields=$(check_fields "$json")

  local next_action_len
  next_action_len=$(echo "$json" | jq -r '.next_action // ""' | wc -c | tr -d ' ')

  # ── Print ─────────────────────────────────────────────────────────────────
  printf "${BOLD}${CYAN}┌─────────────────────────────────────────────┐${RESET}\n"
  printf "${BOLD}${CYAN}│  claude-optimizer — efficiency report        │${RESET}\n"
  printf "${BOLD}${CYAN}└─────────────────────────────────────────────┘${RESET}\n\n"

  # Token counts
  printf "  ${BOLD}Token budget${RESET}\n"
  printf "  %-28s %s\n" "Original conversation:" "${original_tokens} tokens"
  printf "  %-28s %s\n" "Summary size:"          "~${summary_tokens} tokens (~${summary_chars} chars)"

  if [[ "$ratio_pct" != "N/A" ]]; then
    local col
    col=$(ratio_color "$ratio_pct")
    printf "  %-28s ${col}%s %d%%${RESET}" "Compression ratio:" "[$ratio_bar]" "$ratio_pct"
    if (( ratio_pct < summary_tokens )); then
      # summary is smaller — this is good
      printf "  ${GREEN}✓ summary < conversation${RESET}\n"
    else
      printf "  ${RED}✗ summary >= conversation (too verbose!)${RESET}\n"
    fi
  fi

  echo ""

  # Budget breakdown per field
  printf "  ${BOLD}Per-field token estimate${RESET}\n"
  local fields=("summary" "completed_tasks" "key_decisions" "files_modified" "next_action" "context" "open_questions")
  for field in "${fields[@]}"; do
    local val
    val=$(echo "$json" | jq -r ".[\"$field\"] // empty" 2>/dev/null || true)
    [[ -z "$val" ]] && continue
    local ftokens
    ftokens=$(token_estimate "$val")
    printf "  %-24s ~%d tokens\n" "  $field:" "$ftokens"
  done

  echo ""

  # Structure check
  printf "  ${BOLD}Structure validation${RESET}\n"
  if [[ -z "$missing_fields" ]]; then
    printf "  ${GREEN}✓ All required fields present${RESET}\n"
  else
    printf "  ${RED}✗ Missing fields: %s${RESET}\n" "$missing_fields"
  fi

  # next_action specificity (length proxy — short next_action is usually vague)
  if (( next_action_len < 40 )); then
    printf "  ${RED}✗ next_action may be too vague (%d chars)${RESET}\n" "$next_action_len"
  else
    printf "  ${GREEN}✓ next_action is specific (%d chars)${RESET}\n" "$next_action_len"
  fi

  # Budget warning
  if (( summary_tokens > 400 )); then
    printf "  ${YELLOW}⚡ Summary over 400-token budget (%d tokens) — consider trimming${RESET}\n" "$summary_tokens"
  else
    printf "  ${GREEN}✓ Within 400-token budget (%d tokens)${RESET}\n" "$summary_tokens"
  fi

  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────

if [[ ! -f "$SUMMARY_FILE" ]]; then
  printf "${RED}No summary found at %s${RESET}\n" "$SUMMARY_FILE"
  printf "${DIM}Run a session that hits 60%% fill to generate one.${RESET}\n"
  exit 1
fi

SUMMARY_JSON=$(cat "$SUMMARY_FILE")

# Get original token count from state.json (recorded at time of summarize trigger)
ORIGINAL_TOKENS="unknown"
if [[ -f "$STATE_FILE" ]]; then
  ORIGINAL_TOKENS=$(jq -r '.tokens_used // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
fi

# Report on latest summary
report_summary "$SUMMARY_JSON" "$ORIGINAL_TOKENS"

# ── History report ────────────────────────────────────────────────────────────
if $SHOW_HISTORY && [[ -f "$HISTORY_FILE" ]]; then
  printf "${BOLD}${CYAN}Historical summaries${RESET}\n\n"
  printf "  %-22s %-16s %-16s %s\n" "Timestamp" "Original (tok)" "Summary (tok)" "Ratio"
  printf "  %s\n" "──────────────────────────────────────────────────────────"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ts=$(echo "$line"        | jq -r '.timestamp // "unknown"')
    orig=$(echo "$line"      | jq -r '.tokens_used // 0')
    summary_text=$(echo "$line" | jq -r '.summary_json // "{}"')
    stok=$(token_estimate "$summary_text")

    ratio="N/A"
    col="$RESET"
    if [[ "$orig" != "0" && "$orig" != "unknown" ]]; then
      ratio=$(( stok * 100 / orig ))
      col=$(ratio_color "$ratio")
    fi

    printf "  %-22s %-16s %-16s ${col}%s%%${RESET}\n" \
      "$ts" "${orig}" "~${stok}" "${ratio}"
  done < "$HISTORY_FILE"

  echo ""
fi
