# Go Review Rules & Pitfall Catalog

Authoritative reference for reviewing Go codebases. Used by `deep-pr-review` finders (Phases 1 & 3), verifiers (Phase 2), and prompt generators (Phase 4).

---

## 1. Angle D: Go Language Pitfalls & Correctness Bugs

### 1.1 Typed `nil` in Interface Returns
In Go, an interface value is represented internally as a 2-word pair: `(type, value)`. An interface is `nil` **if and only if** both its type and value components are `nil`. Returning a typed pointer whose value is `nil` inside an `error` or interface return type constructs a non-nil interface `(type=*ConcreteType, value=nil) != nil`.

```go
// ❌ WRONG: Returns non-nil interface (type=*CustomError, value=nil)
func Validate(req *Request) error {
    var err *CustomError = nil
    if req.Invalid {
        err = &CustomError{msg: "bad request"}
    }
    return err // Caller's `if err != nil` is ALWAYS true!
}

// ✅ CORRECT: Return untyped nil literal or declare return type as error
func Validate(req *Request) error {
    if req.Invalid {
        return &CustomError{msg: "bad request"}
    }
    return nil // Interface (type=nil, value=nil) == nil
}
```

#### Failure Scenario
The caller executes `if err := Validate(req); err != nil { ... }`. Even when `req.Invalid` is `false`, the `if` block executes. Calling `err.Error()` on the nil pointer crashes with a `nil pointer dereference` panic.

---

### 1.2 Goroutine Leaks & Context Misuse

#### A. Writer Blocked on Unbuffered Channel
Spawning a worker goroutine that writes to an unbuffered channel when the parent reader exits early (e.g. on context cancellation or error) permanently leaks the worker goroutine.

```go
// ❌ WRONG: Goroutine leaks if ctx is canceled before or during worker run
func QueryFirst(ctx context.Context, urls []string) (string, error) {
    ch := make(chan string) // unbuffered
    for _, url := range urls {
        go func(u string) {
            res := fetch(u)
            ch <- res // BLOCKS FOREVER if parent returns early
        }(url)
    }
    select {
    case res := <-ch:
        return res, nil
    case <-ctx.Done():
        return "", ctx.Err()
    }
}

// ✅ CORRECT: Buffer channel to capacity or select on ctx.Done()
func QueryFirst(ctx context.Context, urls []string) (string, error) {
    ch := make(chan string, len(urls)) // buffered capacity matches senders
    for _, url := range urls {
        go func(u string) {
            select {
            case ch <- fetch(u):
            case <-ctx.Done():
                return
            }
        }(url)
    }
    select {
    case res := <-ch:
        return res, nil
    case <-ctx.Done():
        return "", ctx.Err()
    }
}
```

#### B. Context in Struct Fields
Storing `context.Context` inside a struct field (anti-pattern) instead of passing it as the first parameter to methods creates lifetime ambiguity and prevents cancellation/deadline propagation.

```go
// ❌ WRONG: Storing context inside struct
type Client struct {
    ctx context.Context // Anti-pattern
}

// ✅ CORRECT: Pass context as the first argument to every method
type Client struct {}

func (c *Client) Fetch(ctx context.Context, id string) (*Data, error) {
    // ...
}
```
*(Exception: Standard library types explicitly documented like `http.Request.Context()`)*.

#### C. Missing `defer cancel()` on Context Derivation
Failing to call `cancel()` on `context.WithTimeout`, `context.WithDeadline`, or `context.WithCancel` leaks the associated timer and context tree nodes until deadline expiration or process termination.

```go
// ❌ WRONG: Timer resources leak if operation finishes before timeout
ctx, _ := context.WithTimeout(parentCtx, 30*time.Second)
res, err := doWork(ctx)

// ✅ CORRECT: Always defer cancel() immediately
ctx, cancel := context.WithTimeout(parentCtx, 30*time.Second)
defer cancel()
res, err := doWork(ctx)
```

#### D. Deep Context Severing (`context.Background()` / `TODO()`)
Creating a fresh `context.Background()` deep within a call stack disconnects the caller's cancellation signals, deadlines, and distributed tracing spans. Always pass and propagate the caller's `ctx`.

---

### 1.3 Resource Leaks

