# Design Spec: pskill Helper Function

Add a custom `pskill` function to `home/.zshrc` to send a kill signal to all matching processes while excluding the `pskill` process itself.

## Architecture & Design
- **Tool**: Shell function in `home/.zshrc` under Section 8 (Helper Functions).
- **Argument Parsing**:
  - Check if the first argument starts with a `-` (e.g. `-9` or `-KILL`).
  - If yes, use it as the signal and the second argument as the search pattern.
  - If no, default the signal to `-15` (SIGTERM) and use the first argument as the search pattern.
- **Process ID Retrieval**:
  - Run `ps guaxww`.
  - Pipe to `awk` to:
    - Skip the header (`NR>1`).
    - Match lines against the pattern query.
    - Exclude helper processes like `awk -v query=`, `psgrep`, and `pskill` to prevent self-matching.
    - Print the PID (column 2).
- **Execution**:
  - Collect PIDs into an array.
  - Run `kill <signal> <pids>`.

## Implementation Details
```zsh
# Kill processes matching a pattern, preserving safety by excluding this function/subprocesses
pskill() {
  local sig="-15"
  local pattern=""
  if [[ "$1" =~ ^- ]]; then
    sig="$1"
    pattern="$2"
  else
    pattern="$1"
  fi

  if [[ -z "$pattern" ]]; then
    echo "Usage: pskill [signal] <pattern>"
    return 1
  fi

  local pids
  pids=($(ps guaxww | awk -v query="$pattern" 'NR>1 && $0 ~ query && $0 !~ /awk -v query=/ && $0 !~ /psgrep/ && $0 !~ /pskill/ {print $2}'))

  if [[ ${#pids[@]} -eq 0 ]]; then
    echo "No matching processes found for: $pattern"
    return 0
  fi

  echo "Killing processes: ${pids[*]}"
  kill "$sig" "${pids[@]}"
}
```

## Verification Plan
1. Mock the `kill` command and `ps` command to verify that `pskill` correctly parses arguments and targets only the matched process IDs.
2. Verify that `pskill` filters out itself, `awk`, and `psgrep`.
3. Verify that `pskill` supports custom signals (e.g. `pskill -9 pattern`).
