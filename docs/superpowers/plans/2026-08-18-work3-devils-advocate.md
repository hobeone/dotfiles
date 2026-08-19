# /work3 Devil's Advocate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `/work3` — a workflow that validates an issue's premise and searches the solution space in conversation with the user, then implements the agreed design autonomously under the existing review apparatus.

**Architecture:** Two new skills (`premise-check`, `solution-space`) plus a new command (`work3.md`) that composes them with eleven vendored Superpowers skills and the existing `/work2` review pipeline. One existing skill is amended. Nothing is paraphrased: where a Superpowers skill or an existing local skill already owns behaviour, `/work3` invokes it or points at it by step number.

**Tech Stack:** Markdown prompt documents under `home/.claude/`, symlinked into `~/.claude/` by GNU Stow. No runtime, no build, no test runner.

**Spec:** `docs/superpowers/specs/2026-08-18-work3-devils-advocate-design.md`

## Global Constraints

- **Deliverables are prompt documents.** There is no test runner and no unit tests. The TDD cycle is preserved in the only form it can take here: **every task begins with a verification command that fails, and ends with the same command passing.** Run the command and read its output — do not assume.
- **`REPO` means `/home/hobe/dotfiles`.** All edits are made to files under `$REPO/home/.claude/`. Never edit files under `~/.claude/` directly — they are Stow symlinks into the repo.
- **`~/.claude/skills/` holds one symlink per skill, not one directory symlink.** Every new skill directory needs its own symlink: `ln -s $REPO/home/.claude/skills/<name> ~/.claude/skills/<name>`. `~/.claude/commands/` **is** a directory symlink, so new commands need no symlink.
- **Never edit vendored Superpowers skills.** Anything `/work3` needs beyond a vendored skill's default behaviour is passed as controller instruction in `work3.md`. The vendored tree lives at `/home/hobe/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0/skills` and its baseline checksum is verified in Task 6.
- **Never copy text from a skill you are referencing.** Point at it by name and step number. This is the same SSOT discipline `quality-list` states and `quality-lenses` follows. Several tasks below verify it with a negative grep.
- **Conventional Commits**, footer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **`/work2` must remain byte-identical** except where Task 6 explicitly touches `CLAUDE.md`. `/work3` coexists with it.

## File Structure

| File | Responsibility |
|---|---|
| `home/.claude/skills/premise-check/SKILL.md` | Split problem from proposed solution; classify; falsify the problem; emit a verdict and a route. Owns nothing else. |
| `home/.claude/skills/solution-space/SKILL.md` | Given a problem statement, produce three biased candidate solutions and adjudicate them. Never edits files. |
| `home/.claude/commands/work3.md` | The controller. Sequences phases, owns the three gates and the autonomy boundary, and carries the instructions that extend vendored skills without editing them. |
| `home/.claude/skills/review-pipeline-coderabbit/SKILL.md` | Amended: Phase 0.5's contract widens from pre-commit to pre-push. |
| `home/.claude/CLAUDE.md` | One line naming `/work3` and when to prefer it. |

---

### Task 1: `premise-check` skill

**Files:**
- Create: `home/.claude/skills/premise-check/SKILL.md`
- Create: symlink `~/.claude/skills/premise-check`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: a verdict token consumed by `work3.md` Gate 1 — exactly one of `holds`, `holds-with-correction`, `rejected` — and a route token — exactly one of `spike`, `bounded`, `architectural`. Task 4 greps for these strings; do not rename them.

- [ ] **Step 1: Run the verification command and watch it fail**

```bash
REPO=/home/hobe/dotfiles
test -L ~/.claude/skills/premise-check \
  && grep -q '^name: premise-check$' $REPO/home/.claude/skills/premise-check/SKILL.md \
  && grep -qF 'holds-with-correction' $REPO/home/.claude/skills/premise-check/SKILL.md \
  && grep -qF 'quaere-evidence' $REPO/home/.claude/skills/premise-check/SKILL.md \
  && ! grep -qF 'well-scoped change to code that already exists' $REPO/home/.claude/skills/premise-check/SKILL.md \
  && echo TASK1-PASS
```

Expected: no output, non-zero exit — the file does not exist yet.

- [ ] **Step 2: Write the skill**

Frontmatter exactly:

```markdown
---
name: premise-check
description: Split an issue into problem and proposed solution, classify its scope, and dispatch a falsifying audit of the problem itself. Returns a verdict and a route. Read-only — it never edits.
---
```

