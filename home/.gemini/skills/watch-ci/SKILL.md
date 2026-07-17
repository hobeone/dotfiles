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
3. Schedule a recurring check using the `schedule` tool:
   - Use `schedule` with a cron expression (e.g., `CronExpression="*/2 * * * *"` for every 2 minutes) to run a check command.
   - The scheduled command should check the status of the PR checks using `gh pr checks <PR_NUMBER>`.
   - Set `IsDaemon=false` since this task is part of finishing the current workflow.
   - Provide a prompt like: "Check CI status for PR <PR_NUMBER>".
4. When the schedule triggers:
   - Check if all checks have completed.
   - If completed:
     - Cancel the schedule using `manage_task` with the task ID.
     - Notify the user of the result.
     - Trigger `/pr-review remote` if checks passed, or report failures.
     - End the turn.
   - If not completed:
     - Do nothing and wait for the next schedule trigger.

