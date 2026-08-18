---
name: research
description: Investigate a GitHub issue or free-text task with empirical (subagent probes) and derivational (in-context deduction) hypotheses, producing a vetted implementation plan with Inconclusive / Deferred items. Accepts an issue number or task text.
---

# research

GitHub-integrated wrapper around `quaere-evidence`. Drives the Finding → Hypothesis → Defense → Probe → Decision workflow with parallel subagents and posts the resulting plan to GitHub. Do NOT write any production code in this skill.

**Issue / task:** $ARGUMENTS

## Step 0 — Determine issue context

Check whether `$ARGUMENTS` is a number (existing issue) or free text (new task).

- **Number** → `gh issue view $ARGUMENTS` and proceed with that issue.
- **Free text** → use the text as the task description; an issue will be created in Step 5.

## Step 1 — Read issue/task and form hypotheses

1. If existing issue, read it with `gh issue view`. Otherwise use the free text.

2. Skim the project layout (directory tree, CLAUDE.md, key entry points). Do NOT deep-read files yet.

3. **Establish baselines.**

   - **Test baseline**: build and run existing tests. Record pre-existing failures so later regressions can be distinguished.
   - **Memory recall baseline**: read `MEMORY.md` (index only); for each entry whose one-line description plausibly intersects the work, open and read it. A hypothesis that contradicts an active memory rule is rejected at formation.

4. **Structural feasibility of any proposed new symbol (REQUIRED before hypothesis formation).**

   For every new field, accessor, method, or variant the task proposes to add to an
   existing type, read that type's actual definition and confirm it can hold the state
   the symbol needs — either the state already lives there, or it can be added there
   directly. State that lives on a *sibling* type does not count: an accessor cannot
   filter on data its receiver has no access to.

   This is a two-minute read and it runs unconditionally, before any hypothesis whose
   verification cost scales with call-site or file count. An unimplementable API shape
   invalidates every classification decision downstream of it, so finding out after the
   call sites are classified is the expensive ordering.

   If the receiver cannot hold the state, stop and re-form the task around the type that
   can. Do not proceed to hypothesis formation on the original shape.

5. Form hypotheses across three aspects:

   - **What needs to change**: required code modifications
   - **What invariants must hold**: contracts / preconditions / correctness properties
   - **What could break**: existing code paths affected by the change, especially where new inputs flow through existing APIs

6. Each hypothesis is phrased as a **falsifiable Review Claim or Hypothesis** in the `quaere-evidence` sense — concrete enough that a subagent can attempt to disprove it.

7. **Tag each hypothesis with a `kind`:**

   - `empirical` — resolved by reading code, running tests, observing runtime, inspecting git history, querying spec / external API / caller behavior. Subagent probes in Step 2 handle these.
   - `derivational` — resolved by deductive reasoning from defining equations / type laws / protocol axioms / mathematical or physical first principles. The truth value of a derivational hypothesis does not depend on the state of the codebase; reading more code will not resolve it. Step 2 handles these in the main context, not via subagents.

   Disambiguation test: "if the codebase did not exist, would the claim still have a definite truth value?" Yes → derivational. No → empirical. Two follow-on rules:

   - **Numerical verification stays derivational.** "Construct a candidate → check against an oracle (spec, reference value, closed-form ground truth)" is derivational; resolve in Step 2.B with a scratch script outside the project tree.
   - **Misclassification signal.** If a probe's action is "write code in the project, then check whether it works", it is a derivational gap dressed as an empirical probe — re-classify before the plan exits research.

8. **Specific-example claim sweep (REQUIRED when applicable).** If the plan attaches deductive properties to a concrete example ("this example is symmetric / non-degenerate / exercises the multi-X path"), each property MUST be a separate `derivational` hypothesis — "obvious" is not an exemption. Form: "Example E has property P, derivable from E's defining equations / specification."

9. **Present hypotheses to the user for approval before spawning subagents.** Show the `kind` tag for each. The user can narrow scope, split into sub-issues, or correct mis-classifications.

## Step 2 — Verify hypotheses

Hypotheses split by `kind`. Empirical hypotheses go through subagent probes (Step 2.A). Derivational hypotheses are resolved in the main context (Step 2.B). Both must complete before Step 3 consolidates.

