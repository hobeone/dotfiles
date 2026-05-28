---
name: golang-project-standards
description: "Bootstrap Go project development standards. Use when starting a new Go project, onboarding an existing Go project, or when a project is missing a GEMINI.md with development mandates. Generates or audits GEMINI.md with build commands, quality gates, coding idioms, concurrency rules, and commit conventions."
user-invocable: true
metadata:
  author: hobe
  version: "1.0.0"
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(git:*) Bash(goimports:*) Bash(golangci-lint:*) Agent
---

# Go Project Standards Bootstrap

Use this skill to establish or audit development standards for a Go project. It covers two scenarios:

- **New project**: no `GEMINI.md` exists yet.
- **Existing project**: a `GEMINI.md` exists but may be missing the standard development mandate sections.

---

## Step 1: Assess the Project

Before writing anything, run these read-only commands to understand the project:

```bash
# Confirm it is a Go module and read the module name and Go version
cat go.mod | head -10

# List top-level packages
go list ./...

# Check if GEMINI.md already exists
ls GEMINI.md 2>/dev/null && echo "EXISTS" || echo "MISSING"

# Check if golangci-lint config exists
ls .golangci.yml 2>/dev/null || ls .golangci.yaml 2>/dev/null || echo "NO LINT CONFIG"
```

Use the findings to fill in the project-specific fields in the template below (module path, binary name, description).

---

## Step 2: Audit or Create GEMINI.md

### If GEMINI.md exists

Read it fully. Check whether it already contains each of these sections. For any section that is absent or incomplete, append or update it with the canonical content from **Step 3** below. Do **not** remove or overwrite existing project-specific content (architecture notes, lessons learned, etc.) — only add what is missing.

### If GEMINI.md does not exist

Create it using the template in **Step 3**, filling in the project-specific fields.

---

## Step 3: Canonical GEMINI.md Content

The following sections are **required** in every Go project's GEMINI.md. Adapt the project-specific fields (marked with `<angle brackets>`) to the actual project.

---

### Project Overview block (customize fully)

```markdown
# <Project Name>

<One paragraph describing what this project does and who uses it.>

## Architecture

- `<cmd/name>/`: Entry point.
- `<internal/>`: Core packages.

## Building & Running

- **Build:** `go build ./...`
- **Run:** `./<binary> <flags>`
- **Test (unit):** `go test ./...`
- **Test (race):** `go test -race ./...`
- **Lint:** `go vet ./...` and `golangci-lint run ./...`
```

---

### Development Standards block (copy verbatim — do not customize)

````markdown
## Development Standards

Any AI agent or developer working on this codebase **must** follow these mandates.

### Tooling Setup

```bash
# Install goimports if not present
go install golang.org/x/tools/cmd/goimports@latest

# Install golangci-lint if not present (see https://golangci-lint.run/welcome/install/)
```

### Per-File Workflow (after every .go file edit)

```bash
goimports -w <file>   # format + resolve imports
go fix ./...          # adopt new language features automatically
go build ./...        # verify it compiles
```

### Quality Gate (before every commit)

```bash
goimports -w .
go fix ./...
go vet ./...
go test -race ./...
golangci-lint run ./...
```

All five must pass. Do not commit with failing tests, vet errors, or lint warnings.

### Coding Standards

- **Idioms:** "Accept interfaces, return structs." Define interfaces at the consumer side.
- **Context:** Every blocking or cancellable operation **must** accept `context.Context` as the first parameter.
- **Errors:** Wrap with `fmt.Errorf("component: ...: %w", err)`. Never use `%v` for errors that will be inspected.
- **No hacks:** No `init()` for setup. No `panic` for control flow. No `time.Sleep` in tests — use channels or `sync.WaitGroup`.
- **Standard library first:** Prefer `slices`, `maps`, `errors.Is/As`, `min`/`max` builtins over custom helpers or reflection.

### Concurrency & Locking

- **Never hold a mutex during I/O.** Snapshot under the lock, release, then do I/O.
- **Always `defer mu.Unlock()`.** Only exception: intentional snapshot-then-release, marked with `// --- no lock held below this line ---`.
- **Every `select` must watch `ctx.Done()`.** Goroutines blocked without a context escape route leak forever.
- **Use `sync.Once` or `CompareAndSwap` for idempotent shutdown.** Prevents double-close panics.

### Commit Convention

All commits must follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <description>
```

| Type | When to use |
|------|-------------|
| `feat` | New user-visible capability |
| `fix` | Bug patch |
| `perf` | Performance improvement with benchmark evidence |
| `refactor` | Code restructuring, no behavior change |
| `test` | Adding or improving tests |
| `docs` | Documentation only |
| `chore` | Build, CI, dependency updates |

Append `!` or add `BREAKING CHANGE:` footer for any public API or wire-format change.
````

---

## Step 4: Verify Tooling Is Available

Run the following and report any missing tools to the user:

```bash
which goimports   || echo "MISSING: go install golang.org/x/tools/cmd/goimports@latest"
which golangci-lint || echo "MISSING: see https://golangci-lint.run/welcome/install/"
which goimports && goimports --help 2>&1 | head -1
go version
```

If `goimports` is missing, propose the install command but do not run it automatically — ask the user to confirm.

---

## Step 5: Check for golangci-lint Config

If `.golangci.yml` does not exist, suggest creating a minimal one. Do not create it automatically without user approval — just note it as a recommendation.

Minimal recommended config:

```yaml
# .golangci.yml
linters:
  enable:
    - goimports
    - govet
    - staticcheck
    - errcheck
    - gosimple
    - ineffassign
    - unused

linters-settings:
  goimports:
    local-prefixes: <module-path>

issues:
  max-issues-per-linter: 0
  max-same-issues: 0
```

---

## Step 6: Commit the Changes

Once GEMINI.md is written or updated:

```bash
git add GEMINI.md
git commit -m "docs: add development standards to GEMINI.md"
```

If `.golangci.yml` was also created:

```bash
git add .golangci.yml
git commit -m "chore: add golangci-lint configuration"
```

---

## What This Skill Does NOT Do

- Does not modify existing Go source files.
- Does not enforce project-specific architecture rules (add those manually to GEMINI.md after this skill runs).
- Does not install binaries without user confirmation.
- Does not create CI workflow files (see the `golang-continuous-integration` skill for that).
