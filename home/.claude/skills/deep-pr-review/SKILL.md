---
name: deep-pr-review
description: Use only when the user explicitly asks for deep-pr-review or a CodeRabbit-style deep review of a PR, branch, or diff. Recall-biased 15-angle review with eligibility checks and an architecture gate, posted as a GitHub review. Not for routine /pr-review or /code-review requests.
---

# Deep PR Review (Claude Code adapter)

The review method is harness-neutral and shared with agy. It lives in
`method.md` next to this file. Read `method.md` in full with the Read tool,
then follow it, applying the bindings below wherever it writes a `⟨verb⟩`.

## Harness mapping

| Verb | Binding |
|---|---|
| `⟨dispatch-parallel⟩` | Multiple `Agent` tool calls in a **single message**, one per entry, `subagent_type: "general-purpose"`, `model` per routing below. Do not use the `Workflow` tool — it requires explicit user opt-in. |
| `⟨read-at-sha⟩` | `Bash`: `git show <sha>:<path>` |
| `⟨run⟩` | `Bash` |
| `⟨ask-user⟩` | `AskUserQuestion` |
| `⟨skill-dir⟩` | `~/.claude/skills/deep-pr-review` |
| `⟨run-dir⟩` | Once per review: `Bash` `mktemp -d "${TMPDIR:-/tmp}/deep-pr-review.XXXXXX"`; reuse the printed path. |
| `⟨user-instructions⟩` | `~/.claude/CLAUDE.md` |

## Model routing

| Role | Model | Why |
|---|---|---|
| Architecture Gate | `opus` | One judgment that can halt the whole review; ambiguous design reasoning |
| Finders A–I and K–O | `sonnet` | Standard code reading and cross-file tracing |
| Finder J (conventions) | `haiku` | Quote-the-rule / quote-the-line matching |
| Verifiers | `sonnet` | Must construct refutations from code; cheaper tiers wave candidates through |
| Gap Sweep | main context | Needs the deduplicated list |

Before each dispatch, state the model chosen per role and why in one line
(the user's CLAUDE.md requires it).

## Harness notes

- Keep one verifier per candidate even when there are many; if one message
  cannot carry every `Agent` call, send consecutive messages of parallel calls —
  that is still a fan-out, not a sequential run.
- Subagents return their result as the `Agent` tool result; do not poll or
  schedule wakeups for them.
