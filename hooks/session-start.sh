#!/usr/bin/env bash
# session-start.sh — SessionStart hook
#
# Fires at the start of every Claude Code session.
# If ~/.claude-optimizer/summary.json exists, formats it as a resume block
# and writes it to stdout — Claude Code injects SessionStart stdout directly
# into Claude's context before turn 1.
#
# If no summary exists, exits silently (normal session).

set -euo pipefail

STATE_DIR="$HOME/.claude-optimizer"
SUMMARY_FILE="$STATE_DIR/summary.json"
TRIGGER_FLAG="$STATE_DIR/trigger.flag"

# ── Nothing to resume ────────────────────────────────────────────────────────

if [[ ! -f "$SUMMARY_FILE" ]]; then
  exit 0
fi

# ── Format and inject resume block ───────────────────────────────────────────

node - "$SUMMARY_FILE" <<'JSEOF'
const fs   = require('fs');
const path = require('path');

const summaryPath = process.argv[2];
let data;
try {
  data = JSON.parse(fs.readFileSync(summaryPath, 'utf8'));
} catch (err) {
  // Corrupt or unreadable — skip silently
  process.exit(0);
}

const lines = [];
lines.push('<resume_block>');
lines.push('This is a resumed Claude Code session. Context was summarized and cleared');
lines.push('at the previous 60% fill threshold. Pick up exactly where you left off.');
lines.push('');

if (data.summary) {
  lines.push('## Summary');
  lines.push(data.summary);
  lines.push('');
}

if (Array.isArray(data.completed_tasks) && data.completed_tasks.length > 0) {
  lines.push('## Completed Tasks');
  data.completed_tasks.forEach(t => lines.push(`- ${t}`));
  lines.push('');
}

if (Array.isArray(data.key_decisions) && data.key_decisions.length > 0) {
  lines.push('## Key Decisions');
  data.key_decisions.forEach(d => lines.push(`- ${d}`));
  lines.push('');
}

if (Array.isArray(data.files_modified) && data.files_modified.length > 0) {
  lines.push('## Files Modified');
  data.files_modified.forEach(f => lines.push(`- ${f}`));
  lines.push('');
}

if (Array.isArray(data.open_questions) && data.open_questions.length > 0) {
  lines.push('## Open Questions');
  data.open_questions.forEach(q => lines.push(`- ${q}`));
  lines.push('');
}

if (data.next_action) {
  lines.push('## Next Action');
  lines.push(data.next_action);
  lines.push('');
}

if (data.context && Object.keys(data.context).length > 0) {
  lines.push('## Additional Context');
  for (const [key, val] of Object.entries(data.context)) {
    lines.push(`**${key}**: ${val}`);
  }
  lines.push('');
}

lines.push('</resume_block>');

process.stdout.write(lines.join('\n') + '\n');
JSEOF

exit 0
