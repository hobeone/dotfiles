#!/usr/bin/env bash
# body-math-scan.sh — flag Unicode math glyphs, GitHub-unsupported math macros,
# and code-span-neutralized inline math in a GitHub body draft.
#
# Mechanical half of gh-body-check. A single rg pass flags three classes that
# gh-body-conventions § Math forbids:
#   1. Unicode glyphs — any character in the Greek block, the two Mathematical
#      Operators blocks, the Superscripts-and-Subscripts block, the Latin-1 math
#      signs (plus-minus, multiplication, division) and superscripts (two /
#      three / one), or the dagger / double-dagger pair (use $`\alpha`$ etc.
#      instead of bare `α`).
#   2. GitHub-unsupported macro — the literal \operatorname / \operatorname*.
#      GitHub's math renderer does not render it regardless of delimiter form,
#      even though it works in standard MathJax (github/markup#1688); use
#      \mathrm instead.
#   3. Code-span-neutralized inline math — a valid inline-math construct
#      $`...`$ wrapped in an enclosing inline code span (a backtick run of
#      length >= 2 on each side). GitHub renders the wrapped construct as
#      literal code, not math, so the math silently fails to render. This
#      happens when the display form of the construct (how gh-body-conventions
#      shows the literal syntax) is copied straight into a body.
# For classes 1 and 2, a hit inside a fenced code block, an inline code span, or
# prose naming the macro is out of scope here — SKILL.md judges those in main
# context. Class 3 is the exception: the enclosing code span IS the defect, so
# it is flagged; SKILL.md then judges intent (neutralized math vs. a legitimate
# literal $`...`$ shown as code/data).
#
# Limitations: the scan is line-oriented (a code span split across source lines
# is not detected) and covers inline math only ($$...$$ display math wrapped in
# a code span is out of scope). Because a regex cannot track which fences pair,
# two class-3 false positives are possible: a backslash-escaped backtick run, or
# two separate code spans flanking bare (correctly-rendering) inline math on one
# line — the closing fence of the first span mis-pairs with the opening fence of
# the second, bracketing the math. Both are resolved by SKILL.md's main-context
# triage, which inspects whether the math actually renders as code.
#
# Exit codes: 0 = no hits (clean), 1 = hits found, 2 = usage or environment
# error. (rg's native convention is the opposite — match=0, no-match=1 — so this
# script flips it so callers can use the more natural "non-zero = problem"
# convention.)

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: body-math-scan.sh <body-file>

Scans <body-file> for three classes of math that gh-body-conventions forbids:
  - Unicode math characters (Greek, Math Operators, Supplemental Math
    Operators, Superscripts/Subscripts, the Latin-1 signs ± × ÷ and
    superscripts ¹ ² ³, †, ‡).
  - The GitHub-unsupported macro \operatorname / \operatorname* (broken on
    GitHub regardless of delimiter form; use \mathrm{...} instead).
  - Inline math $`...`$ neutralized by an enclosing code span, which GitHub
    renders as literal code instead of math.

Prints rg output (line:match — rg emits no path prefix for a single file)
and exits 1 if any hit is found.
EOF
}

case "${1:-}" in
  ''|-h|--help) usage; [ -z "${1:-}" ] && exit 2 || exit 0 ;;
esac

BODY_FILE=$1
[ -f "$BODY_FILE" ] || { echo "error: file not found: $BODY_FILE" >&2; exit 2; }
command -v rg >/dev/null 2>&1 || { echo "error: ripgrep (rg) is required" >&2; exit 2; }

# Ranges:
#   U+00B1, U+00D7, U+00F7         plus-minus, multiplication, division
#   U+00B2, U+00B3, U+00B9         superscript two, three, one — listed
#                                  individually, NOT as a U+00B2–U+00B9 range,
#                                  which would also catch acute / micro /
#                                  pilcrow / middle-dot / cedilla (prose).
#   U+0370–U+03FF                  Greek and Coptic
#   U+2070–U+209F                  Superscripts and Subscripts (super/subscript
#                                  minus, plus, digits, etc.)
#   U+2200–U+22FF                  Mathematical Operators
#   U+2A00–U+2AFF                  Supplemental Mathematical Operators
#   U+2020, U+2021                 dagger, double dagger
# The character class catches the Unicode glyphs (class 1) above; the second
# alternative catches the GitHub-unsupported macro \operatorname / \operatorname*
# (class 2 — broken on GitHub regardless of delimiter form, github/markup#1688;
# use \mathrm instead). The (?![A-Za-z]) guard keeps \operatorname from
# partial-matching a longer command name such as \operatornamewithlimits, so
# only the in-scope forms match.
#
# The third alternative catches class 3 (code-span-neutralized inline math). It
# encodes GFM's code-span rule — a code span is delimited by two backtick runs
# of EQUAL length, each maximal (neither preceded nor followed by a backtick):
#   (?<!`)(`{2,})(?!`)   opening fence: a maximal run of >= 2 backticks, captured
#                        in \1. >= 2 because the inner $`...`$ holds single
#                        backticks, so a length-1 fence cannot enclose it.
#   (?<!`)\1(?!`)        closing fence: a maximal run of the SAME length.
#   (?:(?!(?<!`)\1(?!`)).)*?   tempered token: consume any content up to (but not
#                        including) the real closing fence. The full maximal-run
#                        lookahead — not a bare \1 — lets the span legitimately
#                        contain a backtick run LONGER than the fence (which does
#                        not close it) without the scan stopping early on it.
#   \$`[^`]*`\$          the wrapped inline-math construct itself (its LaTeX body
#                        has no backticks). Detected anywhere inside the span, so
#                        text co-resident with the math is still caught.
rg -nP '[\x{00B1}\x{00B2}\x{00B3}\x{00B9}\x{00D7}\x{00F7}\x{0370}-\x{03FF}\x{2070}-\x{209F}\x{2200}-\x{22FF}\x{2A00}-\x{2AFF}\x{2020}\x{2021}]|\\operatorname\*?(?![A-Za-z])|(?<!`)(`{2,})(?!`)(?:(?!(?<!`)\1(?!`)).)*?\$`[^`]*`\$(?:(?!(?<!`)\1(?!`)).)*?(?<!`)\1(?!`)' "$BODY_FILE"
rc=$?
# rg: 0 match, 1 no match, 2+ real error.
case "$rc" in
  0) exit 1 ;;   # hits found → problem
  1) exit 0 ;;   # no hits → clean
  *) exit 2 ;;   # rg failed (bad regex, IO error)
esac