### Step 2.A — Empirical hypotheses (subagents under quaere-evidence)

Spawn one subagent per `empirical` hypothesis (or per small related group). Each subagent operates under the `quaere-evidence` skill and follows its workflow exactly.

Subagent contract:

1. **Run `quaere-evidence`** with the assigned hypothesis as the initial Review Claim or Hypothesis.
2. **Probes (per `quaere-evidence` §5) are three-way: Supporting / Disconfirming / Scope.** The Disconfirming probe **must be actually executed**, not just listed.
3. **For non-trivial existing code, read at `quaere-semantic` depth** (its `What / Why / Invariants / Failure / Connections` schema with the UNKNOWN-probe discipline). Shallow grep-only verification is permitted only for trivially mechanical hypotheses (existence checks, file locations).
4. **Runtime probe (preferred for behavioral claims).** Behavioral claims (output ordering, return shape, error-path return, ABI / FFI layout, signal handling, performance) need a minimal reproducer — docs reading is corroboration, not verification. Boundary cases (minimal/maximal sizes, type variations, single-element containers) belong here.
5. **Caller-contract verification for change-impact hypotheses.** Classify the change as compile-breaking (new required trait method, type change) or silently semantic (same signature, different behavior). Semantic changes need caller-by-caller verification. Flag any public API with unchecked internal assumptions (pointer arithmetic trusting an offset, a serializer trusting field order, an index trusting contiguity).
6. **Verify the provenance of every cited symbol.** Before naming a function, type, field, or constant as fact, confirm it exists in the worktree's *currently checked-out* state — by read or grep, not by recall of a sibling branch, an unmerged PR, an earlier session, or a diff you read once. If a symbol comes from git history or another branch, say so explicitly rather than presenting it as current. This is one grep and it prevents a plan built on code that is not there.
7. Return a **Decision** in the four-state shape from `quaere-evidence` §6 (`confirmed` / `rejected` / `inconclusive` / `deferred`). For `inconclusive`, attach the remaining `probe:`. For `deferred`, attach reason and resolution-point.
8. Report back with concise file paths, line numbers, function signatures, and probe results.

**Subagent granularity**: hypotheses requiring only existence checks or single-file grep can be resolved directly from the main context. Reserve subagents for hypotheses that touch multiple files or need deep reading. Spawn all empirical-hypothesis subagents in a single message; each owns its own `quaere-evidence` ledger.

### Step 2.B — Derivational hypotheses (deductive verification in main context)

Each `derivational` hypothesis is resolved by working out the deduction explicitly, not by reading code. The deduction may take either form:

- **Symbolic** — pen-and-paper algebra / type-law rewriting / protocol-axiom application.
- **Numerical** — when the closed form is too messy, reduce to a numerical identity against an oracle (published reference matrix, closed-form spec, ground-truth value); run a scratch script outside the project tree. This **is** the derivation, not a deferred implementation probe.

Subagents cannot resolve derivational hypotheses.

For each derivational hypothesis:

1. **State the defining equations / axioms / specification clauses** the example or claim rests on. Quote the source if it is an external spec (RFC, protocol doc, mathematical definition); reproduce it if it is a project-internal definition.
2. **Derive forward from the defining equations to the claimed property.** Show the deductive steps. A derivation that ends in "therefore P holds" without reproducible steps is unacceptable.
3. **Attempt a counterexample (the disconfirming step).** Try to construct an instance of the example where the claimed property fails, working from the defining equations. A property that resists counterexample construction is corroborated; one that admits a counterexample falsifies the hypothesis.
4. **Report a Decision** in the four-state shape from Step 2.A, with these derivational-specific resolutions:
   - `confirmed` — derivation completed AND counterexample construction failed
   - `rejected` — counterexample constructed (the claim is false; plan needs revision before continuing)
   - `inconclusive` — derivation incomplete due to missing axiom / ambiguous spec / convention conflict; attach the missing piece as an empirical `probe:` routing back through Step 2.A. ("Code it up and check at implementation time" is not valid — use the numerical-derivation lane.)
   - `deferred` — outside current scope; attach reason and resolution-point

A `rejected` derivational hypothesis is a **plan bug**. Correct the plan and re-derive before Step 3. A plan that attaches deductive properties to examples without reproducing the derivation fails this step.

