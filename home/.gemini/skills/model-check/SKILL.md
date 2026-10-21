---
name: model-check
description: Use before relying on a pinned agy model id, or when a configured model may have been retired. Checks the id against `agy models` and, when it is missing, recommends an available alternative for the user to approve instead of substituting silently.
---

# Model Check (agy adapter)

The method is harness-neutral and shared with Claude Code. It lives in
`method.md` next to this file. Read `method.md` in full with `view_file`, then
follow it, applying the bindings below wherever it writes a `⟨verb⟩`.

## Harness mapping

| Verb | Binding |
|---|---|
| `⟨run⟩` | `run_command` |
| `⟨skill-dir⟩` | `~/.gemini/skills/model-check` |
| `⟨ask-user⟩` | `ask_question` |

## Harness notes

- `invoke_subagent` tier aliases (`flash`, `flash_lite`, `pro`) are not agy
  model ids. They are never passed to `resolve-model.sh`.
- On exit 3, put the recommendation in the `ask_question` options. Do not
  switch workers or models while waiting for the answer.
