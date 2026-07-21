---
name: auditing-pull-requests
description: Use when reviewing open pull requests, analyzing code changes before merge, or performing structured adversarial code reviews.
---

# Auditing Pull Requests

Perform a deep, adversarial multi-pass code review of a GitHub PR. Four specialist agents run in parallel — each with a distinct attack mandate — then a verification pass filters false positives before posting a structured, severity-ranked summary as a PR comment.

**Do not modify the branch.** Output only as a GitHub PR comment.

---

## Workflow DAG

```
1. Fetch PR + Diff + Context
         │
2. Run Quality Gates (local: tests, vet, lint)
         │
3. ──[parallel]──────────────────────────────┐
   │  Pass A: Security Red-Team              │
   │  Pass B: Concurrency Auditor            │
   │  Pass C: Logic & Contract Verifier      │
   └─ Pass D: Go Quality Gate                │
                                             │
4. Verification / Merge / Rank ◄────────────┘
         │
5. Post Structured PR Comment
```

---

## Step 1: Fetch PR + Diff + Context

```bash
gh pr view <pr-number> --json title,body,commits,headRefName,baseRefName
gh pr diff <pr-number>
# Check for repo-local review config — inject into every agent if present
cat REVIEW.md 2>/dev/null || true
# Check for prior review comments to detect re-review
gh pr view <pr-number> --json comments --jq '.comments[].body' | grep -l "Code Review:" || true
```

**Re-review detection**: If prior review output exists in PR comments, switch to re-review mode:
- Suppress all 🟡 Nit findings
- Post 🔴 Important findings only
- Prepend summary with: "Re-review: nit findings suppressed. Showing new Important issues only."

**`REVIEW.md` injection**: If `REVIEW.md` exists at repo root, inject its full contents as the highest-priority context block into the system prompt of every specialist agent below. It overrides all default guidance.

---

## Step 2: Run Quality Gates Locally

Check out the PR head ref, then run:

```bash
gh pr checkout <pr-number>
go test -race ./...         # must pass
go vet ./...                # must pass
golangci-lint run ./...     # capture issue count
# Coverage delta (compare against base branch):
go test -coverprofile=pr.out ./... && go tool cover -func=pr.out
```

Record PASS/FAIL status and issue counts for the summary. Do **not** block the review on gate failures — report them.

---

## Step 3: Four Parallel Specialist Passes

Invoke all four passes concurrently using `invoke_subagent` (model: `flash`). Each agent receives the full diff, the full surrounding context of modified files, and the `REVIEW.md` content (if present) as its highest-priority instruction block.

### Pass A — Security Red-Team

**Persona**: You are a penetration tester. Your sole mandate is to find ways to break authorization, leak data, inject malicious input, or bypass validation. You are adversarial.

**Scope**:
- Input trust boundaries: all data crossing package/subsystem boundaries without sanitization
- Authorization/authentication bypass: missing checks, TOCTOU, privilege escalation paths
- Injection vectors: format strings, shell commands, SQL, template injection, path traversal
- Secret/credential exposure in logs, error messages, or serialized structs
- Cryptographic misuse: weak algorithms, static IVs, key material in code
- SSRF, open redirects, header injection (if applicable)

**Required output per finding**:
- Location: `file:line`
- Attack payload or input that triggers the issue (not naming inference — actual code path)
- What data or capability is exposed

**Discard if**: you cannot construct a concrete attack path from the diff or its context.

---

### Pass B — Concurrency Auditor

**Persona**: You are a concurrency engineer. Your sole mandate is to find race conditions, lock-ordering violations, and invariant violations under concurrent access.

**Scope**:
1. **Enumerate shared mutable state**: List every variable/field in the diff that is accessed from multiple goroutines.
2. **For each shared resource**: Determine whether reads and writes are protected by the same lock at all call sites.
3. **Construct interleaving proofs**: For each candidate race, describe a minimal goroutine interleaving (pseudo-code, ordered steps) that causes a visible failure.
4. **Invariant check**: State the invariant each critical section must maintain. Verify the diff cannot violate it.
5. **Channel safety**: Unbuffered sends without select, missing close, goroutine leaks.
6. **`sync.Once`, `sync.Map`, atomic ops**: Check for misuse patterns.

**Required output per finding**:
- Location: `file:line`
- The invariant that is violated
- A minimal interleaving scenario (e.g., "T1 enters Peek at L142 → T2 calls Push, locks write mutex, modifies `q.items` → T1 reads stale pointer")

**Discard if**: you cannot write the interleaving steps — suspicion alone is not a finding.

---

### Pass C — Logic & Contract Verifier

**Persona**: You are a formal code reviewer. Your mandate is to find logic errors, broken contracts between callers and callees, and broken edge cases.

