#!/usr/bin/env bash
# install_udev.sh — install keyboard hotplug/resume reset (Approach B: systemd user service)
#
# Installs:
#   /etc/udev/rules.d/99-keyboard.rules     — udev rule (USB keyboard add events)
#   /usr/local/bin/keyboard-udev            — root bridge script
#   /usr/local/bin/keyboard-settings        — settings script (also in ~/bin via stow)
#   /lib/systemd/system-sleep/keyboard-sleep — resume hook
#   ~/.config/systemd/user/keyboard-reset.service — via stow (no manual copy needed)
#
# Must be run as root (sudo ./scripts/install_udev.sh).
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

log_info "Installing keyboard reset for user: $TARGET_USER (uid=$TARGET_UID)"

# ---------------------------------------------------------------------------
# System files
# ---------------------------------------------------------------------------
execute install -Dm644 "$DOTFILES_DIR/udev/99-keyboard.rules" \
    /etc/udev/rules.d/99-keyboard.rules
log_info "installed 99-keyboard.rules"

execute install -Dm755 "$DOTFILES_DIR/home/bin/keyboard-udev" \
    /usr/local/bin/keyboard-udev
log_info "installed keyboard-udev → /usr/local/bin/"

execute install -Dm755 "$DOTFILES_DIR/home/bin/keyboard-settings" \
    /usr/local/bin/keyboard-settings
log_info "installed keyboard-settings → /usr/local/bin/"

execute install -Dm755 "$DOTFILES_DIR/system-sleep/keyboard-sleep" \
    /lib/systemd/system-sleep/keyboard-sleep
log_info "installed keyboard-sleep → /lib/systemd/system-sleep/"

# ---------------------------------------------------------------------------
# Stow the user service (keyboard-reset.service lives in home/.config/systemd/user/)
# The main install.sh stow step handles this; run it here too if stow is available.
# ---------------------------------------------------------------------------
if command -v stow &>/dev/null; then
    execute stow --ignore="glow" -t "$TARGET_HOME" -d "$DOTFILES_DIR" home
    execute chown -R "$TARGET_USER:" "$TARGET_HOME/.config/systemd"
    log_info "stow: keyboard-reset.service symlinked into $TARGET_HOME/.config/systemd/user/"
else
    log_warn "stow not found — manually copy home/.config/systemd/user/keyboard-reset.service to $TARGET_HOME/.config/systemd/user/"
fi

# ---------------------------------------------------------------------------
# Reload udev
# ---------------------------------------------------------------------------
execute udevadm control --reload-rules
execute udevadm trigger --subsystem-match=input --action=add 2>/dev/null || true
log_info "udev rules reloaded"

# ---------------------------------------------------------------------------
# Reload user's systemd and run once (if session is active)
# ---------------------------------------------------------------------------
if [[ -d "$XDG_RUNTIME_DIR" ]]; then
    execute runuser -u "$TARGET_USER" -- \
        env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
        systemctl --user daemon-reload
    log_info "user systemd daemon reloaded"

    execute runuser -u "$TARGET_USER" -- \
        env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
        systemctl --user start keyboard-reset.service \
        && log_info "keyboard-reset.service started" \
        || log_warn "keyboard-reset.service failed (X may not be ready yet)"
else
    log_warn "No active session for $TARGET_USER — after login run:"
    log_warn "  systemctl --user daemon-reload"
    log_warn "  systemctl --user start keyboard-reset.service"
fi

log_info "Done. Check logs with: journalctl --user -u keyboard-reset.service"
