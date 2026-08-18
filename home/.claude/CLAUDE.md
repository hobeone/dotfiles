# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) for all sessions.

## Decision-Making

- Use git and gh freely. Never merge or close PRs without explicit user approval.
- All repos have branch protection—create PRs, never push to main directly.
- Prefer MCP tools for structured data; use gh CLI for `--watch` flags, runs, and arbitrary API calls.

### Proactive Improvements

Don't wait to be asked. When you notice these patterns, surface them unprompted:
- Gap in tooling coverage (e.g., missing agent for a common audit pattern)
- Repeated manual work that could be automated
- Cross-repo patterns that could be shared
- Documentation drifted from reality
- Workflow friction you experienced during the session

Propose concrete solutions, not just observations.

### Autonomous Decisions

Default: act without asking for file operations, git, tests, linters, PRs, issues, web searches.

Non-obvious autonomy:
- Re-run flaky CI once (`gh run rerun <id> --failed`); investigate if it fails twice
- After completing work: summarize and run `pr-review-toolkit:review-pr` on the local diff before pushing
- When making issues: check for relevant labels, suggest new ones

### Model & Agent Selection

Default to the lowest-cost model/agent you judge capable of doing the task
reliably — don't reach for a premium model out of habit. Rough tiers, cheapest
first: Haiku (mechanical, well-specified, or narrow work) < Sonnet (standard
implementation and refactoring) < Opus (genuinely hard reasoning, architecture,
ambiguous problems, security-sensitive logic, and final verification). When
delegating via the Agent tool, set `model` explicitly to the cheapest fitting
tier.

Be verbose about the choice: before dispatching or acting, state which model
you're selecting and one line on why (task difficulty, blast radius, need for
independent verification). If you escalate to a pricier model, say what made the
cheaper tier insufficient. If you complete work on a premium model that a
cheaper one could have handled, note that too.

### Requires Discussion

- Design trade-offs with multiple valid approaches
- Disagreements with reviewer feedback on Critical/Important items

## Quality Gates

- Run quality gates (linter, formatter, tests) before pushing.
- New code needs tests. User-facing features need examples. Flag gaps.

## Execution Standards

**Verify, don't assume.** After every state-changing command (file write, migration, rename, install), perform a secondary read-only check to confirm the outcome. Exit codes lie; observed state doesn't.

**Read fully before acting.** When working in a component or feature area, read all relevant files top-to-bottom. Grep and partial reads miss context and cause incorrect changes.

**Halt on repeated failure.** If an implementation fails, do not guess fixes recursively. Stop, diagnose the root cause, and present a structured resolution to the user.

**Don't poll for background work.** Background Agent/Task calls notify automatically on completion — never call `ScheduleWakeup` to wait on them; just end the turn. `ScheduleWakeup` is scoped to `/loop`'s dynamic-mode self-pacing only.

**In a worktree, edit with Edit/Write, not Bash.** Auto mode's session-injected guidance says to prefer Bash (`sed`, heredocs, short scripts) over the dedicated file tools. That does not hold inside an `EnterWorktree` session: the isolation guard refuses any Bash command it cannot statically prove stays inside the worktree, which rejects `python3 - <<'PY'` heredocs, `cmd && cmd` chains and redirects — precisely the shapes that guidance asks for. Whether it fires is not predictable from command length, so "it worked last time" tells you nothing. **This rule overrides the Bash preference for file mutation whenever the working directory is under `.claude/worktrees/`.** Read-only inspection over Bash is unaffected — the guard only objects to what it must prove about writes.

## Commit Messages (Conventional Commits 1.0.0)

Every commit message MUST follow this structure:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Type** — pick exactly one:

| Type | When to use |
|---|---|
| `feat` | Adds a new user-visible feature (bumps MINOR in semver) |
| `fix` | Corrects a bug (bumps PATCH) |
| `refactor` | Code restructuring with no behaviour change |
| `perf` | Performance improvement with no behaviour change |
| `test` | Adds or fixes tests only |
| `docs` | Documentation only |
| `build` | Build system, dependency updates |
| `ci` | CI/CD pipeline changes |
| `chore` | Housekeeping that fits none of the above |

**Scope** (optional) — a noun in parentheses naming the subsystem, e.g. `fix(auth)`, `refactor(queue)`. Use the package or module name. Omit when the change is cross-cutting.

**Description** — imperative mood, lowercase, no trailing period, ≤ 72 characters. Says *what* the commit does, not *how*.

**Body** (optional) — one blank line after description. Explains *why*. Does not restate the diff. Wrap at 72 characters.

**Footers** (optional) — `Token: value` per line after a blank line. Token uses hyphens not spaces. Always include `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` on AI-assisted commits.

**Breaking changes** — use `!` before the colon and/or a `BREAKING CHANGE:` footer (token MUST be uppercase):
```
feat(api)!: remove legacy v1 endpoints

BREAKING CHANGE: All callers must migrate to /api/v2.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

**Never** use ad-hoc prefixes like `Step X.Y:`, `Fix:`, or `Refactor:`. The description MUST be lowercase (except proper nouns and acronyms).

## Reflection

After significant work: share what caused friction, where you were redirected (indicates missing guidance), and what's missing. Publish insights to event bus (`gotcha_discovered`, `pattern_found`, `improvement_suggested`). When an Insight (★) is a reusable gotcha or cross-session pattern — not just a local code explanation — publish it too.

## PR Workflow

Use `/work <issue-number>` for guided development. `/work --attach` to join an existing PR.

- **Before pushing**: `pr-review-toolkit:review-pr` on the local diff, update docs if needed
- **After push**: `/pr-create` (or just push) → `/watch-ci` → CI completes → `code-review:code-review` on the open PR
- **On feedback**: Present via AskUserQuestion. Form your own opinion—you have context reviewers lack
- **After fixes**: Push → auto-cycle repeats until clean
