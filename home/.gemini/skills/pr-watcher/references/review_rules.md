# The 4 Deep Review Rules & Adversarial Techniques

These 4 rules were distilled from reviewing over 60 production pull requests in GoNZBD. They address the most common blind spots of automated reviews: trusting authored test specs, missing sibling branches, comment-vs-caller drift, and unverified concurrency hypotheses.

---

## Rule 1: Mutate the Spec, Not Just the Code

Committed `.spec` files only prove that the author's hand-picked mutations fail. Reviewers must synthesize adversarial mutations against the diff in `/tmp/pr-<PR>-audit`:

### 1.1 Conjunct Splitting
For every compound condition `if A && B` or `if A || B`:
- Synthesize mutation replacing condition with `if A`.
- Synthesize mutation replacing condition with `if B`.
- **Verdict**: If either survives, one branch is untested or dead code.

### 1.2 Door Degradation (Instance-to-ID)
Whenever code calls an instance-bound method (`FooJob(j)`, `FooFrom(j, state)`, `HasJob(j)`, `YieldedJob(j)`, `CancelJob(j)`, `RemoveJob(ctx, j)`, `OccupyJob(ctx, j, fn)`):
- Mutate it back to its by-ID counterpart (`Foo(id)`, `Has(id)`, `Yielded(id)`, `Cancel(id)`, `Remove(ctx, id)`).
- **Verdict**: If the by-ID call passes the tests, the test suite has a concurrency/retry gap: it fails to test a competing retry instance whose state the by-ID call would clobber.

### 1.3 Boundary Shifting
- Shift length, counter, and offset boundaries by $\pm 1$ (`> 0` $\to$ `> 1`, `len(x) == 1` $\to$ `len(x) == 2`).
- Check if boundary mutations produce red test failures or pass silently.

### 1.4 Independent Oracle Verification
- Verify that test assertions compare against an **independent oracle**, not circular output from the SUT (e.g. asserting `wantPath := filepath.Join(cfg.AdminDir, "history.db")`, rather than `wantPath := realStore.Path()`).

---

## Rule 2: Mechanical Sibling Enumeration (Standing Design Rule 4)

> *"A fix justified by a rule is a claim about every site that rule governs."*

Whenever a PR replaces an old pattern $P_{\text{old}}$ with a new pattern $P_{\text{new}}$:

1. **Enclosing Function Full-Read**:
   - Read the entire enclosing function from top to bottom (`view_file`).
   - List every branch and exit path: happy path, hopeless path, cancellation path, error path.
   - Verify that NO sibling branch in the function still uses $P_{\text{old}}$ (e.g., if `runAssess` happy path uses `AdvanceFrom(j, ...)`, verify hopeless path doesn't still use `maybeFinalize(id, ...)`).

2. **Package & Pipeline Gate Enumeration**:
   - Run `git grep -n` across the touched package and adjacent pipeline packages for all sites checking the same gate or carrying the same identifier:
     - If adding a predicate (e.g. `handedOff(j)`) next to an intent check (`IntentPause`/`IntentCancel`), grep every intent check across the package.
     - If fencing a stage by `*job.Job` instance, grep in-flight structs/channels feeding or draining that stage to verify stale work cannot cross boundaries.

---

## Rule 3: Callee-Doc vs. Caller-Action & Removed Side-Effects

### 3.1 Callee-to-Caller Contract Cross-Check
For every function whose return value, error semantics, or doc comment is touched:
1. Enumerate all production callers:
   ```bash
   git grep -n '<FuncName>(' -- '*.go' ':!*_test.go'
   ```
2. Read each caller: Does its handling of the return value/error match what the callee's doc comment promises?
   - If a callee documents returning a routed fault, verify callers inspect `ErrFaultRouted` rather than swallowing or double-logging.

### 3.2 Removed Side-Effect Probe
For every deleted line, SQL statement, lock acquisition, or guard (e.g. removing a startup `VACUUM`):
1. Enumerate observable side effects on **Cold Start** (empty file, unmigrated DB, fresh job).
2. Enumerate observable side effects on **Warm / Steady-State** (already-migrated WAL DB reopened read-only, mid-flight job with active leases, retried download).
3. Verify that tests assert the warm steady-state path, not just cold initialization.

---

## Rule 4: Subagent Tier Routing & Executable Reproduction Proofs

### 4.1 Subagent Model Tier Selection
- Always default subagents (`pr-contract-auditor`, `pr-test-verifier`) to `Model: "flash"`.
- Use `flash_lite` for pure pattern-matching and citation verification.
- Only escalate to `pro` for large multi-file architectural redesigns requiring frontier reasoning.

### 4.2 Fail-Fast Worktree Sequencing Invariant
- **Strict Sequencing**: Pass 1 (`scripts/mutate`, test suites, static gates) runs sequentially in `/tmp/pr-<PR>-audit` **before** any Pass 2 subagents are spawned.
- **Why**: If a subagent reads a file while `scripts/mutate` is running, it inspects mutated, broken code.
- **Fail-Fast**: If Pass 1 encounters a compilation failure, broken static gate, or surviving mutation, halt immediately and report findings without wasting tokens on Pass 2.

### 4.3 Throwaway Proof Tests (`TestVerify...`)
- Never reject or accept a concurrency bug based solely on comments like *"cannot happen because X"*.
- Write a minimal reproduction test (`TestVerify_<Scenario>`) in the ephemeral worktree and run `go test -race -count=1 -run TestVerify_ <pkg>`.
- Capture the failure output as concrete evidence for the review.
- Delete the throwaway test before removing `/tmp/pr-<PR>-audit`.
