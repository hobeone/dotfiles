#!/usr/bin/env bash
# Contract test for review_skip_reason() in pr-with-coderabbit-review.sh.
#
# Zero-framework harness: bash, jq, and grep only (the repo has no bash test
# framework, and this adds only enough to source and assert this one unit; jq
# builds the fixtures and runs the stubbed `gh` filter, grep is what the sourced
# production code and the frozen pre-fix artifact match with). It sources the
# script under test, stubs `gh` to run the real --jq filter over fixture comment
# arrays, and asserts review_skip_reason's contract:
#   0 = a skip signature was found (cause token echoed on stdout),
#   1 = fetched but no skip signature, 2 = fetch failed.
# The three cause tokens are `paused`, `rate-limited`, and `file-limit`.
#
# A frozen reconstruction of the pre-fix broad-grep pause detector is checked
# alongside the real assertions so the suite proves it guards the real
# regression, not just restates current behavior (see "non-tautology guard").
#
# Run:
#   bash test-review-skip-reason.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source brings in review_skip_reason + BOT_LOGIN without running the script's
# mode-selection / PR-creation logic (guarded by its BASH_SOURCE check).
# shellcheck source=/dev/null
source "$SCRIPT_DIR/pr-with-coderabbit-review.sh"

# review_skip_reason interpolates these into the gh api URL; the stub ignores the
# URL but they must be set so the call expands cleanly.
repo="owner/repo"
pr_number=1

# Reuse the sourced production constant so the fixture bot identity cannot drift
# from the login review_skip_reason actually filters on.
BOT="$BOT_LOGIN"

# Fixture state read by the gh stub. FIXTURE_JSON is a JSON array of issue
# comments; FIXTURE_FAIL=1 makes the stub fail like a network/jq error.
FIXTURE_JSON='[]'
FIXTURE_FAIL=0

# Stub `gh`: on failure return non-zero (drives review_skip_reason's `|| return 2`
# fail-closed path); otherwise extract the --jq filter and run the real jq over
# the fixture. Running the genuine filter exercises the bot-login selection and
# .body extraction the production call relies on, so the non-bot case is a real
# test of `select(.user.login == "$BOT_LOGIN")`, not a hand-waved one.
gh() {
    if [[ "$FIXTURE_FAIL" == "1" ]]; then
        return 1
    fi
    local filter=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --jq) filter="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    printf '%s' "$FIXTURE_JSON" | jq -r "$filter"
}

# Frozen reconstruction of the pre-fix broad-grep pause detector, taken from
# PR https://github.com/ultimatile/development-skills/pull/21 intermediate commit
# c1a7beba8 (before the HTML-marker fix). It matches
# bare "reviews paused" prose, which CodeRabbit's own walkthrough emits when
# describing the auto-pause feature — the false-positive class the fix removed.
# This is a FROZEN HISTORICAL ARTIFACT: do not update it to track the real
# function. It exists solely so the differential assertion below can show the
# real function diverges from it on the prose fixture.
review_is_paused__pre_fix_broad_grep() {
    local bodies
    bodies=$(
        gh api --paginate "repos/$repo/issues/$pr_number/comments?per_page=100" \
            --jq ".[] | select(.user.login == \"$BOT\") | .body" \
            2>/dev/null
    ) || return 2
    if grep -qiE 'review paused by coderabbit\.ai|reviews paused' <<<"$bodies"; then
        return 0
    fi
    return 1
}

# --- Assertion plumbing ---------------------------------------------------
fails=0

# Build a comments fixture from alternating "login body login body ..." args, so
# the comment-object shape the jq filter reads is defined in exactly one place.
comment_array() {
    jq -nc --args \
        '[range(0; ($ARGS.positional | length); 2) as $i
          | {user: {login: $ARGS.positional[$i]}, body: $ARGS.positional[$i + 1]}]' \
        "$@"
}

