---
name: adversarial-review-loop
description: Use to run an iterative multi-turn Actor-Critic review loop between an adversarial red-team reviewer (deep-pr-review) and a skeptical remediator (receiving-code-review) until findings converge to zero or max iterations are reached.
---

# Adversarial Review Loop

An iterative, multi-turn Actor-Critic review and remediation system that couples an adversarial Red Team Critic with a skeptical Blue Team Actor until the codebase converges to zero actionable defects or reaches consensus.

## Overview & Convergence Model

The workflow executes an iterative feedback loop between two opposing roles:

1. **The Critic (Red Team — `deep-pr-review` subagent)**: Attacks the codebase with recall-biased scrutiny across 12 analytical angles, 1-vote verification, and gap sweeps to identify security vulnerabilities, concurrency bugs, edge-case failures, and architectural regressions. Findings are written to `/tmp/adversarial-review-loop-findings.json`.
2. **The Actor (Blue Team — Orchestrator under `superpowers:receiving-code-review`)**: Skeptically audits each finding against live codebase reality, rejects hallucinations and YAGNI bloat without performative agreement, triages items into `ACCEPT` or `PUSHBACK`, and applies atomic Red-Green TDD fixes for accepted defects.
3. **The Feedback Loop**: Each remediation turn produces new atomic commits, updating the target diff. The loop feeds the updated diff back into the Critic for a fresh evaluation round, verifying that fixes resolve issues without introducing secondary defects or regressions.

```
                    ┌───────────────────────────────┐
                    │ Phase 0: Target & Telemetry   │
                    └───────────────┬───────────────┘
                                    │
                        ┌───────────▼───────────┐
                        │   Iteration = 1..N    │◄────────────────────────┐
                        └───────────┬───────────┘                         │
                                    │                                     │
                    ┌───────────────▼───────────────┐                     │
                    │ Sub-phase 1.1: Critic Turn    │                     │
                    │ (Red Team: deep-pr-review)    │                     │
                    └───────┬───────────────┬───────┘                     │
            0 findings      │               │ > 0 findings                │
     ┌──────────────────────┘               ▼                             │
     │                      ┌───────────────────────────────┐             │
     │                      │ Sub-phase 1.2: Actor Turn     │             │
     │                      │ (receiving-code-review)       │             │
     │                      └───────┬───────────────┬───────┘             │
     │            All PUSHBACK      │               │ >= 1 ACCEPT         │
     │     ┌────────────────────────┘               ▼                     │
     │     │                        ┌───────────────────────────────┐     │
     │     │                        │ Sub-phase 1.3: TDD Fixes      │     │
     │     │                        │ Red-Green test + fix commit   │     │
     │     │                        └───────────────┬───────────────┘     │
     │     │                                        │                     │
     │     │                        ┌───────────────▼───────────────┐     │
     │     │                        │ Sub-phase 1.4: Progression    │─────┘
     │     │                        │ i++ (if i <= max_iterations)  │
     │     │                        └───────────────┬───────────────┘
     │     │                                        │ i > max
     ▼     ▼                                        ▼
  ┌───────────────────────────────────────────────────────────┐
  │ Phase 2: Final Convergence Accounting & Verification      │
  └───────────────────────────────────────────────────────────┘
```

### Termination Conditions

The loop terminates when any of the following three conditions is met:

1. **Full Convergence (`findings.length == 0`)**:
   - The Critic identifies zero actionable defects in the current diff.
   - Clean sweep across all 12 analytical review angles.
2. **Consensus Pushback (All findings `PUSHBACK`)**:
   - The Critic returns findings, but the Actor refutes every item with technical justification adhering to `receiving-code-review` principles (e.g., invalid assumptions, non-issue guarded by existing system invariants, or YAGNI violations).
   - Because no findings are accepted, no code changes occur, preventing unproductive cycles.
3. **Max Iterations Exhausted (`iteration == max_iterations`)**:
   - The loop counter reaches `max_iterations` (default: 3).
   - Halts execution on contentious or complex diffs to present residual findings for human developer intervention.

---

## Phase 0 — Target Resolution & Setup

Establish review scope, clear temporary artifacts, and gather language telemetry before launching the loop.

### 1. Resolve Target Diff

Determine the review target using precedence: explicit commit → explicit branch → working tree.

```bash
# Explicit commit
git show <SHA>
git diff <SHA>^..<SHA>

# Branch against upstream/main
git diff @{upstream}...HEAD                               # Upstream tracking branch
git diff main...HEAD                                      # Fallback when upstream is unset

# Working tree (uncommitted changes)
git diff HEAD                                             # Staged + unstaged combined
git diff --cached                                         # Staged changes only
git diff                                                  # Unstaged changes only
git ls-files --others --exclude-standard                  # Untracked files
```

Read untracked files directly via `view_file` to ensure full context.

### 2. Reset Loop State

Clean up any stale findings artifact from earlier runs:

```bash
rm -f /tmp/adversarial-review-loop-findings.json
```

