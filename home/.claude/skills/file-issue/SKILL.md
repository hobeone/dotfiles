---
name: file-issue
description: Draft and file a GitHub issue using gh-body-conventions and the issue body skeleton, via the gh-post wrapper.
---

# File Issue

Draft a GitHub issue body that follows the user's conventions, show the draft for approval, then file via `gh`.

## Conventions

Apply the rules in `gh-body-conventions` to the title and body. The two issue-specific points to reinforce:

- **Semantic line breaks, not column wrapping.** Most-violated rule on issue bodies — do not hard-wrap at 72/80 the way commit bodies do.
- **Line numbers are forbidden in the issue body.** Issue bodies refer to the default branch's `HEAD` implicitly, which moves; cited line numbers go stale. Inline a code snippet instead. (PR bodies, governed by `file-pullreq`, are different — they are anchored to specific commits, so line refs there do not rot.)
- **Omit empty sections.** If a heading's content would be empty (no bullets, no prose), drop the heading entirely. No `TBD` placeholders, no empty bullet lists, no synthesized filler. Making an absence visible is more useful than papering over it; the section can be added later when there is real content.

### Length

A typical issue body is 5–25 lines. Longer is fine when warranted (e.g., a design proposal with alternatives), but every paragraph should earn its place. Aim for: problem statement, minimal reproduction or evidence, proposed direction (if any).

## Variants

### Umbrella sub-issue

When the new issue is a phase / sub-issue of an existing umbrella tracking issue, the body shape and title convention differ from a standalone issue.

- **First body line.** `Parent: #<umbrella#>`. Always included so tooling can detect the umbrella linkage.
- **Title.** `Phase N: <topic>` when the umbrella uses phase naming; otherwise mirror the umbrella's sub-task naming convention.
- **Body shape.** Goal / Scope / Out of scope / Acceptance (in place of the default problem-statement shape). When the leaf research has produced a full `research` plan, that plan IS the body — the sub-issue body is the canonical contract surface, not a thin pointer to a comment elsewhere.
- **"Out of scope" extraction.** When inheriting from an umbrella with a Phases table: list only **unspawned sibling phases later than the chosen one**, formatted as `<topic> (Phase <id>)`. The point is to pin scope-creep boundaries against work the umbrella has already promised to a future sub-issue. Do not copy umbrella-wide deferrals shared across all phases (e.g. "1-site DMRG", "opsum DSL") — they live on the parent and duplicating them adds noise. Already-completed earlier phases are also not listed (the boundary is forward-looking).
- **Frozen-contract discipline.** The sub-issue body is written at file time and not edited during implementation. Drift discovered during implementation goes to the PR's `Plan-vs-actual delta` (and, when a reader genuinely needs it, a `Notes` caveat in the PR body framed as the code's own limitation), never back to the issue body. Editing the body rewrites history that PR titles, commit messages, and `Closes #N` references already point to.

After filing, append the new sub-issue's number to the umbrella's Phases table row. This is the only umbrella-body edit performed at sub-issue spawn time; deeper umbrella drift (decisions captured, out-of-scope changes) is handled later at sub-issue close, not at spawn.

## Procedure

### 1. Confirm scope

Before drafting, identify:

- Target repo (`gh repo view` if unclear).
- Whether this is a bug, feature, design discussion, or umbrella sub-issue. The default body shape covers the first three; umbrella sub-issues use the shape defined in `Variants > Umbrella sub-issue` above.
- Any related issues/PRs to link.
- **Premise type (rot exposure).** Is the premise an **absence** (a capability / perf / test not built yet) or **coupled to current code state** (a specific construct is wrong / missing a test / a stopgap with a known expiry)?
  - Absence → no tag; it stays valid until built, so it is exempt from rot-sweeps.
  - Code-coupled → apply the `perishable` label so a rot-sweep filters to this set instead of re-reading the whole backlog. If a known issue/refactor would obviate or reshape it, additionally link that trigger in the body (or fold it in there as a checklist item) so the re-check is event-driven (when the trigger lands) rather than waiting for a periodic sweep.

### 2. Draft

Produce a title and body following the conventions above.

**Title** — a single descriptive line under ~70 characters. No leading type prefix unless the repo's existing issues use one.

**Body** — typical structure (adapt as needed):

```
<one-paragraph problem statement using semantic line breaks>

## Context  (optional — only if the reader needs background not visible from the repo)

<minimal context>

## Reproduction / Evidence  (for bugs)

<commands, inputs, observed vs expected, with code blocks where appropriate>

## Proposal  (optional)

<direction, not full implementation>
```

Section headings are optional for short issues — a 5-line body often needs no headings at all.

### 3. Laundering pass — run `gh-body-check`

Run `gh-body-check` against the drafted body. The check runs a Unicode-math regex scan and a cold-reader subagent that judges whether every referent in the body resolves from the target repo's public state alone — the author has just drafted the text and is primed to read what they meant rather than what they wrote, which has repeatedly let private-context tokens slip past a self-administered cold re-read.

Pass artifact kind `issue`, the target repo, and the target language. The check returns a ✅ / ⚠ status. Mandatory before every `gh-post issue create` / `gh-post issue comment`. Any ⚠ blocks step 4; revise the draft and re-run until no unresolved ⚠ remains, or explicitly waive a finding with a one-line justification.

See `gh-body-check/SKILL.md` for the procedure.

### 4. Show for approval

Present the laundered draft to the user verbatim before filing. Do not file without confirmation.

If the user requests changes, revise and re-show. Do not file partially — the next step runs only after explicit approval.

### 5. File

Write the laundered body to a temp file, then invoke the wrapper:

```bash
gh-post issue create \
  --repo <owner>/<repo> \
  --title "<title>" \
  --body-file /tmp/<descriptive-name>.md
```

`gh-post` is a single-entry wrapper that funnels every body through stream input (`--body-file` or `--body-stdin`) and re-runs the hardwrap validator before forwarding to `gh`. Always file the issue through `gh-post`, never `gh issue create --body ...` directly — an inline body (e.g. `--body "$(cat /tmp/x.md)"`) bypasses the validator.

If labels or assignees are appropriate and the user mentioned them, add `--label` / `--assignee` flags — these are forwarded to `gh` verbatim. Do not invent labels; only use ones the user named or that are obviously required by the repo's template.

### 6. Report

After filing, show the user:

- The issue number and URL.
- Any follow-up actions (e.g., linking from a parent umbrella issue, mentioning in a PR).
