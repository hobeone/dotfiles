# Shared deep-pr-review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `deep-pr-review` one harness-neutral method in `skills-shared/`, loaded by thin Claude Code and agy adapters, with eligibility checks, three history-aware angles, and the known defects fixed.

**Architecture:** `skills-shared/deep-pr-review/` holds `method.md`, `reference/`, `scripts/`. Each harness keeps a directory under `home/.{claude,gemini}/skills/deep-pr-review/` containing its own `SKILL.md` (frontmatter, verb bindings, model routing) plus relative symlinks `method.md`, `reference`, `scripts` into the shared core. `method.md` names no tools; it uses `⟨verb⟩` tokens that each adapter binds. A generic bash test enforces the pattern.

**Tech Stack:** Markdown skills, bash, `jq`, `gh`, GNU Stow, GitHub Actions, shellcheck.

**Spec:** `docs/superpowers/specs/2026-09-16-shared-deep-pr-review-design.md`

## Global Constraints

- Branch: `feat/shared-deep-pr-review`. Never push to `master`.
- Move existing files with `git mv`, never `mv`.
- Commit messages: Conventional Commits, lowercase imperative description ≤ 72 chars, ending with the footer `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- No text file under `skills-shared/<name>/` may contain: `run_subagent`, `invoke_subagent`, `view_file`, `run_command`, `ask_question`, `AskUserQuestion`, `subagent_type`, `~/.gemini`, `~/.claude`.
- Every `⟨verb⟩` used in `method.md` is bound in every adapter's `## Harness mapping` table; no adapter binds an unused verb.
- Callers reference `deep-pr-review` phases by **name**, never by number.
- All new/changed shell scripts pass `shellcheck -x`.
- Every test assertion is observed **failing** before it is trusted (revert/break, run, confirm the named assertion fails, restore).
- Run every command from the repo root `/home/hobe/dotfiles` unless a step says otherwise.

## Deviation from spec (recorded)

