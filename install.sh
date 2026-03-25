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

execute() {
    if $DRY_RUN; then
        log_info "[Dry-Run] Would run: $*"
    else
        "$@"
    fi
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

    execute mkdir -p "$(dirname "$dst")"
    execute ln -s "$src" "$dst"
    log_info "Linked $dst -> $src"
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
            execute mkdir -p "$HOME/.local/share/fonts"
            execute curl -fLo /tmp/JetBrainsMono.zip "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
            execute unzip -o /tmp/JetBrainsMono.zip -d "$HOME/.local/share/fonts/"
            execute rm /tmp/JetBrainsMono.zip
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

    # 1. eza
    local eza_dest="$HOME/.config/eza/theme.yml"
    execute mkdir -p "$(dirname "$eza_dest")"
    execute ln -sf "$vendor_dir/extras/eza/tokyonight_night.yml" "$eza_dest"
    log_info "Symlinked eza theme: $eza_dest"

    # 2. btop
    local btop_dest="$HOME/.config/btop/themes/tokyonight_night.theme"
    local btop_conf="$HOME/.config/btop/btop.conf"
    execute mkdir -p "$(dirname "$btop_dest")"
    execute ln -sf "$vendor_dir/extras/btop/tokyonight_night.theme" "$btop_dest"
    log_info "Symlinked btop theme: $btop_dest"
    
    if [[ -f "$btop_conf" ]]; then
        execute sed -i 's/^color_theme = .*/color_theme = "tokyonight_night.theme"/' "$btop_conf"
        log_info "Updated btop.conf to use tokyonight_night.theme"
    fi

    # 3. lazygit
    local lazygit_dest="$HOME/.config/lazygit/config.yml"
    local lazygit_theme_dest="$HOME/.config/lazygit/tokyonight_night.yml"
    if [[ ! -f "$lazygit_theme_dest" ]]; then
        execute mkdir -p "$(dirname "$lazygit_dest")"
        execute ln -sf "$vendor_dir/extras/lazygit/tokyonight_night.yml" "$lazygit_theme_dest"
        log_info "Symlinked lazygit theme: $lazygit_theme_dest"
    else
        log_warn "lazygit config already exists. Skipping theme symlink."
    fi
    
    # 4. tmux
    local tmux_dest="$HOME/.tmux.conf.tokyonight"
    execute ln -sf "$vendor_dir/extras/tmux/tokyonight_night.tmux" "$tmux_dest"
    log_info "Symlinked tmux theme: $tmux_dest"
    
    # 5. delta
    local delta_dest="$HOME/.gitconfig.tokyonight"
    execute ln -sf "$vendor_dir/extras/delta/tokyonight_night.gitconfig" "$delta_dest"
    log_info "Symlinked delta theme: $delta_dest"

    # 6. alacritty
    local alacritty_dest="$HOME/.config/alacritty/theme.toml"
    execute mkdir -p "$(dirname "$alacritty_dest")"
    execute ln -sf "$vendor_dir/extras/alacritty/tokyonight_night.toml" "$alacritty_dest"
    log_info "Symlinked alacritty theme: $alacritty_dest"
}

install_glow() {
    log_info "Installing glow config (copying to avoid git diffs)..."
    local glow_src_dir="$HOME_DIR/config/glow"
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
            if [[ "$basename" == "glow" ]]; then
                continue
            fi
            link_item "$item" "$HOME/.config/$basename"
        done
    fi

    # Handle glow separately (copied instead of linked)
    install_glow

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
