#!/bin/bash
set -euo pipefail

# Read JSON payload from stdin
DATA=$(cat)

if [[ -z "$DATA" ]]; then
  exit 0
fi

# Parse fields from input payload
AGENT_STATE=$(echo "$DATA" | jq -r '(.agent_state // "idle")' 2>/dev/null || echo "idle")
CWD=$(echo "$DATA" | jq -r '(.workspace.project_dir // .workspace.current_dir // .cwd // "")' 2>/dev/null || true)
CWD="${CWD:-$PWD}"

# Resolve project name
PROJECT_NAME=""

# 1. Custom/local workspace check via local extension hook
LOCAL_RESOLVER="${HOME}/.gemini/antigravity-cli/vcs_resolve.local.sh"
if [[ -f "$LOCAL_RESOLVER" ]]; then
  # shellcheck source=/dev/null
  source "$LOCAL_RESOLVER"
  if declare -F resolve_custom_workspace &>/dev/null; then
    custom_ws=$(resolve_custom_workspace "$CWD" 2>/dev/null || true)
    if [[ -n "$custom_ws" ]]; then
      PROJECT_NAME="$custom_ws"
    fi
  fi
fi

# 2. Git worktree check (e.g. .worktrees/<branch>)
if [[ -z "$PROJECT_NAME" && "$CWD" == */.worktrees/* ]]; then
  worktree_parent="${CWD%/.worktrees/*}"
  repo_name="${worktree_parent##*/}"
  worktree_branch="${CWD##*/}"
  PROJECT_NAME="${repo_name} (${worktree_branch})"
fi

# 3. Git repository check
if [[ -z "$PROJECT_NAME" ]] && command -v git &>/dev/null && git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  GIT_DIR=$(git -C "$CWD" rev-parse --git-dir 2>/dev/null || true)
  GIT_COMMON_DIR=$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null || true)
  TOPLEVEL=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)
  REPO_NAME="${TOPLEVEL##*/}"

  if [[ -n "$GIT_DIR" && -n "$GIT_COMMON_DIR" && "$GIT_DIR" != "$GIT_COMMON_DIR" ]]; then
    WT_NAME="${REPO_NAME}"
    BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || true)
    if [[ -z "$BRANCH" ]]; then
      BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    fi
    [[ "$BRANCH" == "HEAD" ]] && BRANCH=""
    if [[ -n "$BRANCH" && "$BRANCH" != "$WT_NAME" ]]; then
      PROJECT_NAME="${WT_NAME} (${BRANCH})"
    else
      PROJECT_NAME="${WT_NAME}"
    fi
  else
    PROJECT_NAME="${REPO_NAME}"
  fi
fi

# 4. Mercurial / Jujutsu check
if [[ -z "$PROJECT_NAME" ]] && command -v hg &>/dev/null && hg -R "$CWD" root &>/dev/null 2>&1; then
  HG_ROOT=$(hg -R "$CWD" root 2>/dev/null || true)
  PROJECT_NAME="${HG_ROOT##*/}"
elif [[ -z "$PROJECT_NAME" ]] && command -v jj &>/dev/null && jj -R "$CWD" root &>/dev/null 2>&1; then
  JJ_ROOT=$(jj -R "$CWD" root 2>/dev/null || true)
  PROJECT_NAME="${JJ_ROOT##*/}"
fi

# 5. Fallback: directory basename
if [[ -z "$PROJECT_NAME" ]]; then
  PROJECT_NAME="${CWD##*/}"
fi
PROJECT_NAME="${PROJECT_NAME:-workspace}"

# Determine title based on agent state
case "$AGENT_STATE" in
  working|thinking|tool_use)
    TMUX_TITLE="⏳ $PROJECT_NAME"
    TERM_TITLE="[AGY] ⏳ $PROJECT_NAME"
    ;;
  *)
    TMUX_TITLE="$PROJECT_NAME"
    TERM_TITLE="[AGY] $PROJECT_NAME"
    ;;
esac

# Rename tmux window if running inside tmux
if [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]]; then
  TARGET_INFO=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id} #{window_name}' 2>/dev/null || true)
  if [[ -n "$TARGET_INFO" ]]; then
    WINDOW_ID="${TARGET_INFO%% *}"
    CURRENT_NAME="${TARGET_INFO#* }"
    if [[ "$CURRENT_NAME" != "$TMUX_TITLE" ]]; then
      tmux set-window-option -t "$WINDOW_ID" automatic-rename off 2>/dev/null || true
      tmux set-window-option -t "$WINDOW_ID" allow-rename off 2>/dev/null || true
      tmux rename-window -t "$WINDOW_ID" "$TMUX_TITLE" 2>/dev/null || true
    fi
  fi
fi

echo "$TERM_TITLE"
