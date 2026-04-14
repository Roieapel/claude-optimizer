#!/usr/bin/env node
/**
 * read-context.js
 * Parses ~/.claude/projects/ JSONL logs to extract context fill %.
 * Writes state to ~/.claude-optimizer/state.json
 * Prints fill % integer to stdout (e.g. "47")
 */

'use strict';

const fs   = require('fs');
const path = require('path');
const os   = require('os');

const CTX_WINDOW = parseInt(process.env.CTX_WINDOW || '200000', 10);
const STATE_DIR  = path.join(os.homedir(), '.claude-optimizer');
const STATE_FILE = path.join(STATE_DIR, 'state.json');

// ── Find latest JSONL log ────────────────────────────────────────────────────

function findLatestJsonl() {
  const projectsDir = path.join(os.homedir(), '.claude', 'projects');
  let latest = null;
  let latestMtime = 0;

  let subdirs;
  try {
    subdirs = fs.readdirSync(projectsDir);
  } catch (_) {
    return null;
  }

  for (const subdir of subdirs) {
    const subdirPath = path.join(projectsDir, subdir);
    let files;
    try {
      files = fs.readdirSync(subdirPath);
    } catch (_) {
      continue;
    }
    for (const file of files) {
      if (!file.endsWith('.jsonl')) continue;
      const filePath = path.join(subdirPath, file);
      try {
        const stat = fs.statSync(filePath);
        if (stat.mtimeMs > latestMtime) {
          latestMtime = stat.mtimeMs;
          latest = filePath;
        }
      } catch (_) {}
    }
  }
  return latest;
}

// ── Parse fill % from JSONL ──────────────────────────────────────────────────

function getContextFill(jsonlPath) {
  let content;
  try {
    content = fs.readFileSync(jsonlPath, 'utf8');
  } catch (_) {
    return null;
  }

  const lines = content.trim().split('\n').filter(l => l.trim());

  // Walk backwards: find the most recent entry that has usage data
  for (let i = lines.length - 1; i >= 0; i--) {
    let entry;
    try {
      entry = JSON.parse(lines[i]);
    } catch (_) {
      continue;
    }

    // usage lives at entry.message.usage (assistant turns)
    const usage = (entry.message && entry.message.usage) || entry.usage;
    if (!usage) continue;

    // Sum all token types that consume context space
    const inputTokens        = Number(usage.input_tokens            || 0);
    const cacheCreation      = Number(usage.cache_creation_input_tokens || 0);
    const cacheRead          = Number(usage.cache_read_input_tokens  || 0);
    const totalInput         = inputTokens + cacheCreation + cacheRead;

    if (totalInput > 0) {
      const pct = Math.min(100, Math.round((totalInput / CTX_WINDOW) * 100));
      return {
        pct,
        tokens_used:  totalInput,
        tokens_total: CTX_WINDOW,
        log_file:     jsonlPath,
      };
    }
  }
  return null;
}

// ── Main ─────────────────────────────────────────────────────────────────────

const jsonlPath = findLatestJsonl();
if (!jsonlPath) {
  process.stderr.write('read-context: no JSONL log found under ~/.claude/projects/\n');
  process.exit(1);
}

const result = getContextFill(jsonlPath);
if (!result) {
  process.stderr.write(`read-context: no usage data found in ${jsonlPath}\n`);
  process.exit(1);
}

// Persist state
try {
  if (!fs.existsSync(STATE_DIR)) {
    fs.mkdirSync(STATE_DIR, { recursive: true });
  }
  const state = { ...result, timestamp: new Date().toISOString() };
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2) + '\n');
} catch (err) {
  process.stderr.write(`read-context: could not write state.json: ${err.message}\n`);
}

// Print fill % to stdout — this is what the hook reads
process.stdout.write(String(result.pct));
