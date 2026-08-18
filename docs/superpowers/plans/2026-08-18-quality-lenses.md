# Quality Lenses Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the four `/simplify` review angles into a findings-only pass that runs against the plan during research and against the diff before the first commit.

**Architecture:** Three layers. Item text lives in `quality-list` (the SSOT) and gains one new item plus a per-item `lens:` tag. A new runner skill `quality-lenses` derives its lens set from that index and dispatches one fresh-context agent per lens, returning findings only — it never edits. Two call sites consume it: `research` Step 3.5 (plan mode) and `review-pipeline-coderabbit` Phase 0.5 (diff mode).

**Tech Stack:** Markdown prompt documents under `home/.claude/` in the dotfiles repo, symlinked into `~/.claude/` by GNU Stow. No compiled code, no runtime.

**Spec:** `docs/superpowers/specs/2026-08-18-quality-lenses-design.md`

## Global Constraints

- **Repo root for all paths:** `/home/hobe/dotfiles`. Every path below is relative to it.
- **`home/.claude/` is already stowed** as symlinks into `~/.claude/`. Edits take effect immediately; do **not** run `./install.sh`.
- **Never copy `quality-list` item prose into a runner.** Runners reference items by slug and read bodies in the subagent's own context (`quality-list/SKILL.md`: *"do not copy item text into them"*).
- **Never hardcode a slug list in a runner.** Runners derive their active item set by reading the Items index (`quality-list/SKILL.md`: *"never by hardcoding a parallel slug list"*).
- **The runner never edits code**, in either mode. This is the defining property of the design.
- **Branch:** `feat/quality-lenses`, already created, already carrying the spec commit `b85d0ce`. Do not push to `master`.
- **Commit style:** Conventional Commits, footer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## A note on "tests" for this plan

These are prompt documents; there is no test runner. The TDD cycle is preserved in the only form it can take here: **each task begins with a verification command that fails, and ends with the same command passing.** The commands are `grep`/`test` invocations against the edited files. Run them exactly as written — a step that says "expected: exit 1" means the grep must find nothing yet.

Two verifications are judgement-based rather than mechanical and are called out where they occur (Task 3 Step 6, Task 5 Step 5).

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `home/.claude/skills/quality-list/items/efficiency-waste.md` | New item definition: wasted work the diff introduces. | 1 |
| `home/.claude/skills/quality-list/SKILL.md` | Items index — registers the new item (T1) and gains the `lens:` tag plus its contract (T2). | 1, 2 |
| `home/.claude/skills/todo-check/SKILL.md` | Preflight quick-reference row for the new item. | 1 |
| `home/.claude/skills/quality-lenses/SKILL.md` | **New runner.** Resolves lenses from the index, dispatches one agent per lens, returns findings. | 3 |
| `home/.claude/skills/research/SKILL.md` | Call site A — Step 3.5 plan gate. | 4 |
| `home/.claude/skills/review-pipeline-coderabbit/SKILL.md` | Call site B — Phase 0.5 diff gate, plus a Rules entry. | 5 |
| `home/.claude/commands/work2.md` | Pipeline summary + Review & Verification Model note. | 6 |
| `home/.claude/CLAUDE.md` | Quality Gates line for ad-hoc work outside the pipeline. | 6 |

Task order is dependency order: the runner (T3) reads the tags written in T2, which register the item added in T1. The call sites (T4, T5) invoke the runner. T6 is documentation and touches nothing the others depend on.

---

### Task 1: Add the `efficiency-waste` item

The only lens with no existing `quality-list` coverage. Everything else in the design reuses items that already exist.

**Files:**
- Create: `home/.claude/skills/quality-list/items/efficiency-waste.md`
- Modify: `home/.claude/skills/quality-list/SKILL.md` (Items index, after the `public-api-surface` line)
- Modify: `home/.claude/skills/todo-check/SKILL.md` (Preflight framing quick reference list)

**Interfaces:**
- Consumes: nothing.
- Produces: the slug `efficiency-waste`, lane `mechanical`. Task 2 tags it `lens: efficiency`; Task 3's runner reaches it only through that tag.

- [ ] **Step 1: Verify the item does not exist yet**

```bash
cd /home/hobe/dotfiles
grep -r "efficiency-waste" home/.claude/ ; echo "exit=$?"
```

Expected: no output, `exit=1`.

- [ ] **Step 2: Create the item file**

Write `home/.claude/skills/quality-list/items/efficiency-waste.md` with exactly this content:

