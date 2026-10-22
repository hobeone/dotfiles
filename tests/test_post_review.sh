#!/usr/bin/env bash
# post-review.sh behavior against a stub gh: anchoring, head guard, count, marker.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

script=skills-shared/deep-pr-review/scripts/post-review.sh
fx=tests/fixtures/post_review
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export PATH="$PWD/$fx:$PATH" STUB_LOG=$work/gh.log STUB_DIFF=$fx/diff.txt STUB_HEAD=abc123 STUB_CHANGED_FILES=3
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
[[ $(head -1 <<<"$body") =~ ^'<!-- deep-pr-review head:abc123 verdict:'[A-Z_]+' threads_open:'[0-9]+' -->'$ ]] \
  || err "head marker is not the first body line: $(head -1 <<<"$body")"

# The Eligibility "already reviewed" jq program in method.md must recognise
# the marker this script actually writes. Run the program from method.md
# itself (not a copy) against a dry-run body; the stub head needs >=7 hex
# chars to satisfy the marker's SHA pattern.
marker_prog=$(awk '/^  marker=\x27/ {f=1; sub(/^  marker=\x27/, "")} f {print} f && /\x27$/ {exit}' \
  skills-shared/deep-pr-review/method.md | sed '$ s/\x27$//')
[[ -n $marker_prog ]] || err "could not extract the marker jq program from method.md"
out_mk=$(STUB_HEAD=abc1234 "$script" 7 "$fx/findings.json" --repo o/r --dry-run 2>&1) || err "marker dry run failed"
body_mk=$(jq -r .body <<<"$(awk 'f; /^## Review payload$/ {f=1}' <<<"$out_mk")")
got_mk=$(jq -nr --arg b "$body_mk" "[{body: \$b, html_url: \"u\"}] | $marker_prog")
[[ $got_mk == 'abc1234 u' ]] || err "method.md marker program does not match post-review.sh's marker (got '$got_mk')"
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

# Static analyzers: without --analyzers the body says so (never silent); with
# it, the --summarize lines follow **Checks run** directly. Defaults for
# checks / not-verified are honest rather than claiming gates that never ran.
grep -qF '**Static analyzers:** not run for this review.' <<<"$body" || err "default body lacks the analyzers-not-run line"
grep -qF -- 'Pass 1 deterministic gates' <<<"$body" && err "default --checks still claims gates ran"
[[ $(grep -A1 -F '**Checks run:**' <<<"$body" | tail -1) == 'none recorded' ]] || err "default --checks is not 'none recorded'"
grep -qF '**Not verified:** not recorded' <<<"$body" || err "default --not-verified is not 'not recorded'"
out_an=$("$script" 7 "$fx/findings.json" --repo o/r --analyzers "$fx/analyzers.json" --dry-run 2>&1) || err "--analyzers dry run failed: $out_an"
body_an=$(jq -r .body <<<"$(awk 'f; /^## Review payload$/ {f=1}' <<<"$out_an")")
grep -qF '**Static analyzers run:** shellcheck (3 files, 2 findings, 5 outside diff)' <<<"$body_an" || err "--analyzers body lacks the ran line"
grep -qF '**Static analyzers NOT run:** semgrep — not installed (applies to 4 changed files)' <<<"$body_an" || err "--analyzers body lacks the NOT-run line"
grep -qF 'not run for this review' <<<"$body_an" && err "--analyzers body still has the not-run default"
# The coverage table survives into the body intact: rows contiguous, no blank
# line splitting the table into paragraphs.
grep -qF '<summary>🔍 Static analyzer coverage: ' <<<"$body_an" || err "--analyzers body lacks the coverage block"
grep -qxF '| semgrep | — | ⚠️ not installed: 4 changed files unchecked | rule-based security and bug patterns in source code |' <<<"$body_an" \
  || err "--analyzers body lacks the semgrep coverage row"
[[ $(grep -A4 -xF '| Analyzer | Version | This diff | What it checks |' <<<"$body_an" | grep -c '^|') == 5 ]] \
  || err "--analyzers coverage table rows are not contiguous"
