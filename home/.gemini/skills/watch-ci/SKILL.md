---
name: watch-ci
description: Monitor CI in background and notify when complete
---

# Watch CI

Monitor CI status for a PR in the background.

## Usage

```
/watch-ci [PR_NUMBER]
```

## Instructions

1. Retrieve PR number (default to current branch's PR) and repository name.
2. Wait for checks to be initialized:
   ```bash
   for i in {1..6}; do
     count=$(gh pr checks <PR_NUMBER> 2>/dev/null | wc -l)
     [ "$count" -gt 0 ] && break
     sleep 5
   done
   ```
3. Start the background check task:
   ```bash
   gh pr checks <PR_NUMBER> --watch --interval 10
   ```
   Run this in the background. The Antigravity CLI will automatically log when this completes.
4. Once completed, notify the user and trigger `/pr-review remote`.