**Scope**:
- **Pre/post conditions**: For each modified function, state what the caller must guarantee (pre) and what the function must guarantee (post). Check if the diff can violate either.
- **Off-by-one, nil dereference, integer overflow**: On all new arithmetic and slice indexing.
- **Error handling**: Swallowed errors, errors not propagated with `%w`, error path that leaves state inconsistent.
- **State machine correctness**: Queue, assembler, downloader lifecycle state transitions — verify no illegal state is reachable from the diff.
- **Interface contracts**: Any callers of modified interfaces — are their assumptions still valid?
- **Regression risk**: Could this change break callers not in the diff?

**Required output per finding**:
- Location: `file:line`
- The contract or invariant being violated
- A concrete scenario or input that triggers the failure

---

### Pass D — Go Quality Gate

**Scope** (existing audit categories, now in a focused pass):

- **Idiomatic Go**: Standard library preference (`slices.Equal`, `min`/`max` builtins, `errors.Is/As`, `context` propagation). Flag use of `reflect` where stdlib suffices.
- **Test coverage**: New/modified functions without tests — flag as 🟡 Nit unless they are trivial getters or unexported helpers with an `//nocover:` comment.
- **Commit hygiene**: Conventional Commits format (`feat(pkg): ...`, `fix(queue): ...`). Subject documents *what*, body documents *how* and *why*. Flag violations.
- **Documentation drift**: If a modified function's godoc no longer matches its behavior, flag as 🟡 Nit.
- **`go.mod` / `go.sum`**: Unexpected new dependencies.

**Cap**: Report at most **5** 🟡 Nit findings. If more exist, say "plus N similar nits" in the summary — do not post them inline.

---

## Step 4: Verification / Merge / Rank

After all four passes complete, run a synthesis pass (`pro` model):

> "You are a senior reviewer. You have received findings from 4 specialist agents.
> For each finding, apply these filters:
>
> 1. **Evidence bar**: Does the finding cite a specific `file:line` from the diff or its surrounding context? If not — discard.
> 2. **Reproducibility**: Does the finding include a concrete attack payload, interleaving, or violation scenario? If the reasoning is purely from naming or convention inference — discard.
> 3. **De-duplication**: If two agents found the same underlying issue, keep the finding with better evidence. Merge the reproduction details.
>
> After filtering, rank survivors:
> - 🔴 Important: Would break functionality in production, leak data, introduce a data race, or block rollback.
> - 🟡 Nit: Style, naming, non-idiomatic Go — worth fixing, not blocking.
> - 🟣 Pre-existing: Bug present in the base branch; not introduced by this PR.
>
> Apply nit cap: max 5 inline nit findings. Remainder → summary count only."

---

## Step 5: Post Structured PR Comment

```bash
gh pr comment <pr-number> --body "$(cat <<'EOF'
### 🔍 Code Review: PR #<N> — <Title>

**Summary**: X 🔴 Important · Y 🟡 Nit · Z 🟣 Pre-existing

---

#### 🔴 Important

| Location | Issue | Reproduction |
|---|---|---|
| `pkg/file.go:L42` | Description | Concrete attack/interleaving/scenario |

---

#### 🟡 Nit (capped at 5; plus N similar)

- `pkg/file.go:L88` — description

---

#### 🟣 Pre-existing (not introduced by this PR)

- `pkg/file.go:L12` — description (exists on base branch)

---

#### ⚙️ Quality Gates

| Gate | Result |
|---|---|
| `go test -race ./...` | ✅ PASS / ❌ FAIL |
| `go vet ./...` | ✅ PASS / ❌ FAIL |
| `golangci-lint run` | ✅ N issues / ❌ N issues |
| Coverage delta | +/-N% |

---

#### 📋 Commit Hygiene

- [ ] All commits follow Conventional Commits (`type(scope): description`)
- [ ] Commit bodies document *what*, *how*, and *realized benefit*

EOF
)"
```

---

## Quick Reference Checklist

- [ ] Fetched PR diff and surrounding context for modified files.
- [ ] Checked for `REVIEW.md` at repo root and injected if present.
- [ ] Detected re-review mode (prior review comment exists).
- [ ] Ran `go test -race ./...`, `go vet ./...`, `golangci-lint run ./...` on PR head.
- [ ] All four specialist passes completed (Security, Concurrency, Logic, Quality).
- [ ] Verification pass discarded findings lacking `file:line` citation or concrete reproduction.
- [ ] Nit cap enforced (≤5 inline nits).
- [ ] Posted finding as PR comment — did **not** edit the branch.

---

## Severity Reference

| Marker | Severity | Meaning |
|---|---|---|
| 🔴 | Important | Would break production, leak data, or introduce a race — fix before merge |
| 🟡 | Nit | Minor issue — worth fixing, not blocking |
| 🟣 | Pre-existing | Bug in base branch; not introduced by this PR — flag for awareness |