checks_ln=$(grep -n '^\*\*Checks run:\*\*' <<<"$body_an" | cut -d: -f1)
ran_ln=$(grep -n '^\*\*Static analyzers run:' <<<"$body_an" | cut -d: -f1)
nv_ln=$(grep -n '^\*\*Not verified:' <<<"$body_an" | cut -d: -f1)
[[ -n $checks_ln && -n $ran_ln && -n $nv_ln && $checks_ln -lt $ran_ln && $ran_ln -lt $nv_ln ]] \
  || err "analyzer lines are not placed between Checks run and Not verified"
if out=$("$script" 7 "$fx/findings.json" --repo o/r --analyzers "$work/missing.json" --dry-run 2>&1); then err "unreadable --analyzers exited 0"; fi

# --angles: the Method line states how many angles ran out of how many exist,
# the tier, and each skipped angle with its reason. The total comes from the
# angles file, never from a constant in the script; here it must equal the
# number of angle headings in method.md when the file is real select-angles
# output.
heading_n=$(grep -c '^### Angle [A-Z] — ' skills-shared/deep-pr-review/method.md)
out_ag=$("$script" 7 "$fx/findings.json" --repo o/r --angles "$fx/angles.json" --dry-run 2>&1) || err "--angles dry run failed: $out_ag"
body_ag=$(jq -r .body <<<"$(awk 'f; /^## Review payload$/ {f=1}' <<<"$out_ag")")
grep -qF '**Method**: ran 7 of 9 angles (tier: tiny)' <<<"$body_ag" || err "--angles Method line wrong: $(grep -F '**Method**' <<<"$body_ag")"
grep -qF '* F — tiny tier' <<<"$body_ag" || err "--angles body lacks skipped angle F with its reason"
grep -qF '* E — gate not met: no wrapper/proxy/decorator/adapter/cache/delegate in added lines' <<<"$body_ag" || err "--angles body lacks skipped angle E with its reason"
grep -qF '16-angle' <<<"$body_ag" && err "--angles body still quotes the all-angles wording"
grep -qF 'fanned out to concurrent subagents' <<<"$body_ag" || err "--angles body lost the fan-out wording"
out_agq=$("$script" 7 "$fx/findings.json" --repo o/r --angles "$fx/angles.json" --sequential --dry-run 2>&1) || err "--angles --sequential dry run failed"
body_agq=$(jq -r .body <<<"$(awk 'f; /^## Review payload$/ {f=1}' <<<"$out_agq")")
grep -qF 'ran 7 of 9 angles (tier: tiny)' <<<"$body_agq" || err "--angles --sequential Method line wrong: $(grep -F '**Method**' <<<"$body_agq")"
grep -q 'sequentially in a' <<<"$body_agq" || err "--angles --sequential body lacks the sequential wording"
# Real select-angles output: the total in the Method line is the heading count.
"$PWD/skills-shared/deep-pr-review/scripts/select-angles.sh" --diff "$fx/diff.txt" > "$work/real-angles.json" || err "select-angles.sh failed on the fixture diff"
out_ar=$("$script" 7 "$fx/findings.json" --repo o/r --angles "$work/real-angles.json" --dry-run 2>&1) || err "real --angles dry run failed"
body_ar=$(jq -r .body <<<"$(awk 'f; /^## Review payload$/ {f=1}' <<<"$out_ar")")
ran_n=$(jq '.angles | length' "$work/real-angles.json")
grep -qF "**Method**: ran $ran_n of $heading_n angles (tier: $(jq -r .tier "$work/real-angles.json"))" <<<"$body_ar" \
  || err "real --angles Method total is not the heading count $heading_n: $(grep -F '**Method**' <<<"$body_ar")"
