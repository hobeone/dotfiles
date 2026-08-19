# Design Spec: `/work3` — Devil's Advocate

A workflow that takes an issue or a free-text description, **validates its premise before planning
it**, **generates competing solutions before committing to one**, settles both of those *in
conversation with the user*, and then implements the agreed design fire-and-forget under the full
existing review and simplification apparatus.

`/work3` composes existing skills. It introduces two new ones and amends one; everything else is
invoked, not restated.

## Problem

`/work2` is thorough about the *outside* of a change — issue tracking, four review surfaces, PR body
discipline, a merge gate. The Superpowers skills are thorough about the *inside* — design intent,
tests, evidence. Neither is thorough about the step between them, and `/work2` has two specific gaps:

1. **No premise validation.** `/work2` treats the issue as a settled spec. Every downstream gate asks
   whether the *plan* is sound; none asks whether the *issue* is right. The `quality-lenses` altitude
   finding is the closest thing, and it only fires once a plan already exists.
2. **No solution-space search.** `research` produces exactly one plan. There is no step that proposes
   a smaller alternative and argues for it before the expensive machinery starts.

A third gap is one of composition rather than capability: `/work2` reproduces behaviour that
Superpowers already owns — worktree setup, task decomposition, the halt-vs-rule decision — instead of
invoking it. `/work3` is the correction.

## Goals

- Accept an issue number, URL, or free-text description and run to a merge-ready PR.
- **Front-load the conversation.** Premise, approach, and design are worked out *with* the user, in
  dialogue, not presented as a single multiple-choice question. This is where the user's judgment is
  worth the most and where a wrong turn is cheapest to correct.
- **Autonomy after the plan is approved.** Once the design is settled, run to a merge-ready PR with no
  *design-driven* check-in — nothing pauses merely because a phase ended. Review-driven stops remain;
  see *The autonomy boundary* below, which names where the one authoritative enumeration lives.
- Prove or disprove the problem before planning a solution to it.
- Force at least one genuinely smaller alternative onto the table before implementation begins.
- Retain every quality gate `/work2` has today: `done-check`, `quality-lenses`, `finding-triage`'s
  per-item veto, CodeRabbit, `/pr-review remote`, never auto-merge.
- Invoke Superpowers skills rather than paraphrasing them.

## Non-goals

- **Not a replacement for `/work2`.** Both coexist. `/work2` is unmodified by this change and remains
  the choice when the issue is already settled and you want a say at every step.
- **No edits to vendored Superpowers skills.** Anything `/work3` needs beyond a skill's default
  behaviour is passed as controller instruction at invocation time, never by editing files under
  `~/.claude/plugins/`.
- **`solution-space` does not implement anything.** Building a candidate to find out whether it works
  is a different workflow (see *Future work*).
- **Not wired into `/work`.** `/work` and `/work2` are already independent; `/work3` joins them.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Premise validation | A dedicated `premise-check` skill with a **falsifying** subagent | The auditor must try to disprove the problem. A reviewer asked "is this right?" agrees; one asked "prove this is wrong" produces evidence. |
| Auditor default | **Premise holds** when falsification fails | Asymmetric on purpose. The auditor must not be able to veto an issue on vibes. |
| Premise rejection | Becomes a **fork inside Gate 1**, not a new stop | User decision: the counter-proposal comes to the user, who either takes the issue as written or takes the corrected problem — recorded on the issue either way. |
| Alternatives generation | `solution-space` for **bounded** work; `brainstorming`'s full architectural path for **architectural** work | Brainstorming's architectural path already proposes 2–3 approaches. Its *bounded* path does not — that is the gap `solution-space` fills. No overlap. |
| Author count | **Three** — as-asked / minimal / structural | The smallest set spanning smaller, same, and bigger. Growing N is a separate workflow. |
| Adjudication | **Main context**, not a fourth agent | Main context holds the user's constraints and the conversation; the authors do not. |
| Implementation engine | **`subagent-driven-development`**, displacing `quaere-execution` | User decision. Fresh context per task is what makes long plans survivable; main context never accumulates implementation detail. |
| Test discipline | `test-driven-development`, iron law, inside every implementer | The single largest thing `/work2` lacks. |
| Plan authoring | `writing-plans` | SDD requires bite-sized independently-testable tasks. `research`'s prose plan body does not decompose that way. |

## The autonomy boundary