```markdown
# Efficiency waste

When a diff introduces work the program does not need to do, the waste is the finding: name the cheaper alternative. Four forms, all judgable from the literal diff text:

1. **Redundant computation or repeated I/O** — the same value recomputed per iteration when it is loop-invariant; the same file, query, or request issued more than once where one result would serve.
2. **Sequential independent operations** — two or more operations with no data dependency between them, awaited one after another, where the runtime offers a concurrent form.
3. **Work added to startup or a hot path** — initialization, parsing, or I/O introduced into a path the program runs on every request, every frame, or every process launch, when it could be deferred, cached, or hoisted out.
4. **Long-lived objects built from closures or captured environments** — a closure, bound method, or partial application that outlives the scope it captured keeps that entire enclosing scope alive for the object's lifetime. When the captured scope holds large values, this is a memory leak with no visible allocation site. Prefer a class or struct that copies only the fields it needs.

Form 4 is the one a reviewer is least likely to catch by inspection and the one with the largest blast radius, because nothing at the allocation site names the retained data.

**Concern conditions:**

- A diff introduces any of the four forms above, and a cheaper alternative exists that does not change observable behavior.

**N/A:**

- The diff adds no new computation, I/O, concurrency structure, or captured-scope object.
- The apparent waste is required for correctness — an intentional re-read to observe external mutation, a deliberate sequential ordering enforcing a happens-before relationship, an eager initialization a later invariant depends on.
- The cheaper alternative would change observable behavior (evaluation order a caller depends on, timing a test asserts, identity semantics of a returned value). That makes it an `impact-verification` question, not this item's.
- The captured scope in form 4 is small and bounded, and the object's lifetime does not exceed the scope's natural one.
```

- [ ] **Step 3: Register it in the Items index**

In `home/.claude/skills/quality-list/SKILL.md`, find this line (currently the last entry in the Items list):

```markdown
- [public-api-surface](items/public-api-surface.md) — mechanical
```

Add a new line immediately after it:

```markdown
- [efficiency-waste](items/efficiency-waste.md) — mechanical
```

Lane is `mechanical`: every one of the four forms is judgable from literal diff text plus literal code text, with no need for conversation history or command execution — the lane test stated at the top of the index.

- [ ] **Step 4: Add the todo-check preflight row**

