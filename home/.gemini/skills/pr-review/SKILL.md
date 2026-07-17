---
name: pr-review
description: Review code via local analysis or remote reviewer comments
---

# PR Review

Analyze feedback from local analysis or remote GitHub reviewers.

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

Output 2-3 sentence summary of changes.

### 2. Run Analysis

Run `Skill(auditing-pull-requests)` or perform custom linting, testing, and static analysis on the modified files.

### 3. Check Coverage Gaps

Analyze diff for untested code paths:
- Verify new/modified functions have corresponding tests.
- Identify missing documentation or usage examples for new features/exports.

### 4. Security Spot-Check

Scan changed files specifically for hardcoded secrets, input validation flaws, and injection vectors.

---

## Mode: `remote`

### 1. Fetch Comments

```bash
PR_NUM=$(gh pr view --json number -q .number)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

Use `gh` command or API queries to fetch comments and reviews:
```bash
gh api repos/${REPO}/pulls/${PR_NUM}/comments
gh api repos/${REPO}/pulls/${PR_NUM}/reviews
gh api repos/${REPO}/issues/${PR_NUM}/comments
```

### 2. Filter Resolved Items

Check for previous "Feedback Addressed" comments. Filter resolved ones.

### 3. Present via ask_question

Present findings and ask user for decision per item:
- Implement (Recommended) - if you agree, then run `Skill(receiving-code-review)` before applying changes
- Skip - not worth fixing
- Defer - create GitHub issue with high/medium/low priority label
- Elaborate - explain topic in detail

### 4. Post Resolution Comment to PR

Post a comment summarizing decisions:
```markdown
## Feedback Addressed
...
```
```
