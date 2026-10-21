# Shell profile (bash, POSIX sh, zsh)

Claims marked "verified" were run on bash 5.2, dash, zsh or busybox ash on
Debian; unmarked ones are standard documented behaviour. Many behaviours differ
between shells, so first decide which shell the file targets: the shebang, the
file's own `set`/`shopt` lines, or the interpreter a workflow step or hook names.

## Detection

- Extensions `.sh`, `.bash`, `.zsh`, `.ksh`; dotfiles such as `.bashrc`, `.zshrc`, `.profile`.
- Shebangs `#!/bin/sh`, `#!/bin/bash`, `#!/usr/bin/env bash`, `#!/usr/bin/env sh`, `#!/usr/bin/env zsh`. Extensionless files in `bin/`, `scripts/` and git hooks (`.githooks/*`, `.git/hooks/*`) are identified by shebang.
- Shell embedded in other files: CI `run:` blocks, Makefile recipes, Dockerfile `RUN` lines, `package.json` scripts. Apply the profile to those lines; the target shell is whatever the runner uses (GitHub Actions `run:` without `shell:` is `bash -e {0}` on Linux and macOS runners, falling back to `sh` when bash is absent; it has no `pipefail` or `-u` unless `shell: bash` is set explicitly).
- Target-shell rule: a `#!/bin/sh` file must stay POSIX (on Debian and Ubuntu `/bin/sh` is dash). A `#!/bin/bash` file may use bash features. zsh files follow zsh rules (see the first Do not flag bullet).

## Do not flag

- **Unquoted expansion that is meant to word-split**, e.g. `for f in $files`, `cmd $flags`, where the variable is a script-controlled, whitespace-separated list (`flags="-a -b"` expands to two arguments unquoted, one argument quoted). Why: quoting would break the intended splitting. This stops being correct when the value can contain spaces, glob characters (`*`, `?`, `[`) or comes from outside the script; then the finding stands, because an unquoted `*.txt` expands to matching filenames.
- **Unquoted expansion in zsh files.** Why: zsh does not word-split unquoted parameters by default (`x="a b"; printf '[%s]' $x` prints `[a b]` in zsh, `[a][b]` in bash). Only flag when the file sets `setopt SH_WORD_SPLIT` or is sourced into a bash/sh context.
- **Unquoted variables where no word splitting or globbing happens:** the right side of a plain assignment (`x=$y`), the word after `case` (`case $y in`), and operands inside `[[ ... ]]` (`[[ $y == "a b" ]]`). Why: the shell skips splitting and pathname expansion in exactly these positions. `[ $y = ... ]` single-bracket is different and does break (`[: too many arguments`).
- **Unquoted right side of `==`, `!=` or `=~` inside `[[ ]]`**, e.g. `[[ $s == $pattern ]]`, `[[ $s =~ $re ]]`. Why: unquoted means pattern/regex on purpose; quoting turns it into a literal comparison (`[[ abc =~ "$re" ]]` with `re='^a.c$'` fails). Flag the quoted form only when the variable is meant to be a pattern.
- **Absence of `set -euo pipefail` in a file that is sourced** (`.zshrc`, `.bashrc`, `*.zsh` plugins, `lib.sh` helpers) **or interactive**. Why: options set in a sourced file change the caller's shell (verified: `set -e` in a sourced file makes the sourcing shell exit on its next failing command), so a library must not set them.
- **`${var:-}` and `${1:-}` with an empty default under `set -u`.** Why: it is the guard that lets an unset variable or missing argument through; `echo "$1"` with no argument aborts with `unbound variable` and `${1:-}` does not.
- **`cmd || true` and `cmd || :` under `set -e`.** Why: the `||` list makes a failure of `cmd` non-fatal on purpose. Flag it only if `cmd`'s failure is something the script then relies on having succeeded.
- **Single-quoted `trap` bodies that mention variables:** `trap 'rm -rf "$work"' EXIT`. Why: the variables are expanded when the trap fires, so a later reassignment is honoured (verified: `f=one; trap 'echo $f' EXIT; f=two` prints `two`). The double-quoted form expands at definition time (prints the old value) and is the one worth checking.
- **Variables that look unused but are consumed outside the file:** exported variables, ones read by a sourced file, an `eval`, or a child process. Why: a single-file scan cannot see those readers; check the sourcing and exporting sites before flagging.
- **`local` in `#!/bin/sh` scripts.** Why: it is not in POSIX, but dash, bash `--posix` and busybox ash all implement it (verified), so on the shells that provide `/bin/sh` today it works. Flag it only where the script claims strict POSIX or targets another shell.
- **`[ ]` instead of `[[ ]]` in bash scripts.** Why: both work in bash and `[ ]` is the only portable form; the reverse is a real bug (see Common bugs). Quoting inside `[ ]` is what matters.

## Common bugs

