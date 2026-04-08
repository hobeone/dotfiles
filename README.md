# dotfiles

Personal dotfiles for Zsh, Vim, Tmux, and system-level configuration.
Supports Debian/Ubuntu, Arch Linux, Fedora, and macOS.

## Setup

```bash
./install.sh           # Full install: packages, fonts, symlinks
./install.sh -d        # Also install desktop/compositor packages
./install.sh -c        # Also install Claude Code configuration
./install.sh -n        # Dry-run (preview changes without applying)
./install.sh -v        # Verbose output
```

## Architecture

Uses **GNU Stow** to symlink everything in `home/` to `$HOME`.
Git submodules manage third-party plugins (Oh My Zsh, Powerlevel10k, etc.).

| Path | Purpose |
|------|---------|
| `home/.zshrc` | Zsh config (Oh My Zsh + Powerlevel10k) |
| `home/.vimrc` | Vim config (vim-plug, ALE, Tokyo Night) |
| `home/.config/tmux/` | Tmux config |
| `home/.gitconfig` | Git config with delta diffs |
| `home/.claude/` | Claude Code hooks, skills, commands |
| `packages/` | Per-OS package lists (`apt.txt`, `brew.txt`, etc.) |
| `packages/apt-desktop.txt` | Optional desktop/compositor packages (`-d` flag) |
| `scripts/` | Helper scripts (Go install, keyboard setup, etc.) |
| `vendor/` | Vendored themes (Tokyo Night) |

## Local Overrides

- `~/.zshrc.local` — machine-specific shell config (auto-created, not tracked)
- `~/.vim/user.vim` — machine-specific Vim config (auto-created, not tracked)
