---
name: debtreaper
description: Audit a test suite for structural debt — fixtures that trivialize the code under test, tautological differential assertions, implementation-locked or assertion-less tests, and name-claim mismatches. Optional scope argument (file path, directory, or module name); without arguments, audits the workspace's test surfaces. Companion to driftreaper / breachreaper.
---

# debtreaper

Audit a test suite for structural debt — patterns where the test exists but does not provide the coverage its presence implies. Do NOT change test semantics or remove regression coverage without user confirmation; suggest fixture refactors and report findings. Invoke manually when sweeping test debt is the goal.

## Step 1 — Determine scope

- **With argument**: audit only the specified file, directory, or module.
- **Without argument**: audit the workspace's test surfaces (`tests/`, `test_*.{ext}`, `*_test.{ext}`, language-specific test conventions).

For each test file in scope, identify (a) the test bodies and (b) the production code each test nominally covers (by import / `use` / `#include` / module reference).

## Step 2 — Categorize debt

For each test, classify against the following categories. A single test can fall into multiple.

### 2a. Trivial-fixture dominance (MNT violation)

The fixture's parameter values trivialize every code path the test nominally covers (MNT = minimal-non-trivial fixture; the fixture fails to be non-trivial). Cross-reference with the structural-split parameter list in `quality-list`'s `behavior-coverage` item. Examples of trivializing values:

- N=2 sites on an MPS / MPO / tensor-train algorithm (every site is an edge; bulk machinery untested)
- `target_index = depth - 1` on a multi-stage pipeline (post-stage machinery collapses to identity)
- Identity / single-instance / zero-flux symmetry labels on a symmetry-aware algorithm
- Square matrices on a code path that handles non-square cases
- Dimension 1 / single element on iteration-bearing code
- Recursion / induction depth 0 / 1 on inductive algorithms

For each fixture, list the parameters it pins. For each parameter whose pinned value is a boundary value of a structural split the code under test exhibits, flag.

### 2b. Legacy mirror (debt cluster)

The test shape mirrors an existing test in the same file that has 2a-class debt. New tests added by extending the file's pattern inherit and propagate the legacy fixture choice without re-evaluating MNT.

Detection signal: clusters of tests in one file that all use the same trivial parameter value; the cluster grows over time (visible via `git log --follow` on the file) as new behavior is tested by extending the cluster rather than branching to MNT-compliant fixtures. Report the cluster as a single finding, not each test individually.

### 2c. Tautological differential

A differential assertion `A(x) == B(x)` between two implementations whose code paths share the region the test nominally covers. The shared code by construction makes A and B agree there, so the assertion carries no information about that region.

Detection signal: the two sides call the same helper / lambda / shared sub-procedure, and the assertion is downstream of the shared computation but the non-shared portion is small relative to the shared portion (or absent entirely at the test fixture's parameter values). Re-read `quality-list`'s `behavior-coverage` item for the non-shared traversal requirement.

### 2d. Implementation-locked test

The test asserts a specific internal data structure shape, field order, private representation, or implementation choice rather than the contract. A refactor that preserves the contract breaks the test.

Detection signal: assertions on private fields, internal type names, specific iteration order that the spec does not pin, or magic numbers that come from the implementation rather than from the spec / derivation.

### 2e. Name-claim mismatch

The test name asserts coverage of a class ("handles all symmetry sectors", "any input dimension", "every error variant") but the fixture exercises one or two instances. Either the name overclaims or the fixture undercovers.

Detection signal: test name contains generic quantifiers ("all", "any", "every", "various", "comprehensive") or a class noun used in a universally-quantified position; the fixture is a single instance.

### 2f. Assertion-less observer

The test calls the function under test, possibly inspects state, but no assertion reads the function's output or post-state directly. The function could panic, return wrong values, or silently corrupt state without affecting the test result.

Detection signal: function calls in the test body whose return value flows to `_` / is dropped / is bound but never asserted; no `assert*` / `expect*` / `EXPECT*` / equivalent reads the function's actual output. Mirrors `quality-list`'s `behavior-coverage` "no test reads that state directly" failure across the whole test suite, not just the diff.

## Step 3 — Verify and triage

For each candidate debt finding:

1. **Confirm the debt is real.** False positives are common — a test using N=2 may be the right minimal-non-trivial fixture for that algorithm; a differential test may have a genuinely independent comparison path. Read the test and the code it covers before flagging.
2. **Classify severity:**
   - **High** — latent regression channel: 2a (MNT violation in bug-prone code), 2c (tautological differential), 2f (assertion-less observer). A bug in the untested branch would not surface through this test.
   - **Medium** — maintenance / coverage-claim hazard: 2d (implementation-locked), 2e (name-claim mismatch). Bugs in the touched code do still surface; the concern is refactor brittleness or overclaim of coverage.
   - **Low** — cluster pattern: 2b (legacy mirror). The pattern is the concern; individual tests in the cluster may or may not be high-severity on their own.

## Step 4 — Report

Present findings grouped by category, with severity tags. For each finding:

- `file:line` of the test (or the cluster's representative test for 2b)
- Debt category (2a–2f)
- The specific parameter value / assertion target / shared-code region that triggers the classification
- Suggested minimal-non-trivial fixture or differential refactor, when one is obvious from reading the code under test

Do **not** auto-edit tests beyond suggesting MNT fixture parameter changes that the user explicitly approves per file. Removing or restructuring tests requires explicit per-test confirmation; the test may exist to lock down a regression that is not obvious from its name.

## Scope guidance

For large test suites, prioritize:

1. **Recently added tests** (`git log --since="1 month ago" --name-only -- tests/`) — debt that just landed is easier to refactor than legacy debt and prevents cluster growth.
2. **Tests covering code with closed bug-fix PRs** — debt in this region has empirically failed to catch real bugs; the bug-fix PR is evidence the existing coverage missed something.
3. **Differential tests between same-project implementations** — high prior for 2c (tautological) because intra-project siblings often share helpers / lambdas.
4. **Files with cluster-style 2b patterns** — the legacy mirror cluster is the structural debt; reporting individual tests inside the cluster is less actionable than naming the cluster.

## Principles

- **Test debt is not bug.** A test with debt does not necessarily fail to catch the specific bug it was written for; it fails to catch the *class* of bug its name / placement suggests. Report accordingly — debt is a coverage-honesty issue, not a regression.
- **Don't restructure tests without user confirmation.** Removing assertions or changing fixture shapes can hide real regressions the test was originally written to catch.
- **Cross-reference SSOTs.** The substantive rules live in `quality-list` (the `behavior-coverage` item covers MNT, structural-split parameters, and behavior coverage).
