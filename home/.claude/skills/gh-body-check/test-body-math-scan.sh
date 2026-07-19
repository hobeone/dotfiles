#!/usr/bin/env bash
# Contract test for body-math-scan.sh's exit-code + detection contract.
#
# Zero-dependency harness: bash + rg only (the repo has no bash test framework,
# and this adds only enough to drive this one script). It runs the scan against
# crafted body fixtures and asserts the exit-code contract:
#   0 = clean, 1 = a forbidden Unicode glyph, macro, or code-span-neutralized
#   inline-math construct found, 2 = usage / env error.
#
# Two frozen regex reconstructions are checked alongside the real assertions, so
# the suite proves it guards the real regressions rather than just restating
# current behavior (see the "non-tautology guard" differentials): the
# Unicode-only PREFIX_REGEX shows a \operatorname body slipped through pre-fix,
# and the classes-1+2 PRE_CODESPAN_REGEX shows a code-span-neutralized inline-math
# body slipped through before class 3 was added.
#
# Run:
#   bash test-body-math-scan.sh
#
# shellcheck disable=SC2016  # single-quoted fixture bodies hold literal LaTeX
#                            # (e.g. \operatorname); non-expansion is intentional.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/body-math-scan.sh"

# Frozen reconstruction of the scanner's regex BEFORE \operatorname detection was
# added: the Unicode-codepoint class only, with no \operatorname alternative.
# FROZEN HISTORICAL ARTIFACT: do not extend it. It exists solely so the
# differential below can show a \operatorname-only body slipped through pre-fix.
PREFIX_REGEX='[\x{00B1}\x{00B2}\x{00B3}\x{00B9}\x{00D7}\x{00F7}\x{0370}-\x{03FF}\x{2070}-\x{209F}\x{2200}-\x{22FF}\x{2A00}-\x{2AFF}\x{2020}\x{2021}]'

# Frozen reconstruction of the scanner's regex BEFORE the class-3 (code-span-
# neutralized inline math) alternative was added: classes 1 + 2 only (Unicode
# glyphs + \operatorname). FROZEN HISTORICAL ARTIFACT: do not extend it. It
# exists solely so the class-3 differential below can show a body with inline
# math neutralized by a code span slipped through before this fix.
PRE_CODESPAN_REGEX='[\x{00B1}\x{00B2}\x{00B3}\x{00B9}\x{00D7}\x{00F7}\x{0370}-\x{03FF}\x{2070}-\x{209F}\x{2200}-\x{22FF}\x{2A00}-\x{2AFF}\x{2020}\x{2021}]|\\operatorname\*?(?![A-Za-z])'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Write a body string to a temp file and echo its path.
mkfix() { local f; f="$(mktemp "$tmpdir/fx-XXXXXX")"; printf '%s\n' "$1" >"$f"; echo "$f"; }

# Exit code of the real scan on a body string.
scan_rc() { "$SCAN" "$(mkfix "$1")" >/dev/null 2>&1; echo "$?"; }

# Exit code of the frozen pre-fix Unicode-only regex on a body string, under the
# same 0=hit / 1=clean / 2=error flip the script applies to rg's status.
prefix_rc() {
  local f rc
  f="$(mkfix "$1")"
  rg -nP "$PREFIX_REGEX" "$f" >/dev/null 2>&1
  rc=$?
  case "$rc" in 0) echo 1 ;; 1) echo 0 ;; *) echo 2 ;; esac
}

# Exit code of the frozen pre-class-3 regex (classes 1 + 2) on a body string,
# under the same 0=hit / 1=clean / 2=error flip the script applies to rg.
pre_codespan_rc() {
  local f rc
  f="$(mkfix "$1")"
  rg -nP "$PRE_CODESPAN_REGEX" "$f" >/dev/null 2>&1
  rc=$?
  case "$rc" in 0) echo 1 ;; 1) echo 0 ;; *) echo 2 ;; esac
}

fails=0
assert() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   %-46s rc=%s\n' "$label" "$got"
  else
    printf 'FAIL %-46s want rc=%s got rc=%s\n' "$label" "$want" "$got"
    fails=$((fails + 1))
  fi
}

