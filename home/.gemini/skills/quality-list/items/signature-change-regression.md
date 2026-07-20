# Silent semantic regression on signature change

Signature changes — parameter removal, reorder, or type substitution — can produce a silently miscompiled caller path when the old call form still satisfies the new signature's type rules under the language's conversion semantics. The audit lane is responsible for detecting whether such a path exists *before* the call sites silently take on a different meaning.

The failure mode is structural: a `git diff` that contracts or rewires a function signature leaves the function declaration loudly changed but its callers visually unchanged. If the call sites still compile under the new signature — through implicit conversions, default-argument insertion, narrowing constructors, coercion traits — they are quietly remapped to the new semantics. The old behavior is gone and no compile-time signal points at it.

**Concern conditions:**

- The diff removes, reorders, or substitutes parameters in a public (or otherwise out-of-file-visible) function or method.
- The old call form is still well-typed under the new signature due to language-level conversion / promotion / coercion — i.e., a caller written against the previous signature still compiles, even though its argument is now bound to a *different* parameter slot or *different* parameter type.
- No compile-time signal exists at existing call sites: a developer reading the call site cannot tell whether the call was swept after the signature change or was silently re-routed.

**Mitigation pattern:** introduce a *sentinel* — typically a `= delete;` overload or a `[[deprecated]]` overload — that takes the old signature shape and makes the old call form fail to compile (or loudly warn). The sentinel forces every call site to be touched after the signature change. Strong types over the affected parameters (newtype / phantom-tagged wrappers) achieve the same protection at the type level without an explicit sentinel.

The generic principle is language-agnostic; the actual triggers, mitigation idioms, and mechanical detection patterns depend on the host language's conversion semantics. Concrete realizations live in `lang-<language>.md` next to this file. When `done-check` / `todo-check` resolve the active rule set, the lang-supplement is loaded alongside the base item.

**N/A:** the diff does not remove, reorder, or substitute parameters of any function or method whose call sites live outside the touched translation unit, AND the call sites of any touched function are exhaustively re-verified to type-check under the new signature with no implicit-conversion path from the old form.
