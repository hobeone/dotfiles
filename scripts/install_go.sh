#!/bin/bash
set -euo pipefail

# install_go.sh - Install or upgrade Go to the latest version
# Follows best practices from https://go.dev/doc/install

get_latest_version() {
  curl -fsSL "https://go.dev/VERSION?m=text" | head -1
}

get_installed_version() {
  local go_bin
  if command -v go >/dev/null 2>&1; then
    go_bin="go"
  elif [[ -x "/usr/local/go/bin/go" ]]; then
    go_bin="/usr/local/go/bin/go"
  else
    return 1
  fi
  $go_bin version | awk '{print $3}'
}

version_gt() {
  # Returns 0 if v1 > v2, 1 otherwise
  local v1=$1
  local v2=$2
  [[ "$v1" == "$v2" ]] && return 1
  [[ "$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -n1)" == "$v2" ]]
}

install_go() {
  local version=$1
  local tarball="${version}.linux-amd64.tar.gz"
  local tmp_dir
  tmp_dir=$(mktemp -d)

  echo "Downloading Go ${version}..."
  if ! curl -fsSL "https://go.dev/dl/${tarball}" -o "${tmp_dir}/go.tar.gz"; then
    echo "Error: Failed to download Go ${version}."
    rm -rf "$tmp_dir"
    return 1
  fi

  echo "Removing existing Go installation at /usr/local/go..."
  sudo rm -rf /usr/local/go

  echo "Extracting Go ${version} to /usr/local..."
  sudo tar -C /usr/local -xzf "${tmp_dir}/go.tar.gz"

  rm -rf "$tmp_dir"

  echo "Go ${version} installed successfully."
  /usr/local/go/bin/go version
  
  echo ""
  echo "Ensure /usr/local/go/bin is in your PATH."
  echo "If you're using the dotfiles from this repo, it's already handled in .zshrc."
}

main() {
  local latest
  latest=$(get_latest_version)
  if [[ -z "$latest" ]]; then
    echo "Error: Failed to fetch latest Go version from go.dev."
    exit 1
  fi

  local current
  current=$(get_installed_version || true)

  if [[ -z "$current" ]]; then
    echo "Go is not installed."
    read -p "Do you want to install Go ${latest}? [y/N] " response
    case "$response" in
      [yY][eE][sS]|[yY])
        install_go "$latest"
        ;;
      *)
        echo "Installation cancelled."
        ;;
    esac
  else
    if version_gt "$latest" "$current"; then
      echo "A newer version of Go is available: ${latest} (current: ${current})"
      read -p "Do you want to upgrade? [y/N] " response
      case "$response" in
        [yY][eE][sS]|[yY])
          install_go "$latest"
          ;;
        *)
          echo "Skipping upgrade."
          ;;
      esac
    else
      echo "Go is up to date (${current})."
    fi
  fi
}

main "$@"
