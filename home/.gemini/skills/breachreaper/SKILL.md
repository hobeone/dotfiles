---
name: breachreaper
description: Audit existing code for stock-detectable API-contract breaches.
---

# breachreaper

Audit production code for stock-detectable API-contract breaches. Report findings only; do not edit production code. Resolutions (API redesign, trait extraction, dependency-direction repair, shared validator extraction) are architectural decisions left to the user.

## Step 1 — Determine scope

- **With argument**: audit only the specified file, directory, or module (using `view_file`, `list_dir`).
- **Without argument**: audit the full workspace (using `code_search`, `find_by_name`). Start with public API surfaces (`pub fn`, `pub struct`, `pub trait`, `pub enum`, exported functions/types), then descend.

## Step 2 — Run each class

### Class A — Defensive-transformation replication

Structural shadow: the same defensive transformation (`.to_order()`, `.normalize()`, `.canonicalize()`, `.coerce()`, equivalent input-shaping calls) is invoked at N ≥ 2 callsites to repair producer output.

1. Identify candidate transformation methods matching `to_*`, `normalize*`, `canonicalize*`, `coerce*`, `as_*`, `into_*`.
2. Search symbols across non-test code using `code_search`.
3. Count callsites where transformation is applied to a producer return value.
4. **Trigger:** ≥ 2 callsites with no producer-side enforcement.

### Class B — Parallel-implementation surface asymmetry

Structural shadow: two implementations are intentionally parallel (`Dense` / `BlockSparse`, sync / async, local / remote, eager / lazy), but their public function / method sets are asymmetric.

1. Identify parallel-impl pairs (e.g., sibling files, `Foo` / `FooAsync`, `LocalX` / `RemoteX`).
2. Enumerate public function / method names using `code_search` or language tooling via `run_command`.
3. Strip parallel-axis prefixes / suffixes and compute symmetric difference.
4. **Trigger:** any function present on one side and missing on the other without domain justification.

### Class C — Architectural-boundary violation

Structural shadow: an import / dependency crosses a documented module boundary in a disallowed direction.

1. Check project architectural rules (`ARCHITECTURE.md`, `GEMINI.md`, `CLAUDE.md`, top-level docs).
2. If no rule is documented, this class is N/A.
3. If a rule exists, walk import graph using `code_search` / `grep_search` and flag edges contradicting it.

### Class D — Sibling-method guard asymmetry

Structural shadow: a public method has an input-validation guard (`assert!`, `if !cond { return Err(...) }`), but a sibling method with parallel signature does not.

1. Identify sibling-method clusters using `code_search` and `view_file`.
2. Check whether each method validates shared constraints.
3. **Trigger:** ≥ 1 method validates, ≥ 1 sibling does not.

## Step 3 — Report

Group findings by class. For each finding, include:

- `[file:line](file:///path/to/file#L10)` of every callsite / symbol / edge.
- The structural shadow itself.
- Resolution direction (Class A: producer API redesign; Class B: trait extraction; Class C: dependency repair; Class D: shared validator extraction).

Do NOT propose patches at callsites.
