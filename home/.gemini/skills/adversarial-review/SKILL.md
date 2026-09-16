---
name: adversarial-review
description: Use to run a local adversarial red-team code review on uncommitted changes, a branch, or a commit, followed by skeptical triage and prioritized remediation using the receiving-code-review methodology.
---

# Adversarial Review

An end-to-end local review and remediation loop that couples aggressive adversarial inspection with skeptical engineering triage.

The workflow follows a two-phase Red Team / Blue Team pattern:

1. **Red Team (`deep-pr-review` subagent)**: Attacks the code without deference, running a 15-angle recall-biased review, 1-vote verification, and gap sweep to surface concrete defects, security vulnerabilities, concurrency bugs, and edge-case failures. Verified findings are saved to `/tmp/adversarial-review-findings.json`.
2. **Blue Team (Main orchestrator under `superpowers:receiving-code-review`)**: Skeptically audits every finding against codebase reality, rejects hallucinations, YAGNI additions, or out-of-context nitpicks, publishes a triage table, and drives prioritized Red-Green TDD remediation for accepted findings.

```
Phase 0  Target Resolution & Scope             Resolve target diff & language rules
Phase 1  Adversarial Review (Red Team)         Coordinator subagent runs deep-pr-review
Phase 2  Skeptical Reception (Blue Team)       Triage findings into ACCEPT / PUSHBACK
Phase 3  Prioritized TDD Remediation           Red-Green fix loop per accepted finding
Phase 4  Summary & Verification                Verification suite & final accounting
```

---

## Phase 0 — Target Resolution & Scope

Identify the exact scope of changes under review and gather relevant language rules.

### 1. Resolve Target Diff

Target resolution follows precedence: explicit commit → explicit branch → working tree.

```bash
# Explicit commit
git show <SHA>                                            # Single commit patch
git diff <SHA>^..<SHA>

# Branch against upstream/main
git diff @{upstream}...HEAD                               # Upstream branch diff
git diff main...HEAD                                      # Fallback when upstream is unset

# Working tree (uncommitted changes)
git diff HEAD                                             # Staged + unstaged combined
git diff --cached                                         # Staged changes only
git diff                                                  # Unstaged changes only
git ls-files --others --exclude-standard                  # Untracked files
```

Read any untracked files directly via `view_file` to ensure complete coverage.

### 2. Language & Runtime Telemetry

Inspect the target diff for language-specific rules:

- **Go Detection**: If `.go` or `go.mod` files are modified:
  - Extract target Go version: inspect the `go` directive in `go.mod` or run `go version`.
  - Locate Go review rules at `~/.gemini/skills/deep-pr-review/reference/go_rules.md`.
  - Pass the Go version and rules to the Red Team subagent in Phase 1 (covering Section 2 angle mappings, Section 5 verification matrix, Section 6 AI remediation guidelines, and Section 7 companion skills).
- **Other Languages**: Detect language conventions from project configuration files (`GEMINI.md`, `CLAUDE.md`, lint configs).

---

## Phase 1 — Adversarial Review (Red Team Subagent)

Dispatch an isolated coordinator subagent to conduct an aggressive, recall-biased code review using `deep-pr-review` in local mode.

### 1. Subagent Dispatch

Use `invoke_subagent` to spawn a fresh-context reviewer:

- **`TypeName`**: `"self"`
- **`Role`**: `"Red Team Review Coordinator"`
- **Prompt Requirements**:
  - The unified diff or exact git commands to inspect the target.
  - Project rules and guidelines from repo configuration files.
  - If Go is detected: target Go version and the text of `~/.gemini/skills/deep-pr-review/reference/go_rules.md`.
  - Mandate to run every angle in `deep-pr-review`'s Find phase (Angles A–O, as
    defined in its `method.md`), plus 1-vote verification and the gap sweep.
  - Run in **local mode**: skips the Eligibility and Post phases of `deep-pr-review`.
  - Output contract: write verified findings to `/tmp/adversarial-review-findings.json`.

### 2. Output Schema (`/tmp/adversarial-review-findings.json`)

The findings array must follow the CodeRabbit format:

```json
[
  {
    "path": "path/to/file.ext",
    "line": 142,
    "start_line": 138,
    "category": "🔒 Security Defenses",
    "severity": "🔴 Critical",
    "verdict": "CONFIRMED",
    "title": "Short descriptive title of the defect",
    "body": "Detailed failure scenario and technical explanation...",
    "sites": [
      {
        "file": "path/to/file.ext",
        "lines": "138-142",
        "role": "anchor",
        "note": "Root cause location"
      }
    ],
    "agent_prompt": "Precise instruction for fixing the issue..."
  }
]
```

