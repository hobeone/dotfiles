# Go profile

`go_rules.md` (next to `lang/`) is the governing catalog for Go: language
pitfalls (typed nil in interfaces, goroutine leaks and context misuse, resource
leaks, map/slice aliasing, version-aware loop-variable capture), modern-idiom
adoption, concurrency and state lifecycle, error wrapping, and the verifier
decision table. This profile does not repeat any of it. It adds only the idioms
and bugs that catalog leaves out. Claims marked "verified" were run or read from
`go doc` on Go 1.27; version gates refer to the `go` line in `go.mod`.

## Detection

- Extensions `.go`; `go.mod`, `go.work`, `go.sum`.
- Generated files carry the header `// Code generated ... DO NOT EDIT.`; they are Go files but not reviewable, see Do not flag.
- Target version: the `go` directive in the nearest `go.mod`, as `go_rules.md` describes.

## Do not flag

- **Loop-variable capture at `go >= 1.22`, and the other cases the Verify decision table in `go_rules.md` (Section 5) refutes or confirms.** Why: those rules are owned there; a finding that matches one is judged by that table, not by this profile.
- **An ignored error from the write methods of a `bytes.Buffer` or `strings.Builder` (`Buffer.Write`, `WriteString`, `WriteByte`, `WriteRune`), or from `hash.Hash.Write`.** Why: the documentation says the error is always nil (`bytes.Buffer.Write`: "err is always nil"; `strings.Builder.Write`: "always returns len(p), nil"; `hash.Hash`: "It never returns an error"; all read from `go doc`). A `bytes.Buffer` can still panic with `ErrTooLarge`, so unbounded input is a separate finding.
- **Reading from, ranging over, taking `len` of, or `append`ing to a nil slice or nil map.** Why: all are defined and safe (verified: `m["x"]` on a nil map gives the zero value, `range` runs zero times, `append(nil, 1)` works). Only writing to a nil map panics (verified: `assignment to entry in nil map`), so that line is the one to look for.
- **`defer f.Close()` ignoring the error on a file opened read-only (`os.Open`, `fs.File`).** Why: closing a descriptor you only read from cannot lose data. On a file that was written (`os.Create`, `OpenFile` with write flags), the `Close` error can be the only report of a failed flush or a full disk, so there the ignored error is a real finding.
- **`time.After` (or `time.NewTimer` without `Stop`) inside a `select` in a loop when `go.mod` says `go 1.23` or later.** Why: from Go 1.23 unreferenced, unstopped timers are garbage-collected immediately (`go doc time.After`: "As of Go 1.23, the garbage collector can recover unreferenced, unstopped timers"), and the release notes limit that behaviour to modules whose `go` line is 1.23 or newer. Below that, the timer lives until it fires and the leak finding stands.
- **`regexp.MustCompile`, `template.Must`, or similar `Must*` calls on a constant at package level or in `init`.** Why: they panic only when the literal is malformed, which is a programmer error that surfaces at startup (`go doc regexp.MustCompile`: "simplifies safe initialization of global variables"). Flag them when the argument is dynamic or request-derived.
- **Using the zero value of `sync.Mutex`, `sync.RWMutex`, `sync.WaitGroup`, `sync.Once`, `bytes.Buffer` or `strings.Builder` with no constructor.** Why: the zero value is documented to be ready for use (`sync.Mutex`: "The zero value for a Mutex is an unlocked mutex"). What is not allowed is copying them after first use, which `go_rules.md` Section 3 covers.
- **`context.Background()` or `context.TODO()` in `main`, `init`, package-level setup, and tests.** Why: a root context has to come from somewhere, and these are the entry points. Flag it in a function that already receives a `ctx` or serves a request, where it drops cancellation and deadlines.
- **`err` declared again in an `if err := f(); err != nil {` initializer or in a block that handles the error entirely inside it.** Why: the shadow is scoped to that statement and cannot hide a failure from the outer code. The shadowing bug in `go_rules.md` Section 4.2 is an inner `:=` whose error is then lost or whose outer `err` is read afterwards.
- **Newer language features written for a `go.mod` that allows them:** the `min`, `max`, `clear` builtins (1.21), `for i := range n` over an integer (1.22), and range over a function iterator (1.23). Why: they are valid at or above those versions; calling them undefined or a syntax error is wrong. Check the `go` line first.
- **Anything in a file with the `// Code generated ... DO NOT EDIT.` header.** Why: the fix belongs in the generator or its input, and the next generation run overwrites a hand edit.

