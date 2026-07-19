---
name: finding-triage
description: Single source of truth for per-finding review-triage dispositions — actionable / false-positive / uncertain-validity / opens-a-question → research / invariant-premise-check / defer. Definition file, not a procedure.
---

# Finding Triage (SSOT)

This skill is **a definition file, not a runnable procedure**. Skills that triage review findings apply these dispositions by reference. Do not copy the class definitions into them; point at them by name.

A reviewer (CodeRabbit, a fresh-context code-review subagent) produces findings without the project context you hold — test results, design intent, scope constraints, conversation history. Triage is the step that converts a raw finding into a disposition. This file is the catalogue of dispositions; the catalogue does not vary by reviewer, so it lives in one place.

## Scope: stateless, per-finding

Every disposition here is judged on **one finding in isolation** — no dependence on what other findings said or on prior iterations. Loop-level criteria that depend on history across review iterations (oscillation detection, re-triage carryover policy) are **out of scope for this SSOT** — they belong to whatever orchestrates the review loop. A standalone review run applies these per-finding classes without the loop machinery — which is exactly why the classes cannot live in the loop orchestrator alone.

## The dispositions

Each finding receives exactly one disposition. A finding may be *re-triaged* to a different disposition after investigation (e.g. `uncertain-validity` → `actionable`), but at any moment it holds one.

- **actionable** — a real issue the reviewer correctly identified, whose resolution is a **local edit** (via `replace_file_content` or `multi_replace_file_content`). Fix in place.

- **false-positive** — plausible but wrong given context the reviewer lacked (test results, deliberate design choice, a system constraint that rules out the hypothesized input). Dismiss **with explicit reasoning** stated to the user. Never silently override a finding: false-positive classification is itself a triage step the user can challenge via `ask_question`. This should be rare enough to be worth paper-trailing. When the dismissal rests on the behavior of an external system (a markdown renderer, parser, compiler, ABI, API), verify it before dismissing per **Verifying external-system claims** below.

- **uncertain-validity** — you cannot yet tell whether the finding is real. The open question is **validity**. Investigate — read code (`view_file`), run a targeted probe (`run_command`) — until it resolves to `actionable` or `false-positive`. When the targeted probe judges an external-system-behavior claim, verify it per **Verifying external-system claims** below. Do not carry an unresolved `uncertain-validity` past the point where a fix would be committed.

- **opens-a-question → research** — the finding **is real**, but its resolution is **non-local**: it needs investigation, a design choice, or a scope judgment beyond a local edit. Both default responses are wrong here:

  - "fix in place" is wrong — the fix is not local.
  - "escalate to the user" is wrong — the resolution is probe-able.

  The correct disposition is to **re-enter `research`** with the finding as the task, then escalate only the genuinely user-owned residue (scope authority, taste, an external constraint).

- **invariant-premise-check** — the finding's *conclusion* may be correct, but its *premise* may be wrong. Applies to claims about mathematical properties, semantic validity, or precondition necessity. Before committing a fix, **verify the premise** — check whether the invariant the finding assumes actually holds, by reading code and tests and running targeted experiments. When the premise is an external-system-behavior claim, verify it per **Verifying external-system claims** below. Resolves to `actionable` (premise holds → fix it) or `false-positive` (premise fails → the finding's conclusion does not follow). The mechanism for verifying the premise is the caller's; this SSOT owns only the class.

- **defer** — the finding is valid and its fix is understood, but it is **out of scope** for the current task. Record it (follow-up issue, note) and do not fix now. Distinct from `opens-a-question`: here the resolution is known and local, only the *timing* is deferred; in `opens-a-question` the resolution itself is unknown.

## Pre-existing instances do not license dismissal

A finding is not downgraded to `false-positive` (or `defer`) merely because the surrounding code already exhibits the same flaw. Pre-existing instances of a problem are unextracted debt, not a convention that licenses adding another — "matches the surrounding code" describes the debt, it does not dismiss the finding. Dismissal still requires the disposition's own bar: for `false-positive`, context that makes *this* finding wrong; for `defer`, an explicit out-of-scope decision. The mere presence of prior offenders meets neither.

## opens-a-question vs uncertain-validity

The two name **different unknowns**:

- `uncertain-validity` — "**is the finding real?**" Validity unknown; resolution (if real) presumed local.
- `opens-a-question` — "the finding **is** real, but its **resolution is non-local**." Validity known; resolution unknown.

A finding can pass through both in sequence: resolve validity first (`uncertain-validity` → real), then, if the fix turns out non-local, re-triage to `opens-a-question`.

## The tell for opens-a-question

An `opens-a-question` finding often first reads as a **user gate** — "ask the user to decide X." The diagnostic: a *genuine* user gate stays a gate after investigation, whereas an `opens-a-question` **dissolves the moment someone investigates** — it was never user-owned. If the escalation would evaporate once a probe runs, route it through `research`, not straight to the user. Escalate only the residue that survives investigation: scope authority, taste, external constraint.

## Verifying external-system claims

Three dispositions can rest a committed verdict on a claim about an **external system's behavior** (a markdown renderer, parser, compiler, ABI, API, runtime): `false-positive` (the system rules out the input), `uncertain-validity` (a targeted probe judges the claim), and `invariant-premise-check` (the premise is an external-system fact) — including when the verdict is `actionable` and ships a fix.

**Requirement.** Before committing a verdict that rests on such a claim, run the finding's input through that system's **authoritative implementation** (`gh api /markdown` via `run_command` for GitHub rendering; the actual compiler / parser / runtime otherwise). A local proxy (a regex standing in for a renderer, a reimplemented parser) or a hand-derivation is built from your own mental model of how the system behaves — the same model that produced your reading — so it can only confirm that reading; only the authoritative implementation can test whether the reading holds.

**Scope.** This fires only for claims about an external system's *behavior*, and only at the point a verdict is committed (a fix shipped, a finding dismissed) — not for intermediate reasoning.

**When the authoritative implementation is unavailable or too costly to run.** Cost decides whether you can pay to confirm; it never makes a proxy into sufficient evidence. If you cannot run the authoritative implementation, the claim does not resolve via a proxy: the finding stays unresolved rather than advancing to a committed verdict, and whether the verification is worth its cost — or whether an alternative authoritative source exists — escalates to the user via `ask_question`.
