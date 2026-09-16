# Design Spec: Shared `deep-pr-review` Across Claude Code and agy

Turn `deep-pr-review` into the first **shared skill definition**: one harness-neutral method, loaded by
thin per-harness adapters in `home/.claude/skills/` and `home/.gemini/skills/`. At the same time, fold in
the parts of the `code-review:code-review` plugin that `deep-pr-review` lacks, and fix its known defects.

## Problem

1. **Forked skills drift.** About 15 skills exist as hand-maintained copies in both
   `home/.claude/skills/` and `home/.gemini/skills/`, and the copies have diverged
   (`quality-list` 54 differing lines, `research` 96, `coderabbit-review` 85). Most of each diff is
   harness vocabulary, not method: `invoke_subagent` vs `Agent`, `view_file` vs `Read`,
   `.gemini/skills/...` vs `skills/...`. Because tool names are embedded in method prose, every
   method improvement must be hand-ported, and in practice is not.
2. **`deep-pr-review` exists only for agy.** Claude Code has no equivalent recall-biased, multi-angle,
   CodeRabbit-format review. The closest, `code-review:code-review`, is precision-biased and posts a
   single terse comment.
3. **`deep-pr-review` lacks capabilities the plugin has:** it reviews closed/draft/already-reviewed
   PRs, and it has no history-aware angles (git blame, prior PR feedback, in-code comment contracts).
4. **`deep-pr-review` has known defects:**
   - `reference/go_rules.md` cites stale phase numbers ("Phase 2 Verifier", "Phase 4 AI Remediation")
     left over from when the Architecture Gate was inserted.
   - Findings go to a fixed `/tmp/deep-pr-review-findings.json`; concurrent reviews clobber each other.
   - `post-review.sh --sequential` is used by the format but undocumented in SKILL.md.
   - "Actionable comments posted: N" excludes findings moved to the body as not anchorable.
   - Gap-sweep candidates "run through Phase 3" with no described second verify round.

## Decisions (settled during brainstorming)

| Question | Decision |
|---|---|
| Scope | Establish a reusable pattern; migrate only `deep-pr-review` now |
| Harness-difference strategy | Neutral core + thin per-harness adapters (no build/render step, no inline harness branches) |
| Merge set | Eligibility + idempotency; history angles M/N/O; defect fixes |
| Architecture Gate | Remains **halting** (not made advisory) |
| Verifier fan-out on Claude | One verifier per candidate (no per-file batching), despite cost |

## Layout

```
skills-shared/                      # repo root; not under home/, so stow ignores it
  README.md                         # the pattern and its rules
  deep-pr-review/
    method.md                       # harness-neutral phases, angles, rules
    reference/format.md
    reference/go_rules.md
    scripts/post-review.sh

home/.gemini/skills/deep-pr-review/
  SKILL.md                          # frontmatter + harness mapping + "follow method.md"
  method.md  -> ../../../../skills-shared/deep-pr-review/method.md
  reference  -> ../../../../skills-shared/deep-pr-review/reference
  scripts    -> ../../../../skills-shared/deep-pr-review/scripts

home/.claude/skills/deep-pr-review/
  SKILL.md                          # frontmatter + Claude mapping
  method.md, reference, scripts     # same three relative symlinks
```

- `reference/` and `scripts/` are linked **individually**, not through one `core/` link, so the
  absolute paths existing callers use (`~/.gemini/skills/deep-pr-review/reference/go_rules.md`) remain
  valid.
- Relative symlinks resolve against the adapter directory's real location in the repo, so they work
  through both install paths: stow's per-skill link for `~/.gemini/skills/` and
  `install_claude_skills`' per-skill link for `~/.claude/skills/`. No install-script change is expected;
  this is verified, not assumed (see Verification).

### Neutral verbs

`method.md` names no tools. Harness-specific actions are written as a closed set of verbs in a greppable
form:

| Verb | Meaning |
|---|---|
| `⟨dispatch-parallel⟩` | Launch N self-contained subagents concurrently and join their results |
| `⟨read-at-sha⟩` | Read a file's content at a given commit |
| `⟨run⟩` | Execute a shell command |
| `⟨ask-user⟩` | Ask the user a question and wait |
| `⟨skill-dir⟩` | The adapter's installed skill directory |
| `⟨run-dir⟩` | This run's private temp directory |
| `⟨user-instructions⟩` | The user's global instruction file(s) to read during Gather |

