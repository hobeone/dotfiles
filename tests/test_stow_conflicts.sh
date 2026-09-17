#!/usr/bin/env bash
# Test suite for find_stow_conflicts in install.sh
set -uo pipefail

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DOTFILES_ROOT" || exit 1

# Source install.sh (main is guarded, so it only loads definitions)
# shellcheck source=install.sh
source "$DOTFILES_ROOT/install.sh"

fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

# Setup isolated sandbox
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

MOCK_REPO="$TMPDIR/repo"
MOCK_HOME_DIR="$MOCK_REPO/home"
MOCK_TARGET="$TMPDIR/target_home"

mkdir -p "$MOCK_HOME_DIR/.gemini/skills/implement"
echo "implement skill" > "$MOCK_HOME_DIR/.gemini/skills/implement/SKILL.md"

mkdir -p "$MOCK_HOME_DIR/.gemini/skills/normal"
echo "normal skill" > "$MOCK_HOME_DIR/.gemini/skills/normal/SKILL.md"

echo "repo bashrc" > "$MOCK_HOME_DIR/.bashrc"
echo "repo conflicting symlink target" > "$MOCK_HOME_DIR/conflicting_symlink.txt"
echo "repo broken symlink target" > "$MOCK_HOME_DIR/broken_symlink.txt"

# Create target home state:
# 1. Absolute symlink to repo entry (e.g. .gemini/skills/implement)
mkdir -p "$MOCK_TARGET/.gemini/skills"
ln -s "$MOCK_HOME_DIR/.gemini/skills/implement" "$MOCK_TARGET/.gemini/skills/implement"

# 2. Relative symlink to repo entry (e.g. .gemini/skills/normal)
# From $MOCK_TARGET/.gemini/skills, relative to $MOCK_HOME_DIR/.gemini/skills/normal
ln -s "../../../repo/home/.gemini/skills/normal" "$MOCK_TARGET/.gemini/skills/normal"

# 3. Regular non-symlink conflicting file (.bashrc)
echo "user custom bashrc" > "$MOCK_TARGET/.bashrc"

# 4. Conflicting symlink pointing to an external destination
echo "external file" > "$TMPDIR/external.txt"
ln -s "$TMPDIR/external.txt" "$MOCK_TARGET/conflicting_symlink.txt"

# 5. Broken symlink
ln -s "$TMPDIR/nonexistent.txt" "$MOCK_TARGET/broken_symlink.txt"

# Point HOME_DIR to our mock home
HOME_DIR="$MOCK_HOME_DIR"
DRY_RUN=false
VERBOSE=false

# Run find_stow_conflicts
find_stow_conflicts "$MOCK_HOME_DIR" "$MOCK_TARGET"

# Verification 1: Absolute symlink to repo entry must be removed (Stow will recreate as relative)
if [[ -L "$MOCK_TARGET/.gemini/skills/implement" ]]; then
    err "Absolute symlink to repo (.gemini/skills/implement) was not removed"
fi

# Verification 2: Valid relative symlink must be preserved
if [[ ! -L "$MOCK_TARGET/.gemini/skills/normal" ]]; then
    err "Valid relative symlink (.gemini/skills/normal) was unexpectedly modified or removed"
else
    target_link=$(readlink "$MOCK_TARGET/.gemini/skills/normal")
    if [[ "$target_link" != "../../../repo/home/.gemini/skills/normal" ]]; then
        err "Valid relative symlink destination was altered: $target_link"
    fi
fi

# Verification 3: Regular non-symlink conflicting file must be backed up to .bak
if [[ -f "$MOCK_TARGET/.bashrc" && ! -f "$MOCK_TARGET/.bashrc.bak" ]]; then
    err "Conflicting regular file (.bashrc) was not backed up to .bashrc.bak"
elif [[ ! -f "$MOCK_TARGET/.bashrc.bak" ]]; then
    err ".bashrc.bak does not exist"
elif [[ "$(< "$MOCK_TARGET/.bashrc.bak")" != "user custom bashrc" ]]; then
    err ".bashrc.bak content mismatch"
fi

# Verification 4: Conflicting symlink pointing elsewhere must be backed up to .bak
if [[ -L "$MOCK_TARGET/conflicting_symlink.txt" ]]; then
    err "Conflicting external symlink was not backed up and cleared"
fi
if [[ ! -L "$MOCK_TARGET/conflicting_symlink.txt.bak" ]]; then
    err "Conflicting external symlink was not backed up to conflicting_symlink.txt.bak"
fi

# Verification 5: Broken symlink must be backed up or removed
if [[ -L "$MOCK_TARGET/broken_symlink.txt" ]]; then
    err "Broken symlink was not backed up or removed"
fi
if [[ ! -L "$MOCK_TARGET/broken_symlink.txt.bak" ]]; then
    err "Broken symlink was not backed up to broken_symlink.txt.bak"
fi

if ((fail == 0)); then
    echo "PASS"
    exit 0
else
    echo "FAIL"
    exit 1
fi
