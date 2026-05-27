#!/bin/bash
set -euo pipefail

# Read JSON payload from stdin
DATA=$(cat)

#read -r cwd agent_state < <(echo "$DATA" | jq -r '.cwd, .agent_state')
read -r cwd agent_state < <(echo "$DATA" | jq -r '[.cwd, .agent_state] | @tsv')

TITLE="[AGY] Agent:$agent_state CWD:$cwd"

echo "$TITLE"
