#!/usr/bin/env node
/**
 * read-context.js
 * Parses ~/.claude/projects/ JSONL logs to extract context fill % AND waste factor.
 *
 * Waste factor = current_turn_tokens / first_turn_tokens.
 * This matches Claude Code's native compaction metric more accurately than raw % fill.
 *
 * Auto-detects context window size from model name in JSONL.
 * Falls back to CTX_WINDOW env var (default 200000).
 *
 * Writes state.json and prints: <pct> <waste_factor>
 * e.g. "42 4.1"
 */

'use strict';

const fs   = require('fs');
const path = require('path');
const os   = require('os');

const STATE_DIR  = path.join(os.homedir(), '.claude-optimizer');
const STATE_FILE = path.join(STATE_DIR, 'state.json');

// ── Model → context window map ───────────────────────────────────────────────
const MODEL_CTX = {
  'claude-opus-4':         200000,
  'claude-sonnet-4':       200000,
  'claude-haiku-4':        200000,
  'claude-opus-3-7':       200000,
  'claude-sonnet-3-7':     200000,
  'claude-haiku-3-5':      200000,
  'claude-3-5-sonnet':     200000,
  'claude-3-5-haiku':      200000,
  'claude-3-opus':         200000,
  'claude-3-sonnet':       200000,
  'claude-3-haiku':        200000,
};

function ctxWindowForModel(modelId) {
  if (!modelId) return null;
  for (const [prefix, size] of Object.entries(MODEL_CTX)) {
    if (modelId.startsWith(prefix)) return size;
  }
  return null;
}

// ── Find the transcript JSONL passed via env, or latest across all projects ──

function findLatestJsonl() {
  const projectsDir = path.join(os.homedir(), '.claude', 'projects');
  let latest = null, latestMtime = 0;
  let subdirs;
  try { subdirs = fs.readdirSync(projectsDir); } catch (_) { return null; }
  for (const subdir of subdirs) {
    const subdirPath = path.join(projectsDir, subdir);
    let files;
    try { files = fs.readdirSync(subdirPath); } catch (_) { continue; }
    for (const file of files) {
      if (!file.endsWith('.jsonl')) continue;
      const filePath = path.join(subdirPath, file);
      try {
        const m = fs.statSync(filePath).mtimeMs;
        if (m > latestMtime) { latestMtime = m; latest = filePath; }
      } catch (_) {}
    }
  }
  return latest;
}

// ── Parse JSONL — returns { first, current, model } ─────────────────────────

function parseJsonl(jsonlPath) {
  let content;
  try { content = fs.readFileSync(jsonlPath, 'utf8'); } catch (_) { return null; }

  const lines = content.trim().split('\n').filter(l => l.trim());
  let first = null;
  let current = null;
  let model = null;

  for (const line of lines) {
    let entry;
    try { entry = JSON.parse(line); } catch (_) { continue; }

    // Extract model name from any entry that has it
    if (!model) {
      model = (entry.message && entry.message.model) || entry.model || null;
    }

    const usage = (entry.message && entry.message.usage) || entry.usage;
    if (!usage) continue;

    const total = (usage.input_tokens || 0)
                + (usage.cache_creation_input_tokens || 0)
                + (usage.cache_read_input_tokens || 0);
    if (total === 0) continue;

    if (first === null) first = total;
    current = total;
  }

  if (current === null) return null;
  return { first, current, model };
}

// ── Main ─────────────────────────────────────────────────────────────────────

// Allow caller to pass transcript path directly (from hook stdin)
const jsonlPath = process.argv[2] || findLatestJsonl();
if (!jsonlPath) {
  process.stderr.write('read-context: no JSONL found\n');
  process.exit(1);
}

const parsed = parseJsonl(jsonlPath);
if (!parsed) {
  process.stderr.write('read-context: no usage data found\n');
  process.exit(1);
}

const { first, current, model } = parsed;

// Context window: model auto-detect > env var > 200k default
const envWindow = process.env.CTX_WINDOW ? parseInt(process.env.CTX_WINDOW, 10) : null;
const CTX_WINDOW = ctxWindowForModel(model) || envWindow || 200000;

const pct        = Math.min(100, Math.round((current / CTX_WINDOW) * 100));
const wasteFactor = first > 0 ? Math.round((current / first) * 10) / 10 : 1.0;

// Persist state
try {
  if (!fs.existsSync(STATE_DIR)) fs.mkdirSync(STATE_DIR, { recursive: true });
  const state = {
    pct,
    waste_factor:      wasteFactor,
    tokens_used:       current,
    tokens_total:      CTX_WINDOW,
    first_turn_tokens: first,
    model:             model || 'unknown',
    log_file:          jsonlPath,
    timestamp:         new Date().toISOString(),
  };
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2) + '\n');
} catch (err) {
  process.stderr.write(`read-context: could not write state.json: ${err.message}\n`);
}

// Print "<pct> <waste_factor>" — check-context.sh reads both
process.stdout.write(`${pct} ${wasteFactor}`);
