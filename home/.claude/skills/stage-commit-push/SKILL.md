---
name: stage-commit-push
description: Stage changed files, generate a conventional commit message, commit, and push in one step. Used inside automated review-fix loops.
---

# Stage, Commit, Push

One-shot skill for the review-fix loop: stage modified files, generate a commit message, commit, and push.

**Always a new commit, never `--amend`.** In a multi-cycle review-fix loop (e.g. `review-pipeline-coderabbit` Phase 1), every invocation of this skill creates a NEW commit — including before the branch has ever been pushed, and including when the fix is small or closely related to the commit that introduced the reviewed code. Do not fold a fix into a prior commit via `git commit --amend` to keep history tidy; that's what `gh pr merge --squash` is for, at merge time. Before step 3, explicitly confirm you are running `git commit` (a new commit), not `git commit --amend` — check this every time, don't rely on remembering it from earlier in the session.

## Procedure

### 1. Stage

```bash
git add <specific files that were modified>
```

Stage only the files you changed. Do NOT use `git add -A` or `git add .` — be explicit about which files are staged. Never stage files that could contain secrets (.env, credentials).

### 2. Generate commit message

Inspect the staged diff and recent commits to produce a conventional commits message.

```bash
git diff --staged
git log --oneline -5
```

**Type selection** — based on what changed and why:

- Documentation only → `docs`
- Build/CI config → `ci` or `build`
- Code style/formatting → `style`
- Tests only → `test`
- Deps/cleanup → `chore`
- Restructuring without behavior change → `refactor`
- New functionality that didn't exist before → `feat`
- Existing functionality that was wrong/broken → `fix`

Size doesn't determine type. API signature changes that correct a mistake are `fix`, not `feat`.

**Title length** — keep the commit title (first line) to 72 characters or fewer. Use the body for details.

**Exclusions** — the message must NOT contain:

- Phase/step numbers ("Phase 1", "Step 2")
- Plan or task references ("As part of...", "Following the plan...")
- Internal implementation context

### 3. Commit

Confirm: this is a plain `git commit`, not `git commit --amend`. If there is any temptation to amend, stop and use a new commit instead — see the note above.

```bash
git commit -m "$(cat <<'EOF'
<title>
<body>
EOF
)"
```

Always use HEREDOC for the message to preserve formatting.

### 4. Push

```bash
git push
```

If the branch has no upstream, use `git push -u origin <branch>`.

### 5. Report

After pushing, show the user:

- The commit hash and message title
- The branch and remote status
