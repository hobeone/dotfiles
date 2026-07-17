---
description: Dump recent conversation to file (avoids context pollution after compaction)
---

# Session Dump

Export recent conversation to a temporary file for reference without bloating context.

## Arguments

- `$ARGUMENTS` - Optional: number of messages (default: 50), "all" for full session, or "cross" for cross-session view

## Instructions

### 1. Parse Arguments

```
limit = parse $ARGUMENTS:
  - empty or not provided → 50
  - "all" → 500
  - "cross" → 50 (but read every transcript in the project dir, not just the latest)
  - number → that number

cross_session = ($ARGUMENTS == "cross")
```

### 2. Locate Transcript(s)

No external service is needed — read directly from the JSONL logs Claude Code already writes:

```bash
proj_dir=~/.claude/projects/$(pwd | sed 's/\//-/g')
ls -t "$proj_dir"/*.jsonl   # newest first
```

- Default: use the single most recently modified file (the current/just-finished session).
- `cross_session`: consider all files in `$proj_dir`, most recent first, until `limit` messages are collected.

### 3. Extract Messages

For each transcript file, read line by line. Each line is one JSON record; the ones that matter here have `"type": "user"` or `"type": "assistant"` with a `message.content` field (a string, or a list of blocks — use the text/thinking blocks, skip `tool_use`/`tool_result` blocks for this command). Take the last `limit` such records across the file(s) selected in step 2.

### 4. Format Output

Each record has a `type` field ("user" or "assistant") and a `timestamp` field (ISO 8601).

Write to `/tmp/session-dump-{timestamp}.md`:

```markdown
# Session Dump

**Generated:** {timestamp}
**Messages:** {count} ({user_count} user, {assistant_count} assistant)
**Session:** {transcript filename(s), or "cross-session" if multiple}

---

## Conversation

### User (HH:MM)
{message content}

### Assistant (HH:MM)
{message content}

...
```

Format each message based on its `type` field. Capitalize the type for headers.

### 5. Open File

```bash
${EDITOR:-less} /tmp/session-dump-{timestamp}.md
```

### 6. Minimal Response

Return ONLY:

```
Wrote {N} messages to /tmp/session-dump-{timestamp}.md (opened in {editor})
```

Do NOT echo any message content to the conversation. The entire point is to avoid context pollution.
