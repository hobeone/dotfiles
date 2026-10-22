#!/usr/bin/env bash
# Run the optional deterministic analyzers that apply to a diff and emit one
# normalised JSON result. Every tool is optional, but a tool that APPLIED to
# the diff and did not run is reported (not_installed / failed) so the review
# can say so; absence never fails the run.
#
# Usage:
#   run-analyzers.sh --base REF [--head REF] [--out FILE] [--all-lines]
#   run-analyzers.sh --summarize FILE
#   run-analyzers.sh --inventory
#
# --base REF     compare against REF. With --head: BASE...HEAD (merge-base
#                semantics). Without it: the working tree against REF itself.
# --head REF     analyse that commit. Without it, the working tree vs BASE plus
#                untracked files. A --head other than the checked-out HEAD (or a
#                dirty tree) is analysed in a throwaway detached worktree; the
#                commit must already exist locally.
# --out FILE     write the JSON there instead of stdout
# --all-lines    keep findings on unchanged lines too (default: changed lines only;
#                the rest are counted per tool as outside_diff)
# --summarize F  print the review-body markdown (run / NOT-run lines and a
#                coverage table) and exit
# --inventory    print which analyzers this machine has, what each checks and
#                what a missing one means for the review, then exit 0. Needs no
#                git repository; the review shows it before it starts.
#
# Env ANALYZER_BIN_DIR: when set, ONLY executables in that directory count as
# installed (test hook); otherwise PATH is searched.
#
# Exit 0 whenever analysis completed, even if every tool was missing; 1 on
# usage or git errors.
#
# Upstream formats implemented. Verified live against these versions (clean
# and seeded files): shellcheck 0.10.0, trufflehog 3.99.3, gitleaks 8.30.1,
# semgrep 1.182.0, golangci-lint 2.15.0, ruff 0.17.1, actionlint 1.7.12,
# hadolint 2.15.1, osv-scanner 2.7.0. (memory) marks a detail not yet observed:
#   ShellCheck     0.10  -f json1 -> {"comments":[{file,line,level,code,message}]}
#   trufflehog     3.x   filesystem --json --no-update --no-verification: NDJSON,
#                        SourceMetadata.Data.Filesystem.{file,line}, DetectorName
#   gitleaks       8.19+ `dir` / <8.19 `detect --no-git`; --report-format json
#                        --report-path F --redact --exit-code 0: array of
#                        {RuleID,File,StartLine}
#   semgrep        1.x   scan --json --metrics=off --quiet: {results:[{check_id,path,
#                        start.line,extra.{message,severity}}],errors:[]}; extra.lines
#                        can be "requires login", so a suppression is read from the file
#   golangci-lint  v1 `--out-format json` (stdout) / v2 `--output.json.path F`:
#                        {"Issues":[{FromLinter,Text,Pos.{Filename,Line}}]}; v2 run live
#   ruff           0.x   check --output-format json --exit-zero: [{code,message,
#                        filename(abs),location.row}]
#   actionlint     1.7   -format '{{json .}}': [{message,filepath,line,kind}] (docs: array)
#   hadolint       2.x   -f json --no-fail: [{code,file,level,line,message}]
#   osv-scanner    v1 `--format json -L F` / v2 `scan source --format json -L F`:
#                        {results:[{source.path,packages:[{package,vulnerabilities:[{id,summary}]}]}]};
#                        exit 1 = vulnerabilities found, 128 = no packages (memory: 128)
set -euo pipefail

die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }
usage() { sed -n '2,31p' "$0"; }

# ---------------------------------------------------------------------------
# What each analyzer checks. One source for the kick-off inventory and the
# review body. "secrets" is trufflehog, else gitleaks.
# ---------------------------------------------------------------------------
ANALYZERS=(shellcheck secrets semgrep golangci-lint ruff actionlint hadolint osv-scanner)
BINARIES=(shellcheck trufflehog gitleaks semgrep golangci-lint ruff actionlint hadolint osv-scanner)
covers() {
  case $1 in
    shellcheck)    echo "shell-script bugs: quoting, word splitting, unsafe expansions" ;;
    secrets)       echo "credentials and tokens committed in changed files" ;;
    semgrep)       echo "rule-based security and bug patterns in source code" ;;
    golangci-lint) echo "Go vet, staticcheck and common Go bugs" ;;
    ruff)          echo "Python lint: unused or undefined names, common bugs" ;;
    actionlint)    echo "GitHub Actions workflow errors and script injection" ;;
    hadolint)      echo "Dockerfile pitfalls: unpinned images and packages" ;;
    osv-scanner)   echo "known vulnerabilities (CVEs) in dependency manifests" ;;
  esac
}
covers_json() {
  local a
  for a in "${ANALYZERS[@]}"; do jq -n --arg k "$a" --arg v "$(covers "$a")" '{($k): $v}'; done | jq -sc add
}

