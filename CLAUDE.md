# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Modular and modernized dotfiles for Zsh, Vim, and system-level configurations. Supports Debian/Ubuntu, Arch Linux, Fedora, and macOS. Uses GNU Stow for symlinking, custom shell scripts for automation, and git submodules for third-party plugin management.
## Commands

```bash
./install.sh           # Full sync: pull, install/update packages, sync dotfiles
./install.sh -c        # Full sync including Claude Code configurations
./install.sh -n        # Dry-run mode
./install.sh -v        # Verbose output
./scripts/update.sh    # Synchronize all submodules and update Oh My Zsh
git submodule update --init --recursive  # Update submodules
```

## Architecture

### Symlinking Strategy

The project uses **GNU Stow**. The `home/` directory in the repository mirrors the user's `$HOME`.
- Files in `home/` (e.g., `home/.zshrc`) are symlinked to `~/.zshrc`.
- **Exceptions:** The `glow` configuration is copied rather than linked to allow for absolute path rewriting.

### Configuration Components

- **Zsh**: Oh My Zsh with Powerlevel10k theme. Plugins: `git`, `golang`, `tmux`, etc.
- **Vim**: `vim-plug` for plugin management. Tokyo Night theme.
- **Git**: `git-delta` for syntax-highlighted diffs.
- **Claude Code**: `home/.claude/` contains global config, agents, commands, hooks, and skills.

### Claude Code Components

- **Hooks** (`home/.claude/hooks/`): Shell scripts for Claude Code lifecycle events.
- **Skills** (`home/.claude/skills/`): Model-invoked domain expertise.
- **Commands** (`home/.claude/commands/`): User-invoked workflows (e.g., `/pr-review`).
- **Statusline** (`home/.claude/statusline-command.sh`): Single-line custom statusline for Claude Code.

## Development Conventions

- **Moving Files**: Use `git mv` instead of `mv` to preserve history.
- **Adding Packages**: Identify package name for managers, add to `packages/*.txt`, run `./install.sh`.
- **Adding Configs**: Place in `home/` mirroring the `~` path, run `./install.sh`.
