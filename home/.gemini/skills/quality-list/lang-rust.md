# Language addenda for Rust

This file extends `SKILL.md` with Rust-specific triggers, mitigation idioms, and mechanical detection patterns. The audit (`done-check`) and preflight (`todo-check`) skills auto-load this file when the project declares `Language: rust` in its `CLAUDE.md`, or when the diff touches `.rs` files.

This file does **not** introduce new audit items. Items live in `items/<slug>.md` and are language-neutral. Each section below corresponds to an existing item slug and provides the Rust realization: what to grep for, what semantics apply, what idioms remediate the concern. When auditing, treat the language addendum as the concrete answer to "how does this generic item manifest in Rust specifically?"

______________________________________________________________________

## `behavior-coverage`

### Triggers (Rust)

Delegation / equivalence tests that destructure a multi-component result with `_` / `_name` placeholders:

```rust
let (u, _s, vt, _err) = wrapper(...);
```

The `_`-bound components travel through the wrapper but are dropped without any assertion — the Rust realization of the "received but never read" concern condition.

### Mechanical detection

```sh
rg -n 'let \([^)]*\b_\w*\s*[,)]' -g '*.rs'
```

Restrict to test surfaces (`tests/`, `#[cfg(test)]` modules) and triage each hit.

### False-positive review

A `_` binding is legitimate when the component genuinely carries nothing checkable for the test's claim (e.g., a backend-less scalar in a pointer-identity authority test) — but an *equivalence* test should still compare its value. Placeholder-only destructuring outside delegation / equivalence tests is out of this item's scope.

______________________________________________________________________

## `paired-artifact-drift`

### Triggers (Rust)

A doc comment has a *rendered* surface (rustdoc / docs.rs) distinct from its source text, and a token that is meaningful in code position can be inert in doc-text position. The recurring Rust instance:

- **Macro metavariable leaked into doc-comment text.** A `///` or `//!` line containing a `$name` token (`$ty`, `$float`, `$T`, `$fn`, …). A doc comment desugars to `#[doc = "…"]` — a string literal — and `macro_rules!` transcription does not interpolate into string literals. So `$name` in doc text renders **literally** in rustdoc, whether the comment sits inside a macro body or on a standalone item near one. The author, thinking in the macro's mental model, reads "the type parameter"; the docs.rs reader sees `$ty`.

  Verified empirically: `/// Returns a value of type $ty` inside a `macro_rules!` renders `$ty` literally in the generated HTML, even though the same `$ty` in the adjacent return-type position substitutes to the concrete type. The substitution boundary is "token position vs string-literal position", not "inside vs outside the macro".

  Most common origin: writing helper-fn or wrapper docs that *describe* a sibling macro's parameterization in the macro's own vocabulary instead of in concrete terms.

### Mitigation idiom

Describe the concrete behavior, not the metavariable. For a tol-narrowing helper, write "the f64 path is the identity, the f32 path does the real `as f32` narrowing" rather than "narrows `options.tol as $ty`". If a generated item genuinely needs a per-instantiation doc value, use `#[doc = concat!(…)]` or the `paste` / `doc-comment` crates — never rely on `$name` interpolating inside `///`.

### Mechanical detection

```sh
git diff <base>..HEAD -- '*.rs' | rg '^\+\s*//[/!].*\$[A-Za-z_]'
```

Or sweep the working tree:

```sh
rg -n '^\s*//[/!].*\$[A-Za-z_]' -g '*.rs'
```

### False-positive review

