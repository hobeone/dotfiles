---
name: quality-list
description: Single source of truth for universal code-quality items. Definitions live in items/<slug>.md; audit and preflight skills reference items by slug.
---

# Quality List (SSOT)

This skill is **a definition file, not a runnable procedure**. Skills that audit or preflight against universal code-quality apply these items by reference. When an item changes, referencing skills pick up the change automatically — do not copy item text into them. The Items index below is likewise the single source of truth for **which items exist and which lane each belongs to**: runners derive their active item set by reading this index, never by hardcoding a parallel slug list. Adding an item here propagates to every runner automatically.

## Audit lanes

Each item is tagged for which audit lane it belongs to in `done-check`'s split between fresh-context subagent audit and main-context audit:

- **mechanical** — judgable from literal diff text + literal code text + literal rule text alone, with no need for conversation history, plan context, or actual command execution. Delegated to a fresh-context subagent in `done-check` Step 2 to neutralize the author's blindspot for what their own comments and code actually say (vs what they meant them to say).
- **contextual** — requires plan / intent / review history that only the main context has, OR requires running a command against the working tree to gather evidence. Stays in main context.

A small number of items are **dual-lane**: their detection has both mechanical (literal-grep) and contextual (history-aware) signals. Such items appear in both audit lanes; consumers (`done-check`) route the relevant signal to the appropriate context. The current dual-lane item is `ported-code-attribution` (declared port = mechanical, undeclared port = contextual).

Each item's lane is declared once, in the Items index below (the `— mechanical` / `— contextual` suffix on each entry). Item files do not carry a lane tag in their H1 heading.

## Items

Listed in canonical reading order. Reference items by slug (e.g., `behavior-coverage`); numbering is not stable and not part of the SSOT.

- [invariant-derivation](items/invariant-derivation.md) — contextual
- [purpose-verification](items/purpose-verification.md) — contextual
- [pattern-audit](items/pattern-audit.md) — contextual
- [duplication-extraction](items/duplication-extraction.md) — mechanical
- [scope-discipline](items/scope-discipline.md) — contextual
- [behavior-coverage](items/behavior-coverage.md) — mechanical
- [implementation-guards](items/implementation-guards.md) — mechanical
- [impact-verification](items/impact-verification.md) — mechanical
- [test-execution](items/test-execution.md) — contextual
- [completion-hygiene](items/completion-hygiene.md) — contextual
- [architectural-boundary](items/architectural-boundary.md) — mechanical
- [escape-hatch-necessity](items/escape-hatch-necessity.md) — contextual
- [paired-artifact-drift](items/paired-artifact-drift.md) — mechanical
- [docstring-drift](items/docstring-drift.md) — contextual
- [discovery-surfacing](items/discovery-surfacing.md) — contextual
- [ported-code-attribution](items/ported-code-attribution.md) — mechanical (+ contextual half)
- [signature-change-regression](items/signature-change-regression.md) — mechanical
- [public-doc-durability](items/public-doc-durability.md) — mechanical
- [public-api-surface](items/public-api-surface.md) — mechanical

Language-specific addenda live alongside this file as `lang-<language>.md` and supplement specific items with triggers and mitigation idioms (current examples: `lang-cpp.md`, `lang-rust.md`). An addendum section **realizes** an item concretely; it never **bounds** the item: its triggers and N/A criteria scope only that realization, and a diff outside the realization's constructs remains subject to the base item's conditions.
