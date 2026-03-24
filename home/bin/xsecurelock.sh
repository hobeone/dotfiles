#!/bin/bash
#
# xsecurelock.sh - A wrapper for xsecurelock with sane defaults and integration.
#
# This script ensures that only one instance of xsecurelock runs, handles
# configuration loading, sets up environment variables, and integrates with
# logind.

set -o nounset
set -o pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly LOCK_FILE="/run/user/${UID}/xsecurelock_${XDG_SESSION_ID:-unknown}_${DISPLAY:-unknown}"

# Function to handle singleton execution using flock.
ensure_singleton() {
  if [[ "${FLOCKER:-}" != "$0" ]]; then
    # Open a locked file descriptor.
    exec {FLOCK_FD}>"${LOCK_FILE}"
    if ! flock --exclusive --nonblock "${FLOCK_FD}"; then
      exit 1
    fi

    # Fork to separate locking roles.
    # Parent holds the flock; child will execute the main logic.
    {
      exec {FLOCK_FD}>&-
      export FLOCKER="$0"
      exec "$0" "$@"
    } &
    
    local child_pid=$!
    
    # Close sleep lock if present in parent.
    if [[ -n "${XSS_SLEEP_LOCK_FD:-}" ]]; then
      exec {XSS_SLEEP_LOCK_FD}>&-
    fi

    # Forward SIGTERM to the child.
    trap 'kill "${child_pid}" 2>/dev/null' TERM
    wait "${child_pid}"
    exit $?
  fi
}

# Load configuration from .xsecurelockrc and .xsessionrc.
load_config() {
  if [[ -f "${HOME}/.xsecurelockrc" ]]; then
    # shellcheck source=/dev/null
    source "${HOME}/.xsecurelockrc"
    if [[ -f "${HOME}/.xsessionrc" ]] && grep -qE '^export XSECURELOCK_' "${HOME}/.xsessionrc"; then
      echo "WARNING: XSECURELOCK settings in .xsessionrc and .xsecurelockrc" >&2
      echo "         Only parsing .xsecurelockrc" >&2
    fi
  elif [[ -f "${HOME}/.xsessionrc" ]]; then
    # Parse only XSECURELOCK exports from .xsessionrc.
    source <(grep -E '^export XSECURELOCK_' "${HOME}/.xsessionrc")
  fi
}

# Set default environment variables for xsecurelock.
setup_env() {
  # Forcing grabs to err on the side of caution.
  export XSECURELOCK_FORCE_GRAB="${XSECURELOCK_FORCE_GRAB:-1}"

  # Keep monitors on by default via xsecurelock; let power manager handle it.
  export XSECURELOCK_BLANK_DPMS_STATE="${XSECURELOCK_BLANK_DPMS_STATE:-on}"

  # PAM service name.
  export XSECURELOCK_PAM_SERVICE="${XSECURELOCK_PAM_SERVICE:-xsecurelock}"

  # Path to xscreensaver helpers.
  export XSECURELOCK_XSCREENSAVER_PATH="${XSECURELOCK_XSCREENSAVER_PATH:-/usr/libexec/xscreensaver}"

  # Timer for non-idle detection.
  export XSECURELOCK_IDLE_TIMERS="${XSECURELOCK_IDLE_TIMERS:-IDLETIME}"

  # Dimming configuration.
  export XSECURELOCK_DIM_TIME_MS="${XSECURELOCK_DIM_TIME_MS:-2000}"
  export XSECURELOCK_WAIT_TIME_MS="${XSECURELOCK_WAIT_TIME_MS:-8000}"
  export XSECURELOCK_ENABLE_DIMMER="${XSECURELOCK_ENABLE_DIMMER:-true}"

  export XSECURELOCK_DATE_FONT="${XSECURELOCK_DATE_FONT:-Roboto}"
  export XSECURELOCK_TIME_FONT="${XSECURELOCK_TIME_FONT:-Roboto-Thin}"
  
  # Ensure formats start with exactly one '+'.
  local date_fmt="${XSECURELOCK_DATE_FORMAT-%A, %d %B %Y}"
  export XSECURELOCK_DATE_FORMAT="+${date_fmt##+}"
  
  export XSECURELOCK_TIME_FORMAT="%H:%M"

  export XSECURELOCK_DISCARD_FIRST_KEYPRESS="${XSECURELOCK_DISCARD_FIRST_KEYPRESS:-0}"
  export XSECURELOCK_PASSWORD_PROMPT="${XSECURELOCK_PASSWORD_PROMPT:-cursor}"
  export XSECURELOCK_FONT="${XSECURELOCK_FONT:-Noto Mono-21}"
  
  # User switching and identity display.
  local show_user=1
  local show_host=1
  local switcher=''

  # Check if user switching should be allowed (typically on multi-user systems).
  if command -v netgroup >/dev/null 2>&1; then
    if ! cmp --silent <(echo "${USER}") <(netgroup -u login_localhost 2>/dev/null); then
      switcher='dm-tool switch-to-greeter'
    fi
  fi

  export XSECURELOCK_SHOW_USERNAME="${XSECURELOCK_SHOW_USERNAME:-${show_user}}"
  export XSECURELOCK_SHOW_HOSTNAME="${XSECURELOCK_SHOW_HOSTNAME:-${show_host}}"
  export XSECURELOCK_SWITCH_USER_COMMAND="${XSECURELOCK_SWITCH_USER_COMMAND-${switcher}}"
}

# Notify logind about the lock state.
notify_logind() {
  local state="$1" # boolean:true or boolean:false
  /usr/bin/dbus-send --system --print-reply \
    --dest=org.freedesktop.login1 /org/freedesktop/login1/session/self \
    org.freedesktop.login1.Session.SetLockedHint \
    "boolean:${state}" > /dev/null 2>&1 || true
}

# Main execution logic.
main() {
  ensure_singleton "$@"

  load_config
  setup_env

  # Handle idle-lock dimming if enabled.
  if [[ "${LOCKED_BY_SESSION_IDLE:-}" == "true" && "${XSECURELOCK_ENABLE_DIMMER:-}" == "true" ]]; then
    local helper_path="/usr/libexec/xsecurelock"
    if "${helper_path}/until_nonidle" "${helper_path}/dimmer"; then
      echo "$(date) - xsecurelock idle lock canceled by session activity" >&2
      exit 0
    fi
  fi

  # Run xsecurelock.
  # The command after '--' is executed by xsecurelock once the screen is locked.
  xsecurelock "$@" -- \
    /usr/bin/dbus-send --system --print-reply \
    --dest=org.freedesktop.login1 /org/freedesktop/login1/session/self \
    org.freedesktop.login1.Session.SetLockedHint \
    boolean:true &
  
  local child_pid=$!
  
  # Close the sleep inhibit file descriptor so xsecurelock is the sole holder.
  if [[ -n "${XSS_SLEEP_LOCK_FD:-}" ]]; then
    exec {XSS_SLEEP_LOCK_FD}>&-
  fi

  # Forward SIGTERM to xsecurelock.
  trap 'kill "${child_pid}" 2>/dev/null' TERM
  
  wait "${child_pid}"
  local status=$?

  # Notify logind that we are unlocked.
  notify_logind false
  
  exit "${status}"
}

main "$@"
