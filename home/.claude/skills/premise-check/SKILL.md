---
name: premise-check
description: Split an issue into problem and proposed solution, classify its scope, and dispatch a falsifying audit of the problem itself. Returns a verdict and a route. Read-only — it never edits.
---

# Premise Check

`/work3`'s Phase A0. Every downstream gate in a normal pipeline asks whether the *plan* is sound;
none asks whether the *issue* is right. This skill asks that question, once, before any planning
starts, and it asks it adversarially — the audit in Step 3 is instructed to try to disprove the
problem, not to review it politely.

**Input:** an issue number, URL, or free-text task description.

**Output:** a verdict token and a route token, handed to the caller for Gate 1.

## Step 1 — Split

Read the issue (or the free text) and produce two labelled paragraphs:

- **Problem** — the observable bad thing, stated in the reporter's own terms. No solution
  vocabulary: describe the symptom, not the fix.
- **Proposed solution** — what the issue actually asks for.

An issue that contains only a solution and no observable problem is itself a finding, not a gap to
fill in silently. When that happens, say so explicitly, then derive the most charitable problem
statement the proposed solution implies, and record that derived statement as the Problem paragraph
— labelled as derived, not as something the reporter wrote.

## Step 2 — Classify

Invoke `brainstorming` for its spike / bounded / architectural classification — its "Three Paths"
section defines the three; do not restate the definitions here. State the classification out loud,
with the reasoning behind it, so the user can override it before routing happens. When in doubt,
take the heavier path, per that skill's ratchet.

## Step 3 — Null-hypothesis audit

Dispatch **one** fresh-context subagent under `quaere-evidence`, tasked to **falsify** the Problem
paragraph from Step 1 along exactly three axes:

1. Does it reproduce? (a failing command, test, or log — not an argument)
2. Is it already handled somewhere the reporter did not look?
3. Is it a symptom whose cause is elsewhere, such that fixing it as stated would leave the actual
   cause in place?

Frame the dispatch as a `quaere-evidence` Hypothesis: the hypothesis under test is that the problem
is real, current, and rooted where the issue says it is; the three axes above are the falsifiers.
The agent must return `file:line` references, command output, or a test for any claim it makes — an
argument alone does not count as evidence in either direction.

## Verdicts

| Verdict | Meaning | Effect |
|---|---|---|
| `holds` | Falsification failed on all three axes | Continue to routing below |
| `holds-with-correction` | Problem is real but stated wrongly (wrong symptom, wrong scope, wrong location) | Problem statement is rewritten to the corrected form; continue to routing |
| `rejected` | The audit produced evidence the problem is absent, already solved, or a symptom of a different cause | Carries to Gate 1 as a fork — not decided here |

## Routing

Route by the Step 2 classification:

| Route | Effect |
|---|---|
| `spike` | Run the probe as cheaply as correctness allows. Report a recommendation. Anything built is labelled throwaway. **Terminates here** — turning a spike's answer into implementation work is a new invocation, not a continuation of this one. |
| `bounded` | Hand off with the (possibly corrected) problem statement for a clarifying-question pass followed by solution-space exploration. |
| `architectural` | Hand off with the (possibly corrected) problem statement for the full architectural design path — clarifying questions, multiple approaches, sectioned design, spec document. |

## Rules

- **Returns `holds` whenever falsification fails.** This is the asymmetric default and it is
  deliberate: absence of proof is not proof of absence, and a false rejection here costs more than a
  false acceptance — a false acceptance costs one more audit downstream, a false rejection throws
  away a real problem before anyone gets to look at it again.
- **Never edits files.** This skill only reads, classifies, and dispatches an audit; every action
  it takes is read-only, including the subagent it dispatches in Step 3.
- **Never restate another skill's definitions — cite them.** `brainstorming`'s Three Paths and
  `quaere-evidence`'s Hypothesis/Decision vocabulary are referenced by name and section above, not
  copied. If a definition changes upstream, this file must not be the place that goes stale.
