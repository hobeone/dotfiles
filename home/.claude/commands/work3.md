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

`/work3` has **no `--attach` mode**, and this is deliberate: `/work2`'s `--attach` infers completed
phases from PR state (has a review landed, has done-check evidence been posted). That inference is
fine for `/work2`'s single conversational checkpoint, but `/work3`'s two gates close *before any PR
exists*, so there is nothing for PR state to infer from — and guessing would skip the exact
conversation the autonomy boundary depends on.

**`/work3 --resume <issue>` reads gate state instead of inferring it.** The distinction is the whole
design: a gate is resumable only when it left a record saying so.

The record already exists in substance. `premise-check`'s evidence and `solution-space`'s
three-sketch comparison are both posted to the issue as they are produced, which is where the
settled direction lives. What was missing is a declaration that a gate *closed*, so:

- **Gate 1**, on closing, posts `<!-- work3:gate1-settled -->` followed by one sentence naming the
  direction chosen and the verdict it rests on.
- **Gate 2**, on closing, posts `<!-- work3:gate2-settled -->` followed by one sentence naming the
  approved plan and how it was authorized (an explicit approval, or the instruction that satisfied
  the gate under the three-condition rule).

`--resume` reads the `[work3:*]` todos and those markers. A gate whose marker is present and names
its outcome is resumed; a gate whose marker is **absent, ambiguous, or contradicted by later
conversation on the issue is re-run in full, never inferred**. Re-running a settled gate costs one
conversation. Skipping an unsettled one costs the guarantee the command exists to provide, so the
asymmetry is deliberate and should stay.

This matters more here than the phrasing suggests: `/work3` targets exactly the work that does not
fit one sitting, and a run can spend a long stretch on premise and solution-space before a single
line of code exists. Losing that to a context boundary is the failure this prevents.

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
| After the line | A3, B, C, D | Fire-and-forget on *design*. No check-ins between tasks; ambiguity is settled by `Ruling:` and recorded. Stops here are **review-driven, never design-driven** — enumerated in full under Gate 2. |

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

Invoke `premise-check` against the issue or free text. Its Steps 1–3 (split, classify, and
null-hypothesis audit) run as that skill defines them — read them from `premise-check/SKILL.md`
rather than re-deriving them here; a copy would drift the first time that file changed, the same
pointer discipline `quality-lenses` Step 1 uses for `done-check` Step 1.

The interface `/work3` consumes out of those three steps is the **verdict token** — `holds`,
`holds-with-correction`, or `rejected` — and the **route classification** from Step 2.

**Evaluation order: verdict first, then route.** The two tokens are not independent branches run in
parallel — the verdict is settled at Gate 1 *before* any route action is taken, including the
`spike` route's termination. Otherwise a `rejected` verdict on a spike would never reach Gate 1's
fork, and the workflow would run a probe against a problem the auditor had just produced evidence
against. Concretely:

1. If the verdict is `rejected`, go straight to Gate 1's rejected-premise fork. Nothing on the
   routing table below runs until the user has chosen a branch of that fork.
2. Otherwise (`holds` or `holds-with-correction`), take the route below, then bring its output to
   Gate 1.

**Routing** by the Step 2 classification. The route's own effects are defined in
`premise-check/SKILL.md` § Routing — read them there. What follows is only what the route changes
about `/work3`'s own phases:

| Route | `/work3` consequence |
|---|---|
| `spike` | No `brainstorming` design path, no `solution-space`, no Phase A1. `/work3` ends when the recommendation is reported — a terminal path, so close out the `[work3:*]` todos before stopping (see *Terminal paths* below). |
| `bounded` | `brainstorming`'s clarifying-question step, then `solution-space` against the (possibly corrected) Problem paragraph. |
| `architectural` | `brainstorming`'s full architectural path. **`solution-space` does not run** — brainstorming already proposes multiple approaches here, and `solution-space` exists only to fill the gap in brainstorming's *bounded* path. |

