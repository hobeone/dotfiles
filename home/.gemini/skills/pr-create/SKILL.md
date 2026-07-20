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

### 0. Determine Working Directory ($WORKDIR)

**Do this before anything else.** If this session's work happened in a git worktree, the session's default cwd may still be the main checkout — but the actual changes live in the worktree.

```bash
git worktree list
```

- If exactly one worktree (the main checkout): use it, proceed normally.
- If multiple worktrees exist: identify the one matching the branch this task is on (check recent conversation context for a branch name, or match against `git status --short` / `git diff --stat` showing actual changes in each candidate).
- **Pin the resolved path** (`$WORKDIR`) and use it explicitly (`git -C "$WORKDIR" ...`) for every command in this skill.

### 1. Check for Changes

```bash
git -C "$WORKDIR" status --short
```

If working tree is clean, inform user: "No changes to commit. Make changes first or run `/pr-review local` to review existing code."

### 2. Check for Main Drift

```bash
git -C "$WORKDIR" fetch origin main
git -C "$WORKDIR" log HEAD..origin/main --oneline
```

If main has advanced:
- Inform user: "Main has advanced by N commits since your branch diverged."
- Ask user whether to rebase onto main using `ask_question`.
- If rebase: `git -C "$WORKDIR" rebase origin/main`, resolve conflicts if needed.

### 3. Verify Before Pushing

Run verification commands (linter, formatter, tests) to confirm quality gates pass before committing. Evidence before assertions.

### 4. Create PR

1. Stage changes: `git -C "$WORKDIR" add <specific paths>` (or `add -A` if appropriate)
2. Form a commit message inheriting and strictly following the project's or agent's configured commit conventions (e.g. from `GEMINI.md`, `CLAUDE.md`, or user rules).
3. Commit: `git -C "$WORKDIR" commit -m "<message>"`
4. Push: `git -C "$WORKDIR" push -u origin <branch>`
5. Create PR using `gh pr create`:
   - Check if `.github/pull_request_template.md` (or similar template) exists.
   - Populate description, checklist, and related issues.
   - Run `gh pr create` with cwd set to `$WORKDIR` (e.g. `(cd "$WORKDIR" && gh pr create ...)`).

Report errors and suggest manual steps if creation fails.

### 5. Monitor CI (unless --no-watch)

Unless `--no-watch` was passed, trigger `/watch-ci` to monitor CI status in background.
