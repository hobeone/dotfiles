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
# Repo instructions — inject into every agent. AGENTS.md is the common name;
# REVIEW.md is a fallback. Most repos have the former and not the latter.
cat AGENTS.md 2>/dev/null || cat REVIEW.md 2>/dev/null || true
# Record the merge base now — the provenance check in Step 4 needs it.
BASE=$(git merge-base origin/<base-ref> HEAD) && echo "BASE=$BASE"
# Check for prior review comments to detect re-review
gh pr view <pr-number> --json comments --jq '.comments[].body' | grep -l "Code Review:" || true
```

**Re-review detection**: If prior review output exists in PR comments, switch to re-review mode:
- Suppress all 🟡 Nit findings
- Post 🔴 Important findings only
- Prepend summary with: "Re-review: nit findings suppressed. Showing new Important issues only."

**Repo-instruction injection**: If `AGENTS.md` (or `CLAUDE.md`/`GEMINI.md`, which are often symlinks to it) or `REVIEW.md` exists at repo root, inject its full contents as the highest-priority context block into the system prompt of every specialist agent below. It overrides all default guidance.

**Follow the topic-doc table.** Repo instructions frequently carry a table mapping changed areas to design docs ("read X before touching Y"). Read every doc whose trigger the diff matches, and treat those docs as binding on **fix recommendations**, not just on findings. A fix that contradicts a design doc is a defect in the review, not advice — and the doc that rules it out is usually one table lookup from the file you are already reading.

---

## Step 2: Run Quality Gates Locally

Check out the PR head ref, then run **the repo's own gates** if it has them — a wrapper script (`./scripts/run_tests.sh`, `make check`, `just test`) and any custom gate binaries under `scripts/`. Generic Go commands are the fallback for a repo with none:

```bash
gh pr checkout <pr-number>
./scripts/run_tests.sh      # or the repo's equivalent, per AGENTS.md
go test -race ./...         # must pass
go vet ./...                # must pass
golangci-lint run ./...     # capture issue count
```

**Report only metrics you actually ran, under the name the repo uses.** A repo with a custom coverage gate has a specific threshold and scope (per-function, per-diff, whole-file); a raw `go tool cover` percentage is a *different number* and reporting it as "coverage" is misleading. If you did not run a gate, mark it `— not run`, never ✅.

Record the command and its exit code, not a self-assessed verdict. Do **not** block the review on gate failures — report them.

---

## Step 3: Four Parallel Specialist Passes

Invoke all four passes concurrently using `invoke_subagent` (model: `flash`). Each agent receives the full diff, the full surrounding context of modified files, and the repo-instruction content (if present) as its highest-priority instruction block.

### The evidence contract (binds all four passes)

A reproduction you *wrote* is not a reproduction you *verified*. Well-formed prose naming real functions at real line numbers is generated just as easily for a scenario that cannot occur as for one that can — so every finding carries its provenance explicitly:

**Evidence class** — exactly one, stated per finding:

| Class | Means | Requires |
|---|---|---|
| `VERIFIED` | I ran something that demonstrates this | The command and its output, pasted |
| `READ` | I traced it in source, did not execute | Every file:line read to reach the conclusion |
| `INFERRED` | Reasoning from the code's shape | What would confirm or refute it |

`INFERRED` findings are still worth reporting. Reporting one *as* a reproduction is not.

**Reachability** — before describing any runtime scenario, establish that it can occur:

```bash
grep -rn --include='*.go' '\.MethodName(' . | grep -v '_test\.go'
```

Paste the result. If a scenario requires a caller and no caller exists, the finding is **LATENT** — say so and argue from the API surface (exported, invites misuse, a planned change will add callers) rather than describing a race that nothing can currently trigger. Latent findings are legitimate; fictional reproductions are not.

**Falsify external-tool claims — always.** Any claim about the behaviour of git, the standard library, or a dependency must be `VERIFIED` in a scratch directory with the command and output pasted, or dropped. These are seconds to test and expensive to get wrong: a confident, specific, false claim about tool behaviour is the single most likely thing to survive review and waste the author's time.

**Trace the class before writing up.** Once you have a root cause, grep for other instances of it. Report the class and list every site. The instance you noticed first is often not the worst one — a finding fixed only where it was spotted leaves the same bug live two functions away.

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
>
> **These filters check whether a claim is true, not whether it is well-written.** A finding citing real functions at real line numbers with a fluent scenario can still be fiction; that is the common failure, not the rare one. Do not let form stand in for substance.
>
> For each finding, apply these filters:
>
> 1. **Evidence bar**: Does the finding cite a specific `file:line` from the diff or its surrounding context? If not — discard.
> 2. **Provenance**: Does it carry an evidence class (`VERIFIED`/`READ`/`INFERRED`)? An unclassed finding is `INFERRED` — relabel it, do not discard it.
> 3. **Reachability**: If the finding describes a runtime scenario, does it show the call sites that make it reachable? If no caller exists, reclassify as LATENT and rewrite the rationale from the API surface. Do not keep a scenario that cannot occur.
> 4. **External-tool claims**: If the finding rests on how git, the stdlib, or a dependency behaves, is that `VERIFIED` with pasted output? If not, drop that premise. **Keep the finding if its conclusion survives on other grounds** — a true conclusion reached via a false premise is worth reporting with the premise corrected, and is one of the more valuable things a review produces. Separate the two rather than discarding both.
> 5. **Fix legality**: Does any recommended fix contradict a repo design doc? If so, replace the recommendation — a fix the repo's own docs forbid is a defect in the review.
> 6. **De-duplication**: If two agents found the same underlying issue, keep the finding with better evidence. Merge the reproduction details.
>
> **Provenance check — mandatory before ranking, for every survivor.** Using the merge base recorded in Step 1:
>
> ```bash
> git show $BASE:<file> | sed -n '<region>p'
> ```
>
> If the defective code, or the missing guard, is already present at `$BASE`, the finding is 🟣 **Pre-existing** — regardless of whether this PR touched nearby lines. Touching a file does not make its existing bugs yours. Paste the base-branch excerpt as evidence.
>
> You may not report '🟣 Pre-existing: None' unless you ran this for every finding. An empty pre-existing column is itself a claim and carries the same evidence burden as any other. Reporting a pre-existing defect as newly introduced sends the author looking for a regression they did not cause; it also misstates what the PR is responsible for.
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

| Location | Issue | Evidence | Reproduction |
|---|---|---|---|
| `pkg/file.go:L42` | Description | `VERIFIED` / `READ` / `INFERRED` / `LATENT` | Concrete attack/interleaving/scenario — or, for LATENT, why the API invites it and what would make it reachable |

---

#### 🟡 Nit (capped at 5; plus N similar)

- `pkg/file.go:L88` — description

---

#### 🟣 Pre-existing (not introduced by this PR)

- `pkg/file.go:L12` — description (present at merge base `<sha>`)

<!-- If this section is empty, the provenance check still ran. Say so:
     "Pre-existing: none — all findings confirmed absent at merge base <sha>."
     Do not print a bare "None". -->

---

#### ⚙️ Quality Gates

Report the command actually run. `— not run` is an acceptable, and required,
entry for anything skipped.

| Gate | Command | Result |
|---|---|---|
| Repo suite | `./scripts/run_tests.sh` | ✅ exit 0 / ❌ exit N / — not run |
| Race | `go test -race ./...` | ✅ PASS / ❌ FAIL / — not run |
| Vet | `go vet ./...` | ✅ PASS / ❌ FAIL / — not run |
| Lint | `golangci-lint run` | N issues / — not run |
| Coverage | *(the repo's own gate, named)* | its verdict / — not run |

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
- [ ] Checked for `AGENTS.md` / `REVIEW.md` at repo root and injected if present.
- [ ] Read every design doc whose trigger the diff matches, per the repo's topic-doc table.
- [ ] Recorded the merge base for the provenance check.
- [ ] Detected re-review mode (prior review comment exists).
- [ ] Ran the repo's own gate script where one exists, plus the generic Go gates.
- [ ] All four specialist passes completed (Security, Concurrency, Logic, Quality).
- [ ] Every finding carries an evidence class; none dressed an `INFERRED` claim as a reproduction.
- [ ] Every runtime scenario has its call sites shown, or is labelled LATENT.
- [ ] Every external-tool claim was executed in a scratch dir, or dropped.
- [ ] Grepped for other instances of each root cause before writing it up.
- [ ] Ran `git show $BASE:<file>` for **every** finding; the pre-existing column reflects that check, not an assumption.
- [ ] Checked each recommended fix against the repo's design docs.
- [ ] Quality-gate table reports only gates actually run, under the repo's own names.
- [ ] Nit cap enforced (≤5 inline nits).
- [ ] Posted finding as PR comment — did **not** edit the branch.

---

## Severity Reference

| Marker | Severity | Meaning |
|---|---|---|
| 🔴 | Important | Would break production, leak data, or introduce a race — fix before merge |
| 🟡 | Nit | Minor issue — worth fixing, not blocking |
| 🟣 | Pre-existing | Bug in base branch; not introduced by this PR — flag for awareness |
