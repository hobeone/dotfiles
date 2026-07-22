---
name: work2
description: Trimmed personal fork of development-skills' research-and-implement + review-pipeline-coderabbit, tuned for this workflow (no Codex, no postmortem-elevation phase)
---

# Work2 (experimental)

Trial harness for a personal, trimmed fork of `development-skills`' pipeline as a replacement for `/work`.
The forked skills live under `~/.gemini/skills/` (`research`, `implement`, `research-and-implement`,
`review-pipeline-coderabbit`, `done-check`, `quality-list`, `stage-commit-push`, `todo-check`,
`finding-triage`, `file-pullreq`, `gh-body-check`, `gh-body-conventions`, `coderabbit-review`). Does not modify `/work` — use this to iterate on the new pipeline in isolation.

Flow: research-and-implement → review-pipeline-coderabbit (through the merge gate) →
wait for **your** review → summarize → merge decision → reflect.

## Prerequisites

Checked once per session, before Step 1:

1. `command -v gh-post` (via `run_command`) — optional. If present, body writes route through `gh-post`; if absent, skills fall back gracefully to native `gh` commands (`gh issue create`, `gh pr create`, etc.). Recommend installing with `uv tool install git+https://github.com/ultimatile/gh-post` for extra body validation.
2. CodeRabbit app — assume installed unless Phase B reports no `CodeRabbit` commit status / check run after a reasonable poll.

## Usage

```
/work2 <issue-number | URL | "description">
/work2 --attach
```

## Identifiers

Uses a separate `[work2:ID]` todo prefix from `/work`'s `[work:ID]` — the two commands' active-session
checks are independent, so you can have a `/work` session and a `/work2` trial open at once without collision.

| Input | Identifier |
|-------|------------|
| Issue number | `issue-<N>` |
| Ad-hoc | `adhoc` → `pr-<N>` after PR creation |
| Attach to PR | `issue-<N>` or `pr-<N>` |

---

## Attach Mode (`--attach`)

1. `gh pr view --json number,title,state,body` via `run_command` — no PR → "No PR found. Use `/work2 <issue-number>` to start, or `/pr-create` first."
2. Determine identifier from PR body (`Closes #N` → `issue-N`, else `pr-N`).
3. Infer completed phases from PR state and resume from there.
4. Create remaining tasks only.

---

## Starting New Work

### 1. Check for Active Session

Block on incomplete `[work2:*]` tasks.

### 2. Parse Input

Same as `/work`: number → check `gh issue view`, else `adhoc`; URL → extract issue number; other → `adhoc`.
If `adhoc`, `research-and-implement` will create the tracking issue itself in Phase 1 (research) Step 5 — do not pre-create one.

### 3. Present Scope

```markdown
## Proposed Work Scope (work2 — experimental pipeline)

**Source:** #42 - <title>  (or: ad-hoc — "<description>")
**Identifier:** [work2:issue-42]

### Pipeline
1. /research-and-implement 42   — research + plan approval + implementation + done-check
2. /review-pipeline-coderabbit  — local review gates, PR creation, CodeRabbit fix-loop
3. Wait for your review
4. Summarize + merge decision
5. Reflect
```

Ask via `ask_question`: **Start** / **Modify scope** / **Cancel**.

### 4. Create Tasks

Track work using `[work2:${ID}]` prefix.

---

## Phase A — Research + Implement

Run the `research-and-implement` skill (`~/.gemini/skills/research-and-implement/SKILL.md`, passing `${ARG}`). Note that all child skills referenced by `/work2` live explicitly under `~/.gemini/skills/`.

- Phase 0 (worktree baseline): creates/uses an isolated git worktree automatically instead of switching branches in place.
- Phase 1 (research): uses `~/.gemini/skills/research/SKILL.md`, posting a plan to the issue with an `Inconclusive / Deferred items` section. Its Step 3.5 plan-review gate offers a fresh-context subagent review pass before approval (`ask_question`).
- Phase 2 (implement): uses `~/.gemini/skills/implement/SKILL.md`, executing unit-by-unit and halting on any discovery not covered by the plan's discovery contract. Ends with `~/.gemini/skills/done-check/SKILL.md`.

Do not proceed to Phase B until `research-and-implement` reports Step 5 complete.

## Phase B — Review Pipeline

Before running the review pipeline, perform a mandatory pre-review sync/rebase check via `run_command`:
```bash
git fetch origin main && git merge-tree $(git write-tree) HEAD origin/main
```
If merge conflicts exist or the branch has diverged, rebase or merge `origin/main` cleanly and resolve all conflicts before proceeding.

Run the `review-pipeline-coderabbit` skill (`~/.gemini/skills/review-pipeline-coderabbit/SKILL.md`). Note that CodeRabbit is best-effort (non-blocking brief poll); if it never responds (rate limit, etc.), proceed on whatever review coverage exists.

Stop at the pipeline's own `## ← user merges PR ←` gate.

## Phase C — Wait For Your Review

1. Run `pr-review remote`. It fetches from every source at once — CodeRabbit's inline comments/review summary (when available), and any plain top-level PR comment (the user's own review, or a delegated adversarial-review agent posting under the user's GitHub identity) — filters out anything already addressed, and reports if no unaddressed feedback exists.
2. If it reports no feedback, tell the user the PR is open and ready, and stop turn — do not poll in a loop.
3. If feedback is found, let `pr-review remote` run its decision loop, layering this pipeline's discipline underneath: `done-check` in delta mode after each fix, `stage-commit-push` for every commit, oscillation detection across iterations, and a best-effort CodeRabbit re-poll before the next pass if a push re-triggered it.
4. Proceed to Phase D once `pr-review remote` reports no unaddressed feedback remains.

## Phase D — Summarize and Merge Decision

Before prompting for merge decision, perform a mandatory pre-merge sync/conflict check via `run_command`:
```bash
git fetch origin main && gh pr view <PR#> --json mergeable,mergeStateStatus
```
If the PR reports merge conflicts (`CONFLICTING` or `DIRTY`), halt immediately and resolve conflicts with `origin/main` cleanly before presenting the final merge prompt.

Spawn `summarize-work` subagent via `invoke_subagent` (`TypeName: "self"`).

Present output highlighting key files and PR URL.
Ask via `ask_question`: **Merge now** / **Wait**. Never auto-merge.

## Phase E — Reflect

Rate difficulty/friction, pipeline comparison, and spawn `improve-workflow` subagent via `invoke_subagent` (`TypeName: "self"`).