Each adapter's SKILL.md contains one **Harness mapping** table that binds every verb, plus model routing
per role. Adding a verb to `method.md` without binding it in every adapter fails the test suite.

### `skills-shared/README.md` rules

- No file in the neutral core (method, references, scripts) contains tool names or harness home paths
  (`~/.claude`, `~/.gemini`); companion skills are cited by name.
- Adapters contain frontmatter, the mapping table, model routing, and harness-only notes, nothing about
  method.
- Callers reference phases by **name**, never by number.

## Merged method

### Phases

| # | Name | Content |
|---|---|---|
| 0 | **Eligibility** | PR target only; skipped in local mode. Stop if closed or merged. Stop if draft, unless the user named the PR explicitly. Stop if trivial: bot author (renovate, dependabot) or every changed file is a lockfile (`go.sum`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `Cargo.lock`, `uv.lock`, `poetry.lock`). Search the PR's reviews and issue comments for `<!-- deep-pr-review head:<sha> -->`: same SHA as current head → stop with "already reviewed at <sha>"; older SHA → proceed with a full review, and the walkthrough links the prior review. |
| 1 | **Gather** | Former Phase 0, unchanged, plus record `expected_head`. |
| 2 | **Architecture Gate** | Former Phase 1, unchanged; FLAWED_APPROACH still halts. |
| 3 | **Find** | 15 angles (A–L unchanged, plus M, N, O below), ≤8 candidates each, one `⟨dispatch-parallel⟩`. |
| 4 | **Verify** | Former Phase 3. Dedup, then one verifier per candidate. Also run a second, smaller `⟨dispatch-parallel⟩` round over Gap Sweep candidates. |
| 5 | **Gap Sweep** | Former Phase 4, unchanged; its candidates feed Verify's second round. |
| 6 | **Render** | Former Phase 5. Method line says 15-angle; review body carries the head marker comment. Findings JSON and walkthrough are written under `⟨run-dir⟩`. |
| 7 | **Post** | Former Phase 6. Re-run the Eligibility checks immediately before posting. Call `post-review.sh --expect-head <expected_head>`. Document `--sequential`. |

**Local mode** (branch or working-tree target, or invocation by `adversarial-review` /
`adversarial-review-loop`) skips Eligibility and Post and prints the rendered output.

### New angles

- **Angle M — history and blame.** Run `git log -L` / blame over changed ranges; flag a change that
  reverts or weakens a deliberate earlier fix, citing the commit and its message. Correctness tier.
- **Angle N — prior PR feedback.** For files the diff touches, map recent commits to their merged PRs
  (`gh api repos/{o}/{r}/commits/{sha}/pulls`), read those PRs' review comments, and flag feedback that
  applies again to the new code, quoting the original comment and linking it. Returns nothing when there
  is no GitHub remote. Category inherited from the quoted feedback.
- **Angle O — code-comment compliance.** Read comments in and adjacent to changed functions that state
  contracts ("caller holds mu", "must be idempotent", doc-comment preconditions); flag changes that
  violate them, quoting the comment. Correctness tier.

Correctness tier for output-cap ranking becomes A–E, K, L, M, O. N ranks by its inherited category.

**Verifier rule for N:** CONFIRMED only when the pattern the quoted prior comment objected to is present
at the new line; otherwise REFUTED.

### Defect fixes

- `go_rules.md` section headings and intro reference phases by name (Find, Verify, Render).
- `go_rules.md` §7 names companion skills by skill name only (`golang-safety`), not by
  `~/.gemini/skills/...` path; `install_skills.sh` links them into both harnesses.
- Findings and walkthrough paths use `⟨run-dir⟩`; each adapter defines it as a unique per-run
  directory (e.g. `mktemp -d` under `$TMPDIR` with a `deep-pr-review.` prefix).
- `post-review.sh`:
  - new `--expect-head <sha>`: refuse (non-zero exit, nothing posted) when the live PR head differs;
  - count line reads `**Actionable comments posted: N inline + M in body**`;
  - body includes `<!-- deep-pr-review head:<sha> -->`.
- `method.md` Post phase documents `--sequential`.

### Callers

`home/.gemini/skills/adversarial-review/SKILL.md` and `adversarial-review-loop/SKILL.md`:
"12-angle" → "15-angle"; "skip GitHub posting (Phase 5)" → "local mode (skips Eligibility and Post)".
Their `go_rules.md` paths are unchanged.

