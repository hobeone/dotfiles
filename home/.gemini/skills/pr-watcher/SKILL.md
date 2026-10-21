---
name: pr-watcher
description: Use when monitoring GitHub pull requests in the background, conducting continuous 2-pass deep PR reviews, verifying incremental author pushes, and managing automated approvals and merge readiness.
---

# PR Watcher: Autonomous Continuous Deep PR Review

Autonomous background pull-request review and monitoring workflow. Combines scheduled polling, ephemeral worktrees, adaptive tier triage (lightweight vs. full deep review), cross-model adversarial swarm auditing, deterministic mutation gating, and automated thread resolution.

> [!IMPORTANT]
> **Active Model Configuration (Update Here as Models Evolve)**
> - **Primary Adversarial Swarm Model (`<PRIMARY_REVIEW_MODEL>`)**: **Claude Opus 5.5 (High)** (`opus-5.5-high`)
> - **Pro Quota-Failover Model (`<PRO_FAILOVER_MODEL>`)**: **Gemini 4 Argon (High)**
> - **Fast / Subagent Flash Model (`<FLASH_MODEL>`)**: **Gemini 3.8 Flash (High)** (`gemini-3.8-flash-high`, or `flash` for `invoke_subagent`)
> - **Lightweight / Lite Model (`<FLASH_LITE_MODEL>`)**: **Gemini 3.5 Flash Lite** (`gemini-3.5-flash-lite`, or `flash_lite` for `invoke_subagent`)
>
> *All references to `<PRIMARY_REVIEW_MODEL>`, `<PRO_FAILOVER_MODEL>`, and `<FLASH_MODEL>` in this skill and its reference docs resolve to the models above.*

---

## Quick Reference

| Phase | Responsibility | Tools / Commands |
| :--- | :--- | :--- |
| **0. Drain & Poll** | Read swarm board up to head; poll open PRs every 5m; classify tier | `read_board`, `scripts/poll-prs.sh`, `scripts/tier-pr.sh` |
| **1. Worktree Setup** | Fetch origin & create ephemeral detached worktree at `headRefOid` | `git fetch origin pull/<PR>/head && git worktree add --detach /tmp/pr-<PR>-audit <head>` |
| **2. Pass 1: Gates** | Race tests, static gates, mutation specs, adversarial probes | `go test -race`, `scripts/mutate`, static linters |
| **3. Pass 2: Audits** | Tier 1: inline doc review; Tier 2: mandatory 3-lane `<PRIMARY_REVIEW_MODEL>` adversarial swarm (`rev-1`, `rev-2`, `rev-3`) | `swarm` (`<PRIMARY_REVIEW_MODEL>` $\leftrightarrow$ `<PRO_FAILOVER_MODEL>` on quota) |
| **4. Pass 3: Action** | Resolve fixed threads, post formal review + commit status | `scripts/resolve-thread.sh`, `post-review.sh --expect-head <sha>` |
| **5. Cleanup & Report** | Remove ephemeral worktree, update `state.json` (`reviewModels`), output PT status table | `git worktree remove --force /tmp/pr-<PR>-audit`, update `state.json` |

---

## 1. Setting Up the Watcher

Run the watcher on a recurring schedule using the `schedule` tool:
- **`CronExpression`**: `"*/5 * * * *"` (every 5 minutes).
- **`IsDaemon`**: `false` (keeps the session active across monitoring cycles).
- **`Prompt`**: Prompt instructing the agent to run one watcher cycle.

```bash
# Example scheduler tool invocation
schedule(
  CronExpression="*/5 * * * *",
  IsDaemon=false,
  Prompt="Run PR watcher cycle: drain swarm board messages and publish any completed verdicts immediately. Poll gh pr list for new or updated open PRs. On new PRs, run adversarial review via the 3-lane <PRIMARY_REVIEW_MODEL> swarm and post findings. On author replies or new commits, re-review, resolve fixed threads via GraphQL, and post approval when all threads are resolved. Record reviewModels in state.json and output the PT status table."
)
```

---

## 2. Each Watcher Cycle: Step-by-Step

