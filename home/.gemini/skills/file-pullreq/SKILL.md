---
name: file-pullreq
description: Draft and file a GitHub PR using gh-body-conventions and the PR body skeleton, via the gh-post wrapper. Supports a gate mode that stops at user approval.
---

# File Pull Request

Draft a GitHub PR title and body that follow the user's conventions, show the draft for approval, then file via `gh` (or, in gate mode, hand off to a caller).

## Conventions

Apply the rules in `gh-body-conventions` to both the title and body. The two PR-specific points to reinforce:

- **Semantic line breaks, not column wrapping.** This is the user's most-corrected formatting habit on PR bodies — commit-body-style hard wrapping renders as ragged text on GitHub's wide viewport.
- **Line numbers within this PR's own diff are permitted** (the PR is anchored to specific commits, so the references will not rot). Inline review comments are still preferred for line-specific feedback because they render next to the code.
- **Commit and PR conventions**: inherit and strictly follow the project's or agent's configured commit and PR description conventions (e.g. from `GEMINI.md`, `CLAUDE.md`, or user rules).

### Length

A typical PR body is 10–40 lines pre-merge, plus a plan-vs-actual delta if one is appended later. Trivial fixes can be much shorter; major features or multi-file refactors can be longer. Every section in the skeleton below should earn its place — a one-line fix needs neither an Impact nor a Notes section.

### Title

A single descriptive line under ~70 characters. Use a conventional commit prefix (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, etc.) when the surrounding repo's existing PR titles use one; otherwise no prefix.

## Procedure

### 1. Confirm scope

Before drafting, identify:

- **Target repo and base branch.** Run `gh repo view` and `git symbolic-ref --short refs/remotes/origin/HEAD` via `run_command` if unclear.
- **Linked issue.** Read the issue body and comments using `view_file` — especially the `research` plan (in the sub-issue body for umbrella-spawned leaves, or in a comment for single-scope issues), if the work passed through `/research-and-implement`. The plan is the source of truth for Changes / Impact / Test plan.
- **Whether the work went through `research`.** If yes, fold the plan's reader-facing content (Changes / Impact / Test plan) into the body skeleton. If no, derive the same content from the local diff and commits. Either way, do not transcribe the plan's process bookkeeping — see the reader-facing note below the skeleton.

### 2. Draft

Produce a title and body following the conventions above and the skeleton below.

#### Body skeleton

```
## Summary

<one-paragraph problem statement and resolution, semantic line breaks>
<Closes #N> on its own line; <Depends on #M> if applicable.

## Changes

<compressed plan checklist: file path + one-line description per unit>
<for repos that prefer prose: a few sentences covering the same ground>

## Impact

<callers / public APIs affected; reference plan's Impact list compressed>
<omit when the change is genuinely local (single private function, etc.)>

## Test plan

<invariants verified, tests added/modified, cross-API coverage>
<contract tests added during review, if any>
<verification results: go test / pytest / etc. — pass/fail summary>

## Notes  (optional)

<known caveats, risks, follow-ups — including any behavior the plan
 deferred, framed as the limitation itself (what the PR does not do, and
 why), NOT as a "plan said X / actual Y" delta or a plan-comment link>
```

The PR body is **reader-facing**: it documents the merged artifact for a future bisect reader / maintainer, not the research process that produced it. Do **not** add a `Plan reference`, `Discovery contract status`, or `Open questions from the research plan` section even when the work went through `research-and-implement` — those transcribe plan-internal bookkeeping (opaque plan-comment IDs, inconclusive-item enumerations) that rots fast and means nothing to a reader without the plan in front of them. A deferred behavior a reader genuinely needs goes in `Notes`, framed as the code's own limitation rather than a plan delta. (A `## Plan-vs-actual delta` appended later by the caller is the one sanctioned exception — it is the audit surface for umbrella-tracked work and lives at the bottom of the body.)

The `## Plan-vs-actual delta` section is appended later by the caller; do not pre-create an empty delta section here.

Section headings are optional for trivial PRs — a 5-line body covering Summary + Test plan often needs no headings.

### 3. Laundering pass — run `gh-body-check`

Run `gh-body-check` against the drafted body. The check runs a Unicode-math regex scan and a cold-reader subagent that judges whether every referent in the body resolves from the target repo's public state alone — the author has just drafted the text and is primed to read what they meant rather than what they wrote, which has repeatedly let private-context tokens slip past a self-administered cold re-read.

Pass artifact kind `pr`, the target repo, and the target language. The check returns a ✅ / ⚠ status. Mandatory before every `gh-post pr create` / `gh-post pr edit`. Any ⚠ blocks step 4; revise the draft and re-run until no unresolved ⚠ remains, or explicitly waive a finding with a one-line justification.

See `gh-body-check/SKILL.md` for the procedure.

### 4. Show for approval

Present the laundered draft to the user verbatim (or via `ask_question`) before filing. Do not file without confirmation.

If the user requests changes, revise and re-show. Do not file partially — the next step runs only after explicit approval.

### 5. File

Two modes, distinguished by the caller.

#### 5a. Standalone mode (default)

Used when invoked directly by the user, not in gate mode. Write the laundered body to a temp file (via `write_to_file`), then invoke the wrapper via `run_command`:

```bash
gh-post pr create \
  --repo <owner>/<repo> \
  --base <base-branch> \
  --title "<title>" \
  --body-file /tmp/<descriptive-name>.md
```

`gh-post` funnels every body through stream input and re-runs the hardwrap validator before forwarding to `gh`. Always create the PR through `gh-post` if available. If `gh-post` is missing, fall back to `gh pr create --repo <owner>/<repo> --base <base-branch> --title "<title>" --body-file /tmp/<descriptive-name>.md`. Add `--draft` if the user wants a draft PR; extra flags (`--label`, `--reviewer <login>`, etc.) are forwarded to `gh` verbatim.

#### 5b. Gate mode

Used when invoked as a gate by a caller that creates the PR itself. Stop after approval; do NOT run `gh pr create`. Output the approved title and body for the caller to pass into its PR-creation step.

Output format:

```
APPROVED TITLE:
<title>

APPROVED BODY (HEREDOC-ready):
<body>
```

The caller then writes the approved body to a temp file and runs its PR-creation step, e.g. (this is `review-pipeline-coderabbit`'s actual pattern):

```bash
cat > /tmp/<descriptive-name>.md <<'EOF'
<approved body>
EOF

~/.gemini/skills/coderabbit-review/scripts/pr-with-coderabbit-review.sh \
  --base <base-branch> \
  --title "<approved title>" \
  --body-file /tmp/<descriptive-name>.md
```

The script routes PR creation through `gh-post pr create`, which rejects inline `--body <string>` / `-b` to keep every body through the wrapper's validator stack — `--body-file` (preferred) or `--body-stdin` are the only accepted body inputs.

### 6. Report

After filing in standalone mode, show the user:

- The PR number and URL.
- Any follow-up actions (linking from a parent umbrella issue, etc.).

In gate mode, just confirm the approval and hand off to the caller.
