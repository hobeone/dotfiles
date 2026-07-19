# Architectural boundary integrity

If the project has an architectural rule about dependency direction or module boundaries — layered ordering, hexagonal / clean inward-pointing, a documented module DAG, a public / internal split — verify the diff respects it:

- New imports / `use` / `#include` cross a boundary in the disallowed direction.
- New package dep entry creates a disallowed edge.
- New `pub` / `export` widens access beyond what the rule allows.

**Concern conditions:**

- Diff introduces an import / dep edge contradicting the rule
- Public exposure widened beyond the rule

**N/A:** the project has no architectural rule, or the diff introduces no relevant imports / dep edges / public symbols.
