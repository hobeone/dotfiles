---
name: hook-authoring
description: |
  Writing and modifying hooks, sidecars, and background scripts for Jetski / Antigravity 2.0.
  Auto-applies when authoring scripts, sidecar definitions (<configDir>/sidecars/), or event hooks.
---

# Hook & Sidecar Authoring Patterns

This skill auto-applies when working with Jetski / Antigravity 2.0 hooks, sidecars, and background event scripts.

## Antigravity Tool & Scripting Equivalents
- **Read files**: `view_file`
- **Write files**: `write_to_file`
- **Edit files**: `replace_file_content` / `multi_replace_file_content`
- **Run shell commands**: `run_command`
- **Search content**: `code_search` or `grep_search`
- **Find files**: `find_by_name`
- **CLI Agent API**: `agentapi` CLI tool (`agentapi send-message`, `agentapi new-conversation`, `agentapi get-conversation-metadata`)

## Background Sidecars Architecture

In Antigravity 2.0 / Jetski:
- **Location**: `<configDir>/sidecars/<sidecar-id>/`
- **Configuration**: `sidecar.json`
- **Runtime Data**: `<appDataDir>/sidecar_data/<sidecar-id>/data/`
- **Builtin Schedule**: Cron expression support (e.g. `["schedule", "*/15 * * * *", "agentapi", "new-conversation", "..."]`)

Example `sidecar.json`:

```json
{
  "command": "python3",
  "args": ["sidecar.py"],
  "restart_policy": "always",
  "description": "Background monitoring sidecar"
}
```

## Script Conventions

### 1. Script Header

Always start with:

```bash
#!/bin/bash
set -euo pipefail
```

### 2. Graceful Degradation

Scripts should degrade gracefully when optional utilities are missing:

```bash
if ! command -v jq &>/dev/null; then
    echo "jq missing; skipping JSON parsing" >&2
    exit 0
fi
```

### 3. Exit Codes

- `exit 0` - Success
- Non-zero exits signal failure to background task runners (`manage_task`)

### 4. Interacting with Agent API

Use `agentapi` from shell scripts to notify the agent or trigger new conversations:

```bash
agentapi send-message --title "Task Notice" "$CONVERSATION_ID" "Background process complete."
```

## Testing

Run tests via `run_command` on test harnesses (e.g. `bash tests/test-hooks.sh`).