- **Unquoted expansion of data**: filenames, user input, command output, `$@`/`$*` where arguments are meant to stay separate (`rm -rf $dir/*` with an empty or space-containing `$dir`; `cp $src $dst`). Splits on whitespace and expands globs. Use `"$var"` and `"$@"`.
- **`[[`, `==` inside `[ ]`, arrays, `<<<`, `${v//a/b}`, `source`, `function f` in a `#!/bin/sh` script.** dash prints `[[: not found` and `[: a: unexpected operator` (verified). Check against the shebang, not against the author's interactive shell.
- **`set -e` blind spots.** `set -e` does not stop on: a failing command in the condition of `if`/`while`/`until`; the left side of `&&`/`||` (only the final command of an `&&` list can abort the script); a function called as `if f; then`, inside which `set -e` is effectively off for the whole body (verified: `f(){ false; echo continued; }; if f; then :; fi` prints `continued`); a command substitution in plain bash (verified: `x=$(false; echo hi)` leaves `x=hi` unless `shopt -s inherit_errexit`); any non-last stage of a pipeline unless `set -o pipefail`.
- **`(( n++ ))` / `(( count -= 1 ))` under `set -e` when the expression evaluates to 0.** The arithmetic command exits 1 for a zero result, so the script dies (verified: `n=0; (( n++ ))` under `set -e` exits). Use `n=$((n + 1))`.
- **`local x=$(cmd)`, `export x=$(cmd)`, `readonly x=$(cmd)`.** The exit status is the builtin's, so `cmd`'s failure is masked (verified: `local x=$(false)` returns 0, `local x; x=$(false)` returns 1). Declare, then assign.
- **`producer | grep -q pattern` under `pipefail`.** `grep -q` exits at the first match, the producer gets SIGPIPE, and the pipeline reports 141 (verified with `yes | grep -q y`: 141 every run). The pipeline fails although the match was found. Capture to a variable, or avoid `-q`.
- **Variables set inside `cmd | while read ...` are lost in bash, dash and busybox ash.** The loop runs in a subshell (verified: counter stays 0). zsh runs the last pipeline stage in the current shell (verified), and bash has `shopt -s lastpipe` for non-interactive scripts. Redirect with `< <(cmd)` or `<<<` instead.
- **`while read line`**: without `-r`, backslashes are mangled (`a\b` reads as `ab`); without `IFS=`, leading and trailing whitespace is stripped; a final line with no trailing newline is skipped (verified). Use `while IFS= read -r line || [[ -n $line ]]`.
- **`[ -n $x ]` / `[ -z $x ]` with an unquoted variable.** With `x` empty, `[ -n $x ]` becomes `[ -n ]`, which is true (verified). Quote it, or use `[[ ]]`.
- **`echo "$var"` in sh scripts where the value is data.** dash's `echo` interprets backslash escapes and treats a lone `-n` as an option (verified: `echo "a\nb"` prints two lines; `echo "-n"` prints nothing). Use `printf '%s\n' "$var"`.
- **Parsing `ls` output or iterating `$(ls)`** (breaks on spaces and newlines in names); **`find | xargs`** without `-print0`/`-0`; use `find ... -exec` or a glob.
- **User-controlled value used as an option**: `rm "$f"`, `grep "$pat" file`, `git checkout "$ref"` when the value can start with `-`. Add `--` (verified: `rm -- -f` works where `rm -f` is parsed as an option) or prefix with `./`.
- **`$(( ))`, `(( ))`, and `[[ $x -eq N ]]` evaluate their operands as arithmetic expressions in bash**, and an array-subscript form such as `a[$(cmd)]` runs `cmd` (verified in `$(( x + 1 ))` and `[[ $x -eq 0 ]]` with `x='a[$(echo INJECTED >&2)]'`). Single-bracket `[ "$x" -eq 0 ]` errors instead. Validate numeric input (`[[ $x =~ ^[0-9]+$ ]]`) before arithmetic on it.
- **`eval`, `sh -c "...$x..."`, `bash -c` with interpolated data, and `source "$path"` of a user-writable path** execute data as code.
- **Predictable temp files** (`/tmp/name.$$`, `> /tmp/out`): use `mktemp` and clean up with a `trap ... EXIT`.
- **GNU/BSD differences in scripts meant to run on macOS:** `sed -i` needs an explicit backup-suffix argument on BSD sed (`sed -i '' ...`), and BSD `grep` has no `-P` (both per the BSD tools' documentation; not run on this Linux machine). Check the script's stated platforms (this repo supports Debian, Arch, Fedora and macOS).
- **A missing `|| exit` / `|| return` after `cd`** when `set -e` is not on: the following commands run in the wrong directory.

## Trust boundaries

- Positional parameters, option values, and environment variables (`$1`, `$@`, `$EDITOR`, `$PATH`, `$IFS`). In a privileged context (`sudo`, a setuid wrapper, a service) the environment is attacker-influenced.
- Filenames: any byte except `/` and NUL, including spaces, newlines, leading `-`, and glob characters.
- Output of other commands (`git`, `ls`, `curl`, `jq`). Git ref names may contain `$`, `(`, `)`, `;`, backtick, `&` and `|` (verified: `git check-ref-format --branch 'a;b$(id)'` accepts it), so a branch name interpolated into a shell command line is code injection. Spaces and a leading `-` are rejected, which makes the quoted-argument case safe but not the unquoted or `eval` case.
- CI: `${{ github.event.* }}` expressions (PR title, branch, issue body, commit message) pasted into a `run:` block are substituted into the script text before the shell parses it, which is script injection. Pass them through `env:` and reference them as `"$VAR"`.
- Files read at run time and then executed or sourced (`.`, `source`, `eval "$(cat f)"`), downloaded scripts piped into a shell, and anything in world-writable directories such as `/tmp`.
- stdin and here-documents that carry user data: an unquoted heredoc delimiter (`<<EOF`) expands `$()` and backticks in the body, while `<<'EOF'` does not (verified).
