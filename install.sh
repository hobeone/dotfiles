#!/usr/bin/env bash

# Modernized install.sh for dotfiles
# Works on Debian/Ubuntu, Arch Linux, Fedora, and macOS

set -euo pipefail

DRY_RUN=false
VERBOSE=false

# Flags
while getopts "nv" opt; do
    case ${opt} in
        n) DRY_RUN=true ;;
        v) VERBOSE=true ;;
        \?) echo "Usage: $0 [-n] [-v]" >&2; exit 1 ;;
    esac
done

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$DOTFILES_DIR/home"

log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $*"
}

log_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $*"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
}

# 1. Detect OS and Package Manager
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macOS"
        PKG_MGR="brew"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        if [[ "$ID" == "ubuntu" ]] || [[ "$ID" == "debian" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
            PKG_MGR="apt"
        elif [[ "$ID" == "arch" ]] || [[ "$ID_LIKE" == *"arch"* ]]; then
            PKG_MGR="pacman"
        elif [[ "$ID" == "fedora" ]] || [[ "$ID_LIKE" == *"rhel"* ]]; then
            PKG_MGR="dnf"
        else
            PKG_MGR="unknown"
        fi
    else
        OS="Unknown"
        PKG_MGR="unknown"
    fi
}

# 2. Install Packages
install_packages() {
    log_info "Detecting OS and package manager..."
    detect_os
    log_info "OS: $OS, Package Manager: $PKG_MGR"

    # Baseline packages
    local apt_packages=(eza zoxide git-delta tmux watch xclip gh btop lazygit)
    local pacman_packages=(eza zoxide delta tmux watch xclip github-cli btop lazygit) # Arch package names might differ slightly
    local dnf_packages=(eza zoxide git-delta tmux watch xclip gh btop lazygit)
    local brew_packages=(eza zoxide git-delta tmux watch xclip gh btop lazygit)

    if $DRY_RUN; then
        log_info "[Dry-Run] Would install packages for $PKG_MGR"
        return 0
    fi

    case "$PKG_MGR" in
        apt)
            log_info "Installing packages via apt..."
            sudo apt update
            sudo apt install -y "${apt_packages[@]}"
            ;;
        pacman)
            log_info "Installing packages via pacman..."
            sudo pacman -Sy --needed "${pacman_packages[@]}"
            ;;
        dnf)
            log_info "Installing packages via dnf..."
            sudo dnf install -y "${dnf_packages[@]}"
            ;;
        brew)
            log_info "Installing packages via Homebrew..."
            brew install "${brew_packages[@]}"
            ;;
        *)
            log_warn "Unknown package manager. Please install baseline packages manually: ${apt_packages[*]}"
            ;;
    esac
}

# 3. Safe Linking
link_item() {
    local src="$1"
    local dst="$2"

    if [[ -e "$dst" ]] || [[ -L "$dst" ]]; then
        if [[ -L "$dst" ]] && [[ "$(readlink -f "$dst")" == "$src" ]]; then
            if $VERBOSE; then
                log_info "Link already correct: $dst -> $src"
            fi
            return 0
        fi

        log_warn "Destination exists: $dst"
        if $DRY_RUN; then
            log_info "[Dry-Run] Would prompt to overwrite $dst and proceed with linking."
        else
            read -p "Overwrite? [y/N] " response
            case "$response" in
                [yY][eE][sS]|[yY])
                    rm -rf "$dst"
                    ;;
                *)
                    log_info "Skipping $dst"
                    return 0
                    ;;
            esac
        fi
    fi

    if $DRY_RUN; then
        log_info "[Dry-Run] Would link $dst -> $src"
    else
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
        log_info "Linked $dst -> $src"
    fi
}

# 4. Initialize Submodules
init_submodules() {
    log_info "Initializing submodules..."
    if $DRY_RUN; then
        log_info "[Dry-Run] Would run: git submodule update --init --recursive"
    else
        git submodule update --init --recursive
    fi
}

# 5. Ensure Local Override Files Exist
ensure_local_files() {
    log_info "Ensuring local override files exist..."
    
    local zsh_local="$HOME/.zshrc.local"
    local vim_user="$HOME/.vim/user.vim"

    if $DRY_RUN; then
        [[ ! -f "$zsh_local" ]] && log_info "[Dry-Run] Would create empty $zsh_local"
        [[ ! -f "$vim_user" ]] && log_info "[Dry-Run] Would create empty $vim_user"
    else
        if [[ ! -f "$zsh_local" ]]; then
            touch "$zsh_local"
            log_info "Created empty $zsh_local"
        fi
        
        if [[ ! -f "$vim_user" ]]; then
            touch "$vim_user"
            log_info "Created empty $vim_user"
        fi
    fi
}

main() {
    # 1. Initialize Submodules
    init_submodules

    # 2. Install Packages
    install_packages

    # 3. Create Links
    log_info "Creating symlinks..."

    # Iterate over items in home/
    for item in "$HOME_DIR"/*; do
        basename="$(basename "$item")"

        # Skip config and ssh directories for safe merging
        if [[ "$basename" == "config" ]] || [[ "$basename" == "ssh" ]]; then
            continue
        fi

        link_item "$item" "$HOME/.$basename"
    done

    # Safe merge .config
    if [[ -d "$HOME_DIR/config" ]]; then
        for item in "$HOME_DIR/config"/*; do
            basename="$(basename "$item")"
            link_item "$item" "$HOME/.config/$basename"
        done
    fi

    # Safe merge .ssh
    if [[ -d "$HOME_DIR/ssh" ]]; then
        for item in "$HOME_DIR/ssh"/*; do
            basename="$(basename "$item")"
            link_item "$item" "$HOME/.ssh/$basename"
        done
    fi

    # 4. Ensure Local Files Exist
    ensure_local_files

    log_info "Dotfiles installation complete!"
}

main "$@"
