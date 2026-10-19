---
name: pr-shepherd
description: Use when monitoring authored GitHub pull requests for reviewer feedback, CI status, or merge conflicts, and addressing review comments by implementing fixes or pushing back on invalid findings. Polls on a 5-minute loop; never merges.
---

# PR Shepherd (Claude Code adapter)

The shepherd method is harness-neutral and shared with agy. It lives in
`method.md` next to this file. Read `method.md` in full with the Read tool, then
follow it, applying the bindings below wherever it writes a `⟨verb⟩`.

## Harness mapping

| Verb | Binding |
|---|---|
| `⟨run⟩` | `Bash` |
| `⟨read-file⟩` | `Read` |
| `⟨ask-user⟩` | `AskUserQuestion` |
| `⟨skill-dir⟩` | `~/.claude/skills/pr-shepherd` |
| `⟨state-dir⟩` | `~/.claude/pr-shepherd` |
| `⟨worktree-root⟩` | `<repo>/.claude/worktrees` — the one location `EnterWorktree` will enter, and the one the repo's own worktree rule names. |
| `⟨schedule-recurring⟩` | The `loop` skill via the `Skill` tool, args `5m <cycle prompt from method.md>`. The loop lives only while this Claude session stays open. |
| `⟨cancel-schedule⟩` | Stop the loop: `CronList` to find the job `/loop` created, then `CronDelete` (both are deferred — load with `ToolSearch` first). |

## Harness notes

- Never merge or close a PR, whatever the verdict says. The shepherd reports
  `APPROVED (READY FOR MERGE)`; merging needs the user's explicit approval.
- Inside a worktree under `.claude/worktrees/`, edit with `Edit`/`Write`, not
  `Bash` heredocs or `sed` — the isolation guard refuses what it cannot prove
  stays inside the worktree.
- State the model chosen before any subagent dispatch (the user's CLAUDE.md
  requires it). A cycle needs no subagent: `poll-feedback.sh` is the poll.
- Do not use `ScheduleWakeup` or poll a background agent; completion
  notifications arrive on their own.
- A repo whose `ci.yml` is manual-dispatch only shows few or no checks in
  `statusCheckRollup`; that is the expected state, not a stuck PR.