#### A. HTTP Response Body Handling
Calling `defer resp.Body.Close()` before checking `err != nil` triggers a nil-pointer dereference panic on network errors. Not draining and closing `resp.Body` on non-200 responses leaks the underlying TCP connection and prevents HTTP keep-alive reuse.

```go
// ❌ WRONG: Panic on error, leaked socket on non-200 if not closed
resp, err := http.Get(url)
defer resp.Body.Close() // PANIC if err != nil!
if err != nil {
    return err
}

// ✅ CORRECT: Check error first, defer close, drain body before exit
resp, err := http.Get(url)
if err != nil {
    return fmt.Errorf("http get %s: %w", url, err)
}
defer resp.Body.Close()

if resp.StatusCode != http.StatusOK {
    io.Copy(io.Discard, resp.Body) // Drain to reuse connection
    return fmt.Errorf("unexpected status: %d", resp.StatusCode)
}
```

#### B. `defer` Inside Unbounded Loops
`defer` statements execute when the **enclosing function** returns, NOT when the loop iteration ends. Placing `defer` inside a `for` or `range` loop accumulates open file descriptors, sockets, or mutex locks.

```go
// ❌ WRONG: All files remain open until ProcessFiles returns
func ProcessFiles(paths []string) error {
    for _, p := range paths {
        f, err := os.Open(p)
        if err != nil {
            return err
        }
        defer f.Close() // Accumulates file descriptors
        // process f...
    }
    return nil
}

// ✅ CORRECT: Wrap iteration in closure or close explicitly
func ProcessFiles(paths []string) error {
    for _, p := range paths {
        if err := func(path string) error {
            f, err := os.Open(path)
            if err != nil {
                return err
            }
            defer f.Close()
            return process(f)
        }(p); err != nil {
            return err
        }
    }
    return nil
}
```

#### C. Unbounded `io.ReadAll`
Calling `io.ReadAll(r)` on untrusted network streams without size limits allows malicious or unexpected payloads to consume all available memory (OOM vulnerability).

```go
// ❌ WRONG: Memory exhaustion on large/infinite stream
body, err := io.ReadAll(req.Body)

// ✅ CORRECT: Limit maximum readable bytes
const maxBodyBytes = 10 * 1024 * 1024 // 10MB
body, err := io.ReadAll(io.LimitReader(req.Body, maxBodyBytes))
```

---

### 1.4 Map & Slice Aliasing / Data Races

#### A. Concurrent Map Access
Concurrent reads and writes on a native Go `map` trigger an unrecoverable runtime crash: `fatal error: concurrent map read and map write`. This cannot be caught by `recover()`.

```go
// ❌ WRONG: Data race and fatal crash under concurrent access
type Registry struct {
    items map[string]string
}
func (r *Registry) Set(k, v string) { r.items[k] = v }
func (r *Registry) Get(k string) string { return r.items[k] }

// ✅ CORRECT: Guard with sync.RWMutex
type Registry struct {
    mu    sync.RWMutex
    items map[string]string
}
func (r *Registry) Set(k, v string) {
    r.mu.Lock()
    defer r.mu.Unlock()
    r.items[k] = v
}
func (r *Registry) Get(k string) (string, bool) {
    r.mu.RLock()
    defer r.mu.RUnlock()
    v, ok := r.items[k]
    return v, ok
}
```

#### B. Subslice Memory Retention (GC Leak)
Sub-slicing a large slice (`largeSlice[:small]`) holds a reference to the entire backing array in memory, preventing garbage collection.

```go
// ❌ WRONG: Retains full 100MB backing array in memory
func GetHeader(data []byte) []byte {
    return data[:16]
}

// ✅ CORRECT: Clone or copy to detach from large backing array
func GetHeader(data []byte) []byte {
    return slices.Clone(data[:16]) // Or make+copy
}
```

#### C. Append Clobbering / Shared Backing Array Mutation
When multiple sub-slices share a backing array, `append` operations on one slice can overwrite elements of another if capacity is available.

```go
// ❌ WRONG: b mutates elements of a's backing array
a := []int{1, 2, 3, 4, 5}
b := a[1:3]     // len=2, cap=4
b = append(b, 99) // Overwrites a[3] with 99!

// ✅ CORRECT: Use 3-index slicing to constrain capacity
b := a[1:3:3]   // len=2, cap=2. append will allocate new backing array
b = append(b, 99) // a is unchanged
```

