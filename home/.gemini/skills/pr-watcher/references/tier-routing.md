# PR Review Tier Routing & Adaptive Triage

To maintain deep review rigor without wasting compute or introducing multi-minute review latency on minor changes, PRs are automatically triaged into two execution tiers:

---

## Tier Comparison Matrix

| Attribute | Tier 1: Lightweight Fast-Path | Tier 2: Full Deep PR Review |
| :--- | :--- | :--- |
| **Applicable PR Types** | Pure documentation, markdown updates, license/typos, comment-only diffs | **All code changes**: any PR modifying Go code (production or test), build scripts, CI tooling, or runtime behavior |
| **Target Directories** | `docs/`, `*.md`, `README*`, `LICENSE*` (strictly no `.go` files) | Any `.go` file in the repo (`internal/*`, `cmd/*`, `test/*`), `scripts/*`, `.github/*` |
| **Worktree Isolation** | Recommended (or checked-out branch) | **Mandatory** detached worktree in `/tmp/pr-<PR>-audit` |
| **Pass 1: Deterministic Gates** | Run doc/citation checks (`check_citations`, `check_doc_citations`) | Full suite: `go test -race`, all static gates, committed `.spec`, independent adversarial `.spec` synthesis, sibling enumeration |
| **Pass 2: Swarm Audit** | **Bypassed** (single-pass review in main context) | **Mandatory 3-Lane Swarm**: Persistent 3-lane swarm on `<PRIMARY_REVIEW_MODEL>` (`rev-1`, `rev-2`, `rev-3`) with automatic in-place failover to `<PRO_FAILOVER_MODEL>` on quota exhaustion (see `SKILL.md` Active Model Configuration) |
| **Adversarial Mutation** | Bypassed (docs only) | **Mandatory Independent Probes**: Reviewers construct novel `.spec` mutations attacking implicit invariants and boundaries; never rely solely on author's `.spec` |
| **Callee & Downstream Audit** | N/A | **Mandatory**: End-to-end tracing into callers, intermediate handlers, fault handlers, and downstream dependency engines (`par2engine`, `rarengine`, etc.) |
| **Expected Turnaround** | 30–60 seconds | 2–5 minutes |

---

## Detailed Classification Rules

### Tier 1: Lightweight Fast-Path Review

A PR qualifies for Tier 1 **only if** one of the following holds:
1. **Documentation-only**: All modified files match `\.(md|txt|rst|adoc)$`, `^docs/`, `^LICENSE`, or `README*`. Zero `.go` code files, test files, or scripts modified.
2. **Comment-only diffs**: `git diff -U0` contains strictly comment lines (`//`, `/*`, `*`) or whitespace changes across the PR.

#### Tier 1 Review Procedure:
1. Fetch PR and inspect diff or create worktree.
2. Run doc and citation gates:
   ```bash
   go run ./scripts/check_citations && go run ./scripts/check_doc_citations
   ```
3. Verify doc claims adhere to Standing Design Rule 4 (no false universals, accurate citations from source).
4. Post inline findings or immediate approval comment with commit status.

---

### Tier 2: Full Deep PR Review

**Any PR modifying Go code (including tests, testdata, single-file bug patches), build/CI logic, or runtime behavior triggers Tier 2.** There are NO line-count exemptions (a 1-line change can introduce a data race or nil dereference) and NO test-only exemptions (tests require verification against false positives and mutant survival).

#### Tier 2 Review Procedure:
1. Create detached ephemeral worktree `/tmp/pr-<PR>-audit` at `headRefOid`:
   ```bash
   git fetch origin main pull/<PR>/head
   git worktree add --detach /tmp/pr-<PR>-audit <headRefOid>
   ```
2. **Pass 1 (Sequential Deterministic Gates)**:
   - Race tests: `go test -race -count=1 <touched_packages>`.
   - Committed mutation specs: `go run ./scripts/mutate <spec>`.
   - All static gates: `golangci-lint`, `check_citations`, `check_doc_citations`, `check_dup_comments`, `check_test_alignment --min-complexity=8`, `check_lock_io --all`, `check_test_doubles`.
   - Rule 2 Sibling Enumeration: Enclosing function full read, pipeline-wide grep for matching patterns/callers.
   - Rule 3 Callee-Doc vs Caller-Action & Removed Side-Effects.
   - **Fail-Fast**: If Pass 1 fails, halt and record findings without spending swarm compute.
3. **Pass 2 (3-Lane Adversarial Swarm Auditing on `<PRIMARY_REVIEW_MODEL>`)**:
   - Dispatch to 3 persistent swarm workers pinned to `<PRIMARY_REVIEW_MODEL>` (with in-place failover to `<PRO_FAILOVER_MODEL>` if primary quota exhausts, as defined in `SKILL.md` Active Model Configuration):
     - **Lane 1 (`rev-1`) — Core Invariants & Concurrency**: Audit state machine transitions, mutex locking, channel synchronization, goroutine lifecycles, and panic/error routing.
     - **Lane 2 (`rev-2`) — Downstream Consumers & Dependency Engines**: Trace callee side-effects, intermediate handlers, fault handlers, and downstream dependency engines (`par2engine`, `rarengine`, post-processing stages).
     - **Lane 3 (`rev-3`) — Independent Adversarial Mutation & Rule 4**: Synthesize novel mutation specs (`/tmp/adv.spec`) attacking unstated invariants, boundary shifts, door degradation, and conjunct splitting (do NOT rely solely on author's `.spec`); verify Rule 4 doc/comment citations pipeline-wide.
   - Enforce the **Mandatory 4-Gate Active Refutation & Calibration Protocol** across all lanes.
   - Drain the swarm board (`read_board`) immediately upon wakeup.
4. **Pass 3 (Publication, Resolution & State Update)**:
   - Resolve any fixed review threads via GraphQL (`resolve-thread.sh`).
   - Publish formal review and commit status via `post-review.sh <PR> <findings.json> --expect-head <sha> --verdict <APPROVED|CHANGES_REQUESTED|COMMENTED>`.
   - Clean up worktree: `git worktree remove --force /tmp/pr-<PR>-audit`.
   - Update `state.json` (including `reviewModels`, `lastReviewedHeadOid`, `verdict`, `reviewUrl`, and `openThreadIds`) and output the Pacific Time status table.
