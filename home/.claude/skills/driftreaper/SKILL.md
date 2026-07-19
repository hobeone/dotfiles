---
name: driftreaper
description: Audit docstrings for drift — claims that no longer match actual code behavior. Optional scope argument (file path, directory, or module name); without arguments, audits the entire workspace.
---

# driftreaper

Audit docstrings for SSOT violations (drift between documentation and code). Do NOT write production code — only fix docstrings or report findings.

## Step 1 — Determine scope

- **With argument**: audit only the specified file, directory, or module
- **Without argument**: audit the full workspace. Start with public API surfaces (`pub fn`, `pub struct`, `pub trait`, `pub enum`) since those are what callers and agents read.

## Step 2 — Extract docstring claims

For each public item in scope, read the docstring and extract verifiable claims. Claims fall into these categories:

| Category | Example | How to verify |
| -- | -- | -- |
| Return type / shape | "returns (Q, R) where Q has flux = identity()" | Read the function body or the callee it delegates to |
| Precondition | "panics if center >= chain.len()" | Search for the assert/panic in the body |
| Postcondition | "after completion, canonical form is Mixed { center }" | Trace the code path to the set_canonical_form call |
| Invariant | "Q is isometric regardless of flux" | Check tests or mathematical reasoning |
| Delegation claim | "uses qr_block_sparse internally" | Grep the body for the call |
| Complexity | "O(n) additional cost" | Analyze the code structure |

Skip purely descriptive text ("This function does X") — focus on **falsifiable claims** that a caller might depend on.

## Step 3 — Verify each claim

For each extracted claim:

1. **Read the code** that the claim describes. Follow the actual control flow, not what the docstring says the flow is.
2. **Cross-reference with tests** — if a test exercises the claimed behavior, the claim is corroborated (though not proven; the test itself could be trivial). If no test covers the claim, note this as an untested claim.
3. **Run a code-execution probe when reading is not sufficient.** If the claim depends on a third-party library's behavior (`mdformat.text`, `serde_json::from_str`, …), on a refactor that delegated logic to an external module, or on any path where the visible local code does not by itself prove or disprove the claim, construct a minimal call and observe the output. Treat commit messages, PR descriptions, and even prior in-house implementations as leads, never as evidence — squash-merged PRs in particular concatenate intermediate states whose behavior differs from the final shape, and reading the message in isolation will mislead. The chain of authority is: **execution > current code > tests > docstring > commit message / PR description**.
4. **Classify the result**:
   - **Verified**: code matches claim, optionally backed by a test or a successful execution probe
   - **Drifted**: code contradicts claim — the docstring is stale or wrong
   - **Untested**: claim is plausible but no test or code path directly confirms it — flag for manual review
   - **Ambiguous**: docstring is vague enough to be technically correct but misleading — suggest a more precise wording

## Step 4 — Fix or report

- **Drifted**: fix the docstring to match the code (or flag if the code should be fixed to match the docstring — that is a bug, not drift). For each fix, state what the old claim was and what the corrected claim is.
- **Untested**: report as a finding. These are candidates for contract test elevation via `/bug-to-contract`.
- **Ambiguous**: propose a more precise wording. Do not change without user confirmation if the intended meaning is unclear.

## Step 5 — Report

Present findings grouped by severity:

1. **Drifted** (fixed) — list each correction with file:line, old claim, new claim
2. **Untested** — claims that could not be verified by code or tests
3. **Ambiguous** — vague docstrings with proposed rewording
4. Summary statistics: files audited, claims checked, drifts found

## Scope guidance

For large codebases, prioritize:

1. **Functions that other modules call** — drift here propagates farthest
2. **Recently changed files** (`git log --since="2 weeks ago" --name-only`)
3. **Functions with complex return types** (tuples, Result, custom structs) — these are most likely to have stale shape/invariant claims
4. **Decomposition / factorization functions** — their output properties (flux, direction, rank, isometry) are subtle and callers depend on exact claims

## Principles

- **Code is ground truth, not docstrings.** When code and docstring disagree, the code is almost always right and the docstring is stale. The exception is when the docstring represents an intentional spec and the code has a bug — but that requires explicit user confirmation.
- **Commit messages, PR descriptions, and code comments about history are leads, never evidence.** They describe what an author *intended* or what an *intermediate step* did. Squash-merged PRs in particular concatenate the trajectory of multiple intermediate commits whose behavior differs from the final shape — reading the message in isolation will mislead. Use them only to locate where to look in the code, never to conclude what the code does.
- **When local code delegates to a third-party library or to a refactor whose final shape is non-obvious, supplement reading with execution.** Construct a minimal call and observe the output. Reading alone is insufficient when behavior is owned by an external module — the chain of authority is execution > current code > tests > docstring > commit message.
- **One drift fix per claim.** Do not batch unrelated fixes. Each correction should be independently reviewable.
- **Don't add docstrings.** This skill audits and fixes existing docstrings. Adding docstrings to undocumented functions is a separate task.