---

### 1.5 Version-Aware Loop Variable Capture

#### Go < 1.22
Range loop variables `k, v` reuse the same memory address across iterations. Closures or goroutines capturing `v` by reference observe the value of `v` at execution time (typically the final iteration value).
- **Remediation**: Re-bind `v := v` inside the loop or pass `v` as an argument to the goroutine/closure.

#### Go >= 1.22
Loop variables in `for` and `range` loops have **per-iteration scope** by default. Closures created in each iteration capture distinct variables.
- **Review Rule**: Do **NOT** flag loop variable closure captures as bugs if the project's `go.mod` specifies Go 1.22 or higher, unless `GOEXPERIMENT=noloopvar` is explicitly set.

---

## 2. Angle G: Simplification & Modern Go Idioms

### 2.1 Modern Standard Library Adoption (Go 1.21+)

#### A. `slices` & `maps` Packages (Go 1.21+)
Replace custom loops and external libraries with standard library functions:
- `slices.Contains(s, v)` / `slices.ContainsFunc(s, fn)`
- `slices.Equal(s1, s2)` / `slices.EqualFunc(s1, s2, fn)`
- `slices.Clone(s)` / `slices.Compact(s)` / `slices.Delete(s, i, j)`
- `slices.SortFunc(s, cmpFn)` / `slices.Index(s, v)`
- `maps.Clone(m)` / `maps.Copy(dst, src)` / `maps.Equal(m1, m2)` / `maps.DeleteFunc(m, fn)`

```go
// ❌ WRONG: Custom loop boilerplate
func contains(list []string, target string) bool {
    for _, item := range list {
        if item == target { return true }
    }
    return false
}

// ✅ CORRECT: Standard library generic helper
if slices.Contains(list, target) { ... }
```

#### B. Built-ins `min`, `max`, `clear` & `cmp.Or` (Go 1.21+)
- Use `min(a, b, ...)` and `max(a, b, ...)` instead of custom comparison helpers or `math.Min` float conversions.
- Use `clear(slice)` (zeros elements) and `clear(map)` (deletes all entries).
- Use `cmp.Or(val1, val2, fallback)` to resolve the first non-zero/non-empty value.

```go
// ❌ WRONG: Verbose fallback checks
host := config.Host
if host == "" {
    host = os.Getenv("HOST")
    if host == "" {
        host = "localhost"
    }
}

// ✅ CORRECT: Declarative default selection
host := cmp.Or(config.Host, os.Getenv("HOST"), "localhost")
```

#### C. `sync.OnceValue` / `sync.OnceValues` / `sync.OnceFunc` (Go 1.21+)
Simplify lazy one-time initialization:

```go
// ❌ WRONG: Manual sync.Once variable synchronization
var (
    configInstance *Config
    configErr      error
    configOnce     sync.Once
)
func GetConfig() (*Config, error) {
    configOnce.Do(func() {
        configInstance, configErr = loadConfig()
    })
    return configInstance, configErr
}

// ✅ CORRECT: sync.OnceValues encapsulates value and error
var getConfig = sync.OnceValues(func() (*Config, error) {
    return loadConfig()
})
```

#### D. Structured Logging with `log/slog` (Go 1.21+)
Prefer `log/slog` for structured, leveled, contextual logging:
```go
slog.Info("processing job", slog.String("job_id", id), slog.Int("attempts", count))
```

#### E. Go 1.22 Routing & `math/rand/v2`
- **`net/http` Enhanced Routing**: Use method matching and path parameters (`mux.HandleFunc("GET /users/{id}", handleUser)`).
- **`math/rand/v2`**: Use `rand.N(n)` for uniform ranges, faster ChaCha8/PCG generators, and thread-safe global random functions without `rand.Seed()`.

#### F. Go 1.23 Iterators (`iter.Seq`, `iter.Seq2`)
Use standard range over func patterns instead of allocating full intermediate slices:
```go
func (t *Tree) All() iter.Seq[string] {
    return func(yield func(string) bool) {
        // traverse and yield
    }
}
// Consumer
for val := range tree.All() { ... }
```
Use `slices.Collect(seq)` to collect an iterator into a slice.

