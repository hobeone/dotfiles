#!/usr/bin/env bash
# resolve-model.sh behavior against a fixture model list and a stub agy.
# Live `agy models` is never called here.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

script=skills-shared/model-check/scripts/resolve-model.sh
fx=tests/fixtures/resolve_model
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

# run_case DESC WANT_RC WANT_STDOUT REQUEST... — resolves against the fixture
# file; stdout is compared exactly, stderr kept for the message checks below.
run_case() {
	local desc=$1 want_rc=$2 want_out=$3 out rc
	shift 3
	out=$("$script" --models-file "$fx/models.tsv" "$@" 2>"$work/stderr")
	rc=$?
	[[ $rc -eq $want_rc ]] || err "$desc: exit $rc, want $want_rc"
	[[ $out == "$want_out" ]] || err "$desc: stdout '$out', want '$want_out'"
}

# --- exact id, display name -------------------------------------------------
run_case "exact id" 0 gemini-3.8-flash-high gemini-3.8-flash-high
run_case "display name of an available model" 0 gemini-3.8-flash-high "Gemini 3.8 Flash (High)"

# --- the two real-world unavailable cases -----------------------------------
run_case "pinned agy-review default" 3 gemini-3.8-flash-high gemini-3.7-flash-high
grep -q "model-check: 'gemini-3.7-flash-high' is not available on agy. Recommended: gemini-3.8-flash-high (Gemini 3.8 Flash (High))" "$work/stderr" \
	|| err "unavailable message wrong: $(cat "$work/stderr")"
grep -q 'Available: .*claude-opus-4-6-thinking' "$work/stderr" || err "message should list available models"
run_case "pr-watcher primary" 3 claude-opus-4-6-thinking opus-5.5-high
run_case "unavailable display name" 3 gemini-3.8-flash-high "Gemini 4 Argon (High)"

# --- auto:<family>-<tier>[-<effort>] ----------------------------------------
run_case "auto picks newest of tier" 0 gemini-3.8-flash-high auto:gemini-flash-high
run_case "auto pro" 0 gemini-3.1-pro-high auto:gemini-pro-high
run_case "auto never substitutes a missing tier" 3 gemini-3.8-flash-high auto:gemini-flash-lite

# --- listing failures -------------------------------------------------------
export STUB_LOG=$work/agy.log XDG_CACHE_HOME=$work/cache
: >"$STUB_LOG"

out=$(MODEL_CHECK_AGY=$fx/agy STUB_FAIL=1 "$script" gemini-3.8-flash-high 2>"$work/stderr")
rc=$?
[[ $rc -eq 4 && -z $out ]] || err "agy failing: exit $rc stdout '$out', want 4 and empty"
grep -q 'model-check:' "$work/stderr" || err "agy failing: stderr should explain"

out=$(MODEL_CHECK_AGY=$work/does-not-exist "$script" gemini-3.8-flash-high 2>/dev/null)
rc=$?
[[ $rc -eq 4 && -z $out ]] || err "agy missing: exit $rc stdout '$out', want 4 and empty"

out=$(MODEL_CHECK_AGY=$fx/agy STUB_EMPTY=1 "$script" gemini-3.8-flash-high 2>/dev/null)
rc=$?
[[ $rc -eq 4 && -z $out ]] || err "empty list: exit $rc stdout '$out', want 4 and empty"
[[ ! -e $work/cache/model-check/agy-models.tsv ]] || err "a failed/empty listing must not be cached"

# --- cache ------------------------------------------------------------------
: >"$STUB_LOG"
export MODEL_CHECK_AGY=$fx/agy
"$script" gemini-3.8-flash-high >/dev/null 2>&1
"$script" opus-5.5-high >/dev/null 2>&1
n=$(wc -l <"$STUB_LOG")
[[ $n -eq 1 ]] || err "cache hit re-invoked agy ($n calls, want 1)"
"$script" --refresh gemini-3.8-flash-high >/dev/null 2>&1
n=$(wc -l <"$STUB_LOG")
[[ $n -eq 2 ]] || err "--refresh did not re-invoke agy ($n calls, want 2)"
MODEL_CHECK_TTL=0 "$script" gemini-3.8-flash-high >/dev/null 2>&1
n=$(wc -l <"$STUB_LOG")
[[ $n -eq 3 ]] || err "expired cache did not re-invoke agy ($n calls, want 3)"
"$script" --models-file "$fx/models.tsv" gemini-3.8-flash-high >/dev/null 2>&1
n=$(wc -l <"$STUB_LOG")
[[ $n -eq 3 ]] || err "--models-file must not touch agy ($n calls, want 3)"
unset MODEL_CHECK_AGY

# --- --json -----------------------------------------------------------------
json=$("$script" --models-file "$fx/models.tsv" --json gemini-3.8-flash-high 2>/dev/null)
jq -e '.requested == "gemini-3.8-flash-high" and .available == true
       and .resolved == "gemini-3.8-flash-high" and .recommended == null
       and .display == "Gemini 3.8 Flash (High)" and (.reason | type == "string")' <<<"$json" >/dev/null \
	|| err "--json (available) shape wrong: $json"
json=$("$script" --models-file "$fx/models.tsv" --json opus-5.5-high 2>/dev/null)
rc=$?
[[ $rc -eq 3 ]] || err "--json unavailable should still exit 3 (got $rc)"
jq -e '.requested == "opus-5.5-high" and .available == false and .resolved == null
       and .recommended == "claude-opus-4-6-thinking"
       and .display == "Claude Opus 4.6 (Thinking)" and (.reason | length > 0)' <<<"$json" >/dev/null \
	|| err "--json (unavailable) shape wrong: $json"

# --- usage ------------------------------------------------------------------
"$script" >/dev/null 2>&1
[[ $? -eq 1 ]] || err "no request should exit 1"
"$script" --bogus x >/dev/null 2>&1
[[ $? -eq 1 ]] || err "unknown flag should exit 1"

((fail)) && exit 1
echo PASS
