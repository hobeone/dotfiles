#!/usr/bin/env bash
# run-analyzers.sh against a throwaway git repo and stub tools (ANALYZER_BIN_DIR),
# so the result never depends on what is installed on the machine running it.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

script=$PWD/skills-shared/deep-pr-review/scripts/run-analyzers.sh
fx=$PWD/tests/fixtures/run_analyzers
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

# Built at runtime: a token-shaped literal must never be committed.
secret_val="AKIA""FAKEFAKEFAKE1234"
export STUB_SECRET=$secret_val STUB_LOG=$work/stub.log

# mkbin NAME TOOL... — an ANALYZER_BIN_DIR holding stubs for exactly TOOLs.
mkbin() {
  local d=$work/bin-$1 t
  shift
  rm -rf "$d"; mkdir -p "$d"
  for t in "$@"; do ln -s "$fx/bin/stub" "$d/$t"; done
  printf '%s' "$d"
}

repo=$work/repo
git init -q -b main "$repo"
git -C "$repo" config user.email t@example.test
git -C "$repo" config user.name t
git -C "$repo" config commit.gpgsign false
cd "$repo" || exit 1
# shellcheck disable=SC2016 # literal shell source, no expansion intended
printf '#!/usr/bin/env bash\nset -eu\nx=1\necho "$x"\nexit 0\n' > a.sh
printf '# readme\n' > README.md
git add -A && git commit -qm base
git checkout -q -b feature
# shellcheck disable=SC2016 # literal shell source, no expansion intended
printf 'y=2\necho $y\n' >> a.sh                      # a.sh lines 6-7 are the diff
printf '# readme\nmore\n' > README.md
printf 'import sys\nimport os\neval("1")\n' > app.py
printf 'package main\n\nfunc main() {\n\tx()\n}\n' > main.go
printf 'module x\n\ngo 1.22\n' > go.mod
git add -A && git commit -qm feature

# jq helpers over a result file.
tool_field() { jq -r --arg t "$2" ".tools[] | select(.tool == \$t) | .$3" "$1"; }

# --- Case 1: findings on changed lines kept, others counted outside_diff ----
bin=$(mkbin one shellcheck trufflehog ruff)
: > "$STUB_LOG"
ANALYZER_BIN_DIR=$bin "$script" --base main --head feature --out "$work/r1.json" >"$work/o1.txt" 2>"$work/e1.txt" \
  || err "case 1: exited non-zero: $(cat "$work/e1.txt")"
jq -e . "$work/r1.json" >/dev/null 2>&1 || err "case 1: --out file is not valid JSON"
[[ $(tool_field "$work/r1.json" shellcheck status) == ran ]] || err "case 1: shellcheck not 'ran'"
[[ $(tool_field "$work/r1.json" shellcheck findings) == 2 ]] || err "case 1: want 2 shellcheck findings on changed lines"
[[ $(tool_field "$work/r1.json" shellcheck outside_diff) == 1 ]] || err "case 1: want 1 shellcheck outside_diff"
[[ $(jq '[.findings[] | select(.tool == "shellcheck")] | map(.line) | sort' -c "$work/r1.json") == '[6,7]' ]] \
  || err "case 1: kept lines are not [6,7]"
jq -e '.findings[] | select(.tool == "shellcheck" and .line == 7) | .severity == "high" and .rule == "SC1072"' "$work/r1.json" >/dev/null \
  || err "case 1: shellcheck error not normalised to high / SC1072"
[[ $(tool_field "$work/r1.json" ruff findings) == 1 ]] || err "case 1: ruff finding (absolute filename) not kept"
jq -e '.findings[] | select(.tool == "ruff") | .file == "app.py"' "$work/r1.json" >/dev/null \
  || err "case 1: ruff filename not made repo-relative"

# --- applicability ----------------------------------------------------------
[[ $(tool_field "$work/r1.json" semgrep status) == not_installed ]] || err "case 1: semgrep (applicable, absent) not 'not_installed'"
[[ $(tool_field "$work/r1.json" golangci-lint status) == not_installed ]] || err "case 1: golangci-lint not 'not_installed'"
for t in hadolint actionlint; do
  [[ $(tool_field "$work/r1.json" "$t" status) == not_applicable ]] || err "case 1: $t not 'not_applicable'"
done

# go.mod is a dependency manifest, so osv-scanner applies and is a gap.
[[ $(tool_field "$work/r1.json" osv-scanner status) == not_installed ]] || err "case 1: osv-scanner (go.mod changed) not 'not_installed'"

