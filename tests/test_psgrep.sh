#!/usr/bin/env zsh

# Extract and eval psgrep function from home/.zshrc
eval "$(sed -n '/^psgrep() {/,/^}/p' home/.zshrc)"

# Mock ps function
ps() {
  cat <<'EOF'
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0  22556  9484 ?        Ss   Jun12   0:01 /sbin/init
hobe      1234  0.5  0.1 312345 45678 ?        Sl   09:00   0:05 /usr/bin/my-awesome-app --port 8080
hobe      5678  0.0  0.0  12345  4567 pts/1    S+   09:05   0:00 psgrep my-awesome-app
hobe      5679  0.0  0.0   8900  1200 pts/1    R+   09:05   0:00 awk -v query=my-awesome-app
EOF
}

# Run psgrep
output=$(psgrep "my-awesome-app")

echo "Output of psgrep 'my-awesome-app':"
echo "$output"
echo "-----------------------------------"

# Assertions
# 1. Header must exist
if ! echo "$output" | grep -q "USER       PID %CPU"; then
  echo "FAIL: Header is missing"
  exit 1
fi

# 2. Match must exist
if ! echo "$output" | grep -q "my-awesome-app --port 8080"; then
  echo "FAIL: Matched process is missing"
  exit 1
fi

# 3. psgrep self-match must NOT exist
if echo "$output" | grep -q "psgrep my-awesome-app"; then
  echo "FAIL: psgrep self-match was not filtered"
  exit 1
fi

# 4. awk command must NOT exist
if echo "$output" | grep -q "awk -v query="; then
  echo "FAIL: awk command was not filtered"
  exit 1
fi

echo "PASS"
