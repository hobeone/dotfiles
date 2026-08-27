#!/usr/bin/env bash
set -euo pipefail

# install_skills.sh - Install and manage plugins and curated skills for Gemini CLI and Claude Code
#
# Manages:
# - Superpowers plugin (Gemini & Claude)
# - Quaere core skills (quaere-cli)
# - Curated Svelte and Tailwind skills
# - Curated Go review/remediation skills (via install_go_skills.sh)
# - Unified linking into ~/.gemini/skills and ~/.claude/skills

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_info() {
  printf "\033[34m[INFO]\033[0m %s\n" "$*"
}

log_success() {
  printf "\033[32m[SUCCESS]\033[0m %s\n" "$*"
}

log_warn() {
  printf "\033[33m[WARN]\033[0m %s\n" "$*"
}

log_error() {
  printf "\033[31m[ERROR]\033[0m %s\n" "$*" >&2
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install and sync agent skills and plugins for Gemini CLI and Claude Code.

Options:
  -p, --prune    Prune uncurated Go skills and stale links
  -n, --dry-run  Dry run mode (show what would be run)
  -h, --help     Show this help message
EOF
  exit 0
}

PRUNE=true
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--prune)
      PRUNE=true
      shift
      ;;
    --no-prune)
      PRUNE=false
      shift
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
done

execute() {
  if $DRY_RUN; then
    log_info "[Dry-Run] Would run: $*"
  else
    "$@"
  fi
}

# 1. Install Superpowers Plugin
install_superpowers() {
  log_info "Configuring Superpowers plugin..."

  # Gemini CLI / Antigravity plugin
  if command -v agy >/dev/null 2>&1; then
    log_info "Installing / updating Superpowers plugin via agy CLI..."
    execute agy plugin install https://github.com/obra/superpowers >/dev/null 2>&1 || true
  else
    local gemini_superpowers="$HOME/.gemini/config/plugins/superpowers"
    if [[ -d "$gemini_superpowers/.git" ]]; then
      log_info "Updating Gemini Superpowers plugin..."
      execute git -C "$gemini_superpowers" pull --ff-only || log_warn "Failed to update Gemini Superpowers"
    else
      log_info "Cloning Superpowers plugin for Gemini CLI..."
      execute mkdir -p "$(dirname "$gemini_superpowers")"
      execute git clone https://github.com/obra/superpowers.git "$gemini_superpowers"
    fi
  fi

  # Claude Code plugin
  if command -v claude >/dev/null 2>&1; then
    log_info "Ensuring Superpowers plugin is installed in Claude Code..."
    execute claude plugin install superpowers@claude-plugins-official >/dev/null 2>&1 || true
  fi
}

# 2. Install Quaere Skills
install_quaere() {
  if ! command -v npx >/dev/null 2>&1; then
    log_warn "npx not found. Skipping Quaere skills installation."
    return 0
  fi

  log_info "Installing Quaere skills via quaere-cli..."
  execute npx -y quaere-cli install all >/dev/null 2>&1 || true
}

# 3. Install Curated Svelte and Tailwind Skills
install_frontend_skills() {
  if ! command -v npx >/dev/null 2>&1; then
    log_warn "npx not found. Skipping frontend skills installation."
    return 0
  fi

  log_info "Installing Svelte 5 and Tailwind v4 companion skills..."
  execute npx -y skills add sveltejs/ai-tools -g -y --skill svelte-code-writer --skill svelte-core-bestpractices >/dev/null 2>&1 || true
  execute npx -y skills add ejirocodes/agent-skills -g -y --skill svelte5-best-practices >/dev/null 2>&1 || true
  execute npx -y skills add claude-skills/sveltekit-svelte5-tailwind-skill -g -y --skill sveltekit-svelte5-tailwind-skill >/dev/null 2>&1 || true
  execute npx -y skills add giuseppe-trisciuoglio/developer-kit -g -y --skill tailwind-css-patterns >/dev/null 2>&1 || true
}

# 4. Install Curated Go Skills
install_go_skills() {
  local go_script="$DOTFILES_DIR/scripts/install_go_skills.sh"
  if [[ -f "$go_script" ]]; then
    local args=()
    if $PRUNE; then
      args+=("--prune")
    fi
    if $DRY_RUN; then
      log_info "[Dry-Run] Would run: $go_script ${args[*]}"
    else
      bash "$go_script" "${args[@]}"
    fi
  else
    log_warn "install_go_skills.sh not found at $go_script"
  fi
}

# 5. Link Shared External Skills
EXTERNAL_SKILLS=(
  find-skills
  grill-me
  quaere-evidence
  quaere-execution
  quaere-grounding
  quaere-semantic
  svelte-code-writer
  svelte-core-bestpractices
  svelte5-best-practices
  sveltekit-svelte5-tailwind-skill
  tailwind-css-patterns
  design-taste-frontend
  high-end-visual-design
  industrial-brutalist-ui
  minimalist-ui
  redesign-existing-projects
)

sync_external_skills() {
  log_info "Syncing external skills to runtime directories..."

  for base_dir in "$HOME/.gemini/skills" "$HOME/.claude/skills"; do
    execute mkdir -p "$base_dir"
    for skill in "${EXTERNAL_SKILLS[@]}"; do
      local source_dir="$HOME/.agents/skills/$skill"
      local dest_link="$base_dir/$skill"

      if [[ -d "$source_dir" ]]; then
        if [[ ! -e "$dest_link" && ! -L "$dest_link" ]]; then
          execute ln -s "$source_dir" "$dest_link"
        fi
      fi
    done
  done
}

main() {
  log_info "Starting agent skills and plugins installation..."

  install_superpowers
  install_quaere
  install_frontend_skills
  install_go_skills
  sync_external_skills

  log_success "All agent skills and plugins are installed and synced."
}

main "$@"
