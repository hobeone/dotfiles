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

# Fixture has 5 findings across 3 files (old.go deleted, a.go modified, b.go
# added): a.go:2 inline, a.go:40 orphan, a.go:3 degrades to single-line,
# b.go:2 inline, old.go:1 orphan (deleted file, never anchorable).
jq -e '.comments | length == 3' <<<"$payload" >/dev/null || err "want 3 inline comments"
jq -e '[.comments[] | select(.path == "a.go" and .line == 2)] | length == 1' <<<"$payload" >/dev/null \
  || err "a.go line 2 not inline"
jq -e '[.comments[] | select(.path == "b.go" and .line == 2)] | length == 1' <<<"$payload" >/dev/null \
  || err "b.go line 2 not inline"
# B1: the degrade filter must actually require a line-3 comment to exist, not
# just tolerate its absence — `[...][0]` on an empty array is `null`, and
# `null | has("start_line") | not` is true, so a payload with NO line-3
# comment at all vacuously "passes". Assert exactly one line-3 comment exists
# AND lacks start_line.
jq -e '[.comments[] | select(.line == 3)] | length == 1 and (.[0] | has("start_line") | not)' <<<"$payload" >/dev/null \
  || err "out-of-diff start_line did not degrade to single-line"
jq -e '[.comments[] | select(.line == 3)] | length == 1 and (.[0] | has("start_line") | not)' <<<'{"comments":[]}' >/dev/null \
  && err "degrade filter must not vacuously pass when no line-3 comment exists"
jq -e '.commit_id == "abc123" and .event == "COMMENT"' <<<"$payload" >/dev/null || err "commit_id/event wrong"

body=$(jq -r .body <<<"$payload")
grep -q 'a.go:40' <<<"$body" || err "a.go orphan finding missing from body"
grep -q 'old.go:1' <<<"$body" || err "deleted-file finding (old.go:1) missing from body"
[[ $(head -1 <<<"$body") == '<!-- deep-pr-review head:abc123 -->' ]] || err "head marker is not the first body line"
grep -qF '**Actionable comments posted: 3 inline + 2 in body**' <<<"$body" || err "count line wrong"

# G2 — format.md drift: body matches what the script actually emits.
# shellcheck disable=SC2016 # literal markdown backticks, no expansion intended
grep -qF '**Reviewed**: head `abc123`' <<<"$body" || err "missing 'Reviewed: head' line"
files_block=$(awk '/📒 Files selected for processing/,/<\/details>/' <<<"$body")
# shellcheck disable=SC2016 # literal markdown backticks, no expansion intended
grep -qF '* `a.go`' <<<"$files_block" || err "Files selected block missing a.go"
# shellcheck disable=SC2016 # literal markdown backticks, no expansion intended
grep -qF '* `b.go`' <<<"$files_block" || err "Files selected block missing b.go"
# shellcheck disable=SC2016 # literal markdown backticks, no expansion intended
grep -qF '* `old.go`' <<<"$files_block" || err "Files selected block missing old.go"

# Sequential Method wording.
out_seq=$("$script" 7 "$fx/findings.json" --repo o/r --sequential --dry-run 2>&1) || err "sequential dry run failed"
body_seq=$(jq -r .body <<<"$(awk 'f; /^## Review payload$/ {f=1}' <<<"$out_seq")")
grep -q 'fanned out to concurrent subagents' <<<"$body" || err "default body missing fan-out wording"
grep -q 'sequentially in a' <<<"$body_seq" || err "--sequential body missing sequential wording"

# A finding with a 2-element sites array: Affects block and "(this comment)".
out_sites=$("$script" 7 "$fx/findings-sites.json" --repo o/r --dry-run 2>&1) || err "sites dry run failed"
payload_sites=$(awk 'f; /^## Review payload$/ {f=1}' <<<"$out_sites")
comment_sites=$(jq -r '.comments[0].body' <<<"$payload_sites")
grep -qF '<summary>📍 Affects 2 files</summary>' <<<"$comment_sites" || err "missing Affects 2 files summary"
grep -qF '(this comment)' <<<"$comment_sites" || err "missing (this comment) marker on first site"

