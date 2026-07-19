---
name: debtreaper
description: Audit a test suite for structural debt — fixtures that trivialize the code under test, tautological differential assertions, implementation-locked or assertion-less tests, and name-claim mismatches. Companion to driftreaper / breachreaper.
---

# debtreaper

Audit a test suite for structural debt — patterns where the test exists but does not provide the coverage its presence implies. Do NOT change test semantics or remove regression coverage without user confirmation (`ask_question`); suggest fixture refactors and report findings.

## Step 1 — Determine scope

- **With argument**: audit only the specified file, directory, or module (using `view_file`, `list_dir`).
- **Without argument**: audit the workspace's test surfaces (`tests/`, `test_*.{ext}`, `*_test.{ext}`) using `find_by_name` or `code_search`.

For each test file in scope, identify test bodies and production code nominally covered.

## Step 2 — Categorize debt

### 2a. Trivial-fixture dominance (MNT violation)

The fixture's parameter values trivialize code paths (MNT = minimal-non-trivial fixture). Cross-reference with `quality-list`'s `behavior-coverage` item. Examples:
- Boundary parameter values (N=2, depth=0/1, single element) on complex algorithms.
- Square matrices on non-square code paths.
- Identity/single-instance labels on symmetry-aware algorithms.

### 2b. Legacy mirror (debt cluster)

Clusters of tests in one file that all use the same trivial parameter value, growing over time by extending the file's pattern.

### 2c. Tautological differential

A differential assertion `A(x) == B(x)` between two implementations sharing the underlying code path being tested.

### 2d. Implementation-locked test

Assertions on internal data structure shapes, field order, private fields, or implementation choices rather than contracts.

### 2e. Name-claim mismatch

Test name asserts coverage of a class ("handles all symmetry sectors", "every error variant") but fixture exercises only one instance.

### 2f. Assertion-less observer

Test calls function under test but no assertion reads the output or post-state directly.

## Step 3 — Verify and triage

1. **Confirm debt is real** by reading test and code with `view_file`.
2. **Classify severity**:
   - **High**: latent regression channel (2a, 2c, 2f).
   - **Medium**: maintenance / coverage-claim hazard (2d, 2e).
   - **Low**: cluster pattern (2b).

## Step 4 — Report

Present findings grouped by category with severity tags:

- `[file:line](file:///path/to/file#L10)` of the test
- Debt category (2a–2f)
- Specific parameter / assertion / shared-code region triggering classification
- Suggested minimal-non-trivial fixture or differential refactor

Do **not** auto-edit tests beyond suggesting MNT fixture parameter changes that the user explicitly approves via `ask_question`.
