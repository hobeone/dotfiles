#!/usr/bin/env bash

# Uninstall dotfiles: remove symlinks created by install.sh
# Does NOT delete config files that were copied (glow) or locally created (.zshrc.local)

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
VERBOSE=false
REMOVE_CLAUDE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Remove symlinks created by install.sh.

Options:
    -n, --dry-run   Show what would be removed without doing it.
    -v, --verbose   Verbose output.
    -c, --claude    Also remove Claude Code symlinks.
    -h, --help      Show this help message and exit.

EOF
}

while [[ $# -gt 0 ]]; do
    case ${1} in
        -n|--dry-run) DRY_RUN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -c|--claude)  REMOVE_CLAUDE=true; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*"; }

execute() {
    if $VERBOSE; then log_info "Executing: $*"; fi
    if $DRY_RUN; then
        log_info "[Dry-Run] Would run: $*"
    else
        "$@"
    fi
}

# 1. Unstow: remove symlinks managed by GNU Stow
if command -v stow &>/dev/null; then
    log_info "Removing Stow-managed symlinks..."
    local_opts=("--ignore=glow" "--ignore=\.claude" "-t" "$HOME" "home")
    if $VERBOSE; then
        local_opts=("--verbose=2" "${local_opts[@]}")
    fi
    execute stow -D "${local_opts[@]}"
else
    log_warn "GNU Stow not found — skipping stow -D. Remove symlinks manually."
fi

# 2. Remove Tokyo Night theme symlinks
log_info "Removing Tokyo Night theme symlinks..."
theme_links=(
    "$HOME/.config/eza/theme.yml"
    "$HOME/.config/btop/themes/tokyonight_night.theme"
    "$HOME/.config/lazygit/tokyonight_night.yml"
    "$HOME/.config/tmux/tmux.conf.tokyonight"
    "$HOME/.gitconfig.tokyonight"
    "$HOME/.config/alacritty/theme.toml"
)
for link in "${theme_links[@]}"; do
    if [[ -L "$link" ]]; then
        execute rm "$link"
        log_info "Removed: $link"
    fi
done

# 3. Remove copied glow config
log_info "Removing copied glow config..."
if [[ -d "$HOME/.config/glow" ]] && [[ ! -L "$HOME/.config/glow" ]]; then
    execute rm -f "$HOME/.config/glow/glow.yml"
    if [[ -L "$HOME/.config/glow/tokyo_night.json" ]]; then
        execute rm "$HOME/.config/glow/tokyo_night.json"
    fi
    # Remove dir if now empty
    rmdir "$HOME/.config/glow" 2>/dev/null || true
    log_info "Removed glow config"
fi

# 4. Remove Claude Code symlinks (only with -c)
if $REMOVE_CLAUDE; then
    log_info "Removing Claude Code symlinks..."
    if [[ -d "$HOME/.claude" ]]; then
        # Only remove entries that are symlinks pointing into our dotfiles
        for entry in "$HOME/.claude"/*; do
            if [[ -L "$entry" ]] && [[ "$(readlink "$entry")" == *"$DOTFILES_DIR"* ]]; then
                execute rm "$entry"
                log_info "Removed: $entry"
            fi
        done
    fi
fi

log_info "Uninstall complete."
log_info "Local override files (~/.zshrc.local, ~/.vim/user.vim) were preserved."