The subagent reports back to the coordinator with the total finding count and a high-level summary.

---

## Phase 2 — Skeptical Code Review Reception (`receiving-code-review`)

The main orchestrator acts as the Blue Team, reading `/tmp/adversarial-review-findings.json` via `view_file` and evaluating each finding through the `superpowers:receiving-code-review` methodology.

### 1. Reception Discipline

- **Zero Performative Agreement**: Never utter pleasantries ("Great point!", "You're absolutely right!", "Thanks for catching that"). Ban all gratitude expressions; focus strictly on technical reality.
- **Codebase Reality Check**:
  - Is the finding technically sound for *this* specific codebase and architecture?
  - Does the proposed fix break existing callers, contracts, or platform compatibility?
  - Does it violate YAGNI (You Aren't Gonna Need It) by introducing unused complexity or speculative flexibility?
  - Did the reviewer lack runtime context, full test execution traces, or system invariants?

### 2. Triage Dispositions

Every finding must receive one of two dispositions:

- **`ACCEPT`**:
  - The finding identifies a genuine bug, security hole, race condition, data integrity issue, or worthwhile cleanup.
  - The fix is local, testable, and aligns with codebase architecture.
- **`PUSHBACK`**:
  - The finding is a false positive, rests on an invalid premise, is refuted by broader system invariants, breaks backward compatibility, or violates YAGNI.
  - Pushback must be supported by concrete technical rationale referencing code locations, test coverage, or architectural constraints.

### 3. Markdown Triage Table

Present the complete evaluation in a clean triage table:

| # | Finding / Title | File:Line | Severity | Disposition | Technical Rationale |
|---|---|---|---|---|---|
| 1 | Race condition on map access | `server.go:45` | 🔴 Critical | `ACCEPT` | Missing mutex lock allows concurrent map read/write in handler. |
| 2 | Add generic factory interface | `builder.go:12` | 🟡 Minor | `PUSHBACK` | Violates YAGNI. Single caller exists; factory adds indirection without requirement. |

---

## Phase 3 — Prioritized TDD Remediation

Address accepted findings sequentially following strict priority and Red-Green test discipline.

### 1. Fix Ordering

Remediate accepted items in strict order:

1. **Blocking & Security issues** (`🔴 Critical`): memory safety, authentication bypass, data corruption, crashes, deadlocks.
2. **Logic & Correctness bugs** (`🟠 Major`): calculation errors, nil dereferences, missing error checks, state leakage.
3. **Performance & Cleanup** (`🟡 Minor`, `🔵 Trivial`): allocations in hot loops, error wrapping, naming conventions.

### 2. Red-Green-Refactor Cycle

For each accepted finding:

1. **Red (Failing Test)**:
   - Write a unit test, integration test, or regression assertion demonstrating the defect described in the finding's failure scenario.
   - Run the test suite and confirm the test **FAILS** with the expected error.
2. **Green (Minimal Implementation)**:
   - Apply the minimal code change required to resolve the defect, leveraging the finding's `agent_prompt`.
   - Run the test and confirm it **PASSES**.
3. **Refactor & Regression Check**:
   - Clean up code structure while keeping tests green.
   - Run the broader project test suite to verify no regressions were introduced.
4. **Atomic Commit**:
   - Stage and commit the fix following Conventional Commits (`fix(<scope>): ...`).
   - Detail `Why:`, `Approach:`, and `Improvements:` in the commit message body.
   - Do NOT add any extra tags to the commit message.

---

## Phase 4 — Summary & Verification

Conclude the adversarial review with an accounting of results and comprehensive verification.

### 1. Verification Suite

Run the project's authoritative validation commands (build, lint, test):

```bash
# Examples:
go test -race ./...
cargo test
npm test
```

Confirm all checks pass with clean exit codes.

### 2. Final Report

Present the final status summary to the user:

- **Review Scope**: Commit, branch, or working tree analyzed.
- **Findings Accounting**:
  - Total findings surfaced by Red Team.
  - Accepted count (remediated).
  - Pushback count (defended with technical justification).
- **Remediation History**: List of generated commits with descriptions.
- **Verification Status**: Final test and validation suite outcome (`PASS` / `FAIL`).
