---
name: research-and-implement
description: Work a GitHub issue end to end in two phases — research, then implement — under quaere-evidence and quaere-execution discipline.
---

# research-and-implement

End-to-end wrapper. Runs `research` (Phase 1) and `implement` (Phase 2) in sequence, with a branch baseline gate up front.

**Issue:** #$ARGUMENTS

## PHASE 0 — BRANCH BASELINE

Before research begins, settle the working branch.

1. Check current branch: `git branch --show-current`
2. Determine default branch: `git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'`
3. **Decision gate**:
   - On default branch → pick a conventional `<type>/<issue#>-<slug>` (`feat/195-dmrg-envs`, `fix/187-arpack-info`, `chore/<slug>`), create it, and proceed. Do not poll the user for the name — branch names are throwaway closed-PR metadata. Announce the chosen name in one line so the user can intervene if they object, then continue without waiting.
   - On a non-default branch → treat it as the intended branch and proceed. Only stop if the branch name plainly contradicts the issue (e.g., on `feat/100-foo` while working #200) — in that case announce the mismatch and ask.
4. Once the branch is settled, record it (and any switch / creation action) so Phase 2 can pick it up unambiguously.

This phase exists to keep direct pushes off the default branch by making the question deterministic at the start. Default → branch automatically; do not block on the user for naming.

## PHASE 1 — RESEARCH

Execute `/research $ARGUMENTS`.

The plan posted to the issue MUST include the `Inconclusive / Deferred items` section (or `Inconclusive / Deferred items: none identified`). This section is the discovery contract Phase 2 will enforce.

## PHASE 2 — IMPLEMENT

After Phase 1 settles and the user approves the (possibly review-revised) plan, execute `/implement $ARGUMENTS`.

Phase 2 will halt rather than ad-hoc-patch any mid-implementation discovery that is not listed in the plan's discovery contract. If that happens, return to Phase 1 (or update the plan explicitly) before resuming.
