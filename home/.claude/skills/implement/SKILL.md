---
name: implement
description: Execute a prior research plan via quaere-execution with GitHub issue integration, plan-vs-actual drift, done-check, and conventional commits. Optional issue number argument.
---

# implement

GitHub-integrated wrapper around `quaere-execution`. Drives the Plan → Do → Study → Act workflow with plan-vs-actual drift surfacing and a final `done-check` audit.

**Issue / task:** $ARGUMENTS

## Step 1 — Retrieve the plan

1. Read the GitHub issue and comments using `gh issue view $ARGUMENTS --comments`.
2. Locate the implementation plan. It can live in two places depending on how the issue was created:
   - **Issue body** (D1 default for umbrella-spawned sub-issues): the body begins with `Parent: #<umbrella>` and contains the plan directly. When this line is present, treat the body itself as the plan and ignore comments for plan discovery.
   - **Issue comments** (single-scope issues): scan comments for the `research` output shape (`Hypotheses`, `Inconclusive / Deferred items` sections).
3. The retrieved plan is expected to follow the `research` output shape, including the `Inconclusive / Deferred items` section, regardless of which surface it lived on.
4. If no plan is found in either location, check the current conversation context. If neither is available, suggest running `/research $ARGUMENTS` first and stop.

## Step 2 — Extract the discovery contract

From the plan, extract:

- **Plan checklist** (units of work)
- **Impact list** (callers expected to be touched)
- **Implementation guards** (assertions, paired APIs, constructor validations)
- **Derivations** (specific examples and their deductive properties, already verified in `research` Step 2.B). The list of examples whose properties have been derived defines the **derivationally cleared example set** — examples not on this list are unverified by the plan, regardless of how obvious their properties may seem.
- **Inconclusive items** with their `probe` and `expected branches`
- **Deferred items** with their `reason` and `resolution-point`

These together form the **discovery contract**: the plan-side definition of what counts as "expected during implementation" vs "research gap".

If the plan has no `Inconclusive / Deferred items` section at all, treat that as a research gap and stop. Do not synthesize the section yourself. Re-run `/research` or ask the user to update the plan.

If the plan has no `Derivations` section but the work involves specific-example fixtures (concrete Hamiltonians, concrete protocol messages, named worked cases, etc.), treat that as a research gap on the derivational axis and stop the same way. The absence of a `Derivations` section means no specific example has been derivationally cleared.

## Step 3 — Run quaere-execution

Invoke the `quaere-execution` skill with the plan as the source of truth. Honor its workflow exactly: Plan → Do → Study → Act with scoped units, fresh verification evidence, diff review, fix loops, and commit/push discipline. The wrapper layers the following additional rules on top.

### 3.0 Preflight via todo-check

Before any code change, invoke `todo-check` against the plan to extract the active `quality-list` items and their setup actions for this work. Hand the resulting △ rows to `quaere-execution`'s Plan step so the unit checks already include them. Re-invoke `todo-check` between units when the next unit changes the active item set (e.g., it introduces a new public API → `impact-verification` and `paired-artifact-drift` become active).

### 3.0.1 Pre-commit hook recall

Once per session (cache for the duration of the conversation), read the project's pre-commit configuration to identify the constraints each hook will enforce. Typical config locations: `.pre-commit-config.yaml`, `lefthook.yml`, `.husky/`, the `[hooks]` section of a project task runner (e.g. `Makefile.toml` / `Justfile`).

For each hook, summarize what it enforces. Do not memorize hook internals. Pay particular attention to:

- **Line-count / file-size limits.** Correct response is file-split first, trim only genuinely redundant text (see `quality-list` `completion-hygiene`).
- **Linter constraints** that gate commits (e.g., warnings-as-errors flags). They feed into Step 3.1 Baseline.
- **Custom checks** specific to the project (banned imports, header enforcement, schema validation). Note their existence.

Formatter hooks (rustfmt, prettier, black, clang-format) do not need anticipation — they reformat in place at commit time.

Output: a short summary of the binding constraints. Do not paste the configuration into context.

### 3.0.2 Memory recall

Make recall deliberate once per session.

1. Read `MEMORY.md` (index only).
2. For each entry whose one-line description plausibly intersects a unit in the Step 2 checklist, open and read it.
3. Scope filter: entries the unit's description does not plausibly invoke are not active.

Output: a short list of active memory rules, threaded into per-unit checks alongside `todo-check`'s `quality-list` items. A unit violating an active memory rule is a discovery-contract violation.

### 3.0.3 Project documentation recall

