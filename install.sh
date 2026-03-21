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

log_info "Installing dotfiles from $DOTFILES_DIR to $HOME"

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
    local apt_packages=(eza zoxide git-delta tmux watch xclip gh btop lazygit unzip curl)
    local pacman_packages=(eza zoxide delta tmux watch xclip github-cli btop lazygit unzip curl) # Arch package names might differ slightly
    local dnf_packages=(eza zoxide git-delta tmux watch xclip gh btop lazygit unzip curl)
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

    # Check if all submodules are already populated
    if [[ -f "$HOME_DIR/ohmyzsh/oh-my-zsh.sh" ]] && \
       [[ -f "$HOME_DIR/zsh_custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
       [[ -f "$HOME_DIR/zsh_custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && \
       [[ -f "$HOME_DIR/zsh_custom/themes/powerlevel10k/powerlevel10k.zsh-theme" ]] && \
       [[ -f "$DOTFILES_DIR/vendor/tokyonight-themes/extras/btop/tokyonight_night.theme" ]]; then
        log_info "Submodules already initialized."
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        log_warn "git is not installed. Skipping submodule initialization."
        return 0
    fi

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
        if [[ ! -f "$zsh_local" ]]; then
            log_info "[Dry-Run] Would create empty $zsh_local"
        fi
        if [[ ! -f "$vim_user" ]]; then
            log_info "[Dry-Run] Would create empty $vim_user"
        fi
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

# 6. Install JetBrains Mono Font
install_fonts() {
    log_info "Checking for JetBrains Mono Nerd Font..."

    if [[ "$PKG_MGR" == "brew" ]]; then
        if $DRY_RUN; then
            log_info "[Dry-Run] Would install JetBrains Mono Nerd Font via Homebrew Cask"
        else
            if ! brew list --cask font-jetbrains-mono-nerd-font &>/dev/null; then
                log_info "Installing JetBrains Mono Nerd Font via Homebrew..."
                brew install --cask font-jetbrains-mono-nerd-font
            else
                log_info "JetBrains Mono Nerd Font already installed via Homebrew."
            fi
        fi
    else
        # Linux (Debian, Arch, Fedora)
        # Check both fc-list (if available) and the direct file existence
        local font_installed=false
        if command -v fc-list &>/dev/null && fc-list | grep -qi "JetBrains.*Nerd"; then
            font_installed=true
        elif [[ -f "$HOME/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf" ]] || \
             [[ -f "$HOME/.local/share/fonts/JetBrains Mono Regular Nerd Font Complete.ttf" ]]; then # Match old names too
            font_installed=true
        fi

        if ! $font_installed; then
            log_info "Installing JetBrains Mono Nerd Font..."
            if $DRY_RUN; then
                log_info "[Dry-Run] Would download and install JetBrains Mono Nerd Font to ~/.local/share/fonts"
            else
                mkdir -p "$HOME/.local/share/fonts"
                curl -fLo /tmp/JetBrainsMono.zip "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
                unzip -o /tmp/JetBrainsMono.zip -d "$HOME/.local/share/fonts/"
                rm /tmp/JetBrainsMono.zip
                if command -v fc-cache &>/dev/null; then
                    fc-cache -fv
                else
                    log_warn "fc-cache not found. Please install fontconfig or reboot to refresh font cache."
                fi
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

    # 1. eza
    local eza_dest="$HOME/.config/eza/theme.yml"
    if $DRY_RUN; then
        log_info "[Dry-Run] Would symlink eza theme: $eza_dest"
    else
        mkdir -p "$(dirname "$eza_dest")"
        ln -sf "$vendor_dir/extras/eza/tokyonight_night.yml" "$eza_dest"
        log_info "Symlinked eza theme: $eza_dest"
    fi

    # 2. btop
    local btop_dest="$HOME/.config/btop/themes/tokyonight_night.theme"
    local btop_conf="$HOME/.config/btop/btop.conf"
    if $DRY_RUN; then
        log_info "[Dry-Run] Would symlink btop theme: $btop_dest"
        if [[ -f "$btop_conf" ]]; then
            log_info "[Dry-Run] Would update btop.conf to use tokyonight_night.theme"
        fi
    else
        mkdir -p "$(dirname "$btop_dest")"
        ln -sf "$vendor_dir/extras/btop/tokyonight_night.theme" "$btop_dest"
        log_info "Symlinked btop theme: $btop_dest"
        
        if [[ -f "$btop_conf" ]]; then
            sed -i 's/^color_theme = .*/color_theme = "tokyonight_night.theme"/' "$btop_conf"
            log_info "Updated btop.conf to use tokyonight_night.theme"
        fi
    fi

    # 3. lazygit
    local lazygit_dest="$HOME/.config/lazygit/config.yml"
    if [[ ! -f "$lazygit_dest" ]]; then
        if $DRY_RUN; then
            log_info "[Dry-Run] Would symlink lazygit theme: $lazygit_dest"
        else
            mkdir -p "$(dirname "$lazygit_dest")"
            ln -sf "$vendor_dir/extras/lazygit/tokyonight_night.yml" "$lazygit_dest"
            log_info "Symlinked lazygit theme: $lazygit_dest"
        fi
    else
        log_warn "lazygit config already exists. Skipping theme symlink."
    fi
    
    # 4. tmux
    local tmux_dest="$HOME/.tmux.conf.tokyonight"
    if $DRY_RUN; then
        log_info "[Dry-Run] Would symlink tmux theme: $tmux_dest"
    else
        ln -sf "$vendor_dir/extras/tmux/tokyonight_night.tmux" "$tmux_dest"
        log_info "Symlinked tmux theme: $tmux_dest"
    fi
    
    # 5. delta
    local delta_dest="$HOME/.gitconfig.tokyonight"
    if $DRY_RUN; then
        log_info "[Dry-Run] Would symlink delta theme: $delta_dest"
    else
        ln -sf "$vendor_dir/extras/delta/tokyonight_night.gitconfig" "$delta_dest"
        log_info "Symlinked delta theme: $delta_dest"
    fi

    # 6. alacritty
    local alacritty_dest="$HOME/.config/alacritty/theme.toml"
    if $DRY_RUN; then
        log_info "[Dry-Run] Would symlink alacritty theme: $alacritty_dest"
    else
        mkdir -p "$(dirname "$alacritty_dest")"
        ln -sf "$vendor_dir/extras/alacritty/tokyonight_night.toml" "$alacritty_dest"
        log_info "Symlinked alacritty theme: $alacritty_dest"
    fi
}

main() {
    # 1. Initialize Submodules
    init_submodules

    # 2. Install Packages
    install_packages

    # 2.5 Install Fonts
    install_fonts

    # 2.6 Install Tokyo Night Themes
    install_tokyonight_themes

    # 3. Create Links
    log_info "Creating symlinks..."

    # Iterate over items in home/
    for item in "$HOME_DIR"/*; do
        basename="$(basename "$item")"

        # Skip config, ssh, and bin directories for safe merging
        if [[ "$basename" == "config" ]] || [[ "$basename" == "ssh" ]] || [[ "$basename" == "bin" ]]; then
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

    # Safe merge ~/bin
    if [[ -d "$HOME_DIR/bin" ]]; then
        for item in "$HOME_DIR/bin"/*; do
            basename="$(basename "$item")"
            link_item "$item" "$HOME/bin/$basename"
        done
    fi

    # 4. Ensure Local Files Exist
    ensure_local_files

    log_info "Dotfiles installation complete!"
}

main "$@"
