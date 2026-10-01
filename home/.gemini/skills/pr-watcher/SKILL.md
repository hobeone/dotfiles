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
Poll open PRs using the helper script:
```bash
~/.gemini/skills/pr-watcher/scripts/poll-prs.sh
```
Read `~/.gemini/jetski/scratch/pr_watcher/state.json`:
- **Merged PRs**: PR in `state.json` with status `APPROVED` that no longer appears in `gh pr list` $\to$ mark `MERGED` in `state.json`.
- **Unchanged PRs**: PR whose `headRefOid` matches `head_ref_oid` in `state.json` and has no new comments $\to$ skip.
- **New or Updated PRs**: PR whose `headRefOid` is new or changed $\to$ proceed to triage.

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
  - Applicable: Changes in `internal/app`, `internal/dispatch`, `internal/durability`, `internal/downloader`, `internal/assembler`, `internal/nntp`, `internal/par2`, `internal/job`, or any concurrency/mutex/lifecycle changes.
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
   go run ./scripts/check_test_alignment
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

### Case A: New or Unaddressed Issues Found
Format findings into JSON and post inline review using `post-review.sh`:
```bash
~/.gemini/skills/deep-pr-review/scripts/post-review.sh <PR> <findings.json>
```
*Note: Each finding must include `"path"`, `"line"`, `"severity"`, `"category"`, `"effort"`, `"title"`, `"body"`, and `"agent_prompt"`.*

### Case B: Incremental Commit Resolves Open Threads
1. Verify that the incremental commit fixes the identified defect.
2. Resolve the corresponding review threads via GraphQL:
   ```bash
   ~/.gemini/skills/pr-watcher/scripts/resolve-thread.sh <threadId1> <threadId2> ...
   ```
3. Check remaining unresolved threads. If 0 remain:
   ```bash
   ~/.gemini/skills/pr-watcher/scripts/approve-pr.sh <PR> <headRefOid> <evidence_file_or_summary>
   ```
   *(GitHub GraphQL API blocks `gh pr review --approve` when reviewing own PRs; the standardized approval issue comment is the authoritative merge readiness signal).*

### Case C: Worktree & State Cleanup
Always remove the ephemeral worktree:
```bash
git worktree remove --force /tmp/pr-<PR>-audit
```
Update `state.json` with the latest status, `head_ref_oid`, timestamps, and thread IDs.

---

## Common Traps & Antipatterns

| Mistake | Consequence | Prevention |
| :--- | :--- | :--- |
| **Running `scripts/mutate` concurrently with subagents** | Subagents inspect corrupted/mutated code and hallucinate bugs | Enforce Pass 1 completion before spawning Pass 2 |
| **Leaking subagents across cycles** | Context window bloat, leaked background processes | Kill subagents immediately after receiving reports |
| **Using `IsDaemon: true` on monitoring cron** | Agent finishes turn and suspends execution | Always set `IsDaemon: false` on active monitoring tasks |
| **Full 15-angle fanout on 5-line doc/script fix** | 10x token waste and multi-minute latency | Use Tier 1 Lightweight review for docs, tests, and scripts |
| **Trusting authored `.spec` without adversarial probes** | Surviving mutant branches ship silently | Apply conjunct splitting and instance-to-ID degradation |
| **Attempting `gh pr review --approve` on own PRs** | Fails with GraphQL API error | Use `approve-pr.sh` (`gh pr comment`) as approval protocol |
