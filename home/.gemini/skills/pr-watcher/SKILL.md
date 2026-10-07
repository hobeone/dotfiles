---
name: pr-watcher
description: Use when monitoring GitHub pull requests in the background, conducting continuous 2-pass deep PR reviews, verifying incremental author pushes, and managing automated approvals and merge readiness.
---

# PR Watcher: Autonomous Continuous Deep PR Review

Autonomous background pull-request review and monitoring workflow. Combines scheduled polling, ephemeral worktrees, adaptive tier triage (lightweight vs. full deep review), deterministic mutation gating, adversarial contract auditing, and automated thread resolution.

---

## Quick Reference

| Phase | Responsibility | Tools / Commands |
| :--- | :--- | :--- |
| **0. Poll & Triage** | Poll open PRs every 5m; classify tier; skip merged/unchanged | `scripts/poll-prs.sh`, `scripts/tier-pr.sh` |
| **1. Worktree Setup** | Create ephemeral detached worktree at `headRefOid` | `git worktree add --detach /tmp/pr-<PR>-audit <head>` |
| **2. Pass 1: Gates** | Race tests, static gates, mutation specs, adversarial probes | `go test -race`, `scripts/mutate`, static linters |
| **3. Pass 2: Audits** | Tier 1: inline review; Tier 2: contract & test subagents | `invoke_subagent` (`pr-contract-auditor`, `pr-test-verifier`) |
| **4. Pass 3: Action** | Post inline review, or resolve threads & approve merge | `post-review.sh`, `scripts/resolve-thread.sh`, `scripts/approve-pr.sh` |
| **5. Cleanup** | Remove ephemeral worktree, kill subagents, update state | `git worktree remove --force /tmp/pr-<PR>-audit`, update `state.json` |

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
  Prompt="Run PR watcher cycle: poll gh pr list for new or updated open PRs. On new PRs, run review and post findings. On author replies or new commits, re-review, resolve fixed threads via GraphQL, and post approval when all threads are resolved. Update state.json."
)
```

---

## 2. Each Watcher Cycle: Step-by-Step

### Step 2.1: Poll & State Compare
Poll open PRs immediately on every cron trigger using the helper script (never skip or defer polling while a background task for another PR is still running):
```bash
~/.gemini/skills/pr-watcher/scripts/poll-prs.sh
```
Read `~/.gemini/jetski/scratch/pr_watcher/state.json`:
- **Priority Rule — Re-Reviews & Thread Resolution First**: Always check open PRs with prior review comments (`CHANGES_REQUESTED` or unresolved threads) **before** starting or continuing a long-running initial audit on another PR. Once an author pushes a fix or addresses a comment, verifying and resolving that thread takes top priority.
- **Merged PRs**: PR in `state.json` with status `APPROVED` that no longer appears in `gh pr list` $\to$ mark `MERGED` in `state.json` (recording `merged_at` timestamp via `gh pr view <PR> --json mergedAt`), and fast-forward local `main` via `git pull --ff-only origin main`.
- **Aborted / Closed PRs**: PR in `state.json` that was closed without merging $\to$ kill any in-flight tasks/subagents for that PR, remove `/tmp/pr-<PR>-audit`, and mark `CLOSED` in `state.json`.
- **Review Feedback / Changes Requested**: When owner or peer review comments raise new substantive findings on an open PR $\to$ update status to `CHANGES_REQUESTED` and record finding summaries and GraphQL thread IDs (`PRRT_...`) in `state.json`, awaiting author fixes.
- **Unchanged PRs**: PR whose `headRefOid` and `updatedAt` match `state.json` and has 0 unresolved threads $\to$ skip.
- **New or Updated PRs**: PR whose `headRefOid` or `updatedAt` changed, or which has unresolved review threads (`~/.gemini/skills/pr-watcher/scripts/resolve-thread.sh --list-unresolved <PR>`) $\to$ proceed to triage.

### Step 2.2: Adaptive Tier Triage
Run the tier classifier on the target PR:
```bash
~/.gemini/skills/pr-watcher/scripts/tier-pr.sh <PR>
```
See [references/tier-routing.md](references/tier-routing.md) for full classification details:
- **Tier 1 (Lightweight Fast-Path)**:
  - Applicable: Documentation only, pure test/spec additions, scripts/CI tooling, or diff $\le 30$ lines outside core packages.
  - Review: Fast sequential verification of tests and static gates. Single-pass evaluation in main context without subagents. 30–60s turnaround.
- **Tier 2 (Full Deep PR Review)**:
  - Applicable: Changes in `internal/app`, `internal/dispatch`, `internal/durability`, `internal/downloader`, `internal/assembler`, `internal/nntp`, `internal/par2`, `internal/job`, `internal/sched`, or any concurrency/mutex/lifecycle changes.
  - Review: Ephemeral worktree, Pass 1 deterministic gates + adversarial mutation expansion, Pass 2 parallel subagents (`flash`), Pass 3 inline review / thread resolution.

---

## 3. Worktree Isolation & Gate Sequencing

Always audit in an ephemeral detached worktree:
```bash
git fetch origin
git worktree add --detach /tmp/pr-<PR>-audit <headRefOid>
```

> [!IMPORTANT]
> **Strict Sequencing Invariant**: Pass 1 (`scripts/mutate`, unit tests, linters) MUST finish completely before any Pass 2 subagents are spawned. If a subagent reads files in `/tmp/pr-<PR>-audit` while `scripts/mutate` is running, it inspects mutated, broken code.
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

## 5. Pass 2: Parallel Auditing Subagents (Tier 2 Only)

Spawn `pr-contract-auditor` and `pr-test-verifier` subagents via `invoke_subagent`:
- **Model Tier**: Always use `Model: "flash"` per user rules.
- **Subagent Instruction**:
  - Enforce read-only inspection.
  - **Explicitly forbid running `scripts/mutate` or editing files in `/tmp/pr-<PR>-audit`**.
- **Collection & Teardown**:
  - Receive subagent reports.
  - Immediately kill completed subagents via `manage_subagents(Action="kill", ConversationIds=[...])`.

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
  --verdict CHANGES_REQUESTED \
  --scope "full PR" \
  --previously-raised "none" \
  --checks "- go test -race ...: PASS" \
  --not-verified "live Usenet E2E (test/e2e/) and crash consistency (test/crash/)."
```
*Note: Each finding must include `"path"`, `"line"`, `"severity"`, `"category"`, `"effort"`, `"title"`, `"body"`, and `"agent_prompt"`. `post-review.sh` automatically queries live `PRRT_...` thread IDs after creating the review, patches the `**Open threads:**` section and `threads_open:<n>` marker, and posts the `deep-pr-review` commit status.*
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
4. Re-check remaining unresolved threads (`resolve-thread.sh --list-unresolved <PR>`). Post the structured verdict comment and commit status via `approve-pr.sh`:
   ```bash
   ~/.gemini/skills/pr-watcher/scripts/approve-pr.sh <PR> <full-40-char-headRefOid> \
     --verdict APPROVED \
     --since <old-sha> \
     --scope "\`<old-short>..<new-short>\` (1 commit)" \
     --previously-raised "- \`PRRT_...\`: fixed in \`<sha>\`" \
     --checks "- go test -race ...: PASS" \
     --not-verified "live Usenet E2E (test/e2e/) and crash consistency (test/crash/)."
   ```

