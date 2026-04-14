# claude-optimizer

A Claude Code CLI tool that monitors context window fill % and automatically summarizes, clears, and resumes sessions before quality degrades.

## What this project does

Hooks into Claude Code's native infrastructure to:
- Read context fill % from local JSONL logs after every turn
- Warn at 40% fill (non-blocking)
- At 60%: run `/summarize-session` → save JSON summary → clear context → inject summary into next session

No browser. No cloud. No external APIs. Everything runs locally via Claude Code hooks.

## Project structure

```
claude-optimizer/
├── CLAUDE.md                          # this file
├── install.sh                         # one-command setup
├── README.md
├── hooks/
│   ├── session-start.sh               # SessionStart — injects last summary into context
│   ├── check-context.sh               # PostToolUse — reads fill %, fires at 40%/60%
│   └── capture-summary.sh             # Stop — saves Claude's summary JSON to disk
├── scripts/
│   └── read-context.js                # parses ~/.claude/projects/ JSONL, writes state.json
└── skills/
    └── summarize-session/
        └── SKILL.md                   # /summarize-session slash command
```

After install, runtime files live at:

```
~/.claude-optimizer/
├── state.json       # { pct, tokens_used, tokens_total, timestamp } — updated every turn
├── summary.json     # latest session summary — read on next SessionStart
├── history.jsonl    # append-only archive of all past summaries
└── trigger.flag     # exists only when 60% was hit and summary cycle is in progress
```

## Architecture decisions

**Why context % not waste factor** — Waste factor (turn N / turn 1) is a proxy with no research backing. Context fill % maps directly to the known degradation curve: attention weakens at 40%, quality drops measurably at 60%, Anthropic's own internal threshold is 70%. We act at 60% to stay ahead of it.

**Why Haiku for summarization** — The summary runs at 60% fill when context is already expensive. Haiku is fast, cheap, and sufficient for structured JSON output. Sonnet is reserved for actual work.

**Why `next_action` is a required field** — Most summarizers capture what happened. This one captures what to do next, specific enough that a fresh Claude instance can act immediately. That's the difference between a resumption that feels seamless and one that requires five minutes of re-orientation.

**Why `trigger.flag`** — Hooks can't send `/clear` directly into a live session. The flag decouples the 60% detection (PostToolUse) from the clear+resume cycle (SessionStart on next launch). It's deleted after successful resume to reset the cycle cleanly.

**Why `session-start.sh` stdout** — Claude Code's SessionStart hook is one of two hook events where stdout is injected directly into Claude's context before turn 1. This is the only clean way to auto-inject a resume block without polluting the system prompt or CLAUDE.md.

## Context thresholds

| Fill % | Action |
|--------|--------|
| 0–40%  | Normal operation |
| 40–60% | Warning printed to stderr — no block |
| 60%+   | Auto: summarize → save → flag → next session injects resume block |

Thresholds are tunable via env vars: `CTX_WARN=40`, `CTX_ACT=60`, `CTX_WINDOW=200000`.

## Key constraints

- **Do not change the summary JSON schema** without updating `session-start.sh` — the resume block formatter reads specific keys by name
- **Do not use exit 2 at 40%** — non-blocking warning only; exit 2 would block the tool call which is too aggressive at 40%
- **`capture-summary.sh` only fires when `trigger.flag` exists** — the Stop hook runs on every session end; the flag is what scopes it to triggered cycles only
- **JSONL log path uses most-recently-modified file** — Claude Code rotates logs per session; always find the latest, never hardcode a path
- **Haiku model string for summarize-session skill**: `claude-haiku-4-5-20251001`

## Install

```bash
bash install.sh
```

Requires: `jq`, `node` (≥18) or `python3`. Tested on macOS and Linux.

## Env vars

| Var | Default | Description |
|-----|---------|-------------|
| `CTX_WARN` | `40` | % fill at which warning fires |
| `CTX_ACT` | `60` | % fill at which summarize pipeline fires |
| `CTX_WINDOW` | `200000` | Total context window size (tokens). Change for non-Sonnet models |

## Files never to commit

```
~/.claude-optimizer/state.json
~/.claude-optimizer/summary.json
~/.claude-optimizer/history.jsonl
~/.claude-optimizer/trigger.flag
```

These are runtime files, personal to each user. `history.jsonl` in particular may contain sensitive session content.