# A full run (nothing skipped) lists no skipped angles.
printf '{"tier":"large","lines":900,"files":9,"angles":["A","B"],"skipped":[]}\n' > "$work/full-angles.json"
out_af=$("$script" 7 "$fx/findings.json" --repo o/r --angles "$work/full-angles.json" --dry-run 2>&1) || err "full --angles dry run failed"
grep -qF 'Angles skipped' <<<"$out_af" && err "empty skipped list still rendered an 'Angles skipped' block"
printf '{"tier":"tiny"}\n' > "$work/bad-angles.json"
if "$script" 7 "$fx/findings.json" --repo o/r --angles "$work/bad-angles.json" --dry-run >/dev/null 2>&1; then err "malformed --angles file exited 0"; fi
if "$script" 7 "$fx/findings.json" --repo o/r --angles "$work/missing.json" --dry-run >/dev/null 2>&1; then err "unreadable --angles exited 0"; fi
# Without --angles the wording is unchanged.
grep -qF 'ran 7 of' <<<"$body" && err "default body should not carry the --angles Method line"

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

# A1 — truncation guard: fewer `diff --git` headers than the PR's
# authoritative changed_files count refuses to post (run WITHOUT --dry-run,
# and confirm nothing was posted — a dry run alone can't prove that).
: > "$STUB_LOG"
if out=$(STUB_DIFF="$fx/diff-truncated.txt" "$script" 7 "$fx/findings.json" --repo o/r 2>&1); then
  err "truncated diff exited 0"
fi
grep -qF 'diff has 2 of 3 changed files; refusing to post — re-run' <<<"$out" \
  || err "missing truncation-guard message: $out"
if grep -q '/reviews\|/comments' "$STUB_LOG"; then err "truncated diff posted despite guard"; fi

# A1 — the count-based guard tolerates diff shapes the old path-list guard
# false-refused: a pure rename, a binary add, a path with a space (with the
# trailing TAB git emits), and a quoted non-ASCII path. Each yields exactly
# one `diff --git` header and nothing the old `---`/`+++` path comparison
# could match on (rename and binary emit neither line at all).
: > "$STUB_LOG"
out_edge=$(STUB_DIFF="$fx/diff-edge-cases.txt" STUB_CHANGED_FILES=4 \
  "$script" 7 "$fx/findings.json" --repo o/r --dry-run 2>&1) \
  || err "edge-case diff (rename/binary/space/quoted path) refused: $out_edge"

# A3 — a finding on a space-containing path anchors inline: the awk that
# builds valid.tsv must strip the trailing TAB git emits after such a path
# before comparing it to the finding's path.
out_space=$(STUB_DIFF="$fx/diff-edge-cases.txt" STUB_CHANGED_FILES=4 \
  "$script" 7 "$fx/findings-space.json" --repo o/r --dry-run 2>&1) \
  || err "space-path finding dry run failed: $out_space"
payload_space=$(awk 'f; /^## Review payload$/ {f=1}' <<<"$out_space")
jq -e '[.comments[] | select(.path == "has space.txt" and .line == 2)] | length == 1' \
  <<<"$payload_space" >/dev/null \
  || err "has space.txt line 2 not inline: $payload_space"

# A diff holding only a rename (or only binary files) has no `+++` line, yet
# gh pr diff succeeded; it must not trigger the local git-diff fallback, which
# fails when the script runs outside the PR's repository.
: > "$STUB_LOG"
out_ren=$(STUB_DIFF="$fx/diff-rename-only.txt" STUB_CHANGED_FILES=1 \
  "$script" 7 "$fx/findings.json" --repo o/r --dry-run 2>&1) \
  || err "rename-only diff failed: $out_ren"
if grep -q 'falling back' <<<"$out_ren"; then err "rename-only diff took the git-diff fallback"; fi
if grep -q -- '--jq .base.sha' "$STUB_LOG"; then err "rename-only diff fetched base sha for fallback"; fi

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

# --draft: a PENDING review (no `event` in the payload), walkthrough folded
# into the body, no issue comment, no commit status, no thread-list patch, and a
# snapshot saved for read-back.sh.
export XDG_STATE_HOME=$work/state
cat > "$work/review-comments.json" <<'EOF'
[{"id":11,"path":"a.go","line":2,"body":"c1"},{"id":12,"path":"b.go","line":2,"body":"c2"}]
EOF
export STUB_REVIEW_COMMENTS=$work/review-comments.json
: > "$STUB_LOG"
out_dr=$(STUB_PAYLOAD_OUT=$work/draft-payload.json "$script" 7 "$fx/findings.json" --repo o/r --walkthrough "$fx/walkthrough.md" --draft 2>&1) \
  || err "--draft post failed: $out_dr"