`/work3` is deliberately **two workflows joined at one line**, and the line is plan approval:

| | Phases | Temperament |
|---|---|---|
| **Before the line** | 0, A0, A0b, A1, A2 | Conversational. Clarifying questions asked one at a time. Sketches presented for discussion, not just selection. The user may interrogate, combine, reject, or ask for a fourth option. Nothing is time-boxed. |
| **After the line** | A3, B, C, D | Fire-and-forget on *design*. No check-ins between tasks; ambiguity is settled by `Ruling:` and recorded. Stops are review-driven only — enumerated below. |

The precise claim is not "no stops after the line" — Phases B and C are `/work2`'s, unchanged, and
`/work2` stops in them. The claim is that every post-boundary stop is **review-driven** (a reviewer
found something, or a PR body needs sign-off) and none is **design-driven** (no check-in happens
merely because a phase ended).

**The enumeration itself lives in `work3.md`, under Gate 2, and only there.** This spec deliberately
does not carry a second copy. An earlier revision did, and the two lists immediately diverged — one
had five entries, one had four, and both were labelled exhaustive while both in fact omitted two real
stops. A list that claims completeness is exactly the kind of text that must have a single owner: the
operational document an executing agent actually reads. This spec keeps authority over the *claim*
(review-driven only, never design-driven); `work3.md` keeps the *inventory*, because the inventory is
a fact about `review-pipeline-coderabbit`'s behaviour rather than a design decision.

Keeping this distinction sharp is what still separates `/work3` from `/work2`: both stop for
reviewers, only `/work2` stops for the workflow's own bookkeeping.

This is the design's central bet: **the expensive mistakes are made before the first line of code, and
the expensive interruptions happen after it.** Spending human attention on premise and approach is
cheap and high-leverage; spending it on task 7 of 12 is neither.

An earlier draft of this spec collapsed the pre-line phases into a single `AskUserQuestion` in pursuit
of a low gate count. That was wrong. Gate *count* is not the objective — gate *placement* is.

## Architecture

```
Phase 0   using-git-worktrees                            [superpowers]
Phase A0  premise-check                                  [NEW]
            └─ GATE 1 — premise verdict + direction
Phase A1  writing-plans  (or brainstorming's spec first) [superpowers]
Phase A2  plan validation — research Steps 3.4, 3.5, 5   [by pointer]
            └─ GATE 2 — plan approval   ◀── autonomy boundary
Phase A3  subagent-driven-development                    [superpowers]
            per task: test-driven-development
                      requesting-code-review
          whole-branch review
          verification-before-completion → done-check
Phase B   review-pipeline-coderabbit                     [existing]
Phase C   /pr-review remote → receiving-code-review
            └─ GATE 3 — merge decision
Phase D   finishing-a-development-branch → summarize-work + improve-workflow
```

Skills invoked: `using-git-worktrees`, `brainstorming`, `dispatching-parallel-agents`,
`writing-plans`, `subagent-driven-development`, `test-driven-development`, `requesting-code-review`,
`receiving-code-review`, `verification-before-completion`, `finishing-a-development-branch`, and
`systematic-debugging` on failure. Eleven, none paraphrased.

### Phase 0 — Workspace

Invoke `using-git-worktrees`. Its Step 0 carries a **submodule guard** — `GIT_DIR != GIT_COMMON` is
also true inside a submodule — that `/work2`'s hand-rolled Phase 0 lacks. Branch naming follows
`/work2`'s convention: `<type>/<issue#>-<slug>`.

Session guard uses a `[work3:*]` todo prefix, independent of `[work:*]` and `[work2:*]`.

### Phase A0 — `premise-check` (new skill)

`home/.claude/skills/premise-check/SKILL.md`.

**Input:** issue number, URL, or free text.

**Step 1 — Split.** Produce two labelled paragraphs:

- **Problem** — the observable bad thing, in the reporter's terms, with no solution vocabulary.
- **Proposed solution** — what the issue asks for.

If the issue contains only a solution and no observable problem, say so explicitly and derive the
most charitable problem statement it implies. A solution-only issue is itself a finding and is
recorded as one.

**Step 2 — Classify.** Invoke `brainstorming` for its spike / bounded / architectural verdict. State
the classification out loud so the user can override it. When in doubt take the heavier path — the
ratchet is one-way, per that skill.

