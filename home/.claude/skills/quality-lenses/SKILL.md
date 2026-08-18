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

The lens *vocabulary* is fixed by this file — the four names below, each with its own framing. The lens *membership* is derived: adding an item to `quality-list` and tagging it with an existing lens changes this skill's behaviour with no edit here, which is the point. Introducing a fifth lens value does require an edit here, to give it framing.

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

`<REPO>` is the absolute path of the directory that *contains* the `skills/` directory — on this machine `/home/hobe/.claude`, so that `<REPO>/skills/quality-list/items/<slug>.md` resolves to a real file. It is not the skills directory itself; resolving it that way yields `.../skills/skills/...` and the agent reads nothing. Resolve it before dispatch and embed the resolved path — never the placeholder. A dispatched agent has no access to the conversation that assembled its prompt, so an unresolved `<REPO>` leaves it unable to find the item files it is told to read. Embed only the resolved paths and the target: **do not embed item body text**, since the agent reads the item files itself and that is what keeps main context free of rule text.

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
