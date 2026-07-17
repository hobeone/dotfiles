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

Identify the active conversation ID from metadata or locate the most recently modified subdirectory in `<appDataDir>/brain/`.
Inside it, read the JSONL log file:
`<appDataDir>/brain/<conversation-id>/.system_generated/logs/transcript.jsonl`

### 2. Extract and Format Messages

Parse the last N JSON objects where `"type": "user"` or `"type": "assistant"`.
Format them into a Markdown file in the session's artifact directory:
`<appDataDir>/brain/<conversation-id>/session_dump_{timestamp}.md`

Write the file using `write_to_file` and provide `ArtifactMetadata` with `UserFacing: true` and a suitable summary.

