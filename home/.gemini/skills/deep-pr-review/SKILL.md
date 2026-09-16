---
name: deep-pr-review
description: Use when asked to deeply review a pull request, run a CodeRabbit-style review, review a diff before merge, or produce severity-ranked PR findings. Runs eligibility checks and an architectural approach gate followed by a 15-angle recall-biased review, posting findings as a GitHub review.
---

# Deep PR Review (agy adapter)

The review method is harness-neutral and shared with Claude Code. It lives in
`method.md` next to this file. Read `method.md` in full with `view_file`, then
follow it, applying the bindings below wherever it writes a `⟨verb⟩`.

## Harness mapping

| Verb | Binding |
|---|---|
| `⟨dispatch-parallel⟩` | One `run_subagent` call carrying every entry (entries in one call launch concurrently), `TypeName: "self"`, `Model` per routing below. |
| `⟨read-at-sha⟩` | `run_command`: `git show <sha>:<path>` |
| `⟨run⟩` | `run_command` |
| `⟨ask-user⟩` | `ask_question` |
| `⟨skill-dir⟩` | `~/.gemini/skills/deep-pr-review` |
| `⟨run-dir⟩` | Once per review: `run_command` `mktemp -d "${TMPDIR:-/tmp}/deep-pr-review.XXXXXX"`; reuse the printed path. |
| `⟨user-instructions⟩` | `~/.gemini/GEMINI.md` and `~/.claude/CLAUDE.md` |

## Model routing

| Role | Model | Why |
|---|---|---|
| Architecture Gate, Finders A–I and K–O, Verifiers | `flash` | Gemini 3.8 Flash on high reasoning outperforms 3.1 Pro while executing significantly faster and cheaper |
| Finder J (conventions) | `flash_lite` | quote-the-rule / quote-the-line matching |
| Gap Sweep | main context | needs the deduplicated list |

## Verified call shape

Probed against this install — `agy agents` lists no custom types, and
`TypeName: "self"` is what works:

```json
{
  "Subagents": [
    { "TypeName": "self", "Role": "Angle A — line-by-line diff scan",
      "Model": "flash", "Prompt": "<self-contained angle prompt>" },
    { "TypeName": "self", "Role": "Angle F — reuse",
      "Model": "flash", "Prompt": "<self-contained angle prompt>" }
  ]
}
```

Read the tool's live schema before calling — field names above are what this
install accepted, not a contract. Each subagent returns its own conversation ID;
if one hangs, the subagent-management tool can `list` and `kill` it without
losing the others.