[[ -s $work/draft-payload.json ]] || err "--draft never created a review"
jq -e 'has("event") | not' "$work/draft-payload.json" >/dev/null || err "--draft payload carries an event (would not be PENDING)"
jq -e '.comments | length == 3' "$work/draft-payload.json" >/dev/null || err "--draft payload lost its inline comments"
head -1 < <(jq -r .body "$work/draft-payload.json") | grep -q '^<!-- deep-pr-review head:abc123 ' \
  || err "--draft body does not start with the marker"
grep -qF '<summary>📝 Walkthrough</summary>' <(jq -r .body "$work/draft-payload.json") || err "--draft body lacks the folded walkthrough"
grep -qF 'Adds two small Go files' <(jq -r .body "$work/draft-payload.json") || err "--draft body lacks the walkthrough text"
if grep -q 'issues/7/comments' "$STUB_LOG"; then err "--draft posted a walkthrough issue comment"; fi
if grep -q 'statuses/' "$STUB_LOG"; then err "--draft posted a commit status"; fi
if grep -q -- '-X PUT' "$STUB_LOG"; then err "--draft patched the open-thread list"; fi
snap="$XDG_STATE_HOME/deep-pr-review/o_r_7_901.json"
[[ -r $snap ]] || err "--draft wrote no snapshot at $snap"
jq -e '.review_id == 901 and .head == "abc123" and (.comments | length == 2) and (.comments[0].id == 11) and (.body | startswith("<!-- deep-pr-review"))' "$snap" >/dev/null \
  || err "snapshot content wrong: $(cat "$snap" 2>/dev/null)"
grep -qF "snapshot: $snap" <<<"$out_dr" || err "--draft did not print the snapshot path"
grep -qF 'pull/7/files' <<<"$out_dr" || err "--draft did not print where to submit"

# Without --draft the payload still carries event=COMMENT (publish stays the default).
STUB_PAYLOAD_OUT=$work/pub-payload.json "$script" 7 "$fx/findings.json" --repo o/r >/dev/null 2>&1 || err "publish failed"
jq -e '.event == "COMMENT"' "$work/pub-payload.json" >/dev/null || err "publish payload lost event=COMMENT"

# --draft dry run: shows the payload, folds the walkthrough, makes no write.
: > "$STUB_LOG"
out_dd=$("$script" 7 "$fx/findings.json" --repo o/r --walkthrough "$fx/walkthrough.md" --draft --dry-run 2>&1) || err "--draft dry run failed: $out_dd"
grep -q '^## Walkthrough comment$' <<<"$out_dd" && err "--draft dry run shows a separate walkthrough comment"
jq -e 'has("event") | not' <<<"$(awk 'f; /^## Review payload$/ {f=1}' <<<"$out_dd")" >/dev/null || err "--draft dry-run payload carries an event"
if grep -q 'reviews --input' "$STUB_LOG"; then err "--draft dry run created a review"; fi

# An existing PENDING review of the same user: refuse before any write.
echo '[{"id":55,"state":"PENDING","user":{"login":"me"}}]' > "$work/reviews-pending.json"
: > "$STUB_LOG"
if out=$(STUB_REVIEWS=$work/reviews-pending.json "$script" 7 "$fx/findings.json" --repo o/r --draft 2>&1); then
  err "--draft with an existing pending review exited 0"
fi
grep -qF 'already have a PENDING review (id 55)' <<<"$out" || err "missing pending-review refusal: $out"
if grep -q 'reviews --input\|issues/7/comments\|statuses/' "$STUB_LOG"; then err "wrote something despite an existing pending review"; fi
# Another user's pending review (or my own submitted one) is not a blocker.
echo '[{"id":56,"state":"PENDING","user":{"login":"someone"}},{"id":57,"state":"COMMENTED","user":{"login":"me"}}]' > "$work/reviews-other.json"
STUB_REVIEWS=$work/reviews-other.json "$script" 7 "$fx/findings.json" --repo o/r --draft >/dev/null 2>&1 \
  || err "--draft refused although the pending review belongs to someone else"
