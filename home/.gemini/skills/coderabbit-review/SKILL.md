---
name: coderabbit-review
description: Create a GitHub PR and poll until the auto-triggered CodeRabbit review arrives.
---

# CodeRabbit Review

Create a GitHub PR, wait for CodeRabbit's automatic review, and triage the results.

## How it works

CodeRabbit is app-driven: once the GitHub app is installed on the repository, it reviews every PR on open and re-reviews incrementally on every push. There is no reviewer-request step.

**Non-default base → no auto-review.** A PR whose base isn't the default branch (e.g. an integration branch) gets a `Review skipped` comment and no `CodeRabbit` status. Trigger with `@coderabbitai review`, then `--poll` (normal mode would poll-timeout waiting for an auto-review that never starts).

**The completion signal is the `CodeRabbit` commit status or the `CodeRabbit / Review` check run, not the review object.** CodeRabbit reports the review lifecycle (`Review queued` → `Review in progress` → `Review completed`) on the PR's head SHA — as a commit status on most installs, or, on installs that post no commit status, as the `CodeRabbit / Review` check run (Checks API, `app.slug == "coderabbitai"`); the script reads whichever is present. **A clean review posts no review object at all** — a zero-finding run leaves only the walkthrough comment plus the `Review completed` terminal signal. Read the outcomes as:

- `Review completed` + review object for the head commit → findings exist; triage them.
- `Review completed` + no review object → **ambiguous**: either a genuine zero-finding pass or a **non-review skip** that still emits terminal `success`. A skip means the review never ran, so it must never be recorded as zero findings. Three skip causes are known, each leaving a discriminator in CodeRabbit's bot issue comments; the script rules them all out (exit `2`) before declaring a clean pass:
  - **Auto-pause** — `auto_pause_after_reviewed_commits` stops the review after N commits. Discriminator: the HTML marker `review paused by coderabbit.ai` (inside an HTML comment). Resume with `@coderabbitai review`, then `--poll`.
  - **Rate-limit** — the per-developer PR review limit was reached, so the review never started (visible prose: `[!WARNING]` / "Review limit reached"). Discriminator: the HTML marker `rate limited by coderabbit.ai`. Resume after the reset window (or push a new commit), then `--poll`.
  - **File-count** — the diff exceeds the max-files-per-review cap, so the review was skipped to avoid a low-quality review (visible prose: `[!IMPORTANT]` / "Review skipped" / "skipped due to max files limit"). Discriminator: the machine prose `skipped due to max files limit` **co-occurring in the same comment** with the `skip review by coderabbit.ai` marker. CodeRabbit reuses that marker for this and for intentional config skips, so the marker alone cannot separate an unintended file-count skip from a deliberate one; the prose alone would self-trigger on a walkthrough that quotes it — requiring both in one comment scopes the match to a real file-count skip (a marker in one comment plus the prose in a separate one does not qualify). Re-polling alone will not help while the file count is unchanged: either split the PR so fewer files change (the push re-reviews on its own), or raise the limit (plan / `.coderabbit.yaml`) and trigger a fresh review manually with `@coderabbitai review` — a config change does not auto-apply to an open PR — then `--poll`.
  - When no skip signature is present, the completion is a genuine zero-finding pass and the gate passes. The marker checks require the `<!--` wrapper so bot walkthrough prose describing these features does not self-trigger; deliberate config skips are intentionally left as clean.
- No terminal signal at all (poll timeout) — neither a `CodeRabbit` commit status nor a `CodeRabbit / Review` check run reached a terminal state → the review never started; halt and surface to the user — check the app installation, plan, and automatic-review settings in the CodeRabbit dashboard, or post `@coderabbitai full review` and read the response.

**Use `pr-with-coderabbit-review.sh` for the entire flow.** Do NOT create the PR separately with `gh pr create` and then try to poll — the script handles PR creation and status-based polling in one shot.

### Normal mode: create PR + poll

Run via `run_command`:

```bash
~/.gemini/skills/coderabbit-review/scripts/pr-with-coderabbit-review.sh --title "fix: foo" --body-file /tmp/body.md --base main
```

All arguments are forwarded to `gh-post pr create`. The script then polls for the CodeRabbit completion signal (the `CodeRabbit` commit status or the `CodeRabbit / Review` check run) until it reaches a terminal state, outputting one of: the review body plus that review's inline comments; an explicit zero-finding result; or a non-review-skip notice (exit `2`, for auto-pause / rate-limit / file-count) when the terminal `success` reflects a skipped, unreviewed push. The notice states the per-cause remedy.

Inline `--body <string>` and `-b <string>` are rejected by `gh-post` — the wrapper exists to keep every body through its hardwrap validator. Use `--body-file <path>` (preferred) or `--body-stdin`.

