# Efficiency waste

When a diff introduces work the program does not need to do, the waste is the finding: name the cheaper alternative. Four forms, all judgable from the literal diff text:

1. **Redundant computation or repeated I/O** — the same value recomputed per iteration when it is loop-invariant; the same file, query, or request issued more than once where one result would serve.
2. **Sequential independent operations** — two or more operations with no data dependency between them, awaited one after another, where the runtime offers a concurrent form.
3. **Work added to startup or a hot path** — initialization, parsing, or I/O introduced into a path the program runs on every request, every frame, or every process launch, when it could be deferred, cached, or hoisted out.
4. **Long-lived objects built from closures or captured environments** — a closure, bound method, or partial application that outlives the scope it captured keeps that entire enclosing scope alive for the object's lifetime. When the captured scope holds large values, this is a memory leak with no visible allocation site. Prefer a class or struct that copies only the fields it needs.

Form 4 is the one a reviewer is least likely to catch by inspection and the one with the largest blast radius, because nothing at the allocation site names the retained data.

**Concern conditions:**

- A diff introduces any of the four forms above, and a cheaper alternative exists that does not change observable behavior.

**N/A:**

- The diff adds no new computation, I/O, concurrency structure, or captured-scope object.
- The apparent waste is required for correctness — an intentional re-read to observe external mutation, a deliberate sequential ordering enforcing a happens-before relationship, an eager initialization a later invariant depends on.
- The cheaper alternative would change observable behavior (evaluation order a caller depends on, timing a test asserts, identity semantics of a returned value). That makes it an `impact-verification` question, not this item's.
- The captured scope in form 4 is small and bounded, and the object's lifetime does not exceed the scope's natural one.
