#!/usr/bin/env bash
# install_keyboard.sh — install keyboard resume hook (system-sleep integration)
#
# Installs:
#   /lib/systemd/system-sleep/keyboard-sleep — re-applies settings after resume
#
# Hotplug (KVM switch, USB plug) is handled by keyboard-watch, which runs
# inside the X session and is autostarted via ~/.config/autostart/keyboard-watch.desktop
#
# Must be run as root (sudo ./scripts/install_keyboard.sh).
# Installs for $SUDO_USER (the user who invoked sudo).

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=false

usage() {
    echo "Usage: sudo $(basename "$0") [-n|--dry-run]"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=true; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: must be run as root (use sudo)." >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-$(whoami)}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_UID=$(id -u "$TARGET_USER")
XDG_RUNTIME_DIR="/run/user/$TARGET_UID"

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*"; }

execute() {
    if $DRY_RUN; then
        log_info "[dry-run] $*"
    else
        "$@"
    fi
}

log_info "Installing keyboard resume hook for user: $TARGET_USER (uid=$TARGET_UID)"

# ---------------------------------------------------------------------------
# System sleep hook (suspend/resume)
# ---------------------------------------------------------------------------
execute install -Dm755 "$DOTFILES_DIR/system-sleep/keyboard-sleep" \
    /lib/systemd/system-sleep/keyboard-sleep
log_info "installed keyboard-sleep → /lib/systemd/system-sleep/"