### Step 2.1: Drain Swarm Board, Poll & State Compare
1. **Drain Swarm Board First**: Before polling or starting new work, check if any swarm board messages have arrived and call `read_board(since=<last_read_seq>)` up to the latest `head`.
   - **Publish Completed Verdicts Immediately**: Whenever a swarm reviewer posts a completed review or incremental verification on the board, **immediately** resolve addressed threads and publish the review to GitHub via `post-review.sh` before starting new reviews or calling `swarm_wait`. Never let a completed verdict sit unpublished on the board across turns or compactions.
   - **Stop Hook Invariant**: You must `read_board` up to the latest board `head` before ending a turn or calling `swarm_wait`, or the stop hook will block termination.
2. **Poll Open PRs**: Poll open PRs immediately on every cron trigger using the helper script (never skip or defer polling while a background task for another PR is still running):
```bash
TZ="America/Los_Angeles" date "+%Y-%m-%d %H:%M:%S %Z" && ~/.gemini/skills/pr-watcher/scripts/poll-prs.sh
```
Read `~/.gemini/scratch/pr_watcher/state.json`:
- **Priority Rule — Re-Reviews & Thread Resolution First**: Always check open PRs with prior review comments (`CHANGES_REQUESTED` or unresolved threads) **before** starting or continuing a long-running initial audit on another PR. Once an author pushes a fix or addresses a comment, verifying and resolving that thread takes top priority.
- **Merged PRs**: PR in `state.json` with status `APPROVED` that no longer appears in `gh pr list` $\to$ mark `merged: true` / `state: "MERGED"` in `state.json` (recording `mergedAt` via `gh pr view <PR> --json state,mergedAt`) and run `git fetch origin main` (never run `git pull` on the main working copy).
- **Aborted / Closed PRs**: PR in `state.json` that was closed without merging $\to$ kill any in-flight tasks/subagents for that PR, remove `/tmp/pr-<PR>-audit`, and mark `CLOSED` in `state.json`.
- **Review Feedback / Changes Requested**: When owner or peer review comments raise new substantive findings on an open PR $\to$ update status to `CHANGES_REQUESTED` and record finding summaries and GraphQL thread IDs (`PRRT_...`) in `state.json`, awaiting author fixes.
- **Unchanged PRs**: PR whose `headRefOid` and `updatedAt` match `state.json` and has 0 unresolved threads $\to$ skip.
- **New or Updated PRs**: PR whose `headRefOid` or `updatedAt` changed, or which has unresolved review threads (`~/.gemini/skills/pr-watcher/scripts/resolve-thread.sh --list-unresolved <PR>`) or new follow-up comments on resolved threads (`gh api repos/<owner>/<repo>/pulls/<PR>/comments`) $\to$ proceed to triage.

### Step 2.2: Adaptive Tier Triage
Run the tier classifier on the target PR:
```bash
~/.gemini/skills/pr-watcher/scripts/tier-pr.sh <PR>
```
See [references/tier-routing.md](references/tier-routing.md) for full classification details:
- **Tier 1 (Lightweight Fast-Path)**:
  - Applicable: Documentation only (`.md`, `docs/*`, `README*`, `LICENSE*`) or comment-only diffs. Strictly NO `.go` code, test code, or scripts.
  - Review: Fast sequential verification of doc and citation gates (`check_citations`, `check_doc_citations`). Single-pass evaluation in main context without subagents. 30–60s turnaround.
- **Tier 2 (Full Deep PR Review)**:
  - Applicable: **Any PR touching Go code** (production or test files, single-line patches, non-core packages), build scripts, CI tooling, or runtime behavior.
  - Review: Detached ephemeral worktree in `/tmp/pr-<PR>-audit`, Pass 1 deterministic gates, Pass 2 mandatory 3-lane adversarial review via `<PRIMARY_REVIEW_MODEL>` swarm (`rev-1`, `rev-2`, `rev-3`), Pass 3 formal review / thread resolution.

---

## 3. Worktree Isolation & Gate Sequencing

Always audit in an ephemeral detached worktree. **Never** run `git pull` or `git checkout` on the main working copy, as concurrent agents or background daemons may hold `.git/index.lock`:
```bash
git fetch origin main pull/<PR>/head
git worktree add --detach /tmp/pr-<PR>-audit <headRefOid>
```

