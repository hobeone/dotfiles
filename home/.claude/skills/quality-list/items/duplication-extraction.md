# Duplication extraction

When a diff adds the Nth (N ≥ 3 across the file or module) near-identical construct or block — inline fixture setup, repeated literal scaffolding, parallel branches differing only in a value — that an existing helper, or a trivially-extractable one (a function, a fixture factory, a table-driven loop, a parametrized test), could express, the duplication is the finding: propose the helper. The default disposition is **actionable**; it is not downgraded by appeal to the surrounding code, because neighboring duplication is unextracted debt, not a convention to match. The pre-existing copies are what make this the Nth occurrence — they are the trigger, not an exemption.

The rule of three (tolerate two occurrences; extract on the third) is the threshold heuristic this item rests on. Below three, abstracting risks the wrong abstraction — coupling code that only looks alike.

**Concern conditions:**

- A diff adds an Nth (N ≥ 3) near-identical construct or block that an existing or trivially-extractable helper could express.

**N/A:**

- Fewer than three near-identical instances exist.
- The constructs are only superficially similar, and no single helper cleanly expresses them without coupling unrelated code.
- The repetition is defensive-transformation replication repairing invalid producer output — that is `public-api-surface` Concern A's territory, where the fix is tightening the producer API rather than extracting a helper.
