# Textual / paired-artifact drift sweep

Renames, removals, and module-structure changes have to be threaded through every textual surface that names them. Going through only the primary identifier (the function definition, the type, the moved file) is not enough — secondary surfaces keep referring to the old shape and silently rot.

**Same-crate sweep.** For each rename / removal in the diff:

- `rg <old-identifier>` over the touched crate(s). Resolve every remaining hit: panic / `expect` / `assert!` messages, error format strings, inline comments, doctest code blocks, rustdoc links, error-variant `detail` strings, `format!` payloads, module-level prose.
- For each `mod` / `pub mod` add / remove / rename: re-read the parent module's `//!` (or equivalent) docstring against the current set of children. Stale "lands in a subsequent phase", "currently exposes X" claims after Y was added are concerns.
- For each new public callsite that produces, returns, or attaches behavior to an existing public type (new function / method, added trait implementation, added subclass / extension, etc.):
  - Re-read that type's own definition-level docstring against the current producer set. Definition-level docstrings often list producers / consumers / sources of an instance (e.g. "raised by X", "returned by X", "produced by X", "consumed by X") and silently rot when the list grows.
  - **Additionally, run a file-scoped grep over the shared type's source file for the existing sibling's identifier.** When a sibling function / method / handler / impl already exists, that file frequently names it in surfaces that are *not* the type's primary docstring:
    - doc cross-references / link macros (rustdoc `[`X`]`, Sphinx `:func:`X\`\`, JSDoc `{@link X}`, KDoc `[X]`, etc.)
    - user-facing message strings (formatter / `__str__` / `Display` output, error messages, log lines, exception messages)
    - per-case docs inside enumerated types (enum variants, sum-type cases, discriminated-union members)
    - example or "raised by" / "returned by" snippets in module-level / namespace-level prose. Evaluate each hit for whether the new sibling should also be named — patching only what an external review tool flags lets findings cluster by surface kind and converge slowly across multiple review rounds.
- For each removed item: confirm no docstring elsewhere still references it.
- **For each *invariant-operator or quantifier change*** (`==` → `>=`/`<=`, `exact` → `at least`/`at most`, `nev <= ncv` → `nev + 2 <= ncv`, `for all` → `for first N`, etc.), grep the OLD operator paired with the identifier across docstrings, prose, assertions, error / log strings. Include suffixed / chained forms (`assert_eq!(x, y, "msg")`, `X.field, Y`) — a literal `replace_all` skips these.
- **For each *deleted code block within a function body*** (loop removed, branch dropped, intermediate variable inlined away), re-read every comment **inside the same function** against the post-deletion control flow. Structural deletions leave no named artifact for the rg sweep to catch, so adjacent commentary describing the deleted flow rots silently.

**Naming-as-claim.** A new identifier whose name asserts a property the implementation does not in fact provide — e.g. `random_right_canonical_*` that calls `canonicalize(_, 0)` and produces `Mixed { center: 0 }` instead — is a concern. Helpers that wrap a parametrized API call should be named after the parameter values they pin, not after the operational role they happen to serve.

This extends to **struct / enum fields** that reuse a name carrying established semantics elsewhere while binding a different quantity — e.g. a field named `nconv` (everywhere else "number of converged Ritz values") that actually stores `IPARAM(5)`, the Arnoldi factorization size, on one variant. The tell is a field whose own doc comment describes a quantity that does not match the field's name, or a field reusing a sibling variant's / sibling type's field name for a different quantity. Flag it **even when the doc comment is itself accurate** — an accurate comment does not rescue a name that contradicts it, and the New-comment claim sweep below will pass clean precisely because the comment is right, so the field-name-vs-bound-value check has to run independently. Name the field after the quantity it holds (`factorization_size`), not the slot it was copied from.

**New-comment claim sweep (author-blindspot mitigation).** Authors read intent; reviewers read literal text. For every comment / docstring **newly added or modified** in the diff, cross-check the literal claim against the code. The extraction bullets below enumerate the claim kinds (numeric literals, identifiers / notation, set / property claims) and carry the worked examples. This sweep also covers **fenced code-block examples in newly added / modified prose docs** (`README`, `CONTRIBUTING.md`, `docs/`): an illustrative snippet that presents real workspace symbols must name symbols that actually exist (catches `HeffError` in a `#[source]` example when the real type is `DmrgHeffError`).

For each new / modified comment, extract:

- **Numeric literals** (`1e-9`, `tol = 1e-12`, `m >= 2`, `O(1e-4)`, threshold names with values). Cross-check that every such number appears verbatim somewhere in the same translation unit / module / file scope. If the comment names a `tol` value, the corresponding `constexpr` / `const` / parameter should use the same literal.
- **Identifiers and code-like spans** (function names, variable names, type names, mathematical notation like `V_g^T`, `V^†`, `M^*`, `\dagger`, `^T`, conjugate vs transpose). For each, verify the code it refers to is spelled / behaves the same way. `^T` vs `^†` / `transpose` vs `adjoint` are easy to slip when the operands are real (so the two coincide numerically) but the comment is read literally. When the identifier names a type / function / variant presented as a real workspace symbol, also verify it **resolves to an actual definition** (`rg 'enum|struct|fn|trait <name>'` finds it) — a plausible-but-nonexistent name is a concern, not merely a misspelling.
- **Set / distribution / property claims** (`SU(2)`, `Haar`, `traceless`, `unitary`, `Hermitian`, `non-zero trace`, `simultaneously diagonalizes`, `orthogonal`, `non-degenerate`, `uniformly distributed`, `bounded`, `monotone`, `convergent`). For each, verify the code provably enforces the claim or — if it only enforces the claim *up to a tolerance / under a precondition* — verify the qualifier is in the comment too. "X is Hermitian" in a comment over code that constructs X by independent accumulations of `(a,b)` and `(b,a)` is a concern unless the code also enforces symmetry (e.g., mirrors a triangle); the qualifier ("up to ULP-level noise" or "after explicit symmetrization") must be present or the construction must enforce the claim structurally.

The check is mechanical, not heuristic: if the comment names a specific value / identifier / property, the code must back it up at the level of literal text. Vague hand-waving that has no extractable claim is fine; specific assertions are the failure surface.

**Behavioral-guarantee claims (totality sweep).** An *unqualified* guarantee phrase asserts a property over *every* path, so — unlike the per-site claims above — it cannot be discharged by checking one representative case; confirming a single catch clause is not evidence the guarantee holds. When a new / modified docstring or comment carries an unqualified totality / never-raise / always-returns phrase — `never raises`, `cannot fail`, `infallible`, `total`, `always returns X`, `never returns None`, `degrades to … rather than propagating`, and the like — sweep the *whole* function body, not the comment's site:

- **Never-raise / totality guarantees.** The guarantee holds only if **no** path can propagate. Enumerate every exception source that can execute on any path — calls, subscripts, attribute accesses, parses / conversions / arithmetic — and count the easily-forgotten sources: a re-raising or itself-fallible `except` body, an `else` / `finally` clause (none of which the same `try` guards), and a context manager's `__enter__` / `__exit__`. These are illustrations of easily-missed sources, not a closed list — the test is **not** "does the code match this list" but "is every source provably prevented from escaping." Flag the guarantee as **not** discharged whenever any vector is left unruled-out. Confirming one catch clause is never enough: a *narrow* `except` catches only a subset of what its protected code may raise (true even for seemingly-transparent ops — `d[k]` raises `KeyError`, or `TypeError` on an unhashable key, or anything via a custom `__getitem__` / `__hash__`; `lst[i]` raises `IndexError`, or `TypeError` on a non-integer index — and *a fortiori* for an opaque call such as `metadata.version(dist)`), and even a broad `except Exception` still lets `BaseException` (`KeyboardInterrupt`, `SystemExit`) through.
- **Always-returns / never-None guarantees.** Enumerate every `return` path *and* every fall-through (implicit end-of-function `return None`, unhandled branch); each must yield a value conforming to the guarantee. A path that raises is a path that does not return, so apply the never-raise sweep above as well — an escaping exception falsifies an always-returns claim too.

A guarantee with even one unguarded source is a `paired-artifact-drift` concern, not a pass. A **qualified** guarantee narrows *what* must not escape, not *how thoroughly* to look: sweep exactly as above — handlers, `else` / `finally`, and `with` headers included — but discharge against only the named failure. `never raises FooError` requires that no path let a `FooError` escape; `never raises under precondition P` is checked assuming P; a mathematical "for all inputs, X is unitary" is a property claim, not a control-flow totality claim, and belongs to the **Set / distribution / property claims** bullet above, not here.

**Cold-read pass.** After the literal-vs-code sweep, re-read each new / modified comment as if you had never seen the code — trying to construct what the code would have to do to make the comment true. If the construction differs from what the code actually does, the comment is misleading regardless of whether any specific literal is wrong.

**Scope check.** Per-unit comments describe present-tense behavior of that unit (what it does, what invariants hold, what failure modes to expect). They do **not** describe (a) cross-function design rationale, (b) change history, or (c) comparison to rejected alternatives — those belong in commit messages / PR body / umbrella / changelog. The cold-read pass catches **misleading** claims; the scope check catches **misplaced** ones.

Mechanical detection of misplaced content in a new / modified per-unit comment:

- Comparative phrases naming sibling functions / methods / classes / modules: "while X does Y", "unlike X, this Z", "matches / mirrors X" (when the match is incidental rather than a maintained invariant), "X also does this but with Y procedure".
- Decision-history phrases: "we chose / picked / adopted ...", "option (X) / option (Y)", "the SSOT decision", "the design intent", "scoped to a follow-up".
- Cross-surface rationale that names other surfaces by role: "see the commit message for ...", "the umbrella discusses ...", "as noted in the PR".
- Tuning / rewrite-history phrases: "after the PR #N rewrite", "we used to ...", "previously this ...".
- **Deletion-site tombstones** — comments whose subject is the *absence* of code at this site rather than the behavior of the code at this site: "X is handled at parse time in ...", "X is enforced in ...", "X moved to ...", "X is no longer required because ...", "reaching this point means X" (explaining what a removed guard would have done). The diff and commit message own that rationale; an in-source pointer rots independently. **Delete the comment.**

Each such phrase is a candidate ⚠ — flag it and either trim the comment to present-tense behavior or move the content to the appropriate surface (commit message, PR body, umbrella issue, changelog). A claim that justifies *the current code choice in a way the reader cannot re-derive from the code alone* may stay; everything else moves.

**Hyperlink completeness on source surfaces.** In source-file comments, reference GitHub issues / PRs with the **full URL**, not bare `#N`. Source viewers don't auto-link `#N` (only PR / issue / commit-message renderers do).

**Same-repo paired artifacts.** API / schema / contract changes ripple beyond the crate. Sweep these surfaces in the same repo:

- `examples/` — sample code referencing the changed API
- `bench/` — benchmarks referencing it
- doctests anywhere in the repo
- `README.md` / top-level docs / `docs/` prose
- `CLAUDE.md` if it documents the changed surface
- migration / schema files if the change affects persistence
- generated artifacts that should be regenerated (e.g., protobuf, bindgen output)
- **the PR description itself**, if a PR is open or imminent. PR bodies routinely re-state numeric tolerances, identifier names, and structural claims from the code's docstrings (`atol ≈ 2.2e-12` in the PR body vs `≈ 2.2e-10` in the docstring). The PR body and the code are separately editable surfaces; whenever a numeric literal, identifier, or property claim from the code appears in the PR body, the two must agree at the level of literal text.

**User-visible-concept spread (drip-mitigation).** A user-visible concept — an output / log key (`peak_bp_sweep=`, `level=info`), a CLI flag (`--debug_bp_diagnostics`), a CLI option's *description text* (the `add_option` / `add_flag` help string), a runtime warning or error message string, a test format-string assertion (`out.find( "X=") != npos`) — typically lives across many surfaces at once. Adding such a concept, renaming it, or changing its semantics ripples beyond the producer code. Sweep these surfaces in the same fix iteration:

- the producer site (the code that emits it)
- CLI help text — the `add_option` / `add_flag` *description* string that ships with `--help`. This is a user-facing contract, distinct from `docs/` prose and routinely overlooked when prose is updated in isolation.
- runtime warning / error / log strings that name the concept
- regression-test format-string assertions — tests that lock the surface to a specific spelling. Every key the production path emits must be in the assertion set for the diagnostic format to be regression-guarded; partial assertion sets silently allow later additions to drift.
- the PR description and **commit messages staged for the current fix iteration**. Commit messages are immutable post-push, so a rename / wording change must be picked up before the next `git commit`.

Mechanical version: `rg <concept-name>` (case-sensitive, with / without trailing `=` or `:`) over touched directories + staged commit messages + PR body. Enumerate exhaustively; do not selectively patch only the surfaces an external reviewer flagged.

**Cross-repo paired artifacts (opt-in).** If the repo declares external paired artifacts (e.g., a reference implementation in another language, a client library expected to track this API, a published spec), check them as well. Without an explicit declaration this lane is N/A — do not invent paired repos.

**N/A:** the diff renames / removes nothing, adds / removes / renames no modules, adds no identifiers whose name encodes a behavioral claim, adds / modifies no comments that make extractable claims (specific numbers, identifiers, properties, notation, or totality / never-raise / always-returns guarantees), adds / modifies no prose-doc code-block examples naming workspace symbols, and touches no API / schema / contract surface paired artifacts could mirror.
