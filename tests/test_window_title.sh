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
  *"display-message -t %99 -p #{window_id}"*"#{window_name}"*"#{@agy_title}"*"#{@claude_title}"*)
    printf '%b\n' "\${MOCK_AGENT_STATE:-@99\t\t\t}"
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

echo "=== Test 7: tmux.conf automatic-rename-format uses @agy_title and @claude_title ==="
TMUX_CONF="$REPO_ROOT/home/.config/tmux/tmux.conf"
EXPECTED_FMT="setw -g automatic-rename-format '#{?#{m/r:^(cli|agy)$,#{pane_current_command}},#{?#{@agy_title},#{@agy_title},#{b:pane_current_path}},#{?#{==:#{pane_current_command},claude},#{?#{@claude_title},#{@claude_title},#{b:pane_current_path}},#{?#{==:#{pane_current_command},zsh},#{b:pane_current_path},#{pane_current_command}}}}'"
if grep -Fq -- "$EXPECTED_FMT" "$TMUX_CONF" 2>/dev/null; then
  echo "PASS: tmux.conf automatic-rename-format configured with @agy_title and @claude_title"
else
  echo "FAIL: tmux.conf automatic-rename-format missing @agy_title/@claude_title rule"
  FAILED=1
fi

echo "=== Test 8: Claude tmux-status.sh sets @claude_title and keeps automatic-rename on ==="
CLAUDE_STATUS_BIN="$REPO_ROOT/home/.claude/hooks/tmux-status.sh"
: > "$MOCK_TMUX_LOG"
PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" MOCK_PANE_PATH="/tmp/mock-repo" "$CLAUDE_STATUS_BIN" working < /dev/null
assert_log_contains "Claude working sets @claude_title" "tmux set-option -p -t %99 @claude_title ⏳ mock-repo"
assert_log_contains "Claude working renames window" "tmux rename-window -t @99 ⏳ mock-repo"
assert_log_contains "Claude working keeps automatic-rename on" "tmux set-window-option -t @99 automatic-rename on"
assert_log_not_contains "Claude working never disables automatic-rename" "automatic-rename off"

: > "$MOCK_TMUX_LOG"
PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" MOCK_PANE_PATH="/tmp/mock-repo" "$CLAUDE_STATUS_BIN" waiting < /dev/null
assert_log_contains "Claude waiting updates @claude_title" "tmux set-option -p -t %99 @claude_title mock-repo"
assert_log_contains "Claude waiting removes hourglass" "tmux rename-window -t @99 mock-repo"
assert_log_contains "Claude waiting keeps automatic-rename on" "tmux set-window-option -t @99 automatic-rename on"
assert_log_not_contains "Claude waiting never disables automatic-rename" "automatic-rename off"