## Adapters

### Model routing

| Role | agy | Claude Code | Rationale (Claude) |
|---|---|---|---|
| Architecture Gate | `flash` | Opus | Single judgment that can halt the review; ambiguous design reasoning |
| Finders A–I, K–O | `flash` | Sonnet | Standard code reading and cross-file tracing |
| Finder J (conventions) | `flash_lite` | Haiku | Quote-the-rule / quote-the-line matching |
| Verifiers | `flash` | Sonnet | Must construct refutations from code |
| Gap Sweep | main context | main context | Needs the deduplicated list |

### Verb bindings

| Verb | agy | Claude Code |
|---|---|---|
| `⟨dispatch-parallel⟩` | one `run_subagent` call, all entries, `TypeName: "self"` | multiple `Agent` calls in a single message, `subagent_type: "general-purpose"`, explicit `model` |
| `⟨read-at-sha⟩` | `run_command` `git show <sha>:<path>` | `Bash` `git show <sha>:<path>` |
| `⟨run⟩` | `run_command` | `Bash` |
| `⟨ask-user⟩` | `ask_question` | `AskUserQuestion` |
| `⟨skill-dir⟩` | `~/.gemini/skills/deep-pr-review` | `~/.claude/skills/deep-pr-review` |
| `⟨run-dir⟩` | `mktemp -d "${TMPDIR:-/tmp}/deep-pr-review.XXXXXX"` | same command |
| `⟨user-instructions⟩` | `~/.gemini/GEMINI.md` and `~/.claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |

Claude uses `Agent` fan-out, not the `Workflow` tool, because `Workflow` requires explicit user opt-in
per session.

The existing fallback stays in the neutral core: if `⟨dispatch-parallel⟩` is unavailable, run each entry
sequentially in the main context and pass `--sequential` to `post-review.sh`.

### Claude trigger

The Claude adapter's description restricts invocation to explicit requests for `deep-pr-review` or a
"CodeRabbit-style deep review", so it does not preempt `/pr-review`, `/code-review`, or the
`review-pipeline-coderabbit` steps CLAUDE.md already assigns.

## Testing

Both suites live in `tests/`, matching `test_psgrep.sh` style. Each assertion is confirmed **red** before
it is trusted: revert the fix or break the symlink/verb, and observe the specific assertion fail.

### `tests/test_skills_shared.sh` (generic over `skills-shared/*/`)

- No text file under `skills-shared/<name>/` (method, references, scripts) contains forbidden harness
  tokens: `run_subagent`, `invoke_subagent`,
  `view_file`, `run_command`, `ask_question`, `AskUserQuestion`, `subagent_type`, `~/.gemini`,
  `~/.claude`.
- Every `⟨verb⟩` used in `method.md` is bound in every adapter's mapping table, and every bound verb is
  used (no dead rows).
- Every adapter that links a shared skill has `method.md`, `reference`, `scripts` symlinks resolving
  into `skills-shared/<name>/`.

### `tests/test_post_review.sh` (stub `gh` on `PATH`, fixture diff and findings)

- Anchorable findings go inline; unanchorable ones go to the body section.
- A multi-line anchor with out-of-diff `start_line` degrades to single-line.
- `--expect-head` with a mismatched stub head exits non-zero and posts nothing.
- Count line reads `N inline + M in body` with correct numbers.
- Body contains the head marker.

## Verification (manual, before claiming completion)

- `./install.sh -n` and a `stow -n` dry run show no conflicts; after install,
  `~/.claude/skills/deep-pr-review/method.md` and
  `~/.gemini/skills/deep-pr-review/reference/go_rules.md` are readable.
- Claude: run the skill in local mode on a small real diff; confirm parallel `Agent` dispatch with the
  routed models; render only.
- agy: same local-mode run; `post-review.sh --dry-run` against a real PR.
- Eligibility: dry run against a PR whose head already carries a marker halts with "already reviewed".

## Rollout

Single branch and PR. Existing files move to `skills-shared/deep-pr-review/` via `git mv` to keep
history; adapters and symlinks are added afterward.

## Out of scope (follow-ups)

- Migrating the other ~15 forked skills to `skills-shared/`.
- Incremental re-review (reviewing only commits since the prior marker).
- Adopting the plugin's false-positive exclusion list into the Verify refutation rules.
- Making the Architecture Gate advisory.
