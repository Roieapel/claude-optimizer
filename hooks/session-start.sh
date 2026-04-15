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
const fs = require('fs');

const summaryPath = process.argv[2];
let data;
try {
  data = JSON.parse(fs.readFileSync(summaryPath, 'utf8'));
} catch (err) {
  process.exit(0);
}

const lines = [];
lines.push('<resume_block>');

// Stats header — single compact line
if (data.session_tokens) {
  const t = data.session_tokens;
  lines.push(`Resumed session (${t.pct}% fill, ${t.waste_factor}x waste). Pick up from Next Action below.`);
} else {
  lines.push('Resumed session. Pick up from Next Action below.');
}
lines.push('');

if (data.summary) {
  lines.push(data.summary);
  lines.push('');
}

// Pipe-separated lists — no headers wasted on structure
const done = data.done || data.completed_tasks;
if (Array.isArray(done) && done.length > 0) {
  lines.push('DONE: ' + done.join(' | '));
}

const decided = data.decided || data.key_decisions;
if (Array.isArray(decided) && decided.length > 0) {
  lines.push('DECIDED: ' + decided.join(' | '));
}

// Compat: open_questions folded into next_action display
const next = data.next || data.next_action;
if (next) {
  lines.push('NEXT: ' + next);
}

if (data.context && Object.keys(data.context).length > 0) {
  const pairs = Object.entries(data.context).map(([k, v]) => `${k}: ${v}`);
  lines.push('GOTCHA: ' + pairs.join(' | '));
}

// Legacy: files_modified (old schema) — kept for backward compat only
if (Array.isArray(data.files_modified) && data.files_modified.length > 0) {
  lines.push('FILES: ' + data.files_modified.join(' | '));
}

lines.push('</resume_block>');

process.stdout.write(lines.join('\n') + '\n');
JSEOF

exit 0
