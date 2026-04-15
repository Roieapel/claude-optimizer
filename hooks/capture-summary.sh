#!/usr/bin/env bash
# capture-summary.sh — Stop hook
#
# Fires when a Claude Code session ends (user types /exit, closes terminal, etc.).
# Only activates when ~/.claude-optimizer/trigger.flag exists (set by check-context.sh
# when fill % hits the 60% threshold).
#
# What it does:
#   1. Reads the most recent JSONL log
#   2. Extracts the last assistant message that contains valid summary JSON
#      (must have a "next_action" field — the canonical marker from the skill)
#   3. Saves it to ~/.claude-optimizer/summary.json
#   4. Appends a timestamped record to ~/.claude-optimizer/history.jsonl
#   5. Deletes trigger.flag to reset the cycle

set -euo pipefail

STATE_DIR="$HOME/.claude-optimizer"
TRIGGER_FLAG="$STATE_DIR/trigger.flag"
SUMMARY_FILE="$STATE_DIR/summary.json"
HISTORY_FILE="$STATE_DIR/history.jsonl"

# ── Guard: only run when triggered ───────────────────────────────────────────

if [[ ! -f "$TRIGGER_FLAG" ]]; then
  exit 0
fi

# ── Extract summary from JSONL ────────────────────────────────────────────────

SUMMARY=$(node - <<'JSEOF'
const fs   = require('fs');
const path = require('path');
const os   = require('os');

// Find the most recently modified JSONL in ~/.claude/projects/
const projectsDir = path.join(os.homedir(), '.claude', 'projects');

function findLatestJsonl(dir) {
  let latest = null;
  let latestMtime = 0;
  let subdirs;
  try { subdirs = fs.readdirSync(dir); } catch (_) { return null; }
  for (const sub of subdirs) {
    let files;
    try { files = fs.readdirSync(path.join(dir, sub)); } catch (_) { continue; }
    for (const file of files) {
      if (!file.endsWith('.jsonl')) continue;
      const fp = path.join(dir, sub, file);
      try {
        const m = fs.statSync(fp).mtimeMs;
        if (m > latestMtime) { latestMtime = m; latest = fp; }
      } catch (_) {}
    }
  }
  return latest;
}

const jsonlPath = findLatestJsonl(projectsDir);
if (!jsonlPath) process.exit(1);

let content;
try { content = fs.readFileSync(jsonlPath, 'utf8'); } catch (_) { process.exit(1); }

const lines = content.trim().split('\n').filter(l => l.trim());

// Walk backwards; find last assistant text block containing valid summary JSON
for (let i = lines.length - 1; i >= 0; i--) {
  let entry;
  try { entry = JSON.parse(lines[i]); } catch (_) { continue; }

  // Only assistant messages
  const role = entry.type || (entry.message && entry.message.role);
  if (role !== 'assistant') continue;

  // Collect text blocks
  const blocks = (entry.message && entry.message.content) || entry.content || [];
  const textBlocks = Array.isArray(blocks)
    ? blocks.filter(b => b.type === 'text').map(b => b.text)
    : (typeof blocks === 'string' ? [blocks] : []);

  for (const text of textBlocks) {
    // Extract JSON object from text (may be wrapped in markdown fences)
    const match = text.match(/```(?:json)?\s*(\{[\s\S]*?\})\s*```/) ||
                  text.match(/(\{[\s\S]*\})/);
    if (!match) continue;
    try {
      const json = JSON.parse(match[1]);
      // next_action is the canonical required field from the summarize-session skill
      if (json.next_action) {
        process.stdout.write(JSON.stringify(json));
        process.exit(0);
      }
    } catch (_) {}
  }
}

// No valid summary found
process.exit(1);
JSEOF
) || true

if [[ -z "$SUMMARY" ]]; then
  echo "capture-summary: no valid summary JSON found — leaving trigger.flag in place" >&2
  exit 0
fi

# ── Merge token stats from state.json ────────────────────────────────────────

STATE_FILE="$STATE_DIR/state.json"
if [[ -f "$STATE_FILE" ]]; then
  SUMMARY=$(node -e "
    const s = JSON.parse(require('fs').readFileSync('$STATE_FILE','utf8'));
    const d = JSON.parse(process.argv[1]);
    d.session_tokens = {
      tokens_used:       s.tokens_used       || 0,
      tokens_total:      s.tokens_total      || 200000,
      pct:               s.pct               || 0,
      waste_factor:      s.waste_factor      || 1.0,
      first_turn_tokens: s.first_turn_tokens || 0,
      model:             s.model             || 'unknown',
    };
    process.stdout.write(JSON.stringify(d));
  " "$SUMMARY" 2>/dev/null || echo "$SUMMARY")
fi

# ── Persist ───────────────────────────────────────────────────────────────────

mkdir -p "$STATE_DIR"
echo "$SUMMARY" > "$SUMMARY_FILE"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"timestamp":"%s","summary":%s}\n' "$TIMESTAMP" "$SUMMARY" >> "$HISTORY_FILE"

# ── Reset cycle ───────────────────────────────────────────────────────────────

rm -f "$TRIGGER_FLAG"

echo "capture-summary: summary saved to $SUMMARY_FILE" >&2
exit 0
