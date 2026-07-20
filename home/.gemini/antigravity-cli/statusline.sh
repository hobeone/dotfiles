#!/bin/bash
set -euo pipefail

# ─── ANSI Helpers (Standard 16-color palette only) ───────────────────────────
R="\033[0m"         # Reset
B="\033[1m"         # Bold
I="\033[3m"         # Italic

FG_WHITE="\033[37m"
FG_GRAY="\033[90m"
FG_BRIGHT_RED="\033[91m"
FG_BRIGHT_GREEN="\033[92m"
FG_BRIGHT_YELLOW="\033[93m"
FG_BRIGHT_BLUE="\033[94m"
FG_BRIGHT_MAGENTA="\033[95m"
FG_BRIGHT_CYAN="\033[96m"
FG_BRIGHT_WHITE="\033[97m"

# Number Highlight Color
NUM_COLOR="${FG_BRIGHT_WHITE}${B}"

# ─── Parse JSON from stdin (Single jq pass for performance) ──────────────────
# Extract all fields in one pass to prevent spawning jq 8 times.
STDIN_CONTENT=$(cat)

# Save input to a tmp file for examination, not everything is fully documented
# so looking at the actual file helps set up the parsing.
(umask 077; printf "%s" "$STDIN_CONTENT" > /tmp/statusline_input.json) 2>/dev/null || true

