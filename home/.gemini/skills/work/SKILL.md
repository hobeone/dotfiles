---
name: work
description: Workflow-aware task execution with checkpoints
---

# Work

Execute tasks with checkpoints: [guided development] → develop → `/pr-review local` → `/pr-create` → `/watch-ci` → `/pr-review remote` → merge → reflect.

Guided development (optional) runs exploration agents, asks clarifying questions, and designs architecture before implementation.

## Usage

```
/work <issue-number | URL | "description">
/work --attach
```

## Identifiers

Tasks use `[work:ID]` prefix:

| Input | Identifier | Example |
|-------|------------|---------|
| Issue number | `issue-<N>` | `[work:issue-42]` |
| Ad-hoc | `adhoc` → `pr-<N>` | `[work:adhoc]` then `[work:pr-118]` |
| Attach to PR | `issue-<N>` or `pr-<N>` | `[work:pr-118]` |

Ad-hoc work transitions to `pr-<N>` after PR creation.

---

## Attach Mode (`--attach`)

Join existing PR on current branch, restoring WIP context if available.

1. **Check for WIP checkpoint**: Look for context from session start.
2. Get PR info: `gh pr view --json number,title,state` via `run_command`.
   - If no PR: "No PR found. Use `/work <issue-number>` to start new work, or `/pr-create` first."
3. Determine identifier from PR body (`Fixes #N` → `issue-N`, otherwise `pr-N`).
4. Determine position from PR/CI state.
5. Create remaining tasks only. Display resume plan showing what's done and what remains.

---

## Starting New Work

### 1. Check for Active Session

If incomplete `[work:*]` tasks exist, block new work.

### 2. Parse Input

- Number → check if it's a GitHub issue first (`gh issue view <N>`). If not found, treat as `adhoc`.
- GitHub URL → extract issue number
- Other → `adhoc`

### 3. Check for Parallel Context

If `.parallel-context.md` exists in cwd, read it with `view_file`. This file is created by `/parallel-work start` and contains:
- Task description from parent session
- Decisions and constraints already established
- Relevant code locations identified
- Whether exploration was already done

Store this as `PARALLEL_CONTEXT` for use in scope presentation and guided development.

### 4. Fetch Context

For issues: fetch title, body, labels using `gh issue view <N> --json title,body,labels` via `run_command`.

### 5. Derive Initial Tasks

Break down into 2-6 implementation tasks (imperative form).
These are preliminary — if user opts into guided development, they'll be refined.

### 6. Present Scope

```markdown
## Proposed Work Scope

**Source:** #42 - Fix authentication timeout
**Identifier:** [work:issue-42]

### Tasks
1. <task 1>
2. <task 2>

### Checkpoints
- /pr-review local → /pr-create → /watch-ci → /pr-review remote → merge → reflect
```

Ask via `ask_question`:
- **Start work** — Proceed to guided development question
- **Modify scope** — Adjust tasks before starting
- **Cancel** — Abort without creating tasks

### 7. Guided Development (Optional)

Ask via `ask_question`: **Yes, explore first (Recommended)** / No, proceed directly

**Default to "Yes"** — the cost of exploration is usually worth it.

Only skip if ALL of these are true:
- You've already read the relevant code in this session
- The change touches ≤3 files
- No architectural decisions to make
- Requirements are unambiguous
- **OR** `PARALLEL_CONTEXT` indicates parent already explored

#### Guided Development Phases

##### Phase 1: Explore

Launch subagents via `invoke_subagent` (`TypeName: "self"`, `Role: "Code Explorer"`):
- "Find features similar to [feature] and trace their implementation"
- "Map the architecture and abstractions for [feature area]"
- "Identify integration points and dependencies"

After agents return, read identified key files with `view_file`.

##### Phase 2: Clarify

Use `brainstorming` skill procedure to structure the design conversation. Feed it exploration findings + issue details:
- Explore user intent and requirements
- Identify edge cases, integration points, and scope boundaries
- Propose approaches and get approval using `ask_question`

##### Phase 3: Architect

Launch 2-3 subagents via `invoke_subagent` (`TypeName: "self"`, `Role: "Code Architect"`) for different approaches:
- **Minimal changes**: Smallest change, maximum reuse
- **Clean architecture**: Maintainability, elegant abstractions
- **Pragmatic balance**: Speed + quality

Present options and recommendations to user via `ask_question`.

##### Phase 4: Document

Use `writing-plans` procedure to create a structured implementation plan in session artifact `<appDataDir>/brain/<conversation-id>/YYYY-MM-DD-<feature-name>.md`. Feed it:
- Key files to modify/create
- Decisions made from clarifying questions
- Chosen architecture approach

##### Phase 5: Derive Tasks

Based on the architecture plan, derive final implementation tasks.

---

### 8. Create Tasks

```
[work:${ID}] <task 1>
[work:${ID}] <task 2>
[work:${ID}] Run /pr-review local
[work:${ID}] Create PR with /pr-create
[work:${ID}] Monitor CI with /watch-ci
[work:${ID}] Process feedback with /pr-review remote
[work:${ID}] Confirm merge with user
[work:${ID}] Reflect with improve-workflow agent
```

---

## Checkpoint Handling

- **Run /pr-review local**: Run, fix issues if found, loop until clean.
- **Create PR**: Run `/pr-create`. If adhoc, update remaining tasks to `[work:pr-N]`.
- **Monitor CI**: Run `/watch-ci <PR#>` in background.
- **Process feedback**: Run `/pr-review remote`.
- **Confirm merge**: Spawn `summarize` subagent to show what's being merged. Always ask user via `ask_question` before merging.
- **Reflect**: Rate difficulty/friction/steering, spawn `improve-workflow` subagent.
