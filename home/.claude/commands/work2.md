---
argument-hint: <issue-number | URL | "description" | --attach>
description: Research + implement + review pipeline for gonzbd work
---

# Work2

Uses skills under `~/.claude/skills/`: `research`, `implement`, `research-and-implement`,
`review-pipeline-coderabbit`, `done-check`, `quality-list`, `stage-commit-push`, `todo-check`,
`finding-triage`, `file-pullreq`, `gh-body-check`, `gh-body-conventions`, `coderabbit-review`.

Flow: research-and-implement → review-pipeline-coderabbit (through the merge gate) →
wait for **your** review (bolted on — not part of the pipeline itself) → summarize → merge decision → reflect.

## Notes

- The plan-review gate (`research` Step 3.5) uses a fresh-context subagent review pass. Claude's own
  `/code-review` (Phase 0.5 of the review pipeline) plus the user's own reads (plan approval, PR review) are
  the only other checks.
- Findings are not written back to any external skills repo.
- **`quality-list` has a `lang-go.md` addendum** — `done-check` and `todo-check` have Go-specific
  realizations (mutex-scope, unchecked type assertions, `goimports`/`go vet`/`golangci-lint`,
  exported-symbol-as-public-API, interface satisfaction on signature changes).

## Review & Verification Model

The cost-aware default in `~/.claude/CLAUDE.md` picks the cheapest capable model for
*implementation*. Review and verification are a separate decision: a cheap implementation
paired with a strong review pass is usually the better spend than running everything on one
tier. **When the change is complex enough to warrant it, run this pipeline's review and
verification steps on Opus even if implementation ran on a cheaper model.**

The review/verification steps this applies to:

- Phase A — the Step 3.5 plan-review subagent, and the `/done-check` pass.
- Phase B — Claude's own `/code-review` (Phase 0.5 of the review pipeline).
- Phase C — the `receiving-code-review` verification of each fix.