find_tool() {
  if [[ -n ${ANALYZER_BIN_DIR+x} ]]; then
    [[ -f $ANALYZER_BIN_DIR/$1 && -x $ANALYZER_BIN_DIR/$1 ]] && printf '%s' "$ANALYZER_BIN_DIR/$1"
  else
    command -v "$1"
  fi
}

# probe_binaries — BIN_PATH[bin] / BIN_VER[bin] for every installed binary.
# The version is the first dotted number the tool reports ("" if none).
declare -A BIN_PATH=() BIN_VER=()
probe_binaries() {
  local b p
  for b in "${BINARIES[@]}"; do
    p=$(find_tool "$b") || continue
    BIN_PATH[$b]=$p
    BIN_VER[$b]=$({ SEMGREP_ENABLE_VERSION_CHECK=0 "$p" --version 2>&1 || "$p" version 2>&1; } </dev/null \
      | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
  done
}

# engine_for ANALYZER — the installed binary that would run it, or "".
engine_for() {
  if [[ $1 == secrets ]]; then
    if [[ -n ${BIN_PATH[trufflehog]:-} ]]; then echo trufflehog
    elif [[ -n ${BIN_PATH[gitleaks]:-} ]]; then echo gitleaks; fi
  elif [[ -n ${BIN_PATH[$1]:-} ]]; then
    echo "$1"
  fi
}

# ---------------------------------------------------------------------------
# --inventory: plain text for the user before the review starts.
# ---------------------------------------------------------------------------
inventory() {
  local a e have=0 missing=() what installer
  probe_binaries
  echo "Static analyzers available to deep-pr-review on this machine:"
  for a in "${ANALYZERS[@]}"; do
    e=$(engine_for "$a")
    if [[ -n $e ]]; then
      have=$((have + 1))
      what=$e; [[ $a == secrets ]] && what="secrets ($e)"
      printf '  ✓ %-22s %-9s %s\n' "$what" "${BIN_VER[$e]:-?}" "$(covers "$a")"
    else
      missing+=("$a")
      printf '  ✗ %-22s %-9s %s\n' "$a" missing "$(covers "$a")"
    fi
  done
  echo
  if ((${#missing[@]} == 0)); then
    echo "All ${#ANALYZERS[@]} analyzers are available: every one that applies to the diff will run."
    return 0
  fi
  echo "$have of ${#ANALYZERS[@]} analyzers are available."
  echo "What this means: a missing analyzer cannot run. If it applies to the diff (for"
  echo "example semgrep when source files changed), that area is reviewed by the agent"
  echo "angles only, with no deterministic tool behind them, and the review body lists"
  echo "it under \"Static analyzers NOT run\". A missing analyzer that does not apply to"
  echo "the diff costs nothing."
  # Present only in the dotfiles checkout this skill ships from.
  installer="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../scripts/install_analyzers.sh"
  if [[ -x $installer ]]; then
    echo "Install the missing ones with: $(readlink -f "$installer")"
  fi
}

# ---------------------------------------------------------------------------
# --summarize: review-body markdown from a result file. Paragraphs are
# separated by blank lines here, so callers print the output as-is.
# ---------------------------------------------------------------------------
summarize() {
  [[ -r $1 ]] || die "cannot read result file: $1"
  jq -r --argjson covers "$(covers_json)" '
    def pl($n; $w): "\($n) \($w)\(if $n == 1 then "" else "s" end)";
    def lbl: if .tool == "secrets" and .engine then "secrets/\(.engine)" else .tool end;
    def join_or_none: if length == 0 then "none" else join(" · ") end;
    def gap: .status == "not_installed" or .status == "failed";
    def what: $covers[.tool] // "";
    def annot: if (.annotated // 0) > 0 then ", \(.annotated) already annotated" else "" end;
    def state:
      if .status == "ran" then "✅ ran on \(pl(.files; "file")): \(pl(.findings; "finding")), \(.outside_diff) outside diff\(annot)"
      elif .status == "not_installed" then "⚠️ not installed: \(pl(.files; "changed file")) unchecked"
      elif .status == "failed" then "⚠️ failed: \(pl(.files; "changed file")) unchecked"
      else "➖ no matching files" + (if .installed == false then " (not installed)" else "" end) end;
    (.tools | map(select(gap))) as $gaps
    | "**Static analyzers run:** "
      + (.tools | map(select(.status == "ran")
          | "\(lbl) (\(pl(.files; "file")), \(pl(.findings; "finding")), \(.outside_diff) outside diff\(annot))")
        | join_or_none),
    "",
    "**Static analyzers NOT run:** "
      + ($gaps | map(
            (if .status == "not_installed"
             then "\(.tool) — not installed (applies to \(pl(.files; "changed file")))"
             else "\(.tool) — failed: \(.reason // "unknown") (applies to \(pl(.files; "changed file")))" end)
            + (if what != "" then " → unchecked: \(what)" else "" end))
        | join_or_none),
    (if (.tools | length) == 0 then empty else
      "",
      "<details>",
      "<summary>🔍 Static analyzer coverage: \(.tools | map(select(.installed == true or .status == "ran")) | length) of \(.tools | length) available to the reviewer</summary>",
      "",
      "| Analyzer | Version | This diff | What it checks |",
      "|---|---|---|---|",
      (.tools[] | "| \(lbl) | \(.version // "—") | \(state) | \(what) |"),
      "",
      (if ($gaps | length) > 0
       then "**What this means:** the ⚠️ rows applied to this diff but did not run, so those areas were reviewed by the agent angles only, with no deterministic tool behind them. Treat a clean result there as weaker evidence."
       else "**What this means:** every analyzer that applied to this diff ran; ➖ rows had no matching changed files." end),
      "",
      "</details>" end)
  ' "$1"
}

base=""; head=""; out=""; all_lines=0; sum_file=""
while (($#)); do
  case "$1" in
    --base)       base="${2:?--base needs a ref}"; shift 2 ;;
    --head)       head="${2:?--head needs a ref}"; shift 2 ;;
    --out)        out="${2:?--out needs a file}"; shift 2 ;;
    --all-lines)  all_lines=1; shift ;;
    --summarize)  sum_file="${2:?--summarize needs a file}"; shift 2 ;;
    --inventory)  inventory; exit 0 ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown argument: $1" ;;
  esac
done

command -v jq >/dev/null || die "jq is not installed"
if [[ -n $sum_file ]]; then summarize "$sum_file"; exit 0; fi
[[ -n $base ]] || die "usage: run-analyzers.sh --base REF [--head REF] [--out FILE] [--all-lines] | --summarize FILE"

toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$toplevel"
base_sha=$(git rev-parse --verify -q "${base}^{commit}") || die "cannot resolve --base '$base'"
head_sha=""
if [[ -n $head ]]; then
  head_sha=$(git rev-parse --verify -q "${head}^{commit}") || die "cannot resolve --head '$head' (is the commit fetched locally?)"
fi

tmp=$(mktemp -d)
wt_added=0
cleanup() {
  if ((wt_added)); then
    git -C "$toplevel" worktree remove --force "$tmp/wt" >/dev/null 2>&1 || true
    git -C "$toplevel" worktree prune >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Analysis root, changed files, changed line ranges.
# ---------------------------------------------------------------------------
root=$toplevel
if [[ -n $head_sha ]]; then
  cur=$(git rev-parse HEAD)
  if [[ $head_sha != "$cur" || -n $(git status --porcelain --untracked-files=no) ]]; then
    git worktree add -q --detach "$tmp/wt" "$head_sha" >/dev/null 2>&1 || die "cannot create worktree at $head_sha"
    wt_added=1
    root=$tmp/wt
  fi
  range=("$base_sha...$head_sha")
  head_label=$head_sha
else
  range=("$base_sha")
  head_label=WORKTREE
fi

mapfile -d '' changed < <(git diff -z --name-only --diff-filter=ACMR "${range[@]}")
untracked=()
if [[ -z $head_sha ]]; then
  mapfile -d '' untracked < <(git ls-files -z --others --exclude-standard)
  changed+=("${untracked[@]}")
fi

# Added-line ranges from `git diff -U0` hunk headers: "+a,b" -> a..a+b-1.
# Untracked files are all-added.
git -c core.quotepath=off diff -U0 --no-color --diff-filter=ACMR "${range[@]}" | awk '
  /^\+\+\+ / { p = substr($0, 7); sub(/\t.*$/, "", p); next }
  /^@@ / {
    if (!match($0, /\+[0-9]+(,[0-9]+)?/)) next
    spec = substr($0, RSTART + 1, RLENGTH - 1)
    n = split(spec, a, ",")
    s = a[1] + 0; c = (n > 1) ? a[2] + 0 : 1
    if (c > 0) printf "%s\t%d\t%d\n", p, s, s + c - 1
  }' > "$tmp/ranges.tsv"
for f in ${untracked[@]+"${untracked[@]}"}; do
  printf '%s\t1\t2147483647\n' "$f" >> "$tmp/ranges.tsv"
done

# ---------------------------------------------------------------------------
# Plumbing shared by every tool.
# ---------------------------------------------------------------------------
: > "$tmp/tools.jsonl"
: > "$tmp/findings.jsonl"
probe_binaries

# finish TOOL STATUS FILES [REASON] [ENGINE] — also records whether the tool is
# installed and its version, so the review body can show the whole inventory,
# not only the tools this diff needed.
finish() {
  local engine=${5:-}
  [[ -n $engine ]] || engine=$(engine_for "$1")
  local installed=false version=""
  if [[ -n $engine && -n ${BIN_PATH[$engine]:-} ]]; then installed=true; version=${BIN_VER[$engine]:-}; fi
  [[ $1 == secrets ]] || engine=""
  jq -nc --arg tool "$1" --arg status "$2" --argjson files "$3" \
         --arg reason "${4:-}" --arg engine "$engine" \
         --argjson installed "$installed" --arg version "$version" \
    '{tool: $tool, status: $status, files: $files, installed: $installed}
     + (if $version != "" then {version: $version} else {} end)
     + (if $reason != "" then {reason: $reason} else {} end)
     + (if $engine != "" then {engine: $engine} else {} end)' >> "$tmp/tools.jsonl"
}

tail_of() { tail -c 300 "$1" 2>/dev/null | tr '\n\t' '  '; }

# run_in DIR OUTFILE ERRFILE CMD... — sets rc; never trips set -e.
rc=0
run_in() {
  local dir=$1 o=$2 e=$3
  shift 3
  rc=0
  (cd "$dir" && "$@") >"$o" 2>"$e" || rc=$?
}

# not_run TOOL NFILES MISSING_MSG — records not_installed.
not_installed() { finish "$1" not_installed "$2" "$3"; }

# simple_tool TOOL NFILES "OKRC..." JQPROG CMD... — run in $root, check the exit
# code against the allowed list, normalise stdout through JQPROG into findings.
simple_tool() {
  local tool=$1 n=$2 ok=" $3 " prog=$4
  shift 4
  run_in "$root" "$tmp/$tool.out" "$tmp/$tool.err" "$@"
  if [[ $ok != *" $rc "* ]]; then
    finish "$tool" failed "$n" "exit $rc: $(tail_of "$tmp/$tool.err")"
    return
  fi
  # Every tool run through here prints JSON even on a clean file (checked
  # live), so empty output means it did not really run.
  if [[ ! -s $tmp/$tool.out ]]; then
    finish "$tool" failed "$n" "no output: $(tail_of "$tmp/$tool.err")"
    return
  fi
  # A program's own error() (semgrep's config check) is the clearest reason.
  if ! jq -c "$prog" "$tmp/$tool.out" > "$tmp/f.$tool" 2>"$tmp/jq.$tool.err"; then
    finish "$tool" failed "$n" "unparseable output: $(tail_of "$tmp/jq.$tool.err") $(tail_of "$tmp/$tool.err")"
    return
  fi
  cat "$tmp/f.$tool" >> "$tmp/findings.jsonl"
  finish "$tool" ran "$n"
}

# ---------------------------------------------------------------------------
# Applicability.
# ---------------------------------------------------------------------------
first_line_of() { local l=""; IFS= read -r l < "$root/$1" 2>/dev/null || true; printf '%s' "$l"; }

sh_files=(); src_files=(); go_files=(); py_files=(); wf_files=(); docker_files=(); manifests=()
for f in ${changed[@]+"${changed[@]}"}; do
  b=${f##*/}
  case $f in
    *.sh|*.bash) sh_files+=("$f") ;;
    *) if [[ $(first_line_of "$f") =~ ^#!\ *(/usr/bin/env\ +)?(/[^\ ]*/)?(ba)?sh(\ |$) ]]; then sh_files+=("$f"); fi ;;
  esac
  case $f in
    *.py|*.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.go|*.java|*.kt|*.rb|*.php|*.c|*.h|*.cc|*.cpp|*.hpp|*.cs|*.rs|*.swift|*.scala) src_files+=("$f") ;;
  esac
  case $f in *.go) go_files+=("$f") ;; esac
  case $f in *.py) py_files+=("$f") ;; esac
  case $f in .github/workflows/*.yml|.github/workflows/*.yaml) wf_files+=("$f") ;; esac
  case $b in Dockerfile|Dockerfile.*|*.Dockerfile) docker_files+=("$f") ;; esac
  case $b in
    go.mod|go.sum|package-lock.json|pnpm-lock.yaml|yarn.lock|requirements*.txt|poetry.lock|uv.lock|Cargo.lock|composer.lock|Gemfile.lock)
      manifests+=("$f") ;;
  esac
done

# semgrep gets the source files minus tests. Its default ignore list (tests,
# fixtures) applies only to directories it walks, and --exclude is ignored for
# files named on the command line (both checked live on 1.182), so a named
# test file is scanned in full — security rules on test fixtures are noise.
sg_files=()
for f in ${src_files[@]+"${src_files[@]}"}; do
  case /$f in
    */test/*|*/tests/*|*/__tests__/*|*/testdata/*) continue ;;
    *_test.go|*/test_*.py|*_test.py|*.test.[jt]s|*.test.[jt]sx|*.spec.[jt]s|*.spec.[jt]sx) continue ;;
  esac
  sg_files+=("$f")