> [!IMPORTANT]
> **Strict Worktree Mutation Invariant**: Only one agent may run `scripts/mutate` in a given `/tmp/pr-<PR>-audit` worktree at a time. When delegating to a single swarm worker, that worker runs Pass 1 (`scripts/mutate`, tests, linters) sequentially before its Pass 2 code audit. When fanning out a large PR across 3 parallel swarm lanes, either run `scripts/mutate` in the coordinator before dispatching the lanes or give the mutation lane its own `/tmp/pr-<PR>-mutate` worktree so read-only lanes never inspect mid-mutation code.
>
> **Fail-Fast**: If Pass 1 fails (unit test fails, static gate errors, or authored `.spec` survives), HALT immediately. Post the failure evidence without spending tokens on Pass 2.

---

## 4. Pass 1: Deterministic Verification (In `/tmp/pr-<PR>-audit`)

1. **Race-Enabled Unit Tests**:
   ```bash
   go test -race -count=1 <touched_packages>
   ```
2. **Static Analysis & Citation Gates**:
   ```bash
   golangci-lint run <touched_packages>
   go run ./scripts/check_citations
   go run ./scripts/check_doc_citations
   go run ./scripts/check_dup_comments
   go run ./scripts/check_test_alignment --min-complexity=8
   go run ./scripts/check_lock_io --all
   go run ./scripts/check_test_doubles
   ```
3. **Committed Mutation Specs**:
   ```bash
   go run ./scripts/mutate <spec_file.spec>
   ```
4. **Adversarial Mutation Expansion (Rule 1)**:
   Synthesize temporary mutations against modified conditions in `/tmp/adv.spec` and verify they are `KILLED`:
   - **Conjunct Splitting**: Split `if A && B` or `if A || B` into `if A` and `if B`.
   - **Door Degradation**: Replace instance-bound methods (`FooJob(j)`) with by-ID counterparts (`Foo(id)`).
   - **Boundary Shifting**: Adjust counters/lengths by $\pm 1$.
   ```bash
   go run ./scripts/mutate /tmp/adv.spec && rm -f /tmp/adv.spec
   ```
5. **Sibling Enumeration & Callee-Doc Audit (Rules 2 & 3)**:
   - Full read of enclosing functions to ensure no sibling exit paths still use old patterns.
   - Pipeline-wide `git grep` for matching gates/identifiers.
   - Cross-check callee doc comments against production caller actions.

---

## 5. Pass 2: Adversarial Swarm Auditing (Tier 2)

Maintain a persistent pool of 3 swarm review workers (`rev-1`, `rev-2`, `rev-3`) using the `swarm` tool and the models configured in the **Active Model Configuration** callout at the top of this file:

1. **Cross-Model Adversarial Posture (`<PRIMARY_REVIEW_MODEL>`)**:
   - Pin review workers to `<PRIMARY_REVIEW_MODEL>` via `swarm(action="add", name="rev-1", model="<PRIMARY_REVIEW_MODEL>", brief="...")`.
   - Because PRs are often authored by a sibling Gemini model (e.g., Gemini 4 Argon), instruct reviewers to be **extra adversarial and skeptical**: never trust commit-body claims, doc comments, or authored `.spec` files without mechanical verification.
2. **Quota Failover & Recovery (`<PRIMARY_REVIEW_MODEL>` $\leftrightarrow$ `<PRO_FAILOVER_MODEL>`)**:
   - If a `<PRIMARY_REVIEW_MODEL>` worker hits `RESOURCE_EXHAUSTED` quota limits, **do not `kill` and `add`** the worker. Switch `waiting` workers in-place to `<PRO_FAILOVER_MODEL>` (or `<FLASH_MODEL>` for flash-tier passes) via:
     ```bash
     swarm(action="model", name="rev-1", model="<PRO_FAILOVER_MODEL>")
     ```
   - Record the quota reset time reported in the error message. Once the `<PRIMARY_REVIEW_MODEL>` quota window resets, switch the workers back in-place via `swarm(action="model", name="rev-1", model="<PRIMARY_REVIEW_MODEL>")`.
