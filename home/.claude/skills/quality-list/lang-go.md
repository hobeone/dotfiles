# Language addenda for Go

This file extends `SKILL.md` with Go-specific triggers, mitigation idioms, and mechanical detection patterns. The audit (`done-check`) and preflight (`todo-check`) skills auto-load this file when the project declares `Language: Go` in its `CLAUDE.md`/`AGENTS.md`, or when the diff touches `.go` files.

This file does **not** introduce new audit items. Items live in `items/<slug>.md` and are language-neutral. Each section below corresponds to an existing item slug and provides the Go realization: what to grep for, what semantics apply, what idioms remediate the concern.

______________________________________________________________________

## `implementation-guards`

### Triggers (Go)

- **Mutex-scope violations.** A blocking I/O call (network, disk, `time.Sleep`) inside a critical section (`mu.Lock()`...`mu.Unlock()`, or a `defer mu.Unlock()` whose scope encloses the call). Snapshot-then-release is the fix: read/marshal under the lock, release, then do the I/O.
- **Manual unlock instead of `defer`.** Any `mu.Unlock()` not immediately preceded by `defer` on the matching `Lock()`, unless the function has an explicit `// --- No lock held below this line ---` comment marking an intentional snapshot-then-release split.
- **`RLock()` guarding a mutation.** `delete()`, map/slice assignment, or field mutation on data whose read side uses `RLock` — mutation always needs the full `Lock`.
- **Unchecked type assertion.** `x := i.(T)` (single-return form) outside a context where the concrete type is already provably guaranteed by construction (e.g., immediately after a `switch v := i.(type)` case). The two-return `x, ok := i.(T)` form is the default; a panic-risking single-return assertion needs a comment explaining why the type is guaranteed.
- **`select` without a shutdown/context case.** A `select` blocking on a channel or semaphore send/receive with no `case <-ctx.Done()` / `case <-shutdownCh` sibling case, in a goroutine that's expected to exit on shutdown.

### Mechanical detection

```sh
rg -n '\.Lock\(\)' -g '*.go' -A 3   # eyeball for I/O between Lock and Unlock
rg -n '\w+, ok := .*\.\(\w' -g '*.go'   # confirm two-return assertions are the norm
rg -n '\.\([A-Z]\w*\)' -g '*.go' | rg -v ', ok :='   # candidate single-return assertions
```

### False-positive review

A single-return type assertion right after a `switch v := i.(type) { case T: ... }` case, or on a value the function itself just constructed with that concrete type, is safe — the guard already exists structurally, just not lexically at the assertion site.

______________________________________________________________________

## `escape-hatch-necessity`

### Triggers (Go)

- **`_ = err`** (or any error silently discarded) without an inline comment stating why the error is intentionally ignored.
- **`//nolint:<rule>`** without a `// reason` suffix explaining why the rule genuinely doesn't apply here, per this project's own convention of requiring a reason on every `nolint` directive.
- **`interface{}` / `any`** in new code where a concrete type or generic type parameter would work — check whether the value's shape is actually known at the call site.
- **`panic()`** for a condition reachable from external input (parsed data, network response, user config) rather than a genuine programmer-error invariant violation.

### Mechanical detection

```sh
rg -n '_\s*=\s*\w+\(' -g '*.go'        # candidate ignored-error sites; filter to actual error returns
rg -n '//nolint:' -g '*.go'            # confirm each has a trailing "// reason"
rg -n '\bpanic\(' -g '*.go'
```

### N/A

`_ = someFunc()` where `someFunc` has no error return (e.g. `_ = fmt.Fprintln(...)` in a context where the write target is a `bytes.Buffer` that cannot fail) is not this item's concern — only genuine error-return discards need a reason.

______________________________________________________________________

## `completion-hygiene`

### Triggers (Go)

- `goimports -w` not run on every touched `.go` file (import grouping/formatting drift).
- `go vet ./...` reporting anything on the touched packages.
- `golangci-lint run ./...` reporting new issues (compare against a pre-change baseline run, not zero-issues-overall, since pre-existing issues in an untouched part of the file aren't this diff's to fix).
- Stray `fmt.Println` / `fmt.Printf` debug output left in non-`main`/non-CLI code, or a commented-out block of code.

### Mechanical detection

```sh
goimports -l .                          # lists files needing formatting; empty = clean
go vet ./...
golangci-lint run ./...
rg -n 'fmt\.Print(ln|f)?\(' -g '*.go' -g '!cmd/**' -g '!**/*_test.go'
```

______________________________________________________________________

## `behavior-coverage`

### Triggers (Go)

