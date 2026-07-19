---
name: driftreaper
description: Audit docstrings for drift — claims that no longer match actual code behavior. Optional scope argument (file path, directory, or module name); without arguments, audits the entire workspace.
---

# driftreaper

Audit docstrings for SSOT violations (drift between documentation and code). Do NOT write production code — only fix docstrings or report findings.

## Step 1 — Determine scope

- **With argument**: audit only the specified file, directory, or module (using `view_file`, `list_dir`, `code_search`).
- **Without argument**: audit the full workspace. Start with public API surfaces (`pub fn`, `pub struct`, `pub trait`, `pub enum`, exported functions/types) using `code_search` or `find_by_name`.

## Step 2 — Extract docstring claims

For each public item in scope, read the docstring via `view_file` and extract verifiable claims. Claims fall into these categories:

| Category | Example | How to verify |
| -- | -- | -- |
| Return type / shape | "returns (Q, R) where Q has flux = identity()" | Read the function body using `view_file` |
| Precondition | "panics if center >= chain.len()" | Search for the assert/panic using `code_search` / `grep_search` |
| Postcondition | "after completion, canonical form is Mixed { center }" | Trace the code path in `view_file` |
| Invariant | "Q is isometric regardless of flux" | Check tests or mathematical reasoning |
| Delegation claim | "uses qr_block_sparse internally" | Search the body using `code_search` |
| Complexity | "O(n) additional cost" | Analyze the code structure in `view_file` |

Skip purely descriptive text — focus on **falsifiable claims** that a caller might depend on.

## Step 3 — Verify each claim

For each extracted claim:

1. **Read the code** using `view_file` that the claim describes. Follow control flow.
2. **Cross-reference with tests** using `code_search` — if a test exercises the claimed behavior, the claim is corroborated.
3. **Run a code-execution probe** using `run_command` when reading is not sufficient. Construct a minimal call and observe output.
4. **Classify the result**:
   - **Verified**: code matches claim
   - **Drifted**: code contradicts claim — the docstring is stale or wrong
   - **Untested**: claim is plausible but no test or code path directly confirms it
   - **Ambiguous**: docstring is vague enough to be technically correct but misleading

## Step 4 — Fix or report

- **Drifted**: fix the docstring using `replace_file_content` to match the code.
- **Untested**: report as a finding.
- **Ambiguous**: propose a more precise wording. Ask user via `ask_question` if meaning is unclear.

## Step 5 — Report

Present findings grouped by severity:

1. **Drifted** (fixed) — list each correction with `[file:line](file:///path/to/file#L10)`, old claim, new claim
2. **Untested** — claims that could not be verified
3. **Ambiguous** — vague docstrings with proposed rewording
4. Summary statistics: files audited, claims checked, drifts found

## Principles

- **Code is ground truth, not docstrings.**
- **Commit messages and PR descriptions are leads, never evidence.**
- **One drift fix per claim.** Do not batch unrelated fixes.