Once per session, read any contributor / agent guidance docs present at the repo root or in `docs/` (top-level only): `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `STYLE.md` / `STYLEGUIDE.md`, `HACKING.md`, `docs/CODING_GUIDELINES.md`, `docs/conventions/`. `README.md` only if it carries contribution guidance. Treat clearly-labeled non-standard names as in-scope. Thread the constraints into per-unit checks the same way as 3.0.2 — violations are discovery-contract violations.

### 3.1 Baseline

Before any code change, build and run existing tests to record pre-existing failures, and run the project's linter (e.g., `cargo clippy`, `clang-tidy`, `ruff check`, `eslint`) to record pre-existing warnings. Compare against both baselines at every verification step. Pre-commit-gated linters (Step 3.0.1) are especially important — the gate rejects on any new violation. Formatters are excluded.

### 3.2 Discovery handling during Do

If, while executing a unit, an unexpected fact is observed (a behavior, type, caller, or invariant the plan did not anticipate):

1. **Check the plan's `Inconclusive` items.** Is this discovery an expected branch?
   - **Yes** → follow the listed branch. If the branch says "re-plan trigger", **stop implementation** and return to research for this hypothesis.
   - **No** → continue to step 2.
2. **Check the `Deferred` items.** Is this discovery the resolution-point of a deferred concern?
   - **Yes** → surface to user, decide whether to expand scope or keep it deferred.
   - **No** → continue to step 3.
3. **Unlisted discovery = research gap.** **Stop.** Do not patch the surprise ad-hoc. Surface to the user with: what was observed, why it contradicts the plan, what hypothesis class it falls under. Ask whether to re-research or to expand the discovery contract explicitly.

The plan's Inconclusive section is the only sanctioned channel for mid-implementation surprises.

### 3.2.1 Specific-example derivation gate

The Step 3.2 rule above covers behavioral / structural surprises. A parallel gate covers **the introduction of a new specific example** during implementation, review, or test addition — even when no "unexpected fact" has surfaced. This includes:

- A concrete Hamiltonian, fixture, or input case being added to satisfy a test plan that named only the abstract spec.
- A worked numerical case being chosen to instantiate a property the plan stated abstractly ("multi-sector W bond" → a particular choice of operators that supposedly realizes it).
- A protocol message, schema, or replay sequence being filled in for a placeholder.
- A test fixture acquiring concrete parameter values where the plan only constrained their qualitative properties.

For every such example, before adding the implementation:

1. **Check the derivationally cleared example set** (extracted in Step 2 from the plan's `Derivations` section). If the example is on the list, it has already been derivationally verified during research; proceed.
2. **If the example is not on the list, halt.** Do not add it on the strength of its properties feeling obvious.
3. **Required action when halted:** Surface to the user with: the proposed example, the deductive properties it is being relied on to satisfy (e.g., "this Hamiltonian must be U(1)-symmetric, must be Hermitian, must be non-diagonal in the chosen basis, must exercise the multi-sector path"), and the request to extend the plan's `Derivations` section before proceeding. The derivation itself is performed in `research` Step 2.B, not in implementation.

A `rejected` derivational outcome is a plan bug — return to research and choose a different example.

### 3.2.2 Mechanism-substitution discipline

When the plan sketches a specific strategy (algorithm, data structure, unsafe pattern) and the implementer chooses a different one at execution time, the substitution must preserve **every** property of the original, not just the explicit motivation named in the sketch.

Procedure when substituting:

1. **Enumerate the original strategy's properties explicitly.** Not just the named motivation — every property the original mechanism happens to achieve. E.g. `MaybeUninit` + transmute provides {no zero-init, no per-element heap alloc, caller-controlled placement, deterministic layout}; `Vec::with_capacity` + push provides {no zero-init} only.
2. **Verify the substitute preserves each property.** Any dropped property must be named in the plan-vs-actual diff and surfaced to the user — "substituting M with M' to avoid unsafe; M' loses Q. OK to ship?" — not silently discarded.

### 3.3 Quality items during Do / Study

Substantive rules for guards, fixtures, docstring consistency, textual drift, naming-as-claim, and plan-vs-actual reconciliation live in `quality-list`. Honor whichever items Step 3.0's `todo-check` marked active for the current unit. The wrapper-specific gates (3.2 / 3.2.1 / 3.2.2 above) layer on top.

## Step 4 — Run done-check

Invoke the `done-check` skill against the diff. Resolve every `⚠` before proceeding. If a ⚠ cannot be resolved within the current scope, file a follow-up issue and document the deferral.

## Step 5 — Final output

After done-check passes:

1. **Plan-vs-actual diff** (from Step 3.6)
2. **Conventional commit message(s)**, generated under the rules of `generate-conventional-commit-messages` if the skill is available. No HPC paths, no cluster context, no local environment details, no line numbers in body.
3. Hand off — do **not** commit unless the user explicitly authorized commits.
