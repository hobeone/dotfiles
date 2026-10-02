# PR Review Tier Routing & Adaptive Triage

To maintain deep review rigor without wasting compute or introducing multi-minute review latency on minor changes, PRs are automatically triaged into two execution tiers:

---

## Tier Comparison Matrix

| Attribute | Tier 1: Lightweight Fast-Path | Tier 2: Full Deep PR Review |
| :--- | :--- | :--- |
| **Applicable PR Types** | Documentation, pure tests/specs, developer scripts/CI, small bug fixes ($\le 30$ lines) outside core packages | Core pipeline subsystems, concurrency, state machines, complex refactors ($> 30$ lines) |
| **Target Directories** | `docs/`, `scripts/`, `testdata/`, non-pipeline packages without concurrency | `internal/app`, `internal/dispatch`, `internal/durability`, `internal/downloader`, `internal/assembler`, `internal/nntp`, `internal/par2`, `internal/job`, `internal/sched` |
| **Worktree Isolation** | Recommended (or checked-out branch) | **Mandatory** detached worktree in `/tmp/pr-<PR>-audit` |
| **Pass 1: Deterministic Gates** | Run relevant package tests, doc/citation checks, linters | Full suite: `go test -race`, all static gates, committed `.spec`, adversarial `.spec` expansion, sibling enumeration |
| **Pass 2: Subagent Fan-Out** | **Bypassed** (single-pass review in main context) | **Mandatory**: Concurrent `pr-contract-auditor` and `pr-test-verifier` (or 15-angle fanout) using `Model: "flash"` |
| **Adversarial Mutation** | Author's spec files only | Author's spec + adversarial conjunct splitting, instance-to-ID degradation, boundary shifting |
| **Expected Turnaround** | 30–60 seconds | 2–5 minutes |

---

## Detailed Classification Rules

### Tier 1: Lightweight Fast-Path Review

A PR qualifies for Tier 1 if **any** of the following hold:
1. **Documentation-only**: All modified files match `*.md`, `docs/*`, `README*`, or doc comment edits.
2. **Pure tests & specs**: All modified files match `*_test.go`, `*.spec`, `testdata/*`, or `test/*`, without altering production code.
3. **Scripts & Tooling**: All modified files match `scripts/*`, `.github/*`, or build configuration, with no runtime pipeline code touched.
4. **Minor Non-Core Fixes**: Additions + deletions $\le 30$ lines, and zero touched files in the core pipeline directories.

#### Tier 1 Review Procedure:
1. Fetch PR and create worktree or inspect diff.
2. Run relevant package tests (`go test -race -count=1 <pkg>`).
3. Run static gates:
   - For docs: `go run ./scripts/check_citations && go run ./scripts/check_doc_citations`.
   - For code/scripts: `golangci-lint run <pkg>`, `go run ./scripts/check_test_alignment --min-complexity=8`.
   - For specs: `go run ./scripts/mutate <spec>`.
4. Single-pass evaluation:
   - Verify doc claims adhere to Standing Design Rule 4 (no false universals, accurate citations).
   - Verify test additions actually discriminate (not vacuous).
5. Post inline findings or immediate approval comment.

---

### Tier 2: Full Deep PR Review

A PR triggers Tier 2 if **any** of the following hold:
1. Modifies production code in:
   - `internal/app/`
   - `internal/dispatch/`
   - `internal/durability/`
   - `internal/downloader/`
   - `internal/assembler/`
   - `internal/nntp/`
   - `internal/par2/`
   - `internal/job/`
   - `internal/sched/`
2. Modifies mutex locking, channel synchronization, goroutine lifecycles, or state machine transitions.
3. Modifies persistence formats, database schemas, or error recovery / retry paths.
4. Total additions + deletions exceed 30 lines in functional code.

#### Tier 2 Review Procedure:
1. Create detached ephemeral worktree `/tmp/pr-<PR>-audit` at `headRefOid`.
2. **Pass 1 (Sequential Deterministic Gates)**:
   - Race tests: `go test -race -count=1 <packages>`.
   - Committed mutation specs: `go run ./scripts/mutate <spec>`.
   - All static gates: `golangci-lint`, `check_citations`, `check_doc_citations`, `check_dup_comments`, `check_test_alignment --min-complexity=8`, `check_lock_io --all`.
   - Rule 1 Adversarial Spec Probing (conjunct splitting, door degradation).
   - Rule 2 Sibling Enumeration (enclosing function full read, pipeline-wide grep).
   - Rule 3 Callee-Doc vs Caller-Action & Removed Side-Effects.
   - **Fail-Fast**: If Pass 1 fails, halt and record findings without spawning Pass 2.
3. **Pass 2 (Parallel Subagent Auditing)**:
   - Spawn `pr-contract-auditor` and `pr-test-verifier` subagents using `Model: "flash"`.
   - Instruct subagents: read-only inspection only, do not run `scripts/mutate` or edit files.
   - Collect reports and immediately kill subagents (`manage_subagents kill`).
4. **Pass 3 (Publication, Resolution & State Update)**:
   - Format and post review findings via `post-review.sh` (or resolve fixed threads via GraphQL).
   - When all threads are resolved, post approval comment via `approve-pr.sh`.
   - Clean up worktree: `git worktree remove --force /tmp/pr-<PR>-audit`.
   - Update `state.json`.