# --- Contract cases -------------------------------------------------------
assert "operatorname in math -> hit"         "$(scan_rc 'Define $`\operatorname{Tr}(A)`$.')"        1
assert "operatorname* in math -> hit"        "$(scan_rc 'See $`\operatorname*{argmin}_x`$.')"       1
assert "operatornamewithlimits -> clean"     "$(scan_rc 'Use $`\operatornamewithlimits{lim}`$.')"   0
assert "unicode glyph -> hit"                "$(scan_rc 'The angle is α here.')"                     1
assert "mathrm substitute -> clean"          "$(scan_rc 'Use `\mathrm{Tr}` for the trace.')"        0

# --- Class 3: code-span-neutralized inline math ---------------------------
# The construct $`...`$ wrapped in a >=2-backtick code span renders as literal
# code on GitHub, not math, so it must be flagged.
assert "codespan-wrapped math -> hit"        "$(scan_rc 'Define `` $`\pm i`$ `` clearly.')"         1
assert "codespan-wrapped, no padding -> hit" "$(scan_rc 'Define ``$`\pm i`$`` here.')"               1
# Math co-resident with other text inside the span is still inside the span.
assert "codespan text + math -> hit"         "$(scan_rc '``example: $`a`$`` trailing.')"             1
# GFM lets a code span contain a backtick run LONGER than its own fence (a >fence
# run does not close it). The math after such a run is still neutralized; the
# tempered-token regex must not stop early on the longer internal run.
assert "codespan longer inner run -> hit"    "$(scan_rc 'a `` b ``` c $`x`$ d `` e')"               1
# Over-match guard: a bare valid inline-math construct (no enclosing span) is
# fine and must stay clean.
assert "bare inline math -> clean"           "$(scan_rc 'The value is $`\pm i`$ today.')"            0
# False-positive guard: a code span IMMEDIATELY FOLLOWED by valid math (the math
# is outside the span) must stay clean.
assert "codespan then bare math -> clean"    "$(scan_rc 'Use `` `inline` `` then $`\pm i`$ here.')"  0
# Mismatched fences (open 2, close 3) are not a GFM code span, so the math is not
# neutralized and must stay clean.
assert "mismatched fences -> clean"          "$(scan_rc 'Bad `` $`x`$ ``` mismatch.')"               0

# Environment error, source 1: a path that does not exist -> caught by the -f
# guard -> exit 2.
"$SCAN" "$tmpdir/does-not-exist.md" >/dev/null 2>&1
assert "missing file -> usage/env error"     "$?"                                                   2

# Environment error, source 2: a file that exists (passes the -f guard) but rg
# cannot read -> the rg-error branch maps to exit 2, a distinct exit-2 source.
# Skipped under root, where permission bits do not block reads.
if [[ "$(id -u)" -ne 0 ]]; then
  unreadable="$(mkfix 'unreadable body')"
  chmod 000 "$unreadable"
  "$SCAN" "$unreadable" >/dev/null 2>&1
  assert "unreadable file -> usage/env error" "$?"                                                  2
  chmod 644 "$unreadable" # restore so trap cleanup is unimpeded
else
  printf 'skip unreadable file -> usage/env error           (running as root)\n'
fi

# --- Non-tautology guard --------------------------------------------------
# A \operatorname-only body (no Unicode glyph) is where the pre-fix Unicode-only
# scanner and the fixed scanner diverge: pre-fix reports clean (the miss this
# change fixes), the fixed scanner reports a hit. Asserting both directions
# proves the operatorname case is a genuine regression guard, not a restatement
# of current behavior.
OPNAME_BODY='Define $`\operatorname{Tr}(A)`$.'
assert "operatorname: pre-fix regex -> clean (miss)" "$(prefix_rc "$OPNAME_BODY")" 0
assert "operatorname: fixed scan    -> hit"          "$(scan_rc "$OPNAME_BODY")"   1

# A code-span-neutralized inline-math body (no Unicode glyph, no \operatorname)
# is where the pre-class-3 regex (classes 1 + 2) and the fixed scanner diverge:
# pre-class-3 reports clean (the miss this change fixes), the fixed scanner
# reports a hit. Asserting both directions proves class 3 is a genuine
# regression guard, not a restatement of current behavior.
CODESPAN_BODY='Define `` $`\pm i`$ `` clearly.'
assert "codespan: pre-class3 regex -> clean (miss)"  "$(pre_codespan_rc "$CODESPAN_BODY")" 0
assert "codespan: fixed scan       -> hit"           "$(scan_rc "$CODESPAN_BODY")"         1

# --- Summary --------------------------------------------------------------
echo
if [[ "$fails" -eq 0 ]]; then
  echo "All checks passed."
  exit 0
fi
echo "$fails check(s) failed."
exit 1
