# Completion hygiene

Project-standard format / lint / type-check / build commands ran clean against the diff. Use the project's actual commands; examples:

- Rust: `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`, `cargo build`
- C / C++: `clang-tidy`, `clang-format --dry-run -Werror`, build clean
- Python: `ruff check`, `ruff format --check` (or `black --check`), `mypy`
- TypeScript / JavaScript: `tsc --noEmit`, `eslint`, `prettier --check`

Debug-only artifacts removed: `dbg!`, trace `println!` / `print(...)` / `console.log`, commented-out code, scratch files.

**Pre-commit constraint response.** When a pre-commit hook rejects the commit due to a per-file size or line-count threshold, the correct response is **file split first, content trim only when the trimmed text is genuinely redundant** — repeated boilerplate, overlong heredocs, copy-pasted scaffolding. Removing load-bearing docstrings, comments, structural code, or test cases just to slip under the threshold is a concern. It converts a structural violation (the unit is too large) into silent information loss (the documentation that would have explained the unit is gone).

**Concern conditions:**

- Lint / format / type-check / build commands were not run, or they reported issues
- Debug-only output left in the diff
- Pre-commit hook size / line-count rejection was resolved by trimming load-bearing content (docstrings, comments, structural code, test cases) instead of by splitting the unit

**N/A:** documentation-only changes with no code touched.