## Common bugs

Beyond `go_rules.md` Sections 1, 3 and 4:

- **Calling `t.Fatal`, `t.FailNow` or `t.Skip` from a goroutine the test started.** `FailNow` "must be called from the goroutine running the test or benchmark function, not from other goroutines created during the test" (`go doc testing.T.FailNow`); elsewhere it only ends that goroutine. Use `t.Error` and return, or send the failure back to the test goroutine.
- **`for _, v := range items { v.X = 1 }` modifying a copy** (verified: `items` unchanged). Index the slice (`items[i].X = 1`) or range over pointers.
- **`json.Unmarshal` into `any` / `map[string]any` turns every number into `float64`** and loses integers above 2^53 (verified: `9007199254740993` became `9.007199254740992e+15`). Decode into a typed struct, or use `Decoder.UseNumber`.
- **`http.Server` with no `ReadHeaderTimeout` or `ReadTimeout`, and `http.Client` with no `Timeout`.** Zero means no timeout for both (`go doc` for each field), so a slow or stalled peer can hold the connection and goroutine indefinitely. The package-level `http.Get` and `http.ListenAndServe` use those zero values.
- **`==` on `time.Time`, or a `time.Time` as a map key.** `==` compares the location and the monotonic reading as well as the instant; the documentation says to prefer `t.Equal(u)`.
- **`defer` arguments are evaluated when the `defer` statement runs**, not when the function returns: `defer log.Println(elapsed)` logs the value at defer time. Wrap it in a closure when the later value is wanted.
- **Narrowing integer conversions on sizes and indexes from outside** (`int32(len(b))`, `uint8(n)`) wrap silently. Check the range first.

## Trust boundaries

- `net/http` request data: `r.URL.Path` and `r.URL.RawQuery`, `r.Host`, every header, `r.FormValue`, cookies, and the body (cap it with `http.MaxBytesReader`). `r.RemoteAddr` is the peer, while `X-Forwarded-For` is whatever the client sent unless a trusted proxy overwrites it.
- File paths built from outside input. `filepath.Join(base, user)` keeps `..` segments (verified: `Join("/srv/uploads", "../../etc/passwd")` is `/etc/passwd`). Containment needs `os.OpenRoot` (Go 1.24+), `filepath.IsLocal`, or a `filepath.Rel` boundary check. Archive member names are attacker-controlled too: `archive/zip` reports `ErrInsecurePath` only when `GODEBUG=zipinsecurepath=0` is set (`go doc archive/zip`), so by default it is the caller's job to check names.
- Commands: `exec.Command(name, args...)` does not use a shell, so arguments are not parsed for metacharacters, but a user-controlled `name` is looked up on `PATH` and arguments beginning with `-` are options. `exec.Command("sh", "-c", s)` with outside text in `s` is injection.
- SQL: values interpolated with `fmt.Sprintf` instead of placeholders (`?`, `$1`) in `database/sql` calls.
- Templates: `text/template` does no HTML escaping; `html/template` does, but `template.HTML`, `template.JS` and `template.URL` conversions mark the value as already safe.
- Outbound requests built from user-supplied URLs (SSRF), `tls.Config{InsecureSkipVerify: true}`, `unsafe`, `reflect` and `cgo` boundaries, and decoding of untrusted data into `any` (Common bugs).
- Environment, flags and config files read at startup are trusted only as far as whoever can write them is trusted.
