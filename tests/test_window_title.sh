#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WINDOW_TITLE_BIN="$REPO_ROOT/home/.gemini/antigravity-cli/window_title.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Mock tmux to capture invocations without touching real tmux sessions
MOCK_TMUX_LOG="$TMP_DIR/tmux.log"
cat << MOCK_TMUX > "$TMP_DIR/tmux"
#!/usr/bin/env bash
echo "tmux \$*" >> "$MOCK_TMUX_LOG"
case "\$*" in
  *"display-message -t %99 -p #{window_id}|#{@agy_title}#{@claude_title}"*)
    echo "\${MOCK_AGENT_STATE:-@99|}"
    exit 0
    ;;
  *"display-message -t %99 -p #{window_id} #{window_name}"*)
    echo "@99 test_win"
    exit 0
    ;;
  *"display-message -t %99 -p #{window_id}"*)
    echo "@99"
    exit 0
    ;;
  *"display-message -t %99 -p #{pane_current_path}"*)
    echo "\${MOCK_PANE_PATH:-/tmp/mock-repo}"
    exit 0
    ;;
esac
exit 0
MOCK_TMUX
chmod +x "$TMP_DIR/tmux"

FAILED=0
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $label - expected '$expected', got '$actual'"
    FAILED=1
  else
    echo "PASS: $label"
  fi
}

assert_log_contains() {
  local label="$1" needle="$2"
  if ! grep -Fq -- "$needle" "$MOCK_TMUX_LOG" 2>/dev/null; then
    echo "FAIL: $label - log did not contain '$needle'"
    echo "Log content:"
    cat "$MOCK_TMUX_LOG" 2>/dev/null || true
    FAILED=1
  else
    echo "PASS: $label"
  fi
}

assert_log_not_contains() {
  local label="$1" needle="$2"
  if grep -Fq -- "$needle" "$MOCK_TMUX_LOG" 2>/dev/null; then
    echo "FAIL: $label - log unexpectedly contained '$needle'"
    echo "Log content:"
    cat "$MOCK_TMUX_LOG" 2>/dev/null || true
    FAILED=1
  else
    echo "PASS: $label"
  fi
}

echo "=== Test 1: Git repo in working state ==="
: > "$MOCK_TMUX_LOG"
GIT_REPO="$TMP_DIR/my-repo"
mkdir -p "$GIT_REPO"
git -C "$GIT_REPO" init -q -b main
INPUT_JSON=$(jq -n --arg cwd "$GIT_REPO" '{agent_state: "working", cwd: $cwd}')

