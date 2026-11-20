#!/bin/bash
# SessionStart: point this project's Claude memory folder at the shared
# store and refresh the indexes, so a new checkout or a new machine is wired
# up without a manual step. Never blocks the session: a failure is reported
# as one line of session context and the hook still exits 0.
set -uo pipefail

input="$(cat)"
command -v agent-memory >/dev/null 2>&1 || exit 0
[[ -d "${AGENT_MEMORY_HOME:-${HOME}/.agents/memory}" ]] || exit 0

cwd=""
if command -v jq >/dev/null 2>&1; then
  cwd="$(jq -r '.cwd // empty' <<<"${input}" 2>/dev/null)"
fi
[[ -n "${cwd}" && -d "${cwd}" ]] || cwd="${PWD}"

if ! out="$(agent-memory link "${cwd}" 2>&1 && agent-memory index 2>&1)"; then
  printf 'agent-memory: shared memory is not wired up for this project: %s\n' "${out}"
fi
exit 0