3. **Mandatory 3-Lane Swarm Architecture (Default for ALL Tier 2 PRs)**:
   Every code change receives a 3-lane parallel audit across the swarm workers:
   - **Lane 1 (`rev-1`) — Core Invariants, Concurrency & Lifecycle**: Audit state machine transitions, mutex locking, channel synchronization, goroutine lifecycles, and panic/error routing. Verify that residency invariants hold across all state branches.
   - **Lane 2 (`rev-2`) — Downstream Consumers, Callee Side-Effects & Dependency Engines**: Trace callee side-effects, intermediate handlers, fault handlers, and downstream dependency engines (`par2engine`, `rarengine`, post-processing stages). Verify caller ordering before entry and downstream failure propagation.
   - **Lane 3 (`rev-3`) — Independent Adversarial Mutation Probes & Rule 4 Sweep**:
     - **Independent Mutation Probes**: Do NOT rely solely on the author's committed `.spec` files (which only test what the author thought of). Synthesize novel mutation specs (`/tmp/adv.spec`) attacking implicit invariants, unhandled edge cases, boundary shifts, door degradation, and conjunct splitting. Verify each mutation is `KILLED`.
     - **Rule 4 Pipeline Sweep**: Verify all doc/comment citations pipeline-wide using `git grep`. Check that no false universals (*only*, *never*, *always*) or stale references remain.
   - **Fallback (`invoke_subagent`)**: If `swarm` is unavailable, spawn subagents via `invoke_subagent(Model="flash")` (`<FLASH_MODEL>`) to audit the 3 angles after Pass 1 completes.
4. **Mandatory 4-Gate Active Refutation & Calibration Protocol (Include in Every Reviewer Brief)**:
   Every swarm reviewer (`@rev-1`..`@rev-3`) and coordinator verification pass MUST apply these four gates before reporting any finding:
   - **Gate 1 — Intermediate-Line, Callee Side-Effect & Caller-Ordering Trace**: Before claiming a race or state bug between point A and point B, read every intermediate statement and callee between A and B (e.g., checking whether an intermediate helper already validates residency or whether a fault handler calls `PauseJob` and flips `Intent` before a downstream check), and trace the caller's ordering before entry.
   - **Gate 2 — Verbatim Source Quotes & Library Check**: Quote exact guard expressions, function signatures, and line numbers directly from the worktree file at `<headRefOid>` — never paraphrase or assert library behavior from memory.
   - **Gate 3 — Reachable-Outcome Severity Calibration**: Calibrate severity from `(reachable outcome) × (precondition width)`, not the worst imagined outcome. Narrow multi-precondition races or non-corrupting leftovers are `severity:low` / `🟡 Minor`.
   - **Gate 4 — Fix-Precondition Check**: Before proposing a fix copied from a neighboring code path, verify that path's concurrency and exclusivity preconditions (e.g., never apply a single-writer directory-diff snapshot rollback to a directory shared with concurrent download writers).

---

## 6. Pass 3: Publishing Findings, Resolving Threads & Approval

### Standardized Verdict Comment & Commit Status Protocol
Every verdict comment (initial review, re-review, and incremental review — even when the only change on a new head is "no new findings") MUST use this exact machine- and human-readable format and post a GitHub commit status (`context: deep-pr-review`) on the reviewed SHA:

1. **Hidden Marker (Line 1)**:
   ```markdown
   <!-- deep-pr-review head:<full 40-char sha> verdict:<APPROVED|CHANGES_REQUESTED|COMMENTED> threads_open:<n> -->
   ```
2. **Visible Header (Line 2)**:
   ```markdown
   ## Review of `<short sha>` (<full 40-char sha>)[ (since `<old short sha>`)]: <APPROVED|CHANGES REQUESTED|COMMENTED>
   ```
3. **Fixed Body Sections**:
   - `**Scope:**` commits covered (e.g., `` `28ea17b8..fd6f6970` (1 commit) `` or `full PR`).
   - `**Previously raised, now:**` one line per earlier finding, marked `fixed in <sha>` / `still open` / `declined: <reason>`, or `none`.
   - `**Checks run:**` exact commands executed and their results.
   - `**Not verified:**` suites not run (e.g., `live Usenet E2E (test/e2e/) and crash consistency (test/crash/).`), or `none` only if literally everything was run.
   - `**Open threads:**` list of open GraphQL thread IDs (`PRRT_...`), or `none`.
4. **Last Line**:
   ```markdown
   Status: <APPROVED|CHANGES REQUESTED|COMMENTED> at `<short sha>`. Becomes stale if the PR head moves.
   ```
