# Design Spec: psgrep Helper Function

Add a custom `psgrep` function to `home/.zshrc` to search running processes while preserving the header and excluding the search command itself.

## Architecture & Design
- **Tool**: Shell function in `home/.zshrc` under Section 8 (Helper Functions).
- **Command Pipeline**:
  - Run `ps guaxww` to capture detailed process information.
  - Pipe to `awk` to process:
    - Print the first line (NR==1) which contains the header.
    - Match any subsequent lines against the query parameter.
    - Exclude matching lines that contain `awk -v query=` or `psgrep` to prevent self-matching.

## Implementation Details
```zsh
# Search for processes using a pattern, preserving the header and excluding this search process
psgrep() {
  if [[ -z "$1" ]]; then
    echo "Usage: psgrep <pattern>"
    return 1
  fi
  ps guaxww | awk -v query="$1" 'NR==1 || ($0 ~ query && $0 !~ /awk -v query=/ && $0 !~ /psgrep/)'
}
```

## Verification Plan
1. Source `home/.zshrc` or run the function locally.
2. Verify that `psgrep` shows the header.
3. Verify that `psgrep` filters processes by pattern.
4. Verify that `psgrep` does not include itself or `awk` in the results.