On the `bounded` route, `solution-space` dispatches its three biased authors — `as-asked`,
`minimal`, `structural` — and adjudicates their sketches in main context per its own Step 2. Its
input contract is asymmetric by design (`solution-space/SKILL.md` Step 1); pass both
`premise-check` Step 1 paragraphs into the skill and let it distribute them.

## GATE 1 — Direction approval

**A conversation, not a multiple-choice question.** Present the premise verdict and — on the
`bounded` route — the three sketches from `solution-space` in chat: each with its complexity
numbers, what it does not solve, and its own self-objection, plus a recommendation and the
reasoning behind it. On the `architectural` route, present brainstorming's proposed approaches the
same way. Then stop and discuss.

The user may interrogate a sketch, ask for a fourth, ask for two to be combined, reject the
problem statement's framing itself, or send the whole thing back. Re-dispatching with an added
constraint is expected here — see `solution-space/SKILL.md` § Rules for why that is not a failure
state. There is no iteration cap and no time-box on this phase.

`AskUserQuestion` is used only to **close** the conversation once the options are settled and
mutually exclusive — never to open it.

**On closing, post the gate marker** to the issue: `<!-- work3:gate1-settled -->` followed by one
sentence naming the direction chosen and the premise verdict it rests on. This is what makes the
gate resumable (see *Check for active session*), and it is written when the decision is fresh
rather than reconstructed later from a transcript. On the `adhoc` path it is held with the other
artifacts and posted once the issue exists in Phase A2.

### The rejected-premise fork

**When the premise verdict was `rejected`**, this fork is presented *before* the route runs (see
*Evaluation order* in Phase A0), so it is reached on all three routes. Three branches:

- **Implement what was asked** — record the auditor's evidence as an accepted, acknowledged risk
  (see *Recording when no issue exists yet*, below), then take the route as classified: on
  `bounded`, run `solution-space` and proceed with its `as-asked` candidate; on `architectural`,
  run `brainstorming`'s architectural path constrained to the issue's proposed solution; on
  `spike`, run the probe as classified and terminate there.
- **Implement the real fix** — record the counter-proposal and its evidence, rewrite the Problem
  paragraph to the corrected form, then take the route against the *corrected* problem: on
  `bounded`, run `solution-space` and present its result; on `architectural`, run `brainstorming`'s
  architectural path; on `spike`, re-probe against the corrected problem. The route classification
  is re-checked against the corrected problem before this happens — correcting the problem can
  change what kind of work it is.
- **Neither — stop.** A terminal path: close out the `[work3:*]` todos before stopping (see
  *Terminal paths* below).

**Recording when no issue exists yet.** On the `adhoc` input path no tracking issue exists until
`research` Step 5.1 runs in Phase A2, so "post to the issue" has no destination at this gate. When
an issue exists, post the evidence or counter-proposal to it now. When it does not, hold the
artifact and post it as the first comment after the issue is created in Phase A2. Do not create an
issue early to have somewhere to post — this mirrors `solution-space/SKILL.md` Step 3's handling of
the same situation for the sketch comparison, and both held artifacts are posted together.

### Terminal paths

Three paths end a `/work3` run without reaching Phase D: the `spike` route at Phase A0, **Neither —
stop** at this gate, and the `subagent-driven-development` stop condition in Phase A3. Each is a
correct ending, not a failure — and each must **close out every `[work3:*]` todo** (complete the
ones that ran, cancel the ones that will not) before the turn ends. The session guard in *Check for
active session* blocks on incomplete `[work3:*]` todos, so a run that stops correctly but leaves
them open latches the guard and blocks the next `/work3` invocation.

## Phase A1 — Plan

Invoke `writing-plans` against the chosen direction. On the `architectural` route, the plan is
written against the committed spec document instead.

Tasks must be **independently testable**. This is the property Phase A3 needs to dispatch one
implementer per task, and it is also what makes the task count meaningful below — a plan whose
tasks cannot be verified alone has not been decomposed, whatever its length.

**The plan MUST carry an `Inconclusive / Deferred items` section**, in the shape `research` Step 5
mandates — each item with its `probe` and `expected branches`, or the literal
`Inconclusive / Deferred items: none identified`. `writing-plans` does not ask for one, which is
why it is required here rather than left to the sub-skill.

