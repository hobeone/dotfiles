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

### agent-memory hook claude start|stop
**Trigger:** `SessionStart` (`start`), `Stop` (`stop`). Lives in `~/bin/agent-memory`, not in this folder; agy runs the same hook as `agent-memory hook agy ...` from `~/.gemini/config/hooks.json`.

**Purpose:** Keep the shared two-tier memory store (`~/.agents/memory`, see `agent-memory --help`) synced and wired up while an agent runs. There is no background timer.

**Actions:**
- `start`: sync the store (commit, pull, push), point this project's Claude memory folder at `projects/<owner>/<repo>/`, regenerate the indexes, and check the memory files' front matter
- `stop`: sync only when there is something to commit or push; otherwise no network

**Input:** Reads `cwd` from the hook JSON (falls back to `$PWD`).

**Output:** `start` prints nothing when all is well, otherwise lines of session context: a failed sync, a project that could not be linked, or memory files to fix. `stop` prints nothing. Both exit 0, so a session is never blocked. Nothing happens on a machine without the store, without `~/bin/agent-memory`, or when disabled via `agent-memory disable` or `AGENT_MEMORY_DISABLED=1`.

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
