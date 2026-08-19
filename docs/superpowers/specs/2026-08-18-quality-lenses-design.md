# Design Spec: Quality Lenses as a Pre-PR Step

Promote the four review angles from the built-in `/simplify` command — Reuse, Simplification,
Efficiency, Altitude — into a reusable, findings-only pass that runs at two gates: against the
**plan** during research, and against the **diff** before the first commit.

## Problem

`/simplify` has been producing genuinely good improvements, but it is invoked ad hoc and cannot be
composed into the existing pipeline as-is:

1. **It mutates.** Its Phase 2 applies fixes directly. Every other gate in `review-pipeline-coderabbit`
   (`done-check`, `pr-review-toolkit:code-reviewer`, `/pr-review remote`) is read-only and feeds the
   `finding-triage` SSOT, where each item gets a per-item disposition. An auto-applying step bypasses
   that veto — and quality findings are far more taste-dependent than correctness findings, so the
   veto matters more here, not less.
2. **It runs too late.** Its value is highest against a *plan*: deleting an unneeded abstraction from a
   plan costs a sentence, deleting it from merged code costs a rewrite. Applied only to a diff, the
   pass is a safety net standing in for a mechanism that should sit further upstream.
3. **Its lens prose duplicates an existing SSOT.** `quality-list` already owns universal code-quality
   items and states the contract explicitly: *"do not copy item text into [referencing skills]"* and
   *"runners derive their active item set by reading this index, never by hardcoding a parallel slug
   list."* A new skill carrying four freshly-written lens descriptions would violate both halves.

## What already exists, and what does not

Mapping the four lenses onto the 19 current `quality-list` items:

| Lens | Existing coverage |
|---|---|
| Reuse | `duplication-extraction`, `pattern-audit` |
| Simplification | `scope-discipline` |
| Altitude | `architectural-boundary`, `escape-hatch-necessity` |
| Efficiency | **none** |

Efficiency is a real gap. No item covers redundant computation or repeated I/O, independent work run
sequentially, blocking work added to startup or hot paths, or long-lived objects built from closures
that keep an entire enclosing scope alive. The last of those is the sharpest rule in `/simplify` and
the least likely to be caught by a checklist row.

The overlap on the other three is **not** a reason to skip them. `done-check` applies items as
checklist rows — breadth, one auditor, many items. `/simplify`'s value comes from the opposite shape:
one agent per angle, each obsessed with a single lens, reading the codebase around the change. The
item is the *what*; the dispatch shape is the *how*. Conflating them is what made the first draft of
this design wrong.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Mutating vs findings-only | **Findings-only.** Never edits. | Restores the per-item veto; makes the pass composable with `finding-triage` like every other gate. |
| Item text location | **`quality-list`**, referenced by slug. | The SSOT's own propagation contract. New runner carries zero item prose. |
| Lens grouping location | **`quality-list` Items index**, as a per-item `lens:` tag. | Same reason lanes live there. A runner that hardcodes its own slug→lens table is the parallel list the SSOT forbids. |
| Relationship to `done-check` | **Runner owns depth, `done-check` owns coverage.** Overlap accepted and documented. | `done-check` still covers every item for every task; the lens runner adds depth at two gates only. |
| Call sites | **Both**, plan-review first. | Plan-time is the primary mechanism; diff-time is the safety net. |

## Architecture

Three layers, matching the split `quality-list` already defines.

### Layer 1 — Items (`quality-list`)

1. **New item `efficiency-waste`** at `items/efficiency-waste.md`, lane **mechanical** (every signal —
   repeated I/O, sequential independent operations, closure-captured scope — is judgable from literal
   diff text without conversation history).
2. **New `lens:` tag** on each entry in the Items index, alongside the existing lane suffix. Values:
   `reuse`, `simplification`, `efficiency`, `altitude`, or absent for items belonging to no lens.
   Initial assignment per the mapping table above; `efficiency-waste` → `efficiency`.
3. **No rewrites of existing item bodies** in this change. If a lens pass shows an item body is too
   narrow for the lens, that is a follow-up item edit, not part of this wiring.

### Layer 2 — Runner (new skill `quality-lenses`)

`home/.claude/skills/quality-lenses/SKILL.md`. A runnable procedure, not a definition file.

- **Resolve the lens set** by reading the `quality-list` Items index and grouping slugs by `lens:` tag.
  Never hardcode the grouping.
