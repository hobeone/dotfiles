#!/usr/bin/env bash
# Contract test for classify_completion() in pr-with-coderabbit-review.sh.
#
# Zero-framework harness (bash + jq only, matching test-review-skip-reason.sh):
# it sources the script for its function definitions, builds the two normalized
# API payloads classify_completion consumes ({statuses:[...]} / {check_runs:[...]})
# as jq fixtures, and asserts the normalized completion state it echoes:
#   success | failed | pending, as "<state>\t<description>".
#
# classify_completion is pure (no gh/network I/O) — coderabbit_completion_state
# does the fetching — so the whole contract is exercised offline from fixtures.
#
# The core regression this guards
# (https://github.com/ultimatile/development-skills/issues/93): a check-run-only install (no
# CodeRabbit commit status, review reported via the `CodeRabbit / Review` check
# run) must classify as terminal. A frozen status-only reconstruction of the
# pre-fix detector is asserted alongside to prove the check-run fixture is a
# genuine regression guard: the old status-only logic returns `pending` (the
# hang) on it, while classify_completion returns `success`.
#
# Run:
#   bash test-completion-state.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source brings in classify_completion without running the script's
# mode-selection / PR-creation logic (guarded by its BASH_SOURCE check).
# shellcheck source=/dev/null
source "$SCRIPT_DIR/pr-with-coderabbit-review.sh"

# --- Fixture builders -----------------------------------------------------
# The payload shapes mirror what coderabbit_completion_state reassembles from
# `gh api --paginate ... --jq '.<array>[]' | jq -s '{<array>: .}'`, so the
# fixtures test the same object classify_completion sees in production.
status_payload() { # <state> <description>
    jq -nc --arg s "$1" --arg d "$2" \
        '{statuses: [{context: "CodeRabbit", state: $s, description: $d}]}'
}
status_empty() { echo '{"statuses": []}'; }

check_payload() { # <status> <conclusion>  (empty conclusion -> null, as GitHub reports until completed)
    jq -nc --arg st "$1" --arg c "$2" \
        '{check_runs: [{name: "CodeRabbit / Review", status: $st,
                        conclusion: (if $c == "" then null else $c end),
                        app: {slug: "coderabbitai"}, id: 1000}]}'
}

# Two same-named CodeRabbit / Review runs in the newest-first array order the
# Checks API returns: the newest (higher id) is still in_progress; an older
# (lower id) completed successfully. Selecting by max_by(.id) must pick the
# newest -> pending. A positional `| last` would instead pick the stale older
# run and misreport success, so asserting `pending` here fails on that
# implementation and passes only on the id-ordered one.
check_two_reruns() {
    jq -nc '{check_runs: [
        {name: "CodeRabbit / Review", status: "in_progress", conclusion: null,
         app: {slug: "coderabbitai"}, id: 2002},
        {name: "CodeRabbit / Review", status: "completed", conclusion: "success",
         app: {slug: "coderabbitai"}, id: 1001}
    ]}'
}
check_empty() { echo '{"check_runs": []}'; }

# A check run from a different app / name (e.g. ordinary CI) — must NOT be read
# as CodeRabbit's review signal.
check_foreign() {
    jq -nc '{check_runs: [{name: "build", status: "completed",
                          conclusion: "success", app: {slug: "github-actions"}}]}'
}

# A second CodeRabbit-app check run whose name CONTAINS "review" but is NOT
# exactly "CodeRabbit / Review". The exact name match must reject it -> pending.
# The name deliberately contains "review" so this fixture discriminates the
# exact match from the earlier substring matcher: a `contains("review")` filter
# WOULD have matched this run and read its `success` conclusion, so asserting
# `pending` here fails on the substring implementation and passes only on the
# exact one — a genuine, non-tautological guard for the exact-match contract.
check_coderabbit_other() {
    jq -nc '{check_runs: [{name: "CodeRabbit / Incremental Review", status: "completed",
                          conclusion: "success", app: {slug: "coderabbitai"}}]}'
}

# Frozen reconstruction of the pre-fix STATUS-ONLY detector: it reads only the
# Statuses API and is blind to check runs. This is a FROZEN HISTORICAL ARTIFACT
# — do not update it to track classify_completion. It exists solely so the
# differential below shows the two diverge on the check-run-only fixture.
classify_status_only__pre_fix() { # <status_json>
    local st
    st=$(jq -r '[.statuses[] | select(.context == "CodeRabbit")] | first | .state // empty' <<<"$1")
    case "$st" in
        success) echo success ;;
        failure | error) echo failed ;;
        *) echo pending ;;
    esac
}

# Frozen reconstruction of the pre-exact-match check-run SELECTOR: it matched by
# the name substring `contains("review")` instead of the exact `CodeRabbit /
# Review`. FROZEN HISTORICAL ARTIFACT — do not update it to track
# classify_completion. It exists so the differential below shows the exact match
# rejects a review-named-but-not-exact run that the substring matcher accepted.
classify_checkrun_substring__pre_exact() { # <checks_json>
    local cr
    cr=$(jq -c '[.check_runs[] | select(.app.slug == "coderabbitai" and (.name | ascii_downcase | contains("review")))] | last' <<<"$1")
    if [[ -z "$cr" || "$cr" == "null" ]]; then
        echo pending
        return
    fi
    local s c
    s=$(jq -r '.status // empty' <<<"$cr")
    c=$(jq -r '.conclusion // empty' <<<"$cr")
    if [[ "$s" == "completed" ]]; then
        [[ "$c" == "success" ]] && echo success || echo failed
    else
        echo pending
    fi
}

# --- Assertion plumbing ---------------------------------------------------
fails=0