Required sections, in this order:

1. **`## Step 1 — Split`** — produce two labelled paragraphs, **Problem** (the observable bad thing, in the reporter's terms, no solution vocabulary) and **Proposed solution**. State the rule that an issue containing only a solution is itself a finding: say so explicitly, derive the most charitable problem statement it implies, and record it.
2. **`## Step 2 — Classify`** — invoke `brainstorming` for its spike / bounded / architectural verdict. **Do not restate the three definitions** — cite the skill. State the classification out loud so the user can override it.
3. **`## Step 3 — Null-hypothesis audit`** — dispatch **one** fresh-context subagent under `quaere-evidence`, tasked to **falsify** the problem along exactly three axes: (a) does it reproduce, (b) is it already handled somewhere the reporter did not look, (c) is it a symptom whose cause is elsewhere. The agent must return `file:line`, command output, or a test — not an argument.
4. **`## Verdicts`** — a table with exactly the three tokens `holds`, `holds-with-correction`, `rejected` and their effects.
5. **`## Routing`** — the three routes and what each does; `spike` terminates at a reported recommendation and never reaches planning.
6. **`## Rules`** — must include, in substance: *"Returns `holds` whenever falsification fails."* with the reason (absence of proof is not proof of absence; a false rejection costs more than a false acceptance); *"Never edits files."*; *"Never restate another skill's definitions — cite them."*

- [ ] **Step 3: Create the symlink**

```bash
ln -s /home/hobe/dotfiles/home/.claude/skills/premise-check ~/.claude/skills/premise-check
```

- [ ] **Step 4: Run the verification command and watch it pass**

Run the Step 1 command. Expected: `TASK1-PASS`.

- [ ] **Step 5: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/skills/premise-check/SKILL.md
git commit -m "feat(premise-check): add falsifying premise audit skill

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `solution-space` skill

**Files:**
- Create: `home/.claude/skills/solution-space/SKILL.md`
- Create: symlink `~/.claude/skills/solution-space`

**Interfaces:**
- Consumes: the **Problem** paragraph produced by `premise-check` Step 1.
- Produces: three candidate records whose author names are exactly `as-asked`, `minimal`, `structural`. Task 4 greps for these names; do not rename them.

- [ ] **Step 1: Run the verification command and watch it fail**

```bash
REPO=/home/hobe/dotfiles
F=$REPO/home/.claude/skills/solution-space/SKILL.md
test -L ~/.claude/skills/solution-space \
  && grep -q '^name: solution-space$' $F \
  && grep -qF 'as-asked' $F && grep -qF 'minimal' $F && grep -qF 'structural' $F \
  && grep -qF 'dispatching-parallel-agents' $F \
  && grep -qiF 'strongest objection' $F \
  && echo TASK2-PASS
```

Expected: no output, non-zero exit.

- [ ] **Step 2: Write the skill**

Frontmatter exactly:

```markdown
---
name: solution-space
description: Given a problem statement, dispatch three independent authors under mandated biases and adjudicate their candidate solutions into one recommended direction. Read-only — it never edits.
---
```

Required sections:

1. **`## Step 1 — Dispatch`** — invoke `dispatching-parallel-agents`. Three fresh-context authors, **one message**, none seeing the others. The mandate table, verbatim in substance:

   | Author | Mandate |
   |---|---|
   | `as-asked` | The issue's proposed solution, in its cheapest correct form. |
   | `minimal` | The smallest change that resolves the *problem*. Explicitly permitted to answer: delete code, change configuration, "already fixed — add a regression test", or "do nothing and document". |
   | `structural` | What the codebase would want if this problem recurs. Allowed to be larger; must justify itself against the other two. |

2. **`## Return schema`** — each author returns exactly these five fields: sketch (one paragraph); files touched; complexity added (lines, new concepts, new dependencies); what it does **not** solve; **its own strongest objection to itself**. State why the last field exists: it is the only field an author cannot fill with advocacy.
3. **`## Step 2 — Adjudicate`** — happens in **main context, not a fourth agent**, because main context holds the user's constraints and the conversation and the authors do not. Output is one recommendation plus the other two recorded as rejected-with-reason.
4. **`## Step 3 — Record`** — post the full comparison to the issue. This is the "alternatives considered" section that otherwise never gets written.
5. **`## Rules`** — must include: *"Never edits files."*; *"Never implements a candidate"* (building one to find out is a different workflow); *"Three authors, not more"* — the smallest set spanning smaller / same / bigger; *"Re-running with an added constraint is a normal outcome, not a failure."*

- [ ] **Step 3: Create the symlink**

```bash
ln -s /home/hobe/dotfiles/home/.claude/skills/solution-space ~/.claude/skills/solution-space
```

- [ ] **Step 4: Run the verification command and watch it pass**

Run the Step 1 command. Expected: `TASK2-PASS`.

- [ ] **Step 5: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/skills/solution-space/SKILL.md
git commit -m "feat(solution-space): add biased-author solution search skill

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Amend Phase 0.5's commit contract

**Files:**
- Modify: `home/.claude/skills/review-pipeline-coderabbit/SKILL.md:28` (the sentence under `## Phase 0.5: Local review gate (correctness + quality)`)

**Interfaces:**
- Consumes: nothing.
- Produces: the widened contract that Task 5's Phase A3 depends on — `subagent-driven-development` commits after every task, which the current pre-commit wording forbids.

- [ ] **Step 1: Run the verification command and watch it fail**

```bash
REPO=/home/hobe/dotfiles
F=$REPO/home/.claude/skills/review-pipeline-coderabbit/SKILL.md
! grep -qF 'before anything is committed' $F \
  && grep -qF 'before anything is pushed' $F \
  && grep -qiF 'subagent-driven-development' $F \
  && echo TASK3-PASS
```

Expected: no output, non-zero exit — the old wording is still present.

- [ ] **Step 2: Read the current sentence before changing it**

```bash
sed -n '26,30p' /home/hobe/dotfiles/home/.claude/skills/review-pipeline-coderabbit/SKILL.md
```

It currently reads: *"Runs after the done-check loop and **before anything is committed**. If a small/trivial fix was already committed before this gate was reached … run this gate against `git show <sha>` / the last commit's diff instead …"*

- [ ] **Step 3: Rewrite it**

Replace **before anything is committed** with **before anything is pushed**, and add a sentence recording *why*, so a future reader does not "restore" the old wording:

> The gate's purpose is *before anyone else sees the change*, which commits to an unpushed branch satisfy. This wording was widened deliberately: `/work3` runs `subagent-driven-development`, which commits after every task, and the earlier pre-commit wording was incompatible with it. `/work2` is unaffected — its Phase A still does not commit, so the gate still runs pre-commit there in practice.

Keep the existing small/trivial-fix carve-out sentence; it still applies and now reads naturally against the wider contract.

- [ ] **Step 4: Run the verification command and watch it pass**

Run the Step 1 command. Expected: `TASK3-PASS`.

- [ ] **Step 5: Confirm nothing else in the file changed**

```bash
git diff --stat home/.claude/skills/review-pipeline-coderabbit/SKILL.md
```

Expected: one file, a small number of changed lines confined to Phase 0.5. If the diff touches other phases, revert and redo.

- [ ] **Step 6: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/skills/review-pipeline-coderabbit/SKILL.md
git commit -m "fix(review-pipeline): widen phase 0.5 gate from pre-commit to pre-push

subagent-driven-development commits after every task, which the
pre-commit wording forbade. The gate's real contract is before anyone
else sees the change.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `work3.md` — the conversational half

**Files:**
- Create: `home/.claude/commands/work3.md`

**Interfaces:**
- Consumes: `premise-check`'s verdict and route tokens (Task 1), `solution-space`'s author names (Task 2).
- Produces: a file that Task 5 appends to. Task 5 assumes the sections written here end after Gate 2 and that a `## Phase A3 — Implementation` heading does **not** yet exist.

- [ ] **Step 1: Run the verification command and watch it fail**

```bash
REPO=/home/hobe/dotfiles
F=$REPO/home/.claude/commands/work3.md
grep -qF 'GATE 1' $F && grep -qF 'GATE 2' $F \
  && grep -qF 'autonomy boundary' $F \
  && grep -qF 'premise-check' $F && grep -qF 'solution-space' $F \
  && grep -qF 'using-git-worktrees' $F \
  && grep -qF '[work3:' $F \
  && grep -qF 'as-asked' $F && grep -qF 'structural' $F \
  && grep -qF 'spike' $F && grep -qF 'bounded' $F && grep -qF 'architectural' $F \
  && ! grep -qF 'Dead-on-arrival state' $F \
  && echo TASK4-PASS
```

Expected: no output, non-zero exit.

The final negative grep enforces pointer discipline: `research`'s reachability-check text must be **referenced**, never copied.

- [ ] **Step 2: Write the front matter and framing**

Frontmatter:

```markdown
---
argument-hint: <issue-number | URL | "description">
description: Premise-validating, solution-searching research + implement + review pipeline
---
```

Then a `# Work3` heading and:

- A **skills used** list naming every skill invoked, split into vendored Superpowers skills and local skills.
- A **`## Starting new work`** section whose first step is the session guard: block on incomplete
  `[work3:*]` todos. `/work2`'s `--attach` resume mode is **deliberately out of scope** — the spec does
  not cover it, and inferring completed phases from PR state interacts badly with the autonomy
  boundary. Say so in the file so its absence reads as a decision, not an omission.
- A **`## The autonomy boundary`** section reproducing the spec's table: phases 0/A0/A0b/A1/A2 are conversational; A3/B/C/D are fire-and-forget; the line is plan approval. State the bet in one sentence — the expensive mistakes are made before the first line of code, and the expensive interruptions happen after it. State that gate *placement*, not gate *count*, is the objective.
- **`## Identifiers`** — a `[work3:*]` todo prefix, independent of `[work:*]` and `[work2:*]`.

- [ ] **Step 3: Write Phase 0 and Phase A0**

- **`## Phase 0 — Workspace`** — invoke `using-git-worktrees`. Note explicitly that its Step 0 carries a submodule guard (`GIT_DIR != GIT_COMMON` is also true inside a submodule) that `/work2`'s hand-rolled Phase 0 lacks. Branch naming follows `/work2`'s `<type>/<issue#>-<slug>` convention.
- **`## Phase A0 — Premise`** — invoke `premise-check`. Reproduce the routing table by *route token only* (`spike` / `bounded` / `architectural`) and what each triggers. On the `bounded` route, run `brainstorming`'s clarifying-question step first — one question per message, only the ones that change the answer — then `solution-space`. On the `architectural` route, run `brainstorming`'s full architectural path and **skip `solution-space`**: brainstorming already proposes 2–3 approaches, and `solution-space` exists to fill the gap in its *bounded* path.

- [ ] **Step 4: Write Gate 1**

`## GATE 1 — Direction approval`. It must state:

- This is a **conversation, not a multiple-choice question.** Present the premise verdict and the three sketches in chat, each with complexity numbers, what it does not solve, and its own self-objection, plus a recommendation and the reasoning.
- The user may interrogate a sketch, ask for a fourth, ask two combined, reject the problem statement's framing, or send the whole thing back. **Re-running `solution-space` with an added constraint is a normal outcome, not a failure.** No iteration cap, no time-box.
- `AskUserQuestion` is used only to **close** the conversation once options are settled and mutually exclusive — never to open it.
- The **rejected-premise fork**, three branches: *implement what was asked* (auditor's evidence posted to the issue as an accepted risk); *implement the real fix* (counter-proposal and evidence posted to the issue, then `solution-space` re-runs against the corrected problem statement); *neither — stop*.

- [ ] **Step 5: Write Phase A1, Phase A2 and Gate 2**

- **`## Phase A1 — Plan`** — invoke `writing-plans` against the chosen direction (on the architectural route, against the committed spec instead). Plan saved to `docs/superpowers/plans/YYYY-MM-DD-<slug>.md` and committed. Tasks must be **independently testable**: SDD dispatches one implementer per task, and a task that cannot be verified alone cannot be reviewed alone.
- **`## Phase A2 — Plan validation`** — execute `research` Steps **3.4**, **3.5** and **5** *by pointer*: read them from `research/SKILL.md` and run them unchanged. State the reason inline — copying them here would drift the first time either file changed; this is the same pointer discipline `quality-lenses` uses for `done-check` Step 1. Step 3.5 is demoted to an **automatic loop** (soundness reviewer + `quality-lenses` in `plan` mode, repeat until clean or three rounds); three rounds without convergence escalates to the user.
- **`## GATE 2 — Plan approval ◀ autonomy boundary`** — the cleaned plan is presented for approval. State why the automatic loop runs first: the mechanical findings are already applied, so the conversation is about whether the design is right rather than whether the document is tidy. Sending the plan back for reshaping is a normal outcome. Everything after this gate runs without check-ins.

- [ ] **Step 6: Run the verification command and watch it pass**

Run the Step 1 command. Expected: `TASK4-PASS`.

- [ ] **Step 7: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/commands/work3.md
git commit -m "feat(work3): add conversational phases and gates 1-2

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: `work3.md` — the autonomous half

**Files:**
- Modify: `home/.claude/commands/work3.md` (append after Gate 2)

**Interfaces:**
- Consumes: the file as Task 4 left it.
- Produces: the complete controller.

- [ ] **Step 1: Run the verification command and watch it fail**

```bash
REPO=/home/hobe/dotfiles
F=$REPO/home/.claude/commands/work3.md
grep -qF 'GATE 3' $F \
  && grep -qF 'subagent-driven-development' $F \
  && grep -qF 'test-driven-development' $F \
  && grep -qF 'verification-before-completion' $F \
  && grep -qF 'finishing-a-development-branch' $F \
  && grep -qF 'systematic-debugging' $F \
  && grep -qF 'task-brief' $F \
  && grep -qF 'Ruling:' $F \
  && ! grep -qF 'NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST' $F \
  && echo TASK5-PASS
```

Expected: no output, non-zero exit. The final negative grep enforces that TDD's iron law is **invoked**, not transcribed.

- [ ] **Step 2: Write Phase A3 Step 0 — the task brief**

`## Phase A3 — Implementation`, then `### Step 0 — Preflight and task brief`.

Run `todo-check` once over the plan. Gather its output **plus** `implement`'s recall steps — pre-commit hook recall, memory recall, and project-documentation recall, i.e. `implement/SKILL.md` Steps 3.0.1 through 3.0.3, referenced by number, not copied — into a **shared task-brief preamble** handed to every SDD implementer.

State the reason in the file, in these terms: SDD implementers receive fresh context, so anything not written into the brief is lost. This is the single most likely regression in the design.

- [ ] **Step 3: Write Phase A3 Steps 1–3**

- **Step 1 — invoke `subagent-driven-development`.** Per task: a fresh implementer working under `test-driven-development`'s iron law, followed by `requesting-code-review`. No check-ins between tasks.
- **Discovery handling** — a two-row table:

  | Discovery | Handling |
  |---|---|
  | Inside the chosen direction's scope | `Ruling: <decision> — <why> — <cost if wrong>` in the ledger; continue. |
  | Invalidates the chosen direction | **Stop.** |

  State that the stop maps onto SDD's existing fourth stop condition ("a plan so broken that every path forward is a guess") and is **passed as controller instruction — the vendored skill is not edited.**
- **`systematic-debugging`** is invoked whenever an implementer or its reviewer hits a test failure or unexpected behaviour, before any fix is proposed. It is not on the happy path.
- **Step 2 — whole-branch review**, per SDD.
- **Step 3 — completion gate.** `verification-before-completion` runs *before* `done-check` is allowed to report: evidence in the same message as the claim, or the claim is not made.
- SDD's per-task commits go through `stage-commit-push` like every other commit in these pipelines.

- [ ] **Step 4: Write Phases B, C, D and Gate 3**

- **`## Phase B — Review pipeline`** — run `review-pipeline-coderabbit` to its merge gate. Carry over `/work2`'s two variances verbatim in substance: CodeRabbit is best-effort and never a stop condition; the PR-description delta applies only to umbrella-tracked sub-issues and self-skipping is expected.
- **`## Phase C — Your review`** — `/pr-review remote` feeding `receiving-code-review`. State that **Phase C's wait and Gate 3 are one checkpoint, not two**: when `/pr-review remote` reports no unaddressed feedback, the merge question is asked in the same breath. This is what keeps the post-boundary half to a single gate.
- **`## GATE 3 — Merge decision`** — never automatic; an approved merge still waits for green CI and does not re-prompt once green.
- **`## Phase D — Land and reflect`** — `finishing-a-development-branch` owns the integration decision and worktree cleanup (its cleanup is provenance-based, which matters because `/work3` always runs in a worktree); its three-option menu is constrained to the pipeline's merge gate. Then `summarize-work` and `improve-workflow`.

- [ ] **Step 5: Write the closing sections**

- **`## Review & Verification Model`** — carry `/work2`'s six Opus escalation triggers by reference, plus the addition: **the `premise-check` auditor is a verification role** and escalates under the same triggers, because a false rejection there is the most expensive mistake this workflow can make. `solution-space` authors stay at implementation tier — they are generative and their output is adjudicated before it can do harm.
- **`## Prerequisites`** — same as `/work2`: `gh-post` present, CodeRabbit assumed installed.
- **`## Error Handling`** — a table covering: issue not found; active `[work3:*]` session; `gh-post` missing; plan-review loop fails to converge in three rounds; SDD stop condition fired.

- [ ] **Step 6: Run the verification command and watch it pass**

Run the Step 1 command. Expected: `TASK5-PASS`. Then re-run Task 4's command and confirm it still prints `TASK4-PASS` — appending must not have disturbed the conversational half.

- [ ] **Step 7: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/commands/work3.md
git commit -m "feat(work3): add autonomous phases, gate 3 and the model policy

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Documentation pointer and whole-plan integration check

**Files:**
- Modify: `home/.claude/CLAUDE.md` (the `## PR Workflow` section)

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: the final integration evidence.

- [ ] **Step 1: Run the verification command and watch it fail**

```bash
REPO=/home/hobe/dotfiles
SP=/home/hobe/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0/skills
grep -qF '/work3' $REPO/home/.claude/CLAUDE.md \
  && test -L ~/.claude/skills/premise-check && test -L ~/.claude/skills/solution-space \
  && test -f ~/.claude/commands/work3.md \
  && [ "$(find "$SP" -name 'SKILL.md' -print0 | sort -z | xargs -0 cat | sha256sum | cut -d' ' -f1)" \
       = "0c573edfdf17fbdefeb1aa4eec150f6325ad33db0551be018a673d8dbcd68700" ] \
  && [ -z "$(cd $REPO && git diff --stat HEAD -- home/.claude/commands/work2.md)" ] \
  && echo TASK6-PASS
```

Expected: no output, non-zero exit — the `CLAUDE.md` line is missing.

The checksum assertion proves **no vendored Superpowers skill was edited**. The `git diff` assertion proves `/work2` was left alone.

- [ ] **Step 2: Add the pointer to `CLAUDE.md`**

In the `## PR Workflow` section, after the existing `/work` line, add:

```markdown
`/work3 <issue-number>` when the issue's premise is worth testing before you plan a solution to it —
it validates the premise, argues three candidate solutions with you, then implements the agreed one
without further check-ins. `/work2` remains the choice when the approach is already settled.
```

- [ ] **Step 3: Run the verification command and watch it pass**

Run the Step 1 command. Expected: `TASK6-PASS`.

- [ ] **Step 4: Verify pointer discipline across every new file**

```bash
REPO=/home/hobe/dotfiles
cd $REPO
! grep -rqF 'well-scoped change to code that already exists' home/.claude/skills/premise-check home/.claude/commands/work3.md \
  && ! grep -rqF 'NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST' home/.claude/commands/work3.md \
  && ! grep -rqF 'Dead-on-arrival state' home/.claude/commands/work3.md \
  && ! grep -rqF 'Rulings, not stalls' home/.claude/commands/work3.md \
  && echo POINTER-DISCIPLINE-PASS
```

Expected: `POINTER-DISCIPLINE-PASS`. Any hit means a referenced skill's text was copied instead of cited — fix by replacing the copied passage with a reference to the skill and step.

- [ ] **Step 5: Verify the three gates are the only human stops**

```bash
grep -c 'GATE [123]' /home/hobe/dotfiles/home/.claude/commands/work3.md
```

Expected: at least 3. Then read every `AskUserQuestion` mention in the file and confirm each sits at a gate or at a named error-handling stop — an `AskUserQuestion` between Gate 2 and Gate 3 would violate the autonomy boundary and must be removed.

- [ ] **Step 6: Commit**

```bash
cd /home/hobe/dotfiles
git add home/.claude/CLAUDE.md
git commit -m "docs(claude-md): point ad-hoc work at /work3 for unsettled premises

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Final Verification

After all six tasks, dogfood the workflow rather than trusting the greps.

- [ ] Run `TASK1-PASS` … `TASK6-PASS` and `POINTER-DISCIPLINE-PASS` commands once more, in order, on the final tree.
- [ ] Run `/work3` on a real **bounded** issue. Confirm: Gate 1 arrives as a discussion rather than a bare multiple-choice prompt, with complexity numbers and self-objections shown; Gate 2 presents an already-cleaned plan; **no check-in occurs between Gate 2 and Gate 3**; the task-brief preamble exists and carries the recall steps; `done-check` reports only after `verification-before-completion` has run.
- [ ] Run `/work3` on an issue whose premise is known to be wrong. Confirm the fork appears at Gate 1 with all three branches, and that choosing *implement the real fix* posts the counter-proposal to the issue **before** planning resumes.
- [ ] Confirm `/work2` still runs end to end, unchanged.
