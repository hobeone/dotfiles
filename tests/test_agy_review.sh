#!/usr/bin/env bash
# agy-review.sh model handling against a stub agy: an unavailable model must
# stop the run (exit 4) before agy is ever invoked, never be swapped silently.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

script=$PWD/home/.claude/skills/agy-adversarial-review/scripts/agy-review.sh
fx=$PWD/tests/fixtures/agy_review
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export PATH="$fx:$PATH" STUB_LOG=$work/agy.log XDG_CACHE_HOME=$work/cache
fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

repo=$work/repo
git init -q "$repo"
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
echo "/adversarial-review" >"$work/prompt.txt"

# review DESC WANT_RC WANT_RUNS [ARGS...] — WANT_RUNS is how many times the
# stub's review run (the non -models call) must have been logged.
review() {
	local desc=$1 want_rc=$2 want_runs=$3 rc runs
	shift 3
	: >"$STUB_LOG"
	"$script" --prompt "$work/prompt.txt" --out "$work/out.md" --repo "$repo" "$@" 2>"$work/stderr" >/dev/null
	rc=$?
	runs=$(wc -l <"$STUB_LOG")
	[[ $rc -eq $want_rc ]] || err "$desc: exit $rc, want $want_rc ($(tail -3 "$work/stderr"))"
	[[ $runs -eq $want_runs ]] || err "$desc: agy review ran $runs times, want $want_runs"
}

# Default model is auto:gemini-flash-high, resolved to a real id before use.
review "default model" 0 1
grep -q -- '--model gemini-3.8-flash-high ' "$STUB_LOG" || err "default: agy not given the resolved id: $(cat "$STUB_LOG")"

# An explicit model that is not offered: exit 4 with the recommendation, and
# agy is never run.
review "unavailable explicit model" 4 0 --model gemini-3.7-flash-high
grep -q 'Recommended: gemini-3.8-flash-high' "$work/stderr" || err "unavailable: recommendation missing: $(cat "$work/stderr")"

# An available explicit model passes through untouched.
review "available explicit model" 0 1 --model gemini-3.1-pro-high
grep -q -- '--model gemini-3.1-pro-high ' "$STUB_LOG" || err "explicit: wrong model passed: $(cat "$STUB_LOG")"

# auto cannot resolve (no such tier) -> 4 as well.
review "auto with no match" 4 0 --model auto:gemini-flash-lite

# Listing failure -> 4: availability is unknown, so do not guess. A fresh cache
# dir forces the listing to be re-fetched.
XDG_CACHE_HOME=$work/cache-empty STUB_MODELS_FAIL=1 review "agy models failing" 4 0
grep -q 'cannot list models' "$work/stderr" || err "listing failure: stderr should say so: $(cat "$work/stderr")"

# The claude-* refusal applies to the RESOLVED model: claude-sonnet-4-6 is
# available, and still refused.
review "claude-* resolved model" 1 0 --model claude-sonnet-4-6
grep -q 'refusing --model claude-sonnet-4-6' "$work/stderr" || err "claude refusal message missing: $(cat "$work/stderr")"
review "auto resolving to claude-*" 1 0 --model auto:claude-sonnet

# Resolution comes before any git check: an unavailable model reports 4 even
# when --repo is not a repository.
: >"$STUB_LOG"
"$script" --prompt "$work/prompt.txt" --out "$work/out.md" --repo "$work" --model gemini-3.7-flash-high 2>/dev/null
rc=$?
[[ $rc -eq 4 ]] || err "model check should precede git checks (exit $rc, want 4)"

((fail)) && exit 1
echo PASS