- New test function that duplicates an existing test function's shape (build input, call function, assert one condition) three or more times in the same file — a `duplication-extraction` candidate specifically realized as "should have been a table-driven test with `t.Run` subtests".
- A new branch (new `if`/`switch` case, new error path) added to a function with no corresponding new test case exercising it.
- A bug-fix diff whose regression test was not proven to fail on the pre-fix code (this project's own Red-Green Discipline convention, if the project states one).
- **Error-classification predicates tested against synthetic look-alikes instead of real stdlib values.** A function that branches on `errors.As`/type assertion into a stdlib or third-party error type, or on a narrow interface check (`Timeout() bool`, `Temporary() bool`, `Unwrap() error`), where the test fixture is a hand-rolled struct satisfying only the interface under test rather than a real value of the concrete type (e.g. a bare `struct{}` with a `Timeout() bool` method standing in for `*net.OpError`, which itself also implements `Timeout()`). The synthetic fixture can pass while masking a branch-ordering bug that only manifests against the real type's broader interface surface — e.g. checking `errors.AsType[*net.OpError]` before the `Timeout()` interface makes the timeout branch dead code for every real network timeout, since `*net.OpError` itself satisfies `Timeout() bool`, but a synthetic non-`*net.OpError` fixture never exercises that ordering interaction.

### Mechanical detection

```sh
rg -n '^func Test\w+\(t \*testing\.T\)' -g '*_test.go'   # count near-duplicate test function names/shapes by eye
```

### False-positive review

Individually-named test functions are fine below the rule-of-three threshold, or when each genuinely exercises meaningfully different setup/assertion logic (not just different input literals against the identical call-and-assert shape).

For the synthetic-fixture trigger: a hand-rolled fixture is fine when the function under test only checks the single narrow interface and never checks a concrete type that also happens to satisfy it — the risk is specifically ordering between multiple checks (a concrete-type check before a narrower interface check it also satisfies), not narrow-interface testing per se. When a classifier checks both a concrete type and a narrower interface it implements, at least one test case must use the real concrete type wrapping a genuine instance of what the interface represents (e.g. `&net.OpError{Err: os.ErrDeadlineExceeded}`, not a bespoke stub), not just a value satisfying the interface in isolation.

______________________________________________________________________

## `paired-artifact-drift`

### Triggers (Go)

- An exported symbol's doc comment (the `// FuncName ...` comment directly above a `func`/`type`/`var` starting with the symbol's own name, per godoc convention) makes a claim — "never returns nil", "always sorted", "safe for concurrent use", a specific numeric bound — that the diff's new code contradicts or no longer guarantees.
- A doc comment naming a specific error sentinel (`// returns ErrNotFound when...`) where the diff adds a new error return path not covered by that sentinel and not added to the comment.
- A struct field's doc comment describing units/format (`// Timeout in seconds`) where the diff changes the field's type or semantic (e.g. to `time.Duration`).

### Mechanical detection

```sh
git diff <base>..HEAD -- '*.go' | rg '^\+.*func ' -B5 | rg '^-?\s*//'   # doc comments near changed funcs
```

Read each hit's full doc comment and compare its claims against the new function body line-by-line — this item is not mechanically decidable past locating candidates.

______________________________________________________________________

## `public-api-surface`

### Go realization

Go has no explicit `pub`/`export` keyword — capitalization *is* the export mechanism. Any new or renamed identifier (func, type, const, var, struct field, interface method) starting with an uppercase letter, declared at package scope or as an exported struct field, is public API surface the moment it's committed, regardless of whether anything in this repo currently calls it. Treat a new exported symbol in a library-shaped package (anything under a project's public import path, as opposed to `internal/`) with the same scrutiny as a public API in any other language.

`internal/` packages (per Go's own compiler-enforced visibility rule) are *not* public API surface outside the module — a new exported symbol inside `internal/foo` is only reachable by other packages in the same module, so this item is N/A for changes confined to `internal/`.

### Mechanical detection

```sh
git diff <base>..HEAD -- '*.go' | rg '^\+(func|type|const|var) [A-Z]' | rg -v 'internal/'
```

______________________________________________________________________

## `signature-change-regression`

### Triggers (Go)

- A function/method signature change (parameter added/removed/reordered, return type changed, a new required parameter with no natural zero-value default) on an **exported** symbol outside `internal/`, or on any symbol implementing an interface — changing a method's signature can silently break interface satisfaction elsewhere with only a compile error at the *call site*, not the implementation site, easy to miss if only the implementing package was built/tested.
- Adding a method to an interface type — every existing implementer must be updated; `go build ./...` across the whole module (not just the changed package) is the only way to surface this.

### Mechanical detection

```sh
go build ./...      # must be run for the WHOLE module, not just the changed package, after any interface change
grep -rn 'func.*<OldSignatureFragment>' --include='*.go' .   # find all call sites before changing
```

______________________________________________________________________

## `architectural-boundary`

### Triggers (Go)

- A new import from `internal/<pkgA>` to `internal/<pkgB>` that creates or risks an import cycle, or that crosses a layering boundary the project's own architecture doc declares (e.g. a lower-layer package importing a higher-layer one).
- A new dependency added to `go.mod` not already vetted/discussed — Go's module system makes this diff-visible (`go.mod`/`go.sum` changes) but easy to gloss over in a large diff.

### Mechanical detection

```sh
git diff <base>..HEAD -- go.mod go.sum
go list -deps ./... 2>&1 | rg 'import cycle'
```