# Publish mode does not consult the pending list.
: > "$STUB_LOG"
STUB_REVIEWS=$work/reviews-pending.json "$script" 7 "$fx/findings.json" --repo o/r >/dev/null 2>&1 || err "publish refused because of a pending review"

# read-back.sh: kept / edited / removed / added against the snapshot.
rb=skills-shared/deep-pr-review/scripts/read-back.sh
mkdir -p "$work/rb"
cat > "$work/rb/reviews.json" <<'EOF'
[{"id":3,"state":"COMMENTED","user":{"login":"me"}},
 {"id":901,"state":"PENDING","user":{"login":"me"}},
 {"id":950,"state":"COMMENTED","user":{"login":"other"}}]
EOF
cat > "$work/rb/review.json" <<'EOF'
{"id":901,"state":"PENDING","body":"edited body"}
EOF
# c1 kept (CRLF and trailing space are UI noise, not an edit), c2 removed,
# c3 edited, c4 added.
cat > "$work/rb/snap-src.json" <<'EOF'
{"review_id":901,"head":"abc123","body":"orig body",
 "comments":[{"id":11,"path":"a.go","line":2,"body":"c1"},
             {"id":12,"path":"b.go","line":2,"body":"c2"},
             {"id":13,"path":"a.go","line":3,"body":"c3 before"}]}
EOF
cp "$work/rb/snap-src.json" "$XDG_STATE_HOME/deep-pr-review/o_r_7_901.json"
printf '%s' '[{"id":11,"path":"a.go","line":2,"body":"c1\r\n "},
 {"id":13,"path":"a.go","line":3,"body":"c3 after"},
 {"id":14,"path":"b.go","line":null,"original_line":9,"body":"c4 new"}]' > "$work/rb/comments.json"
rb_out=$(STUB_REVIEWS=$work/rb/reviews.json STUB_REVIEW=$work/rb/review.json STUB_REVIEW_COMMENTS=$work/rb/comments.json \
  "$rb" 7 --repo o/r 2>&1) || err "read-back.sh failed: $rb_out"
jq -e '(.kept | map(.id)) == [11]' <<<"$rb_out" >/dev/null || err "read-back kept wrong: $rb_out"
jq -e '(.removed | map(.id)) == [12]' <<<"$rb_out" >/dev/null || err "read-back removed wrong: $rb_out"
jq -e '(.edited | length == 1) and .edited[0].id == 13 and .edited[0].before == "c3 before" and .edited[0].after == "c3 after" and .edited[0].path == "a.go"' <<<"$rb_out" >/dev/null \
  || err "read-back edited wrong: $rb_out"
jq -e '(.added | length == 1) and .added[0].id == 14 and .added[0].line == 9 and .added[0].body == "c4 new"' <<<"$rb_out" >/dev/null \
  || err "read-back added wrong: $rb_out"
jq -e '.body_changed == true' <<<"$rb_out" >/dev/null || err "read-back missed the body change"
# Unedited body and comments: everything kept, nothing else.
printf '%s' '{"id":901,"state":"PENDING","body":"orig body\n"}' > "$work/rb/review-same.json"
printf '%s' '[{"id":11,"path":"a.go","line":2,"body":"c1"},{"id":12,"path":"b.go","line":2,"body":"c2"},{"id":13,"path":"a.go","line":3,"body":"c3 before"}]' > "$work/rb/comments-same.json"
rb_same=$(STUB_REVIEWS=$work/rb/reviews.json STUB_REVIEW=$work/rb/review-same.json STUB_REVIEW_COMMENTS=$work/rb/comments-same.json \
  "$rb" 7 --repo o/r --review-id 901 2>&1) || err "read-back (unchanged) failed: $rb_same"
jq -e '(.kept | length == 3) and (.edited | length == 0) and (.removed | length == 0) and (.added | length == 0) and .body_changed == false' <<<"$rb_same" >/dev/null \
  || err "read-back of an untouched review is not all-kept: $rb_same"