**Step 3 — Null-hypothesis audit.** Dispatch one fresh-context subagent under `quaere-evidence`,
tasked to **falsify** the problem along three axes:

1. Does it reproduce? (a failing command, test, or log — not an argument)
2. Is it already handled somewhere the reporter did not look?
3. Is it a symptom whose cause is elsewhere, such that fixing it as stated leaves the cause in place?

The auditor must return `file:line` references, command output, or a test. **It returns
`premise: holds` whenever it cannot produce such evidence.** Absence of proof is not proof of absence,
and the cost of a false rejection here is higher than the cost of a false acceptance.

**Output:**

| Verdict | Meaning | Effect |
|---|---|---|
| `holds` | Falsification failed | Continue to routing |
| `holds-with-correction` | Problem is real but stated wrongly | Problem statement is rewritten; continue |
| `rejected` | Evidence that the problem is absent, already solved, or a symptom | Carries to Gate 1 as a fork |

**Step 4 — Route by classification:**

| Verdict | Path |
|---|---|
| **spike** | Run the probe as cheaply as correctness allows. Report a recommendation. Anything built is labelled throwaway. **Terminates here** — turning a spike's answer into work is a new `/work3` invocation. |
| **bounded** | Run `brainstorming`'s clarifying-question step first — one question per message, only the ones that change the answer — then `solution-space`. |
| **architectural** | Run `brainstorming`'s full architectural path — clarifying questions, 2–3 approaches, sectioned design with per-section approval, spec document, spec self-review, user review gate. Skip `solution-space`; brainstorming supplies the alternatives natively. |

Gate count therefore varies by path, deliberately, and all of the variance sits *before* the autonomy
boundary. Architectural work earns extra design conversation; bounded work gets a shorter one. Neither
changes what happens after the plan is approved.

### Phase A0b — `solution-space` (new skill, bounded path only)

`home/.claude/skills/solution-space/SKILL.md`.

**Input:** both Step 1 paragraphs from `premise-check`, distributed asymmetrically — `as-asked` is
the only author that sees the Proposed-solution paragraph (it is costing out that specific
proposal); `minimal` and `structural` see the Problem paragraph alone, because their mandates are
only worth anything unanchored from the issue's proposal.

Invoke `dispatching-parallel-agents`. Three fresh-context authors, one message, none seeing the
others, each under a **mandated bias**:

| Author | Mandate |
|---|---|
| `as-asked` | The issue's proposed solution, in its cheapest correct form. |
| `minimal` | The smallest change that resolves the *problem*. Explicitly permitted to answer: delete code, change configuration, "already fixed — add a regression test", or "do nothing and document". |
| `structural` | What the codebase would want if this problem recurs. Allowed to be larger; must justify itself against the other two. |

Each returns a fixed schema:

- Sketch — the change in a paragraph
- Files touched
- Complexity added — lines, new concepts, new dependencies
- What it does **not** solve
- **Its own strongest objection to itself**

The self-objection field is load-bearing: it is the only part of the schema an author cannot fill in
with advocacy.

**Adjudication** happens in main context. Output is one recommended direction plus the other two
recorded as rejected-with-reason. The full comparison is posted to the issue — this is the
"alternatives considered" section that otherwise never gets written.

`solution-space` never edits files.

### Gate 1 — Direction approval

**A conversation, not a multiple-choice question.** Present the premise verdict and the three sketches
in chat — each with its complexity numbers, what it does not solve, and its own self-objection — with a
recommendation and the reasoning behind it. Then stop and discuss.

The user may interrogate a sketch, ask for a fourth, ask two to be combined, reject the framing of the
problem statement itself, or send the whole thing back. Re-running `solution-space` with an added
constraint is a normal outcome here, not a failure. There is no iteration cap and no time-box; this
phase ends when the user says which direction to take, not when a counter runs out.

`AskUserQuestion` is used only to *close* the conversation once the options are genuinely settled and
mutually exclusive — never to open it.

**When the premise was rejected**, the conversation carries the fork:

- **Implement what was asked** — proceed with the `as-asked` direction. The auditor's evidence is
  posted to the issue as an accepted, acknowledged risk.
- **Implement the real fix** — post the counter-proposal and its evidence to the issue, then re-run
  `solution-space` against the corrected problem statement and present its result.
- **Neither — stop.**

### Phase A1 — Plan

