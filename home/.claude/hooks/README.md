# Claude Code Hooks

Shell scripts that run at specific points in the Claude Code lifecycle. Configured in `settings.json` under the `hooks` key.

## Hook Details

### tmux-status.sh
**Trigger:** `UserPromptSubmit` (with arg `working`), `Stop` (with arg `waiting`)

**Purpose:** Visual indicator of Claude's state via the tmux status line.

**Actions:**
- `working`: Show a working indicator in the tmux status line
- `waiting`: Clear the indicator

**Input:** Consumes stdin (required) but doesn't use it. State passed as argument.

**Output:** None (tmux status line only)

## Writing Hooks

### Requirements
- Must be executable (`chmod +x`)
- Must consume stdin (even if not used) to avoid broken pipe errors
- Should use `set -euo pipefail` for safety
- Should gracefully degrade if dependencies missing (tmux, jq)

### Input Format
All hooks receive JSON on stdin with at least:
```json
{
  "session_id": "uuid",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/working/directory"
}
```

Additional fields vary by hook type.

### Output
- Text output is shown to Claude as context
- Use XML tags for structured data
- Exit 0 for success (non-zero doesn't block Claude, but may show error)

### Testing
Run `make test-hooks` to test all hooks. Add tests for new hooks in `tests/test-hooks.sh`.

## Configuration

In `settings.json`:
```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/tmux-status.sh working" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/tmux-status.sh waiting" }] }]
  }
}
```
