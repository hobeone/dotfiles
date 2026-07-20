---
name: research-and-implement
description: Work a GitHub issue end to end in two phases — research, then implement — under quaere-evidence and quaere-execution discipline.
---

# research-and-implement

End-to-end wrapper. Runs `research` (Phase 1) and `implement` (Phase 2) in sequence, with a branch baseline gate up front.

**Issue:** #$ARGUMENTS

## PHASE 0 — WORKTREE BASELINE

Before research begins, settle the workspace and branch:

1. Check current branch and worktree path: `git branch --show-current` and `git worktree list`.
2. Determine default branch: `git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'`
3. **Decision gate**:
   - On default branch in primary checkout → pick a conventional `<type>/<issue#>-<slug>` (`feat/195-dmrg-envs`, `fix/187-arpack-info`, `chore/<slug>`). Do NOT branch in place. Create an isolated git worktree: `mkdir -p .worktrees && git worktree add -b <branch> .worktrees/<branch> origin/<default-branch>`, then `cd .worktrees/<branch>` for all subsequent phases. Do not poll the user for the name — announce the chosen branch and worktree path in one line so the user can intervene if they object, then continue without waiting.
   - Already in a worktree or on a non-default branch → treat it as the intended workspace and proceed. Only stop if the branch name plainly contradicts the issue (e.g., on `feat/100-foo` while working #200) — in that case announce the mismatch and ask.
4. Once the worktree and branch are settled, record the directory path and branch so Phase 2 can pick them up unambiguously.

This phase exists to keep direct pushes off the default branch and prevent workspace lock contention by isolating development in a dedicated worktree. Default → create worktree automatically; do not block on the user for naming.

## PHASE 1 — RESEARCH

Execute `/research $ARGUMENTS`.

The plan posted to the issue MUST include the `Inconclusive / Deferred items` section (or `Inconclusive / Deferred items: none identified`). This section is the discovery contract Phase 2 will enforce.

## PHASE 2 — IMPLEMENT

After Phase 1 settles and the user approves the (possibly review-revised) plan, execute `/implement $ARGUMENTS`.

Phase 2 will halt rather than ad-hoc-patch any mid-implementation discovery that is not listed in the plan's discovery contract. If that happens, return to Phase 1 (or update the plan explicitly) before resuming.
