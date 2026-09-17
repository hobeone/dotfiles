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
if [[ "\$*" == *"display-message -t %99 -p "* ]]; then
  echo "@99 test_win"
  exit 0
fi
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
  if ! grep -q -- "$needle" "$MOCK_TMUX_LOG" 2>/dev/null; then
    echo "FAIL: $label - log did not contain '$needle'"
    echo "Log content:"
    cat "$MOCK_TMUX_LOG" 2>/dev/null || true
    FAILED=1
  else
    echo "PASS: $label"
  fi
}

echo "=== Test 1: Git repo in working state ==="
> "$MOCK_TMUX_LOG"
GIT_REPO="$TMP_DIR/my-repo"
mkdir -p "$GIT_REPO"
git -C "$GIT_REPO" init -q -b main
INPUT_JSON=$(jq -n --arg cwd "$GIT_REPO" '{agent_state: "working", cwd: $cwd}')

OUT=$(PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" "$WINDOW_TITLE_BIN" <<< "$INPUT_JSON")
assert_eq "Working stdout" "[AGY] ⏳ my-repo" "$OUT"
assert_log_contains "Working tmux rename" "tmux rename-window -t @99 ⏳ my-repo"

echo "=== Test 2: Git repo in idle state ==="
> "$MOCK_TMUX_LOG"
INPUT_JSON=$(jq -n --arg cwd "$GIT_REPO" '{agent_state: "idle", cwd: $cwd}')
OUT=$(PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" "$WINDOW_TITLE_BIN" <<< "$INPUT_JSON")
assert_eq "Idle stdout" "[AGY] my-repo" "$OUT"
assert_log_contains "Idle tmux rename" "tmux rename-window -t @99 my-repo"

echo "=== Test 3: Local VCS Resolver Hook ==="
> "$MOCK_TMUX_LOG"
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
assert_eq "Local hook stdout" "[AGY] ⏳ custom-ws" "$OUT"
assert_log_contains "Local hook tmux rename" "tmux rename-window -t @99 ⏳ custom-ws"

echo "=== Test 4: Linked Git Worktree ==="
> "$MOCK_TMUX_LOG"
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
assert_eq "Worktree stdout" "[AGY] parent-repo (feature-auth)" "$OUT"
assert_log_contains "Worktree tmux rename" "tmux rename-window -t @99 parent-repo (feature-auth)"

echo "=== Test 5: Plain directory without VCS ==="
> "$MOCK_TMUX_LOG"
PLAIN_DIR="$TMP_DIR/simple-folder"
mkdir -p "$PLAIN_DIR"
INPUT_JSON=$(jq -n --arg cwd "$PLAIN_DIR" '{agent_state: "working", cwd: $cwd}')
OUT=$(PATH="$TMP_DIR:$PATH" TMUX="/tmp/test,1,0" TMUX_PANE="%99" "$WINDOW_TITLE_BIN" <<< "$INPUT_JSON")
assert_eq "Plain dir stdout" "[AGY] ⏳ simple-folder" "$OUT"
assert_log_contains "Plain dir tmux rename" "tmux rename-window -t @99 ⏳ simple-folder"

echo "=== Test 6: Outside of TMUX ==="
> "$MOCK_TMUX_LOG"
OUT=$(PATH="$TMP_DIR:$PATH" TMUX="" TMUX_PANE="" "$WINDOW_TITLE_BIN" <<< "$INPUT_JSON")
assert_eq "No TMUX stdout" "[AGY] ⏳ simple-folder" "$OUT"
if [[ -s "$MOCK_TMUX_LOG" ]]; then
  echo "FAIL: Tmux commands called when TMUX is unset"
  FAILED=1
else
  echo "PASS: No tmux commands invoked when outside TMUX"
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "TESTS FAILED"
  exit 1
fi
