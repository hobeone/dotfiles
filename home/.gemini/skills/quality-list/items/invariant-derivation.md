# Invariant derivation (when fixing)

For any fix in response to a bug, review finding, or failing test classified as **invariant-bearing**, derive complete necessary-and-sufficient conditions from first principles before committing. Incremental "patch the symptom" fixes are concerns.

Representative invariant-bearing classes: boundary conditions, type / unit / width conversions, numerical computation, concurrency, state transitions, protocol or spec contracts, external API contracts, data persistence consistency, security / permission boundaries.

**N/A:** the change is a typo, stale comment, doc tweak, or other surface fix where the conclusion is self-evident from the diff.
