---
name: pr-shepherd
description: Use when monitoring authored GitHub pull requests in the background for reviewer feedback, CI status, or merge conflicts, and addressing review comments by implementing fixes or pushing back on invalid findings
---

# PR Shepherd (agy adapter)

The shepherd method is harness-neutral and shared with Claude Code. It lives in
`method.md` next to this file. Read `method.md` in full with `view_file`, then
follow it, applying the bindings below wherever it writes a `⟨verb⟩`.

## Harness mapping

| Verb | Binding |
|---|---|
| `⟨run⟩` | `run_command` |
| `⟨read-file⟩` | `view_file` |
| `⟨ask-user⟩` | `ask_question` |
| `⟨skill-dir⟩` | `~/.gemini/skills/pr-shepherd` |
| `⟨state-dir⟩` | `~/.gemini/jetski/scratch/pr_shepherd` |
| `⟨worktree-root⟩` | `/tmp` |
| `⟨schedule-recurring⟩` | The `schedule` tool: `CronExpression="*/5 * * * *"`, `IsDaemon=False`, `Prompt=` the cycle prompt from `method.md`. |
| `⟨cancel-schedule⟩` | `manage_task(Action="kill", TaskId=...)` |

## Harness notes

- `IsDaemon` must be `False`. `True` suspends the session between cycles, and
  `*/30 * * * *` or any other interval is the same mistake in a different
  field.