In `home/.claude/skills/todo-check/SKILL.md`, in the `## Preflight framing per item (quick reference)` bullet list, add this bullet at the end of the list (after the `architectural-boundary` bullet and any bullets following it — append to the list's final position):

```markdown
- **`efficiency-waste`** — Identify any loop-invariant computation, repeated I/O, independent-but-sequential operations, startup/hot-path additions, or closure-captured scope the change will introduce. Plan the cheaper form now, before writing the wasteful one.
```

- [ ] **Step 5: Verify all three edits landed**

```bash
cd /home/hobe/dotfiles
test -f home/.claude/skills/quality-list/items/efficiency-waste.md && echo "item file OK"
grep -c "efficiency-waste" home/.claude/skills/quality-list/SKILL.md    # expect 1
grep -c "efficiency-waste" home/.claude/skills/todo-check/SKILL.md      # expect 1
```

Expected: `item file OK`, then `1`, then `1`.

- [ ] **Step 6: Verify the symlinked copy resolves**

```bash
cat ~/.claude/skills/quality-list/items/efficiency-waste.md | head -3
```

Expected: the `# Efficiency waste` heading. This confirms the stow symlink exposes the new file without an `install.sh` run.

- [ ] **Step 7: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/skills/quality-list/items/efficiency-waste.md \
        home/.claude/skills/quality-list/SKILL.md \
        home/.claude/skills/todo-check/SKILL.md
git commit -m "feat(quality-list): add efficiency-waste item

The four /simplify lenses map onto existing items except Efficiency,
which nothing covered: redundant I/O, sequential independent work,
hot-path additions, and closure-captured scope outliving its owner.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Add the `lens:` tag to the Items index

The tag is what lets the runner derive its lens grouping instead of hardcoding one. It is additive and inert to existing consumers (`done-check`, `todo-check`) — they read the `mechanical`/`contextual` suffix and ignore trailing text.

**Deviation from the spec, applied deliberately:** the spec says the tag may be *absent* for items in no lens. This task instead requires an explicit `lens: none`. An absent tag is indistinguishable from a forgotten one, which defeats the spec's own stated mitigation ("adding an item forces the author past both tags").

**Files:**
- Modify: `home/.claude/skills/quality-list/SKILL.md` (all 20 Items index lines + a new contract paragraph)

**Interfaces:**
- Consumes: the `efficiency-waste` index line from Task 1.
- Produces: the tag vocabulary `lens: reuse | simplification | efficiency | altitude | none`, one per index line. Task 3's runner parses exactly this.

- [ ] **Step 1: Verify no lens tags exist yet**

```bash
cd /home/hobe/dotfiles
grep -c "lens:" home/.claude/skills/quality-list/SKILL.md ; echo "exit=$?"
```

Expected: `0` and `exit=1`.

- [ ] **Step 2: Rewrite the Items index with tags**

In `home/.claude/skills/quality-list/SKILL.md`, replace the entire Items list (from the `invariant-derivation` line through the `efficiency-waste` line added in Task 1) with:

```markdown
- [invariant-derivation](items/invariant-derivation.md) — contextual — lens: none
- [purpose-verification](items/purpose-verification.md) — contextual — lens: none
- [pattern-audit](items/pattern-audit.md) — contextual — lens: reuse
- [duplication-extraction](items/duplication-extraction.md) — mechanical — lens: reuse
- [scope-discipline](items/scope-discipline.md) — contextual — lens: simplification
- [behavior-coverage](items/behavior-coverage.md) — mechanical — lens: none
- [implementation-guards](items/implementation-guards.md) — mechanical — lens: none
- [impact-verification](items/impact-verification.md) — mechanical — lens: none
- [test-execution](items/test-execution.md) — contextual — lens: none
- [completion-hygiene](items/completion-hygiene.md) — contextual — lens: simplification
- [architectural-boundary](items/architectural-boundary.md) — mechanical — lens: altitude
- [escape-hatch-necessity](items/escape-hatch-necessity.md) — contextual — lens: altitude
- [paired-artifact-drift](items/paired-artifact-drift.md) — mechanical — lens: none
- [docstring-drift](items/docstring-drift.md) — contextual — lens: none
- [discovery-surfacing](items/discovery-surfacing.md) — contextual — lens: none
- [ported-code-attribution](items/ported-code-attribution.md) — mechanical (+ contextual half) — lens: none
- [signature-change-regression](items/signature-change-regression.md) — mechanical — lens: none
- [public-doc-durability](items/public-doc-durability.md) — mechanical — lens: none
- [public-api-surface](items/public-api-surface.md) — mechanical — lens: altitude
- [efficiency-waste](items/efficiency-waste.md) — mechanical — lens: efficiency
```

Rationale for the non-obvious assignments: `completion-hygiene` covers dead code and debug artifacts left behind, which is the Simplification lens's "dead code left behind" clause. `public-api-surface` lands on Altitude because its Concern A fix is tightening the producer rather than layering defensive transformation on the consumer — the definition of fixing at the right depth.

- [ ] **Step 3: Document the tag's contract**

In the same file, immediately **after** the closing paragraph about language addenda (the paragraph beginning `Language-specific addenda live alongside this file`), append this section:

```markdown
## Lenses

Each item also carries a `lens:` tag in the index above. A lens is a **review angle**, not an audit lane: it groups items that a single dedicated reviewer should hold in mind at once. The four lenses — `reuse`, `simplification`, `efficiency`, `altitude` — are the angles the `quality-lenses` runner dispatches one agent per. Items belonging to no lens are tagged `lens: none` explicitly; an absent tag is a bug, not a value.

Lenses and lanes are orthogonal and answer different questions. The lane says *which context can judge this item* (`done-check`'s fresh-subagent vs main-context split). The lens says *which reviewer should be obsessing over it* (`quality-lenses`' parallel dispatch). An item can be mechanical and altitude, or contextual and reuse; neither tag constrains the other.

As with lanes, this index is the single source of truth for lens membership. Runners derive their lens groups by reading it — never by hardcoding a slug-to-lens table.
```

- [ ] **Step 4: Verify every item carries exactly one tag**

```bash
cd /home/hobe/dotfiles
F=home/.claude/skills/quality-list/SKILL.md
grep -c "^- \[" "$F"            # total index lines: expect 20
grep -c "^- \[.*lens: " "$F"    # tagged index lines: expect 20
grep -o "lens: [a-z]*" "$F" | sort | uniq -c
```

Expected: `20`, then `20`, then counts of `lens: altitude` 3, `lens: efficiency` 1, `lens: none` 13, `lens: reuse` 2, `lens: simplification` 2 — 21 total, because the new `## Lenses` prose mentions `lens: none` once outside the index.

- [ ] **Step 5: Verify the existing consumers still parse the lane**

```bash
cd /home/hobe/dotfiles
grep "^- \[ported-code-attribution\]" home/.claude/skills/quality-list/SKILL.md
```

Expected: the line still reads `— mechanical (+ contextual half) — lens: none`. This is the one entry whose lane suffix is compound; confirm the lens tag was appended after it rather than inserted into it, since `done-check` Step 2 instructs its subagent to select on the literal string `mechanical (+ contextual half)`.

- [ ] **Step 6: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/skills/quality-list/SKILL.md
git commit -m "feat(quality-list): tag items with review lenses

Adds a lens: tag per index entry so a runner can derive its lens groups
from the SSOT rather than hardcoding a parallel slug table. Orthogonal
to the existing audit lanes: lane says which context judges an item,
lens says which reviewer obsesses over it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Create the `quality-lenses` runner skill

**Files:**
- Create: `home/.claude/skills/quality-lenses/SKILL.md`

**Interfaces:**
- Consumes: the `lens:` tags from Task 2; `done-check` Step 1's diff-resolution commands; `done-check` Step 0's language detection.
- Produces: the skill name `quality-lenses`, invoked as `Skill: quality-lenses` with argument `plan` or `diff`. Tasks 4 and 5 invoke exactly these two modes. Its output contract is the findings table defined in Step 2 below — Task 4 and Task 5 both triage that table.

- [ ] **Step 1: Verify the skill does not exist yet**

```bash
cd /home/hobe/dotfiles
test -e home/.claude/skills/quality-lenses ; echo "exit=$?"
```

Expected: `exit=1`.

- [ ] **Step 2: Create the skill**

Write `home/.claude/skills/quality-lenses/SKILL.md` with exactly this content:

````markdown
---
name: quality-lenses
description: Dispatch one dedicated review agent per quality lens against a plan or a diff, and return findings. Read-only — it never edits. Item definitions come from quality-list by slug; lens membership comes from that index's lens: tags.
---

# Quality Lenses

A **depth** pass over the quality items, complementing `done-check`'s **breadth** pass. `done-check` applies every item as a checklist row, once, in one auditor's context. This skill takes the items belonging to a lens, hands them to an agent whose only job is that lens, and runs the lenses concurrently. Same items, different attention.

This skill **returns findings and applies nothing**. It does not edit, stage, or commit. Every finding it returns is triaged by the caller under `finding-triage`, which is where the per-item veto lives. If you find yourself wanting to fix something mid-run, stop — that decision belongs to the caller.

It hunts **quality**, not correctness. Bugs are `/code-review`'s and `pr-review-toolkit:code-reviewer`'s territory. Report a bug if a lens agent stumbles on one, but do not extend the lens set to look for them.

## Modes

Invoked with one argument:

- `plan` — the target is a plan body, passed by the caller in the invocation.
- `diff` — the target is the working state, resolved by this skill in Step 1.

## Step 0 — Resolve the lens set

Read `quality-list/SKILL.md`'s Items index. Group the slugs by their `lens:` tag. Discard `lens: none`. The resulting groups — `reuse`, `simplification`, `efficiency`, `altitude` — are the active lenses for this run.

Derive the groups from the index every run. Do **not** carry a remembered slug-to-lens table: adding an item to `quality-list` must change this skill's behavior with no edit here, which is the whole point of the tag.

A lens whose group is empty is skipped, not failed.

Detect project language(s) exactly as `done-check` Step 0 does, so each agent can load matching `quality-list/lang-<language>.md` addenda.

## Step 1 — Resolve the target

**`diff` mode** — cover all four sources, identically to `done-check` Step 1, so the two runners never disagree about what is under review:

```bash
git log --oneline @{upstream}..HEAD                       # committed
git diff @{upstream}..HEAD                                # committed content
git diff --cached                                         # staged
git diff                                                  # unstaged
git ls-files --others --exclude-standard                  # untracked paths
```

Read the contents of any untracked file relevant to the review — paths alone let you check nothing. If `@{upstream}` is unset, substitute the merge base with the default branch.

**`plan` mode** — the target is the plan body the caller passed. There is no diff. Do not go read the working tree to guess what the plan would produce; the plan's own text is the artifact under review.

## Step 2 — Dispatch one agent per lens

Launch every lens agent in a **single message** so they run concurrently. Use `subagent_type: "general-purpose"`.

Main context **must not** load the item bodies. Each agent reads its own lens's items in its own fresh context; main composes prompts and dispatches. This is `done-check` Step 2's discipline and it exists for the same reason: an author reads intent, a fresh context reads text.

Prompt shape — substitute `<REPO>`, `<LENS>`, `<SLUGS>`, `<TARGET>`, and the mode-specific framing:

```
You are reviewing under a single quality lens: <LENS>. You have NO
access to the conversation that produced this work and MUST NOT
speculate about author intent.

Read each of these quality-list item files in full and hold them as
your rule set:
<SLUGS as paths: <REPO>/skills/quality-list/items/<slug>.md>

Also load every language addendum at
<REPO>/skills/quality-list/lang-<lang>.md that exists for a detected
project language; a multi-language target has one per language and you
must load them all.

Your lens is <LENS>. Read the target below, then read the surrounding
codebase with your tools — the neighboring files, the shared/utility
modules, the siblings of anything the target touches. Your items tell
you what counts as a finding; the surrounding code is where the
evidence lives.

<TARGET>

Return findings only. You have no mandate to edit anything, and any
edit you make will be discarded. For each finding return:

- location: file:line, or the plan section heading in plan mode
- summary: one line, what is wrong
- cost: the concrete consequence — what is duplicated, what work is
  wasted, what becomes harder to maintain, what breaks next time
- item: the quality-list slug it falls under
- fix: the specific alternative, named. "Consider simplifying" is not
  a finding; "call existing helper parse_range() in utils/range.py:40
  instead of the new inline parser" is.

If your lens finds nothing, say so plainly. A clean lens is a real
result and padding it with speculation costs the caller a triage round
for nothing.
```

`<REPO>` is the absolute path of the directory holding these skills. Resolve it before dispatch and embed the resolved path — never the placeholder. A dispatched agent has no access to the conversation that assembled its prompt, so an unresolved `<REPO>` leaves it unable to find the item files it is told to read. Embed only the resolved paths and the target: **do not embed item body text**, since the agent reads the item files itself and that is what keeps main context free of rule text.

Per-lens framing to append to `<LENS>`, matching the lens's own angle:

- **reuse** — Grep the shared and utility modules, and the files adjacent to the target, for an existing implementation of anything the target introduces. Name the existing helper to call instead. A finding without a named existing helper is not a reuse finding.
- **simplification** — Look for complexity the target *adds*: redundant or derivable state, copy-paste with slight variation, deep nesting, dead code left behind. Name the simpler form that does the same job.
- **efficiency** — Look for work the target introduces that the program does not need to do. Pay particular attention to long-lived objects built from closures or captured environments, whose retained scope has no visible allocation site.
- **altitude** — Ask whether each change sits at the right depth. Special cases layered on shared infrastructure are the signal that a fix is too shallow; prefer generalizing the underlying mechanism. In `plan` mode this is the highest-value lens, because depth is nearly free to change in a plan and expensive to change in merged code.

## Step 3 — Collate and return

Dedup findings that point at the same line or the same mechanism — lenses overlap at the edges (a copy-pasted block is both `reuse` and `simplification`), and the caller should triage one finding, not two. Keep the lens attribution on the surviving finding; when two lenses agree, say so, because agreement across independent lenses is evidence.

Return a table: location, lens, item slug, summary, cost, fix. Report clean lenses explicitly so the caller can see coverage rather than infer it.

Then stop. Triage, fixes, `done-check`, and commits all belong to the caller.

## Rules

- **Never edit.** No exceptions, no "it was a one-word fix". The read-only property is what makes this composable with `finding-triage`.
- **Never hardcode the lens groups.** Read the index every run.
- **Never copy item text into this file.** Agents read item bodies themselves.
- **Quality findings are not blockers.** The caller decides; an unactioned finding closes as a recorded deferral, not a failure.
- **Do not re-run to convergence on your own.** A single pass per invocation. Convergence loops belong to the calling gate, which knows how many rounds it has spent.
````

- [ ] **Step 3: Verify the skill file exists and declares its name**

```bash
cd /home/hobe/dotfiles
head -4 home/.claude/skills/quality-lenses/SKILL.md
```

Expected: frontmatter with `name: quality-lenses`.

- [ ] **Step 4: Verify no hardcoded slug list leaked in**

```bash
cd /home/hobe/dotfiles
grep -nE "duplication-extraction|scope-discipline|architectural-boundary|escape-hatch|efficiency-waste|pattern-audit|public-api-surface|completion-hygiene" \
  home/.claude/skills/quality-lenses/SKILL.md ; echo "exit=$?"
```

Expected: no output, `exit=1`. Any hit means a slug-to-lens table leaked into the runner — the exact thing the SSOT forbids. Remove it and re-run.

- [ ] **Step 5: Verify no item prose was copied**

```bash
cd /home/hobe/dotfiles
grep -c "Concern conditions" home/.claude/skills/quality-lenses/SKILL.md
```

Expected: `0`. Item bodies carry that heading; the runner must not.

- [ ] **Step 6: Judgement check — symlink and readability**

```bash
cd /home/hobe/dotfiles
ls -l ~/.claude/skills/quality-lenses 2>&1
```

If this reports "No such file or directory", the new skill directory is not covered by an existing stow symlink (`~/.claude/skills/` contains per-skill symlinks, not one directory symlink). Create it:

```bash
ln -s /home/hobe/dotfiles/home/.claude/skills/quality-lenses ~/.claude/skills/quality-lenses
ls -l ~/.claude/skills/quality-lenses
```

Then read the file top to bottom once and confirm the dispatch prompt is self-contained — an agent receiving it has the paths it needs, knows it may not edit, and knows what a finding must contain.

- [ ] **Step 7: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/skills/quality-lenses/SKILL.md
git commit -m "feat(quality-lenses): add findings-only lens runner

Dispatches one dedicated agent per quality lens against a plan or a
diff and returns findings. Unlike the built-in /simplify it applies
nothing, so every finding passes through finding-triage where the
per-item veto lives.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Wire the plan gate (`research` Step 3.5)

The primary call site. Removing complexity from a plan costs a sentence; removing it from merged code costs a rewrite.

**Files:**
- Modify: `home/.claude/skills/research/SKILL.md` (Step 3.5, items 1 and 2)

**Interfaces:**
- Consumes: `Skill: quality-lenses` in `plan` mode (Task 3).
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Verify the call site is absent**

```bash
cd /home/hobe/dotfiles
grep -c "quality-lenses" home/.claude/skills/research/SKILL.md ; echo "exit=$?"
```

Expected: `0`, `exit=1`.

- [ ] **Step 2: Add the lens pass to the review dispatch**

In `home/.claude/skills/research/SKILL.md`, Step 3.5 item 1, find this paragraph:

```markdown
   If run: dispatch a fresh-context subagent (no access to this conversation) with the plan body, the issue/task text, and instructions to look for (a) implementation soundness given the plan's own stated assumptions, and (b) whether those assumptions themselves actually hold — it should re-derive or spot-check at least one non-trivial claim rather than taking the plan's word for it.
```

Append a new paragraph immediately after it, at the same indentation:

```markdown
   In the same dispatch, run `Skill: quality-lenses` in `plan` mode with the plan body as its target. Its lens agents and the soundness reviewer above are independent and run concurrently — one message, not two rounds. The lens pass asks a different question than the soundness reviewer does: not "is this plan correct?" but "is this plan bigger, more duplicative, or shallower than it needs to be?". It returns findings only; it patches nothing.
```

- [ ] **Step 3: Route lens findings through the existing triage**

In Step 3.5 item 2, find this line:

```markdown
   - **Implementation concerns** (algorithm details, error handling, test coverage gaps, naming): patch the plan in place and proceed to the loop gate below.
```

Add these two bullets immediately after it, at the same indentation:

```markdown
   - **Lens findings — `reuse`, `simplification`, `efficiency`**: implementation concerns. Patch the plan in place. A reuse finding that names an existing helper deletes a planned component outright; prefer that over planning to write it and simplify later.
   - **Lens findings — `altitude`**: a finding that the plan solves the problem at the wrong depth is a **premise concern**, not an implementation one — return to Step 1 with the rest of the premise concerns. Do not patch depth in place. A plan that layers a special case on shared infrastructure is not repaired by editing the special case; the hypothesis about where the problem lives is what is wrong. This is the case the lens pass exists to catch, and patching it in place is how it gets missed.
```

- [ ] **Step 4: Verify both edits landed and the loop rules were not touched**

```bash
cd /home/hobe/dotfiles
grep -c "quality-lenses" home/.claude/skills/research/SKILL.md       # expect 1
grep -ci "premise concern" home/.claude/skills/research/SKILL.md     # expect 4
grep -n "Cap: 3 iterations" home/.claude/skills/research/SKILL.md    # must still be present
```

Expected: `1`; exactly `4`; and the iteration cap line intact. The count is case-insensitive and counts *lines*, not occurrences: the file carries three such lines today (measured, not assumed) and Step 3's altitude bullet adds the fourth. The lens pass reuses the existing loop gate and cap — it must not have introduced a second one.

- [ ] **Step 5: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/skills/research/SKILL.md
git commit -m "feat(research): run quality lenses at the plan-review gate

Complexity is nearly free to remove from a plan and expensive to remove
from merged code, so the lens pass runs here first. Altitude findings
route as premise concerns back to Step 1 rather than being patched in
place, since a wrong-depth plan is a wrong hypothesis, not a wrong step.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Wire the diff gate (`review-pipeline-coderabbit` Phase 0.5)

The safety net, for complexity that enters during implementation. Folded into the existing loop rather than added as a later phase, so every fix — correctness or quality — gets re-reviewed on the next iteration by construction.

**Files:**
- Modify: `home/.claude/skills/review-pipeline-coderabbit/SKILL.md` (Phase 0.5 heading and items 1–4; Rules section)

**Interfaces:**
- Consumes: `Skill: quality-lenses` in `diff` mode (Task 3).
- Produces: the phase's new name, "Local review gate (correctness + quality)" — Task 6 quotes it in `work2.md`.

- [ ] **Step 1: Verify the call site is absent**

```bash
cd /home/hobe/dotfiles
grep -c "quality-lenses" home/.claude/skills/review-pipeline-coderabbit/SKILL.md ; echo "exit=$?"
```

Expected: `0`, `exit=1`.

- [ ] **Step 2: Rename the phase**

Find:

```markdown
## Phase 0.5: Claude code-review gate
```

Replace with:

```markdown
## Phase 0.5: Local review gate (correctness + quality)
```

- [ ] **Step 3: Add the lens dispatch and provenance rule**

In Phase 0.5, find item 1 (the paragraph beginning ``1. `/code-review` cannot be invoked programmatically``) and item 2:

```markdown
2. Triage the output — classify each finding under the `finding-triage` SSOT dispositions.
```

Replace item 2 with these three items, renumbering the existing items 3 and 4 to 5 and 6. Item 5 additionally gets a clause replacement (see below) — its renumbering is not a plain text-preserving rename:

```markdown
2. In the same message that dispatches the correctness reviewer, run `Skill: quality-lenses` in `diff` mode. Unlike `/code-review`, `quality-lenses` **is** model-invocable — invoke the skill directly, no agent substitution. Its lens agents and the correctness reviewer are independent and run concurrently; one dispatch, one triage table, one loop.
3. Triage the combined output — classify each finding under the `finding-triage` SSOT dispositions, and record each finding's **provenance**: the correctness reviewer, or which lens. Provenance is not bookkeeping. The sentence below this list — that every later reviewer finding is by construction a penetration of this gate — is a claim about *correctness* coverage. Quality findings carry no such implication, and a CodeRabbit nit about naming is not evidence this gate leaked.
4. Quality findings are **never blockers**. An actionable one is fixed like any other; anything else closes as a recorded deferral through `finding-triage`'s normal path. Do not hold the pipeline for a taste disagreement, and do not re-dispatch the lens pass inside one iteration hoping for a softer answer — the next iteration re-runs it as part of the full gate (item 5).
```

In renumbered item 5 (formerly item 3), also replace this clause — naming only the correctness reviewer left the lens pass out of the convergence loop entirely, and item 5's original text (`/code-review`) named a skill that item 1 explicitly forbids invoking. Find:

```markdown
then re-run `/code-review` at the same effort (fresh, full review — no bias from the previous iteration)
```

Replace with:

```markdown
then re-run the full gate at the same effort — the correctness reviewer and `Skill: quality-lenses` in `diff` mode, dispatched together as in items 1–2 (fresh, full review — no bias from the previous iteration)
```

- [ ] **Step 4: Add the Rules entry**

In the `## Rules` section, add this bullet after the existing `Fix-loop substeps` bullet:

```markdown
- **Lens findings and `done-check` overlap deliberately.** The lens runner and `done-check` read the same `quality-list` items; they differ in depth and moment, not in rule set. `done-check` applies every item as a checklist row on every pass; `quality-lenses` gives one agent per lens the time to go read the surrounding code, and runs only at this gate and the plan gate. When both surface the same thing, triage it once — the duplicate is confirmation, not a second finding. Do not "fix" the overlap by removing items from either runner.
```

- [ ] **Step 5: Judgement check — read the phase end to end**

Read the whole of Phase 0.5 as edited. Confirm three things a grep cannot: the item numbering runs 1–6 with no duplicates or gaps; the convergence loop (now item 5) still says to re-run at the same effort with no bias from the previous iteration, and that instruction now plainly covers the lens pass too; and the "penetration of this gate" sentence still follows the list and now reads consistently with the provenance rule in item 3.

- [ ] **Step 6: Verify the mechanical parts**

```bash
cd /home/hobe/dotfiles
F=home/.claude/skills/review-pipeline-coderabbit/SKILL.md
grep -c "quality-lenses" "$F"                        # expect 2 (phase item 2, Rules bullet)
grep -n "^## Phase 0.5" "$F"                         # expect the renamed heading
grep -c "Claude code-review gate" "$F"               # expect 0
grep -n "^6\. Repeat until no actionable findings" "$F"  # renumbered tail of the loop
```

Expected: `2`; the renamed heading; `0`; and the final loop item now numbered 6.

- [ ] **Step 7: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/skills/review-pipeline-coderabbit/SKILL.md
git commit -m "feat(review-pipeline): fold quality lenses into Phase 0.5

Runs the lens agents in the same dispatch as the correctness reviewer
so both converge in one loop — a later separate phase would let its own
fixes reach the commit unreviewed. Findings carry provenance so quality
nits are not counted as correctness escapes.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Documentation touchpoints

Makes the pass discoverable outside the pipeline, which is what the original ask — "a generally useful step in coding tasks before we send out PRs" — was about.

**Files:**
- Modify: `home/.claude/commands/work2.md` (skills list, Phase B summary, Review & Verification Model, Step 3 pipeline listing)
- Modify: `home/.claude/CLAUDE.md` (Quality Gates)

**Interfaces:**
- Consumes: the phase name from Task 5, the skill name from Task 3.
- Produces: nothing.

- [ ] **Step 1: Verify the docs are unaware of the pass**

```bash
cd /home/hobe/dotfiles
grep -c "quality-lenses" home/.claude/commands/work2.md home/.claude/CLAUDE.md
```

Expected: `0` for both files.

- [ ] **Step 2: Add the skill to work2's skills list**

In `home/.claude/commands/work2.md`, find:

```markdown
Uses skills under `~/.claude/skills/`: `research`, `implement`, `research-and-implement`,
`review-pipeline-coderabbit`, `done-check`, `quality-list`, `stage-commit-push`, `todo-check`,
`finding-triage`, `file-pullreq`, `gh-body-check`, `gh-body-conventions`, `coderabbit-review`.
```

Replace with:

```markdown
Uses skills under `~/.claude/skills/`: `research`, `implement`, `research-and-implement`,
`review-pipeline-coderabbit`, `done-check`, `quality-list`, `quality-lenses`, `stage-commit-push`,
`todo-check`, `finding-triage`, `file-pullreq`, `gh-body-check`, `gh-body-conventions`,
`coderabbit-review`.
```

- [ ] **Step 3: Note the tier exemption in the Review & Verification Model**

In the same file, find:

```markdown
- Phase B — Claude's own `/code-review` (Phase 0.5 of the review pipeline).
```

Replace with:

```markdown
- Phase B — Claude's own `/code-review` (Phase 0.5 of the review pipeline). The `quality-lenses`
  agents sharing that dispatch are **not** covered by these triggers — they stay at implementation
  tier. The triggers exist because a missed correctness defect in persistence, concurrency, or a
  trust boundary is expensive; a missed simplification is not.
```

- [ ] **Step 4: Update the Phase A and Phase B summaries**

In the Phase A bullet list, find:

```markdown
- Phase 1 (research): posts a plan to the issue with an `Inconclusive / Deferred items` section. Its Step 3.5
  plan-review gate offers a fresh-context subagent review pass before approval — accept or skip it as
  offered. Run that subagent on Opus when a **Review & Verification Model** trigger fires (see above).
```

Replace with:

```markdown
- Phase 1 (research): posts a plan to the issue with an `Inconclusive / Deferred items` section. Its Step 3.5
  plan-review gate offers a fresh-context subagent review pass before approval — accept or skip it as
  offered. Run that subagent on Opus when a **Review & Verification Model** trigger fires (see above).
  That gate also runs `quality-lenses` in `plan` mode alongside the soundness reviewer; its altitude
  findings route as premise concerns back to Step 1, which is the one path in this pipeline that can
  send a plan back for being the wrong shape rather than wrong in a detail.
```

In the Phase B section, find:

```markdown
Run `/review-pipeline-coderabbit`, with this variance from the skill's default text.
Escalate the `/code-review` (Phase 0.5) pass to Opus when a **Review & Verification Model**
trigger fires (see above).
```

Replace with:

```markdown
Run `/review-pipeline-coderabbit`, with this variance from the skill's default text.
Escalate the correctness half of the Phase 0.5 local review gate to Opus when a **Review &
Verification Model** trigger fires (see above); the `quality-lenses` half stays at implementation tier.
```

- [ ] **Step 5: Update the Step 3 pipeline listing shown to the user**

Find:

```markdown
2. /review-pipeline-coderabbit  — local review gates (Claude /code-review), PR creation, review/fix-loop (CodeRabbit best-effort + /pr-review remote for any source)
```

Replace with:

```markdown
2. /review-pipeline-coderabbit  — local review gates (Claude /code-review + quality-lenses), PR creation, review/fix-loop (CodeRabbit best-effort + /pr-review remote for any source)
```

- [ ] **Step 6: Add the global Quality Gates line**

In `home/.claude/CLAUDE.md`, find:

```markdown
## Quality Gates

- Run quality gates (linter, formatter, tests) before pushing.
- New code needs tests. User-facing features need examples. Flag gaps.
```

Replace with:

```markdown
## Quality Gates

- Run quality gates (linter, formatter, tests) before pushing.
- New code needs tests. User-facing features need examples. Flag gaps.
- Before pushing, run `quality-lenses` in `diff` mode over the change and triage what it returns.
  `/work2` does this inside the pipeline's Phase 0.5; ad-hoc work has to invoke it. It returns
  findings only — nothing is applied without a per-item decision.
```

- [ ] **Step 7: Verify**

```bash
cd /home/hobe/dotfiles
grep -c "quality-lenses" home/.claude/commands/work2.md   # expect 5
grep -c "quality-lenses" home/.claude/CLAUDE.md           # expect 1
```

Expected: `5` and `1`.

- [ ] **Step 8: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/commands/work2.md home/.claude/CLAUDE.md
git commit -m "docs(work2): document the quality-lenses pass

Adds the global Quality Gates line so ad-hoc work outside the pipeline
gets the pass too, and records that the lens agents are exempt from the
Opus escalation triggers, which exist for correctness risk.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Final Verification

After Task 6, before opening a PR:

- [ ] **All call sites resolve to a real skill**

```bash
cd /home/hobe/dotfiles
grep -rn "quality-lenses" home/.claude/ | grep -v "skills/quality-lenses/SKILL.md"
test -f home/.claude/skills/quality-lenses/SKILL.md && echo "runner exists"
```

Every reference above must be one of: the two call sites (Tasks 4, 5), the Rules bullet (Task 5), or the doc lines (Task 6). No reference to a mode other than `plan` or `diff`.

- [ ] **The SSOT contract holds**

```bash
cd /home/hobe/dotfiles
grep -c "^- \[.*lens: " home/.claude/skills/quality-list/SKILL.md   # expect 20
grep -cE "items/[a-z-]+\.md" home/.claude/skills/quality-lenses/SKILL.md
```

The second count must be `0` for any *specific* slug path — the runner may describe the path *shape* in its dispatch prompt (`<REPO>/skills/quality-list/items/<slug>.md`) but must name no concrete slug. Inspect any hit rather than trusting the count.

- [ ] **Run the pass on its own diff**

```bash
cd /home/hobe/dotfiles
git diff master...HEAD --stat
```

Then invoke `Skill: quality-lenses` in `diff` mode against this branch. This is the first real exercise of the runner, and the branch is a fair target: six markdown files with deliberate cross-references. Triage whatever it returns under `finding-triage` and fix what is actionable. If it returns nothing at all across four lenses, treat that as suspicious and read the dispatch prompt again — a lens that cannot fire on any input is a broken lens, not a clean diff.

- [ ] **Open the PR** via `/file-pullreq`, referencing the spec at `docs/superpowers/specs/2026-08-18-quality-lenses-design.md`.