This section is the **discovery contract**, and it is what makes Phase A3's autonomy safe rather
than merely unattended. Past the boundary an implementer settles ambiguity by `Ruling:` and keeps
going; the contract is the only thing that distinguishes an ambiguity it may settle from a finding
that refutes the plan. Without it, a design breaking under implementation has nothing to be checked
against, and the run either patches around it silently or improvises a stop the boundary does not
sanction. Both have happened.

An item belongs here when the plan *assumed* something it did not verify — that an index can be
keyed on a given field, that a value is caller-controlled, that a helper is reachable from a phase.
Those are the assumptions that break, and naming them costs a line each.

**Where the plan is recorded** depends on how much plan there is:

- **`architectural`, or 4+ independently-testable tasks** — save to
  `docs/superpowers/plans/YYYY-MM-DD-<slug>.md` and commit it, *provided the repo already has a
  `docs/` tree*. If it does not, use whatever convention the repo does use for durable notes and
  say which; if it has none, keep the plan in chat and carry it into the PR body, and say that too.
- **Fewer than 4 tasks** — the plan is presented in chat at Gate 2 and carried into the PR body.
  No file is written.

Route classification informs this; the **task count decides it**. The classification is made at
Phase A0, before the plan exists, so it cannot know how large the change turned out to be — a
`bounded` problem can still decompose into a dozen tasks that badly want a committed plan.

Inventing a directory convention a repo has never used, to hold a plan for a change smaller than
the plan, is not a planning requirement. Skipping the file for that reason is a normal outcome and
needs no apology; it is the size of the plan that decides, never the effort of writing it.

## Phase A2 — Plan validation

Execute `research` Steps **3.4**, **3.5**, and **5** *by pointer*: read them from
`research/SKILL.md` and run them **by pointer, with the one documented deviation below**, rather
than restating them here — the same pointer discipline `quality-lenses` uses for `done-check`
Step 1. Copying that text into this file would drift the first time either file changed.

- Step 3.4 is the mandatory reachability check. No deviation.
- Step 3.5 — **the one deviation.** Its item 1 is a mandatory *offer* to the user; `/work3` runs it
  as a **mandatory automatic loop** instead, because Phase A2 sits before the autonomy boundary but
  the offer itself is not a decision worth the user's turn. The soundness reviewer and
  `quality-lenses` in `plan` mode run together, findings are applied, and the pass repeats until
  clean or three rounds elapse. **Three rounds without convergence escalates to the user.**
  Everything else in 3.5 — its triage categories, its per-premise iteration counting, its
  "the plan that exits this step is the contract" rule — runs unchanged.
