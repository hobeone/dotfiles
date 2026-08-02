---
name: work2
description: Trimmed personal fork of development-skills' research-and-implement + review-pipeline-coderabbit with configurable stage model selection (Gemini 3.5 Pro Preview for planning/reviews/complex coding, Gemini 3.6 Flash for straightforward subagent handoffs).
---

# Work2 (experimental)

Trial harness for a personal, trimmed fork of `development-skills`' pipeline as a replacement for `/work`.
The forked skills live under `~/.gemini/skills/` (`research`, `implement`, `research-and-implement`,
`review-pipeline-coderabbit`, `done-check`, `quality-list`, `stage-commit-push`, `todo-check`,
`finding-triage`, `file-pullreq`, `gh-body-check`, `gh-body-conventions`, `coderabbit-review`). Does not modify `/work` — use this to iterate on the new pipeline in isolation.

Flow: research-and-implement → review-pipeline-coderabbit (through the merge gate) →
wait for **your** review → summarize → merge decision → reflect.

## Model Selection & Stage Configuration

`work2` uses a configurable multi-tiered model strategy to balance high-tier reasoning, execution speed, and quota usage.

### Default Model Allocation Matrix

| Pipeline Stage | Default Model Tier | Purpose & Execution Strategy | Override Flag |
| :--- | :--- | :--- | :--- |
| **`PLANNING`** | `pro` (`Gemini 3.5 Pro Preview`) | Phase 1 research, initial requirements creation, hypothesis formation, derivational checks, discovery contract drafting. | `--model-plan=<pro\|flash>` |
| **`REVIEWS`** | `pro` (`Gemini 3.5 Pro Preview`) | Antagonistic self code reviews (Step 3.5 plan review gate, Phase 0.5 pre-commit code review gate, `done-check` audits, Phase C PR review verification). | `--model-review=<pro\|flash>` |
| **`COMPLEX_CODING`** | `pro` (`Gemini 3.5 Pro Preview`) | Implementation of high-complexity changes (see triggers below). | `--model-impl=<auto\|pro\|flash>` |
| **`STRAIGHTFORWARD_CODING`** | `flash` (`Gemini 3.6 Flash`) | Hand off to a `flash` subagent via `invoke_subagent` (`TypeName: "self"`) for straightforward, localized implementation units. | `--model-impl=<auto\|pro\|flash>` |
| **`REPORTING`** | `flash` (`Gemini 3.6 Flash`) | Summary and reflection tasks (`summarize-work` in Phase D, `improve-workflow` in Phase E). | `--model-reporting=<pro\|flash>` |

### Model Tier Override Options

Override options can be passed at invocation time:
- `--model-all=<pro|flash>` — Sets all pipeline stages to the specified tier.
- `--model-plan=<pro|flash>` — Overrides model for initial plan and requirements creation.
- `--model-review=<pro|flash>` — Overrides model for antagonistic self code reviews and verification passes.
- `--model-impl=<auto|pro|flash>` — Controls implementation tier:
  - `auto` (default): Dynamically uses `pro` for complex coding tasks and hands off straightforward tasks to a `flash` subagent.
  - `pro`: Runs all coding tasks on `pro`.
  - `flash`: Hands off all coding tasks to `flash` subagents.
- `--model-reporting=<pro|flash>` — Overrides model tier for summary and reflection subagents.

### Coding Complexity Classification Triggers

When `--model-impl=auto` is active, classify implementation units as **Complex Coding** (`pro`) if **any** of these triggers fire:
- Touches persistence / storage format, DB schemas, or migrations.
- Changes concurrency: mutex scope, goroutine lifecycle, channel protocols, lock ordering.
- Touches crash-recovery or durability invariants.
- Changes a public interface between packages, or the diff spans 3+ packages.
- Is security-sensitive (auth, trust policy, parser/sanitizer logic).
- Is large or high-churn by blast-radius signal.

Otherwise, classify as **Straightforward Coding** (`flash`) and hand off to a Gemini 3.6 Flash subagent (e.g. single-file edits, straightforward bug fixes, mechanical test additions, boilerplate generation, minor refactorings, or linter/doc fixes).

## Prerequisites

Checked once per session, before Step 1:

1. `command -v gh-post` (via `run_command`) — optional. If present, body writes route through `gh-post`; if absent, skills fall back gracefully to native `gh` commands (`gh issue create`, `gh pr create`, etc.). Recommend installing with `uv tool install git+https://github.com/ultimatile/gh-post` for extra body validation.
2. CodeRabbit app — assume installed unless Phase B reports no `CodeRabbit` commit status / check run after a reasonable poll.

## Usage