# --- summary lines ----------------------------------------------------------
sum=$("$script" --summarize "$work/r1.json") || err "case 1: --summarize failed"
ran_line=$(grep -F '**Static analyzers run:**' <<<"$sum")
not_line=$(grep -F '**Static analyzers NOT run:**' <<<"$sum")
grep -qF 'shellcheck (' <<<"$ran_line" || err "case 1: ran line lacks shellcheck: $ran_line"
grep -qF '2 findings, 1 outside diff' <<<"$ran_line" || err "case 1: ran line lacks counts: $ran_line"
grep -qF 'semgrep — not installed (applies to 2 changed files)' <<<"$not_line" || err "case 1: NOT-run line lacks semgrep: $not_line"
grep -qF 'golangci-lint — not installed' <<<"$not_line" || err "case 1: NOT-run line lacks golangci-lint: $not_line"
for t in hadolint actionlint; do
  grep -qF "$t" <<<"$not_line" && err "case 1: not_applicable $t leaked into NOT-run line"
done

# --- secrets: engine named, matched value never printed ----------------------
[[ $(tool_field "$work/r1.json" secrets status) == ran ]] || err "case 1: secrets not 'ran'"
[[ $(tool_field "$work/r1.json" secrets engine) == trufflehog ]] || err "case 1: secrets engine not trufflehog"
[[ $(tool_field "$work/r1.json" secrets findings) == 1 ]] || err "case 1: want 1 secrets finding"
if grep -rqF "$secret_val" "$work/r1.json" "$work/o1.txt" "$work/e1.txt"; then err "case 1: trufflehog secret value leaked into output"; fi
if grep -qF "$secret_val" <<<"$sum"; then err "case 1: secret value leaked into summary"; fi
grep -qF -- '--no-verification' "$STUB_LOG" || err "case 1: trufflehog not run with --no-verification"

# gitleaks is the fallback engine, and also never leaks the value.
bin=$(mkbin gl gitleaks)
ANALYZER_BIN_DIR=$bin STUB_VERSION_GITLEAKS=8.21.0 "$script" --base main --head feature --out "$work/rg.json" >"$work/og.txt" 2>&1 \
  || err "gitleaks case: exited non-zero"
[[ $(tool_field "$work/rg.json" secrets engine) == gitleaks ]] || err "gitleaks case: engine not gitleaks"
[[ $(tool_field "$work/rg.json" secrets findings) == 1 ]] || err "gitleaks case: want 1 finding"
if grep -rqF "$secret_val" "$work/rg.json" "$work/og.txt"; then err "gitleaks case: secret value leaked"; fi

# --- semgrep severities (legacy ERROR/WARNING and newer HIGH/MEDIUM) and
# osv-scanner dependency findings, which are never line-filtered -----------------
bin=$(mkbin sg semgrep osv-scanner)
ANALYZER_BIN_DIR=$bin "$script" --base main --head feature --out "$work/rs.json" >/dev/null 2>&1 \
  || err "semgrep/osv case: exited non-zero"
[[ $(tool_field "$work/rs.json" semgrep status) == ran ]] || err "semgrep case: semgrep not 'ran'"
[[ $(jq -c '[.findings[] | select(.tool == "semgrep")] | sort_by(.line) | map(.severity)' "$work/rs.json") == '["high","medium","high"]' ]] \
  || err "semgrep case: severities not mapped (want lines 1-3 high,medium,high): $(jq -c '[.findings[] | select(.tool == "semgrep") | {line, severity}]' "$work/rs.json")"
# The fixture's lockfile path is not a changed line range at all; a
# line-filtered dependency finding would be dropped here.
[[ $(tool_field "$work/rs.json" osv-scanner findings) == 1 ]] || err "osv case: dependency finding was line-filtered away"
[[ $(tool_field "$work/rs.json" osv-scanner outside_diff) == 0 ]] || err "osv case: dependency finding counted outside_diff"

# --- failed: unexpected exit -------------------------------------------------
bin=$(mkbin fail shellcheck ruff)
STUB_EXIT_RUFF=2 ANALYZER_BIN_DIR=$bin "$script" --base main --head feature --out "$work/r2.json" >/dev/null 2>&1 \
  || err "failed case: a failing tool must not fail the run"
[[ $(tool_field "$work/r2.json" ruff status) == failed ]] || err "failed case: ruff not 'failed'"
[[ $(tool_field "$work/r2.json" shellcheck status) == ran ]] || err "failed case: shellcheck must still run"
sum=$("$script" --summarize "$work/r2.json")
grep -F '**Static analyzers NOT run:**' <<<"$sum" | grep -qF 'ruff — failed' \
  || err "failed case: NOT-run line lacks 'ruff — failed': $sum"