# No snapshot: refuse with a pointer to --draft.
if out=$(XDG_STATE_HOME=$work/empty-state STUB_REVIEWS=$work/rb/reviews.json "$rb" 7 --repo o/r 2>&1); then err "read-back without a snapshot exited 0"; fi
grep -qF 'post-review.sh --draft' <<<"$out" || err "read-back no-snapshot message lacks the --draft pointer: $out"

# Secret redaction: every outbound text (inline bodies, review body incl. the
# combined agent prompt, walkthrough, draft snapshot) goes through
# redact-secrets.sh. The fake token is assembled at runtime so no token-shaped
# string is committed.
secret="gh""p_$(printf 'Q%.0s' {1..36})"
jq --arg s "$secret" '.[0].body += " Leaked " + $s + " here." | .[0].agent_prompt += " token " + $s' \
  "$fx/findings.json" > "$work/findings-secret.json"
printf 'Walkthrough mentions %s too.\n' "$secret" > "$work/walkthrough-secret.md"
: > "$STUB_LOG"
out_rs=$("$script" 7 "$work/findings-secret.json" --repo o/r --walkthrough "$work/walkthrough-secret.md" --dry-run 2>&1) \
  || err "secret-bearing dry run failed: $out_rs"
grep -qF -- "$secret" <<<"$out_rs" && err "dry run still shows the secret"
grep -qF '<secret-redacted>' <<<"$out_rs" || err "dry run shows no redaction placeholder"
payload_rs=$(awk 'f; /^## Review payload$/ {f=1}' <<<"$out_rs")
jq -e '.comments[0].body | contains("<secret-redacted>") and (contains("Leaked") )' <<<"$payload_rs" >/dev/null \
  || err "inline comment was not redacted in place"
jq -e '.body | contains("<secret-redacted>")' <<<"$payload_rs" >/dev/null || err "review body (combined agent prompt) not redacted"
# A real post sends the redacted payload.
STUB_PAYLOAD_OUT=$work/rs-payload.json "$script" 7 "$work/findings-secret.json" --repo o/r --walkthrough "$work/walkthrough-secret.md" >/dev/null 2>&1 \
  || err "secret-bearing post failed"
grep -qF -- "$secret" "$work/rs-payload.json" && err "posted payload contains the secret"
# Draft: payload (walkthrough folded in) and snapshot are clean.
printf '[{"id":11,"path":"a.go","line":2,"body":"quotes %s"}]' "$secret" > "$work/review-comments-secret.json"
STUB_REVIEW_COMMENTS=$work/review-comments-secret.json STUB_PAYLOAD_OUT=$work/rs-draft.json \
  "$script" 7 "$work/findings-secret.json" --repo o/r --walkthrough "$work/walkthrough-secret.md" --draft >/dev/null 2>&1 \
  || err "secret-bearing draft failed"
grep -qF -- "$secret" "$work/rs-draft.json" && err "draft payload contains the secret"
grep -qF 'Walkthrough mentions <secret-redacted>' "$work/rs-draft.json" || err "draft walkthrough not redacted"
grep -rqF -- "$secret" "$XDG_STATE_HOME" && err "snapshot contains the secret"
grep -rqF '<secret-redacted>' "$XDG_STATE_HOME/deep-pr-review/o_r_7_901.json" || err "snapshot comment not redacted"

