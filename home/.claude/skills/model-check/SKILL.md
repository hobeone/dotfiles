---
name: model-check
description: Use before relying on a pinned agy model id, or when a configured model may have been retired. Checks the id against `agy models` and, when it is missing, recommends an available alternative for the user to approve instead of substituting silently.
---

# Model Check (Claude Code adapter)

The method is harness-neutral and shared with agy. It lives in `method.md` next
to this file. Read `method.md` in full with the Read tool, then follow it,
applying the bindings below wherever it writes a `⟨verb⟩`.

## Harness mapping

| Verb | Binding |
|---|---|
| `⟨run⟩` | `Bash` |
| `⟨skill-dir⟩` | `~/.claude/skills/model-check` |
| `⟨ask-user⟩` | `AskUserQuestion` |

## Harness notes

- Scripts that need the check call `resolve-model.sh` directly (for example
  `agy-adversarial-review/scripts/agy-review.sh`); this skill is for the
  agent doing it by hand.
- On exit 3, put the recommendation in the `AskUserQuestion` options. Do not
  continue with the recommended model while waiting.
