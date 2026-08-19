#!/usr/bin/env bash
# Contract test for the commit-status skip discriminator in
# pr-with-coderabbit-review.sh.
#
# Why this exists as its own unit: review_skip_reason() infers a skip from HTML
# markers in bot comments, and not every skip emits one. A repository whose
# CodeRabbit plan or settings exclude automatic review announces the cause only
# in the commit-status description, so the marker checks return "no skip found"
# and the run is reported as a clean pass -- a false green on a review gate,
# turning "nobody looked" into "looked and found nothing". Observed on three
# separate PRs before it was diagnosed.
#
# The discriminator lives inline in poll_for_review, which does network I/O and
# cannot be unit-tested directly. What is testable, and what actually broke, is
# the pattern: this asserts it fires on the real skip descriptions and stays
# quiet on the real clean-pass ones, including strings chosen to be adjacent to
# both.
#
# Run:
#   bash test-status-skip.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/pr-with-coderabbit-review.sh"

# The pattern as poll_for_review applies it. Kept here as a single definition
# so a change to one side is visible as a diff against the other; the guard at
# the end asserts the two have not drifted apart.
STATUS_SKIP_PATTERN='review skipped'

status_is_skip() {
    grep -qiE "$STATUS_SKIP_PATTERN" <<<"$1"
}

fail=0
check() {
    local want="$1" desc="$2" label="$3" got=no
    status_is_skip "$desc" && got=yes
    if [[ "$got" == "$want" ]]; then
        printf 'ok   %-52s skip=%s\n' "$label" "$got"
    else
        printf 'FAIL %-52s skip=%s want=%s\n' "$label" "$got" "$want"
        fail=1
    fi
}

# Real skip descriptions. The first is the one that went undetected three times.
check yes "Review skipped: manual review required for this OSS repository" \
    "OSS manual-review skip (the observed miss)"
check yes "Review skipped" "bare skip"
check yes "review skipped due to max files limit" "file-limit skip"
check yes "REVIEW SKIPPED: paused" "case-insensitive"

# Real clean-pass and in-flight descriptions must not trip it. A gate that
# reports every run as skipped is as useless as one that reports none.
check no "Review completed" "clean pass"
check no "Review in progress" "in flight"
check no "Review queued" "queued"
check no "" "empty description"

# Adjacent strings: a description that merely mentions skipping something else
# must not read as a skipped review, or the gate cries wolf and gets ignored.
check no "Review completed — 3 files skipped by path filter" \
    "completed review that skipped some files"
check no "Skipped 2 of 40 files; review completed" "skipped files, review ran"

# Non-tautology guard: the assertions above would all pass against a pattern
# that matched nothing if the `yes` cases were dropped, and against one that
# matched everything if the `no` cases were. Prove the pattern discriminates by
# checking a deliberately broad alternative fails the suite's own no-cases --
# `skipped` alone is the obvious wrong fix and would misfire on path filters.
if grep -qiE 'skipped' <<<"Review completed — 3 files skipped by path filter"; then
    printf 'ok   %-52s\n' "broad 'skipped' pattern would misfire (guard)"
else
    printf 'FAIL %-52s\n' "guard did not reproduce the broad-pattern misfire"
    fail=1
fi

# Drift guard: the pattern above is a copy of the one in poll_for_review, so
# assert the production site still contains it. A test of a stale copy proves
# nothing about the shipped code.
if grep -qF "grep -qiE 'review skipped' <<<\"\$status_desc\"" \
    "$SCRIPT_DIR/pr-with-coderabbit-review.sh"; then
    printf 'ok   %-52s\n' "production site still uses this pattern"
else
    printf 'FAIL %-52s\n' "pattern drifted from poll_for_review"
    fail=1
fi

if [[ "$fail" -eq 0 ]]; then
    echo
    echo "All checks passed."
else
    echo
    echo "FAILURES above." >&2
fi
exit "$fail"
