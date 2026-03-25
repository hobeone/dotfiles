#!/usr/bin/env bash

# Modernized install.sh for dotfiles
# Works on Debian/Ubuntu, Arch Linux, Fedora, and macOS

set -euo pipefail

DRY_RUN=false
VERBOSE=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    -n, --dry-run   Dry-run mode. Don't make any changes.
    -v, --verbose   Verbose output. Show commands being executed.
    -h, --help      Show this help message and exit.

EOF
}

# Flags
while [[ $# -gt 0 ]]; do
    case ${1} in
        -n|--dry-run) DRY_RUN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "Unknown option: $1" >&2; usage; exit 1 ;;
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

execute() {
    if $VERBOSE; then
        log_info "Executing: $*"
    fi

    if $DRY_RUN; then
        log_info "[Dry-Run] Would run: $*"
    else
        "$@"
    fi
}

# 1. Setup Git Hooks
setup_git_hooks() {
    log_info "Setting up git hooks..."
    if ! command -v git >/dev/null 2>&1; then
        log_warn "git is not installed. Skipping git hook setup."
        return 0
    fi

    # Set the hooksPath to the tracked .githooks directory
    execute git config core.hooksPath .githooks
}

# 2. Detect OS and Package Manager
detect_os() {
    log_info "Detecting OS and package manager..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macOS"
        PKG_MGR="brew"
    elif [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
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
    log_info "OS: $OS, Package Manager: $PKG_MGR"
}

# 2. Install Packages
install_packages() {
    if [[ "$PKG_MGR" == "unknown" ]]; then
        log_warn "Unknown package manager. Please install baseline packages manually."
        return 0
    fi

    local pkg_file="$DOTFILES_DIR/packages/$PKG_MGR.txt"
    if [[ ! -f "$pkg_file" ]]; then
        log_warn "Package list not found: $pkg_file"
        return 0
    fi

    local packages=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        packages+=("$line")
    done < "$pkg_file"

    if [[ ${#packages[@]} -eq 0 ]]; then
        log_info "No packages to install for $PKG_MGR."
        return 0
    fi

    case "$PKG_MGR" in
        apt)
            log_info "Installing packages via apt..."
            execute sudo apt update
            execute sudo apt install -y "${packages[@]}"
            ;;
        pacman)
            log_info "Installing packages via pacman..."
            execute sudo pacman -Sy --needed "${packages[@]}"
            ;;
        dnf)
            log_info "Installing packages via dnf..."
            execute sudo dnf install -y "${packages[@]}"
            ;;
        brew)
            log_info "Installing packages via Homebrew..."
            execute brew install "${packages[@]}"
            ;;
    esac
}

# 4. Initialize Submodules
init_submodules() {
    log_info "Initializing submodules..."

    if ! command -v git >/dev/null 2>&1; then
        log_warn "git is not installed. Skipping submodule initialization."
        return 0
    fi

    # More robust check: check if any submodules are uninitialized
    if [[ -z "$(git submodule status --recursive | grep '^-')" ]]; then
        log_info "Submodules already initialized."
        return 0
    fi

    execute git submodule update --init --recursive
}


# 5. Ensure Local Override Files Exist
ensure_local_files() {
    log_info "Ensuring local override files exist..."
    
    local zsh_local="$HOME/.zshrc.local"
    local vim_user="$HOME/.vim/user.vim"

    if [[ ! -f "$zsh_local" ]]; then
        execute touch "$zsh_local"
        log_info "Created empty $zsh_local"
    fi
    
    if [[ ! -f "$vim_user" ]]; then
        execute touch "$vim_user"
        log_info "Created empty $vim_user"
    fi
}

# 6. Install JetBrains Mono Font
install_fonts() {
    log_info "Checking for JetBrains Mono Nerd Font..."

    if [[ "$PKG_MGR" == "brew" ]]; then
        if ! brew list --cask font-jetbrains-mono-nerd-font &>/dev/null; then
            log_info "Installing JetBrains Mono Nerd Font via Homebrew..."
            execute brew install --cask font-jetbrains-mono-nerd-font
        else
            log_info "JetBrains Mono Nerd Font already installed via Homebrew."
        fi
    else
        # Linux (Debian, Arch, Fedora)
        local font_installed=false
        if command -v fc-list &>/dev/null && fc-list | grep -qi "JetBrains.*Nerd"; then
            font_installed=true
        elif [[ -f "$HOME/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf" ]] || \
             [[ -f "$HOME/.local/share/fonts/JetBrains Mono Regular Nerd Font Complete.ttf" ]]; then
            font_installed=true
        fi

        if ! $font_installed; then
            if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
                log_warn "curl or unzip not found. Skipping JetBrains Mono Nerd Font installation."
                return 0
            fi

            log_info "Installing JetBrains Mono Nerd Font..."
            local tmp_dir
            tmp_dir=$(mktemp -d)
            trap 'rm -rf "$tmp_dir"' EXIT

            execute mkdir -p "$HOME/.local/share/fonts"
            execute curl -fsSL -o "$tmp_dir/JetBrainsMono.zip" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
            execute unzip -o "$tmp_dir/JetBrainsMono.zip" -d "$HOME/.local/share/fonts/"
            
            if command -v fc-cache &>/dev/null; then
                execute fc-cache -fv
            else
                log_warn "fc-cache not found. Please install fontconfig or reboot to refresh font cache."
            fi
        else
            log_info "JetBrains Mono Nerd Font already installed."
        fi
    fi
}

# To add the tokyonight.nvim submodule manually:
# git submodule add https://github.com/folke/tokyonight.nvim vendor/tokyonight-themes
install_tokyonight_themes() {
    log_info "Installing Tokyo Night themes (night variant)..."

    local vendor_dir="$DOTFILES_DIR/vendor/tokyonight-themes"

    if [[ ! -d "$vendor_dir/extras" ]]; then
        log_warn "Tokyo Night themes not found (submodule not initialized?)"
        return 0
    fi

    # Define themes: "source_relative_to_vendor_dir|destination_path"
    local themes=(
        "extras/eza/tokyonight_night.yml|$HOME/.config/eza/theme.yml"
        "extras/btop/tokyonight_night.theme|$HOME/.config/btop/themes/tokyonight_night.theme"
        "extras/lazygit/tokyonight_night.yml|$HOME/.config/lazygit/tokyonight_night.yml"
        "extras/tmux/tokyonight_night.tmux|$HOME/.config/tmux/tmux.conf.tokyonight"
        "extras/delta/tokyonight_night.gitconfig|$HOME/.gitconfig.tokyonight"
        "extras/alacritty/tokyonight_night.toml|$HOME/.config/alacritty/theme.toml"
    )

    for entry in "${themes[@]}"; do
        local src="${entry%%|*}"
        local dst="${entry##*|}"
        

        execute mkdir -p "$(dirname "$dst")"
        execute ln -sf "$vendor_dir/$src" "$dst"
        log_info "Symlinked theme: $dst"
    done
    
    # Update btop config specifically
    local btop_conf="$HOME/.config/btop/btop.conf"
    if [[ -f "$btop_conf" ]]; then
        # Use execute for sed as well
        if [[ "$OSTYPE" == "darwin"* ]]; then
             execute sed -i '' 's/^color_theme = .*/color_theme = "tokyonight_night.theme"/' "$btop_conf"
        else
             execute sed -i 's/^color_theme = .*/color_theme = "tokyonight_night.theme"/' "$btop_conf"
        fi
        log_info "Updated btop.conf to use tokyonight_night.theme"
    fi
}

install_glow() {
    log_info "Installing glow config (copying to avoid git diffs)..."
    local glow_src_dir="$HOME_DIR/.config/glow"
    local glow_dst_dir="$HOME/.config/glow"

    # If the destination is a symlink, remove it to make way for a directory
    if [[ -L "$glow_dst_dir" ]]; then
        execute rm "$glow_dst_dir"
    fi

    execute mkdir -p "$glow_dst_dir"

    # Copy glow.yml
    execute cp "$glow_src_dir/glow.yml" "$glow_dst_dir/glow.yml"

    # Link tokyo_night.json (since it's not being modified, linking is fine)
    execute ln -sf "$glow_src_dir/tokyo_night.json" "$glow_dst_dir/tokyo_night.json"

    # Rewrite style path in the COPIED file
    if [[ "$OS" == "macOS" ]]; then
        execute sed -i '' "s|style: \"~/.config/glow/tokyo_night.json\"|style: \"$HOME/.config/glow/tokyo_night.json\"|g" "$glow_dst_dir/glow.yml"
    else
        execute sed -i "s|style: \"~/.config/glow/tokyo_night.json\"|style: \"$HOME/.config/glow/tokyo_night.json\"|g" "$glow_dst_dir/glow.yml"
    fi
    log_info "Copied and updated glow.yml in $glow_dst_dir"
}

main() {
    log_info "Installing dotfiles from $DOTFILES_DIR to $HOME"
    
    # 1. Setup Git Hooks
    setup_git_hooks

    # 2. Detect OS and Package Manager
    detect_os

    # 3. Initialize Submodules
    init_submodules

    # 4. Install Packages
    install_packages

    # 5. Install Fonts
    install_fonts

    # 6. Install Tokyo Night Themes
    install_tokyonight_themes

    # 7. Create Links via GNU Stow
    log_info "Creating symlinks with GNU Stow..."

    if ! command -v stow >/dev/null 2>&1; then
        log_error "GNU Stow is not installed. Please install it to proceed."
        exit 1
    fi

    # Stow everything in home/, ignoring glow (handled separately)
    execute stow --ignore="glow" -t "$HOME" home

    # Handle glow separately (copied instead of linked)
    install_glow

    # 8. Ensure Local Files Exist
    ensure_local_files

    log_info "Dotfiles installation complete!"
}
main "$@"