### 3. Language & Runtime Telemetry

Inspect target files for language-specific rules:

- **Go Detection**: If `.go` or `go.mod` files are modified:
  - Extract target Go version: inspect `go` directive in `go.mod` or run `go version`.
  - Read Go review rules from `~/.gemini/skills/deep-pr-review/reference/go_rules.md`.
  - Pass the target Go version and `go_rules.md` (covering Section 2 angle mappings, Section 5 verification matrix, Section 6 AI remediation guidelines, and Section 7 companion skills) to the Critic in Phase 1.
- **Other Languages / Frameworks**: Inspect repository guidelines (`GEMINI.md`, `CLAUDE.md`, linter configs) for relevant style, lifecycle, and concurrency rules.

---

## Phase 1 — The Iterative Actor-Critic Loop

Initialize the iteration counter: `iteration = 1`, `max_iterations = 3`. Maintain an iteration history tracking findings, acceptances, and pushbacks across rounds.

Execute the following sub-phases while `iteration <= max_iterations`:

```
=== ITERATION <iteration> / <max_iterations> ===
```

### Sub-phase 1.1: Critic Turn (Red Team Subagent)

Dispatch an isolated coordinator subagent running `deep-pr-review` in local mode against the target diff at the start of this iteration.

#### 1. Subagent Invocation

Invoke the reviewer using `invoke_subagent`:

- **`TypeName`**: `"self"`
- **`Role`**: `"Red Team Critic - Iteration <iteration>"`
- **Prompt Requirements**:
  - State the current iteration number and mandate: rigorously attack the diff without deference.
  - Provide the exact git diff command or unified diff corresponding to the target scope.
  - If Go is detected, supply the target Go version and `~/.gemini/skills/deep-pr-review/reference/go_rules.md`.
  - Include relevant repo rules from `GEMINI.md` or `CLAUDE.md`.
  - Mandate execution of the 12-angle review, 1-vote verification, and gap sweep per `deep-pr-review`:
    - Angle A: Line-by-line diff scan (correctness, bounds, nil/null pointers)
    - Angle B: Caller & contract audit (signature changes, assumptions)
    - Angle C: Failure modes & edge cases (boundaries, error branches)
    - Angle D: Language pitfalls (goroutine/closure binding, type assertions)
    - Angle E: Performance & allocations (hot paths, leaks, complexity)
    - Angle F: Reuse & existing helpers (reinvented wheels)
    - Angle G: Modern idioms & stdlib (clean modern stdlib replacements)
    - Angle H: Altitude & architecture (layer violations, abstractions)
    - Angle I: Conventions & naming (idiomatic naming, clarity)
    - Angle J: Repo standards & rules (`GEMINI.md`/`CLAUDE.md` compliance)
    - Angle K: Concurrency & lifecycle (goroutine leaks, race conditions, locks)
    - Angle L: Error ergonomics & telemetry (wrapping, context propagation)
  - Run in **local mode**: do NOT post to GitHub.
  - **Output destination**: Write verified findings to `/tmp/adversarial-review-loop-findings.json`. If 0 defects are found, write an empty JSON array `[]`.

#### 2. Findings Schema (`/tmp/adversarial-review-loop-findings.json`)

The findings array follows the CodeRabbit format:

```json
[
  {
    "path": "pkg/auth/session.go",
    "line": 84,
    "start_line": 80,
    "category": "🔒 Security Defenses",
    "severity": "🔴 Critical",
    "verdict": "CONFIRMED",
    "title": "Unvalidated token expiry enables session replay",
    "body": "The token validation handler parses the claims but omits checking exp against time.Now()...",
    "sites": [
      {
        "file": "pkg/auth/session.go",
        "lines": "80-84",
        "role": "anchor",
        "note": "Missing expiration check"
      }
    ],
    "agent_prompt": "Add claims.VerifyExpiresAt(time.Now(), true) check and return ErrTokenExpired if invalid."
  }
]
```

#### 3. Immediate Convergence Check

Read `/tmp/adversarial-review-loop-findings.json` using `view_file`.

- **If findings count == 0**:
  - Record **Full Convergence** in the iteration log.
  - Exit the Actor-Critic loop immediately and proceed to **Phase 2**.

---

### Sub-phase 1.2: Actor Turn (Skeptical Reception via `receiving-code-review`)

The main orchestrator acts as the Blue Team Actor, reading the findings and skeptically triaging each item under the `superpowers:receiving-code-review` methodology.

#### 1. Reception Discipline

- **Zero Performative Agreement**: Banish all pleasantries ("Great point!", "You're right!", "Thanks for catching that"). Engage strictly on technical facts.
- **Codebase Reality Checks**:
  - Does the finding hold true when examining full caller trees, types, and invariants across the repo?
  - Does the proposed change break existing public APIs, interfaces, or platform compatibility?
  - Did the Critic hallucinate an uninvoked code path or miss an upstream check?
