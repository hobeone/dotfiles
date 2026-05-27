#!/bin/bash
set -euo pipefail

# Read JSON payload from stdin
DATA=$(cat)

# Extract fields using jq
eval $(echo "$DATA" | jq -r '
  "STATE=\"\(.agent_state // "idle")\"
   CWD=\"\(.workspace.current_dir // "")\"
   USED_PCT=\"\(.context_window.used_percentage // 0)\"
   COST=\"\(.cost.total_cost_usd // 0)\"
   VCS_BRANCH=\"\(.vcs.branch // "")\"
   VCS_DIRTY=\"\(.vcs.dirty // false)\"
   SANDBOX=\"\(.sandbox.enabled // false)\"
   TASKS_COUNT=\"\(.background_tasks | length)\"
   ARTIFACTS_COUNT=\"\(.artifacts | length)\"
   MODEL_NAME=\"\(.model.display_name // "")\"
   COLS=\"\(.terminal_width // 80)\"
  "
' 2>/dev/null || echo 'STATE="idle" CWD="" USED_PCT="0" COST="0" VCS_BRANCH="" VCS_DIRTY="false" SANDBOX="false" TASKS_COUNT="0" ARTIFACTS_COUNT="0" MODEL_NAME=""')

USED_PCT_FMT=$(printf "%.2f" "$USED_PCT")
USED_PCT_INT=${USED_PCT%.*}
USED_PCT_INT=${USED_PCT_INT:-0}

# Format state
case "$STATE" in
  idle)     STATE_FMT="\033[1;32m● READY\033[0m" ;;
  thinking) STATE_FMT="\033[1;33m◆ THINKING\033[0m" ;;
  working)  STATE_FMT="\033[1;36m⚙ WORKING\033[0m" ;;
  tool_use) STATE_FMT="\033[1;35m🛠 TOOL USE\033[0m" ;;
  *)        STATE_FMT="\033[2m⏳ ${STATE}\033[0m" ;;
esac

# Format VCS
VCS_FMT=""
if [ -n "$VCS_BRANCH" ]; then
  if [ "$VCS_DIRTY" = "true" ]; then
    VCS_FMT=" \033[31m $VCS_BRANCH*\033[0m"
  else
    VCS_FMT=" \033[34m $VCS_BRANCH\033[0m"
  fi
fi

# Format Sandbox
SANDBOX_FMT="\033[90mSandbox: OFF\033[0m"
if [ "$SANDBOX" = "true" ]; then
  SANDBOX_FMT="\033[32mSandbox: ON\033[0m"
fi

# Format Context usage bar
BAR_COLOR="\033[32m"
[ "$USED_PCT_INT" -ge 60 ] && BAR_COLOR="\033[33m"
[ "$USED_PCT_INT" -ge 85 ] && BAR_COLOR="\033[31m"

BAR=""
TOTAL_BARS=10
FILLED_BARS=$((USED_PCT_INT / 10))
for ((i=0; i<FILLED_BARS; i++)); do BAR="${BAR}▰"; done
for ((i=FILLED_BARS; i<TOTAL_BARS; i++)); do BAR="${BAR}▱"; done

# Format width
if [ "$COLS" -ge 100 ]; then
  echo -e " $STATE_FMT \033[90m│\033[0m \033[35m$MODEL_NAME\033[0m$VCS_FMT \033[90m│\033[0m $CWD \033[90m│\033[0m \033[90mContext:\033[0m ${BAR_COLOR}${BAR}\033[0m \033[33m${USED_PCT_FMT}%\033[0m \033[90m│\033[0m Tasks: \033[36m$TASKS_COUNT\033[0m \033[90m│\033[0m Artifacts: \033[35m$ARTIFACTS_COUNT\033[0m"
else
  echo -e "\033[90m╭─\033[0m $STATE_FMT \033[90m│\033[0m \033[35m$MODEL_NAME\033[0m$VCS_FMT \033[90m│\033[0m $CWD"
  echo -e "\033[90m╰─\033[0m \033[90mContext:\033[0m ${BAR_COLOR}${BAR}\033[0m \033[33m${USED_PCT_FMT}%\033[0m \033[90m│\033[0m Tasks: \033[36m$TASKS_COUNT\033[0m \033[90m│\033[0m Artifacts: \033[35m$ARTIFACTS_COUNT\033[0m"
fi
