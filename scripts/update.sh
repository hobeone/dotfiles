#!/usr/bin/env bash

# Update dotfiles repo and advance all submodules to their latest upstream HEAD.
# Run ./install.sh afterward to re-apply configs with the updated themes/plugins.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DOTFILES_DIR"

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*"; }

# 1. Pull latest dotfiles commits
log_info "Pulling latest dotfiles..."
git pull

# 2. Initialize any new submodules, then advance all to latest upstream HEAD.
# --remote fetches from each submodule's upstream and checks out its default branch HEAD.
# This is intentionally different from 'git submodule update' (no --remote), which
# only syncs to the commit already pinned in the parent repo.
log_info "Updating submodules to latest upstream..."
git submodule update --init --remote

# 3. Show what changed so updated pointers can be committed
if ! git diff --quiet; then
    log_info "Submodule pointers advanced:"
    git diff --submodule=log
    log_warn "Run 'git add -A && git commit -m \"Update submodules\"' to pin the new versions."
fi

log_info "Done. Run ./install.sh to re-apply configs with the updated plugins/themes."
