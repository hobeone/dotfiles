---
name: todo-check
description: Preflight sweep of quality-list items before or during implementation, framed as 'what to set up so done-check passes at the end'. Dual of done-check.
---

# Todo-Check

Forward-looking preflight against the current scope. Item definitions live in `quality-list`; this skill is the **runner**. Update `quality-list`, not this file, when adding or modifying items.

`done-check` asks: "Did the diff satisfy item N?" `todo-check` asks: "What does item N require us to set up so the diff will satisfy it?"

## Procedure

0. **Resolve the active rule set.**

   The base rule set lives in `quality-list/SKILL.md`. Language-specific addenda live alongside it as `quality-list/lang-<language>.md` and supplement the base rules with triggers, mitigation idioms, and mechanical detection patterns for the language. Items themselves stay language-neutral in the base file; addenda only realize them concretely.

   Detection order for the project language:

   1. Check the project's `CLAUDE.md` (or equivalent contributor / agent-guidance file) for a `Language:` declaration line (e.g., `Language: cpp`). If present, load `quality-list/lang-<value>.md`.
   2. Otherwise, auto-detect from file extensions present in the scope (or the work's likely-touched files): `.cpp` / `.cc` / `.cxx` / `.h` / `.hpp` / `.hh` → `cpp`; `.rs` → `rust`; `.py` → `python`; `.ts` / `.tsx` → `typescript`; `.go` → `go`; etc.
   3. Multi-language projects: load every matching `lang-*.md` (one per language present).

   If a detected language has no `lang-<lang>.md`, fall back to the base rules only. Missing addenda are not a concern — they just mean no curated language realizations exist yet.

   The active rule set = base items plus, for each item with content in the loaded addendum, that addendum's section. The preflight framing in Step 2 considers both.

1. **Identify the work scope.** Pull from the plan if one exists, otherwise from the current task description. Determine:

   - What files / modules will change
   - What public symbols, schemas, or contracts will move
   - What invariants the change introduces or modifies
   - Whether a research plan with `Inconclusive / Deferred items` exists (relevant to `discovery-surfacing`)

2. **Process every item in preflight mode.** Read `quality-list/SKILL.md`'s Items index to get the authoritative item set, and process every item in it. Use the per-item Preflight framing quick reference below as the compressed lens — an accelerator over that index spine, not the authoritative set. When an index item has no quick-reference entry, Read its `quality-list/items/<slug>.md` as a safe fallback, so a missing entry never silently drops the item. Read the index for the item set (the slugs); do **not** read the item bodies into main context up front. Only Read a specific `quality-list/items/<slug>.md` file when (a) the item is absent from the quick reference, (b) the quick reference is insufficient to decide active vs N/A, or (c) the item is △ active and the setup action needs the full concern conditions / N/A criteria.

   For each item, determine one of:

   - **△ active — set up needed**: this item will apply to the finished diff; record what to set up *now* so the audit will pass later. Output the concrete preflight action (test fixture variants to include, guard locations to plan, paired-artifact surfaces to update, probes to thread through, etc.).
   - **⊘ N/A**: the item's own N/A criterion already excludes the scope. State why.
   - **? unknown**: cannot decide without more reading; record what would need to be checked to decide.

3. Resolve every **?** before declaring preflight done — either promote to △ with a concrete setup action, or downgrade to ⊘ with a reason.

4. Report the preflight table. Hand the △ rows to the implementation step as setup actions.

## Preflight framing per item (quick reference)

These are how each `quality-list` item reads in preflight mode — a compressed accelerator over the index spine (Step 2), not the authoritative set. The authoritative rule for each item is in `quality-list/items/<slug>.md`, and the authoritative item set is the `quality-list/SKILL.md` index; this is just the lens shift.

- **`invariant-derivation`** — Before patching, derive the full necessary-and-sufficient condition from first principles. List it in the plan.
- **`purpose-verification`** — Identify the input that exposes the purpose end-to-end. Plan to exercise it before declaring done.
- **`pattern-audit`** — If you intend to copy a pattern from a sibling, plan to re-derive its correctness in the current context before reusing it.
- **`scope-discipline`** — Resolve to evaluate findings on their merits, not narrowed to the originating task.
- **`behavior-coverage`** — Design fixtures with the smallest non-trivial parameters per axis. For each parameter, ask "is this the trivial case?" If so, plan a non-trivial variant. Plan happy + error path coverage; plan generic helpers for type-parametric semantics. For tensor-network code, plan ≥3 sites so a bulk tensor is exercised.
- **`implementation-guards`** — Plan `assert!` locations for new invariants, sibling-method consistency reviews (including any new entry that mirrors an existing sibling — replicate the reference sibling's full input-validation set), constructor validations, and validation ordering (place input validation before any panic-prone operation that assumes the validated precondition).
- **`impact-verification`** — Build the impact list now, before editing. Trace public-symbol callers if no formal list exists. If a unit will make a value class newly reachable or unreachable in a symbol's returns (with or without a signature change), or make a same-signature shift of its element ordering or evaluation timing, or add / remove / reorder / relayer a material side effect or change result identity (add / remove memoization, or swap a shared-vs-copy return) — plan the consumer trace now (the item body defines the classes, the diff-visible evidence forms, and two trace bounds: the return-value trace — direct consumers plus one pass-through hop — for value-class / ordering / timing shifts, and the observer-bound trace — call-site reliance plus distant observers keyed by state surface, after a trace-independent materiality gate — for side-effect / result-identity shifts).
- **`test-execution`** — Plan which test commands will be run, and capture the pre-existing failure baseline before any edit. If the diff will touch build-system / packaging / dependency-fetch surfaces, plan an isolated clean-checkout verification run before the PR — once the change is committed, build it from a fresh `git worktree` or local clone with caches and relevant env unset (a worktree / clone sees committed content only, isolating the build from working-tree state).
- **`completion-hygiene`** — Plan which lint / format / type-check / build commands will be run. Note any debug artifacts to strip.
- **`architectural-boundary`** — Identify any new imports / dep edges / `pub` widenings the change will introduce; plan to check them against the project's boundary rules.
- **`escape-hatch-necessity`** — If a unit will introduce a workaround — a static-guarantee escape hatch (Rust `unsafe`, C++ `reinterpret_cast` / `const_cast` / C-style cast, TS `any` / `as` / non-null `!` / `@ts-ignore`), a sleep for a readiness signal, a retry over a race, or any other workaround class covered by the item — plan to derive its necessity first: confirm no direct fix removes the problem. Treat the workaround as a last resort behind that derivation, not a default; a justification comment argues soundness, not necessity.
- **`paired-artifact-drift`** — List every textual surface that will need updating: same-crate `rg` targets, parent module docstrings, `examples/`, `bench/`, doctests, `README.md`, `CLAUDE.md`, migrations / schemas, declared cross-repo paired artifacts. Plan the sweep before editing primary identifiers.
- **`docstring-drift`** — If a unit will change behavior without renaming the identifier (delegating to a library, shifting return shape, adding / removing side effects, restructuring control flow), list now the docstring / comment / README claim surfaces that describe the changed code; plan a cold-read re-verification of each against the new behavior, with an execution probe where the behavior becomes library-owned. If a unit will **widen a reachable outcome set** feeding a documented closed enumeration (an error-variant list, "returns one of", a status-code list, a handled-event list), plan now to list the enumeration docs on the affected entry point **and any sibling whose body can actually reach the new member** (not every sibling that merely returns the same type), and update each to include the new member (or record the deliberate omission).
- **`discovery-surfacing`** — If a plan exists, extract its `Inconclusive` items into a watch list. During implementation, any unexpected fact must match a watch-list branch or trigger halt.
- **`ported-code-attribution`** — If any unit's research surfaced an external implementation as a reference, plan the attribution surface (in-source comment block citing project / file / URL / copyright / license, or a top-level `THIRD_PARTY.md`) before the port lands.
- **`signature-change-regression`** — If a unit changes the signature of a function whose call sites live outside its own translation unit (parameter removal / reorder / type substitution), plan one of: (a) a `= delete;` sentinel overload for the old signature shape, (b) a strong typedef over the affected parameter(s) so the implicit-conversion edge is structurally absent, or (c) an exhaustive call-site sweep across the project (including every preprocessor / build-config branch) verifying no old-form call compiles under the new signature. The lang addendum (`lang-<lang>.md`) lists the language's actual conversion semantics; plan against those.
- **`public-doc-durability`** — If the change touches `README.md` or `docs/**/*.md`, plan the denylist sweep up front (local paths, version literals, roadmap/changelog prose, session-log narrative, file-tree dumps). Use `file-pubdoc` for fresh writes.
- **`public-api-surface`** — If the change touches the public API surface (`pub` items in a public crate, equivalent in other languages), plan the surface diff baseline now (e.g., `cargo public-api` snapshot). For parallel implementations (Dense / BSp, sync / async, ...), plan a symmetry check across the public surfaces. Avoid creating asymmetric public surfaces that force consumers into expert-level internals.

## Output format

```
preflight: <task / unit description>

| Item                          | Status   | Setup action / N/A reason                              |
|-------------------------------|----------|--------------------------------------------------------|
| invariant-derivation          | △ active | derive condition for <invariant> from <constraint>     |
| behavior-coverage             | △ active | fixtures: 3-site MPS bulk variant, non-square 2×3 ...  |
| implementation-guards         | △ active | assert! at <site>; review siblings <a>, <b>            |
| paired-artifact-drift         | △ active | sweep: examples/foo.rs, README.md, doctests in <mod>   |
| discovery-surfacing           | △ active | watch: inconclusive[1] probe at <site>; branches X/Y   |
| scope-discipline              | ⊘ N/A    | no findings raised yet                                 |
| architectural-boundary        | ⊘ N/A    | no new imports / dep edges / pub widening              |
```

Hand the △ rows forward as the implementation setup.
