# claude-optimizer

Monitors your Claude Code context window and automatically summarizes + resumes sessions before quality degrades.

Claude's attention weakens around 40% context fill and drops measurably at 60%. Most people don't notice until responses get noticeably worse — by then the session is already degraded. This tool catches it early.

---

## What it does

- **Green bar** at every tool call — you always know your fill % and waste factor
- **Yellow warning** at 40% fill or 2.0x waste — non-blocking, just awareness
- **Red alert at 60% fill or 3.0x waste** — blocks the current tool, prompts you to summarize
- **Auto-resume** — the next session injects a structured summary so Claude picks up exactly where it left off

**Waste factor** = current turn tokens / first turn tokens. This matches Claude Code's native compaction metric. Caching can keep raw fill % low even when context has grown 4–5x — waste factor catches that.

No browser. No cloud. No external APIs. Everything runs locally via Claude Code's native hook system.

---

## Install

```bash
git clone https://github.com/Roieapel/claude-optimizer.git
cd claude-optimizer
bash install.sh
```

**Requirements:** Node.js ≥ 18, `jq`

That's it. Open a new Claude Code session and the optimizer is live.

To uninstall:

```bash
bash install.sh --uninstall
```

---

## Usage

Once installed, you don't need to do anything — the hooks run automatically.

### What you'll see

**Normal operation (0–39% fill, <2.0x waste):**
```
│ claude-optimizer  [███░░░░░░░░░░░░░░░░░] 15%  1.4x
```

**Warning (40–59% fill or ≥2.0x waste):**
```
┌─────────────────────────────────────────┐
│  ⚡ claude-optimizer                    │
│  Context: [████████████░░░░░░░░]  45%   │
│  Waste:   2.3x (threshold: 3.0x)        │
│  Wrapping up soon?                      │
└─────────────────────────────────────────┘
```

**Action required (≥60% fill or ≥3.0x waste):**
```
┌─────────────────────────────────────────┐
│  ⚠  claude-optimizer                    │
│  Context: [████████████████░░░░]  60%   │
│  Waste:   3.2x (threshold: 3.0x)        │
│  ACTION REQUIRED — run /summarize-session│
└─────────────────────────────────────────┘
```

### When the red alert fires

1. Type `/summarize-session` — Claude outputs a compact JSON summary of the session
2. Type `/clear` — resets the context window
3. Start working again — the next session auto-injects the summary before turn 1

The resume looks like this at the top of the new session:

```
This is a resumed Claude Code session. Context was summarized and cleared
at the previous 60% fill threshold. Pick up exactly where you left off.

## Summary
<what was accomplished>

## Completed Tasks
- ...

## Next Action
<specific next step>
```

---

## Check summarization efficiency

```bash
bash scripts/check-efficiency.sh
```

Reports token count of the summary vs the original conversation, compression ratio, field validation, and whether the summary is within the 400-token budget.

```bash
bash scripts/check-efficiency.sh --history
```

Shows a table of all past summarize cycles.

---

## Configuration

Set these in your shell profile (`~/.zshrc` or `~/.bashrc`) to change thresholds globally:

| Variable | Default | Description |
|----------|---------|-------------|
| `CTX_WARN` | `40` | Fill % at which yellow warning fires |
| `CTX_ACT` | `60` | Fill % at which red alert + summarize triggers |
| `CTX_WINDOW` | `200000` | Total context window size in tokens |
| `WASTE_WARN` | `2.0` | Waste factor at which yellow warning fires |
| `WASTE_ACT` | `3.0` | Waste factor at which red alert + summarize triggers |

Example — lower thresholds for a shorter model:
```bash
export CTX_WARN=30
export CTX_ACT=50
export CTX_WINDOW=100000
```

---

## How it works

Three hooks register into `~/.claude/settings.json`:

| Hook | Script | When it runs |
|------|--------|-------------|
| `PostToolUse` | `hooks/check-context.sh` | After every tool call — reads fill %, shows bar |
| `SessionStart` | `hooks/session-start.sh` | At session open — injects prior summary if one exists |
| `Stop` | `hooks/capture-summary.sh` | At session close — saves Claude's summary JSON to disk |

One slash command registers into `~/.claude/commands/`:

| Command | What it does |
|---------|-------------|
| `/summarize-session` | Instructs Claude to output a compact structured JSON summary of the current session |

### The summarize-resume cycle

```
Session A reaches 60%
  → check-context.sh blocks tool call, shows red alert
  → You run /summarize-session
  → Claude outputs structured JSON
  → You run /clear
  → capture-summary.sh (Stop hook) saves JSON to ~/.claude-optimizer/summary.json

Session B starts
  → session-start.sh reads summary.json
  → Injects <resume_block> into Claude's context before turn 1
  → Claude picks up with full context of what happened and what to do next
```

### Runtime files

All state lives in `~/.claude-optimizer/` — never committed, personal to each machine:

| File | Purpose |
|------|---------|
| `state.json` | Latest fill %, token counts, timestamp |
| `summary.json` | Most recent session summary |
| `history.jsonl` | Append-only archive of all past summaries |
| `trigger.flag` | Exists only during an active summarize cycle |

---

## Project layout

```
claude-optimizer/
├── install.sh                         # One-command setup / uninstall
├── README.md
├── hooks/
│   ├── check-context.sh               # PostToolUse — reads fill %, shows bar
│   ├── session-start.sh               # SessionStart — injects last summary
│   └── capture-summary.sh             # Stop — saves summary JSON on session end
├── scripts/
│   ├── read-context.js                # Parses JSONL logs, writes state.json
│   └── check-efficiency.sh            # Reports summarization efficiency
└── skills/
    └── summarize-session/
        └── SKILL.md                   # /summarize-session slash command definition
```

---

## Troubleshooting

**Green bar not showing** — The bar writes directly to `/dev/tty` so it appears inline in your terminal regardless of how Claude Code captures hook output. If it's still not visible, check that the hook is registered: `cat ~/.claude/settings.json | grep check-context`.

**`read-context.js` returned no data** — Normal on first run before any tool calls have been made. The JSONL log is written after turn 1.

**Hooks not firing** — Run `bash install.sh` again. Check that `~/.claude/settings.json` contains entries for `PostToolUse`, `SessionStart`, and `Stop`.

**Paths with spaces** — If your repo path contains spaces, `install.sh` handles this automatically by wrapping paths in `bash "..."` in the settings.json hook commands.

**Force-test the thresholds** without filling context:
```bash
CTX_WINDOW=1000 CTX_ACT=1 claude
```