# --walkthrough, dry run: walkthrough section precedes the review payload.
out_wt=$("$script" 7 "$fx/findings.json" --repo o/r --walkthrough "$fx/walkthrough.md" --dry-run 2>&1) \
  || err "walkthrough dry run failed"
wt_line=$(grep -n '^## Walkthrough comment$' <<<"$out_wt" | cut -d: -f1)
payload_line=$(grep -n '^## Review payload$' <<<"$out_wt" | cut -d: -f1)
[[ -n $wt_line && -n $payload_line && $wt_line -lt $payload_line ]] \
  || err "walkthrough comment section does not precede review payload"

# --walkthrough, real post: issues/7/comments must be logged before pulls/7/reviews.
: > "$STUB_LOG"
"$script" 7 "$fx/findings.json" --repo o/r --walkthrough "$fx/walkthrough.md" >/dev/null 2>&1 \
  || err "walkthrough post failed"
comments_ln=$(grep -n 'issues/7/comments' "$STUB_LOG" | head -1 | cut -d: -f1)
reviews_ln=$(grep -n 'pulls/7/reviews' "$STUB_LOG" | head -1 | cut -d: -f1)
[[ -n $comments_ln && -n $reviews_ln && $comments_ln -lt $reviews_ln ]] \
  || err "walkthrough comment not posted before the review"

# G3b — truncation guard: a diff missing a PR-listed file refuses to post.
: > "$STUB_LOG"
if out=$(STUB_DIFF="$fx/diff-truncated.txt" "$script" 7 "$fx/findings.json" --repo o/r --dry-run 2>&1); then
  err "truncated diff exited 0"
fi
grep -qF 'diff is missing 1 PR file(s) (b.go); refusing to post — re-run' <<<"$out" \
  || err "missing truncation-guard message: $out"
if grep -q '/reviews\|/comments' "$STUB_LOG"; then err "truncated diff posted despite guard"; fi

# G3c — half-posted state: review POST fails after the walkthrough succeeded.
: > "$STUB_LOG"
if out=$(STUB_FAIL_REVIEW=1 "$script" 7 "$fx/findings.json" --repo o/r --walkthrough "$fx/walkthrough.md" 2>&1); then
  err "forced review failure exited 0"
fi
grep -qF 'walkthrough already posted at https://example.test/comment; review NOT posted — fix the error and re-run WITHOUT --walkthrough' \
  <<<"$out" || err "missing half-posted-state message: $out"
grep -q 'issues/7/comments' "$STUB_LOG" || err "walkthrough comment call was not made"

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

# G4 — remaining untested paths.
echo '{not json' > "$work/bad.json"
if out=$("$script" 7 "$work/bad.json" --repo o/r --dry-run 2>&1); then err "invalid JSON exited 0"; fi

echo '{}' > "$work/obj.json"
if out=$("$script" 7 "$work/obj.json" --repo o/r --dry-run 2>&1); then
  err "'{}' findings exited 0"
fi
grep -qF 'must contain a JSON array' <<<"$out" || err "'{}' findings missing 'must contain a JSON array': $out"

if out=$("$script" abc "$fx/findings.json" --repo o/r --dry-run 2>&1); then err "non-numeric pr exited 0"; fi
grep -qF 'must be numeric' <<<"$out" || err "non-numeric pr missing 'must be numeric': $out"

echo '[]' > "$work/empty.json"
out=$("$script" 7 "$work/empty.json" --repo o/r --dry-run 2>&1) || err "empty findings dry run exited non-zero: $out"
grep -qF '**Actionable comments posted: 0 inline + 0 in body**' <<<"$out" \
  || err "empty findings count line wrong: $out"

# Running without --repo resolves it via `gh repo view`.
: > "$STUB_LOG"
"$script" 7 "$fx/findings.json" --dry-run >/dev/null 2>&1 || err "no --repo dry run failed"
grep -q 'repo view --json nameWithOwner --jq .nameWithOwner' "$STUB_LOG" \
  || err "did not resolve repo via gh repo view"

# -h prints usage and exits 0.
out=$("$script" -h 2>&1); rc=$?
((rc == 0)) || err "-h exited $rc, want 0"
grep -q 'Usage:' <<<"$out" || err "-h did not print usage"

((fail)) && exit 1
echo PASS
