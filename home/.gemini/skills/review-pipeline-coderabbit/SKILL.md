---
name: review-pipeline-coderabbit
description: Full review pipeline from local changes through PR, CodeRabbit review (best-effort), and umbrella drift join. Pauses at the user-controlled merge gate between Phase 3a and 3b.
---

# Review Pipeline (CodeRabbit)

Orchestrate the full flow from local changes through PR review, user merge, and umbrella drift join. This skill ties together several sub-skills — invoke each by name.

CodeRabbit's automated review (best-effort) plus Gemini's own `pr-review` pass are the reviewers in this pipeline.

The pipeline crosses a **user-controlled merge gate** (Phase 3a → 3b): the user, not Gemini, merges the PR. Phases before the gate run on the PR branch; phases after run on `main` and tracking issues. Gemini pauses at the `## ← user merges PR ←` section.

## Phase 0: Done-check loop

1. Run `done-check` against the current diff (committed + staged + unstaged + untracked).
2. Triage the audit table — every `⚠` concern is actionable or closed as a recorded deferral (done-check step 5's defer path).
3. If unresolved concerns (actionable, not closed as recorded deferrals) exist:
   - Fix the code
   - Run `done-check` again (fresh, full audit — do not bias the next pass with the previous concerns list)
   - Re-triage
4. Repeat until every row is `✅`, `⊘ N/A`, or `⚠` closed as a recorded deferral per done-check step 5.

Done-check runs **before** any commit.

## Phase 0.5: Code-review gate

Runs after the done-check loop and **before anything is committed**.

1. Perform self code-review (or dispatch subagent via `invoke_subagent` with `TypeName: "self"`, `Role: "Code Reviewer"`) against the current diff.
2. Triage the output — classify each finding under the `finding-triage` SSOT dispositions.
3. If actionable findings exist: fix, run `done-check` in delta mode, then re-run code-review at the same effort. If the same conceptual topic recurs across 2+ iterations, stop and follow the escalation order in Rules.
4. Repeat until no actionable findings remain.

From here on, every reviewer finding is by construction a penetration of this gate — note that provenance in each triage presentation.

## Phase 1: Review and fix loop

1. Run `stage-commit-push` to stage, commit, and push local changes.
2. Run `file-pullreq` in **gate mode** — drafts the PR title + body following `gh-body-conventions` and the standard body skeleton, runs the laundering pass, and gets the user's approval. The skill stops at approval and emits the approved title + body for the next step. It does NOT create the PR itself.
3. Run `coderabbit-review`, passing the approved title + body — this creates the PR (the CodeRabbit app starts its review on PR open by itself; no reviewer-request step) and polls CodeRabbit's completion signal on the head commit **once, briefly**. CodeRabbit is best-effort here, not a gate:
   - Exit `0` (completed, genuinely zero findings) or a review with findings → note the result; either way, proceed to step 4.
   - Exit `2` (rate-limited / auto-paused / file-count skip) → read the script's printed cause, but do **not** nudge-and-repoll and do **not** block waiting for it. Note the cause and proceed to step 4 regardless — whatever review coverage exists will come from the user's own review or a delegated adversarial-review agent instead. A single opportunistic nudge (`gh pr comment <PR> --repo <owner>/<repo> --body "@coderabbitai review"`) is fine if cheap, but this step must not hold up the pipeline.
4. Run `pr-review remote`. This is the actual comment-fetching and fix-loop mechanism regardless of source: it pulls CodeRabbit's inline comments/review summary (when CodeRabbit responded), general PR conversation comments (where the user's own local review or a delegated adversarial-review agent posts, under the user's own GitHub identity), filters out already-addressed items via its own "Feedback Addressed" tracking, forms an opinion per item, and presents via `ask_question`. For every **Implement** decision it internally verifies via `superpowers:receiving-code-review` (or self-verification) before touching code — layer this pipeline's own discipline underneath that: run `done-check` in delta mode after each fix (not just `pr-review`'s own quality-gate step), and route every commit through `stage-commit-push` per the Rules below, not manual git commands.
5. **Reply to CodeRabbit's inline comments individually** (not folded into a single top-level reply) via `gh-post reply-inline <owner>/<repo> <PR> < /tmp/replies.jsonl` — one `{"id": <comment-id>, "body": "<reply>"}` per line, wrapper validates through the hardwrap detector before sending. (If `gh-post` is unavailable, loop line-by-line using `jq` and `gh api "repos/<owner>/<repo>/pulls/comments/<id>/replies" -f body="$body"`). This applies whenever `pr-review remote` is replying to a CodeRabbit-sourced inline thread; plain top-level PR comments (the user's or a delegated agent's) get a regular reply instead.
6. If a fresh push re-triggers a CodeRabbit review, repeat step 3's best-effort poll (still non-blocking, still no repeated nudging) before running `pr-review remote` again, so CodeRabbit's findings fold in if it responds in time. Repeat steps 3–6 until `pr-review remote` reports no unaddressed feedback remains (from any source).

## Phase 2a: PR description delta (pre-merge)

Skip when the work is not tied to an umbrella tracking issue. Trigger only when the merged-bound PR or its `Closes #N` references a sub-issue with a `Parent: #<umbrella>` line.

1. **Find the parent reference.** Read the sub-issue body (via `run_command`):

   ```bash
   gh issue view <leaf#> --json body -q .body | rg '^Parent:' | head -1
   ```

   No match → skip Phase 2a and 2b entirely.

2. **Derive the plan-vs-actual delta.** Compare the sub-issue's Scope / Out of scope / Acceptance against the merged-bound PR's actual diff and behavior. Cover:

   - Scope additions (work that landed but was not in the original Scope) — was it justified, or scope creep?
   - Scope subtractions (Scope items that were deferred or dropped) — were they punted to a follow-up issue?
   - Out-of-scope churn (deferrals that became in-scope, or new deferrals discovered during implementation)
   - Acceptance criteria that were tightened, loosened, or reworded during review

   A "no delta" outcome (everything matched) is a valid answer — record it explicitly.

3. **Edit the PR description.** Append a `## Plan-vs-actual delta` section to the existing body — full delta with file/line evidence and links to the relevant review iterations.

   Apply `gh-body-conventions` to the appended section (same semantic line breaks, same exclusions). Line refs into this PR's diff are permitted.

   Before invoking `gh-post pr edit`, run `gh-body-check` against the **final body** (existing PR body concatenated with the appended delta section). Paragraph boundaries and reference patterns can cross the section seam, so auditing only the appended section would miss them. Pass artifact kind `pr` and the target language. Any unresolved ⚠ blocks `gh-post pr edit` — revise the appended section and re-run until clean.

   Write the final body to a temp file and invoke `gh-post pr edit <N> --repo <owner>/<repo> --body-file /tmp/<descriptive-name>.md` (or fallback `gh pr edit <N> --repo <owner>/<repo> --body-file /tmp/<descriptive-name>.md` if `gh-post` is missing).

## ← user merges PR ←

Before stopping, check `gh pr view <PR> --json mergeable,mergeStateStatus` via `run_command`. A `mergeable: CONFLICTING` (or `UNKNOWN` after a fresh push — re-check after a few seconds) is a hard `ask_question` trigger, not something to resolve by guessing: surface the specific conflicting commits (`git log --oneline <merge-base>..origin/<base-branch>` filtered to files touched by both sides) and ask how to proceed. Do not attempt a rebase, `--auto`, or force-push on your own initiative — repo state can diverge from what the pipeline last saw (another process pushing to the base branch mid-session is exactly this case), and an automated resolution risks silently dropping work. Once the user directs a resolution, verify it (build, vet, and the relevant test suite) before pushing. This gate applies even after the user has taken over review personally — "the user is reviewing" is not the same as "the user approved this specific conflict resolution." Surface the conflict and get explicit direction before rebasing, regardless of who is driving review at that point.

CodeRabbit is not a merge gate (see Phase 1) — do not wait for it or block the merge gate on it. If it never responded (rate-limited or otherwise), that's expected and not a reason to hold up the user.

Stop here. The user merges the PR via the GitHub UI or `gh pr merge`. Do not attempt the merge from Gemini unless the user explicitly asks or approves via `ask_question`.

After the user confirms the merge has landed, continue to Phase 2b.

## Phase 2b: Umbrella drift join (post-merge)

Runs only after the user has merged.

1. **Sub-issue closing comment.** Post a compressed delta (≈ 5–10 lines) plus the merged PR link via `gh-post issue comment <leaf#> --repo <owner>/<repo> --body-file /tmp/<descriptive-name>.md` (or `gh issue comment` fallback), then close the sub-issue with `gh issue close <leaf#>`.

2. **Umbrella body update.** Two independent axes:

   - **Progress reflection (default action).** If the umbrella tracks sub-items by status annotation (`- [x] foo` checkbox, `_[Promoted to #N.]_` / `_[Done in #M.]_` inline tag, `Phases | Status` table column, etc.), update the item the leaf was promoted from. The skill that filed the leaf already wrote the "promoted" annotation; the merge step closes the loop by switching it to "done". Skip only if the umbrella truly has no per-item status convention.
   - **Design-assumption change.** Edit additionally when the delta changes a parent-level design assumption — a new deferral that affects another phase, a scope shift that invalidates the Phases table, a decision that contradicts the umbrella's "Decisions captured" section.

   A clean implementation with no parent-level implications still gets the progress-reflection edit; the design-assumption axis can be skipped.

3. **Do not edit the sub-issue body.**

## Rules

- **Fix-loop substeps** (Phase 1 step 4, layered underneath `pr-review remote`'s own Implement/Skip/Defer loop): `pr-review remote` drives the per-item decision and the verified fix itself; this pipeline adds three things around that which `pr-review` doesn't know about on its own:

  1. **Oscillation check (iteration N ≥ 2).** Compare current actionable topics against the previous iteration's preserved topics. If any conceptual topic recurs, halt and follow the escalation order below — do NOT fix or done-check.
  2. After each fix, run `done-check` in delta mode before the commit.
  3. Route the commit through `stage-commit-push`.
  4. Preserve actionable topic classifications for the next iteration's oscillation check, and re-poll CodeRabbit (Phase 1 step 6) before running `pr-review remote` again.

- **Never skip done-check, including in fix loops.** Every fix commit is itself a diff that can introduce new drift — especially `completion-hygiene` and `paired-artifact-drift`.

- **New-example derivation gate applies in the fix loop too.** If a fix introduces a new literal test example (a new fixture path, input value, or worked case) to satisfy a reviewer finding, `implement`'s Step 3.2.1 discipline still binds: don't assume the example's properties are obvious. A path chosen to be "just nonexistent," for instance, can land in a different error branch than intended — verify the example actually exercises the intended branch before asserting on it, the same way 3.2.1 requires for the initial implementation.

- **Done-check delta mode.** Report only rows whose status changes from the previous audit, plus any new ⚠. Resolve every new ⚠ before the subsequent `stage-commit-push`. Pay special attention to:

  - `paired-artifact-drift`: every comment / docstring / PR-body sentence touched by or referring to the fixed code must still be accurate.
  - `completion-hygiene`: linters/formatters catch style, but the fix may have added stray debug output or scratch test code.
  - `behavior-coverage`: a fix that edits a docstring / module doc stating a behavioral guarantee can silently widen it to sibling symbols, creating a per-symbol coverage obligation the previous audit never saw. Run the delta pass as a fresh `done-check` (subagent) invocation rather than informal doc-truth reasoning — confirming the broadened claim is *true* does not confirm each newly-covered symbol is *tested*.
  - The PR description: if a fix invalidates a claim in the description (e.g., "previously-missed case is now caught" became "now excluded"), update the description in the same iteration.

- **Never inject previous review comments into the next review prompt.**

- **Every commit goes through `stage-commit-push`.** Do not manually run git add/commit/push during the pipeline.

- **Pre-commit branch gate.** Before each `stage-commit-push`, verify the current branch is not the repo's default branch:

  ```
  test "$(git symbolic-ref --short HEAD)" != "$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@^origin/@@')"
  ```

  Halt and surface to user if equal.

- **Reply to CodeRabbit comments individually**, not as a single PR comment. Use `gh-post reply-inline <owner>/<repo> <PR> < /tmp/replies.jsonl`. JSONL shape: one `{"id": <comment-id>, "body": "<reply>"}` per line.

- **Triage is mandatory.** Never present raw review output to the user. Classify every finding under the `finding-triage` SSOT dispositions and lead with actionable items.

- **Sub-classify actionable findings before fixing.** Not all actionable findings warrant the same response:

  - **Surface** (typo, stale comment, wrong API name): fix is self-evident. Commit immediately.
  - **Invariant** — the `invariant-premise-check` disposition from `finding-triage` (claims about mathematical properties, semantic validity, precondition necessity): the finding's *conclusion* may be correct, but its *premise* may be wrong. Before committing a fix, verify the premise — check whether the invariant the finding assumes actually holds, by reading code, tests, and running a targeted experiment (a small script, a REPL check, or a temporary probe test) before trusting the finding's stated assumption.
  - **Boundary & Buffer Invariants**: for findings involving bit readers, counters, or streaming cursors, explicitly audit and test edge cases (`len == 0`, `err == io.EOF`, `produced >= limit`, `remaining < len(p)`, state resets on stream table transitions).
  - **Non-local** — the `opens-a-question` disposition from `finding-triage`: the finding is real but its resolution needs investigation, a design choice, or a scope judgment beyond a local edit. Re-enter `research` with the finding as the task, then escalate only the genuinely user-owned residue. Do not spot-patch and do not escalate a probe-able question straight to the user.

- **Oscillation detection.** Run at the start of each fix-loop iteration (Phase 1 step 6), BEFORE fix and done-check. If the same conceptual topic (not the same literal comment, but the same underlying question — e.g., "is this input valid?", "does this property hold?", "should this parameter accept both values?") appears across 2+ consecutive review iterations, stop fixing and escalate to the user via `ask_question`. Repeated findings on one topic signal that the underlying invariant is not understood well enough for a confident fix.

  **Escalation order.** Before presenting the fix-direction question (reject vs allow vs convert vs ...), FIRST ask whether the original plan scope is correct. Oscillation in the fix-direction space is the symptom that the contract is empty or depends on something outside the plan's scope — refining the fix without rescoping just re-anchors the same empty contract from a different angle. Ask in this order:

  1. **Is this question even single-actionable inside the current plan?** Does the disagreement among reviewers concern an upstream undecided design question (consumer semantics, system invariant, layout authority, etc.) that the plan implicitly assumed?
  2. **If yes upstream**: rescope. Close the current PR, refile the upstream design question as a separate issue, and let the current decision fall out of that resolution. This is the right move even when the current fix is technically correct in isolation.
  3. **If no upstream issue**: present what is known, what is uncertain, and ask the user to choose among the surviving fix options via `ask_question`.

  Convergence of independent reviewers (Gemini's own pass, CodeRabbit) on the same concern across iterations is the oscillation signal, regardless of any "no-clarifying-questions" preference elsewhere.

- **Pause at the merge gate.** Phase 2b runs only after the user merges. Do not run `gh pr merge` from Gemini unless explicitly asked.

