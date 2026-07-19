# Pattern audit

If a pattern was copied from existing code (sibling module, prior wrapper, parallel type), evaluate (a) whether the source pattern is itself correct, and (b) whether the source's context applies to the current usage. Inheriting a pattern's bugs OR misapplying a correct pattern to a different context are both concerns.

**Sequential → distributed / parallel transplant.** When the reused pattern is sequential logic mirrored into a distributed or parallel context — the per-item update runs on one owner and the result is then shared by `broadcast` / `allreduce` / `scatter` / owner-only write — sequential-equivalence is not sufficient evidence of safety. A branch that was harmless sequentially because an earlier iteration had already set the value can corrupt the collective when a single participant runs it in isolation. Ask: can any participant reach the collective carrying a sentinel, stale, or uninitialized value that the sequential original could never produce? The partial-update + aggregation combination — a value left unset on one participant's branch, then reduced or broadcast to all — is the sharp case.

**N/A:** no pattern was reused; the change is a fresh design.
