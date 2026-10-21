# Language addenda for Shell

This file extends `SKILL.md` with shell-specific triggers, mitigation idioms, and mechanical detection patterns. The audit (`done-check`) and preflight (`todo-check`) skills auto-load this file when the project declares `Language: Shell` in its `CLAUDE.md`/`AGENTS.md`, or when the diff touches `.sh`/`.bash`/`.zsh` files or files with a `sh`/`bash`/`zsh` shebang.

This file does **not** introduce new audit items. Items live in `items/<slug>.md` and are language-neutral. Each section below corresponds to an existing item slug and provides the shell realization: what to grep for, what semantics apply, what idioms remediate the concern. A section realizes an item; it never bounds it, so a diff outside these constructs is still subject to the base item.

First decide the target shell from the shebang (`#!/bin/sh` means POSIX; on Debian and Ubuntu that is dash), because quoting, `[[ ]]`, arrays and `local` behave differently across bash, dash and zsh. For what looks like a bug but is correct in shell, and for the bugs worth hunting, see `deep-pr-review`'s `reference/lang/shell.md`.

______________________________________________________________________

## `implementation-guards`

### Triggers (Shell)

- **An executable script (not a sourced library, not an interactive rc file) with no `set -e` / `set -u` / `set -o pipefail` line**, or with one that does not apply to the construct it is meant to protect. Sourced files must not set them, because they change the caller's shell.
- **A required argument or variable used without a guard.** `$1`, `$HOME_DIR`, or a path built from them used under `set -u` with no default, or without `${1:?message}` to fail early with a message. `rm -rf "$dir/"*` with `dir` possibly empty is the dangerous case.
- **Validation after the dangerous operation.** A `cd`, `rm`, `mv` or `git` call that consumes an argument before the `case`/`[[ ]]` that checks it.
- **`cd dir` with no `|| exit` / `|| return`** when `set -e` is not active.
- **Sibling asymmetry.** One option parser branch, function or sub-command validates its argument and a parallel one does not.
- **Numeric input used in `$(( ))`, `(( ))` or `[[ -eq ]]` without checking it is a number.** Bash evaluates the operand as an expression, so a crafted value can run a command.

### Mechanical detection

```sh
git diff <base>..HEAD --name-only | rg '\.(sh|bash|zsh)$'        # plus extensionless scripts: check the first line for a shebang
rg -n '^set -[a-z]+|^set -o ' <file>                              # which safety options does the script enable
rg -n '\$\{?[1-9@*]' <file>                                       # positional parameters used: guarded before use?
rg -n '\bcd\b' <file>                                             # each cd needs "|| exit" unless set -e is on
```

### False-positive review

A library file that is only ever sourced, an interactive rc file, and a one-line wrapper that `exec`s another program need no `set` line. `[ ]` is correct in a `#!/bin/sh` script and `[[ ]]` is the bug there.

______________________________________________________________________

## `escape-hatch-necessity`

### Triggers (Shell)

- **`# shellcheck disable=SCxxxx` with no reason.** Say why the rule does not apply (for example "intentional word splitting of a trusted flag list"); a bare disable hides the next real instance too.
- **`|| true` / `|| :` appended to a command whose failure matters,** and `2>/dev/null` or `>/dev/null 2>&1` over a command whose error output is the only diagnostic.
- **`eval`, `bash -c "...$var..."`, `sh -c` with interpolation, or `source "$var"`** where a direct call with an argument array or a `case` dispatch would work.
- **`set +e` / `set +o pipefail` around a block** without a comment on what is tolerated, or without `set -e` restored afterwards.
- **`-f`/`--force`, `--no-verify`, `--yes`** added to make a command stop complaining instead of fixing what it complained about.

### Mechanical detection

```sh
rg -n '#\s*shellcheck disable=' <file>        # confirm each carries a reason
rg -n '\|\|\s*(true|:)\b|2>\s*/dev/null' <file>
rg -n '\beval\b|\b(ba)?sh -c\b|\bsource\b|^\s*\. ' <file>
rg -n 'set \+[eo]' <file>
```