---

### 2.2 Anti-Pattern Pruning

#### A. Single-Implementation Producer Interfaces
- **Rule**: Accept interfaces, return concrete structs ("Postel's Law").
- **Anti-Pattern**: Defining 1:1 interfaces in the producer/implementation package next to the single struct that implements it. Interfaces should be defined by the consumer package that requires the abstraction.

#### B. Redundant Getter/Setter Boilerplate
Avoid adding Java-style `GetFoo()` / `SetFoo()` methods on unexported struct fields when there are no invariants, validation checks, or mutex guards. Direct field access is idiomatic in Go.

#### C. Redundant Nil Slices Checks
In Go, `len(nil) == 0` and `cap(nil) == 0`.
```go
// ❌ WRONG: Redundant nil check
if items != nil && len(items) > 0 { ... }

// ✅ CORRECT: Simple length check
if len(items) > 0 { ... }
```

#### D. Unnecessary Pointers to Reference Types
Slices, maps, channels, and interfaces already contain pointer/header internals. Passing `*[]T`, `*map[K]V`, `*chan T`, or `*interface` is an anti-pattern unless the function explicitly needs to modify the header itself (e.g. re-assigning slice header in an in-place resizing helper).

---

## 3. Angle K: Concurrency & State Lifecycle

### 3.1 Lock Copying (`copylocks`)
`sync.Mutex`, `sync.RWMutex`, `sync.WaitGroup`, and `sync.Cond` maintain internal state that must never be copied.
- Passing a struct containing a mutex by value creates a separate, independent lock.
- Any struct containing synchronization primitives **must** be passed by pointer (`*MyStruct`), and all its methods must use pointer receivers.

```go
// ❌ WRONG: Value receiver copies mutex state
type SafeCounter struct {
    mu    sync.Mutex
    value int
}
func (c SafeCounter) Inc() { // COPIES MUTEX! Lock is ineffective
    c.mu.Lock()
    defer c.mu.Unlock()
    c.value++
}

// ✅ CORRECT: Pointer receiver
func (c *SafeCounter) Inc() {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.value++
}
```

---

### 3.2 Synchronization Invariants

#### A. `wg.Add(1)` Goroutine Placement
Calling `wg.Add(1)` inside the spawned goroutine introduces a race condition: the caller may reach `wg.Wait()` before the spawned goroutine executes `Add(1)`, causing `Wait()` to return immediately.

```go
// ❌ WRONG: Add inside goroutine races with Wait()
for _, item := range items {
    go func(it Item) {
        wg.Add(1) // RACE CONDITION!
        defer wg.Done()
        process(it)
    }(item)
}
wg.Wait()

// ✅ CORRECT: Add synchronously before launching goroutine
for _, item := range items {
    wg.Add(1)
    go func(it Item) {
        defer wg.Done()
        process(it)
    }(item)
}
wg.Wait()
```

#### B. `sync.Once` Re-entrancy Deadlock
A `sync.Once.Do` call that directly or indirectly calls the same `sync.Once.Do` instance causes an unrecoverable deadlock because `Do` waits for the outer initialization function to complete before releasing its internal lock.

#### C. Mixed Atomic and Non-Atomic Memory Access
Reading or writing a variable via standard operators (`v = 1` or `_ = v`) while other goroutines access it via `sync/atomic` (`atomic.StoreInt64`, `atomic.LoadInt64`) causes data races and undefined behavior on architectures that do not guarantee word-level atomicity or cache coherence. Use `atomic.Int64` / `atomic.Bool` types consistently everywhere.

---

## 4. Angle L: Signal Loss & Error Ergonomics

### 4.1 Error Wrapping & Type Assertions

#### A. Preserving Error Trees with `%w`
Using `fmt.Errorf("%v", err)` or `fmt.Errorf("%s", err)` turns the error into flat text and discards the underlying error tree. Use `%w` so callers can unwrap and inspect the root cause with `errors.Is` and `errors.As`.

```go
// ❌ WRONG: Breaks error inspection for callers
if err != nil {
    return fmt.Errorf("read failed: %v", err)
}

// ✅ CORRECT: Wraps error preserving causal chain
if err != nil {
    return fmt.Errorf("read config from %s: %w", path, err)
}
```