# Assert classify_completion's echoed <state> (the field before the tab).
assert_state() { # <label> <status_json> <checks_json> <want_state>
    local label="$1" sj="$2" cj="$3" want="$4"
    local out got
    out=$(classify_completion "$sj" "$cj")
    got=${out%%$'\t'*}
    if [[ "$got" == "$want" ]]; then
        printf 'ok   %-50s state=%s\n' "$label" "$got"
    else
        printf 'FAIL %-50s want=%s got=%s (raw=%q)\n' "$label" "$want" "$got" "$out"
        fails=$((fails + 1))
    fi
}

# Assert the full "<state>\t<description>" line, to lock the tab-delimited
# contract poll_for_review reads via `IFS=$'\t' read -r status_state status_desc`.
assert_line() { # <label> <status_json> <checks_json> <want_line>
    local label="$1" sj="$2" cj="$3" want="$4"
    local got
    got=$(classify_completion "$sj" "$cj")
    if [[ "$got" == "$want" ]]; then
        printf 'ok   %-50s line=%q\n' "$label" "$got"
    else
        printf 'FAIL %-50s want=%q got=%q\n' "$label" "$want" "$got"
        fails=$((fails + 1))
    fi
}

assert_status_only() { # <label> <status_json> <want>
    local label="$1" sj="$2" want="$3"
    local got
    got=$(classify_status_only__pre_fix "$sj")
    if [[ "$got" == "$want" ]]; then
        printf 'ok   %-50s state=%s\n' "$label" "$got"
    else
        printf 'FAIL %-50s want=%s got=%s\n' "$label" "$want" "$got"
        fails=$((fails + 1))
    fi
}

assert_checkrun_substring() { # <label> <checks_json> <want>
    local label="$1" cj="$2" want="$3"
    local got
    got=$(classify_checkrun_substring__pre_exact "$cj")
    if [[ "$got" == "$want" ]]; then
        printf 'ok   %-50s state=%s\n' "$label" "$got"
    else
        printf 'FAIL %-50s want=%s got=%s\n' "$label" "$want" "$got"
        fails=$((fails + 1))
    fi
}

# --- Commit-status install: the status drives classification --------------
assert_state "status success -> success" \
    "$(status_payload success 'Review completed')" "$(check_empty)" success
assert_state "status pending -> pending" \
    "$(status_payload pending 'Review in progress')" "$(check_empty)" pending
assert_state "status failure -> failed" \
    "$(status_payload failure 'Review failed')" "$(check_empty)" failed
assert_state "status error -> failed" \
    "$(status_payload error 'Review errored')" "$(check_empty)" failed

# Tab contract: the description passes through as the second field.
assert_line "status success -> success<TAB>desc" \
    "$(status_payload success 'Review completed')" "$(check_empty)" \
    "$(printf 'success\tReview completed')"

# --- Check-run-only install (the core regression) -------------------------
# No CodeRabbit commit status; the review lands as the CodeRabbit / Review
# check run. classify_completion must fall back to it and see a terminal state.
assert_state "check-run completed+success -> success" \
    "$(status_empty)" "$(check_payload completed success)" success
assert_state "check-run in_progress -> pending" \
    "$(status_empty)" "$(check_payload in_progress '')" pending
assert_state "check-run completed+failure -> failed" \
    "$(status_empty)" "$(check_payload completed failure)" failed
assert_state "check-run completed+timed_out -> failed" \
    "$(status_empty)" "$(check_payload completed timed_out)" failed

# --- Neither signal present -----------------------------------------------
assert_state "no status, no check run -> pending" \
    "$(status_empty)" "$(check_empty)" pending
assert_state "foreign check run only -> pending" \
    "$(status_empty)" "$(check_foreign)" pending
assert_state "coderabbit review-named non-exact run -> pending" \
    "$(status_empty)" "$(check_coderabbit_other)" pending

# --- Precedence: a present status wins over the check run -----------------
# On an install that posts a commit status, the status drives the poll even
# while pending — the check run is consulted ONLY when no CodeRabbit status
# context exists at all.
assert_state "status pending beats check success -> pending" \
    "$(status_payload pending 'Review in progress')" \
    "$(check_payload completed success)" pending

# Multiple same-named runs: the newest (by id) wins, not the last in array order.
assert_state "two review reruns -> newest (in_progress) -> pending" \
    "$(status_empty)" "$(check_two_reruns)" pending

# --- Non-tautology differential -------------------------------------------
# The check-run-only+success fixture is where the fix matters: the frozen
# status-only detector returns `pending` (would hang the poll forever), while
# classify_completion returns `success`. Asserting both directions proves the
# fixture guards the real regression rather than restating current behavior.
assert_status_only "differential: status-only pre-fix -> pending (hang)" \
    "$(status_empty)" pending
assert_state "differential: classify_completion -> success" \
    "$(status_empty)" "$(check_payload completed success)" success

# Second differential: the exact-name match vs the earlier substring matcher, on
# a review-named-but-not-exact CodeRabbit check run. The frozen substring
# selector accepts it and reports its `success` conclusion (the wrong terminal
# state); classify_completion's exact match rejects it -> pending. Asserting both
# directions proves the exact-match change is a genuine, non-tautological guard.
assert_checkrun_substring "differential: substring pre-exact -> success (wrong)" \
    "$(check_coderabbit_other)" success
assert_state "differential: exact classify_completion -> pending" \
    "$(status_empty)" "$(check_coderabbit_other)" pending

# --- Summary --------------------------------------------------------------
echo
if [[ "$fails" -eq 0 ]]; then
    echo "All checks passed."
    exit 0
fi
echo "$fails check(s) failed."
exit 1