5. **GitHub Commit Status (`deep-pr-review`)**:
   Both `post-review.sh` and `approve-pr.sh` automatically post a commit status on `<full 40-char sha>` via `gh api repos/<owner>/<repo>/statuses/<sha>` with `context="deep-pr-review"`, `state="success"|"failure"|"pending"`, and `description="<VERDICT> at <short sha>"`.
6. **Mandatory Rules**:
   - Always post the verdict as a top-level PR comment or formal review body, never only as inline thread replies.
   - If the PR head moves after a verdict, always post a new verdict comment and commit status for the new head SHA, even when the only change is "no new findings".

### Case A: New or Unaddressed Issues Found
Format findings into JSON and post inline review + commit status using `post-review.sh`:
```bash
~/.gemini/skills/deep-pr-review/scripts/post-review.sh <PR> <findings.json> \
  --expect-head <full-40-char-headRefOid> \
  --verdict CHANGES_REQUESTED \
  --scope "full PR" \
  --previously-raised "none" \
  --checks "- go test -race ...: PASS" \
  --not-verified "live Usenet E2E (test/e2e/) and crash consistency (test/crash/)."
```
*Note: `<findings.json>` must be a JSON array where each finding uses `"path"` (never `"file"`), `"line"`, `"severity"`, `"category"`, `"effort"`, `"title"`, `"body"`, and `"agent_prompt"`. Governance fields are enforced: every `🔴 Critical` / `🟠 Major` finding must also carry `"counter_argument"` (the strongest argument that it is not a real problem or not worth fixing — the verifier's strongest failed refutation), and every `🔧 Moderate` / `🏗️ Heavy lift` finding must carry `"rejected_alternative"` (one fix considered and rejected, with why). `post-review.sh` refuses to post, before any network write, when one is missing or blank. `--expect-head` aborts if the PR head moved since checkout. `post-review.sh` automatically queries live `PRRT_...` thread IDs after creating the review, patches the `**Open threads:**` section and `threads_open:<n>` marker, and posts the `deep-pr-review` commit status.*
Record the newly created GraphQL review thread IDs (`PRRT_...`) via `~/.gemini/skills/pr-watcher/scripts/resolve-thread.sh --list-unresolved <PR>` into `state.json`.

### Case B: Incremental Commit or Author Reply Addresses Open Threads
1. List all live unresolved review threads directly from GitHub GraphQL (do not rely solely on `state.json`):
   ```bash
   ~/.gemini/skills/pr-watcher/scripts/resolve-thread.sh --list-unresolved <PR>
   ```
2. For each unresolved thread, verify whether the author's new commit(s) or reply has addressed the comment.
3. **Immediately** mark every addressed thread resolved via GraphQL (even if other threads on the PR remain open, and strictly before posting the verdict):
   ```bash
   ~/.gemini/skills/pr-watcher/scripts/resolve-thread.sh <threadId1> <threadId2> ...
   # Or, if all unresolved threads on the PR have been verified addressed:
   ~/.gemini/skills/pr-watcher/scripts/resolve-thread.sh --pr <PR> --all
   ```
4. Re-check remaining unresolved threads (`resolve-thread.sh --list-unresolved <PR>`). Post the formal `APPROVED` review (with an empty findings array `[]`) and commit status via `post-review.sh` (or `approve-pr.sh` when posting an issue comment):
   ```bash
   echo '[]' > /tmp/pr-<PR>-findings.json
   ~/.gemini/skills/deep-pr-review/scripts/post-review.sh <PR> /tmp/pr-<PR>-findings.json \
     --expect-head <full-40-char-headRefOid> \
     --verdict APPROVED \
     --since <old-sha> \
     --scope "\`<old-short>..<new-short>\` (1 commit)" \
     --previously-raised "- \`PRRT_...\`: fixed in \`<sha>\`" \
     --checks "- go test -race ...: PASS" \
     --not-verified "live Usenet E2E (test/e2e/) and crash consistency (test/crash/)."
   ```

### Case C: Worktree Cleanup, State Persistence & Status Table
1. Always remove the ephemeral worktree:
```bash
git worktree remove --force /tmp/pr-<PR>-audit
```
2. Update `~/.gemini/scratch/pr_watcher/state.json` with:
   - `lastReviewedHeadOid` (full 40-char SHA)
   - `verdict` (`APPROVED` | `CHANGES_REQUESTED` | `COMMENTED`)
   - `reviewModels` (array of actual model identifiers from the Active Model Configuration used to review this PR, e.g., `["<PRIMARY_REVIEW_MODEL>"]` or `["<PRIMARY_REVIEW_MODEL>", "<PRO_FAILOVER_MODEL>"]`)
   - `reviewUrl` (clickable URL to the posted `#pullrequestreview-...` or `#issuecomment-...`)
   - `openThreadIds` (array of unresolved `PRRT_...` IDs)
   - `merged` (`true` | `false`)
3. Output a concise status report at the end of every cycle containing:
   - **Header with Pacific Time (`America/Los_Angeles`)**: `### PR Watcher Status — YYYY-MM-DD HH:MM:SS PDT/PST (Iteration N)`
   - **Open PR Table**:
     ```markdown
     | PR | Title | Head SHA | Merge Status | Review Verdict | Review Model(s) | Open Threads | Active Worker / Action |
     |---|---|---|---|---|---|---|---|
     | **#830** | `fix(assembler): ...` | `c217e507` | `CLEAN` | **APPROVED** | `<PRIMARY_REVIEW_MODEL>`, `<PRO_FAILOVER_MODEL>` | 0 | Idle — approved ([review #5481942052](https://github.com/...)) |
     ```
   - **Summary Footer**: Count/range of merged PRs and active Swarm Worker roster (`name`, `model`, `state`).

---

## Common Traps & Antipatterns

| Mistake | Consequence | Prevention |
| :--- | :--- | :--- |
| **Leaving completed swarm verdicts on the board** | PR sits unreviewed on GitHub even though worker finished | Call `read_board` first on every wakeup and publish completed reviews via `post-review.sh` before starting new tasks or waiting |
| **Not calling `read_board` up to `head` before ending turn** | Stop hook blocks turn termination | Always drain `read_board(since=...)` to the latest board `head` before finishing |
| **Killing swarm workers on primary model quota exhaustion** | Destroys worker conversation history and wastes setup | Switch waiting workers in-place via `swarm(action="model", model="<PRO_FAILOVER_MODEL>")` and switch back when quota resets |
| **Running `git pull` on the main working copy** | Collides with `.git/index.lock` from sibling agents/daemons | Never `git pull` or `git checkout` in the main workspace; use `git fetch origin` and detached `/tmp/pr-<PR>-audit` worktrees |
| **Using `"file"` instead of `"path"` in `findings.json`** | `post-review.sh` fails to match `valid.tsv` and drops inline anchors to orphan body comments | Always use `"path"` and `"line"` in every finding object |
| **Leaving addressed review comments unresolved** | Stale open threads block merge readiness and obscure true remaining work | Run `resolve-thread.sh --list-unresolved <PR>` on every update and immediately resolve every addressed thread via `resolve-thread.sh` |
| **Skipping cron polls while a long task runs** | Author fixes on other PRs sit unverified with unresolved threads | Poll `poll-prs.sh` on every cron trigger and prioritize thread resolution on updated PRs |
| **Running `scripts/mutate` concurrently in one worktree** | Concurrent readers inspect corrupted/mutated code and hallucinate bugs | Run `scripts/mutate` sequentially before code inspection or isolate mutation runs in `/tmp/pr-<PR>-mutate` |
| **Leaking subagents across cycles** | Context window bloat, leaked background processes | Kill one-shot subagents immediately after receiving reports |
| **Using `IsDaemon: true` on monitoring cron** | Agent finishes turn and suspends execution | Always set `IsDaemon: false` on active monitoring tasks |
| **Allowing code changes to bypass Tier 2** | Subtle bugs, races, or mutant survivors ship unverified | Tier 1 is strictly for docs and comment-only diffs. All code changes require Tier 2 review |
| **Trusting authored `.spec` without adversarial probes** | Surviving mutant branches ship silently | Apply conjunct splitting and instance-to-ID degradation |
| **Attempting `gh pr review --approve` on own PRs** | Fails with GraphQL API error | Use `post-review.sh --verdict APPROVED` (`event="COMMENT"`) or `approve-pr.sh` as approval protocol |