#### B. `errors.Is` and `errors.As` over Equality / Direct Type Assertions
- Never use direct error equality (`err == sql.ErrNoRows`) because wrapped errors (`fmt.Errorf("...: %w", ErrNotFound)`) will not match. Use `errors.Is(err, sql.ErrNoRows)`.
- Never use direct type assertion (`pe := err.(*os.PathError)`). Use `var pe *os.PathError; if errors.As(err, &pe) { ... }`.

```go
// ❌ WRONG: Fails on wrapped errors or panics on type mismatch
if err == sql.ErrNoRows { ... }
pe := err.(*os.PathError) // Panics if err is wrapped or different type!

// ✅ CORRECT: Traverses unwrapping hierarchy safely
if errors.Is(err, sql.ErrNoRows) { ... }

var pe *os.PathError
if errors.As(err, &pe) {
    slog.Warn("path error", slog.String("path", pe.Path))
}
```

---

### 4.2 Error Variable Shadowing
Using the short declaration `:=` inside an inner block (`if`, `for`, `switch`) can shadow an outer named return variable or error variable, causing the function to return a stale or `nil` error.

```go
// ❌ WRONG: Inner err shadows outer named error
func Execute(cmd string) (err error) {
    if shouldAudit {
        res, err := runAudit(cmd) // Shadowing outer `err`!
        if err != nil {
            return // Returns outer `err`, which is still NIL!
        }
        _ = res
    }
    return nil
}

// ✅ CORRECT: Assign to outer error variable
func Execute(cmd string) (err error) {
    if shouldAudit {
        var res Result
        res, err = runAudit(cmd)
        if err != nil {
            return fmt.Errorf("audit failed: %w", err)
        }
        _ = res
    }
    return nil
}
```

---

## 5. Phase 2 Verifier Guardrails (Go Refutations & Confirmations)

When acting as a Phase 2 Verifier on Go findings, follow these strict validation rules:

| Finding Category | Verification Check | Decision Rule |
|---|---|---|
| **Loop variable closure capture** | Check `go.mod` for Go version. | If `go.mod` specifies `>= 1.22` and no `noloopvar` flag -> **REFUTE** (Go 1.22 per-iteration loop variables guarantee isolation). If `< 1.22` -> **CONFIRM**. |
| **Typed `nil` interface return** | Check static return type vs concrete variable type. | If return type is `error` or interface AND variable is declared as a concrete pointer `*T(nil)` -> **CONFIRM**. If variable is declared as interface `var err error = nil` or literal `return nil` -> **REFUTE**. |
| **Channel send deadlock** | Audit channel capacity, select branches, and contexts. | If `select` has a `default:` clause -> **REFUTE**. If `cap(ch) >= number_of_senders` -> **REFUTE**. If send is guarded by `case <-ctx.Done():` -> **REFUTE**. If unbuffered channel with no guaranteed active reader on early error path -> **CONFIRM**. |
| **Lock copy (`copylocks`)** | Inspect receiver and assignment sites. | If struct containing mutex is passed by value or has value receiver -> **CONFIRM**. If pointer receiver/reference throughout -> **REFUTE**. |
| **Unwrapped error (`%v` vs `%w`)** | Check whether error is exposed across package boundary or tested with `errors.Is`/`As`. | If error is internal log-only string -> **PLAUSIBLE** / **Nitpick**. If error is returned from public/internal API function to caller -> **CONFIRM**. |

---

## 6. Phase 4 AI Remediation Prompt Conventions

When writing `🤖 Prompt for AI Agents` in CodeRabbit comments for Go findings, adhere to these conventions:

### 6.1 Idiomatic Go Naming
- **Receiver Names**: 1 or 2 letters matching the type name (e.g., `s *Server`, `c *Client`, `r *Reader`). Never use `this`, `self`, or verbose nouns like `serverInstance`.
- **Acronyms**: Keep acronyms consistent in casing (`ServeHTTP`, `APIClient`, `XMLHTTPRequest`, `userID`, `URL`).
- **MixedCaps**: Exported names use `PascalCase`, unexported names use `camelCase`. Avoid snake_case.

### 6.2 Table-Driven Tests
Require test remediations to follow standard Go table-driven patterns with subtests and helper annotations:

```go
func TestProcessor_Run(t *testing.T) {
    t.Parallel()

    tests := []struct {
        name    string
        input   string
        want    string
        wantErr bool
    }{
        {
            name:  "valid payload",
            input: "test-data",
            want:  "PROCESSED: test-data",
        },
        {
            name:    "empty input returns error",
            input:   "",
            wantErr: true,
        },
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            t.Parallel()
            
            p := NewProcessor()
            got, err := p.Run(context.Background(), tc.input)
            if tc.wantErr {
                if err == nil {
                    t.Fatalf("Run(%q) expected error, got nil", tc.input)
                }
                return
            }
            if err != nil {
                t.Fatalf("Run(%q) unexpected error: %v", tc.input, err)
            }
            if got != tc.want {
                t.Errorf("Run(%q) = %q, want %q", tc.input, got, tc.want)
            }
        })
    }
}
```
- Use `t.Helper()` at the start of test helper functions.
- Use `t.Cleanup(func() { ... })` for test resource teardown instead of manual `defer` in complex test setups.

### 6.3 Standard Error Wrapping Format
Remediation prompts must instruct error wrapping in the format:
```go
fmt.Errorf("<action> <target>: %w", err)
```
- Action is a lowercase active participle or verb phrase (e.g. `reading config`, `connecting to db`, `decoding payload`).
- No capital letters at start of message, no punctuation or newlines at the end.

---

## 7. Cross-Skill References

When deeper reference material, architectural patterns, or specialized audit checklists are required during a review pass or when generating remediation prompts, consult these companion skills (optional extensions from `samber/cc-skills-golang` located under `~/.gemini/skills/`):

### 7.1 Core Review & Analysis Skills
- **Safety & Defensive Coding**: `~/.gemini/skills/golang-safety`
  - Deep-dive into nil safety, interface tuple internals `(type, value)`, numeric overflow, slice aliasing under `append`, and defensive copying.
- **Concurrency & Goroutine Lifecycle**: `~/.gemini/skills/golang-concurrency`
  - Structured concurrency, channel direction and ownership, `errgroup` vs `sync.WaitGroup`, worker pool patterns, and leak-free shutdown.
- **Error Handling & Inspection**: `~/.gemini/skills/golang-error-handling`
  - The single-handling rule (log or return, never both), `%w` error trees, `errors.Is`/`errors.As`/`errors.Join`, and panic/recover boundaries.
- **Modernization & Language Features**: `~/.gemini/skills/golang-modernize`
  - Go version matrix (Go 1.21–1.26), standard library replacements (`slices`, `maps`, `cmp.Or`, `min`/`max`/`clear`, `sync.OnceValue`, `iter.Seq`), and deprecation migrations.
- **Context Lifecycle & Deadlines**: `~/.gemini/skills/golang-context`
  - Context propagation rules, request boundary management, cancellation cascades, `context.WithoutCancel`, and avoiding struct-held contexts.
- **Structs & Interface Design**: `~/.gemini/skills/golang-structs-interfaces`
  - "Accept interfaces, return structs", interface segregation (1–3 methods max), consumer-defined interfaces, struct embedding pitfalls, and receiver consistency.

### 7.2 Testing, Security & Remediation Skills
- **Table-Driven Testing & Leak Detection**: `~/.gemini/skills/golang-testing`
  - Table-driven test construction, `t.Parallel()` subtest scoping, `t.Helper()` stack annotations, `t.Cleanup()` teardowns, and `goleak` goroutine leak assertions.
- **Performance & Allocation Optimization**: `~/.gemini/skills/golang-performance`
  - Heap allocation profiling, slice/map preallocation, `sync.Pool` reuse, and avoiding closure memory retention on long-lived objects.
- **Security & Vulnerability Prevention**: `~/.gemini/skills/golang-security`
  - Path traversal defense (`os.Root` in Go 1.24+, `filepath.Localize`, or `filepath.Rel` boundary validation), constant-time crypto comparisons (`subtle.ConstantTimeCompare`), SQL/command injection, and safe deserialization.
- **Static Analysis & Linting**: `~/.gemini/skills/golang-lint`
  - `golangci-lint`, `govet`, and `staticcheck` rule configuration and pre-flight diagnostics.
