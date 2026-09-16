#!/usr/bin/env bash
# post-review.sh behavior against a stub gh: anchoring, head guard, count, marker.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

script=skills-shared/deep-pr-review/scripts/post-review.sh
fx=tests/fixtures/post_review
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export PATH="$PWD/$fx:$PATH" STUB_LOG=$work/gh.log STUB_DIFF=$fx/diff.txt STUB_HEAD=abc123
fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

# Dry run: extract the JSON payload after the "## Review payload" header.
out=$("$script" 7 "$fx/findings.json" --repo o/r --dry-run 2>&1) || err "dry run exited non-zero: $out"
payload=$(awk 'f; /^## Review payload$/ {f=1}' <<<"$out")

jq -e '.comments | length == 2' <<<"$payload" >/dev/null || err "want 2 inline comments"
jq -e '[.comments[] | select(.line == 2)] | length == 1' <<<"$payload" >/dev/null || err "line 2 not inline"
jq -e '[.comments[] | select(.line == 3)][0] | has("start_line") | not' <<<"$payload" >/dev/null \
  || err "out-of-diff start_line did not degrade to single-line"
jq -e '.commit_id == "abc123" and .event == "COMMENT"' <<<"$payload" >/dev/null || err "commit_id/event wrong"

body=$(jq -r .body <<<"$payload")
grep -q 'a.go:40' <<<"$body" || err "orphan finding missing from body"
[[ $(head -1 <<<"$body") == '<!-- deep-pr-review head:abc123 -->' ]] || err "head marker is not the first body line"
grep -qF '**Actionable comments posted: 2 inline + 1 in body**' <<<"$body" || err "count line wrong"

# Head guard: mismatch refuses and posts nothing.
: > "$STUB_LOG"
if out=$("$script" 7 "$fx/findings.json" --repo o/r --expect-head def456 2>&1); then
  err "expect-head mismatch exited 0"
fi
grep -qF 'PR head moved: expected def456, live abc123' <<<"$out" || err "missing head-moved message: $out"
if grep -q '/reviews\|/comments' "$STUB_LOG"; then err "posted despite head mismatch"; fi

# Head guard: match proceeds to post.
: > "$STUB_LOG"
"$script" 7 "$fx/findings.json" --repo o/r --expect-head abc123 >/dev/null 2>&1 || err "expect-head match failed"
grep -q 'pulls/7/reviews' "$STUB_LOG" || err "matching head did not post the review"

((fail)) && exit 1
echo PASS
