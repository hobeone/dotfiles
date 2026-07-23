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
DOT="${FG_GRAY} · ${R}"

# ─── Parse JSON from stdin (Single jq pass for performance) ──────────────────
# Extract all fields in one pass to prevent spawning jq 8 times.
STDIN_CONTENT=$(cat)

# so looking at the actual file helps set up the parsing.
(umask 077; printf "%s" "$STDIN_CONTENT" > /tmp/statusline_input.json) 2>/dev/null || true

{
  read -r STATE
  read -r CWD
  read -r RAW_CWD
  read -r VCS_ROOT
  read -r PROJECT_DIR
  read -r USED_PCT
  read -r VCS_BRANCH
  read -r VCS_DIRTY
  read -r SANDBOX
  read -r ARTIFACTS
  read -r SUBAGENTS
  read -r BG_TASKS
  read -r MODEL
  read -r COLS
  read -r Q_PREFIX
  read -r Q5H_REM
  read -r Q5H_RESET_SECS
  read -r QW_REM
  read -r QW_RESET_SECS || true  # last read hits EOF without trailing newline
} <<< "$(
  if [ -z "$STDIN_CONTENT" ]; then
    printf "idle\n\n\n\n\n0\n\nfalse\nfalse\n0\n0\n0\n\n80\n-\n-\n-\n-\n-"
  else
    printf "%s" "$STDIN_CONTENT" | jq -r '
      (.agent_state // "idle"),
      (.workspace.current_dir // ""),
      (.cwd // ""),
      (.vcs.root // ""),
      (.workspace.project_dir // ""),
      (.context_window.used_percentage // 0),
      (.vcs.branch // .vcs.worktree // .vcs.client // ""),
      (.vcs.dirty // false),
      (.sandbox.enabled // false),
      (.artifact_count // 0),
      (if .subagents | type == "array" then ([.subagents[] | select(.status == "running")] | length) else 0 end),
      (.task_count // 0),
      (.model.display_name // ""),
      (.terminal_width // 80),
      # Extract 5h and weekly quota for the active model class
      (
        if .quota | type == "object" and length > 0 then
          (.model.display_name // .model.id // "" | ascii_downcase) as $m |
          (.quota | keys) as $keys |
          ($keys | map(split("-")[0]) | unique) as $available_prefixes |
          (if ($m | contains("gemini")) and ($keys | any(startswith("gemini-"))) then "gemini"
           elif ($m | contains("claude")) and ($keys | any(startswith("claude-"))) then "claude"
           elif ($m | contains("gpt")) and ($keys | any(startswith("gpt-"))) then "gpt"
           else
             (($available_prefixes | map(select(. != "" and ($m | contains(.)))) | first) //
              (if ($keys | any(startswith("3p-"))) then "3p" else ($available_prefixes[0] // "-") end))
           end) as $prefix |
          .quota as $q |
          ($q["\($prefix)-5h"] // $q["5h"] // $q["\($prefix)-5-hour"]) as $q5h |
          ($q["\($prefix)-weekly"] // $q["weekly"] // $q["\($prefix)-7d"] // $q["7d"]) as $qw |
          $prefix,
          ($q5h.remaining_fraction // "-"),
          ($q5h.reset_in_seconds // "-"),
          ($qw.remaining_fraction // "-"),
          ($qw.reset_in_seconds // "-")
        else "-", "-", "-", "-", "-" end
      )
    ' 2>/dev/null || printf "idle\n\n\n\n\n0\n\nfalse\nfalse\n0\n0\n0\n\n80\n-\n-\n-\n-\n-"
  fi
)"

# ─── Computed Values ─────────────────────────────────────────────────────────
# Use LC_NUMERIC=C to prevent bash printf errors in locales that use commas for decimals
PCT_FMT=$(LC_NUMERIC=C printf "%.1f" "$USED_PCT")
PCT_INT=${USED_PCT%.*}; PCT_INT=${PCT_INT:-0}

# ─── Quota Helpers ───────────────────────────────────────────────────────────
fmt_reset_secs() {
  local secs=${1%.*}
  secs=${secs:-0}
  if [ "$secs" -ge 86400 ]; then
    echo "$((secs / 86400))d$(( (secs % 86400) / 3600 ))h"
  elif [ "$secs" -ge 3600 ]; then
    echo "$((secs / 3600))h$(( (secs % 3600) / 60 ))m"
  elif [ "$secs" -ge 60 ]; then
    echo "$((secs / 60))m"
  elif [ "$secs" -gt 0 ]; then
    echo "${secs}s"
  fi
}

fmt_quota_bucket() {
  local label="$1" rem="$2" reset_secs="$3"
  if [ -z "$rem" ] || [ "$rem" = "null" ] || [ "$rem" = "-" ]; then
    return
  fi
  local used_pct
  used_pct=$(awk "BEGIN {print int((1 - ${rem}) * 100 + 0.5)}" 2>/dev/null || echo 0)
  if [ "$used_pct" -lt 0 ]; then used_pct=0; fi
  if [ "$used_pct" -gt 100 ]; then used_pct=100; fi

  local q_color="\033[32m"
  [ "$used_pct" -ge 50 ] && q_color="\033[33m"
  [ "$used_pct" -ge 75 ] && q_color="\033[38;5;208m"
  [ "$used_pct" -ge 90 ] && q_color="\033[31m"

  local q_bar=""
  local filled=$((used_pct * 5 / 100))
  for ((i=0; i<filled; i++)); do q_bar="${q_bar}▰"; done
  for ((i=filled; i<5; i++)); do q_bar="${q_bar}▱"; done

  local reset_str=""
  if [ -n "$reset_secs" ] && [ "$reset_secs" != "null" ] && [ "$reset_secs" != "-" ]; then
    reset_str=$(fmt_reset_secs "$reset_secs")
  fi

  local res="${FG_GRAY}${label} ${q_color}${q_bar} ${NUM_COLOR}${used_pct}%${R}"
  if [ -n "$reset_str" ]; then
    res="${res} ${FG_GRAY}(${reset_str})${R}"
  fi
  echo -e "$res"
}

# ─── Quota Handling ──────────────────────────────────────────────────────────
QUOTA_FMT=""
Q5H_STR=$(fmt_quota_bucket "5h" "$Q5H_REM" "$Q5H_RESET_SECS")
QW_STR=$(fmt_quota_bucket "7d" "$QW_REM" "$QW_RESET_SECS")

if [ -n "$Q5H_STR" ] && [ -n "$QW_STR" ]; then
  QUOTA_FMT="${Q5H_STR}${DOT}${QW_STR}"
elif [ -n "$Q5H_STR" ]; then
  QUOTA_FMT="${Q5H_STR}"
elif [ -n "$QW_STR" ]; then
  QUOTA_FMT="${QW_STR}"
else
  # Legacy fallback: background quota-refresh.sh wrote a cache file
  CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/antigravity"
  CACHE_FILE="${CACHE_DIR}/quota_cache.json"
  if [ -f "$CACHE_FILE" ]; then
    LEGACY_REM=$(jq -r '.models | to_entries | map(.value.remainingFraction) | min // 1.0' "$CACHE_FILE" 2>/dev/null || echo "1.0")
    QUOTA_FMT=$(fmt_quota_bucket "quota" "$LEGACY_REM" "")

    # Spawn background refresh if cache is stale
    NOW=$(date +%s 2>/dev/null || echo 0)
    LAST_MOD=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    CACHE_AGE_SEC=99999
    if [ "$LAST_MOD" -gt 0 ]; then
      CACHE_AGE_SEC=$((NOW - LAST_MOD))
    fi
    REFRESH_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/quota-refresh.sh"
    if [ "$CACHE_AGE_SEC" -ge 30 ] && [ -x "$REFRESH_SCRIPT" ]; then
      ( exec 0</dev/null; exec 1>/dev/null; exec 2>/dev/null; "$REFRESH_SCRIPT" ) &
      disown $! 2>/dev/null || true
    fi
  fi
fi

# ─── State Indicator (No background colors) ──────────────────────────────────
case "$STATE" in
  idle)     S="${FG_BRIGHT_GREEN}${B}● READY${R}" ;;
  thinking) S="${FG_BRIGHT_YELLOW}${B}◆ THINKING${R}" ;;
  working)  S="${FG_BRIGHT_CYAN}${B}⚙ WORKING${R}" ;;
  tool_use) S="${FG_BRIGHT_MAGENTA}${B}🔧 TOOL${R}" ;;
  *)        S="${FG_WHITE}${B}⏳ $(echo "$STATE" | tr '[:lower:]' '[:upper:]')${R}" ;;
esac

# ─── VCS Branch / Worktree ───────────────────────────────────────────────────
# Prioritize candidate directories (like agy-hud): current_dir > cwd > vcs.root > project_dir
VCS_DETECTED=""
if [ -z "$CWD" ]; then
  CWD="${RAW_CWD:-$PROJECT_DIR}"
fi

for cand_dir in "$CWD" "$RAW_CWD" "$VCS_ROOT" "$PROJECT_DIR" "${PWD:-}"; do
  if [ -z "$cand_dir" ] || [ ! -d "$cand_dir" ]; then
    continue
  fi

  if command -v git &>/dev/null && git -C "$cand_dir" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    GIT_DIR=$(git -C "$cand_dir" rev-parse --git-dir 2>/dev/null || true)
    GIT_COMMON_DIR=$(git -C "$cand_dir" rev-parse --git-common-dir 2>/dev/null || true)
    BRANCH=$(git -C "$cand_dir" branch --show-current 2>/dev/null || true)
    if [ -z "$BRANCH" ]; then
      BRANCH=$(git -C "$cand_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    fi
    if [ "$BRANCH" = "HEAD" ]; then
      BRANCH=""
    fi

    if [ -n "$GIT_DIR" ] && [ -n "$GIT_COMMON_DIR" ] && [ "$GIT_DIR" != "$GIT_COMMON_DIR" ]; then
      # Inside a linked git worktree
      WT_NAME=$(basename "$(git -C "$cand_dir" rev-parse --show-toplevel 2>/dev/null || echo "$GIT_DIR")")
      if [ -n "$BRANCH" ] && [ "$BRANCH" != "$WT_NAME" ]; then
        VCS_DETECTED="${WT_NAME} (${BRANCH})"
      else
        VCS_DETECTED="${WT_NAME}"
      fi
    else
      # Main git working tree
      if [ -n "$BRANCH" ]; then
        VCS_DETECTED="$BRANCH"
      else
        VCS_DETECTED=$(git -C "$cand_dir" rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null || true)
      fi
    fi

    if [ "$VCS_DIRTY" = "false" ] || [ -z "$VCS_DIRTY" ]; then
      if [ -n "$(git -C "$cand_dir" status --porcelain 2>/dev/null | head -n 1)" ]; then
        VCS_DIRTY="true"
      fi
    fi
    break
  elif command -v hg &>/dev/null && hg -R "$cand_dir" root &>/dev/null 2>&1; then
    VCS_DETECTED=$(hg -R "$cand_dir" branch 2>/dev/null || true)
    break
  elif command -v jj &>/dev/null && jj -R "$cand_dir" root &>/dev/null 2>&1; then
    VCS_DETECTED=$(jj -R "$cand_dir" log --no-graph -r @ -T 'bookmarks' 2>/dev/null || true)
    break
  elif [[ "$cand_dir" =~ ^/google/src/cloud/[^/]+/([^/]+) ]]; then
    VCS_DETECTED="${BASH_REMATCH[1]}"
    break
  fi
done

if [ -n "$VCS_DETECTED" ]; then
  VCS_BRANCH="$VCS_DETECTED"
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
LINE2=" ${CTX}"
[ -n "$QUOTA_FMT" ] && LINE2="${LINE2}${DOT}${QUOTA_FMT}"
LINE2="${LINE2}${DOT}${ART_FMT}${DOT}${SUB_FMT}${DOT}${BG_FMT}${DOT}${SB}"

if [ "$COLS" -ge 80 ]; then
  # Standard: two-line layout with border (ensures worktree/branch + CWD never overflow)
  echo -e "${FG_GRAY}╭─${R} ${LINE1}"
  echo -e "${FG_GRAY}╰─${R}${LINE2}"
else
  # Narrow: compact two-line layout (ensures branch/worktree is always displayed)
  NARROW_LINE2="${CTX}"
  [ -n "$QUOTA_FMT" ] && NARROW_LINE2="${NARROW_LINE2}${DOT}${QUOTA_FMT}"
  NARROW_LINE2="${NARROW_LINE2}${DOT}${ART_FMT}${DOT}${BG_FMT}"
  echo -e "${S}${M}${V}"
  echo -e "${NARROW_LINE2}"
fi

