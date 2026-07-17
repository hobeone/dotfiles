---
argument-hint: [--no-watch]
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

### 0. Determine Working Directory

**Do this before anything else.** If this session's work happened in a git worktree (projects that mandate worktrees for multi-step work, e.g. via AGENTS.md, commonly do), the session's default cwd may still be the main checkout — but the actual changes live in the worktree. Any git context gathered from the wrong directory (status, diff, branch) will look clean/stale and silently mislead every step below.

```bash
git worktree list
```

- If exactly one worktree (the main checkout): use it, proceed normally.
- If multiple worktrees exist: identify the one matching the branch this task is on (check recent conversation context for a branch name, or match against `git status --short` / `git diff --stat` showing actual changes in each candidate). Prefer the worktree with uncommitted or unpushed changes over the main checkout.
- **Pin the resolved path** (call it `$WORKDIR`) and use it explicitly (`cd "$WORKDIR"` or `git -C "$WORKDIR"`) for every command in this skill — including the delegated commit-push-pr skill below. Do not assume the session's implicit cwd is correct; verify with `git -C "$WORKDIR" rev-parse --show-toplevel` before trusting it.

### 1. Check for Changes

```bash
git -C "$WORKDIR" status --short
```

**Handle edge cases:**
- **Nothing to commit**: If working tree is clean, inform user: "No changes to commit. Make changes first or run `/pr-review local` to review existing code."

### 2. Check for Main Drift

Long-running sessions may drift from main. Before pushing, check if main has advanced:

```bash
git -C "$WORKDIR" fetch origin main
git -C "$WORKDIR" log HEAD..origin/main --oneline
```

If main has new commits:
- Inform user: "Main has advanced by N commits since your branch diverged."
- Ask via AskUserQuestion: **Rebase onto main (Recommended)** / Continue without rebase
- If rebase: `git -C "$WORKDIR" rebase origin/main`, resolve conflicts if needed

### 3. Verify Before Pushing

Use `superpowers:verification-before-completion` to confirm quality gates pass (linter, formatter, tests) before committing. Evidence before assertions — don't assume they pass. Run these gates in `$WORKDIR`, not the session's default directory.

### 4. Create PR

If `$WORKDIR` is the session's default directory (no worktree involved), invoke the commit-push-pr skill as normal:

```
Skill(commit-commands:commit-push-pr)
```

**If `$WORKDIR` is a different directory** (worktree case): the commit-push-pr skill gathers its own git context from the session's default cwd and will pick up the wrong (main-checkout) state, not `$WORKDIR`. Do not invoke it — instead perform the equivalent steps directly, explicitly scoped to `$WORKDIR`:
1. `git -C "$WORKDIR" add <specific paths>` (never `-A`/`.` blindly — review `git -C "$WORKDIR" status --short` first)
2. `git -C "$WORKDIR" commit -m "..."` following this repo's commit message convention
3. `git -C "$WORKDIR" push -u origin <branch>`
4. `gh pr create` run with cwd set to `$WORKDIR` (e.g. `cd "$WORKDIR" && gh pr create ...`), since `gh` resolves the repo from the current directory

**Handle failures:**
- Report the error and suggest manual steps

### 5. Monitor CI (unless --no-watch)

Unless `--no-watch` was passed, invoke `/watch-ci` to monitor CI status in background. It will automatically run `/pr-review remote` when CI completes.