- **YAGNI Audit**:
  - Does the suggestion urge speculative generality (e.g. abstract interfaces, configurable strategies) for single-caller code?
  - If the feature or code is unneeded, remove it; do not over-engineer it.

#### 2. Classification

Assign each finding an explicit disposition:

- **`ACCEPT`**:
  - Concrete bug, security vulnerability, race condition, data corruption, or worthwhile simplification.
  - Aligns with codebase architecture and is verifiable via an automated test.
- **`PUSHBACK`**:
  - False positive, invalid assumption, refuted by external/surrounding invariants, breaks compatibility, or violates YAGNI.
  - **Requirement**: Must document technical rationale citing concrete files, line numbers, or architectural constraints.

#### 3. Consensus Termination Check

Evaluate the triaged findings for this iteration:

- **If ALL findings are classified as `PUSHBACK`**:
  - No changes are needed or justified.
  - Record **Consensus Pushback** in the iteration log.
  - Exit the Actor-Critic loop immediately and proceed to **Phase 2**.

---

### Sub-phase 1.3: Atomic TDD Remediation

If one or more findings are `ACCEPT`, remediate them sequentially using strict priority ordering and Red-Green TDD discipline.

#### 1. Priority Ordering

Remediate accepted items in strict order:

1. **Security & Blocking** (`🔴 Critical`): memory safety, auth bypass, race conditions, crashes, deadlocks.
2. **Logic & Correctness** (`🟠 Major`): data corruption, off-by-one, calculation bugs, error mishandling.
3. **Performance & Cleanups** (`🟡 Minor`, `🔵 Trivial`): hot-path allocations, standard library modernization, naming.

#### 2. Red-Green-Refactor Cycle per Finding

For each accepted finding:

1. **Red (Failing Test)**:
   - Write an automated test reproducing the exact failure scenario detailed in the finding.
   - Run the test and confirm it **FAILS** for the expected reason.
2. **Green (Minimal Fix)**:
   - Apply the targeted fix in the code (leveraging `agent_prompt`).
   - Run the test and confirm it **PASSES**.
3. **Refactor & Regression Verification**:
   - Clean up code structure while keeping all tests passing.
   - Run the full project test suite to guarantee zero regressions.
4. **Atomic Conventional Commit**:
   - Commit the test and fix together using Conventional Commits 1.0.0:
     ```bash
     git commit -m "fix(<scope>): <short description>

     Why:
     - <explanation of defect surfaced by Critic>

     Approach:
     - <technical description of test and fix>

     Improvements:
     - <delivered reliability or correctness outcome>"
     ```
   - Do NOT add any extra tags to the commit message.

---

### Sub-phase 1.4: Loop Progression

After remediating all accepted findings for this iteration:

1. Record completed iteration statistics:
   - Iteration number.
   - Total Critic findings.
   - Number of `ACCEPT` (fixed).
   - Number of `PUSHBACK` (refuted).
2. Clean `/tmp/adversarial-review-loop-findings.json`:
   ```bash
   rm -f /tmp/adversarial-review-loop-findings.json
   ```
3. Check loop bounds:
   - Increment `iteration = iteration + 1`.
   - If `iteration <= max_iterations`: Loop back to **Sub-phase 1.1** with the updated git diff.
   - If `iteration > max_iterations`: Terminate loop with status **Max Iterations Reached** and proceed to **Phase 2**.

---

## Phase 2 — Final Convergence Accounting

Once the loop terminates (via Full Convergence, Consensus Pushback, or Max Iterations), synthesize the complete audit trail and run project-wide verification.

### 1. Project Verification Suite

Execute the repository's verification commands (tests, race detectors, linter, formatting):

```bash
# Examples by ecosystem:
go test -race ./...
cargo test
npm test
git diff --check
```

Confirm all checks pass with clean exit codes.

### 2. Multi-Iteration Convergence Table

Render a comprehensive summary of all iterations in the loop:

| Iteration | Critic Findings | Accepted (Fixed) | Pushed Back | Status |
|:---:|:---:|:---:|:---:|---|
| 1 | 4 | 2 | 2 | Remediated (2 fixes committed) |
| 2 | 1 | 0 | 1 | Consensus Pushback |
| 3 | — | — | — | Skipped (Terminated at Iteration 2) |

### 3. Pushback Log

Document every refuted finding with the technical reasoning that justified pushback:

- **Iteration `<N>`, Finding #`<M>` (`<title>`)**:
  - *Location*: `<file>:<line>`
  - *Critic Claim*: Brief summary of the alleged defect.
  - *Actor Pushback*: Specific technical counter-evidence, citing line numbers, test assertions, or invariants explaining why the claim is invalid or unnecessary.

### 4. Convergence Status & Summary

Conclude with a clear statement of final outcome:

- **Termination Reason**: `Full Convergence (0 defects)` | `Consensus Pushback` | `Max Iterations Reached (<N>/<N>)`.
- **Commits Produced**: List of all atomic remediation commits created during the loop.
- **Verification Result**: Confirmation that the full test suite passed.
