# Public API surface discipline

Layered / hexagonal architectures depend on the public API surface being **structurally visible** at the boundary, **symmetric** across parallel implementations, and **tight** enough that defensive transformations do not proliferate at call sites. When the surface slips on any of these, layer violations surface as call-site symptoms rather than at the boundary. Two structural smells indicate the slip; the lane catches both because review-iteration counting alone cannot — by the time three reviewers have flagged three callsites individually, the underlying API leak has already escaped.

**Concern A: Defensive-transformation replication.** When the same defensive transformation — `.to_order()`, `.normalize()`, `.canonicalize()`, `.coerce()`, equivalent input-shaping calls — is applied at N ≥ 2 callsites to repair an invalid producer output (wrong layout, wrong order, wrong axis position), the root cause is an upstream API-shape leak that lets producers emit the invalid form in the first place. Patching each callsite reproduces the work and locks the leak in place; fixing the public API of the producer (constrain the type, tighten the constructor, hide the leaky variant behind a constructor that enforces the invariant) eliminates the entire class. The signal that this has happened is the proliferation of the patch itself — one defensive call is a one-off, two is the warning, three is confirmation.

**Concern B: Parallel-implementation surface asymmetry.** When two or more implementations are intentionally parallel — `Dense` vs `BlockSparse`, sync vs async, local vs remote, eager vs lazy — their public API surfaces (set of public functions / methods / trait impls) must be symmetric unless the difference is domain-justified (the implementations genuinely differ in what they can express). An implementation whose high-level public driver is missing while the other side has one forces consumers to reach into expert-level internals to use it; this is a forced layer violation produced by absent symmetry, not by widened access. The smell shows up as: one branch's public surface = high-level + expert; the other branch's public surface = expert only. Trait-based dispatch that requires both branches to implement the same method is the structural mitigation — when the trait method exists, both impls must satisfy it, so the symmetry is enforced by the type system rather than by audit.

**Detection.**

- For Rust, `cargo public-api` snapshots the public surface per crate. Diff against a baseline on every PR; any new item (function, type, trait impl) in the diff must be intentional. For parallel-surface checks, snapshot each implementation's namespace and compute the symmetric difference of function names (after stripping prefixes) — any function present on one side but missing on the other is a candidate Concern B.
- For defensive-transformation replication, `rg` for the transformation method name across the workspace. If it appears at ≥ 2 callsites in non-test code applied to producer outputs without a producer-side fix, treat as a Concern A trigger.

**Concern conditions:**

- The same defensive transformation method is invoked at ≥ 2 callsites to reshape producer output, with no producer-side change addressing the root cause.
- Parallel implementations have asymmetric public surfaces (one exposes a high-level driver, the other forces consumers to expert-level internals), and the asymmetry is not justified by an inherent domain difference between the implementations.
- A diff that adds or modifies a public API surface (Rust `pub` items in a public crate, equivalent in other languages) lands without a baseline-vs-current public-surface diff being inspected.

**N/A:** the diff touches no public API surface (purely internal change, no `pub` items added or modified, no parallel sibling implementation in the touched module).
