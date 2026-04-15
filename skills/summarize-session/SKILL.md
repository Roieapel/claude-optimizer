# /summarize-session

Produce a **compact JSON summary** so a fresh Claude instance can resume immediately.

## Output format

Output ONLY this JSON — no preamble, no fences:

```json
{
  "summary": "<2 sentence max: what was done and current state>",
  "done": [
    "<completed task — ≤10 words, include file/function names>",
    "..."
  ],
  "decided": [
    "<decision made — ≤10 words, include the reason>",
    "..."
  ],
  "next": "<specific next step — exact commands, file paths, line numbers>",
  "context": {
    "<key>": "<gotcha or env detail — ≤15 words>"
  }
}
```

## Rules

1. **`next` is required and must be specific.** Not "continue work" — instead: "Run `npm test` in `/src/api`, fix TS error on line 42 of `routes/users.ts`, commit 'fix: user route validation'."

2. **`done` = finished work only.** Half-done → put remainder in `next`.

3. **No `files_modified`.** Git status recovers this — omit it.

4. **No `open_questions`.** Unresolved blockers go in `next`.

5. **Hard token budget:**
   - `summary`: max 2 sentences
   - `done`: max 3 items, ≤10 words each
   - `decided`: max 2 items, ≤10 words each
   - `next`: max 2 sentences
   - `context`: max 2 pairs, values ≤15 words each
   - **Total: target under 200 tokens.** Cut ruthlessly — drop filler, merge items, omit anything git/code can recover.

6. **`context` is gotchas only** — quirky env, flaky tests, non-obvious dependency. Omit if nothing surprising.

7. **Omit empty arrays.**

Review all user messages, tool calls, edits, and errors in your context. Then output the JSON. Nothing else.

## Model

Use `claude-haiku-4-5-20251001`.
