---
name: work
description: Workflow-aware task execution with checkpoints
---

# Work

Execute tasks with checkpoints: [guided development] → develop → `/pr-review local` → `/pr-create` → `/watch-ci` → `/pr-review remote` → merge → reflect.

## Usage

```
/work <issue-number | URL | "description">
/work --attach
```

## Instructions

1. Track work state using `[work:ID]` format.
2. If new work, fetch the issue/URL info using `gh issue view` or `gh pr view`.
3. Check for parent context in `.parallel-context.md` if starting from a worktree.
4. Support **Guided Development**:
   - **Explore**: Spawn `research` subagent to explore codebase context.
   - **Clarify**: Run `Skill(brainstorming)` to refine requirements.
   - **Architect**: Propose minimal/clean/pragmatic architectural options.
   - **Document**: Run `Skill(writing-plans)` to write plans to session artifact.
5. Create checklist tasks with `[work:ID]` prefixes.
6. Verify and merge after `/pr-review remote` has completed. Run `summarize` subagent and request confirmation before merging via GitHub API using `ask_question`.
7. Perform reflection step and spawn `improve-workflow` agent when done.
