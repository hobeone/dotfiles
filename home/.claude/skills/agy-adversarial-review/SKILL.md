---
name: agy-adversarial-review
description: Use to get a second-model adversarial review of local code changes by running the `agy` (Antigravity/Gemini) CLI's /adversarial-review skill inside a subagent, read-only, with the findings pre-triaged before they reach your context.
---

# agy as an Adversarial Reviewer

Run a **different model** over a diff you have already reviewed yourself. The
value is not a second opinion of the same shape — it is that a model with no
memory of writing the code, and no share in the reasoning that produced it,
fails differently. In the session this skill was written from, `agy` caught two
classes that three same-model review passes had walked straight past: **tests
that assert nothing** and **comment citations that are true but not verifiable
as written**.

Use it when a diff is finished and self-reviewed, and the cost of a defect
surviving is higher than fifteen minutes of wall clock.

**This spends Gemini quota, not Claude quota.** That is usually the point of
asking for it — say so once when you dispatch, and don't re-litigate it.

---

## The shape

```
1. Write the review prompt to a file          (the whole skill is in this step)
2. Dispatch a subagent that runs agy          (long wait + long output stay out of your context)
3. Subagent returns a triage table            (not the raw transcript)
4. You verify every ACCEPTed finding yourself (agy's conclusion can be right for a wrong reason)
5. Confirm the tree is still clean            (the script does this; do not skip it)
```

**Why a subagent.** A real run takes 9–25 minutes and prints thousands of
tokens of finding detail. Both belong in a child's context, not yours. The
child waits, reads the output file, and hands back the triage table plus a
pointer to the full text on disk.

**Why not the Gemini side's own remediation.** `/adversarial-review` on the
`agy` side is a four-phase loop that ends in Phase 3 *fixing the code*. You do
not want that — you want its findings and your own hands on the tree. Every
dispatch below stops it after Phase 2.

---

## Invocation

```bash
agy --model gemini-3.7-flash-high --effort high --mode plan \
    --print-timeout 20m \
    -p "$(cat /path/to/prompt.txt)" > /path/to/out.md 2>&1
```

Flag by flag, because each one is load-bearing:

| Flag | Why |
|---|---|
| `--model gemini-3.7-flash-high` | **The default.** Flash at high effort is what found this skill's motivating defects — the vacuous subtests and the unverifiable citations — and it is several times faster and cheaper than the pro tier. Escalate to `gemini-3.1-pro-high` only when a pass at flash comes back thin on a diff you have reason to think is deep. **Never a `claude-*` model** — `agy` can drive Claude, and that forfeits the entire reason for running it. |
| `--effort high` | Adversarial review is the case that wants it. |
| `--mode plan` | **The read-only guard.** Sets execution mode to plan rather than accept-edits, at the harness level. A prompt asking nicely not to edit is not a guard; this is. Still pair it with the prompt's read-only override — belt and braces, since the review is being told to *run commands*. |
| `--print-timeout 20m` | The default is **5m** and a real review will not finish in it — you get a truncated run that looks like a short review. Budget by scope: single task ≈ 9–14m, whole branch ≈ 20–25m. |
| `-p "$(cat …)"` | The prompt is long and structured. Compose it in a file; never inline it. |
| `> out.md 2>&1` | The subagent reads the file. Nothing streams into a context. |

**Do not reach for `--dangerously-skip-permissions`.** Claude Code's Bash
classifier blocks the flag outright. `--mode plan` is what you want anyway.

Slash commands expand in print mode by default (there is a
`--disable-slash-commands` opt-out), so a prompt whose first line is
`/adversarial-review` invokes the Gemini-side skill as intended. Confirm the
skill exists first: `ls ~/.gemini/skills/adversarial-review`.

---

## Composing the prompt

This is the whole skill. A weak prompt produces a long list of confident
non-findings, and triaging those costs more than the review saves.

Six blocks, in this order.

### 1. Target, stated as a range

```
Target: the commit range `<BASE>..<HEAD>` on branch `<branch>` in <repo>,
scoped to `<package>/`. Explicit-range target, NOT the working tree.
```

Name the range explicitly. `/adversarial-review`'s Phase 0 resolves
commit → branch → working tree in that precedence, and if you have anything
uncommitted it will happily review that instead. If the working tree is dirty
with unrelated work, say so and forbid it.

### 2. The mandatory overrides

Three, verbatim in spirit:

```
1. **STOP AFTER PHASE 2.** Phases 0, 1, 2 only. No Phase 3 remediation, no Phase 4.
2. **Strictly READ-ONLY.** Do not modify, create, or delete any file under <repo>;
   do not commit or stage. **Never `git stash`** — the stash stack is shared with
   other live sessions here and a pop can take their work. /tmp scratch is fine.
   I check `git status --short` and `git stash list` afterwards.
3. **Phase 2 triage table plus full detail to STDOUT.** No GitHub — there is no PR yet.
   Per finding: severity, file:line, one-sentence defect, concrete failure scenario,
   the exact command you ran, ACCEPT/PUSHBACK with reasoning.
```

The `git stash` prohibition is not boilerplate. A subagent in the source
session violated the same rule despite it being verbatim in its dispatch —
state it, and then actually run the check afterwards.

### 3. What the change IS

Two or three paragraphs of orientation. A reviewer that has to infer the
design from the diff spends its budget on inference and reports the design as
the finding. Name the types, the axes, the invariant the change exists to
establish.

### 4. Context so it does not report non-findings

The highest-leverage block. Enumerate, concretely:

- **What is deliberately absent** — a split change's other half, symbols that
  arrive in a later task. Without this you get "incomplete implementation"
  findings for every one of them.
- **Comments that mark themselves not-yet-true** — these are correct and
  deliberate, not stale.