## Step 3 — Consolidate into implementation plan

Merge subagent reports into a single plan with the following sections.

### Plan body

- **Checklist of changes** with exact file paths, function signatures, type definitions
- **Impact list**: every caller affected and its implicit contract (for use in implementation verification)
- **Test plan**:
  - Invariants the new/changed code must satisfy
  - Tests to add/modify with expected behavior
  - For new constructors / input paths: tests passing those inputs through every existing public API that could receive them. A new input path without cross-API tests is incomplete.
  - **Surrogate-probe re-instantiation**: every hypothesis confirmed in Step 2 by a *surrogate* probe (proof-of-concept build, reference implementation, toy fixture standing in for the committed artifact) must emit either an artifact-level Test plan entry that re-runs the check against the committed artifact, or an explicit `surrogate evidence suffices because <reason>` line.
  - **Perf acceptance criterion** (perf-motivated tasks only): an end-to-end benchmark that provably exercises the changed path, with a before/after (or feature-off/on) comparison, carried forward as a first-class acceptance criterion with the same status as a correctness test. A component-level microbenchmark proves the component win, not the operation win, and does not discharge this. When the win is conditional (neutral on the default build, paying off only under a feature flag / accelerated backend / specific input class), state where it lands rather than implying an unconditional speedup.
- **Implementation guards** (from confirmed hypotheses):
  - New invariants enforced with assertions, not comments
  - Paired APIs that must stay consistent (sibling methods)
  - Constructor validations required
  - State that needs an explicit field rather than heuristic inference
- **Derivations** (from confirmed derivational hypotheses): for each specific example whose properties were claimed in the plan, reproduce the derivation in compressed form (defining equations → steps → conclusion). The plan reader should be able to retrace the deduction without re-running Step 2.B.
- **Conflicts or dependencies between hypotheses** (if any)

### Inconclusive / Deferred items (REQUIRED section)

This section is **mandatory**. It explicitly carries forward UNKNOWNs into the implementation phase so that mid-implementation discoveries are either listed (handled per plan) or surface as research gaps (halt and escalate).

```markdown
## Inconclusive / Deferred items

- inconclusive — <hypothesis>
  probe: <next investigation: git blame, runtime observation, etc.>
  expected branches:
    - if probe yields X → continue per plan
    - if probe yields Y → re-plan trigger (return to research)

- deferred — <hypothesis>
  reason: <why postponed>
  resolution-point: <when this becomes actionable>
```

If none, write `Inconclusive / Deferred items: none identified` explicitly.

### Filter unresolved questions before listing them

Before escalating a sub-decision to the user as "unresolved":

1. **Workspace patterns** — search the workspace (`rg`, `fd`) for analogous constructs. If the workspace consistently does X, that is the answer.
2. **Memory and prior conversation** — check available memory entries and recent turns for decisions on the same axis.
3. **Subagent reports** — re-read Step 2 output. A subagent's confirmed recommendation is resolved unless contradicted elsewhere.

A sub-decision is genuinely unresolved only when the above are silent or contradictory. "More than one technically-viable option exists" is not unresolved — it is analysis you owe the user. When you do escalate, state what you checked.

Report the plan back to the main context.

## Step 3.4 — Reachability check (mandatory)

A plan can be locally closed yet reach further than the author reasoned about — a new public surface whose semantics depend on consumer code outside scope (Checks 1–3), an enablement that binds compilation units the plan never named (Check 4), a verification probe that covers fewer build configurations than the obligation spans (Check 5), or a performance probe that exercises fewer code paths than the changed path it is trusted to measure (Check 6). Author confidence alone misses these — they require looking outward, deliberately, at what the plan didn't name. Any check firing means the plan's reach is not closed; rescope or defer.

### Check 1 — Dead-on-arrival state

For each new public symbol (parameter with non-trivial value range, struct field, accessor, method, variant), ask: does any current or in-plan code path **branch on** this symbol's value (`match`, `if`, conditional dispatch, layout reorder, validation)? Pure references — `Clone` copying, accessor exposure, constructor storing — are not branches.

- Real branch exists → proceed.
- No real branch → dead-on-arrival. Either expand scope (add consumer-side branching to the checklist) or defer the symbol until the consumer materializes.

### Check 2 — Docstring-vocabulary scan