echo "=== Test 9: zsh add-zsh-hook resets agent-managed tmux titles safely ==="
if command -v zsh >/dev/null 2>&1; then
  ZSH_HOOK_FILE="$TMP_DIR/tmux_hook.zsh"
  awk '/^# Refresh environment variables within TMUX/,/^fi$/' "$REPO_ROOT/home/.zshrc" > "$ZSH_HOOK_FILE"
  if [[ ! -s "$ZSH_HOOK_FILE" ]]; then
    echo "FAIL: Could not extract TMUX hook block from home/.zshrc"
    FAILED=1
  else
    HOOK_CHECK=$(PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" zsh -fc '
      source "'"$ZSH_HOOK_FILE"'"
      [[ "${preexec_functions[(r)_tmux_mark_agent_title_dirty]}" == "_tmux_mark_agent_title_dirty" ]] || exit 11
      [[ "${precmd_functions[(r)_tmux_reset_agent_title]}" == "_tmux_reset_agent_title" ]] || exit 12
      echo "hooks-ok"
    ' 2>&1 || true)
    assert_eq "zsh registers preexec and precmd hooks via add-zsh-hook" "hooks-ok" "$HOOK_CHECK"

    : > "$MOCK_TMUX_LOG"
    PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" zsh -fc '
      source "'"$ZSH_HOOK_FILE"'"
      run_precmd() { local fn; for fn in "${precmd_functions[@]}"; do "$fn"; done; }
      run_preexec() { local fn; for fn in "${preexec_functions[@]}"; do "$fn" "$1"; done; }

      echo "--- startup-dirty ---" >> "'"$MOCK_TMUX_LOG"'"
      export MOCK_AGENT_STATE="@99\t[AGY] ● stale\t[AGY] ● stale\t"
      run_precmd

      echo "--- empty-prompt ---" >> "'"$MOCK_TMUX_LOG"'"
      run_precmd

      echo "--- manual-rename-during-agent ---" >> "'"$MOCK_TMUX_LOG"'"
      run_preexec "claude"
      export MOCK_AGENT_STATE="@99\tcustom-win\t\t⏳ mock-repo"
      run_precmd

      echo "--- clean-manual-window ---" >> "'"$MOCK_TMUX_LOG"'"
      run_preexec "ls"
      export MOCK_AGENT_STATE="@99\tcustom-win\t\t"
      run_precmd
    '

    STARTUP_LOG=$(sed -n '/^--- startup-dirty ---$/,/^--- empty-prompt ---$/p' "$MOCK_TMUX_LOG")
    EMPTY_LOG=$(sed -n '/^--- empty-prompt ---$/,/^--- manual-rename-during-agent ---$/p' "$MOCK_TMUX_LOG" | grep -v '^---' || true)
    MANUAL_AGENT_LOG=$(sed -n '/^--- manual-rename-during-agent ---$/,/^--- clean-manual-window ---$/p' "$MOCK_TMUX_LOG")
    CLEAN_LOG=$(sed -n '/^--- clean-manual-window ---$/,$p' "$MOCK_TMUX_LOG")

    assert_str_contains() {
      local label="$1" haystack="$2" needle="$3"
      if [[ "$haystack" == *"$needle"* ]]; then
        echo "PASS: $label"
      else
        echo "FAIL: $label - missing '$needle'"
        FAILED=1
      fi
    }
    assert_str_not_contains() {
      local label="$1" haystack="$2" needle="$3"
      if [[ "$haystack" != *"$needle"* ]]; then
        echo "PASS: $label"
      else
        echo "FAIL: $label - unexpectedly contained '$needle'"
        FAILED=1
      fi
    }

    assert_str_contains "zsh unsets @agy_title on startup precmd" "$STARTUP_LOG" "tmux set-option -p -u -t %99 @agy_title"
    assert_str_contains "zsh unsets @claude_title on startup precmd" "$STARTUP_LOG" "tmux set-option -p -u -t %99 @claude_title"
    assert_str_contains "zsh restores automatic-rename on matching agent window" "$STARTUP_LOG" "tmux set-window-option -t @99 automatic-rename on"

    assert_eq "zsh skips tmux IPC on empty prompt without preexec" "" "$EMPTY_LOG"

    assert_str_contains "zsh clears @agy_title when window manually renamed" "$MANUAL_AGENT_LOG" "tmux set-option -p -u -t %99 @agy_title"
    assert_str_contains "zsh clears @claude_title when window manually renamed" "$MANUAL_AGENT_LOG" "tmux set-option -p -u -t %99 @claude_title"
    assert_str_not_contains "zsh preserves manual window rename made during agent run" "$MANUAL_AGENT_LOG" "automatic-rename on"

    assert_str_not_contains "zsh does not touch automatic-rename on clean manual windows" "$CLEAN_LOG" "set-window-option"
  fi
else
  if [[ -n "${CI:-}" ]]; then
    echo "FAIL: zsh not installed in CI"
    FAILED=1
  else
    echo "SKIP: zsh not installed"
  fi
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "TESTS FAILED"
  exit 1
fi