- **Two modes**, chosen by argument:
  - `plan` — target is a plan body passed by the caller.
  - `diff` — target resolved exactly as `done-check` Step 1 does (committed + staged + unstaged +
    untracked), so the two runners never disagree about what is under review.
- **Dispatch one fresh-context agent per lens**, all in a single message so they run concurrently.
  Each agent reads its own lens's item bodies from `quality-list` in its own context; main context
  does not load them (same discipline as `done-check` Step 2).
- **Return findings only** — `file:line` (or plan section) and a one-line summary plus the concrete
  cost. It applies nothing, commits nothing, and has no fix loop of its own.
- **Language addenda** load exactly as in `done-check` Step 0.

### Layer 3 — Call sites

**A. Plan gate — `research` Step 3.5.** The lens pass joins the existing plan-review dispatch in
step 1, running alongside the soundness/premise reviewer rather than in a separate round. Its findings
route into step 3.5's existing triage in step 2, and the existing distinction governs them:

- A Reuse / Simplification / Efficiency finding is an **implementation concern** — patch the plan in
  place.
- An Altitude finding that says the plan is solving the problem at the wrong depth is a **premise
  concern** — return to Step 1 and reset the per-premise iteration counter. This is the case the whole
  design exists to catch, and it must not be patched in place.

The existing 3-iteration cap and loop-gate rules apply unchanged.

**B. Diff gate — `review-pipeline-coderabbit` Phase 0.5.** The lens agents join the existing Phase 0.5
dispatch with `pr-review-toolkit:code-reviewer`, producing one triage table and one convergence loop.
Folding rather than adding a Phase 0.6 is deliberate: fixes made in a later, separate phase would
reach the commit without any correctness pass over them, whereas a shared loop re-reviews every fix —
correctness or quality — on its next iteration by construction.

- Phase renamed from "Claude code-review gate" to "Local review gate (correctness + quality)".
- Triage records each finding's **provenance** (correctness reviewer vs which lens), so the phase's
  existing "every reviewer finding is by construction a penetration of this gate" framing is not
  applied to quality findings, which carry no such implication.
- Quality findings are **never blockers**. An actionable one is fixed; anything else closes as a
  recorded deferral through the normal `finding-triage` path.

### Layer 3b — Documentation touchpoints

- `home/.claude/commands/work2.md` — phase summary lines and the pipeline listing in Step 3, plus a
  note in the Review & Verification Model section that the quality lenses stay at implementation tier
  and are not subject to the Opus escalation triggers (those govern correctness and verification).
- `home/.claude/CLAUDE.md` — one line in Quality Gates pointing ad-hoc coding work at the runner
  before pushing, so tasks that never enter the pipeline still get the pass.

## Non-goals

- **Not a bug hunt.** Correctness stays with `/code-review` and the correctness reviewer. If a lens
  agent finds a bug, it reports it, but the lens set is not extended to cover correctness.
- **No auto-apply**, in either mode, ever. That is the defining property of this design.
- **No edits to existing `quality-list` item bodies** as part of this change.
- **Not wired into `/work`.** `/work` and `/work2` are deliberately independent; `/work` picks the
  pass up through the `CLAUDE.md` Quality Gates line if at all.

## Risks

| Risk | Mitigation |
|---|---|
| Double-reporting between the lens runner and `done-check` (shared slugs). | Documented as deliberate in both skills: `done-check` = breadth, lens runner = depth at two gates. Triage dedups by mechanism, as Phase 0.5 already does across reviewers. |
| Loop inflation — taste findings keep the Phase 0.5 loop spinning. | Quality findings are never blockers; the existing "same conceptual topic recurs across 2+ iterations → escalate" rule in Rules covers them unchanged. |
| Token cost — five agents per Phase 0.5 iteration instead of one. | Agents are parallel, so wall-clock is flat; the lens agents are read-only and run at implementation tier. Revisit if a run shows the loop iterating more than twice. |
| The `lens:` tag drifts from the item set. | Tag lives in the same index line as the lane, so adding an item forces the author past both tags. |

## Verification Plan

These are prompt documents; there is nothing to unit-test. Verification is:

1. Read back each edited section against this spec.
2. Confirm the runner's lens set is derived from the index — grep the new skill for any hardcoded slug
   list and confirm there is none.
3. Confirm no `quality-list` item prose was copied into the runner.
4. On the next real `/work2` run: confirm the plan gate produces lens findings before approval, that
   an altitude finding routes as a premise concern, and that Phase 0.5 emits one triage table with
   provenance recorded.