Escalate review + verification to Opus when **any** of these is true (state which trigger
fired, per the global policy's "be verbose about the choice"):

- Touches persistence / on-disk format, or a DB schema / `goose` migration.
- Changes concurrency: mutex scope, goroutine lifecycle, channel protocols, lock ordering.
- Touches crash-recovery or durability invariants.
- Changes a public interface between packages, or the diff spans 3+ packages.
- Is security-sensitive (auth, trust/CIDR policy, NNTP or NZB input parsing).
- Is large or high-churn by the `get_risk` blast-radius signal.

Otherwise keep review at the implementation tier. When in doubt, escalate the *review* — it
is read-only and the downside of a missed defect here is higher than the token cost. This is
a knob on the review subagents, not on the human-in-the-loop gates (plan approval, PR review,
merge) — those are unchanged.

## Prerequisites

Checked once per session, before Step 1:

1. `command -v gh-post` — if absent, stop and tell the user: `uv tool install git+https://github.com/ultimatile/gh-post`
   (Python 3.11+, `gh` on PATH required). Every PR/issue body write in this pipeline routes through it.
2. CodeRabbit app — no reliable CLI check exists; assume installed unless Phase B (below) reports no
   `CodeRabbit` commit status / check run after a reasonable poll, in which case surface the dashboard/app-install
   check called out in `coderabbit-review`'s no-terminal-signal case.

## Usage

```
/work2 <issue-number | URL | "description">
/work2 --attach
```

## Identifiers

Uses a separate `[work2:ID]` todo prefix from `/work`'s `[work:ID]` — the two commands' active-session
checks are independent, so you can have a `/work` session and a `/work2` run open at once without collision.

| Input | Identifier |
|-------|------------|
| Issue number | `issue-<N>` |
| Ad-hoc | `adhoc` → `pr-<N>` after PR creation |
| Attach to PR | `issue-<N>` or `pr-<N>` |

---

## Attach Mode (`--attach`)

1. `gh pr view --json number,title,state,body` — no PR → "No PR found. Use `/work2 <issue-number>` to start,
   or `/pr-create` first."
2. Determine identifier from PR body (`Closes #N` → `issue-N`, else `pr-N`).
3. Infer completed phases from PR state (has a CodeRabbit review landed? has done-check evidence been
   posted? is there a `## Plan-vs-actual delta` section already?) and resume from there.
4. Create remaining todos only.

---

## Starting New Work

### 1. Check for Active Session

Block on incomplete `[work2:*]` todos (not `[work:*]` — the two are independent).

### 2. Parse Input

Same as `/work`: number → check `gh issue view`, else `adhoc`; URL → extract issue number; other → `adhoc`.
If `adhoc`, `research-and-implement` will create the tracking issue itself in Phase 1 (research) Step 5 —
do not pre-create one.

### 3. Present Scope

```markdown
## Proposed Work Scope (work2)

**Source:** #42 - <title>  (or: ad-hoc — "<description>")
**Identifier:** [work2:issue-42]

### Pipeline
1. /research-and-implement 42   — research + plan approval + implementation + done-check
2. /review-pipeline-coderabbit  — local review gates (Claude /code-review), PR creation, review/fix-loop (CodeRabbit best-effort + /pr-review remote for any source)
3. Wait for your review (bolted on — not part of the pipeline itself)
4. Summarize + merge decision
5. Reflect

### Notes for this run
<any --attach resume state>
```

Ask via AskUserQuestion: **Start** / **Modify scope** / **Cancel**.

### 4. Create Todos

```
[work2:${ID}] Run /research-and-implement ${ARG}
[work2:${ID}] Run /review-pipeline-coderabbit through the merge gate
[work2:${ID}] Wait for user's own PR review
[work2:${ID}] Summarize and confirm merge with user
[work2:${ID}] Reflect with improve-workflow agent
```

Mark the first task `in_progress`.

---

## Phase A — Research + Implement

Run `/research-and-implement ${ARG}`.

This single skill covers what `/work`'s guided-development phases (Explore/Clarify/Architect/Document) did,
but via hypothesis-driven investigation (`quaere-evidence`) rather than parallel architecture proposals:

- Phase 0 (worktree baseline): creates/uses an isolated git worktree automatically instead of switching branches in place, announces the branch and worktree path, doesn't poll.
- Phase 1 (research): posts a plan to the issue with an `Inconclusive / Deferred items` section. Its Step 3.5
  plan-review gate offers a fresh-context subagent review pass before approval — accept or skip it as
  offered. Run that subagent on Opus when a **Review & Verification Model** trigger fires (see above).
  **You approve the plan before Phase 2 starts** — this is the plan-approval checkpoint, equivalent
  to `/work`'s architecture sign-off, and the primary plan-quality gate this workflow uses.
- Phase 2 (implement): executes unit-by-unit, halts (does not ad-hoc patch) on any discovery not covered by
  the plan's discovery contract, ends with `/done-check`.

**Known friction to watch for:** the discovery-contract halt behavior is tuned for
codebases with formal invariants. Expect it may halt on benign discoveries more often than `/work`'s looser
guided-development did. Note any such false-halt in the reflect step.

Do not proceed to Phase B until `research-and-implement` reports Step 5 (final output: plan-vs-actual diff +
commit message) complete.

## Phase B — Review Pipeline

Run `/review-pipeline-coderabbit`, with this variance from the skill's default text.
Escalate the `/code-review` (Phase 0.5) pass to Opus when a **Review & Verification Model**
trigger fires (see above).

- **CodeRabbit is best-effort, not a gate** (per the skill's own Phase 1) — if it never responds (rate
  limit, app not installed, whatever), that's expected, not a stop condition. Only stop and tell the user if
  `/pr-review remote` ALSO finds nothing at all across multiple pushes and you suspect the CodeRabbit app
  genuinely isn't installed on the target repo (not confirmed in Prerequisites, only assumed) — otherwise
  just proceed on whatever review coverage exists.
- **PR description delta:** applies only to umbrella-tracked sub-issues (`Parent: #N` in the issue
  body). Most issues don't use that convention, so this will self-skip — expected, not a bug.

Stop at the pipeline's own `## ← user merges PR ←` gate. Do not continue into the post-merge phase yet.

## Phase C — Wait For Your Review (not in the pipeline)

`review-pipeline-coderabbit` stops at the merge gate but does not poll for *your* review state — it assumes
you'll look at the PR when you're ready. Since the ask was to also wait on your review before summarizing:

1. Run `/pr-review remote`. It fetches from every source at once — CodeRabbit's inline comments/review
   summary if it responded, and any plain top-level PR comment (your own locally-run review, or a delegated
   adversarial-review agent posting under your GitHub identity) — filters out anything already addressed via
   its own tracking, and reports "no reviewer feedback found" if there's nothing new. That "no feedback"
   result is this phase's stop condition, not a separate hand-rolled check.
2. If it reports no feedback, tell the user the PR is open and ready, and stop turn — do not poll in a loop.
   Resume this check next time you're invoked (e.g. via `/work2 --attach` or the user pinging back). The user
   invoking `/superpowers:receiving-code-review` directly, or `/pr-review remote` directly, instead of
   `/work2 --attach` is an expected way to resume this phase, not a deviation from it.
3. If it finds feedback, let it run its own Implement/Skip/Defer loop (per-item `AskUserQuestion`,
   `receiving-code-review`-verified fixes) — layer this pipeline's own discipline underneath, per
   `review-pipeline-coderabbit`'s Rules: `/done-check` in delta mode after each fix, `/stage-commit-push` for
   every commit, oscillation detection across iterations, and a best-effort (non-blocking) CodeRabbit re-poll
   before the next pass if a push re-triggered it.
4. Once `/pr-review remote` reports no unaddressed feedback remains, proceed to Phase D.

## Phase D — Summarize and Merge Decision

Spawn `summarize-work` agent: `Task(subagent_type="summarize-work", prompt="Summarize work on this PR for merge review")`.

Present its output highlighting key files and the PR URL, same as `/work`.

Ask via AskUserQuestion: **Merge now** / **Wait**. Never auto-merge.

If the user approves merge before CI/CodeRabbit has completed, wait for a green terminal state before
executing the merge — do not merge on the verbal instruction alone, and do not re-prompt once it's green.

If merged, continue into the pipeline's post-merge umbrella-drift-join phase only if the PR description
delta step determined this PR is umbrella-tracked; otherwise nothing further to do post-merge.

Suggest `/commit-commands:clean_gone`.

## Phase E — Reflect

Same as `/work`, plus pipeline-specific questions:

- **Difficulty / friction / steering** — as in `/work`.
- **Pipeline comparison**: where did `review-pipeline-coderabbit` do something `/work`'s `/pr-review`
  didn't (or vice versa)? Where did the discovery-contract halt behavior help or just add friction?
- **Prerequisite gaps hit this run** (`gh-post`, CodeRabbit app) — note if any degraded the run.
- **Skill tuning**: does anything in these skills need tuning based on this run (a rule that doesn't fit,
  a missing `quality-list` language addendum, a phase that should be trimmed further)?

Spawn `improve-workflow` agent: `Task(subagent_type="improve-workflow", prompt="Analyze this /work2 session for workflow improvements, comparing against /work")`.

---

## Skipping Checkpoints

Same as `/work`: confirm with user, mark completed with a note, continue.

## Error Handling

| Error | Response |
|-------|----------|
| Issue not found | "Issue #N not found. Check the number." |
| Active `[work2:*]` session exists | "Active work2 session exists. Complete or clear first." |
| `gh-post` missing | Stop, print the `uv tool install` command above. |
| CodeRabbit signal never arrives | Not a stop condition — best-effort only (see Phase B/`review-pipeline-coderabbit` Phase 1). Only stop if `/pr-review remote` also finds nothing across multiple pushes and the app seems genuinely uninstalled. |
| Discovery-contract halt (Phase A) | Surface per `implement`'s Step 3.2 procedure — do not patch ad hoc. |
