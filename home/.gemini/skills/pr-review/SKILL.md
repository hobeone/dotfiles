---
name: pr-review
description: Review code via local analysis or remote reviewer comments
---

# PR Review

Analyze feedback from local analysis or remote GitHub reviewers.

## Key Principle

You have context on the work's purpose that automated reviewers lack. Include your opinion in each question, but let the user make the final call via `ask_question`.

## Usage

```
/pr-review local   # Self-review before pushing
/pr-review remote  # Process reviewer comments after CI
```

---

## Mode: `local`

### 1. Summarize Changes

```bash
git diff --stat HEAD~1 2>/dev/null || git diff --stat main...HEAD
```

Output 2-3 sentence summary of what changed and why.

### 2. Run Analysis

Perform custom linting, testing, and static analysis on modified files.

### 3. Check Coverage Gaps

Analyze the diff for untested code paths. For each new/modified source file:
1. **Extract functions** — Identify new/modified functions
2. **Find tests** — Check if corresponding test file exists and contains tests for those functions
3. **Detect user-facing** — Look for CLI flags, commands, public exports
4. **Verify examples** — Check for usage examples in README, examples/, or docs

**Severity:**
- **Critical** — Security-sensitive code without tests
- **Important** — New public function without tests; new user-facing feature without example
- **Suggestion** — Modified function with incomplete coverage; private helpers without tests

### 4. Security Spot-Check

Scan changed files specifically for hardcoded secrets, missing input validation, unsafe deserialization, injection vectors, and overly permissive permissions/CORS.

Flag files matching: `*auth*`, `*crypt*`, `*token*`, `*secret*`, `*password*`, `*credential*`, `*handler*`, `*endpoint*`, `*route*`, `*api*`, `*.env*`, `Cargo.toml`, `package.json`, `go.mod`.

### 5. Output Findings

If clean: "No issues found. Ready to create PR? Run `/pr-create`".
Otherwise proceed to Shared: Categorize and Present.

---

## Mode: `remote`

### 1. Get PR Info & Fetch Comments

```bash
PR_NUM=$(gh pr view --json number -q .number)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

Fetch inline code comments, review summaries, and PR issue comments:
```bash
gh api repos/${REPO}/pulls/${PR_NUM}/comments
gh api repos/${REPO}/pulls/${PR_NUM}/reviews
gh api repos/${REPO}/issues/${PR_NUM}/comments
```

If no feedback found: "No reviewer feedback found. PR is ready for merge or awaiting review." Exit early.

### 2. Filter Resolved Items

Check for previous "Feedback Addressed" comments (`### Implemented`, `### Skipped`, `### Deferred`). Only present NEW feedback.

---

## Shared: Categorize and Present

### 1. Form Opinions

For each item:
- Classify: Critical / Important / Suggestion
- Form opinion: Agree / Disagree / Uncertain
- Note reasoning

### 2. Present via `ask_question`

Present findings ordered by severity (Critical > Important > Suggestion).
Batch questions using `ask_question` (max 4 per call):

**Options per finding:**
- Implement (Recommended) — if you agree
- Skip — not worth fixing
- Defer — create issue for later
- Elaborate — explain topic in detail, then re-ask

### 3. Act on Decisions

- **Implement**: Fix code in place, re-verify.
- **Skip**: Note and move on.
- **Defer**: Create GitHub issue (`gh issue create`) with appropriate priority label (`priority:high`, `priority:medium`, `priority:low`).

### 4. Post Resolution Comment to PR

```markdown
## Feedback Addressed

### Implemented
- [Critical] item - how fixed

### Skipped
- [Suggestion] item - reason

### Deferred
- [Suggestion] item - tracked in #N
```

If fixes were made, run verification gates, commit, push, and run `/watch-ci`.