The spec's verb table lists six verbs. Neutralizing Phase Gather requires a seventh,
`⟨user-instructions⟩` (the user's global instruction file, previously `cat ~/.claude/CLAUDE.md`), because
harness home paths are forbidden in the core. Task 1 adds it and amends the spec's verb table.

## File Structure

| Path | Responsibility |
|---|---|
| `skills-shared/README.md` | Documents the neutral-core + adapter pattern and its rules |
| `skills-shared/deep-pr-review/method.md` | Harness-neutral review method (from the old `SKILL.md`) |
| `skills-shared/deep-pr-review/reference/format.md` | CodeRabbit output templates (moved) |
| `skills-shared/deep-pr-review/reference/go_rules.md` | Go rule catalog (moved) |
| `skills-shared/deep-pr-review/scripts/post-review.sh` | Posts the review; anchors, head guard, marker (moved + changed) |
| `home/.gemini/skills/deep-pr-review/SKILL.md` | agy adapter: frontmatter, bindings, routing, call shape |
| `home/.gemini/skills/deep-pr-review/{method.md,reference,scripts}` | Relative symlinks into the core |
| `home/.claude/skills/deep-pr-review/SKILL.md` | Claude adapter |
| `home/.claude/skills/deep-pr-review/{method.md,reference,scripts}` | Relative symlinks into the core |
| `tests/test_skills_shared.sh` | Generic pattern enforcement for every `skills-shared/*/` |
| `tests/test_post_review.sh` | `post-review.sh` behavior with a stub `gh` |
| `tests/test_deep_pr_review_method.sh` | Structural checks on the merged method and its callers |
| `home/.gemini/skills/adversarial-review/SKILL.md`, `.../adversarial-review-loop/SKILL.md` | Callers: angle count and phase-name references |
| `.github/workflows/dotfiles.yml` | shellcheck + run the three tests |

---

### Task 1: Extract the neutral core and the agy adapter

**Files:**
- Create: `tests/test_skills_shared.sh`, `skills-shared/README.md`, `home/.gemini/skills/deep-pr-review/SKILL.md` (new adapter content)
- Move: `home/.gemini/skills/deep-pr-review/{SKILL.md → skills-shared/deep-pr-review/method.md, reference/, scripts/}`
- Create symlinks: `home/.gemini/skills/deep-pr-review/{method.md,reference,scripts}`
- Modify: `skills-shared/deep-pr-review/method.md` (neutralize), `skills-shared/deep-pr-review/reference/go_rules.md:626-646`, spec verb table

**Interfaces:**
- Produces: verbs `⟨dispatch-parallel⟩`, `⟨read-at-sha⟩`, `⟨run⟩`, `⟨ask-user⟩`, `⟨skill-dir⟩`, `⟨user-instructions⟩` (Task 3 adds `⟨run-dir⟩`). Adapter table rows must start with `` | `⟨verb⟩` `` so the test regex `^\| \`⟨[a-z-]+⟩\`` finds them. `tests/test_skills_shared.sh` exits 0 and prints `PASS` on success.

- [ ] **Step 1: Write the pattern test**

Create `tests/test_skills_shared.sh` (then `chmod +x`):

```bash
#!/usr/bin/env bash
# Enforce the skills-shared pattern for every skills-shared/<name>/:
# the core names no harness tools, every verb it uses is bound by every
# adapter (and nothing extra), and adapter links resolve into the core.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
export LC_ALL=C

fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

forbidden='run_subagent|invoke_subagent|view_file|run_command|ask_question|AskUserQuestion|subagent_type|~/\.gemini|~/\.claude'
verb_re='⟨[a-z-]+⟩'

shopt -s nullglob
cores=(skills-shared/*/)
((${#cores[@]})) || err "no shared skills under skills-shared/"

for core in "${cores[@]}"; do
  core=${core%/}
  name=${core##*/}
  if [[ ! -f $core/method.md ]]; then
    err "$name: missing method.md"
    continue
  fi

  if hits=$(grep -rnE "$forbidden" "$core"); then
    err "$name: harness tokens in neutral core:"
    printf '%s\n' "$hits"
  fi

  used=$(grep -ohE "$verb_re" "$core/method.md" | sort -u)
  adapters=0
  for harness in .claude .gemini; do
    adir=home/$harness/skills/$name
    [[ -d $adir ]] || continue
    adapters=$((adapters + 1))

    for entry in "$core"/*; do
      link=$adir/${entry##*/}
      if [[ ! -L $link ]]; then
        err "$link is not a symlink"
        continue
      fi
      want=$(realpath "$entry")
      got=$(realpath "$link" 2>/dev/null || true)
      [[ $got == "$want" ]] || err "$link resolves to '$got', want '$want'"
    done

    if [[ ! -f $adir/SKILL.md ]]; then
      err "$adir: missing SKILL.md"
      continue
    fi
    bound=$(grep -oE "^\| \`$verb_re\`" "$adir/SKILL.md" | grep -oE "$verb_re" | sort -u)
    missing=$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$bound") | sed '/^$/d')
    dead=$(comm -13 <(printf '%s\n' "$used") <(printf '%s\n' "$bound") | sed '/^$/d')
    [[ -z $missing ]] || err "$adir/SKILL.md does not bind: $(tr '\n' ' ' <<<"$missing")"
    [[ -z $dead ]] || err "$adir/SKILL.md binds unused verbs: $(tr '\n' ' ' <<<"$dead")"
  done
  ((adapters)) || err "$name: no adapter under home/.claude/skills or home/.gemini/skills"
done

((fail)) && exit 1
echo PASS
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `bash tests/test_skills_shared.sh`
Expected: `FAIL: no shared skills under skills-shared/`, exit 1.

- [ ] **Step 3: Move the files into the core**

```bash
mkdir -p skills-shared/deep-pr-review
git mv home/.gemini/skills/deep-pr-review/SKILL.md skills-shared/deep-pr-review/method.md
git mv home/.gemini/skills/deep-pr-review/reference skills-shared/deep-pr-review/reference
git mv home/.gemini/skills/deep-pr-review/scripts skills-shared/deep-pr-review/scripts
ls -A home/.gemini/skills/deep-pr-review   # expect: empty
```

- [ ] **Step 4: Create the agy adapter links**

```bash
cd home/.gemini/skills/deep-pr-review
ln -s ../../../../skills-shared/deep-pr-review/method.md method.md
ln -s ../../../../skills-shared/deep-pr-review/reference reference
ln -s ../../../../skills-shared/deep-pr-review/scripts scripts
cd /home/hobe/dotfiles
head -3 home/.gemini/skills/deep-pr-review/method.md   # expect the old frontmatter start: ---
test -x home/.gemini/skills/deep-pr-review/scripts/post-review.sh && echo exec-ok
```

- [ ] **Step 5: Run the test — expect FAIL on tokens and missing SKILL.md**

Run: `bash tests/test_skills_shared.sh`
Expected: `FAIL: deep-pr-review: harness tokens in neutral core:` listing `run_subagent`, `~/.gemini`, `~/.claude` hits, and `FAIL: home/.gemini/skills/deep-pr-review: missing SKILL.md`.

- [ ] **Step 6: Neutralize `method.md`**

Edit `skills-shared/deep-pr-review/method.md`:

1. Replace lines 1–8 (frontmatter, title, intro paragraph's first line) so the file starts:

```markdown
# Deep PR Review — Method

Harness-neutral. An adapter `SKILL.md` loads this file and binds every
`⟨verb⟩` used below to its own tools and models. Run every shell command in
this document with ⟨run⟩.

A recall-biased, multi-angle code review that begins with an **Approach & Architecture Gate** to ensure the fundamental design is sound, and ends as a **GitHub pull request review** formatted the way CodeRabbit formats one: a walkthrough comment, a review body with an actionable-comment count, and one inline comment per finding carrying a machine-consumable fix prompt.
```

2. In the phase diagram, `sequential (or 1 'flash' subagent)` → `sequential (or 1 subagent)`.

3. Replace the section from `## Fan-out & Model Routing` through the end of the `### Verified call shape` subsection (old lines 24–70, ending `losing the others.`) with:

```markdown
## Fan-out

Phases 2 and 3 are embarrassingly parallel and are the whole cost of this
review. Run each as **a single ⟨dispatch-parallel⟩ carrying every entry**, so
twelve angles cost one angle's wall-clock. Dispatching entries one at a time
runs them in series and defeats the point.

Subagents do **not** share your context. Every entry's prompt must be
self-contained:

- the unified diff (or the exact command to regenerate it, plus the target)
- the repo instruction files read in Phase 0 — paste the governing rules, do not
  just name the file; Angle J is worthless without them
- when Go is detected, the target Go version and the relevant sections of
  `⟨skill-dir⟩/reference/go_rules.md` pasted directly into the prompt (Angles D, G, K, L in
  Phase 2; verifiers in Phase 3)
- that angle's mandate, verbatim from below
- the required output shape: a JSON array of candidates with `file`, `line`,
  `summary`, `failure_scenario`

Model routing per role is set by the adapter.
```

4. `**If \`run_subagent\` is unavailable or refused**` → `**If ⟨dispatch-parallel⟩ is unavailable or refused**`.

5. In Phase 0, replace the instruction-file bash block and add the user file:

````markdown
```bash
cat AGENTS.md CLAUDE.md GEMINI.md 2>/dev/null
ls **/CLAUDE.md **/AGENTS.md **/GEMINI.md 2>/dev/null   # a directory's file governs only files at or below it
```

Also read ⟨user-instructions⟩.
````

6. Go detection item 2: ``Read `~/.gemini/skills/deep-pr-review/reference/go_rules.md` (or `reference/go_rules.md`).`` → ``Read `⟨skill-dir⟩/reference/go_rules.md`.``

7. Phase 2 intro: ``One `run_subagent` call, twelve entries,`` → `One ⟨dispatch-parallel⟩, twelve entries,`.

8. Both **Exact SHA Inspection** bullets (Phase 2 guardrails and Phase 3 guardrails): ``Always inspect code using `git show <headRefOid>:<path>` or `git diff <base>..<headRefOid>` `` → ``Always inspect code with ⟨read-at-sha⟩ at `<headRefOid>`, or `git diff <base>..<headRefOid>`, `` (Phase 3 wording: ``Use ⟨read-at-sha⟩ at `<headRefOid>` or `git diff <base>..<headRefOid>` ``).

9. Phase 3: ``Then one `run_subagent` call with`` → `Then one ⟨dispatch-parallel⟩ with`.

10. Phase 5: ``Read `~/.gemini/skills/deep-pr-review/reference/format.md` `` → ``Read `⟨skill-dir⟩/reference/format.md` ``.

11. Phase 6 script path: `~/.gemini/skills/deep-pr-review/scripts/post-review.sh` → `⟨skill-dir⟩/scripts/post-review.sh`.

12. Phase 6: `payload; post only after they confirm, unless they already said to post.` → `payload, and confirm with ⟨ask-user⟩; post only after they confirm, unless they already said to post.`

Then fix `skills-shared/deep-pr-review/reference/go_rules.md` §7.1/§7.2 (lines 626–646): every `` `~/.gemini/skills/golang-X` `` → `` `golang-X` ``:

```bash
sed -i -E 's#`~/\.gemini/skills/(golang-[a-z-]+)`#`\1`#g' skills-shared/deep-pr-review/reference/go_rules.md
grep -n '~/\.gemini' skills-shared/deep-pr-review/reference/go_rules.md   # expect: no output
```

- [ ] **Step 7: Write the agy adapter**

Create `home/.gemini/skills/deep-pr-review/SKILL.md`:

````markdown
---
name: deep-pr-review
description: Use when asked to deeply review a pull request, run a CodeRabbit-style review, review a diff before merge, or produce severity-ranked PR findings. Runs an architectural approach gate followed by a recall-biased multi-angle review, posting findings as a GitHub review.
---

# Deep PR Review (agy adapter)

The review method is harness-neutral and shared with Claude Code. It lives in
`method.md` next to this file. Read `method.md` in full with `view_file`, then
follow it, applying the bindings below wherever it writes a `⟨verb⟩`.

## Harness mapping

| Verb | Binding |
|---|---|
| `⟨dispatch-parallel⟩` | One `run_subagent` call carrying every entry (entries in one call launch concurrently), `TypeName: "self"`, `Model` per routing below. |
| `⟨read-at-sha⟩` | `run_command`: `git show <sha>:<path>` |
| `⟨run⟩` | `run_command` |
| `⟨ask-user⟩` | `ask_question` |
| `⟨skill-dir⟩` | `~/.gemini/skills/deep-pr-review` |
| `⟨user-instructions⟩` | `~/.gemini/GEMINI.md` and `~/.claude/CLAUDE.md` |

## Model routing

| Entries | Model | Why |
|---|---|---|
| All Phases (Gate, Angles, Verifiers) | `flash` | Gemini 3.8 Flash on high reasoning outperforms 3.1 Pro while executing significantly faster and cheaper |
| Mechanical / Rule Pattern-Matching (Angles F–J) | `flash` (or `flash_lite`) | fast pattern-matching against provided rules |

## Verified call shape

Probed against this install — `agy agents` lists no custom types, and
`TypeName: "self"` is what works:

```json
{
  "Subagents": [
    { "TypeName": "self", "Role": "Angle A — line-by-line diff scan",
      "Model": "flash", "Prompt": "<self-contained angle prompt>" },
    { "TypeName": "self", "Role": "Angle F — reuse",
      "Model": "flash", "Prompt": "<self-contained angle prompt>" }
  ]
}
```

Read the tool's live schema before calling — field names above are what this
install accepted, not a contract. Each subagent returns its own conversation ID;
if one hangs, the subagent-management tool can `list` and `kill` it without
losing the others.
````

- [ ] **Step 8: Run the test — expect PASS**

Run: `bash tests/test_skills_shared.sh`
Expected: `PASS`, exit 0. If a token hit remains, fix that line in `method.md` (not in the test).

- [ ] **Step 9: Prove the verb and link checks can fail**

```bash
a=home/.gemini/skills/deep-pr-review
bak=$(mktemp -d)
cp "$a/SKILL.md" "$bak/SKILL.md"

# a) unbound verb
sed -i '/^| `⟨ask-user⟩`/d' "$a/SKILL.md"
bash tests/test_skills_shared.sh   # expect: FAIL: ... does not bind: ⟨ask-user⟩
cp "$bak/SKILL.md" "$a/SKILL.md"

# b) dead row
printf '| `⟨bogus⟩` | x |\n' >> "$a/SKILL.md"
bash tests/test_skills_shared.sh   # expect: FAIL: ... binds unused verbs: ⟨bogus⟩
cp "$bak/SKILL.md" "$a/SKILL.md"

# c) broken link
mv "$a/scripts" "$bak/scripts-link"
bash tests/test_skills_shared.sh   # expect: FAIL: home/.gemini/skills/deep-pr-review/scripts is not a symlink
mv "$bak/scripts-link" "$a/scripts"

bash tests/test_skills_shared.sh   # expect: PASS
rm -rf "$bak"
```

- [ ] **Step 10: Write `skills-shared/README.md`**

```markdown
# Shared skills

Skills used by both Claude Code and agy. Each lives once here as a
harness-neutral core and is loaded by a thin adapter per harness.

## Layout

    skills-shared/<name>/          # the core: method.md plus any reference/, scripts/
    home/.claude/skills/<name>/    # Claude adapter
    home/.gemini/skills/<name>/    # agy adapter

Each adapter directory contains its own `SKILL.md` and one relative symlink per
top-level core entry, e.g. `method.md -> ../../../../skills-shared/<name>/method.md`.
Linking entries individually (not one `core/` link) keeps paths like
`~/.gemini/skills/<name>/reference/...` valid for existing callers.

## Rules

- **No harness vocabulary in the core.** No tool names (`run_subagent`,
  `view_file`, `AskUserQuestion`, ...) and no harness home paths. Write a
  `⟨verb⟩` instead, and cite companion skills by name.
- **Adapters bind every verb the core uses, and nothing else.** One
  `## Harness mapping` table whose rows start with `` | `⟨verb⟩` ``.
- **Adapters hold no method.** Frontmatter, bindings, model routing, and
  harness-only notes only.
- **Callers cite phases by name**, never by number.

`tests/test_skills_shared.sh` enforces the first two rules and the links.

## Migrating a forked skill

1. `git mv` the more current copy's files into `skills-shared/<name>/`
   (`SKILL.md` becomes `method.md`); fold in anything only the other copy has.
2. Replace tool names and harness paths with verbs.
3. Replace both harness directories with an adapter `SKILL.md` plus links.
4. Run `bash tests/test_skills_shared.sh`.
```

- [ ] **Step 11: Amend the spec's verb table**

In `docs/superpowers/specs/2026-09-16-shared-deep-pr-review-design.md`, add a row after `⟨run-dir⟩` in the **Neutral verbs** table:

```markdown
| `⟨user-instructions⟩` | The user's global instruction file(s) to read during Gather |
```

and add to the **Verb bindings** table:

```markdown
| `⟨user-instructions⟩` | `~/.gemini/GEMINI.md` and `~/.claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
```

- [ ] **Step 12: Commit**

```bash
git add -A skills-shared tests/test_skills_shared.sh home/.gemini/skills/deep-pr-review docs/superpowers/specs/2026-09-16-shared-deep-pr-review-design.md
git status --short   # expect renames R for SKILL.md→method.md, reference, scripts; new adapter, links, test, README
git commit -F - <<'EOF'
refactor(skills): extract deep-pr-review into a harness-neutral core

Move the method into skills-shared/ and replace tool names with verbs
bound by a thin agy adapter, so a Claude adapter can load the same text.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git log --stat -1 | head -20
```

---

### Task 2: Harden `post-review.sh` (head guard, count line, marker)

**Files:**
- Create: `tests/test_post_review.sh`, `tests/fixtures/post_review/diff.txt`, `tests/fixtures/post_review/findings.json`, `tests/fixtures/post_review/gh` (stub)
- Modify: `skills-shared/deep-pr-review/scripts/post-review.sh`

**Interfaces:**
- Consumes: none from Task 1 beyond the moved path.
- Produces: `post-review.sh <pr> <findings.json> [--walkthrough F] [--repo O/R] [--expect-head SHA] [--sequential] [--dry-run]`. With `--expect-head` mismatching the live head: stderr `post-review.sh: PR head moved: expected <A>, live <B>; re-run the review`, exit 1, nothing posted. Review body's first line: `<!-- deep-pr-review head:<sha> -->`. Count line: `**Actionable comments posted: <n_inline> inline + <n_orphan> in body**`.

- [ ] **Step 1: Create fixtures**

`tests/fixtures/post_review/diff.txt`:

```diff
diff --git a/a.go b/a.go
--- a/a.go
+++ b/a.go
@@ -1,2 +1,4 @@
 package a
+func A() {}
+func B() {}
 // end
```

`tests/fixtures/post_review/findings.json`:

```json
[
  {"path": "a.go", "line": 2, "category": "🐛 Correctness & Logic", "severity": "🟠 Major",
   "effort": "🧹 Quick fix", "verdict": "CONFIRMED", "title": "Inline one.",
   "body": "Body one.", "agent_prompt": "Fix A."},
  {"path": "a.go", "line": 40, "category": "🐛 Correctness & Logic", "severity": "🟡 Minor",
   "effort": "🧹 Quick fix", "verdict": "PLAUSIBLE", "title": "Orphan one.",
   "body": "Body two.", "agent_prompt": "Fix orphan."},
  {"path": "a.go", "line": 3, "start_line": 99, "category": "🧹 Maintainability",
   "severity": "🔵 Nitpick", "effort": "🧹 Quick fix", "verdict": "CONFIRMED",
   "title": "Degrades to single line.", "body": "Body three.", "agent_prompt": "Fix B."}
]
```

`tests/fixtures/post_review/gh` (then `chmod +x`):

```bash
#!/usr/bin/env bash
# Stub gh for post-review.sh tests. Logs every call; serves canned output.
printf '%s\n' "$*" >> "$STUB_LOG"
case "$*" in
  "api repos/o/r/pulls/7 --jq .head.sha") echo "$STUB_HEAD" ;;
  "api repos/o/r/pulls/7 --jq .base.sha") echo base000 ;;
  "pr diff 7 --repo o/r") cat "$STUB_DIFF" ;;
  "pr view 7 --repo o/r --json files --jq"*) echo '* `a.go`' ;;
  "api repos/o/r/pulls/7/reviews"*) echo https://example.test/review ;;
  "api repos/o/r/issues/7/comments"*) echo https://example.test/comment ;;
  *) echo "stub gh: unexpected: $*" >&2; exit 99 ;;
esac
```

- [ ] **Step 2: Write the test**

`tests/test_post_review.sh` (then `chmod +x`):

```bash
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
```

- [ ] **Step 3: Run it — expect FAIL**

Run: `bash tests/test_post_review.sh`
Expected: at least `FAIL: head marker is not the first body line`, `FAIL: count line wrong`, and an expect-head failure (`unknown flag: --expect-head`). The three anchoring assertions should already pass — confirm they do; they cover existing behavior.

- [ ] **Step 4: Implement**

In `skills-shared/deep-pr-review/scripts/post-review.sh`:

Usage comment (lines 4–6) becomes:
```bash
#   post-review.sh <pr-number> <findings.json> [--walkthrough FILE] [--repo O/R]
#                  [--expect-head SHA] [--sequential] [--dry-run]
```

Add `expect_head=""` after `sequential=0`, and a case arm after `--repo`:
```bash
    --expect-head) expect_head="${2:?--expect-head needs a SHA}"; shift 2 ;;
```

After `[[ -n $head_sha ]] || die ...` add:
```bash
# Anchors were computed against expected_head; a push during the review would
# attach comments to lines that no longer hold the reviewed code.
if [[ -n $expect_head && $head_sha != "$expect_head" ]]; then
  die "PR head moved: expected $expect_head, live $head_sha; re-run the review"
fi
```

Replace the count `printf` at the top of the review body block with:
```bash
  printf '<!-- deep-pr-review head:%s -->\n' "$head_sha"
  printf '**Actionable comments posted: %s inline + %s in body**\n\n' "$n_inline" "$n_orphan"
```

Update the `usage:` string in the `die` near the top to include `[--expect-head SHA] [--sequential]`.

- [ ] **Step 5: Run — expect PASS; shellcheck**

```bash
bash tests/test_post_review.sh        # expect: PASS
shellcheck -x skills-shared/deep-pr-review/scripts/post-review.sh tests/test_post_review.sh tests/fixtures/post_review/gh tests/test_skills_shared.sh
```
Expected: `PASS`; shellcheck prints nothing.

- [ ] **Step 6: Prove the guard assertion can fail**

Temporarily comment out the `die "PR head moved..."` line, run `bash tests/test_post_review.sh`, confirm `FAIL: expect-head mismatch exited 0` and `FAIL: posted despite head mismatch`, then restore and re-run to `PASS`.

- [ ] **Step 7: Commit**

```bash
git add tests/test_post_review.sh tests/fixtures/post_review skills-shared/deep-pr-review/scripts/post-review.sh
git commit -F - <<'EOF'
fix(deep-pr-review): refuse stale heads and count all findings

A push during a long review moved anchors onto different code, and the
actionable count ignored findings moved into the body. Add a head guard
and a head marker that later runs use to detect a prior review.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: Merge the method (eligibility, angles M–O, phases by name, run dir, callers)

**Files:**
- Create: `tests/test_deep_pr_review_method.sh`
- Modify: `skills-shared/deep-pr-review/method.md`, `skills-shared/deep-pr-review/reference/go_rules.md:3,517,519,531`, `skills-shared/deep-pr-review/reference/format.md:187-188`, `skills-shared/deep-pr-review/scripts/post-review.sh` (Method lines), `home/.gemini/skills/deep-pr-review/SKILL.md` (add `⟨run-dir⟩` row, routing, description), `home/.gemini/skills/adversarial-review/SKILL.md:12,77,90`, `home/.gemini/skills/adversarial-review-loop/SKILL.md:3,14,61,142`

**Interfaces:**
- Consumes: Task 2's `--expect-head`, head marker format `<!-- deep-pr-review head:<sha> -->`.
- Produces: phase headings exactly `## Phase 0 — Eligibility` … `## Phase 7 — Post`; angle headings `### Angle A — ` … `### Angle O — `; verb `⟨run-dir⟩`.

- [ ] **Step 1: Write the structural test**

`tests/test_deep_pr_review_method.sh` (then `chmod +x`):

```bash
#!/usr/bin/env bash
# Structural checks on the merged deep-pr-review method and its callers.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

core=skills-shared/deep-pr-review
m=$core/method.md
fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

want_phases=$'Phase 0 — Eligibility\nPhase 1 — Gather\nPhase 2 — Architecture Gate\nPhase 3 — Find\nPhase 4 — Verify\nPhase 5 — Gap Sweep\nPhase 6 — Render\nPhase 7 — Post'
got_phases=$(grep -E '^## Phase [0-9] — ' "$m" | sed 's/^## //')
[[ $got_phases == "$want_phases" ]] || err "phase headings differ:"$'\n'"$got_phases"

for a in A B C D E F G H I J K L M N O; do
  grep -qE "^### Angle $a — " "$m" || err "missing Angle $a"
done

if grep -nE 'Phase [0-9]' "$core/reference/go_rules.md"; then err "go_rules.md cites phase numbers"; fi
if grep -rn '/tmp/' "$m"; then err "method.md hard-codes /tmp"; fi
if grep -rnE '12-angle|twelve' "$core"; then err "stale 12-angle wording in core"; fi
grep -q -- '--expect-head' "$m" || err "method.md does not use --expect-head"
grep -q -- '--sequential' "$m" || err "method.md does not document --sequential"
grep -qF '<!-- deep-pr-review head:' "$m" || err "method.md does not describe the head marker"

callers=(home/.gemini/skills/adversarial-review/SKILL.md home/.gemini/skills/adversarial-review-loop/SKILL.md)
if grep -nE '12-angle|12 analytical' "${callers[@]}"; then err "callers still say 12 angles"; fi
if grep -nE 'Phase [0-9] of `deep-pr-review`' "${callers[@]}"; then err "callers cite deep-pr-review phases by number"; fi

((fail)) && exit 1
echo PASS
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bash tests/test_deep_pr_review_method.sh`
Expected: phase headings differ, missing Angle M/N/O, go_rules phase numbers, `/tmp/`, stale 12-angle, missing `--expect-head`/`--sequential`/marker, and both caller failures.

- [ ] **Step 3: Rename and renumber phases in `method.md`**

Headings:

| Old | New |
|---|---|
| `## Phase 0 — Gather the diff` | `## Phase 1 — Gather` |
| `## Phase 1 — Approach & Architecture Gate (Altitude Audit)` | `## Phase 2 — Architecture Gate` (keep "(Altitude Audit)" as the first line of body: `Approach & Architecture Gate (Altitude Audit).`) |
| `## Phase 2 — Find candidates (12 angles, up to 8 each)` | `## Phase 3 — Find` (first body line: `15 angles, up to 8 candidates each.`) |
| `## Phase 3 — Dedup and verify (1 vote, 3 states, recall-biased)` | `## Phase 4 — Verify` (first body line: `Dedup, then 1 vote, 3 states, recall-biased.`) |
| `## Phase 4 — Sweep for gaps` | `## Phase 5 — Gap Sweep` |
| `## Phase 5 — Render in CodeRabbit format` | `## Phase 6 — Render` |
| `## Phase 6 — Post` | `## Phase 7 — Post` |

Replace the phase diagram with:

```
Phase 0  Eligibility — skip closed/draft/trivial/already-reviewed  sequential (PR targets only)
Phase 1  Gather — diff, instructions, Go telemetry, expected head   sequential
Phase 2  Architecture Gate (Altitude Audit)                         sequential (or 1 subagent)
         ├── If FLAWED_APPROACH ──► Post Architectural Review & HALT
         └── If SOUND_APPROACH  ──► Proceed to Find
Phase 3  Find — 15 angles, ≤8 candidates each                       FAN OUT — 15 subagents
Phase 4  Verify — dedup + 1-vote 3-state verify (recall-biased)     FAN OUT — 1 subagent per candidate
Phase 5  Gap Sweep — fresh pass, then Verify its candidates          sequential, then FAN OUT
Phase 6  Render in CodeRabbit format                                sequential
Phase 7  Post as a single GitHub review                             sequential
```

Replace every in-body phase reference by name: `read in Phase 0` → `read in Gather`; `Angles D, G, K, L in Phase 2; verifiers in Phase 3` → `Angles D, G, K, L in Find; verifiers in Verify`; `injected into subagent prompts in Phase 2 (Angles D, G, K, L), Phase 3 (verifiers), and Phase 5 (remediation prompts)` → `injected into subagent prompts in Find (Angles D, G, K, L), Verify (verifiers), and Render (remediation prompts)`; `proceed immediately to Phase 2` → `proceed immediately to Find`; `detected in Phase 0` → `detected in Gather`; `through to Phase 3` → `through to Verify`; `Mandatory for Phase 3 Subagents` → `Mandatory for Verify Subagents`; `start until Phase 3 has joined` → `start until Verify has joined`; `what Phase 2 missed` → `what Find missed`; `Run them through Phase 3` → see Step 6; `(Phase 5, \`reference/format.md\`)` → `(Render, \`reference/format.md\`)`; `skip Phase 6 entirely` → `skip Post entirely`; Fan-out's `Phases 2 and 3 are embarrassingly parallel` → `Find and Verify are embarrassingly parallel`. Replace `twelve` / `Twelve` / `12` angle counts with `fifteen` / `15` (Fan-out paragraph, Find intro "One ⟨dispatch-parallel⟩, fifteen entries", Gate intro "Before dispatching 15 subagents"). Verify: `grep -nE 'Phase [0-9]' "$m" | grep -v '^[0-9]*:## Phase'` prints only diagram lines.

- [ ] **Step 4: Add Phase 0 — Eligibility (before Gather)**

````markdown
## Phase 0 — Eligibility

PR targets only. **Local mode** — a branch or working-tree target, or an
invocation by another skill that asks for local mode — skips this phase and
Post, and prints the rendered output instead.

```bash
gh pr view <N> --json state,isDraft,author,headRefOid,files \
  --jq '{state, isDraft, bot: .author.is_bot, head: .headRefOid, files: [.files[].path]}'
```

Stop, telling the user why, when any holds:

- `state` is `CLOSED` or `MERGED`.
- `isDraft` is true, unless the user named this PR explicitly.
- Trivial: `bot` is true, or every path in `files` is a lockfile
  (`go.sum`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `Cargo.lock`,
  `uv.lock`, `poetry.lock`).
- Already reviewed at this head:

  ```bash
  marker='.[] | select(.body // "" | test("<!-- deep-pr-review head:[0-9a-f]+ -->"))
          | (.body | capture("deep-pr-review head:(?<sha>[0-9a-f]+)").sha) + " " + .html_url'
  gh api "repos/{owner}/{repo}/pulls/<N>/reviews" --paginate --jq "$marker"
  gh api "repos/{owner}/{repo}/issues/<N>/comments" --paginate --jq "$marker"
  ```

  Each output line is `<sha> <url>`.

  A marker whose SHA equals `head` → stop with "already reviewed at <sha>",
  linking the review. A marker with an older SHA → continue with a full review;
  the walkthrough's first paragraph links that prior review.

Record `head` as `expected_head` for Post.
````

- [ ] **Step 5: Add Angles M, N, O (after Angle L, before the cleanup note)**

````markdown
### Angle M — history and blame
For each changed range, read its history at the base commit:

```bash
git log -L <start>,<end>:<path> --format='%h %s' -n 20 <base>
git blame -L <start>,<end> <base> -- <path>
```

Flag a change that reverts or weakens a deliberate earlier fix: a guard, retry,
lock, or check whose introducing commit message names the bug it prevented.
Cite the commit hash and quote its subject in `failure_scenario`.

### Angle N — prior PR feedback
For each file the diff touches, map its recent commits to merged PRs and read
their review feedback (cap: 10 distinct PRs total):

```bash
git log --format=%H -n 20 <base> -- <path>
gh api "repos/{owner}/{repo}/commits/<sha>/pulls" --jq '.[] | select(.merged_at) | .number'
gh api "repos/{owner}/{repo}/pulls/<n>/comments" --paginate --jq '.[] | {path, line, body, html_url}'
gh api "repos/{owner}/{repo}/pulls/<n>/reviews" --jq '.[] | select(.body != "") | {body, html_url}'
```

Flag feedback that applies again to the new code: quote the original comment,
link its `html_url`, and name the new line that repeats the objected-to pattern.
Return nothing when the repo has no GitHub remote.

### Angle O — code-comment compliance
Read comments in and adjacent to every changed function that state a contract —
"caller holds mu", "must be idempotent", "never returns nil", doc-comment
preconditions and postconditions. Flag changes that violate one, quoting the
comment and the violating line.
````

Update the cleanup note's ranking sentence: `**Correctness bugs (Angles A–E, K, L) always outrank` → `**Correctness bugs (Angles A–E, K, L, M, O) always outrank`, and append: `Angle N findings rank by the category of the feedback they quote.`

In the Go Dynamic Rule Injection bullet list nothing changes (M–O are language-agnostic).

- [ ] **Step 6: Verify additions — N rule and second round**

In Phase 4 — Verify, after the Go Verification Guardrails bullet list, add:

```markdown
- **Prior-feedback findings (Angle N)**: CONFIRMED only when the pattern the
  quoted comment objected to is present at the cited new line. Otherwise
  REFUTED — quote the new line.
```

In Phase 5 — Gap Sweep, replace `list. Run them through Phase 3. If nothing is new, return nothing — do not pad.` with:

```markdown
list. Verify them with a second ⟨dispatch-parallel⟩ under the Verify rules —
one verifier per candidate — and merge the survivors into the list. If nothing
is new, return nothing and skip the second round — do not pad.
```

- [ ] **Step 7: Render and Post use the run dir, head guard, and `--sequential`**

In Phase 6 — Render, before `Write each finding into a JSON array`, add:
`Create ⟨run-dir⟩ once for this review and write every artifact below into it.`
Replace `` at `/tmp/deep-pr-review-findings.json`: `` with `` at `<run-dir>/findings.json`: ``.

Replace the Phase 7 — Post opening block and the walkthrough sentence with:

````markdown
Immediately before posting, re-run the Eligibility checks. If any now stops the
review (closed, converted to draft, a marker at this head from a concurrent run),
stop without posting.

```bash
⟨skill-dir⟩/scripts/post-review.sh \
  <pr-number> <run-dir>/findings.json \
  --expect-head <expected_head> \
  [--walkthrough <run-dir>/walkthrough.md] [--repo OWNER/NAME] [--sequential] [--dry-run]
```

Write the walkthrough (Render, `reference/format.md`) to `<run-dir>/walkthrough.md`
first; the script posts it as a separate issue comment before the review.

`--expect-head` makes the script refuse if the PR head moved during the review —
the anchors would land on different code. Re-run the review from Eligibility.

Pass `--sequential` when ⟨dispatch-parallel⟩ was unavailable and the angles ran
in this context; the review body's Method line then says so.

The script writes `<!-- deep-pr-review head:<sha> -->` as the first line of the
review body; Eligibility uses it to detect a prior review. When the Architecture
Gate halts, put the same marker as the first line of the architectural review
comment.
````

- [ ] **Step 8: Fix `go_rules.md` phase references and 15-angle wording**

```bash
f=skills-shared/deep-pr-review/reference/go_rules.md
sed -i \
  -e 's/finders (Phases 1 & 3), verifiers (Phase 2), and prompt generators (Phase 4)/finders (Find), verifiers (Verify), and prompt generators (Render)/' \
  -e 's/^## 5\. Phase 2 Verifier Guardrails/## 5. Verify-Phase Guardrails/' \
  -e 's/When acting as a Phase 2 Verifier/When acting as a Verify-phase verifier/' \
  -e 's/^## 6\. Phase 4 AI Remediation Prompt Conventions/## 6. Render-Phase AI Remediation Prompt Conventions/' \
  "$f"
grep -nE 'Phase [0-9]' "$f"   # expect: no output
```

In `reference/format.md` lines 187–188 and both Method `printf`s in `scripts/post-review.sh`, replace `12-angle recall-biased review (7 correctness + 3 cleanup + altitude + conventions)` (line-wrapped in both) with `15-angle recall-biased review (9 correctness + 3 cleanup + altitude + conventions + prior feedback)`, re-wrapping at ~78 columns. Re-run `bash tests/test_post_review.sh` → `PASS`.

- [ ] **Step 9: Update the agy adapter**

In `home/.gemini/skills/deep-pr-review/SKILL.md`:
- description: `...followed by a recall-biased multi-angle review...` → `...Runs eligibility checks and an architectural approach gate followed by a 15-angle recall-biased review, posting findings as a GitHub review.`
- Add row after `⟨skill-dir⟩`: `` | `⟨run-dir⟩` | Once per review: `run_command` `mktemp -d "${TMPDIR:-/tmp}/deep-pr-review.XXXXXX"`; reuse the printed path. | ``
- Replace the Model routing table body with:

```markdown
| Role | Model | Why |
|---|---|---|
| Architecture Gate, Finders A–I and K–O, Verifiers | `flash` | Gemini 3.8 Flash on high reasoning outperforms 3.1 Pro while executing significantly faster and cheaper |
| Finder J (conventions) | `flash_lite` | quote-the-rule / quote-the-line matching |
| Gap Sweep | main context | needs the deduplicated list |
```

- [ ] **Step 10: Update callers**

`home/.gemini/skills/adversarial-review/SKILL.md`:
- line 12: `running a 12-angle recall-biased review` → `running a 15-angle recall-biased review`
- line 77: `Mandate to execute the 12-angle review` → `Mandate to execute the 15-angle review`
- line 90: ``Run in **local mode**: skip GitHub posting (Phase 5 of `deep-pr-review`).`` → ``Run in **local mode**: skips the Eligibility and Post phases of `deep-pr-review`.``

`home/.gemini/skills/adversarial-review-loop/SKILL.md`:
- line 3: no count present — leave.
- line 14: `across 12 analytical angles` → `across 15 analytical angles`
- line 61: `all 12 analytical review angles` → `all 15 analytical review angles`
- line 142: `execution of the 12-angle review` → `execution of the 15-angle review`

Confirm no other reference: `grep -rnE '12[- ]angle|12 analytical|Phase [0-9] of .deep-pr-review' home/` → no output.

- [ ] **Step 11: Run all tests — expect PASS**

```bash
bash tests/test_deep_pr_review_method.sh && bash tests/test_skills_shared.sh && bash tests/test_post_review.sh
```
Expected: three `PASS` lines. `test_skills_shared.sh` would fail if `⟨run-dir⟩` were used but unbound — to see it, delete the new row, run, confirm `does not bind: ⟨run-dir⟩`, restore.

- [ ] **Step 12: Prove the method test can fail**

```bash
sed -i 's/^### Angle N — /### Angle X — /' skills-shared/deep-pr-review/method.md
bash tests/test_deep_pr_review_method.sh   # expect: FAIL: missing Angle N
sed -i 's/^### Angle X — /### Angle N — /' skills-shared/deep-pr-review/method.md
bash tests/test_deep_pr_review_method.sh   # expect: PASS
```

- [ ] **Step 13: Commit**

```bash
git add -A skills-shared tests/test_deep_pr_review_method.sh home/.gemini/skills/deep-pr-review/SKILL.md home/.gemini/skills/adversarial-review/SKILL.md home/.gemini/skills/adversarial-review-loop/SKILL.md
git commit -F - <<'EOF'
feat(deep-pr-review): add eligibility and history-aware angles

Skip closed, draft, trivial and already-reviewed PRs, and add blame,
prior-feedback and code-comment angles from the code-review plugin.
Name phases instead of numbering them so inserts stop staling callers.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: Claude Code adapter

**Files:**
- Create: `home/.claude/skills/deep-pr-review/SKILL.md`, symlinks `home/.claude/skills/deep-pr-review/{method.md,reference,scripts}`

**Interfaces:**
- Consumes: the verb set `⟨dispatch-parallel⟩ ⟨read-at-sha⟩ ⟨run⟩ ⟨ask-user⟩ ⟨skill-dir⟩ ⟨run-dir⟩ ⟨user-instructions⟩` as used by `method.md` after Task 3.

- [ ] **Step 1: Create links only, then run the test — expect FAIL**

```bash
mkdir -p home/.claude/skills/deep-pr-review
cd home/.claude/skills/deep-pr-review
ln -s ../../../../skills-shared/deep-pr-review/method.md method.md
ln -s ../../../../skills-shared/deep-pr-review/reference reference
ln -s ../../../../skills-shared/deep-pr-review/scripts scripts
cd /home/hobe/dotfiles
bash tests/test_skills_shared.sh
```
Expected: `FAIL: home/.claude/skills/deep-pr-review: missing SKILL.md`.

- [ ] **Step 2: Write the adapter**

`home/.claude/skills/deep-pr-review/SKILL.md`:

````markdown
---
name: deep-pr-review
description: Use only when the user explicitly asks for deep-pr-review or a CodeRabbit-style deep review of a PR, branch, or diff. Recall-biased 15-angle review with eligibility checks and an architecture gate, posted as a GitHub review. Not for routine /pr-review or /code-review requests.
---

# Deep PR Review (Claude Code adapter)

The review method is harness-neutral and shared with agy. It lives in
`method.md` next to this file. Read `method.md` in full with the Read tool,
then follow it, applying the bindings below wherever it writes a `⟨verb⟩`.

## Harness mapping

| Verb | Binding |
|---|---|
| `⟨dispatch-parallel⟩` | Multiple `Agent` tool calls in a **single message**, one per entry, `subagent_type: "general-purpose"`, `model` per routing below. Do not use the `Workflow` tool — it requires explicit user opt-in. |
| `⟨read-at-sha⟩` | `Bash`: `git show <sha>:<path>` |
| `⟨run⟩` | `Bash` |
| `⟨ask-user⟩` | `AskUserQuestion` |
| `⟨skill-dir⟩` | `~/.claude/skills/deep-pr-review` |
| `⟨run-dir⟩` | Once per review: `Bash` `mktemp -d "${TMPDIR:-/tmp}/deep-pr-review.XXXXXX"`; reuse the printed path. |
| `⟨user-instructions⟩` | `~/.claude/CLAUDE.md` |

## Model routing

| Role | Model | Why |
|---|---|---|
| Architecture Gate | `opus` | One judgment that can halt the whole review; ambiguous design reasoning |
| Finders A–I and K–O | `sonnet` | Standard code reading and cross-file tracing |
| Finder J (conventions) | `haiku` | Quote-the-rule / quote-the-line matching |
| Verifiers | `sonnet` | Must construct refutations from code; cheaper tiers wave candidates through |
| Gap Sweep | main context | Needs the deduplicated list |

Before each dispatch, state the model chosen per role and why in one line
(the user's CLAUDE.md requires it).

## Harness notes

- Keep one verifier per candidate even when there are many; if one message
  cannot carry every `Agent` call, send consecutive messages of parallel calls —
  that is still a fan-out, not a sequential run.
- Subagents return their result as the `Agent` tool result; do not poll or
  schedule wakeups for them.
````

- [ ] **Step 3: Run tests — expect PASS; prove a Claude-side failure**

```bash
bash tests/test_skills_shared.sh   # expect: PASS
sed -i '/^| `⟨run-dir⟩`/d' home/.claude/skills/deep-pr-review/SKILL.md
bash tests/test_skills_shared.sh   # expect: FAIL: home/.claude/skills/deep-pr-review/SKILL.md does not bind: ⟨run-dir⟩
```
Re-add the `⟨run-dir⟩` row exactly as in Step 2, then `bash tests/test_skills_shared.sh` → `PASS`.

- [ ] **Step 4: Commit**

```bash
git add home/.claude/skills/deep-pr-review
git commit -F - <<'EOF'
feat(skills): add claude adapter for deep-pr-review

Bind the shared method's verbs to Agent, Bash and AskUserQuestion with
per-role model routing, and restrict triggering to explicit requests so
it does not preempt /pr-review or /code-review.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: CI coverage

**Files:**
- Modify: `.github/workflows/dotfiles.yml` (shellcheck job; new `tests` job)

- [ ] **Step 1: Add shellcheck coverage**

After the `Run shellcheck on Claude hooks` step, add:

```yaml
      - name: Run shellcheck on shared skill scripts and script tests
        run: |
          shellcheck -x \
            skills-shared/*/scripts/*.sh \
            tests/test_skills_shared.sh \
            tests/test_post_review.sh \
            tests/test_deep_pr_review_method.sh \
            tests/fixtures/post_review/gh
```

- [ ] **Step 2: Add a tests job**

After the `syntax` job:

```yaml
  skills:
    name: Shared skill tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Skills-shared pattern
        run: bash tests/test_skills_shared.sh

      - name: deep-pr-review method structure
        run: bash tests/test_deep_pr_review_method.sh

      - name: post-review.sh behavior
        run: bash tests/test_post_review.sh
```

- [ ] **Step 3: Validate locally**

```bash
shellcheck -x skills-shared/*/scripts/*.sh tests/test_skills_shared.sh tests/test_post_review.sh tests/test_deep_pr_review_method.sh tests/fixtures/post_review/gh
python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/dotfiles.yml")); print("yaml ok")'
git ls-files -s skills-shared/deep-pr-review/scripts/post-review.sh tests/*.sh tests/fixtures/post_review/gh | awk '{print $1, $4}'
```
Expected: shellcheck silent; `yaml ok`; every mode `100755` (checkout on CI does not need `chmod`; `bash tests/...` does not need +x, but the stub `gh` must be executable). Fix modes with `git update-index --chmod=+x <file>` if needed.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/dotfiles.yml
git commit -F - <<'EOF'
ci: run shared skill tests and shellcheck their scripts

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 6: Install and live verification

No new files. Every check here is observed, not assumed; record outputs in the PR description.

- [ ] **Step 1: Install dry run and stow**

```bash
./install.sh -n -c 2>&1 | grep -iE 'deep-pr-review|conflict|error' || echo "no deep-pr-review/conflict lines"
stow -n -v -R -t "$HOME" --ignore=glow --ignore='\.claude' --ignore='settings\.json' home 2>&1 | grep -iE 'deep-pr-review|conflict'
```
Expected: no conflicts. Then run the real install (`./install.sh -c`) and:

```bash
readlink -f ~/.claude/skills/deep-pr-review/method.md
readlink -f ~/.gemini/skills/deep-pr-review/reference/go_rules.md
head -1 ~/.claude/skills/deep-pr-review/method.md ~/.gemini/skills/deep-pr-review/method.md
test -x ~/.gemini/skills/deep-pr-review/scripts/post-review.sh && echo exec-ok
```
Expected: both resolve under `/home/hobe/dotfiles/skills-shared/deep-pr-review/`; both heads print `# Deep PR Review — Method`; `exec-ok`.

- [ ] **Step 2: Claude local-mode run**

In a fresh Claude Code session in a repo with a small uncommitted or branch diff, ask: "run deep-pr-review on this branch in local mode". Confirm: `method.md` is read; the Gate dispatches with `opus`; Find is one message with 15 `Agent` calls (J on `haiku`, the rest `sonnet`); verifiers are one per candidate on `sonnet`; nothing is posted; output renders in CodeRabbit format.

- [ ] **Step 3: agy local-mode run and posting dry run**

In agy on the same diff, run the skill in local mode; confirm one `run_subagent` call with 15 entries. Then, against a real open PR the user nominates:
`~/.gemini/skills/deep-pr-review/scripts/post-review.sh <N> <run-dir>/findings.json --expect-head <head> --dry-run` — confirm the marker is the first body line and the count line format.

- [ ] **Step 4: Eligibility on a reviewed head**

Against a PR whose current head already carries a posted marker (if none exists yet, a closed PR), run the skill in PR-target mode. Confirm it stops in Eligibility, before Gather, stating the reason, and posts nothing.

- [ ] **Step 5: Pre-push gates (per CLAUDE.md)**

Run `quality-lenses` in diff mode and `pr-review-toolkit:review-pr` on the branch diff; triage findings with the user before pushing. Then push the branch and open a PR (`/pr-create`).