OUT=$(PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" "$WINDOW_TITLE_BIN" <<< "$INPUT_JSON")
assert_eq "Working stdout" "[AGY] ⏳my-repo" "$OUT"
assert_log_contains "Working tmux pane @agy_title" "tmux set-option -p -t %99 @agy_title [AGY] ⏳my-repo"
assert_log_contains "Working tmux rename" "tmux rename-window -t @99 [AGY] ⏳my-repo"
assert_log_contains "Working tmux automatic-rename on" "tmux set-window-option -t @99 automatic-rename on"
assert_log_not_contains "Working tmux never disables automatic-rename" "automatic-rename off"

echo "=== Test 2: Git repo in idle state ==="
: > "$MOCK_TMUX_LOG"
INPUT_JSON=$(jq -n --arg cwd "$GIT_REPO" '{agent_state: "idle", cwd: $cwd}')
OUT=$(PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" "$WINDOW_TITLE_BIN" <<< "$INPUT_JSON")
assert_eq "Idle stdout" "[AGY] ● my-repo" "$OUT"
assert_log_contains "Idle tmux pane @agy_title" "tmux set-option -p -t %99 @agy_title [AGY] ● my-repo"
assert_log_contains "Idle tmux rename" "tmux rename-window -t @99 [AGY] ● my-repo"
assert_log_contains "Idle tmux automatic-rename on" "tmux set-window-option -t @99 automatic-rename on"
assert_log_not_contains "Idle tmux never disables automatic-rename" "automatic-rename off"

echo "=== Test 3: Local VCS Resolver Hook ==="
: > "$MOCK_TMUX_LOG"
FAKE_HOME="$TMP_DIR/fake_home"
mkdir -p "$FAKE_HOME/.gemini/antigravity-cli"
cat << 'HOOK_EOF' > "$FAKE_HOME/.gemini/antigravity-cli/vcs_resolve.local.sh"
resolve_custom_workspace() {
  local target="$1"
  if [[ "$target" == *"/custom-monorepo/"* ]]; then
    echo "custom-ws"
    return 0
  fi
  return 1
}
HOOK_EOF
CUSTOM_PATH="/some/mount/custom-monorepo/service-a"
INPUT_JSON=$(jq -n --arg cwd "$CUSTOM_PATH" '{agent_state: "working", cwd: $cwd}')
OUT=$(HOME="$FAKE_HOME" PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" "$WINDOW_TITLE_BIN" <<< "$INPUT_JSON")
assert_eq "Local hook stdout" "[AGY] ⏳custom-ws" "$OUT"
assert_log_contains "Local hook tmux rename" "tmux rename-window -t @99 [AGY] ⏳custom-ws"

echo "=== Test 4: Linked Git Worktree ==="
: > "$MOCK_TMUX_LOG"
WT_PARENT="$TMP_DIR/parent-repo"
mkdir -p "$WT_PARENT"
git -C "$WT_PARENT" init -q -b main
git -C "$WT_PARENT" config user.email "test@example.com"
git -C "$WT_PARENT" config user.name "Test"
git -C "$WT_PARENT" commit --allow-empty -m "init" -q
WT_DIR="$WT_PARENT/.worktrees/feature-auth"
git -C "$WT_PARENT" worktree add -q "$WT_DIR" -b feature-auth
INPUT_JSON=$(jq -n --arg cwd "$WT_DIR" '{agent_state: "idle", cwd: $cwd}')
OUT=$(PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" "$WINDOW_TITLE_BIN" <<< "$INPUT_JSON")
assert_eq "Worktree stdout" "[AGY] ● parent-repo (feature-auth)" "$OUT"
assert_log_contains "Worktree tmux rename" "tmux rename-window -t @99 [AGY] ● parent-repo (feature-auth)"

echo "=== Test 5: Plain directory without VCS ==="
: > "$MOCK_TMUX_LOG"
PLAIN_DIR="$TMP_DIR/simple-folder"
mkdir -p "$PLAIN_DIR"
INPUT_JSON=$(jq -n --arg cwd "$PLAIN_DIR" '{agent_state: "working", cwd: $cwd}')
OUT=$(PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" "$WINDOW_TITLE_BIN" <<< "$INPUT_JSON")
assert_eq "Plain dir stdout" "[AGY] ⏳simple-folder" "$OUT"
assert_log_contains "Plain dir tmux rename" "tmux rename-window -t @99 [AGY] ⏳simple-folder"

echo "=== Test 6: Outside of TMUX ==="
: > "$MOCK_TMUX_LOG"
OUT=$(PATH="$TMP_DIR:$PATH" TMUX="" TMUX_PANE="" "$WINDOW_TITLE_BIN" <<< "$INPUT_JSON")
assert_eq "No TMUX stdout" "[AGY] ⏳simple-folder" "$OUT"
if [[ -s "$MOCK_TMUX_LOG" ]]; then
  echo "FAIL: Tmux commands called when TMUX is unset"
  FAILED=1
else
  echo "PASS: No tmux commands invoked when outside TMUX"
fi

echo "=== Test 7: tmux.conf automatic-rename-format uses @agy_title for cli/agy ==="
TMUX_CONF="$REPO_ROOT/home/.config/tmux/tmux.conf"
EXPECTED_FMT="setw -g automatic-rename-format '#{?#{m/r:^(cli|agy)$,#{pane_current_command}},#{?#{@agy_title},#{@agy_title},#{b:pane_current_path}},#{?#{m/r:^(zsh|claude)$,#{pane_current_command}},#{b:pane_current_path},#{pane_current_command}}}'"
if grep -Fq -- "$EXPECTED_FMT" "$TMUX_CONF" 2>/dev/null; then
  echo "PASS: tmux.conf automatic-rename-format configured with @agy_title"
else
  echo "FAIL: tmux.conf automatic-rename-format missing @agy_title rule"
  FAILED=1
fi

echo "=== Test 8: Claude tmux-status.sh tracks @claude_title ==="
CLAUDE_STATUS_BIN="$REPO_ROOT/home/.claude/hooks/tmux-status.sh"
: > "$MOCK_TMUX_LOG"
PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" MOCK_PANE_PATH="/tmp/mock-repo" "$CLAUDE_STATUS_BIN" working < /dev/null
assert_log_contains "Claude working sets @claude_title" "tmux set-option -p -t %99 @claude_title ⏳ mock-repo"
assert_log_contains "Claude working renames window" "tmux rename-window -t @99 ⏳ mock-repo"

: > "$MOCK_TMUX_LOG"
PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" MOCK_PANE_PATH="/tmp/mock-repo" "$CLAUDE_STATUS_BIN" waiting < /dev/null
assert_log_contains "Claude waiting updates @claude_title" "tmux set-option -p -t %99 @claude_title mock-repo"
assert_log_contains "Claude waiting removes hourglass" "tmux rename-window -t @99 mock-repo"

echo "=== Test 9: zsh precmd resets agent-managed tmux titles without clobbering manual renames ==="
if command -v zsh >/dev/null 2>&1; then
  ZSH_FN_FILE="$TMP_DIR/tmux_reset.zsh"
  awk '/^      _tmux_reset_agent_title \(\)/,/^      \}/' "$REPO_ROOT/home/.zshrc" > "$ZSH_FN_FILE"
  if [[ ! -s "$ZSH_FN_FILE" ]]; then
    echo "FAIL: Could not extract _tmux_reset_agent_title from home/.zshrc"
    FAILED=1
  else
    : > "$MOCK_TMUX_LOG"
    PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" MOCK_AGENT_STATE="@99|[AGY] ● stale" zsh -fc "source '$ZSH_FN_FILE' && _tmux_reset_agent_title"
    assert_log_contains "zsh unsets @agy_title when agent title present" "tmux set-option -p -u -t %99 @agy_title"
    assert_log_contains "zsh unsets @claude_title when agent title present" "tmux set-option -p -u -t %99 @claude_title"
    assert_log_contains "zsh restores automatic-rename on" "tmux set-window-option -t @99 automatic-rename on"

    : > "$MOCK_TMUX_LOG"
    PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" MOCK_AGENT_STATE="@99|" zsh -fc "source '$ZSH_FN_FILE' && _tmux_reset_agent_title"
    assert_log_not_contains "zsh does not touch automatic-rename on manual windows" "set-window-option"
  fi
else
  echo "SKIP: zsh not installed"
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "TESTS FAILED"
  exit 1
fi