Invoke `writing-plans` against the chosen direction. On the architectural path the plan is written
against the committed spec document instead. The plan is saved to
`docs/superpowers/plans/YYYY-MM-DD-<slug>.md` and committed.

The plan must decompose into tasks that are **independently testable** — SDD dispatches one implementer
per task, and a task that cannot be verified alone cannot be reviewed alone.

### Phase A2 — Plan validation

Execute `research` Steps **3.4** (the six reachability checks), **3.5** (plan-review gate), and **5**
(post to GitHub via `gh-body-check` and `gh-post`) **by pointer** — read them from
`research/SKILL.md` and run them unchanged. Do not copy their text into `work3.md`; this is the same
pointer discipline `quality-lenses` uses for `done-check` Step 1.

Step 3.5 is demoted from a human gate to an **automatic loop**: the soundness reviewer and
`quality-lenses` in `plan` mode run together, findings are applied, and the pass repeats until clean or
three rounds elapse. Altitude findings route back to the chosen direction rather than to the user.
**Three rounds without convergence escalates to the user.**

**Gate 2 — plan approval.** The cleaned plan is then presented to the user for approval. Running the
automatic loop *first* is what makes this gate worth the user's time: the mechanical findings are
already applied, so the conversation is about whether the design is right rather than whether the
document is tidy. As at Gate 1, this is a discussion — sending the plan back for reshaping is a normal
outcome.

**This gate is the autonomy boundary.** Everything after it is review-driven, never design-driven —
see *The autonomy boundary* above for the exhaustive list of post-boundary stops.

### Phase A3 — Implementation

**Step 0 — Preflight.** Run `todo-check` once over the plan. Its output, plus `implement`'s recall
steps (pre-commit hook recall, memory recall, project-documentation recall — Steps 3.0.1 through
3.0.3), are gathered into a **shared task-brief preamble**. SDD implementers receive fresh context, so
anything not written into the brief is lost. This is the single most likely regression in the whole
design and the spec calls it out for that reason.

**Step 1 — Invoke `subagent-driven-development`.** Per task: a fresh implementer working under
`test-driven-development`'s iron law, followed by `requesting-code-review`. Fix loop capped per that
skill. No check-ins between tasks.

**Discovery handling** — this is where `/work2`'s discovery contract and SDD's ruling system merge:

| Discovery | Handling |
|---|---|
| Inside the chosen direction's scope | `Ruling: <decision> — <why> — <cost if wrong>` in the ledger; continue. |
| Invalidates the chosen direction | **Stop.** Mapped onto SDD's existing fourth stop condition ("a plan so broken that every path forward is a guess"), passed as controller instruction — the vendored skill is not edited. |

**Step 2 — Whole-branch review**, per SDD.

**Step 3 — Completion gate.** `verification-before-completion` runs *before* `done-check` is allowed to
report. Evidence in the same message as the claim, or the claim is not made.

### Phases B, C, D

`review-pipeline-coderabbit` through its merge gate, then `/pr-review remote` feeding
`receiving-code-review`, then `summarize-work` and `improve-workflow`. Unchanged from `/work2` except
for the amendment below, plus two placements:

- **Phase C's wait and Gate 3 are one checkpoint, not two.** `/work2` stops the turn while waiting for
  the user's own PR review and asks the merge question afterwards. `/work3` keeps that single stop:
  when `/pr-review remote` reports no unaddressed feedback, the merge question is asked in the same
  breath. That removes a design-driven stop; it does not make Gate 3 the only post-boundary stop
  (see *The autonomy boundary*).
- **`finishing-a-development-branch` owns Phase D's integration decision and cleanup.** `/work3`
  always runs in a worktree, and that skill's cleanup is provenance-based — it knows which worktrees it
  may remove and which are externally managed. Its Step 1 green-suite requirement composes with the
  pipeline's own rule that an approved merge still waits for green CI; the stricter of the two wins.
  Its three-option menu is constrained to the pipeline's merge gate: never automatic.

`systematic-debugging` is invoked inside Phase A3 whenever an implementer or its reviewer hits a test
failure or unexpected behaviour, before any fix is proposed. It is not on the happy path.

## Amendment to an existing skill

**`review-pipeline-coderabbit` Phases 0 and 0.5 — "before any commit" becomes "before anything is
pushed."**

