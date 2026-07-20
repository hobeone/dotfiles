---
name: breachreaper
description: Audit existing code for stock-detectable API-contract breaches.
---

# breachreaper

Audit production code for stock-detectable API-contract breaches. Report findings only; do not edit production code. Resolutions (API redesign, trait extraction, dependency-direction repair, shared validator extraction) are architectural decisions left to the user.

## Step 1 — Determine scope

- **With argument**: audit only the specified file, directory, or module.
- **Without argument**: audit the full workspace. Start with public API surfaces (`pub fn`, `pub struct`, `pub trait`, `pub enum`, equivalent), then descend.

## Step 2 — Run each class

### Class A — Defensive-transformation replication

Structural shadow: the same defensive transformation (`.to_order()`, `.normalize()`, `.canonicalize()`, `.coerce()`, equivalent input-shaping calls) is invoked at N ≥ 2 callsites to repair producer output.

1. Identify candidate transformation methods. Names matching `to_*`, `normalize*`, `canonicalize*`, `coerce*`, `as_*`, `into_*` — transformations that take producer output and reshape it before use.
2. For each candidate, `rg` the symbol across non-test code.
3. Count callsites where the transformation is applied to a producer return value (not internal to the producer itself).
4. **Trigger:** ≥ 2 such callsites with no producer-side change addressing the root cause.

Classification:

- **Confirmed:** ≥ 2 callsites, all on producer output, no producer-side enforcement.
- **Suspected:** ≥ 2 callsites but one is in a transitional context (deprecated path, test scaffolding).
- **Not a breach:** 1 callsite, or the transformation is the producer's own canonical exit point.

### Class B — Parallel-implementation surface asymmetry

Structural shadow: two implementations are intentionally parallel (`Dense` / `BlockSparse`, sync / async, local / remote, eager / lazy), but their public function / method sets are asymmetric in a way not justified by inherent domain difference.

1. Identify parallel-impl pairs. Heuristics:
   - Sibling files / modules with parallel names (`dense.rs` + `block_sparse.rs`).
   - Sibling types implementing the same trait, where both also expose impl-specific public methods.
   - Naming conventions like `Foo` + `FooAsync`, `LocalX` + `RemoteX`.
2. For each pair, enumerate public function / method names. For Rust, `cargo public-api` per crate is the canonical source.
3. Strip parallel-axis prefixes / suffixes and compute the symmetric difference.
4. **Trigger:** any function present on one side and missing on the other, where the missing side has no domain-level reason to lack it.

Classification:

- **Confirmed:** asymmetric surface forces consumers to reach expert-level internals on one side.
- **Justified asymmetry:** the missing function is meaningless for that impl (e.g., `flush()` on an immutable variant).

### Class C — Architectural-boundary violation

Structural shadow: an import / `use` / `#include` / dep entry crosses a documented module boundary in the disallowed direction, or a `pub` (or equivalent) widens exposure beyond the rule.

1. Check whether the project has a documented architectural rule: layering, hexagonal direction, module DAG, public / internal split. Look in `ARCHITECTURE.md`, `CLAUDE.md`, top-level doc files, `Cargo.toml` workspace structure.
2. If no rule is documented, this class is N/A — exit.
3. If a rule exists, walk the import / dep graph and flag edges contradicting it.
4. Also flag `pub` symbols whose exposure widens past the rule.

Classification:

- **Confirmed:** import or `pub` crosses the rule.
- **N/A:** no rule documented for the project.

### Class D — Sibling-method guard asymmetry

Structural shadow: a public method has an input-validation guard (`assert!`, `if !cond { return Err(...) }`, equivalent) at entry, but a sibling method (same type, parallel signature, same constrained parameter shape) does not.

1. Identify sibling-method clusters: methods on the same type whose signatures share constrained parameter shapes (size, count, rank, dimension, exponent, non-empty collection).
2. For each cluster, check whether each method validates the shared constraint at entry.
3. **Trigger:** ≥ 1 method validates, ≥ 1 sibling does not.

Classification:

- **Confirmed:** sibling asymmetry — at least one entry leaves the constraint unenforced.
- **Justified asymmetry:** the missing-guard method has a structurally different parameter contract (different invariant required).

## Step 3 — Report

Group findings by class. For each finding, include:

- File:line of every callsite / symbol / edge.
- The structural shadow itself (callsite count, symmetric-difference set, import edge, sibling cluster).
- Resolution direction:
  - Class A: producer-side API redesign (constrain the type, tighten the constructor, hide leaky variants behind enforcing constructors).
  - Class B: trait extraction so the type system enforces symmetry.
  - Class C: dependency-direction repair (move the dep, invert the interface, relocate the offending `pub`).
  - Class D: shared validator extraction so siblings cannot diverge.

Do NOT propose patches at callsites.

## Principles

- **Stock-auditable only.** Every finding must be justifiable from current syntactic structure without intent input. Findings requiring "this should be doing X" are out of scope — leave for manual review.
- **Report, never fix.** Do not edit production code.
- **Structural shadow ≥ 2.** N = 1 is a one-off, not a pattern. The proliferation IS the signal.