# Run the function under the SAME capture pattern production uses
# (`token=$(fn) || rc=$?` inside a `set -euo pipefail` shell) and check BOTH the
# return code and the echoed cause token. The command-substitution subshell sets
# strict mode itself so errexit is genuinely active inside fn — a bare
# `fn || rc=$?` would disable errexit within fn, so the test would not exercise
# the production strict-mode behavior. The 4th arg is optional: when omitted the
# token is not checked (used for the not-skipped / fetch-fail / pre-fix cases,
# which echo nothing).
assert_skip() {
    local label="$1" fn="$2" want_rc="$3" want_tok="${4-__NOCHECK__}"
    local got_rc=0 got_tok ok=1
    got_tok="$( set -euo pipefail; "$fn" )" || got_rc=$?
    [[ "$got_rc" == "$want_rc" ]] || ok=0
    if [[ "$want_tok" != "__NOCHECK__" && "$got_tok" != "$want_tok" ]]; then
        ok=0
    fi
    if [[ "$ok" == 1 ]]; then
        printf 'ok   %-46s rc=%s tok=%q\n' "$label" "$got_rc" "$got_tok"
    else
        printf 'FAIL %-46s want rc=%s tok=%s got rc=%s tok=%q\n' \
            "$label" "$want_rc" "$want_tok" "$got_rc" "$got_tok"
        fails=$((fails + 1))
    fi
}

# --- Fixtures -------------------------------------------------------------
# Genuine machine markers CodeRabbit emits on a non-review skip: HTML comments in
# the `<!-- ... by coderabbit.ai -->` family (pause, rate-limit).
#
# These fixtures necessarily embed the literal `<!-- ... coderabbit.ai -->`
# markers — a marker-detection test cannot assert a match without the marker in
# its input. So when THIS skill is itself changed and reviewed via the CodeRabbit
# pipeline, CodeRabbit's own walkthrough can quote these lines and self-trigger
# review_skip_reason. That is the known, repo-local self-reference risk
# (development-skills#21): review coderabbit-review changes with a non-CodeRabbit
# reviewer, not by obfuscating these fixtures.
PAUSE_MARKER='<!-- This is an auto-generated comment: review paused by coderabbit.ai -->'
RATE_LIMIT_MARKER='<!-- This is an auto-generated comment: rate limited by coderabbit.ai -->
> [!WARNING]
> ## Review limit reached'

# Genuine file-count skip comment: the `skip review by coderabbit.ai` marker
# (also used for intentional config skips) PLUS the `skipped due to max files
# limit` prose. review_skip_reason requires BOTH, so this triggers file-limit.
FILE_LIMIT_SKIP='<!-- This is an auto-generated comment: skip review by coderabbit.ai -->
> [!IMPORTANT]
> ## Review skipped
>
> More than 25% of the files skipped due to max files limit. The review is being skipped to prevent a low-quality review.'

# A genuine clean pass carries only the summarize marker and no skip signature.
CLEAN_SUMMARY='<!-- This is an auto-generated comment: summarize by coderabbit.ai -->
Walkthrough: summary of changes.'

# Bot walkthrough prose that mentions the auto-pause feature without the <!--
# wrapper. This fixture and the non-tautology guard MUST share this exact string:
# the differential only proves the regression if both implementations see it.
PAUSE_PROSE='CodeRabbit can keep reviews paused after N commits; the pause marker is documented here.'

# Rate-limit VISIBLE prose without the HTML marker — must not self-trigger,
# mirroring the pause-prose guard (the discriminator is the marker, not the words).
RATE_LIMIT_PROSE='> [!WARNING] Review limit reached. You have reached your PR review limit, so we could not start this review.'

# A benign mention of the file limit that is NOT the machine skip sentence:
# contains "max files limit" / "above the max files limit of 100" but not
# "skipped due to max files limit", so the anchored match must NOT fire.
FILE_LIMIT_BENIGN='You can raise the max files limit in plan settings; PRs above the max files limit of 100 get truncated.'

# The file-count skip PROSE without the `skip review by coderabbit.ai` marker —
# e.g. a bot walkthrough quoting the sentence. Because file-limit requires the
# marker AND the prose, this must NOT self-trigger (the parity guard for the
# marker-less prose match the two HTML-marker causes are already protected from).
FILE_LIMIT_PROSE_NO_MARKER='> [!IMPORTANT] Review skipped: more than 25% of the files skipped due to max files limit.'

# A deliberate config skip: the `skip review by coderabbit.ai` marker WITHOUT the
# file-count prose (CodeRabbit reuses the same marker for title-pattern / draft /
# path-filter skips). An intentional skip is not a false clean pass, so this must
# NOT be flagged — and this fixture is what would catch a regression that dropped
# the prose conjunct, reducing file-limit to a bare marker match.
FILE_LIMIT_MARKER_ONLY='<!-- This is an auto-generated comment: skip review by coderabbit.ai -->
> [!IMPORTANT]
> ## Review skipped
>
> Review skipped: the PR title matches a configured skip pattern.'

