#!/usr/bin/env bash
set -euo pipefail

# install_go_skills.sh - Install curated Go companion skills from samber/cc-skills-golang
#
# Installs only the 10 essential review & remediation skills required by deep-pr-review,
# avoiding context window bloat from the remaining 36 framework/library skills.

CURATED_SKILLS=(
  golang-safety
  golang-concurrency
  golang-error-handling
  golang-modernize
  golang-context
  golang-structs-interfaces
  golang-testing
  golang-performance
  golang-security
  golang-lint
)

UNCURATED_SKILLS=(
  golang-benchmark
  golang-cli
  golang-code-style
  golang-continuous-integration
  golang-database
  golang-data-structures
  golang-dependency-injection
  golang-dependency-management
  golang-design-patterns
  golang-documentation
  golang-google-wire
  golang-gopls
  golang-graphql
  golang-grpc
  golang-how-to
  golang-naming
  golang-observability
  golang-pkg-go-dev
  golang-popular-libraries
  golang-project-layout
  golang-refactoring
  golang-samber-do
  golang-samber-hot
  golang-samber-lo
  golang-samber-mo
  golang-samber-oops
  golang-samber-ro
  golang-samber-slog
  golang-spf13-cobra
  golang-spf13-viper
  golang-stay-updated
  golang-stretchr-testify
  golang-swagger
  golang-troubleshooting
  golang-uber-dig
  golang-uber-fx
)

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

Install curated Go companion skills from samber/cc-skills-golang.

Options:
  -p, --prune    Remove uncurated samber/cc-skills-golang skills to save context tokens
  -h, --help     Show this help message
EOF
  exit 0
}

PRUNE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--prune)
      PRUNE=true
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

if ! command -v npx >/dev/null 2>&1; then
  log_error "npx is required to install skills. Please install Node.js and npm first."
  exit 1
fi

prune_skill() {
  local skill="$1"
  # Protect dotfiles-tracked skills
  if [[ "$skill" == "golang-project-standards" ]]; then
    return 0
  fi

  for base_dir in "$HOME/.gemini/skills" "$HOME/.claude/skills"; do
    local link_path="$base_dir/$skill"
    if [[ -L "$link_path" || -d "$link_path" ]]; then
      rm -rf "$link_path"
    fi
    local embedded_path="$base_dir/.agents/skills/$skill"
    if [[ -d "$embedded_path" ]]; then
      rm -rf "$embedded_path"
    fi
  done

  local user_agent_path="$HOME/.agents/skills/$skill"
  if [[ -d "$user_agent_path" ]]; then
    rm -rf "$user_agent_path"
  fi
}

if [[ "$PRUNE" == "true" ]]; then
  log_info "Pruning 36 uncurated Go skills to prevent context window bloat..."
  for skill in "${UNCURATED_SKILLS[@]}"; do
    prune_skill "$skill"
  done
  log_success "Pruned uncurated Go skills from agent directories."
fi

SKILL_ARGS=()
for skill in "${CURATED_SKILLS[@]}"; do
  SKILL_ARGS+=(--skill "$skill")
done

log_info "Installing ${#CURATED_SKILLS[@]} curated Go review and remediation skills via npx skills..."
npx -y skills add samber/cc-skills-golang -g -y "${SKILL_ARGS[@]}" >/dev/null 2>&1 || true

# Ensure curated skills are properly linked in ~/.gemini/skills if created in ~/.agents/skills
for skill in "${CURATED_SKILLS[@]}"; do
  source_dir="$HOME/.agents/skills/$skill"
  dest_link="$HOME/.gemini/skills/$skill"
  if [[ -d "$source_dir" && ! -e "$dest_link" ]]; then
    ln -s "$source_dir" "$dest_link"
  fi
done

log_success "Curated Go skills ready."
log_info "Active curated skills: ${CURATED_SKILLS[*]}"