done

# Suppressions a human already wrote for the class of warning a semgrep rule
# raises. A bare //nolint or nolint:all covers every rule; a gosec / nosec
# marker covers only security rules (check_id containing ".security.").
suppress_all_re='//nolint([^:[:alnum:]_]|$)|//nolint:([[:alnum:]_-]+,)*all([^[:alnum:]_-]|$)'
suppress_sec_re='//nolint:([[:alnum:]_-]+,)*gosec([^[:alnum:]_-]|$)|#[[:space:]]*nosec([^[:alnum:]_]|$)'

# mark_annotated TOOL — tags TOOL's findings with annotated:true when the
# flagged line, or a comment-only line directly above it, carries a matching
# suppression. Tagged findings are counted, not kept (see Assemble).
mark_annotated() {
  local tool=$1 i file line rule src prev re hits=()
  while IFS=$'\t' read -r i file line rule; do
    [[ $file == /* ]] || file=$root/$file
    [[ -f $file && $line =~ ^[1-9][0-9]*$ ]] || continue
    src=$(sed -n "${line}p" "$file")
    prev=""
    ((line > 1)) && prev=$(sed -n "$((line - 1))p" "$file")
    [[ $prev =~ ^[[:space:]]*(//|#) ]] || prev=""
    re=$suppress_all_re
    [[ $rule == *.security.* ]] && re="$re|$suppress_sec_re"
    if grep -qE "$re" <<<"$src"$'\n'"$prev"; then hits+=("$i"); fi
  done < <(jq -rs --arg t "$tool" \
    'to_entries[] | select(.value.tool == $t) | [.key, .value.file, (.value.line | tostring), .value.rule] | @tsv' \
    "$tmp/findings.jsonl")
  ((${#hits[@]})) || return 0
  jq -cs --argjson idx "$(printf '%s\n' "${hits[@]}" | jq -sc .)" \
    'to_entries[] | if (.key as $k | any($idx[]; . == $k)) then .value + {annotated: true} else .value end' \
    "$tmp/findings.jsonl" > "$tmp/findings.marked"
  mv "$tmp/findings.marked" "$tmp/findings.jsonl"
}

# ---------------------------------------------------------------------------
# Tools.
# ---------------------------------------------------------------------------
sev_map='(if . == "error" then "high" elif . == "warning" then "medium" else "low" end)'

# ShellCheck ---------------------------------------------------------------
if ((${#sh_files[@]})); then
  if t=$(find_tool shellcheck); then
    simple_tool shellcheck ${#sh_files[@]} "0 1" \
      ".comments[] | {tool: \"shellcheck\", rule: (\"SC\" + (.code|tostring)), file, line,
         severity: (.level | $sev_map), message}" \
      "$t" -x -f json1 -- "${sh_files[@]}"
  else
    not_installed shellcheck ${#sh_files[@]} "shellcheck not on PATH"
  fi
else
  finish shellcheck not_applicable 0
fi

# secrets (trufflehog, else gitleaks) -------------------------------------------
# The matched value (trufflehog Raw/Redacted, gitleaks Secret/Match) is never
# copied into a finding, a message, or a failure reason.
if ((${#changed[@]})); then
  nc=${#changed[@]}
  if t=$(find_tool trufflehog); then
    run_in "$root" "$tmp/th.out" "$tmp/th.err" "$t" filesystem --json --no-update --no-verification "${changed[@]}"
    # A clean scan prints nothing. Every line it does print must be a result
    # object; anything else means the format changed, which must read as a
    # failure, not as "no secrets".
    th_bad=$(jq -R 'select(test("\\S")) | (fromjson? // null) | select(type != "object" or (has("DetectorName") | not))' \
      "$tmp/th.out" 2>/dev/null | head -c 1) || th_bad=x
    if ((rc != 0)); then
      finish secrets failed "$nc" "trufflehog exit $rc" trufflehog
    elif [[ -n $th_bad ]]; then
      finish secrets failed "$nc" "trufflehog output not recognised" trufflehog
    elif jq -cR 'fromjson? | select(type == "object" and has("DetectorName"))
        | ((.SourceMetadata.Data // {}) | [.[]] | .[0] // {}) as $m
        | {tool: "secrets", rule: .DetectorName, file: ($m.file // "unknown"), line: ($m.line // 0),
           severity: "high",
           message: ("Possible " + .DetectorName + " secret detected by trufflehog (value withheld)")}' \
        "$tmp/th.out" > "$tmp/f.secrets" 2>/dev/null; then
      cat "$tmp/f.secrets" >> "$tmp/findings.jsonl"
      finish secrets ran "$nc" "" trufflehog
    else
      finish secrets failed "$nc" "trufflehog output unparseable" trufflehog
    fi
  elif t=$(find_tool gitleaks); then
    # Scan a copy holding just the changed files so the scan is bounded to the
    # diff and `dir`/`--source` need no file-list flag.
    scan=$tmp/scan; mkdir -p "$scan"
    for f in "${changed[@]}"; do
      [[ -f $root/$f ]] || continue
      mkdir -p "$scan/$(dirname "$f")"
      cp "$root/$f" "$scan/$f"
    done
    gv=${BIN_VER[gitleaks]:-}
    gmaj=${gv%%.*}; gmin=${gv#*.}
    if [[ -n $gv ]] && ((gmaj > 8 || (gmaj == 8 && gmin >= 19))); then
      gcmd=("$t" dir . --no-banner)
    else
      gcmd=("$t" detect --no-git --no-banner --source .)
    fi
    run_in "$scan" "$tmp/gl.out" "$tmp/gl.err" "${gcmd[@]}" --redact --exit-code 0 \
      --report-format json --report-path "$tmp/gl.json"
    if ((rc != 0)); then
      finish secrets failed "$nc" "gitleaks exit $rc" gitleaks
    else
      # gitleaks writes [] when it finds nothing, so a missing report is a failure.
      if [[ ! -s $tmp/gl.json ]]; then
        finish secrets failed "$nc" "gitleaks wrote no report" gitleaks
      elif jq -c '.[] | {tool: "secrets", rule: .RuleID, file: .File, line: .StartLine, severity: "high",
          message: ("Possible secret detected by gitleaks, rule " + .RuleID + " (value withheld)")}' \
          "$tmp/gl.json" > "$tmp/f.secrets" 2>/dev/null; then
        cat "$tmp/f.secrets" >> "$tmp/findings.jsonl"
        finish secrets ran "$nc" "" gitleaks
      else
        finish secrets failed "$nc" "gitleaks report unparseable" gitleaks
      fi
    fi
  else
    not_installed secrets "$nc" "neither trufflehog nor gitleaks on PATH"
  fi
else
  finish secrets not_applicable 0
fi

# semgrep --------------------------------------------------------------------------
if ((${#sg_files[@]})); then
  if t=$(find_tool semgrep); then
    cfg=p/default
    if [[ -e $root/.semgrep.yml ]]; then cfg=.semgrep.yml
    elif [[ -d $root/.semgrep ]]; then cfg=.semgrep; fi
    # A config/network failure must surface as `failed`: exit != 0, or an
    # empty result alongside config/fetch-type errors. Rule crashes on single
    # files are level "warn" with exit 0, and leave the rest of the scan valid.
    simple_tool semgrep ${#sg_files[@]} "0" \
      'if ((.results | length) == 0) and ([.errors[]? | select(.level == "error" and (.type | tostring | test("Config|Fetch|Network|Rule"; "i")))] | length) > 0
         then error("semgrep config error")
         else .results[] | {tool: "semgrep", rule: .check_id, file: .path, line: .start.line,
           severity: (.extra.severity | ascii_upcase
             | if . == "ERROR" or . == "CRITICAL" or . == "HIGH" then "high"
               elif . == "WARNING" or . == "MEDIUM" then "medium" else "low" end),
           message: .extra.message} end' \
      "$t" scan --json --metrics=off --quiet --config "$cfg" "${sg_files[@]}"
    mark_annotated semgrep
  else
    not_installed semgrep ${#sg_files[@]} "semgrep not on PATH"
  fi
elif ((${#src_files[@]})); then
  finish semgrep not_applicable 0 "only test files changed"
else
  finish semgrep not_applicable 0
fi

# golangci-lint --------------------------------------------------------------------
if ((${#go_files[@]})); then
  if t=$(find_tool golangci-lint); then
    gv=${BIN_VER[golangci-lint]:-}; gv=${gv%%.*}
    declare -A mod_pkgs=()
    for f in "${go_files[@]}"; do
      d=$(dirname "$f"); m=$d
      while [[ ! -f $root/$m/go.mod && $m != . && $m != / ]]; do m=$(dirname "$m"); done
      [[ -f $root/$m/go.mod ]] || m=.
      pkg=${d#"$m"}; pkg=./${pkg#/}
      case " ${mod_pkgs[$m]:-} " in *" $pkg "*) ;; *) mod_pkgs[$m]="${mod_pkgs[$m]:-} $pkg" ;; esac
    done
    : > "$tmp/f.golangci"
    gl_fail=""
    for m in "${!mod_pkgs[@]}"; do
      read -r -a pkgs <<<"${mod_pkgs[$m]}"
      if [[ ${gv:-0} -ge 2 ]]; then
        flags=(--output.json.path "$tmp/gc.json"); : > "$tmp/gc.json"
        run_in "$root/$m" "$tmp/gc.out" "$tmp/gc.err" "$t" run --issues-exit-code 0 "${flags[@]}" "${pkgs[@]}"
        cp "$tmp/gc.json" "$tmp/gc.out"
      else
        run_in "$root/$m" "$tmp/gc.out" "$tmp/gc.err" "$t" run --issues-exit-code 0 --out-format json "${pkgs[@]}"
      fi
      if ((rc != 0)); then gl_fail="exit $rc in module $m: $(tail_of "$tmp/gc.err")"; break; fi
      if ! jq -c --arg m "$m" '(.Issues // [])[] | {tool: "golangci-lint", rule: .FromLinter,
            file: (if (.Pos.Filename | startswith("/")) or $m == "." then .Pos.Filename else $m + "/" + .Pos.Filename end),
            line: .Pos.Line, severity: "medium", message: .Text}' "$tmp/gc.out" >> "$tmp/f.golangci" 2>/dev/null; then
        gl_fail="unparseable output in module $m: $(tail_of "$tmp/gc.err")"; break
      fi
    done
    if [[ -n $gl_fail ]]; then
      finish golangci-lint failed ${#go_files[@]} "$gl_fail"
    else
      cat "$tmp/f.golangci" >> "$tmp/findings.jsonl"
      finish golangci-lint ran ${#go_files[@]}
    fi
  else
    not_installed golangci-lint ${#go_files[@]} "golangci-lint not on PATH"
  fi
else
  finish golangci-lint not_applicable 0
fi

# ruff -------------------------------------------------------------------------------
if ((${#py_files[@]})); then
  if t=$(find_tool ruff); then
    simple_tool ruff ${#py_files[@]} "0" \
      '.[] | {tool: "ruff", rule: .code, file: .filename, line: .location.row, severity: "medium", message: .message}' \
      "$t" check --output-format json --no-cache --exit-zero "${py_files[@]}"
  else
    not_installed ruff ${#py_files[@]} "ruff not on PATH"
  fi
else
  finish ruff not_applicable 0
fi

# actionlint -----------------------------------------------------------------------
if ((${#wf_files[@]})); then
  if t=$(find_tool actionlint); then
    simple_tool actionlint ${#wf_files[@]} "0 1" \
      '(. // [])[] | {tool: "actionlint", rule: .kind, file: .filepath, line: .line, severity: "medium", message: .message}' \
      "$t" -format '{{json .}}' "${wf_files[@]}"
  else
    not_installed actionlint ${#wf_files[@]} "actionlint not on PATH"
  fi
else
  finish actionlint not_applicable 0
fi

# hadolint -------------------------------------------------------------------------
if ((${#docker_files[@]})); then
  if t=$(find_tool hadolint); then
    simple_tool hadolint ${#docker_files[@]} "0" \
      '(. // [])[] | {tool: "hadolint", rule: .code, file, line,
         severity: (if .level == "error" then "high" elif .level == "warning" then "medium" else "low" end), message}' \
      "$t" --no-fail -f json "${docker_files[@]}"
  else
    not_installed hadolint ${#docker_files[@]} "hadolint not on PATH"
  fi
else
  finish hadolint not_applicable 0
fi

# osv-scanner ----------------------------------------------------------------------
# go.sum is not a lockfile osv-scanner reads; its sibling go.mod is.
if ((${#manifests[@]})); then
  osv_args=()
  for f in "${manifests[@]}"; do
    if [[ ${f##*/} == go.sum ]]; then
      alt=$(dirname "$f")/go.mod
      if [[ -f $root/$alt ]]; then f=$alt; else continue; fi
    fi
    case " ${osv_args[*]:-} " in *" $f "*) ;; *) osv_args+=("$f") ;; esac
  done
  if t=$(find_tool osv-scanner); then
    ov=${BIN_VER[osv-scanner]:-}
    if [[ ${ov%%.*} == 1 ]]; then ocmd=("$t" --format json); else ocmd=("$t" scan source --format json); fi
    largs=(); for f in "${osv_args[@]}"; do largs+=(-L "$f"); done
    # Exit 128 = no packages found in the given files: ran, nothing to report.
    # Dependency findings are not line-filtered (dep:true).
    # shellcheck disable=SC2016 # jq variables, no shell expansion intended
    simple_tool osv-scanner ${#manifests[@]} "0 1 128" \
      '(.results // [])[] | .source.path as $p | (.packages // [])[] | .package as $k
         | (.vulnerabilities // [])[] | {tool: "osv-scanner", rule: .id, file: $p, line: 0, severity: "high", dep: true,
             message: ($k.name + "@" + $k.version + ": " + (.summary // "known vulnerability"))}' \
      "${ocmd[@]}" "${largs[@]}"
  else
    not_installed osv-scanner ${#manifests[@]} "osv-scanner not on PATH"
  fi
else
  finish osv-scanner not_applicable 0
fi

# ---------------------------------------------------------------------------
# Assemble: repo-relative paths, changed-line filtering, per-tool counts.
# ---------------------------------------------------------------------------
result=$(jq -n --arg base "$base_sha" --arg head "$head_label" --arg root "$root" \
  --argjson all "$all_lines" --rawfile ranges "$tmp/ranges.tsv" \
  --slurpfile tools "$tmp/tools.jsonl" --slurpfile fnd "$tmp/findings.jsonl" '
  def rel: sub("^\\./"; "") | if startswith($root + "/") then .[($root | length) + 1:] else . end;
  ($ranges | split("\n") | map(select(length > 0) | split("\t"))
    | reduce .[] as $r ({}; .[$r[0]] += [[($r[1] | tonumber), ($r[2] | tonumber)]])) as $rg
  | ($fnd | map(.file |= rel | .line = ((.line | tonumber? // 0))
      | . + {inscope: ($all == 1 or (.dep // false)
              or (.file as $f | .line as $l | ($rg[$f] // []) | any(.[]; $l >= .[0] and $l <= .[1])))}
      | . + {keep: (.inscope and ((.annotated // false) | not))})) as $all_f
  | ($all_f | map(select(.keep))) as $kept
  | {base: $base, head: $head,
     tools: ($tools | map(. as $t | if .status == "ran"
        then . + {findings: ($kept | map(select(.tool == $t.tool)) | length),
                  outside_diff: ($all_f | map(select(.tool == $t.tool and (.inscope | not))) | length)}
             + ($all_f | map(select(.tool == $t.tool and .inscope and (.annotated // false))) | length
                | if . > 0 then {annotated: .} else {} end)
        else . end)),
     findings: ($kept | map(del(.keep, .inscope, .dep, .annotated)))}')

if [[ -n $out ]]; then
  printf '%s\n' "$result" > "$out"
else
  printf '%s\n' "$result"
fi
