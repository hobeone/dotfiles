# Prompt template

Copy, fill every `<…>`, delete every block that does not apply. **Delete
nothing else** — the three overrides and the calibration close are what keep
the run read-only and the finding list honest.

Blocks 4 and 5 are the ones that decide whether the review is worth reading.
Skipping them yields a long list of confident non-findings about work that was
deliberately deferred or already settled.

---

```
/adversarial-review

Target: the commit range `<BASE>..<HEAD>` on branch `<branch>` in <repo-path>,
scoped to `<path>/`. Explicit-range target, NOT the working tree.
<if the tree is dirty: The working tree has unrelated work in flight and MUST
NOT be reviewed or touched.>

THREE MANDATORY OVERRIDES:

1. **STOP AFTER PHASE 2.** Run Phase 0 (target resolution), Phase 1 (Red Team
   adversarial review) and Phase 2 (skeptical triage into ACCEPT / PUSHBACK).
   Do NOT run Phase 3 remediation and do NOT run Phase 4. I am doing
   remediation myself under a separate controlled loop.

2. **Strictly READ-ONLY.** Do not modify, create, or delete any file under
   <repo-path>; do not commit or stage. **Never `git stash`** — the stash stack
   is shared with other live sessions here and a pop can take their work. /tmp
   scratch is fine. I check `git status --short` and `git stash list`
   afterwards; a dirty tree voids this review regardless of what you found.

3. **Phase 2 triage table plus full detail to STDOUT.** Do not post to GitHub —
   <there is no PR for this branch / I will handle posting>. Per finding:
   severity, file:line, the defect in one sentence, a concrete failure
   scenario, the exact command you ran to verify it, and your ACCEPT/PUSHBACK
   verdict with reasoning.

WHAT THIS CHANGE IS.
<Two or three paragraphs. Name the types, the axes, the invariant the change
exists to establish. A reviewer that has to infer the design from the diff
spends its budget on inference and then reports the design as the finding.>

<If there is one: THE CENTRAL SAFETY PROPERTY: <state it>. This invariant has
escaped before in this package, <how>.>

CONTEXT SO YOU DO NOT REPORT NON-FINDINGS:
- <What is deliberately absent, by symbol name: the other half of a split
  change, functions arriving in a later task. Say "correctly absent — do not
  report as a gap".>
- <Comments that explicitly mark themselves not-yet-true are CORRECT and
  deliberate, not stale.>
- <Anything not yet wired up: "nothing outside <pkg> imports this yet, by
  design".>
- The repo's governing rules are in <repo>/AGENTS.md. READ IT IN FULL and paste
  the <rules section> into every subagent prompt — the conventions angle is
  worthless without them. <Then summarize the rules in two lines, because a
  subagent it spawns may not read the file.>

<N THINGS ALREADY PROPOSED AND REJECTED ON THE MERITS. Do not re-raise them; if
you believe one is wrong, you must defeat the stated reasoning, not restate the
original claim:
1. <claim> — <why it was rejected>
2. …>

WHERE TO ATTACK, IN PRIORITY ORDER:

1. **<The central invariant>, end to end across the whole range** — the final
   state, not one commit. Can any sequence of exported calls violate it?
   Include <the specific call shapes worth trying>.

2. **Test vacuity.** For each test this range adds, name the mutation that
   would kill it, and flag any whose assertion could be satisfied by a
   different code path than the one it names. <If vacuity has bitten here
   before, say exactly how — it calibrates the search.>

3. **Shared oracles.** A test that judges with the same predicate, latch, or
   bookkeeping the code decides by agrees with itself by construction. For each
   test, is its oracle independent of the code under test?

4. **One writer per derived field.** For every field added, enumerate its
   writers with a grep and state whether the code matches what its comment
   claims — and whether the enforcement test would actually fail if a second
   writer appeared.

5. **Comment and citation defects — no gate catches any of these.** `go vet`
   does not read comments, tests do not execute them, and the duplicate-comment
   checker only finds copies. Check every comment the range adds or changes:
   - Every *only / sole / never / always / the one place* claim: run the
     enumeration; report whether the CLAIM is true AND whether the CITED
     COMMAND returns what the comment says it returns.
   - **A citation TRUE but not VERIFIABLE AS WRITTEN is a defect.** Several
     here matched their own quoted text (5 lines for a claimed 3, 11 for 1).
     The fixes are bracket-escaping (`Is[C]orrectness(`) and pathspecs
     (`-- '<pkg>/*.go' ':!<pkg>/*_test.go'`). Check every citation still holds
     AT THE FINAL COMMIT — several were falsified by later commits than the one
     that wrote them.
   - **A comment can be right about the code and wrong about WHY.** When a
     comment says "because", test whether the because holds at that line.
   - **Commit MESSAGE bodies are in scope** — the one artifact no later grep
     over source can reach.
   - **Line-number citations** (`file.go:NN`): later commits move code. Check
     each still points at what it claims.

6. **Cross-file consistency.** <List the files that describe one model.> Find
   any two that now describe it differently — especially anything still
   describing <the superseded model>.

7. **Anything genuinely dangerous** the above misses: data races, lost wakeups,
   deadlock <name the non-reentrant lock and the function that holds it across
   a callback>, unbounded growth.

Prefer few substantiated findings over many speculative ones, and rank honestly
— a real defect rated Trivial and a false one rated Major both cost me time. If
a category yields nothing, say so explicitly rather than omitting it.
```