SDD commits after every task; the old contract said the local gates run before the first commit.
These are incompatible. The gates' actual purpose is *before anyone else sees the change*, and
commits to an unpushed worktree branch satisfy that. Both phases carry the pre-commit wording and
**both** are amended — Phase 0's done-check loop closes with the same sentence Phase 0.5 opens with,
and fixing only one leaves the defect one section higher. The amendment is noted in the skill at both
sites so a future reader does not "restore" the old wording.

`/work2` is unaffected — its Phase A still does not commit, so the gate still runs pre-commit there in
practice. The contract is widened, not narrowed.

## Model policy

`/work2`'s Review & Verification Model carries over, with one addition: **the `premise-check` auditor
is a verification role** and escalates to Opus under the same six triggers (persistence, concurrency,
durability, cross-package interface, security, blast radius). A false rejection there is the most
expensive mistake this workflow can make.

`solution-space` authors stay at implementation tier — they are generative, and their output is
adjudicated before it can do harm.

## Files

| File | Change |
|---|---|
| `home/.claude/skills/premise-check/SKILL.md` | New |
| `home/.claude/skills/solution-space/SKILL.md` | New |
| `home/.claude/commands/work3.md` | New |
| `home/.claude/skills/review-pipeline-coderabbit/SKILL.md` | Amend Phases 0 and 0.5 commit → push contract |
| `home/.claude/CLAUDE.md` | One line in PR Workflow naming `/work3` and when to prefer it |

`~/.claude/skills/` holds one symlink **per skill**, not one directory symlink — each new skill
directory needs its own symlink created, or it will not resolve.

## Risks

| Risk | Mitigation |
|---|---|
| Adjudication bias — main context wrote the problem statement and will favour its own reading. | Authors return their own strongest self-objection; all three sketches are posted to the issue where the user sees what was rejected and why. |
| Auditor false-rejects a real problem. | Asymmetric default (`holds` on failure to falsify); the verdict is a gate branch, never an auto-action; Opus escalation on the six triggers. |
| Ceremony on trivial issues. | The classification short-circuit: `spike` terminates at a report and never reaches planning; `bounded` skips brainstorming's sectioned-design and spec-document steps entirely. |
| Task-brief regression — SDD implementers lose `implement`'s recall steps. | Named explicitly as Phase A3 Step 0; the shared preamble is a required artifact, and its absence is a verification-plan check. |
| SDD's per-task commits interact badly with `stage-commit-push`'s conventional-commit discipline. | SDD commits go through `stage-commit-push` like every other commit in these pipelines. |
| Two new skills plus an engine swap is a large surface for prompt documents with no test runner. | Verification plan below; dogfood on a real issue before `/work3` is recommended for anything. |

## Verification plan

These are prompt documents; there is no test runner. Verification is:

1. **Structural.** Each new skill resolves through the stow symlink and reports its own `name:`.
   `premise-check` and `solution-space` contain no copied Superpowers prose — grep for distinctive
   phrases from the vendored skills and confirm zero hits.
2. **Pointer discipline.** `work3.md` Phase A2 references `research` Steps 3.4 / 3.5 / 5 rather than
   restating them. Confirm no reachability-check text is duplicated.
3. **No vendored edits.** `git status` in the Superpowers plugin cache is clean after a full run.
4. **Dogfood, bounded path.** Run `/work3` on a real bounded issue. Confirm: three sketches reach
   Gate 1 as a discussion rather than a bare multiple-choice prompt, with complexity numbers and
   self-objections shown; Gates 2 and 3 fire and no further check-in occurs between them; the
   task-brief preamble exists and
   carries the recall steps; `done-check` reports only after `verification-before-completion` has run.
5. **Dogfood, rejection path.** Run `/work3` on an issue whose premise is known to be wrong. Confirm
   the fork appears at Gate 1 with both branches, and that choosing "implement the real fix" posts the
   counter-proposal to the issue before planning resumes.

## Future work

The two new skills are deliberately composable, so further workflows are cheap:

- **`/work4` — Walking Skeleton.** Replace `solution-space`'s paper comparison with building the
  `minimal` candidate in a throwaway worktree and measuring it against the acceptance criteria.
  Converts "is there a simpler way?" from a debate into an experiment.
- **`/work5` — Tournament.** Grow `solution-space` to five biased authors plus a judge panel scoring on
  independent lenses, with synthesis from the winner. For issues where being wrong is expensive.

Both reuse `premise-check` unchanged and differ only in how the solution space is explored.