Grep the plan body and proposed docstrings (case-insensitive):

```
not yet honored | currently restricted | social contract | deferred (mitigation|consumer-side|to a later)
documented limitation | for future use | in preparation for | analogous to ... cascade
in a future PR | follow-up issue tracks | when consumers ... | until consumers ...
```

Each hit admits an out-of-scope dependency. Each must resolve into a `Depends on #N` link (carried in `Inconclusive / Deferred items`), a scope expansion, or a defer / close decision. Hits without a resolution route → return to Step 1 and rescope.

### Check 3 — Local-closure vs contract-closure distinction

Restate the plan's claim in one sentence. Would it still be true if every line of consumer code outside the plan were arbitrary?

- **Local closure**: "constructor stores the data correctly and propagates the order tag" — true regardless of consumers.
- **Contract closure**: "constructor produces a tensor that downstream operations interpret correctly under the declared order" — only true if consumers honor the tag.

If the user-visible value rests on contract closure and contract closure is out of scope, the plan is mis-scoped. Bring contract closure in or step back to the upstream design decision.

### Check 4 — Shared-scope config reach

When the plan enables a lint / setting / config entry at a **shared scope** (Cargo `[workspace.lints]` or package `[lints]`, a workspace / package / global config file, a compiler-wide flag, any setting inherited by more than the one unit being changed), enumerate **every unit the scope mechanically binds** and confirm the intended target matches the actual reach.

For Cargo, a package `[lints]` table — including `[workspace.lints]` inherited via `[lints] workspace = true` — binds every target kind of that package: lib, bins, integration tests, benches, examples, and the build script (`build.rs`). Each is a separate compilation unit, not just the library. (`[workspace.lints]` binds only member packages that opt in with `[lints] workspace = true`.)

- Reach matches intent → proceed.
- Reach exceeds intent (the setting is meant for the library but the scope also binds test / bench / example / build-script units) → resolve one of two ways, never by silent acceptance: (a) narrow the scope to a per-unit attribute (e.g. per-lib `#![deny(...)]`); or (b) bring every bound unit into the Step 3 impact / test plan and verify each satisfies the setting. A bound unit that is neither narrowed out nor verified is an unresolved item, not an accepted one.

### Check 5 — Verification-config representativeness

When the plan's safety rests on a probe — "it builds", "the tests pass", "the cycle compiles" — and the same source is compiled under more than one **non-interchangeable configuration** (Rust `--cfg test` vs the non-test build, a feature-gated vs ungated build, C / C++ translation units compiled with macros that change a type's layout or ODR identity, a distinct `target` / `arch`), a passing probe under one configuration does not certify a sibling. The configurations look interchangeable but can produce distinct type instances / ABIs, so an obligation that binds in configuration B is untouched by a probe that ran configuration A.

Identify the configuration where the **new** obligation binds and confirm the probe exercises THAT configuration:

- Probe runs the binding configuration → proceed.
- Probe runs only a sibling ("does it build", an integration target linking the non-test build, the ungated build) while the obligation binds elsewhere (the crate's own `--cfg test` unit tests, the gated build) → not certified. Name the binding-configuration probe and add it to the Step 3 test plan, or step back to a structure that keeps the obligation inside one configuration.

### Check 6 — Benchmark-reach check

When the plan cites a benchmark (existing or new) as evidence for a performance claim, confirm the benchmark provably executes the changed code — inputs that hit the changed branch, not a fast-path that bypasses it. A benchmark that misses the changed path reads as coverage but certifies nothing about it — worse than no benchmark, because "benches pass" looks like confirmation. A component-level microbenchmark is not an end-to-end reach: it proves the component win, not that any operation dominated by the changed path improved.

- Benchmark provably reaches the changed path → proceed.
- Benchmark misses it (fast-path bypass, inputs that never enter the changed branch), or the only evidence is an isolated-component microbench → not certified. Add an end-to-end benchmark that reaches the path to the Step 3 test plan, or name the different public operation — one dominated by the changed path — that will serve as the perf probe.

Output: **clean** (proceed to Step 3.5) or **flagged** (list firings + proposed resolution + surface to user).

## Step 3.5 — Plan review gate (mandatory offer)

After Step 3 produces a plan and before Step 4 collects user approval:

0. **Carried-forward constraints, and a cheap contradiction check — run this BEFORE dispatching any review pass.**

   When the task arrives carrying findings from a prior investigation — an ad-hoc audit done conversationally, a previous session, an issue comment, anything established before the plan existed — end the plan body with an explicit **Carried-forward constraints** table: one row per finding, stating the constraint and where it came from.

   Then run a single cheap (Sonnet-tier) subagent whose *only* job is to diff the plan against that table and report contradictions. Nothing else — not soundness, not completeness.

   This exists because a plan can silently regress against a fact the session already had. It has happened: an audit identified two test-table rows as already-covered duplicates, and the plan drafted afterwards listed them for conversion anyway. That is a mechanical contradiction, not a judgement call, and paying a premium-tier review round to catch it is waste. Prose context does not survive translation into a plan reliably enough to skip the check.

1. **Always offer a fresh-context plan review** — never silently skip. Phrase it as a recommendation, not a question:

   > "Plan ready. Recommend an independent review pass before approval;
   > type `skip` to bypass, or anything else to run it."

   If run: dispatch a fresh-context subagent (no access to this conversation) with the plan body, the issue/task text, and instructions to look for (a) implementation soundness given the plan's own stated assumptions, and (b) whether those assumptions themselves actually hold — it should re-derive or spot-check at least one non-trivial claim rather than taking the plan's word for it.

2. **If review runs**: triage the findings.

   - **Implementation concerns** (algorithm details, error handling, test coverage gaps, naming): patch the plan in place and proceed to the loop gate below.
   - **Premise concerns** (the assumed root cause may be wrong, the described mechanism doesn't match how the code actually fails, a fixture's claimed properties may not hold, an "obvious" derivation is unproven): **return to Step 1**. Do not patch the plan in place — the hypothesis set itself is suspect, and incremental edits perpetuate the bad premise across iterations.

   Distinguishing the two: an implementation concern asks "given the plan's assumptions, is the proposed approach sound?"; a premise concern asks "are the plan's assumptions actually true?". If the reviewer would have given a different answer with empirical evidence in hand, it's a premise concern.

3. **Loop gate**: after patching, re-run the review pass fresh (no bias from the previous iteration's findings). Exit the loop when a pass raises no new concerns. Cap: 3 iterations within the same premise. If the cap is reached, or a pass keeps raising the same unresolved concern, surface the outstanding findings to the user and ask whether to proceed as-is, patch further manually, or escalate. Premise concerns return to Step 1 and reset the counter — iteration count is per-premise, not lifetime.

4. **The plan that exits this step is the contract.** Step 5 will post that plan once. Revisions happen here, before posting; there is no "post then revise" loop.

## Step 4 — User approval

Present the plan (after any Step 3.5 revisions) and ask for approval before posting to GitHub.

## Step 5 — Post plan to GitHub

### 5.0 Laundering pass — run `gh-body-check` (MANDATORY)

Run `gh-body-check` on the plan body before any `gh-post` invocation; resolve any ⚠ before posting.

### 5.1 Route to the correct surface

After 5.0 clears, route the plan based on what `$ARGUMENTS` resolves to:

- **Existing single-scope issue** → `gh-post issue comment $ARGUMENTS` (per `file-issue` step 5) with the plan as body.
- **Existing umbrella issue** (the body contains a Phases table or sub-tasks list) → spawn a new sub-issue whose body IS the plan, following `file-issue`'s `Variants > Umbrella sub-issue` shape: `Parent: #<umbrella>` on the first line, `Phase N: <topic>` title, Goal / Scope / Out of scope / Acceptance derived from the plan. After creation, append the new sub-issue's number to the umbrella's Phases table row. Do not also post the plan as an umbrella comment.
- **New task** → `gh-post issue create` (per `file-issue` step 5) with the plan in the body; report the new issue number.

When ambiguous, ask the user. Umbrella sub-issue is the D1 default.

**Issue creation rules** (research-specific; body shape and the language / reference / line-number / exclusion rules come from `gh-body-conventions` via `file-issue`):

1. **Split issues by commit unit.** Each issue corresponds to one atomic, independently committable change. Multi-commit plans become multiple issues with `Depends on #N` links.
2. **No "rejected alternatives" sections** unless explicitly requested.