```
/work2 <issue-number | URL | "description"> [--model-all=<pro|flash>] [--model-plan=<pro|flash>] [--model-review=<pro|flash>] [--model-impl=<auto|pro|flash>] [--model-reporting=<pro|flash>]
/work2 --attach [--model-all=<pro|flash>]
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

### 2. Parse Input & Model Flags

Same as `/work`: number → check `gh issue view`, else `adhoc`; URL → extract issue number; other → `adhoc`.
Parse any `--model-*` flags to set current stage model choices (defaulting to the matrix above).
If `adhoc`, `research-and-implement` will create the tracking issue itself in Phase 1 (research) Step 5 — do not pre-create one.

### 3. Present Scope

```markdown
## Proposed Work Scope (work2 — experimental pipeline)

**Source:** #42 - <title>  (or: ad-hoc — "<description>")
**Identifier:** [work2:issue-42]
**Model Configuration:** Planning: pro | Reviews: pro | Coding: auto (flash subagent for simple, pro for complex) | Reporting: flash

### Pipeline
1. /research-and-implement 42   — research + plan approval + implementation + done-check
2. /review-pipeline-coderabbit  — local review gates, PR creation, CodeRabbit fix-loop
3. Wait for your review
4. Summarize + merge decision
5. Reflect
```

Ask via `ask_question`: **Start** / **Modify model configuration** / **Modify scope** / **Cancel**.

### 4. Create Tasks

Track work using `[work2:${ID}]` prefix.

---

## Phase A — Research + Implement

Run the `research-and-implement` skill (`~/.gemini/skills/research-and-implement/SKILL.md`, passing `${ARG}`). Note that all child skills referenced by `/work2` live explicitly under `~/.gemini/skills/`.

- Phase 0 (worktree baseline): creates/uses an isolated git worktree automatically instead of switching branches in place.
- Phase 1 (research): uses `~/.gemini/skills/research/SKILL.md` running on the configured `PLANNING` model tier (`pro` by default). Posts a plan to the issue/artifact with an `Inconclusive / Deferred items` section. Its Step 3.5 plan-review gate runs on the configured `REVIEWS` model tier (`pro` by default) via a fresh-context subagent before approval (`ask_question`).
- Phase 2 (implement): uses `~/.gemini/skills/implement/SKILL.md`. For each unit:
  - If classified as a straightforward coding task, hand off execution to a `flash` subagent via `invoke_subagent` (`TypeName: "self"`, model tier `flash`).
  - If classified as a complex coding task, execute on the `COMPLEX_CODING` model tier (`pro` by default).
  - Halts on any discovery not covered by the plan's discovery contract.
  - Ends with `done-check` audit running on the configured `REVIEWS` model tier (`pro` by default).

Do not proceed to Phase B until `research-and-implement` reports Step 5 complete.

## Phase B — Review Pipeline

Before running the review pipeline, perform a mandatory pre-review sync/rebase check via `run_command`:
```bash
git fetch origin main && git merge-tree $(git write-tree) HEAD origin/main
```
If merge conflicts exist or the branch has diverged, rebase or merge `origin/main` cleanly and resolve all conflicts before proceeding.

Run the `review-pipeline-coderabbit` skill (`~/.gemini/skills/review-pipeline-coderabbit/SKILL.md`). Pre-commit local code reviews and subagent passes run on the configured `REVIEWS` model tier (`pro` by default). Note that CodeRabbit is best-effort (non-blocking brief poll); if it never responds (rate limit, etc.), proceed on whatever review coverage exists.

Stop at the pipeline's own `## ← user merges PR ←` gate.

## Phase C — Wait For Your Review

1. Run `pr-review remote`. It fetches from every source at once — CodeRabbit's inline comments/review summary (when available), and any plain top-level PR comment (the user's own review, or a delegated adversarial-review agent posting under the user's GitHub identity) — filters out anything already addressed, and reports if no unaddressed feedback exists.
2. If it reports no feedback, tell the user the PR is open and ready, and stop turn — do not poll in a loop.
3. If feedback is found, let `pr-review remote` run its decision loop, layering this pipeline's discipline underneath: `done-check` in delta mode after each fix (running on configured `REVIEWS` model tier: `pro` by default), `stage-commit-push` for every commit, oscillation detection across iterations, and a best-effort CodeRabbit re-poll before the next pass if a push re-triggered it.
4. Proceed to Phase D once `pr-review remote` reports no unaddressed feedback remains.

## Phase D — Summarize and Merge Decision

Before prompting for merge decision, perform a mandatory pre-merge sync/conflict check via `run_command`:
```bash
git fetch origin main && gh pr view <PR#> --json mergeable,mergeStateStatus
```
If the PR reports merge conflicts (`CONFLICTING` or `DIRTY`), halt immediately and resolve conflicts with `origin/main` cleanly before presenting the final merge prompt.

Spawn `summarize-work` subagent via `invoke_subagent` (`TypeName: "self"`, using configured `REPORTING` model tier: `flash` by default).

Present output highlighting key files and PR URL.
Ask via `ask_question`: **Merge now** / **Wait**. Never auto-merge.

## Phase E — Reflect

Rate difficulty/friction, pipeline comparison, and spawn `improve-workflow` subagent via `invoke_subagent` (`TypeName: "self"`, using configured `REPORTING` model tier: `flash` by default).

