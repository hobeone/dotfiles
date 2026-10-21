#!/usr/bin/env bash
# redact-secrets.sh: every pattern, no false positives on ordinary code, and
# the perl-missing refusal. Fake tokens are assembled at runtime from pieces so
# no token-shaped string is ever committed (GitHub push protection and the
# repo's secret check would reject it).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

script=skills-shared/deep-pr-review/scripts/redact-secrets.sh
fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# rep CHARS N: CHARS repeated N times (a deterministic stand-in for key bytes).
rep() { local out="" i; for ((i = 0; i < $2; i++)); do out+=$1; done; printf '%s' "$out"; }

R='<secret-redacted>'

# check NAME INPUT WANT_COUNT: the secret must vanish from stdout, the
# placeholder must appear, and stderr must report exactly WANT_COUNT.
check() {
  local name=$1 input=$2 want=$3 secret=${4:-$2} out cnt
  out=$("$script" <<<"$input" 2>"$work/cnt") || { err "$name: exited non-zero"; return; }
  cnt=$(<"$work/cnt")
  [[ $out == *"$secret"* ]] && err "$name: secret still present in output"
  [[ $out == *"$R"* ]] || err "$name: no placeholder in output: $out"
  [[ $cnt == "$want" ]] || err "$name: reported $cnt redactions, want $want"
}

# keep NAME INPUT: output identical to input, zero redactions.
keep() {
  local name=$1 input=$2 out cnt
  out=$("$script" <<<"$input" 2>"$work/cnt") || { err "$name: exited non-zero"; return; }
  cnt=$(<"$work/cnt")
  [[ $out == "$input" ]] || err "$name: ordinary text was altered: $out"
  [[ $cnt == 0 ]] || err "$name: reported $cnt redactions on ordinary text"
}

a36=$(rep A 36); lower32=$(rep a 32); mix20=$(rep aB3 7)
for kind in p o u s r; do
  tok="gh${kind}_${a36}"
  check "github gh${kind}_" "token was $tok in the log" 1 "$tok"
done
tok="github""_pat_$(rep 1A 15)"; check "github_pat_" "x $tok y" 1 "$tok"
tok="AK""IA$(rep Q 16)"; check "aws AKIA" "id=$tok" 1 "$tok"
tok="AS""IA$(rep Z 16)"; check "aws ASIA" "id=$tok" 1 "$tok"
tok="xo""xb-$(rep 1 12)-$(rep a 24)"; check "slack xoxb" "$tok" 1
tok="xo""xp-$(rep 9 12)-$(rep b 12)"; check "slack xoxp" "$tok" 1
tok="AI""za$(rep x 35)"; check "google api key" "key: $tok" 1 "$tok"
tok="ya""29.$(rep c 40)"; check "google oauth" "Bearer $tok" 1 "$tok"
tok="sk""-ant-api03-$mix20$mix20"; check "anthropic" "k=$tok" 1 "$tok"
tok="sk""-$lower32"; check "openai" "OPENAI=$tok" 1 "$tok"
tok="sk""-proj-$(rep aB_ 14)"; check "openai project key" "OPENAI=$tok" 1 "$tok"
jwt="ey""J$(rep a 12).ey""J$(rep b 12).$(rep c 12)"; check "jwt" "Authorization: $jwt" 1 "$jwt"

pem_b="-----BEGIN RSA PRIV""ATE KEY-----"; pem_e="-----END RSA PRIV""ATE KEY-----"
body_line=$(rep Mq 30)
pem=$(printf '%s\n%s\n%s\n%s' "$pem_b" "$body_line" "$body_line" "$pem_e")
out=$(printf 'before\n%s\nafter\n' "$pem" | "$script" 2>"$work/cnt") || err "pem: exited non-zero"
[[ $out == *"$body_line"* || $out == *PRIV* ]] && err "pem: key material or markers survive: $out"
[[ $out == *before* && $out == *after* ]] || err "pem: surrounding text was lost: $out"
[[ $(<"$work/cnt") == 1 ]] || err "pem: want 1 redaction, got $(<"$work/cnt")"
# A block cut off before its END line still must not leak.
out=$(printf 'x\n%s\n%s\n' "$pem_b" "$body_line" | "$script" 2>/dev/null) || err "pem truncated: exited non-zero"
[[ $out == *"$body_line"* ]] && err "pem truncated: key material survives"

# Generic key/value: only the VALUE goes; the key stays readable.
val="hunter2$(rep z 8)"
out=$("$script" <<<"password = \"$val\"" 2>"$work/cnt")
[[ $out == "password = \"$R\"" ]] || err "generic quoted: got $out"
[[ $(<"$work/cnt") == 1 ]] || err "generic quoted: count $(<"$work/cnt")"
out=$("$script" <<<"API_KEY=$val" 2>/dev/null)
[[ $out == "API_KEY=$R" ]] || err "generic env style: got $out"
out=$("$script" <<<"{\"client_secret\": \"$val\"}" 2>/dev/null)
[[ $out == "{\"client_secret\": \"$R\"}" ]] || err "generic JSON: got $out"
out=$("$script" <<<"token: abc123$(rep d 10)" 2>/dev/null)
[[ $out == "token: $R" ]] || err "generic unquoted with digit: got $out"

# No false positives on ordinary code and prose.
keep "go assignment" 'token := cfg.TokenSource.Next()'
keep "call result" 'password = getPasswordFromPrompt(reader)'
keep "short value" 'password = "short"'
keep "plain identifier" 'secret = some_long_identifier_name'
keep "prose" 'The token bucket refills every second; a password manager is advised.'
keep "kebab words" 'see risk-assessment-and-task-planning-documentation-for-the-release'
keep "sha and uuid" 'commit 5f4aadd0c0ffee1234567890abcdef1234567890 id 123e4567-e89b-12d3-a456-426614174000'
keep "go code" 'func (s *Server) Handle(w http.ResponseWriter, r *http.Request) { s.mu.Lock() }'

# Idempotent: redacting redacted text changes nothing.
once=$("$script" <<<"x $(printf 'gh%s_%s' p "$a36") y" 2>/dev/null)
twice=$("$script" <<<"$once" 2>/dev/null)
[[ $once == "$twice" ]] || err "not idempotent: '$once' vs '$twice'"

# Several secrets: the count is the number of redactions.
out=$("$script" <<<"a gh""p_$a36 b AK""IA$(rep Q 16) c" 2>"$work/cnt")
[[ $(<"$work/cnt") == 2 ]] || err "two secrets: reported $(<"$work/cnt")"

# perl missing: refuse (non-zero, no stdout) rather than pass text through.
mkdir -p "$work/noperl"
out=$(PATH="$work/noperl" "$BASH" "$script" <<<"gh""p_$a36" 2>"$work/e") && err "perl missing: exited 0"
[[ -z $out ]] || err "perl missing: text was passed through: $out"
grep -qi perl "$work/e" || err "perl missing: message does not mention perl: $(<"$work/e")"

((fail)) && exit 1
echo PASS
