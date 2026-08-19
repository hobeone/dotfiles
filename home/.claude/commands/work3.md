---
argument-hint: <issue-number | URL | "description">
description: Premise-validating, solution-searching research + implement + review pipeline
---

# Work3

Devil's advocate before code. `/work3` validates whether an issue's stated problem is real,
argues at least one genuinely smaller alternative onto the table, settles both **in conversation**
with the user, and only then implements the agreed direction fire-and-forget under the full
existing review apparatus.

**Vendored Superpowers skills:** `using-git-worktrees`, `brainstorming`, `dispatching-parallel-agents`,
`writing-plans`, `subagent-driven-development`, `test-driven-development`, `requesting-code-review`,
`receiving-code-review`, `verification-before-completion`, `finishing-a-development-branch`,
`systematic-debugging`.

**Local skills:** `premise-check`, `solution-space`, `research` (Steps 3.4/3.5/5, by pointer),
`quality-lenses`, `todo-check`, `done-check`, `review-pipeline-coderabbit`, `stage-commit-push`,
`gh-body-check`, `gh-body-conventions`, `coderabbit-review`.

## Starting new work

### 1. Check for active session

Block on incomplete `[work3:*]` todos (independent of `[work:*]` and `[work2:*]` — the three
commands' session checks do not collide with each other).

`/work3` has **no `--attach` mode.** This is deliberate, not an oversight: `/work2`'s `--attach`
infers completed phases from PR state (has a review landed, has done-check evidence been posted).
That inference is fine for `/work2`'s single conversational checkpoint, but `/work3` has two
conversational gates before any code exists, and inferring "premise already validated" or
"direction already approved" from PR state would let a resumed session skip the exact
conversation the autonomy boundary depends on. The design spec does not cover attach/resume for
this command, so it stays out of scope until a spec change adds it.

### 2. Parse input

Same as `/work2`: number → `gh issue view`, else `adhoc`; URL → extract issue number; other →
`adhoc`. If `adhoc`, `premise-check` works from the free text directly — no tracking issue is
created before Phase A0.

### 3. Present scope, confirm, create todos

```
[work3:${ID}] Run Phase 0 — workspace
[work3:${ID}] Run Phase A0 — premise-check, reach Gate 1
[work3:${ID}] Run Phase A1/A2 — plan + validation, reach Gate 2
[work3:${ID}] Run Phase A3 — implementation (autonomous)
[work3:${ID}] Run Phase B/C — review pipeline through merge gate
[work3:${ID}] Summarize and confirm merge with user
[work3:${ID}] Reflect
```

Ask via AskUserQuestion: **Start** / **Modify scope** / **Cancel**. Mark the first task
`in_progress`.

## The autonomy boundary

`/work3` is two workflows joined at one line, and the line is **Gate 2 — plan approval**:

| | Phases | Temperament |
|---|---|---|
| Before the line | 0, A0, A0b, A1, A2 | Conversational. One clarifying question per message. Sketches discussed, not just selected. No time-box, no iteration cap. |
| After the line | A3, B, C, D | Fire-and-forget. No check-ins between tasks. Ambiguity is settled by `Ruling:` and recorded. One gate (merge) plus named stop conditions. |

The bet: **the expensive mistakes are made before the first line of code, and the expensive
interruptions happen after it.** Human attention spent on premise and approach is cheap and
high-leverage; the same attention spent checking in on task 7 of 12 is neither. Gate *placement*,
not gate *count*, is the objective — an earlier draft tried to collapse everything before the line
into one `AskUserQuestion` to minimize gate count, and that was the wrong axis to optimize.

## Identifiers

Uses a `[work3:ID]` todo prefix, independent of `[work:ID]` and `[work2:ID]` — all three commands'
active-session checks are independent of each other.

| Input | Identifier |
|-------|------------|
| Issue number | `issue-<N>` |
| Ad-hoc | `adhoc` → `pr-<N>` after PR creation |

---

## Phase 0 — Workspace

Invoke `using-git-worktrees`. Its Step 0 carries a **submodule guard** — `GIT_DIR != GIT_COMMON`
is also true inside a submodule, not only inside a worktree — that `/work2`'s hand-rolled Phase 0
does not have. Branch naming follows `/work2`'s `<type>/<issue#>-<slug>` convention.

## Phase A0 — Premise

Invoke `premise-check` against the issue or free text.

**Step 1 (its Step 1)** splits the input into a Problem paragraph and a Proposed solution
paragraph. A solution-only issue is itself a finding, recorded as one, with a derived Problem
paragraph labelled as derived.

**Step 2 (its Step 2)** classifies via `brainstorming`'s spike / bounded / architectural verdict.
State the classification out loud so the user can override it before routing. When in doubt, take
the heavier path.

**Step 3 (its Step 3)** dispatches one fresh-context falsifying audit under `quaere-evidence`.
Verdict is `holds`, `holds-with-correction`, or `rejected` — `holds` is the default whenever
falsification fails, deliberately asymmetric: a false rejection here is more expensive than a
false acceptance.

**Routing** by the Step 2 classification, route token only:

| Route | What it triggers |
|---|---|
| `spike` | Run the probe as cheaply as correctness allows, report a recommendation, label anything built as throwaway. **Terminates here** — turning a spike's answer into work is a new `/work3` invocation. |
| `bounded` | Run `brainstorming`'s clarifying-question step first — one question per message, only the ones that change the answer — then invoke `solution-space` against the (possibly corrected) problem statement. |
| `architectural` | Run `brainstorming`'s full architectural path — clarifying questions, 2–3 approaches, sectioned design, spec document. **Skip `solution-space`** — brainstorming already proposes multiple approaches on this path, and `solution-space` exists only to fill the gap in brainstorming's *bounded* path. |

On the `bounded` route, `solution-space` dispatches its three biased authors — `as-asked`,
`minimal`, `structural` — and adjudicates their sketches in main context per its own Step 2.

## GATE 1 — Direction approval

**A conversation, not a multiple-choice question.** Present the premise verdict and — on the
`bounded` route — the three sketches from `solution-space` in chat: each with its complexity
numbers, what it does not solve, and its own self-objection, plus a recommendation and the
reasoning behind it. On the `architectural` route, present brainstorming's proposed approaches the
same way. Then stop and discuss.

The user may interrogate a sketch, ask for a fourth, ask for two to be combined, reject the
problem statement's framing itself, or send the whole thing back. **Re-running `solution-space`
with an added constraint is a normal outcome, not a failure** — there is no iteration cap and no
time-box on this phase.

`AskUserQuestion` is used only to **close** the conversation once the options are settled and
mutually exclusive — never to open it.

**When the premise verdict was `rejected`**, the conversation carries a fork with three branches:

- **Implement what was asked** — proceed with the `as-asked` direction. The auditor's evidence is
  posted to the issue as an accepted, acknowledged risk.
- **Implement the real fix** — post the counter-proposal and its evidence to the issue, then
  re-run `solution-space` against the corrected problem statement and present its result.
- **Neither — stop.**

## Phase A1 — Plan

Invoke `writing-plans` against the chosen direction. On the `architectural` route, the plan is
written against the committed spec document instead. The plan is saved to
`docs/superpowers/plans/YYYY-MM-DD-<slug>.md` and committed.

Tasks must be **independently testable** — Phase A3 dispatches one implementer per task via
`subagent-driven-development`, and a task that cannot be verified alone cannot be reviewed alone.

## Phase A2 — Plan validation

Execute `research` Steps **3.4**, **3.5**, and **5** *by pointer*: read them from
`research/SKILL.md` and run them unchanged rather than restating them here — the same pointer
discipline `quality-lenses` uses for `done-check` Step 1. Copying that text into this file would
drift the first time either file changed.

- Step 3.4 is the mandatory reachability check.
- Step 3.5 is **demoted from a human gate to an automatic loop**: the soundness reviewer and
  `quality-lenses` in `plan` mode run together, findings are applied, and the pass repeats until
  clean or three rounds elapse. **Three rounds without convergence escalates to the user.**
- Step 5 is the post-to-GitHub step (`gh-body-check` + `gh-post`), run once the plan is approved
  below.

## GATE 2 — Plan approval ◀ autonomy boundary

The cleaned plan — after the automatic Step 3.5 loop has already applied its mechanical findings —
is presented to the user for approval. Running that loop first is what makes this gate worth the
user's time: the conversation here is about whether the *design* is right, not whether the
document is tidy. As at Gate 1, sending the plan back for reshaping is a normal outcome, not a
failure.

**Everything after this gate runs without check-ins.**
