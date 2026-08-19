---
name: solution-space
description: Given a problem statement, dispatch three independent authors under mandated biases and adjudicate their candidate solutions into one recommended direction. Read-only — it never edits.
---

# Solution Space

`/work3`'s bounded-path partner to `premise-check`. That skill's Step 1 produces two labelled
paragraphs; this skill takes them and turns them into competing candidate solutions before anyone
commits to a direction. The bias is the point: a single author, asked for "a solution," anchors on
whatever it first imagines. Three authors under three opposed mandates cannot all anchor on the
same thing.

**Input:** **both** paragraphs from `premise-check` Step 1 — Problem and Proposed solution. They
are *not* distributed uniformly to the authors; see the asymmetry rule in Step 1.

**Output:** one recommended direction, plus the other two candidates recorded as
rejected-with-reason, recorded per Step 3.

## Step 1 — Dispatch

Invoke `dispatching-parallel-agents`. Three fresh-context authors, dispatched in **one message**,
none seeing the others' output or even that the others exist. No author sees the other two mandates
or this skill's adjudication criteria.

| Author | Receives | Mandate |
|---|---|---|
| `as-asked` | Problem **and** Proposed solution | The issue's proposed solution, in its cheapest correct form. |
| `minimal` | Problem only | The smallest change that resolves the *problem*. Explicitly permitted to answer: delete code, change configuration, "already fixed — add a regression test", or "do nothing and document". |
| `structural` | Problem only | What the codebase would want if this problem recurs. Allowed to be larger; must justify itself against the other two. |

**The input asymmetry is deliberate — do not "fix" it.** `as-asked` is the *only* author that
receives the Proposed-solution paragraph, because its mandate is to cost out that specific
proposal; an author asked to price a solution it was never shown invents one, and the three-way
comparison loses the anchor it is being compared against. `minimal` and `structural` are withheld
that paragraph for the mirror-image reason: their mandates are only worth anything if they are
*unanchored*. An author that has read the issue's proposal will reach for a trimmed or inflated
version of it rather than an independently derived answer, and the skill collapses into three
opinions about one idea. A future editor who harmonizes this table by giving all three authors both
paragraphs destroys the skill's purpose, not an inconsistency.

## Return schema

Each author returns exactly these five fields:

- **Sketch** — the change, in one paragraph.
- **Files touched.**
- **Complexity added** — lines, new concepts, new dependencies.
- **What it does not solve.**
- **Its own strongest objection to itself.**

The last field exists because it is the only field an author cannot fill with advocacy. Every other
field can be written to make the candidate look good; asking an author to name its own best
counterargument is the one question a biased mandate cannot spin.

## Step 2 — Adjudicate

Adjudication happens in **main context, not a fourth agent**. Main context holds the user's
constraints and the conversation that led here; the three authors do not, and a fourth dispatched
agent would not either. Compare the three returns against each other and against what the user has
actually said they need. Output is one recommended direction, with the other two recorded as
rejected-with-reason — the reason is a specific field from that candidate's return, not a
restatement of "we chose differently."

## Step 3 — Record

Record the full comparison: all three sketches, their complexity numbers, what each does not solve,
each author's self-objection, and the adjudication with its reasoning. This is the "alternatives
considered" section that otherwise never gets written, because by the time implementation ships, the
rejected paths have usually been forgotten rather than recorded.

**Where it goes depends on whether an issue exists yet**, because this skill can be invoked from
free text before any tracking issue has been created:

- **An issue exists** — post the comparison to it now, as a comment.
- **No issue yet** — hold the comparison as a session artifact and post it at the first moment an
  issue exists. Do not create an issue just to have somewhere to post; issue creation belongs to
  the caller's own workflow, and this skill never takes that action.

Holding is a deferral of the *destination*, never of the writing: the comparison is composed here,
while the three returns are in hand, not reconstructed later from memory.

## Rules

- **Never edits files.** This skill only dispatches authors, reads their returns, and posts a
  comparison; every action is read-only.
- **Never implements a candidate.** Building one to find out which is best is a different workflow;
  this skill compares sketches, not working code.
- **Three authors, not more.** `as-asked`, `minimal`, `structural` is the smallest set that spans
  smaller / same / bigger than the proposed solution. A fourth mandate needs its own axis, not just
  another opinion.
- **Re-running with an added constraint is a normal outcome, not a failure.** If Gate 1 surfaces a
  constraint none of the three authors had, re-dispatch with that constraint added to the Problem
  paragraph rather than trying to patch a candidate by hand.