One legitimate case: a doc comment that *documents macro syntax* — it mentions `$name` as the name of a parameter the caller supplies (typically the `macro_rules!`'s own doc, e.g. "pass `$ty` as the element type"). There the literal `$name` is intentional prose about the token → ⊘ dismiss. Every other hit, where `$name` stands in for a concrete value or type the doc is trying to *describe*, renders literally and reads as a defect → ⚠ reword to the concrete term.

Advisory only — do **not** hard-fail at commit time. The legitimate macro-syntax-doc case means each hit needs human triage, not a blocking gate.

### N/A elaboration

N/A when the diff adds no `///` / `//!` lines, or when every doc-comment `$name` hit is a deliberate description of macro syntax (the dismiss case above).

______________________________________________________________________

## `docstring-drift`

### Triggers (Rust)

A diff makes a new member of an enumerated outcome set reachable from an entry point while a rustdoc `# Errors` section enumerates the returnable variants:

- A new error-enum variant becomes reachable from an existing entry point — a new `#[from]` impl makes the source error convertible and a `?` propagates it, or the variant is constructed directly on a path the entry point reaches. A sibling function returning that error is in scope when a path in its body can yield the new member: it constructs the variant, its `?` converts the newly-convertible source, or its `?` propagates the variant from a callee that itself can now return it (the reflexive `From<E> for E` that `?` applies passes the callee's variants through unchanged). A sibling that returns the same enum but whose body has no such path is out of scope — do not add the variant to its `# Errors`.
- A rustdoc `# Errors` section that enumerates specific returnable variants — a bulleted per-variant list, or `Returns …` lines each naming a variant — is a closed enumeration; widening the reachable variant set leaves it incomplete even though every listed variant is still returnable.

### Mechanical detection

The trigger has two widening mechanisms; these greps are non-exhaustive starting points for both, not a complete sweep:

```sh
# (a) new #[from] conversions — widen what `?` can propagate into the enum
git diff <base>..HEAD -- '*.rs' | rg '^\+.*#\[from\]'
# (b) new construction / conversion sites of an error variant (also .into(), ? on a new source)
git diff <base>..HEAD -- '*.rs' | rg '^\+.*(Err\(|ok_or|map_err)'
# cross-check: every # Errors enumeration against the widened reachable set
rg -n '# Errors' -g '*.rs'
```

Also review the error enum's own diff hunk for added variants — a variant added there is constructible even when no `#[from]` accompanies it. The greps only surface candidates; which entry points and siblings actually reach the new member is the main-context reachability judgment, not a grep result.

### False-positive review

Dismiss when the new variant is deliberately documented as internal / unreachable-in-practice, or when the `# Errors` section is intentionally coarse — it names only the top-level error type rather than a per-variant enumeration, making no closed-set claim to drift.

### N/A elaboration

N/A when no entry point sharing the widened error type carries a `# Errors` (or equivalent closed enumeration) rustdoc section.

______________________________________________________________________

## `escape-hatch-necessity`

This section realizes only the item's representative type-system class — the non-FFI generic → concrete `unsafe` reinterpret. Per the addendum contract in `SKILL.md`, it does not bound the base item: the item's general workaround scope (an open class — see `items/escape-hatch-necessity.md`) applies to any Rust diff, with or without `unsafe`.

### Triggers (Rust)

A non-FFI `unsafe` whose only job is to bridge a generic / type-erased `T` to a concrete type, paired with a runtime type check:

```rust
TypeId::of::<T>() == TypeId::of::<f64>()
unsafe { reinterpret_desc::<T, f64>(desc) }
```

A `// SAFETY:` comment verifying `T == f64` makes the cast *sound* but does not establish it is *necessary*. When the enclosing method is bounded by a trait the concrete type already implements (`T: Trait`), the per-type behavior belongs in that trait's impl, where `Self` is concrete and no reinterpretation arises — a placement problem misframed as a conversion problem. Descriptor / kernel / backend vocabulary can make the site look like an FFI or layout boundary even when the per-type targets are ordinary safe-API calls, which is what makes the misframing easy to miss.

### Mechanical detection

```sh
rg -n 'TypeId::of::<' -g '*.rs'
# -U (multiline): `unsafe {` and the reinterpret op are usually on separate lines
rg -nU 'unsafe\s*\{[^}]*\b(transmute|from_raw_parts|ptr::read)' -g '*.rs'
```

A `TypeId::of` chain sitting next to an `unsafe` reinterpret in the same function is the smell. Confirm the cast bridges generic → concrete (not an external / layout boundary), then check whether a trait the bound already names can hold the per-type branch instead.

### Mitigation idiom

Move the per-type branch into the trait. Either add the operation to the bounding trait directly (one method, implemented per concrete type), or — when the trait's method list must stay free of backend / descriptor / error types — route through a sealed dispatch supertrait whose method forwards a generic argument to a concrete per-type target. Either way the generic entry point collapses to a single `T::method(...)` call and the `TypeId`, `unsafe`, and `'static` bounds disappear.

### False-positive review

`unsafe` at an irreducible boundary is necessity-satisfied and out of scope: FFI / `extern` calls (use `rust-ffi-rule` for those), raw allocation, MMIO, a `repr(C)` layout-compat pointer cast guarded by `assert_eq_size!` / `assert_eq_align!`. This realization targets the *non-FFI generic → concrete reinterpret*; a `transmute` / `from_raw_parts` performing a genuine layout operation no safe construct expresses is ⊘ dismiss.

### N/A elaboration

This *section* is N/A when the diff adds no `unsafe` block, or when every `unsafe` it adds sits at an irreducible boundary (above).