- Step 5 is the post-to-GitHub step (`gh-body-check` + `gh-post`), run once the plan is approved
  below. Its Step 5.1 is where an `adhoc` run's tracking issue is created; any artifacts held from
  Gate 1 (the `solution-space` comparison, the auditor's evidence or counter-proposal) are posted
  as comments immediately after it exists.

**Where Step 3.5's escape hatches go inside the automatic loop.** Step 3.5 item 2 routes altitude
lens findings and premise concerns to "return to Step 1" — a `research` step `/work3` never
executes, so that destination has to be re-pointed here. **Altitude findings and premise concerns
route back to the chosen direction**, not to the user and not to a `research` step: re-open the
direction settled at Gate 1, correct it, and re-enter Phase A1 to rewrite the plan against the
corrected direction. Per Step 3.5's own rule this resets the iteration counter, because it is a new
premise rather than another round on the old one. Only a *third* failure to converge within one
premise escalates to the user. Do not patch depth in place — that is exactly the failure Step 3.5's
altitude clause exists to prevent.

## GATE 2 — Plan approval ◀ autonomy boundary

The cleaned plan — after the automatic Step 3.5 loop has already applied its mechanical findings —
is presented to the user for approval. Running that loop first is what makes this gate worth the
user's time: the conversation here is about whether the *design* is right, not whether the
document is tidy. As at Gate 1, sending the plan back for reshaping is a normal outcome, not a
failure.

**A direct user instruction can satisfy this gate**, under three conditions, all required:

1. The instruction names the work to be done, not merely assent to continue.
2. The direction it authorizes is the one settled in the conversation immediately preceding it.
3. Nothing material has changed since — no new finding, no re-scoping, no reversed decision.

When all three hold, record the instruction as the gate's authorization in one sentence naming what
it authorized, and proceed. Re-asking "may I proceed?" for a decision the user has just made *is*
the design-driven check-in this boundary exists to remove. When any condition fails, ask.

A bare "go ahead", "continue", "sounds good", or "yes" **never** satisfies a gate. Those resume
execution; they do not grant authorization, and treating them as approval is how a gate becomes
theatre — the user is answering the turn, not the question.

This latitude covers **Gates 1 and 2 only**. Gate 3 (merge) and the PR-body approval are never
satisfied by inference, per the post-boundary stop table below: both publish something outward, and
an instruction given before the artifact existed cannot have approved it.

**On closing, post the gate marker** to the issue: `<!-- work3:gate2-settled -->` followed by one
sentence naming the approved plan and how it was authorized — an explicit approval, or the
instruction that satisfied the gate under the rule above. Recording *how* matters as much as
*that*: it is the only way a later reader, or a resumed session, can tell a decision the user made
from one the workflow inferred.

**Everything after this gate is review-driven, never design-driven.** No check-in happens merely
because a phase ended, a task finished, or the workflow wants confirmation that it is still on
course — that is the whole content of the boundary. Stops still occur after it, but every one of
them is caused by a reviewer finding something or by something needing the user's signature. They
are, exhaustively:

| Post-boundary stop | Cause |
|---|---|
| The PR-body approval in `/file-pullreq` **gate mode** (Phase B, via `review-pipeline-coderabbit` Phase 1 step 2) | A PR body needs the user's sign-off before it is published. Never auto-approved — that would contradict `gh-body-check` discipline. |
| Per-finding triage when `/pr-review remote` returns feedback (Phase B step 4 and Phase C) | A reviewer found something. Each finding is decided individually via `AskUserQuestion`. No feedback, no stop. |
| The merge-conflict check at the pipeline's merge gate | Repo state diverged; resolving it by guessing can drop work. |
| **Oscillation escalation** — the same conceptual topic recurs across 2+ review iterations (`review-pipeline-coderabbit` Phase 0.5 item 5, Phase 1's oscillation check, and its Rules § *Oscillation detection*) | The invariant behind the finding is not understood well enough to fix confidently. The pipeline halts instead of fixing again, and the escalation asks a scope question that may close the PR and refile upstream. |
| **The pre-commit branch gate** (`review-pipeline-coderabbit` Rules § *Pre-commit branch gate*) | A commit was about to land on the repo's default branch. Phase 0's worktree should make this unreachable; it is listed anyway, because an enumeration that omits stops reachable in principle is the defect this table exists to prevent. |
| **GATE 3 — merge** (Phase C) | The user merges, never Claude. |
| **The plan's design is refuted during implementation** — a discovery the plan's `Inconclusive / Deferred items` section (Phase A1) does not list, per `implement/SKILL.md` Step 3.2 | The plan is wrong, not merely incomplete, so continuing means implementing a design already known to be broken. This is NOT the design-driven check-in the boundary removes: nobody is asking whether to proceed, the premise for proceeding has been falsified. The escalation reports what was observed, why it contradicts the plan, and asks whether to re-plan or widen the contract explicitly. Step 3.2's fast-path still applies — a discovery inside a planned file, needing no new research, extending reasoning the plan already approved, is noted in the plan-vs-actual diff and NOT stopped on. |
| The named stop conditions — Phase A2's three-round non-convergence, Phase A3's SDD stop condition, the errors in *Error Handling* | Something is broken enough that guessing is worse than asking. |

This is the live distinction between `/work3` and `/work2`: `/work2` also stops for the PR body and
for review findings, and `/work3` keeps those stops deliberately. What `/work3` removes is the
design-driven check-in — the per-phase "shall I continue?" — by front-loading that conversation into
Gates 1 and 2.

---

## Phase A3 — Implementation

### Step 0 — Preflight and task brief

Run `todo-check` once over the plan. Gather its output **plus** `implement`'s recall steps —
`implement/SKILL.md` Steps 3.0.1 (pre-commit hook recall), 3.0.2 (memory recall), and 3.0.3
(project-documentation recall), referenced by number, not copied — into a **shared task-brief
preamble** handed to every SDD implementer.

SDD implementers receive fresh context, so anything not written into the brief is lost. This is
the single most likely regression in this design, and the reason the preamble is gathered once
here rather than left to each implementer to rediscover.

### Step 1 — `subagent-driven-development`

**Whether to dispatch implementers at all** follows the same threshold as the plan file in Phase A1:

- **`architectural`, or 4+ independently-testable tasks, or a plan spanning 3+ packages** — invoke
  `subagent-driven-development` per its own process. Per task: a fresh implementer working under
  `test-driven-development`'s iron law, followed by `requesting-code-review`. No check-ins between
  tasks.
- **Below that** — implement directly in this context, still under `test-driven-development`'s iron
  law. A task brief that costs more to write than the task costs to do is not fresh context, it is
  transcription.

Everything else in this phase runs in **both** modes: Step 0's preflight and shared brief, the
`Ruling:` ledger, `systematic-debugging` on any failure, Step 2's whole-branch review, and Step 3's
completion gate. The threshold governs who writes the code, not what the code must satisfy.

One thing the direct mode buys that fan-out cannot: **reviewer findings that contradict each other
have to be resolved somewhere that holds both**. Phase B dispatches several reviewers at once, by
design, and when two of them disagree the resolution needs the user's constraints and the whole
change in one context. Fresh implementers, one per task, each see one finding — so above the
threshold, expect that resolution to land here in the controller rather than in a subagent.

**Discovery handling:**

| Discovery | Handling |
|---|---|
| Inside the chosen direction's scope | `Ruling: <decision> — <why> — <cost if wrong>` in the ledger; continue. |
| Invalidates the chosen direction | **Stop.** |

The stop maps onto `subagent-driven-development`'s existing fourth stop condition ("a plan so
broken that every path forward is a guess") and is **passed as controller instruction — the
vendored skill is not edited.** It is a terminal path: close out the `[work3:*]` todos before
stopping, per Gate 1's *Terminal paths*.

`systematic-debugging` is invoked whenever an implementer or its reviewer hits a test failure or
unexpected behaviour, before any fix is proposed. It is not on the happy path.

SDD's per-task commits go through `stage-commit-push` like every other commit in these pipelines.

### Step 2 — Whole-branch review

Per `subagent-driven-development`'s own Final Review.

### Step 3 — Completion gate

`verification-before-completion` runs *before* `done-check` is allowed to report: evidence in the
same message as the claim, or the claim is not made.

## Phase B — Review pipeline

Run `review-pipeline-coderabbit` to its merge gate. **This pipeline contains user stops** — its
Phase 1 step 2 runs `/file-pullreq` in gate mode and waits for PR-body approval, and its step 4
presents `/pr-review remote`'s findings for per-finding triage. Both are review-driven stops kept
on purpose; see the enumeration under Gate 2. Two variances, carried over from `/work2` verbatim in
substance:

- **CodeRabbit is best-effort and never a stop condition.** If it never responds (rate limit, app
  not installed, whatever), that's expected, not a stop condition.
- **The PR-description delta applies only to umbrella-tracked sub-issues** (`Parent: #N` in the
  issue body). Most issues don't use that convention, so this self-skips — expected, not a bug.

### Two rules that apply to every review round, in Phase B and Phase C alike

**1. Count the feedback before reading any of it.** Feedback arrives on three independent
endpoints and a reviewer may use any of them. Enumerate IDs and count first:

```bash
gh api repos/OWNER/REPO/pulls/N/comments  --paginate -q '.[].id' | wc -l   # inline
gh api repos/OWNER/REPO/pulls/N/reviews   --paginate -q '.[].id' | wc -l   # review bodies
gh api repos/OWNER/REPO/issues/N/comments --paginate -q '.[].id' | wc -l   # conversation
```

Triage must then account for **every** ID, minus your own replies. **Never pipe a feedback listing
through `head`** — truncating the fetch produces a confident, wrong completeness claim, and nothing
in the output says it was cut. This is not hypothetical: a run reported "seven actionable comments"
as the total while an entire eight-finding review, three of them Major, sat unread below the cut.

A count that does not match what you triaged is a stop, not a rounding error.

**2. Re-review the fix commits, not the branch.** After each round of fixes lands, review
`git diff <round-start>..HEAD` — the fixes themselves — before declaring the round done. A fix that
lands cleanly can introduce a new defect in the code it just touched, and that is a different
failure from the one *Oscillation detection* covers: oscillation is a finding that will not stay
fixed, this is a fix that creates a finding.

It has happened, and the shape is worth recognising: a review fix correctly stopped classifying an
empty record as a conflict, and left the loop *terminating* on it — converting a false report into
a missing one, which is strictly worse. The whole-branch review that preceded the round could not
have caught it, because the defect did not exist yet.

Scope this to the fix diff. It is cheap, and it targets exactly where the risk concentrates.

## Phase C — Your review

Run `/pr-review remote` feeding `receiving-code-review`. **Phase C's wait and Gate 3 are one
checkpoint, not two**: when `/pr-review remote` reports no unaddressed feedback, the merge
question is asked in the same breath rather than as a separate turn. This removes one
*design-driven* stop — the bare "review is done, shall I ask about merging?" — and is not a claim
that Gate 3 is the only post-boundary stop; the enumeration under Gate 2 is authoritative. When
`/pr-review remote` *does* return feedback, its per-finding triage stops for the user first, and
the merge question follows once the loop converges.

## GATE 3 — Merge decision

Never automatic. Ask via `AskUserQuestion`: **Merge now** / **Wait**. An approved merge still
waits for green CI and does not re-prompt once green.

## Phase D — Land and reflect

`finishing-a-development-branch` owns the integration decision and worktree cleanup. Its cleanup
is provenance-based, which matters here because `/work3` always runs in a worktree. Its
three-option menu is constrained to the pipeline's merge gate: never automatic.

If merged, continue into `review-pipeline-coderabbit`'s post-merge umbrella-drift-join phase only
when Phase B's PR-description delta step determined this PR is umbrella-tracked; otherwise there
is nothing further to do post-merge — the same self-skip as Phase B's own delta step, expected
behaviour, not a bug.

Suggest `/commit-commands:clean_gone`.

Then run `summarize-work`, then `improve-workflow`.

---

## Review & Verification Model

Carries `/work2`'s six Opus escalation triggers by reference (persistence, concurrency,
durability, cross-package interface, security, blast radius), plus one addition: **the
`premise-check` auditor is a verification role** and escalates under the same triggers, because a
false rejection there is the most expensive mistake this workflow can make. `solution-space`
authors stay at implementation tier — they are generative and their output is adjudicated before
it can do harm.

## Prerequisites

Same as `/work2`: `gh-post` present (`command -v gh-post`, stop and print the install command if
absent); CodeRabbit app assumed installed, degraded to best-effort per Phase B above.

## Error Handling

| Error | Response |
|-------|----------|
| Issue not found | "Issue #N not found. Check the number." |
| Active `[work3:*]` session exists | "Active work3 session exists. Complete or clear first." |
| `gh-post` missing | Stop, print the `uv tool install` command from Prerequisites. |
| Plan-review loop fails to converge in three rounds (Phase A2) | Escalate to the user — the automatic loop stops itself; do not force a fourth round. |
| SDD stop condition fires (Phase A3) | Stop and present the ledger's `Ruling:` entries and the blocking discovery to the user, per `subagent-driven-development`'s own Finish step. Terminal path — close out the `[work3:*]` todos. |