### Re-review mode: after pushing fixes

After pushing fix commits to an existing PR, wait for the incremental review the push already triggered (via `run_command`):

```bash
~/.gemini/skills/coderabbit-review/scripts/pr-with-coderabbit-review.sh --re-review https://github.com/owner/repo/pull/123
```

No trigger step is needed — CodeRabbit starts the incremental review on the push itself. The status lives on the new head SHA, so the wait is race-free even when the review finishes before the script starts.

### Poll-only mode: recovery for existing PRs

Run via `run_command`:

```bash
~/.gemini/skills/coderabbit-review/scripts/pr-with-coderabbit-review.sh --poll https://github.com/owner/repo/pull/123
```

Same wait as `--re-review`; use it after triggering a review manually. On timeout the script prints the manual trigger command (`gh pr comment <N> --body "@coderabbitai full review"`) for the case where automatic reviews are disabled or the app missed the event.

### Environment variables

- `CODERABBIT_POLL_INITIAL` — initial poll interval in seconds (default: 60)
- `CODERABBIT_POLL_MAX` — max poll interval (default: 300)
- `CODERABBIT_POLL_ATTEMPTS` — max attempts (default: 10)

## Triage the review

CodeRabbit reviews see the diff and file contents and run linters / AST checks, but lack project-specific knowledge about design decisions, test coverage, or runtime verification. The output is chattier than most reviewers: the summary body carries collapsed sections (walkthrough, nitpicks, additional comments) and actionable items arrive as inline comments.

For each finding:

1. **Cross-check** against what you already know from the current conversation — code you've read, tests you've run, decisions made with the user
2. **Classify** under the `finding-triage` SSOT dispositions — typically `actionable`, `false-positive` (with reasoning), or `uncertain-validity`; a real finding whose fix is non-local is `opens-a-question` → re-enter `research`
3. **Present the triage** to the user — don't dump raw review output

Items inside the collapsed nitpick sections of the review body are findings too — expand and triage them under the same dispositions rather than skipping the collapsed blocks.

## Respond to review

Each CodeRabbit finding lives on an inline thread; that thread is the unit of response. After triaging, reply within each thread via `gh-post reply-inline` — every reply body is validated (hardwrap detector + halt-before-send) and a single batch covers the full review:

```bash
# 1. Collect target threads — by default this filters to CodeRabbit-authored heads
#    and reports per-thread state (resolved? has reply? outdated?).
#    Use --unresolved --unreplied to narrow to threads that actually need a reply.
~/.gemini/skills/coderabbit-review/scripts/list-pr-threads.sh {owner}/{repo} {number} --unresolved --unreplied

# 2. Build a JSONL file: one {"id": <head-comment-id>, "body": "<reply text>"} per line.
#    Each reply should be concise — state the classification (fixed, false positive,
#    acknowledged) and the reasoning in 1-2 sentences.

# 3. Send the batch using gh-post reply-inline (or gh api loop fallback if gh-post is unavailable).
gh-post reply-inline {owner}/{repo} {number} < /tmp/replies.jsonl
```

If `list-pr-threads.sh --unresolved --unreplied` returns zero lines: every CodeRabbit thread is already resolved or already has a reply — do NOT post additional replies. Surface this to the user and ask before doing anything else. Stacking a duplicate "addressed in …" reply on a closed thread is the failure mode this wrapper exists to prevent.

CodeRabbit converses on its own threads: it may reply to your reply, and its incremental reviews may resolve threads it judges addressed by a fix commit. Both states are already excluded by `--unresolved --unreplied`, so re-run `list-pr-threads.sh` after each incremental review instead of caching an earlier thread list.

Direct `gh api .../comments/{id}/replies -F body=...` is still possible but defeats both the body-validation guarantee and the thread-state filter — use it only for one-off cases where the JSONL ceremony is overhead, and verify thread state via `list-pr-threads.sh` first.

**Outside-diff findings** sit in the review body, not on an inline thread (CR couldn't anchor them to the diff), so `reply-inline` can't reach them. Respond only when one needs visible closure (e.g. a Critical-flagged false positive), with a single top-level PR comment — the only channel; otherwise leave it.

## Prerequisites

- CodeRabbit GitHub app installed on the repository — PR reviews on private repositories require a Pro plan or active trial; public repositories get them free
- `gh` CLI
- `gh-post` on `PATH` (optional) — the script routes PR creation through `gh-post pr create` when present, falling back to `gh pr create` if absent.
- Optional: `.coderabbit.yaml` in the repo root to tune noise (`profile: chill`), path filters, and auto-review behavior