# --- --all-lines -------------------------------------------------------------
bin=$(mkbin all shellcheck)
ANALYZER_BIN_DIR=$bin "$script" --base main --head feature --all-lines --out "$work/r3.json" >/dev/null 2>&1 || err "all-lines: failed"
[[ $(tool_field "$work/r3.json" shellcheck findings) == 3 ]] || err "all-lines: want 3 findings"
[[ $(tool_field "$work/r3.json" shellcheck outside_diff) == 0 ]] || err "all-lines: want 0 outside_diff"

# --- absence never fails; every applicable tool is flagged --------------------
bin=$(mkbin none)
ANALYZER_BIN_DIR=$bin "$script" --base main --head feature --out "$work/r4.json" >/dev/null 2>&1 || err "no tools: run failed"
[[ $(jq '[.tools[] | select(.status == "not_installed")] | length' "$work/r4.json") -ge 4 ]] \
  || err "no tools: applicable tools not all flagged not_installed"
[[ $(jq '.findings | length' "$work/r4.json") == 0 ]] || err "no tools: findings should be empty"

# --- golangci-lint v1 / v2 flag selection --------------------------------------
bin=$(mkbin go golangci-lint)
: > "$STUB_LOG"
STUB_VERSION_GOLANGCI_LINT="golangci-lint has version 2.1.6 built with go1.24" ANALYZER_BIN_DIR=$bin \
  "$script" --base main --head feature --out "$work/r5.json" >/dev/null 2>&1 || err "golangci v2: run failed"
grep -qF -- '--output.json.path' "$STUB_LOG" || err "golangci v2: v2 json flag not used: $(cat "$STUB_LOG")"
[[ $(tool_field "$work/r5.json" golangci-lint findings) == 1 ]] || err "golangci v2: want 1 finding"
: > "$STUB_LOG"
STUB_VERSION_GOLANGCI_LINT="golangci-lint has version 1.64.8 built with go1.24" ANALYZER_BIN_DIR=$bin \
  "$script" --base main --head feature --out "$work/r6.json" >/dev/null 2>&1 || err "golangci v1: run failed"
grep -qF -- '--out-format' "$STUB_LOG" || err "golangci v1: v1 json flag not used"
[[ $(tool_field "$work/r6.json" golangci-lint findings) == 1 ]] || err "golangci v1: want 1 finding"

# --- --head != HEAD uses a temp worktree and leaves none behind ---------------
git checkout -q main
before=$(git worktree list)
bin=$(mkbin wt shellcheck)
: > "$STUB_LOG"
ANALYZER_BIN_DIR=$bin "$script" --base main --head feature --out "$work/r7.json" >/dev/null 2>&1 || err "worktree case: run failed"
[[ $(git worktree list) == "$before" ]] || err "worktree case: git worktree list changed: $(git worktree list)"
grep -q "^shellcheck cwd=$repo " "$STUB_LOG" && err "worktree case: analysed the checked-out tree, not the head"
[[ $(tool_field "$work/r7.json" shellcheck findings) == 2 ]] || err "worktree case: want 2 findings"
git checkout -q feature

# --- working-tree mode: untracked files count, head is WORKTREE --------------------
printf '#!/bin/sh\necho hi\n' > new.sh
bin=$(mkbin wtm shellcheck)
ANALYZER_BIN_DIR=$bin "$script" --base main --out "$work/r8.json" >/dev/null 2>&1 || err "working-tree case: run failed"
[[ $(jq -r .head "$work/r8.json") == WORKTREE ]] || err "working-tree case: head is not WORKTREE"
[[ $(tool_field "$work/r8.json" shellcheck files) == 2 ]] || err "working-tree case: want 2 shell files (a.sh + untracked new.sh)"
rm -f new.sh

# --- usage / empty summary ---------------------------------------------------------
"$script" >/dev/null 2>&1 && err "no --base: should exit 1"
"$script" --base nosuchref >/dev/null 2>&1 && err "bad --base: should exit 1"
echo '{"base":"x","head":"y","tools":[],"findings":[]}' > "$work/empty.json"
sum=$("$script" --summarize "$work/empty.json")
[[ $(grep -c ': none\|:\*\* none' <<<"$sum") == 2 ]] || err "empty summary: want 'none' on both lines: $sum"

((fail)) && exit 1
echo PASS
