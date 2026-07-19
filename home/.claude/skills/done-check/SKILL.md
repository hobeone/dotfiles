---
name: done-check
description: Single-pass audit of the current diff against quality-list items before declaring a task complete or requesting external review.
---

# Done-Check

Post-hoc audit against the current diff. Item definitions live in `quality-list`; this skill is the **runner**. Update `quality-list`, not this file, when adding or modifying items.

## Procedure

0. **Resolve the active rule set.** Base items live in `quality-list/SKILL.md`; language-specific addenda at `quality-list/lang-<language>.md` realize them concretely.

   Detect language from the project's `CLAUDE.md` `Language:` declaration; otherwise auto-detect from diff file extensions (`.rs` → rust, `.cpp`/`.cc`/`.cxx`/`.h`/`.hpp` → cpp, `.py` → python, `.ts`/`.tsx` → typescript, `.go` → go, etc.). Multi-language projects detect every present language; each matching addendum applies. Missing addendum → base rules only for that language (not a concern). Step 0 only **detects** the language(s); it routes nothing. Each consumer — the Step 2 mechanical subagent and the Step 3 contextual pass — loads every matching addendum file itself.

1. **Identify the diff under audit.** Cover all four sources so recently-added implementation files are not missed:

   ```bash
   git log --oneline @{upstream}..HEAD                       # committed
   git diff @{upstream}..HEAD                                # committed content
   git diff --cached                                         # staged
   git diff                                                  # unstaged
   git ls-files --others --exclude-standard                  # untracked paths
   ```

   Read the contents of any untracked file relevant to the audit (paths alone do not let you check anything).

2. **Spawn a fresh-context auditor for the mechanical / literal items.** Authors read intent; a fresh-context subagent reads literal text — removes the doc-vs-code drift blindspot.

   **Main context MUST NOT load the mechanical item bodies.** The subagent reads the index and those bodies in its own fresh context — it derives the mechanical-lane item set from the index itself; main only composes the prompt (diff + repo path) and dispatches.

   Use the `Agent` tool with `subagent_type: "general-purpose"` and a prompt of the following shape:

   ```
   You are auditing a diff under the `quality-list` quality rules.
   You have NO access to the conversation history that produced this
   diff and MUST NOT speculate about author intent. Judge purely from:

   - the literal text of the diff (provided below)
   - the literal text of the relevant `quality-list` item files (read
     them yourself from the paths below)
   - the literal text of the codebase you can read with your tools

   First read <REPO>/skills/quality-list/SKILL.md and consult its
   Items index. Select every item whose lane is `mechanical`,
   including the mechanical half of any dual-lane item (an entry
   tagged `mechanical (+ contextual half)`, e.g.
   ported-code-attribution). Read each selected item's
   <REPO>/skills/quality-list/items/<slug>.md in full and audit it.

   Also load every language addendum at
   <REPO>/skills/quality-list/lang-<lang>.md that exists for a
   detected project language — a multi-language diff has one per
   present language, and you must load them all (see Step 0 of
   done-check for the detection rule).

   For each of these items return one of:

   - ✅ pass — with concrete evidence (file:line, identifier, or
     literal-text match) that the rule is satisfied
   - ⚠ concern — with the specific diff location and what the
     literal text says that violates the rule
   - ⊘ N/A — using only the item's own N/A criterion as stated

   Pay particular attention to `paired-artifact-drift`'s "new-comment
   claim sweep" and "cold-read pass" sub-rules: extract every numeric
   literal, identifier, property claim, and behavioral guarantee
   (never-raises / always-returns / totality) from new / modified
   comments, and verify each against the code — for a guarantee, trace
   every exception or non-conforming-return source in the function
   body, not just one representative case. Do not assume an
   inconsistency was "intended" — if the literal text says one thing
   and the code does another, that is a ⚠.

   For `ported-code-attribution`, grep the diff for textual signals —
   "ported from", "derived from", "based on", "adapted from", "from
   $project", and any external project name in new comments — and
   verify that any such signal is matched by an attribution comment
   naming source URL, upstream copyright, and license. If a NOTICE /
   THIRD_PARTY-style file is added or modified, follow the upstream
   URL it cites and confirm the upstream actually has the file the
   derivative claims to mirror.

   Report concisely (under 600 words):
   - one row per item with Result + Evidence + Note
   - a final list of any cross-cutting concerns spanning multiple
     items
   ```

   Embed only the diff (committed + staged + unstaged) and the resolved `<REPO>` absolute path in the prompt. **Do not embed item body text** — the subagent reads the item files itself, keeping the main context free of the rule text.

   The subagent runs in parallel with main-context steps 3 below; do not block waiting for it unless step 4 requires the result.

