---
name: session-dump
description: Dump recent conversation to file (avoids context pollution after compaction)
---

# Session Dump

Export recent conversation to a temporary file for reference.

## Arguments

- Optional: limit number of messages (default: 50), "all", or "cross"

## Instructions

### 1. Locate Transcript

Identify the active conversation ID from metadata or locate the most recently modified subdirectory in `~/.gemini/antigravity-cli/brain/`.
Inside it, read the JSONL log file:
`~/.gemini/antigravity-cli/brain/<conversation-id>/.system_generated/logs/transcript.jsonl`

### 2. Extract and Format Messages

Parse the last N JSON objects where `"type": "user"` or `"type": "assistant"`.
Format them into a Markdown file at `/tmp/session-dump-{timestamp}.md`.

### 3. Open File

Open `/tmp/session-dump-{timestamp}.md` using the user's default editor (e.g. `less`).