### Case C: Worktree & State Cleanup
Always remove the ephemeral worktree:
```bash
git worktree remove --force /tmp/pr-<PR>-audit
```
Update `state.json` with the latest status, `head_ref_oid`, timestamps, and resolved/open thread IDs.

---

## Common Traps & Antipatterns

| Mistake | Consequence | Prevention |
| :--- | :--- | :--- |
| **Leaving addressed review comments unresolved** | Stale open threads block merge readiness and obscure true remaining work | Run `resolve-thread.sh --list-unresolved <PR>` on every update and immediately resolve every addressed thread via `resolve-thread.sh` |
| **Skipping cron polls while a long task runs** | Author fixes on other PRs sit unverified with unresolved threads | Poll `poll-prs.sh` on every cron trigger and prioritize thread resolution on updated PRs |
| **Running `scripts/mutate` concurrently with subagents** | Subagents inspect corrupted/mutated code and hallucinate bugs | Enforce Pass 1 completion before spawning Pass 2 |
| **Leaking subagents across cycles** | Context window bloat, leaked background processes | Kill subagents immediately after receiving reports |
| **Using `IsDaemon: true` on monitoring cron** | Agent finishes turn and suspends execution | Always set `IsDaemon: false` on active monitoring tasks |
| **Full 15-angle fanout on 5-line doc/script fix** | 10x token waste and multi-minute latency | Use Tier 1 Lightweight review for docs, tests, and scripts |
| **Trusting authored `.spec` without adversarial probes** | Surviving mutant branches ship silently | Apply conjunct splitting and instance-to-ID degradation |
| **Attempting `gh pr review --approve` on own PRs** | Fails with GraphQL API error | Use `approve-pr.sh` (`gh pr comment`) as approval protocol |