# --- Contract cases: genuine skip signatures -> correct token -------------
FIXTURE_FAIL=0
FIXTURE_JSON="$(comment_array "$BOT" "$PAUSE_MARKER")"
assert_skip "genuine pause marker -> paused" review_skip_reason 0 "paused"

FIXTURE_JSON="$(comment_array "$BOT" "$RATE_LIMIT_MARKER")"
assert_skip "genuine rate-limit marker -> rate-limited" review_skip_reason 0 "rate-limited"

FIXTURE_JSON="$(comment_array "$BOT" "$FILE_LIMIT_SKIP")"
assert_skip "genuine file-count skip -> file-limit" review_skip_reason 0 "file-limit"

# Marker on a later comment (a benign bot comment precedes it): asserts the
# matcher scans every fetched body, not just the first.
FIXTURE_JSON="$(comment_array "$BOT" "$CLEAN_SUMMARY" "$BOT" "$RATE_LIMIT_MARKER")"
assert_skip "marker on later comment -> rate-limited" review_skip_reason 0 "rate-limited"

# --- Contract cases: no skip signature -> not skipped ---------------------
# Genuine clean pass (summarize marker only) is NOT a skip.
FIXTURE_JSON="$(comment_array "$BOT" "$CLEAN_SUMMARY")"
assert_skip "clean summarize only -> not skipped" review_skip_reason 1

# Pause prose without the <!-- wrapper (the regression the HTML-marker fix guards).
FIXTURE_JSON="$(comment_array "$BOT" "$PAUSE_PROSE")"
assert_skip "pause prose -> not skipped" review_skip_reason 1

# Rate-limit visible prose without the marker.
FIXTURE_JSON="$(comment_array "$BOT" "$RATE_LIMIT_PROSE")"
assert_skip "rate-limit prose -> not skipped" review_skip_reason 1

# A "max files" mention that is not the machine skip sentence.
FIXTURE_JSON="$(comment_array "$BOT" "$FILE_LIMIT_BENIGN")"
assert_skip "benign max-files mention -> not skipped" review_skip_reason 1

# File-count prose WITHOUT the skip-review marker (e.g. a walkthrough quoting it).
FIXTURE_JSON="$(comment_array "$BOT" "$FILE_LIMIT_PROSE_NO_MARKER")"
assert_skip "file-count prose, no marker -> not skipped" review_skip_reason 1

# Deliberate config skip: skip-review marker but no file-count prose -> not flagged.
FIXTURE_JSON="$(comment_array "$BOT" "$FILE_LIMIT_MARKER_ONLY")"
assert_skip "config skip (marker, no prose) -> not skipped" review_skip_reason 1

# Cross-comment: the marker in ONE comment and the prose in a SEPARATE comment must
# NOT combine — the co-requirement is per-comment (config skip + a walkthrough that
# quotes the file-count sentence should stay a non-flagged pass).
FIXTURE_JSON="$(comment_array "$BOT" "$FILE_LIMIT_MARKER_ONLY" "$BOT" "$FILE_LIMIT_PROSE_NO_MARKER")"
assert_skip "marker + prose in different comments -> not skipped" review_skip_reason 1

# Non-bot comment containing a marker -> not skipped (bot-login filter drops it
# before the body is ever grepped).
FIXTURE_JSON="$(comment_array "some-human" "$RATE_LIMIT_MARKER")"
assert_skip "non-bot marker -> not skipped" review_skip_reason 1

# Comment fetch failure -> unverifiable (fail closed).
FIXTURE_FAIL=1
FIXTURE_JSON='[]'
assert_skip "fetch failure -> unverifiable" review_skip_reason 2

# --- Non-tautology guard --------------------------------------------------
# The pause-prose fixture is where the real and pre-fix implementations diverge:
# the broad-grep version reports it as paused (0), the fixed function does not
# (1, no token). Asserting both directions proves the prose case is a genuine
# regression guard rather than a restatement of current behavior.
FIXTURE_FAIL=0
FIXTURE_JSON="$(comment_array "$BOT" "$PAUSE_PROSE")"
assert_skip "prose: pre-fix broad-grep -> paused"    review_is_paused__pre_fix_broad_grep 0
assert_skip "prose: fixed function -> not skipped"   review_skip_reason 1

# --- Summary --------------------------------------------------------------
echo
if [[ "$fails" -eq 0 ]]; then
    echo "All checks passed."
    exit 0
fi
echo "$fails check(s) failed."
exit 1