### N/A

`|| true` after `grep -q`-style probes, `kill`/`rm -f` of a thing that may already be gone, and `command -v tool >/dev/null 2>&1` availability checks have an obvious reason that needs no comment. A shellcheck disable on a line that also states why is fine.

______________________________________________________________________

## `completion-hygiene`

### Triggers (Shell)

- `shellcheck` reporting anything new on the touched scripts, run with `-x` so sourced files are followed. Use the project's CI list of files and flags, not just the touched file, so a new script is added to that list.
- `bash -n file` (or `sh -n file` / `zsh -n file`, matching the shebang) failing.
- `shfmt -d` showing differences, where the project uses `shfmt`.
- A leftover `set -x`, `echo "DEBUG ..."`, or commented-out command block.
- The file mode: a new script that is meant to be run needs the executable bit (`git ls-files -s` shows `100755`).

### Mechanical detection

```sh
shellcheck -x <touched .sh files>
bash -n <file>            # or sh -n / zsh -n to match the shebang
shfmt -d <file>           # only if the project uses shfmt
rg -n '^\s*set -x|DEBUG|^\s*#\s*(rm|cp|mv|git|curl)\b' <file>
git ls-files -s <file>    # 100755 for scripts that are executed
```

______________________________________________________________________

## `behavior-coverage`

### Triggers (Shell)

- A new branch, option, or function in a script with no test that exercises it. Shell tests that matter run the script as a subprocess against a throwaway directory or repository (`mktemp -d`) and stubbed external commands on `PATH`, and assert on exit status and output.
- A test that only checks `--help` output or that the script exits 0, while the changed logic is the failure path.
- A new test that was never seen failing: revert the change or stub the mechanism out and confirm this test fails.

### False-positive review

Pure refactors of already-covered paths, and wrappers whose entire behaviour is one delegated command, do not need a new test. A test that sources the script and calls a function directly is fine when the script guards its `main` call (`[[ ${BASH_SOURCE[0]} == "$0" ]]`).

______________________________________________________________________

## `paired-artifact-drift`

### Triggers (Shell)

- **Usage text vs parser.** The header comment, `usage()` output or `--help` text mentions a flag, argument or exit code that the `case` parser or the code no longer matches, or lacks one it added.
- **Header comment vs behaviour.** A comment above a function saying "does not modify X", "requires Y" or "prints Z" that the new body contradicts.
- **Script list vs the places that enumerate scripts.** A new or renamed script that is missing from the CI shellcheck step, the test step, an install or package list, or a README table; a deleted one still listed.
- **Documented environment variables** that the script no longer reads or newly reads.

### Mechanical detection

```sh
rg -n -- '--[a-z][a-z-]+' <file>              # flags named in comments/usage vs the case parser
rg -n '<script-basename>' .github .githooks Makefile README* docs 2>/dev/null   # everywhere the script is listed
```

Read each usage block and header comment against the new code; this is not mechanically decidable past locating candidates.

______________________________________________________________________

## `signature-change-regression`

### Triggers (Shell)

- A function's positional parameters reordered, added or removed in a file that other scripts `source`, or a changed exit-status or stdout contract of a function that callers capture with `$(...)`.
- A changed command-line interface of a script that other scripts, hooks, CI steps, cron entries or documentation invoke: renamed or removed flag, new required argument, different exit codes.
- A changed environment variable name or default that child processes or callers rely on.

### Mechanical detection

```sh
rg -n '\b<function_name>\b' --glob '!<changed file>'      # every caller of the changed function
rg -n '<script-basename>' .github .githooks Makefile home 2>/dev/null   # every invoker of the changed script
```

A shell caller has no compiler to catch the mismatch: an old call with the arguments in the old order still runs and does the wrong thing, so check each caller by reading it.