# perl missing: refuse before any network write, never post unredacted.
mkdir -p "$work/noperl-bin"
for f in /usr/bin/* /bin/*; do
  case ${f##*/} in perl*) continue ;; esac
  [[ -e $work/noperl-bin/${f##*/} ]] || ln -s "$f" "$work/noperl-bin/${f##*/}" 2>/dev/null
done
ln -sf "$PWD/$fx/gh" "$work/noperl-bin/gh"
: > "$STUB_LOG"
if out=$(PATH="$work/noperl-bin" "$script" 7 "$fx/findings.json" --repo o/r 2>&1); then
  err "post-review.sh without perl exited 0"
fi
grep -qi 'perl' <<<"$out" || err "no-perl refusal does not mention perl: $out"
if grep -q 'reviews --input\|issues/7/comments\|statuses/' "$STUB_LOG"; then err "posted although redaction was unavailable"; fi

# Governance: a Critical/Major finding carries counter_argument, a Moderate/Heavy
# one carries rejected_alternative; both are rendered, and a finding missing a
# required field is refused BEFORE any gh call (the log must stay empty).
refuses() { # NAME JQ-PROGRAM WANT-SUBSTRING...
  local name=$1 prog=$2 want=$3 out
  jq "$prog" "$fx/findings-sites.json" > "$work/gov.json"
  : > "$STUB_LOG"
  if out=$("$script" 7 "$work/gov.json" --repo o/r 2>&1); then err "$name: exited 0"; return; fi
  grep -qF -- "$want" <<<"$out" || err "$name: message lacks '$want': $out"
  grep -qF 'Multi-site finding.' <<<"$out" || err "$name: message does not name the finding: $out"
  [[ ! -s $STUB_LOG ]] || err "$name: made gh calls before refusing: $(cat "$STUB_LOG")"
}
refuses "major without counter_argument" 'map(del(.counter_argument))' 'counter_argument'
refuses "heavy lift without rejected_alternative" 'map(del(.rejected_alternative))' 'rejected_alternative'
refuses "blank counter_argument" 'map(.counter_argument = "  ")' 'counter_argument'
refuses "moderate without rejected_alternative" 'map(.effort = "🔧 Moderate" | del(.rejected_alternative))' 'rejected_alternative'
refuses "critical without counter_argument" 'map(.severity = "🔴 Critical" | del(.counter_argument))' 'counter_argument'
# A label without its emoji must not slip past the rules above.
refuses "severity without emoji" 'map(.severity = "Critical" | del(.counter_argument))' 'severity "Critical" is not one of'
refuses "effort without emoji" 'map(.effort = "Heavy lift" | del(.rejected_alternative))' 'effort "Heavy lift" is not one of'
refuses "missing severity" 'map(del(.severity))' 'severity null is not one of'
# Not required: a Minor quick fix needs neither field.
jq 'map(.severity = "🟡 Minor" | .effort = "🧹 Quick fix" | del(.counter_argument, .rejected_alternative))' "$fx/findings-sites.json" > "$work/gov-ok.json"
"$script" 7 "$work/gov-ok.json" --repo o/r --dry-run >/dev/null 2>&1 || err "Minor quick fix was refused for lacking governance fields"
# The dry run refuses too (it is the preview of the post).
jq 'map(del(.counter_argument))' "$fx/findings-sites.json" > "$work/gov.json"
if "$script" 7 "$work/gov.json" --repo o/r --dry-run >/dev/null 2>&1; then err "dry run accepted a finding missing counter_argument"; fi

# Rendering: counter-argument before the per-site fix lines, rejected
# alternative after them.
c_body=$(jq -r '.comments[0].body' <<<"$payload_sites")
grep -qF '**Strongest counter-argument:** Strongest counter: both sites are only reached from tests.' <<<"$c_body" || err "counter-argument not rendered"
grep -qF '**Rejected alternative:** Guarding at the call site was rejected' <<<"$c_body" || err "rejected alternative not rendered"
ca_ln=$(grep -n 'Strongest counter-argument' <<<"$c_body" | head -1 | cut -d: -f1)
# shellcheck disable=SC2016 # literal markdown backticks in the pattern
site_ln=$(grep -n '^- `a.go#L2-L2`' <<<"$c_body" | head -1 | cut -d: -f1)
ra_ln=$(grep -n 'Rejected alternative' <<<"$c_body" | head -1 | cut -d: -f1)
[[ -n $ca_ln && -n $site_ln && -n $ra_ln && $ca_ln -lt $site_ln && $site_ln -lt $ra_ln ]] \
  || err "order must be counter-argument < site lines < rejected alternative (got $ca_ln/$site_ln/$ra_ln)"
# A finding without the optional fields renders neither label.
grep -qF 'Rejected alternative' <<<"$(jq -r '.comments[] | select(.line == 3) | .body' <<<"$payload")" \
  && err "rendered a rejected-alternative label for a finding without one"

((fail)) && exit 1
echo PASS
