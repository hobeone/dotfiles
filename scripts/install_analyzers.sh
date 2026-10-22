#!/usr/bin/env bash
set -euo pipefail

# install_analyzers.sh - Install the static analyzers deep-pr-review's
# run-analyzers.sh knows how to use. Every tool stays optional for the
# review (a missing one is reported as NOT run); this just fills the gaps.
#
# Usage: install_analyzers.sh [-n|--dry-run] [--check] [TOOL...]
#   TOOL defaults to all of: shellcheck trufflehog gitleaks semgrep
#   golangci-lint ruff actionlint hadolint osv-scanner
#   --check     Report what is installed and exit (1 if anything is missing).
#   -n          Print what would be installed without doing it.
#
# Sources: Homebrew on macOS. On Linux, `uv tool install` (or pipx) for the
# Python tools and the latest GitHub release binary for the rest, placed in
# $ANALYZER_INSTALL_DIR (default ~/.local/bin). Release downloads go through
# `gh release download`, so gh must be installed and authenticated.
# The shellcheck binary itself comes from the distro package list (packages/*.txt).

ALL_TOOLS=(shellcheck trufflehog gitleaks semgrep golangci-lint ruff actionlint hadolint osv-scanner)
BIN_DIR="${ANALYZER_INSTALL_DIR:-$HOME/.local/bin}"
DRY_RUN=false
CHECK_ONLY=false

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

usage() { sed -n '8,12p' "$0" | sed 's/^# \{0,1\}//'; }

# release_spec TOOL ARCH — prints "OWNER/REPO ASSET_GLOB" for tools shipped as
# GitHub release assets on Linux. Each project names its architectures
# differently, hence the per-tool mapping.
release_spec() {
    local tool=$1 arch=$2 a x g
    case "$arch" in
        x86_64|amd64)  a=amd64 x=x86_64 g=x64 ;;
        aarch64|arm64) a=arm64 x=arm64  g=arm64 ;;
        *) return 1 ;;
    esac
    case "$tool" in
        trufflehog)    echo "trufflesecurity/trufflehog trufflehog_*_linux_${a}.tar.gz" ;;
        gitleaks)      echo "gitleaks/gitleaks gitleaks_*_linux_${g}.tar.gz" ;;
        golangci-lint) echo "golangci/golangci-lint golangci-lint-*-linux-${a}.tar.gz" ;;
        actionlint)    echo "rhysd/actionlint actionlint_*_linux_${a}.tar.gz" ;;
        osv-scanner)   echo "google/osv-scanner osv-scanner_linux_${a}" ;;
        hadolint)      echo "hadolint/hadolint hadolint-linux-${x}" ;;
        *) return 1 ;;
    esac
}

# install_release TOOL — download the latest release asset and put the TOOL
# binary in BIN_DIR. Tarballs are searched for the binary, since some nest it
# in a versioned directory (golangci-lint).
install_release() {
    local tool=$1 spec repo glob tmp found
    if ! spec=$(release_spec "$tool" "$(uname -m)"); then
        log_error "$tool: no release asset for architecture $(uname -m)"
        return 1
    fi
    read -r repo glob <<<"$spec"
    if $DRY_RUN; then
        log_info "[Dry-Run] Would download $repo release asset '$glob' into $BIN_DIR"
        return 0
    fi
    command -v gh >/dev/null || { log_error "$tool: gh is required for release downloads"; return 1; }
    tmp=$(mktemp -d)
    local rc=0
    _fetch_release "$tool" "$repo" "$glob" "$tmp" || rc=1
    rm -rf "$tmp"
    return "$rc"
}

_fetch_release() {
    local tool=$1 repo=$2 glob=$3 tmp=$4 found
    if ! gh release download -R "$repo" -p "$glob" -D "$tmp" >/dev/null; then
        log_error "$tool: gh release download from $repo failed"
        return 1
    fi
    found=$(find "$tmp" -maxdepth 1 -type f | head -1)
    if [[ $found == *.tar.gz ]]; then
        tar -xzf "$found" -C "$tmp" || { log_error "$tool: could not unpack $(basename "$found")"; return 1; }
        found=$(find "$tmp" -type f -name "$tool" | head -1)
    fi
    if [[ -z $found ]]; then
        log_error "$tool: release asset from $repo did not contain a '$tool' binary"
        return 1
    fi
    mkdir -p "$BIN_DIR" && install -m 0755 "$found" "$BIN_DIR/$tool"
}

# install_python TOOL — semgrep and ruff are Python packages of the same name.
install_python() {
    local tool=$1 runner
    if command -v uv >/dev/null; then
        runner=(uv tool install "$tool")
    elif command -v pipx >/dev/null; then
        runner=(pipx install "$tool")
    else
        log_error "$tool: needs uv or pipx (neither is on PATH)"
        return 1
    fi
    if $DRY_RUN; then
        log_info "[Dry-Run] Would run: ${runner[*]}"
        return 0
    fi
    "${runner[@]}"
}

install_one() {
    local tool=$1
    if [[ "$(uname -s)" == Darwin ]]; then
        command -v brew >/dev/null || { log_error "$tool: Homebrew is required on macOS"; return 1; }
        if $DRY_RUN; then
            log_info "[Dry-Run] Would run: brew install $tool"
            return 0
        fi
        brew install "$tool"
        return
    fi
    case "$tool" in
        shellcheck)
            log_error "shellcheck: install it with your package manager (it is in packages/*.txt; ./install.sh does this)"
            return 1 ;;
        semgrep|ruff) install_python "$tool" ;;
        *) install_release "$tool" ;;
    esac
}

# installed_ok TOOL — the installer exiting 0 is not proof: the binary must now
# be on PATH or in BIN_DIR.
installed_ok() {
    command -v "$1" >/dev/null || [[ -x $BIN_DIR/$1 ]] && return 0
    log_error "$1: the installer reported success but no '$1' binary was found"
    return 1
}

main() {
    local tools=() tool
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--dry-run) DRY_RUN=true ;;
            --check) CHECK_ONLY=true ;;
            -h|--help) usage; exit 0 ;;
            -*) log_error "Unknown option: $1"; usage >&2; exit 1 ;;
            *) tools+=("$1") ;;
        esac
        shift
    done
    [[ ${#tools[@]} -gt 0 ]] || tools=("${ALL_TOOLS[@]}")
    for tool in "${tools[@]}"; do
        [[ " ${ALL_TOOLS[*]} " == *" $tool "* ]] || { log_error "Unknown analyzer: $tool (known: ${ALL_TOOLS[*]})"; exit 1; }
    done

    local present=() installed=() failed=()
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null; then
            present+=("$tool")
        elif $CHECK_ONLY; then
            failed+=("$tool")
        elif install_one "$tool" && { $DRY_RUN || installed_ok "$tool"; }; then
            installed+=("$tool")
        else
            failed+=("$tool")
        fi
    done

    local verb=Installed missing=Failed
    $DRY_RUN && verb="Would install"
    $CHECK_ONLY && missing=Missing
    [[ ${#present[@]} -eq 0 ]] || log_info "Already present: ${present[*]}"
    [[ ${#installed[@]} -eq 0 ]] || log_info "$verb: ${installed[*]}"
    if [[ ${#installed[@]} -gt 0 && ":$PATH:" != *":$BIN_DIR:"* ]]; then
        log_warn "$BIN_DIR is not on PATH; run-analyzers.sh will not find tools installed there"
    fi
    if [[ ${#failed[@]} -gt 0 ]]; then
        log_warn "$missing: ${failed[*]}"
        exit 1
    fi
}

main "$@"