3. **Audit the contextual items in main context.** Read `quality-list/SKILL.md`'s Items index and select every item whose lane is `contextual`, including the contextual half of dual-lane items (an index entry tagged `mechanical (+ contextual half)`, e.g. ported-code-attribution). These need information the subagent does not have — plan / intent / review history, or actual command execution against the working tree. The groupings below are non-exhaustive illustration; the index is the authoritative set:

   - `invariant-derivation`, `purpose-verification`, `scope-discipline`, `discovery-surfacing` — need plan / intent / review history
   - `escape-hatch-necessity` — needs design intent and codebase context to judge whether a direct fix could replace the workaround (a workaround's *presence* may be grep-visible, but its *necessity* is not literal-text-decidable)
   - `test-execution`, `completion-hygiene` — need actual command execution against the working tree
   - `pattern-audit` — needs awareness of which patterns were consciously copied vs independently reinvented
   - `docstring-drift` — needs the diff's behavior-change context plus an execution probe when the changed behavior is library-owned

   For each selected contextual item, `Read` the corresponding `quality-list/items/<slug>.md` file; if a detected language has an addendum section for that item (per Step 0 — e.g. `escape-hatch-necessity`'s Rust realization in `lang-<lang>.md` carries the concrete trigger / detection / mitigation guidance), read every such section too; this contextual pass self-loads every matching addendum itself, one per detected language (Step 0 only detects the languages). Read only the contextual-lane item files, not the mechanical-lane bodies.

   `ported-code-attribution` is dual-lane: the subagent handles the *declared* case (literal grep for "ported from" / "derived from" / external project names → verify attribution); main context handles the *undeclared* case where the conversation history shows research surfaced an external implementation that the diff structurally mirrors but no comment names. If research identified an upstream reference and the diff looks like it followed it, demand attribution even if no comment marks the port. Read `items/ported-code-attribution.md` for both halves.

   Mark each as **✅ pass**, **⚠ concern**, or **⊘ N/A** with evidence as in step 4 below.

4. **Merge results.** When the subagent (step 2) returns, integrate its mechanical-lane rows with main-context's contextual-lane rows into a single table (one row per item, dual-lane items rendered once with both half-results merged). For each ⚠ from the subagent, decide:

   This is the `finding-triage` SSOT's `actionable` / `false-positive` split applied to a fresh-context audit concern:

   - **True positive** (`actionable`) — fix before proceeding (same as a main-context ⚠).
   - **False positive due to missing context** — note explicitly why (e.g., "user explicitly approved the boundary deferral in conversation"); the subagent's literal interpretation is wrong because it lacked context, but this should be rare and worth paper-trailing. Per `finding-triage`, do NOT silently override — false-positive classification is itself a triage step that the user can challenge.

   Each result is ✅ / ⚠ / ⊘ N/A (definitions per Step 2's prompt). Evidence cell records the basis (command run, manual check, `file:line`, or `not run: <reason>`).

5. If any ⚠ remains, fix before proceeding. State concretely what will change. Do not proceed until each concern is resolved, explicitly waived by the user with reasoning, or closed as a recorded deferral per `finding-triage`'s `defer` — a follow-up issue filed with the user's approval. A deferral closes the concern's handling, not its verdict: the row stays ⚠ with the deferral recorded in its Note.

6. Report the audit table.

**When to skip the subagent (step 2).** Pure renames, formatting-only changes, or file moves with no content change — the subagent step is wasted overhead. Any prose / comment / docstring / log / error string add or modify → run the subagent.

## Output format

```
self-audit: <commit-range or "uncommitted">

| Item                          | Result | Evidence                                | Note                                           |
|-------------------------------|--------|-----------------------------------------|------------------------------------------------|
| invariant-derivation          | ⚠      | read: src/foo.rs:42                     | <what's wrong / what to fix>                   |
| behavior-coverage             | ✅     | cargo test (incl. error_path tests)     |                                                |
| test-execution                | ✅     | cargo test: 84 passed, 0 failed         |                                                |
| docstring-drift               | ⊘ N/A  |                                         | diff is text-only; no behavior change          |
| ported-code-attribution       | ⊘ N/A  |                                         | no external code ported                        |
```

Emit one row per item in the `quality-list/SKILL.md` Items index, in index order — the rows above illustrate the format and the result vocabulary (✅ pass / ⚠ concern / ⊘ N/A), not the full set. Dual-lane items render once with both half-results merged. The table is generated from the index, never maintained as an independent list.
