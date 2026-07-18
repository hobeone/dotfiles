---
name: pr-create
description: Commit changes and create/update a PR
---

# PR Create

Commit outstanding changes and create or update a pull request.

## Usage

```
/pr-create [--no-watch]
```

- `--no-watch`: Skip automatic CI monitoring after PR creation

## Instructions

### 1. Check for Changes

```bash
git status --short
```

If working tree is clean, inform user: "No changes to commit. Make changes first or run `/pr-review local` to review existing code."

### 2. Check for Main Drift

```bash
git fetch origin main
git log HEAD..origin/main --oneline
```

If main has advanced:
- Inform user: "Main has advanced by N commits since your branch diverged."
- Ask user whether to rebase onto main using `ask_question`.
- If rebase: `git rebase origin/main`, resolve conflicts if needed.

### 3. Verify Before Pushing

Run `Skill(verification-before-completion)` to confirm quality gates pass (linter, formatter, tests).

### 4. Create PR

Instead of relying on commit-commands plugins:
1. Stage all changes: `git add -A`
2. Form a Conventional Commit message based on changes and ask the user to verify (using `ask_question` or text).
3. Commit: `git commit -m "<message>"`
4. Push: `git push -u origin <branch>`
5. Create PR:
   - Check if `.github/pull_request_template.md` (or similar template in `.github/` or root) exists.
   - If it exists:
     1. Read the template.
     2. Populate the **Description**, **Checklist** (marking run/passed verifications), and **Related Issues** sections based on the actual changes and verification results.
     3. Save the populated content to a temporary file.
     4. Create the PR using:
        ```bash
        gh pr create --title "<title>" --body-file <temp-file-path>
        ```
   - If the template does not exist, fall back to:
     ```bash
     gh pr create --fill
     ```

Report errors and suggest manual steps if creation fails.

### 5. Monitor CI (unless --no-watch)

Unless `--no-watch` was passed, trigger `/watch-ci` to monitor CI status.
