---
name: solution-space
description: Given a problem statement, dispatch three independent authors under mandated biases and adjudicate their candidate solutions into one recommended direction. Read-only — it never edits.
---

# Solution Space

`/work3`'s bounded-path partner to `premise-check`. That skill's Step 1 produces a Problem
paragraph; this skill takes that paragraph as its only input and turns it into competing candidate
solutions before anyone commits to a direction. The bias is the point: a single author, asked for
"a solution," anchors on whatever it first imagines. Three authors under three opposed mandates
cannot all anchor on the same thing.

**Input:** the Problem paragraph from `premise-check` Step 1.

**Output:** one recommended direction, plus the other two candidates recorded as
rejected-with-reason, posted to the issue.

## Step 1 — Dispatch

Invoke `dispatching-parallel-agents`. Three fresh-context authors, dispatched in **one message**,
none seeing the others' output or even that the others exist. Each author gets only the Problem
paragraph and its own mandate below — not the other two mandates, and not this skill's adjudication
criteria.

| Author | Mandate |
|---|---|
| `as-asked` | The issue's proposed solution, in its cheapest correct form. |
| `minimal` | The smallest change that resolves the *problem*. Explicitly permitted to answer: delete code, change configuration, "already fixed — add a regression test", or "do nothing and document". |
| `structural` | What the codebase would want if this problem recurs. Allowed to be larger; must justify itself against the other two. |

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

Post the full comparison to the issue: all three sketches, their complexity numbers, what each does
not solve, each author's self-objection, and the adjudication with its reasoning. This is the
"alternatives considered" section that otherwise never gets written, because by the time
implementation ships, the rejected paths have usually been forgotten rather than recorded.

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