- **Anything not yet wired up** — "nothing outside this package imports it
  yet, by design".
- **The repo's governing rules**, by path, with an instruction to read them in
  full *and paste them into every subagent it spawns*. A conventions angle
  without the project's own rules is worthless, and `agy` fans out internally.

### 5. Already proposed and rejected on the merits

If earlier passes settled something, list it with the reasoning:

```
**N THINGS ALREADY PROPOSED AND REJECTED ON THE MERITS. Do not re-raise them;
if you believe one is wrong, you must defeat the stated reasoning, not restate
the original claim:**
1. <claim> — <why it was rejected>
```

This is what stops the third reviewer re-deriving the first reviewer's
withdrawn finding. Requiring it to *defeat the reasoning* leaves the door open
for the case where the rejection was itself wrong.

### 6. Where to attack, in priority order

Rank the angles by where **this** diff is weak, and say why each is on the
list. Angles worth naming, because they are the ones no gate catches:

- **The central invariant, end to end** — over the final state of the whole
  range, not one commit. Ask for a sequence of exported calls that violates it.
- **Test vacuity** — *"for each test this adds, name the mutation that would
  kill it, and flag any whose assertion could be satisfied by a different code
  path than the one it names."* This phrasing is what surfaced two subtests
  that had asserted nothing for a full task.
- **Shared oracles** — a test that judges with the same predicate, latch, or
  bookkeeping the code decides by agrees with itself by construction. Ask
  whether each test's oracle is independent of the code under test.
- **One writer per derived field** — and whether the *enforcement test* would
  actually fail if a second writer appeared.
- **Comment and citation defects.** Spell out all four sub-classes:
  - every *only / sole / never / always / the one place* claim — is the CLAIM
    true, **and** does the CITED COMMAND return what the comment says?
  - **a citation true but not verifiable as written is a defect** — one that
    matches its own quoted text and returns 5 lines for a claimed 3. Fixes are
    bracket-escaping (`Is[C]orrectness(`) and pathspecs.
  - **a comment can be right about the code and wrong about WHY** — when it
    says "because", test whether the because holds.
  - **commit message bodies are in scope** — the one artifact no later grep
    over source can reach.
- **Cross-file consistency** — find any two files that now describe one model
  differently.

Close with the calibration instruction, which measurably improves the ratio:

```
Prefer few substantiated findings over many speculative ones, and rank honestly
— a real defect rated Trivial and a false one rated Major both cost me time.
If a category yields nothing, say so explicitly rather than omitting it.
```

---

## Dispatching the subagent

Give the child the two paths and the command; do not paste the prompt text
into the dispatch — it is already on disk.

> Run this command exactly as written and wait for it. It takes 10–25 minutes;
> do not poll it, do not shorten the timeout, do not run it in the background.
>
> ```
> <the agy command above>
> ```
>
> You are **read-only on the repository**: run no git command that writes, and
> never `git stash`.
>
> When it exits: read `<out.md>`, then run `git status --short` and
> `git stash list` in the repo and paste their literal output.
>
> Return, and nothing else: (1) the Phase 2 triage table; (2) for each ACCEPT,
> the file:line, the one-sentence defect, and the verification command it
> claims to have run; (3) the pasted git output; (4) the path to `<out.md>`.
> Do not summarize the PUSHBACKs beyond one line each. Do not include the raw
> transcript.

Two things that matter here. **Model:** a mid tier is right — the child is
running a command and reformatting a file, not reviewing. **The pasted git
output:** subagents have claimed a clean tree while leaving files behind;
require the literal output, not the assurance.

---

## Receiving the findings

Handle these under `superpowers:receiving-code-review` — skeptical triage, no
performative agreement. Three things specific to a cross-model reviewer:

**Verify the claim, not the reasoning offered for it.** The single most
important lesson from the source session: `agy` reported two vacuous subtests
and gave a *wrong* reason (it blamed guard ordering). The finding was rejected
on that reasoning — and a mutation proved the conclusion right anyway, by a
different mechanism. **A wrong explanation does not make a finding false.**
Reproduce the failure it describes before deciding.

**Reproduce every ACCEPT before fixing it.** Run the citation. Apply the
mutation. Cross-model reviewers hallucinate line numbers and occasionally cite
the very file that mitigates the problem.

**A PUSHBACK is not free either.** `agy` correctly pushed back on a Critical
deadlock claim from its own red team — the structural risk was real, but no
caller existed yet. That is worth recording as a hazard for the change that
adds one, not discarding.

---

## Cost and tiering

| Scope | Model | `--print-timeout` |
|---|---|---|
| One task, one package | `gemini-3.7-flash-high` | 9–14m |
| Whole branch, many commits | `gemini-3.7-flash-high` | 20–25m |
| Flash came back thin on a diff you think is deep | `gemini-3.1-pro-high` | 14–25m |
| Design doc / prose review | `gemini-3.1-pro-high`, and drop `/adversarial-review` | 14m |

That last row: `/adversarial-review` is diff-and-code oriented — Phase 0
resolves a target *diff* and Phase 1 runs a twelve-angle *code* review with
language rules. Pointed at a markdown design doc it wastes most of its
structure. For prose, write a bare prompt instead of invoking the skill.

---

## Verification

Always, after the child returns:

```bash
git -C <repo> status --short   # must be empty (or exactly your own pre-existing changes)
git -C <repo> stash list       # must be unchanged
```

`scripts/agy-review.sh` in this skill runs the invocation and these checks in
one shot, and exits non-zero if the tree moved. Prefer it to a hand-typed
command — the check is the step that gets skipped.

A fill-in-the-blanks prompt with every block above already in place:
`reference/prompt-template.md`.
