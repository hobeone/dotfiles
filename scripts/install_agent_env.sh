#!/usr/bin/env bash
# Deprecated: use scripts/install_skills.sh instead
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/install_skills.sh" "$@"