{
  read -r STATE
  read -r CWD
  read -r USED_PCT
  read -r VCS_BRANCH
  read -r VCS_DIRTY
  read -r SANDBOX
  read -r ARTIFACTS
  read -r SUBAGENTS
  read -r BG_TASKS
  read -r MODEL
  read -r COLS
} <<< "$(
  if [ -z "$STDIN_CONTENT" ]; then
    printf "idle\n0\n\nfalse\nfalse\n0\n0\n0\n\n80\n"
  else
    printf "%s" "$STDIN_CONTENT" | jq -r '
      (.agent_state // "idle"),
      (.workspace.current_dir // ""),
      (.context_window.used_percentage // 0),
      (.vcs.branch // .vcs.worktree // .vcs.client // ""),
      (.vcs.dirty // false),
      (.sandbox.enabled // false),
      (.artifact_count // 0),
      (if .subagents | type == "array" then ([.subagents[] | select(.status == "running")] | length) else 0 end),
      (.task_count // 0),
      (.model.display_name // ""),
      (.terminal_width // 80)
    ' 2>/dev/null || printf "idle\n0\n\nfalse\nfalse\n0\n0\n0\n\n80\n"
  fi
)"

# ─── Computed Values ─────────────────────────────────────────────────────────
# Use LC_NUMERIC=C to prevent bash printf errors in locales that use commas for decimals
PCT_FMT=$(LC_NUMERIC=C printf "%.1f" "$USED_PCT")
PCT_INT=${USED_PCT%.*}; PCT_INT=${PCT_INT:-0}

# ─── State Indicator (No background colors) ──────────────────────────────────
case "$STATE" in
  idle)     S="${FG_BRIGHT_GREEN}${B}● READY${R}" ;;
  thinking) S="${FG_BRIGHT_YELLOW}${B}◆ THINKING${R}" ;;
  working)  S="${FG_BRIGHT_CYAN}${B}⚙ WORKING${R}" ;;
  tool_use) S="${FG_BRIGHT_MAGENTA}${B}🔧 TOOL${R}" ;;
  *)        S="${FG_WHITE}${B}⏳ $(echo "$STATE" | tr '[:lower:]' '[:upper:]')${R}" ;;
esac

# ─── VCS Branch / Worktree ───────────────────────────────────────────────────
if [ -z "$VCS_BRANCH" ] && [ -n "$CWD" ] && [ -d "$CWD" ]; then
  if command -v git &>/dev/null && git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    VCS_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || true)
    if [ -z "$VCS_BRANCH" ]; then
      VCS_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
      if [ "$VCS_BRANCH" = "HEAD" ] || [ -z "$VCS_BRANCH" ]; then
        VCS_BRANCH=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null || true)
      fi
    fi
    if [ "$VCS_DIRTY" = "false" ] || [ -z "$VCS_DIRTY" ]; then
      if [ -n "$(git -C "$CWD" status --porcelain 2>/dev/null | head -n 1)" ]; then
        VCS_DIRTY="true"
      fi
    fi
  elif command -v hg &>/dev/null && hg -R "$CWD" root &>/dev/null 2>&1; then
    VCS_BRANCH=$(hg -R "$CWD" branch 2>/dev/null || true)
  elif command -v jj &>/dev/null && jj -R "$CWD" root &>/dev/null 2>&1; then
    VCS_BRANCH=$(jj -R "$CWD" log --no-graph -r @ -T 'bookmarks' 2>/dev/null || true)
  elif [[ "$CWD" =~ ^/google/src/cloud/[^/]+/([^/]+) ]]; then
    VCS_BRANCH="${BASH_REMATCH[1]}"
  fi
fi

V=""
if [ -n "$VCS_BRANCH" ]; then
  if [ "$VCS_DIRTY" = "true" ]; then
    V="${FG_GRAY} ╱ ${FG_BRIGHT_RED}${VCS_BRANCH}${FG_BRIGHT_YELLOW}*${R}"
  else
    V="${FG_GRAY} ╱ ${FG_BRIGHT_BLUE}${VCS_BRANCH}${R}"
  fi
fi

# ─── Model ───────────────────────────────────────────────────────────────────
M=""
if [ -n "$MODEL" ]; then
  M="${FG_GRAY} ╱ ${FG_BRIGHT_MAGENTA}${I}${MODEL}${R}"
fi

# ─── Sandbox Badge ───────────────────────────────────────────────────────────
if [ "$SANDBOX" = "true" ]; then
  SB="${FG_GRAY}sandbox ${FG_BRIGHT_GREEN}${B}ON${R}"
else
  SB="${FG_GRAY}sandbox off${R}"
fi

# Format Context usage bar
USED_PCT_INT=${USED_PCT%.*}
USED_PCT_INT=${USED_PCT_INT:-0}

BAR_COLOR="\033[32m"
[ "$USED_PCT_INT" -ge 60 ] && BAR_COLOR="\033[33m"
[ "$USED_PCT_INT" -ge 85 ] && BAR_COLOR="\033[31m"

BAR=""
TOTAL_BARS=10
FILLED_BARS=$((USED_PCT_INT / 10))
for ((i=0; i<FILLED_BARS; i++)); do BAR="${BAR}▰"; done
for ((i=FILLED_BARS; i<TOTAL_BARS; i++)); do BAR="${BAR}▱"; done




# ─── Stats ───────────────────────────────────────────────────────────────────
CTX="${FG_GRAY}ctx ${BAR_COLOR}${BAR} ${NUM_COLOR}${PCT_FMT}%${R}"
ART_FMT="${FG_GRAY}artifacts ${NUM_COLOR}${ARTIFACTS}${R}"
SUB_FMT="${FG_GRAY}subagents ${NUM_COLOR}${SUBAGENTS}${R}"
BG_FMT="${FG_GRAY}tasks ${NUM_COLOR}${BG_TASKS}${R}"

# ─── Separators ──────────────────────────────────────────────────────────────
DOT="${FG_GRAY} · ${R}"

# ─── Output ──────────────────────────────────────────────────────────────────
LINE1="${S}${M}${V}${DOT}${CWD}"
LINE2=" ${CTX}${DOT}${ART_FMT}${DOT}${SUB_FMT}${DOT}${BG_FMT}${DOT}${SB}"

if [ "$COLS" -ge 80 ]; then
  # Standard: two-line layout with border (ensures worktree/branch + CWD never overflow)
  echo -e "${FG_GRAY}╭─${R} ${LINE1}"
  echo -e "${FG_GRAY}╰─${R}${LINE2}"
else
  # Narrow: compact two-line layout (ensures branch/worktree is always displayed)
  echo -e "${S}${M}${V}"
  echo -e "${CTX}${DOT}${ART_FMT}${DOT}${BG_FMT}"
fi
