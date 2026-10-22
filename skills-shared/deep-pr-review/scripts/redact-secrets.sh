#!/usr/bin/env bash
# Redact secrets from text before it is posted anywhere.
#
# Usage:
#   redact-secrets.sh < in > out
#
# stdin -> stdout with each secret replaced by <secret-redacted>; the number of
# redactions is printed to stderr (a bare integer). Needs perl: when perl is
# missing this exits non-zero and writes NOTHING to stdout, and callers must
# refuse to post — passing text through unredacted would defeat the point.
#
# Patterns are deliberately narrow. A false negative leaks a secret; a false
# positive only hides a harmless string in a review comment, but a broad
# pattern would redact ordinary code until nobody trusts the output.
#   PEM private key   -----BEGIN ... PRIVATE KEY----- through the END line (a
#                     block cut off before END: the header plus the base64 lines)
#   GitHub            gh[pousr]_ + 36 or more alphanumerics; github_pat_ + 22+
#   AWS access key id AKIA or ASIA + 16 uppercase alphanumerics (20 in all)
#   Slack             xox[abprs]- + 10 or more [A-Za-z0-9-]
#   Google API key    AIza + 35 of [0-9A-Za-z_-]
#   Google OAuth      ya29. + 20 or more [0-9A-Za-z_-]
#   Anthropic         sk-ant- + 20 or more [A-Za-z0-9_-]
#   OpenAI            sk- + 32 or more plain alphanumerics, or sk-proj- + 32 or
#                     more [A-Za-z0-9_-]. Not preceded by [A-Za-z0-9_-], and no
#                     hyphens in the plain form, so words like "task-..." or
#                     "risk-assessment-..." are left alone.
#   JWT               eyJ<b64url>.eyJ<b64url>.<b64url>, each part 8+ chars
#   Bearer            "Bearer " + 20 or more token characters; only the token
#                     is replaced
#   URL credentials   scheme://user:PASSWORD@ with a password of 6+ characters;
#                     only the password is replaced
#   generic           (api_key|apikey|api-key|secret|token|password|passwd) with
#                     an optional short suffix (GITHUB_TOKEN, client_secret,
#                     authToken), an optional closing quote, then : or =, then a
#                     value of 12+ characters; ONLY the value is replaced. A
#                     quoted value may hold spaces (a passphrase) but not a
#                     newline. An unquoted value may not contain whitespace,
#                     quotes, or ( ) { } [ ] < > $ , ; so code such as
#                     `token = getToken(req)` or `password = $PASSWORD` is left
#                     alone, and it may be followed by one of those closers, as
#                     in prose like "(token=...)". A quoted value is
#                     redacted whatever it looks like; an unquoted one must
#                     also contain a digit, which a bare identifier
#                     (`secret = some_long_name`) rarely does and a generated
#                     credential almost always does. Known gap: an unquoted
#                     all-letters password is not caught by this rule.
set -euo pipefail

command -v perl >/dev/null 2>&1 \
  || { printf '%s: perl is not installed; refusing to pass text through unredacted\n' "${0##*/}" >&2; exit 2; }

# The program is single-quoted so bash leaves $, \ and the regexes alone; the
# quote characters inside are written \x27 / \x22.
exec perl -0777 -e '
  use strict; use warnings;
  my $t = <STDIN>; $t = "" unless defined $t;
  my $R = "<secret-redacted>";
  my $n = 0;
  sub plain { my ($re) = @_; $n += ($t =~ s/$re/$R/g); }

  plain(qr/-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----/s);
  plain(qr/-----BEGIN [A-Z ]*PRIVATE KEY-----\s*(?:[A-Za-z0-9+\/=]{16,}\s*)*/);
  plain(qr/(?<![A-Za-z0-9])(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})/);
  plain(qr/(?<![A-Z0-9])(?:AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])/);
  plain(qr/(?<![A-Za-z0-9])xox[abprs]-[A-Za-z0-9-]{10,}/);
  plain(qr/(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{35}/);
  plain(qr/(?<![A-Za-z0-9])ya29\.[0-9A-Za-z_-]{20,}/);
  plain(qr/(?<![A-Za-z0-9_-])sk-ant-[A-Za-z0-9_-]{20,}/);
  plain(qr/(?<![A-Za-z0-9_-])(?:sk-proj-[A-Za-z0-9_-]{32,}|sk-[A-Za-z0-9]{32,})/);
  plain(qr/(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/);
  $n += ($t =~ s/(\bBearer\s+)[A-Za-z0-9._~+\/=-]{20,}/$1$R/g);
  $n += ($t =~ s/(:\/\/[^\/\s:@]+:)[^@\s\/]{6,}(?=@)/$1$R/g);

  my $key = qr/(?:api[_-]?key|secret|token|password|passwd)[A-Za-z0-9_-]{0,20}[\x27\x22]?\s*[:=]\s*/i;
  my $val = qr/[^\s\x27\x22(){}\[\]<>\$,;]{12,}/;
  # Quoted: redact whatever the value looks like.
  $n += ($t =~ s/($key)([\x27\x22])((?:(?!\2)[^\n]){12,})\2/$1$2$R$2/g);
  # Unquoted: needs a digit and must be a whole word-ish run, not the start of
  # an expression.
  $n += ($t =~ s/($key)(?![\x27\x22])(?=[^\s\x27\x22]*\d)($val)(?=[,;)\]}>]|[\s\x27\x22]|\z)/$1$R/g);

  print $t;
  print STDERR "$n\n";
'
