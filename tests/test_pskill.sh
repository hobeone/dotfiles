#!/usr/bin/env zsh

# Extract and eval pskill function from home/.zshrc
eval "$(sed -n '/^pskill() {/,/^}/p' home/.zshrc)"

# Mock ps function
ps() {
  cat <<'EOF'
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0  22556  9484 ?        Ss   Jun12   0:01 /sbin/init
hobe      1234  0.5  0.1 312345 45678 ?        Sl   09:00   0:05 /usr/bin/my-awesome-app --port 8080
hobe      5678  0.0  0.0  12345  4567 pts/1    S+   09:05   0:00 pskill my-awesome-app
hobe      5679  0.0  0.0   8900  1200 pts/1    R+   09:05   0:00 awk -v query=my-awesome-app
EOF
}

# Mock kill function to print call
kill() {
  echo "KILL_CALL: $*"
}

# Run pskill without custom signal
output=$(pskill "my-awesome-app")
echo "Output:"
echo "$output"
echo "-----------------------------------"

# Assertions for run 1
if ! echo "$output" | grep -q "KILL_CALL: -15 1234"; then
  echo "FAIL: Expected kill call '-15 1234' not found in output"
  exit 1
fi

# Run pskill with custom signal
output=$(pskill "-9" "my-awesome-app")
echo "Output:"
echo "$output"
echo "-----------------------------------"

# Assertions for run 2
if ! echo "$output" | grep -q "KILL_CALL: -9 1234"; then
  echo "FAIL: Expected kill call '-9 1234' not found in output"
  exit 1
fi

echo "PASS"
