# Gemini Context: Dotfiles Project

This project is a modular and modernized dotfiles repository designed to manage system configurations across Debian/Ubuntu, Arch Linux, Fedora, and macOS. It uses a combination of GNU Stow for symlinking, custom shell scripts for automation, and git submodules for third-party plugin management.

## Project Overview

*   **Purpose:** Centralized management of shell (Zsh), editor (Vim), and system-level configurations.
*   **Target OS:** Linux (apt, pacman, dnf) and macOS (Homebrew).
*   **Key Technologies:** Bash, Zsh (Oh My Zsh, Powerlevel10k), Vim (vim-plug, ALE, YouCompleteMe), GNU Stow, git-delta.

## Core Components & Architecture

### 1. Installation & Management
*   **`install.sh`**: The main entry point. It handles git hook setup, OS detection, package installation, submodule initialization, font installation, and symlinking via GNU Stow.
    *   **Usage:** `./install.sh [-v] [-n]` (Verbose / Dry-run).
*   **`.githooks/`**: Tracked directory for git hooks. The `pre-commit` hook automatically sorts and deduplicates package lists in `packages/`.
*   **`scripts/`**: Contains specialized helper scripts:
    *   `scripts/update.sh`: Synchronizes all submodules and updates Oh My Zsh.
    *   `scripts/install_go.sh`: Standalone script for installing/upgrading Go.
    *   `scripts/gnome_settings.sh`: Configures GNOME desktop preferences via `gsettings`.
    *   `scripts/install_udev.sh`: Sets up udev rules for hardware-specific actions (e.g., KVM switches).
*   **`packages/`**: OS-specific package lists (`apt.txt`, `brew.txt`, etc.).

### 2. Shell Configuration (Zsh)
*   **Framework:** Oh My Zsh with the Powerlevel10k theme.
*   **Plugins:** `git`, `golang`, `tmux`, `zsh-autosuggestions`, `zsh-syntax-highlighting`, and more.
*   **Local Overrides:** `~/.zshrc.local` is automatically created for machine-specific environment variables or aliases.

### 3. Editor Configuration (Vim)
*   **Plugin Manager:** `vim-plug`.
*   **Key Features:** Tokyo Night theme, ALE (Asynchronous Linting Engine) with `gopls` and `golangci-lint`, and Tagbar/NERDTree for navigation.
*   **Local Overrides:** `~/.vim/user.vim` for local Vim configurations.

### 4. Git Configuration
*   **Visuals:** Uses `git-delta` for side-by-side, syntax-highlighted diffs.
*   **Workflow:** Global `.gitignore_global` and various aliases (`st`, `co`, `br`, `lg`).

## Development & Usage Conventions

### Symlinking Strategy
The project uses **GNU Stow**. The `home/` directory in the repository mirrors the user's `$HOME`.
*   Files in `home/` (e.g., `home/.zshrc`) are symlinked to `~/.zshrc`.
*   **Exceptions:** The `glow` configuration is copied rather than linked to allow for absolute path rewriting without affecting the git state.

### File Operations
*   **Moving Files:** Any file or directory moves within the repository **MUST** be performed using `git mv` instead of the standard `mv` command to ensure git history is preserved and tracking is maintained.

### Adding New Packages
To add a dependency:
1.  Identify the package name for each supported manager.
2.  Add it to the corresponding file in `packages/`.
3.  Run `./install.sh`.

### Adding New Configs
1.  Place the config file in the appropriate path under `home/`.
2.  Ensure any absolute paths are handled (either via `~` or special handling in `install.sh`).
3.  Run `./install.sh` to update symlinks.

## Troubleshooting & Maintenance
*   **Dry Run:** Always use `./install.sh -n` to preview changes before applying them.
*   **Submodules:** If plugins are missing, run `./scripts/update.sh` or `git submodule update --init --recursive`.
*   **Fonts:** JetBrains Mono Nerd Font is required for the Powerlevel10k prompt to render correctly. It is installed automatically by `install.sh`.
