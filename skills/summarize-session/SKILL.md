# /summarize-session

You are performing a **context window summarization** for a Claude Code session that has reached the 60% fill threshold.

Your job is to produce a **compact, structured JSON summary** that will allow a fresh Claude instance to resume this session with zero re-orientation time.

## Output format

Output ONLY the following JSON object — no preamble, no explanation, no markdown fences:

```json
{
  "summary": "<2-4 sentence overview of what this session accomplished>",
  "completed_tasks": [
    "<specific task completed — be concrete, include file names and function names>",
    "..."
  ],
  "key_decisions": [
    "<architectural or design decision made and why>",
    "..."
  ],
  "files_modified": [
    "<path/to/file.ext>",
    "..."
  ],
  "open_questions": [
    "<unresolved question or blocker>",
    "..."
  ],
  "next_action": "<single most important thing to do next — specific enough that a fresh Claude can act immediately without asking>",
  "context": {
    "<any_key>": "<any value that doesn't fit above — e.g. env vars, test commands, known gotchas>"
  }
}
```

## Rules

1. **`next_action` is required and must be specific.** Not "continue the work" — instead: "Run `npm test` in `/src/api`, fix the TypeScript error on line 42 of `routes/users.ts`, then commit with message 'fix: user route validation'."

2. **`completed_tasks` captures done work, not in-progress work.** If something is half-done, put what remains in `next_action` or `open_questions`.

3. **Be concrete.** File paths, function names, variable names, error messages — include them. Vague summaries force the next session to re-explore.

4. **Hard token budget — the summary MUST be shorter than the conversation it summarizes.**
   - `summary`: max 3 sentences
   - `completed_tasks`: max 5 items, one line each (≤15 words per item)
   - `key_decisions`: max 3 items, one line each
   - `files_modified`: paths only, no explanation
   - `open_questions`: max 3 items
   - `next_action`: max 2 sentences
   - `context`: max 3 key/value pairs, values ≤20 words each
   - **Total JSON output: target under 400 tokens.** If you are over, cut ruthlessly — drop filler words, merge related items, omit anything reconstructable from the code.

5. **`context` is for gotchas only.** If there's something that took time to figure out (a quirky env setup, a flaky test, a dependency conflict), capture it here so the next Claude doesn't repeat the same investigation. Skip it if there's nothing surprising.

6. **Omit empty arrays.** If there are no `open_questions`, omit that key entirely.

## What to look at

Review the full conversation history visible in your context:
- All user messages and instructions
- All tool calls and their results (read files, bash commands, edits)
- All your previous assistant responses
- Any errors encountered and how they were resolved

Then produce the JSON. Nothing else.

## Model

Use `claude-haiku-4-5-20251001` for this skill — it is fast, cheap, and sufficient for structured JSON output.
