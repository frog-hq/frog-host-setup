#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly ROOT
readonly TOOL="$ROOT/bin/frog-host-setup"
REAL_BASH=$(command -v bash)
readonly REAL_BASH
REAL_UNAME=$(command -v uname)
readonly REAL_UNAME
REAL_ID=$(command -v id)
readonly REAL_ID

pass=0
fail=0

version_output=$("$REAL_BASH" "$TOOL" --version)
[[ "$version_output" == "frog-host-setup 0.1.0-alpha.3" ]] \
  && pass=$((pass + 1)) \
  || { printf 'FAIL: unexpected version: %s\n' "$version_output" >&2; fail=$((fail + 1)); }

assert_contains() {
  local haystack=$1 needle=$2
  if [[ "$haystack" == *"$needle"* ]]; then
    pass=$((pass + 1))
  else
    printf 'FAIL: expected output to contain %q\n%s\n' "$needle" "$haystack" >&2
    fail=$((fail + 1))
  fi
}

assert_status() {
  local actual=$1 expected=$2
  if [[ "$actual" == "$expected" ]]; then
    pass=$((pass + 1))
  else
    printf 'FAIL: expected status %s, got %s\n' "$expected" "$actual" >&2
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local haystack=$1 needle=$2
  if [[ "$haystack" != *"$needle"* ]]; then
    pass=$((pass + 1))
  else
    printf 'FAIL: expected output not to contain %q\n%s\n' "$needle" "$haystack" >&2
    fail=$((fail + 1))
  fi
}

make_fake_path() {
  local dir=$1
  mkdir -p "$dir"
  ln -s "$REAL_UNAME" "$dir/uname"
  ln -s "$REAL_ID" "$dir/id"
  ln -s "$REAL_BASH" "$dir/bash"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_fake_path "$tmp/empty"
set +e
output=$(PATH="$tmp/empty" FROG_HOST_SETUP_OS=linux "$REAL_BASH" "$TOOL" --component tmux --verify-only 2>&1)
status=$?
set -e
assert_status "$status" 4
assert_contains "$output" "Host setup: missing"
assert_contains "$output" "Plan: unavailable"

set +e
output=$(PATH="$tmp/empty" FROG_HOST_SETUP_OS=linux "$REAL_BASH" "$TOOL" --component tmux --verify-only --json 2>&1)
status=$?
set -e
assert_status "$status" 4
assert_contains "$output" '"state":"missing"'
assert_contains "$output" '"package_manager":"none"'
assert_contains "$output" '"command":[]'
assert_contains "$output" '"requires_sudo":false'

make_fake_path "$tmp/apt"
cat >"$tmp/apt/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-called:%s\n' "$*" >>"${FROG_TEST_LOG:?}"
EOF
chmod +x "$tmp/apt/apt-get"
output=$(PATH="$tmp/apt" FROG_HOST_SETUP_OS=linux "$REAL_BASH" "$TOOL" --component tmux --dry-run --json)
assert_contains "$output" '"state":"planned"'
assert_contains "$output" '"packages":["tmux"]'
assert_contains "$output" '"command":["sudo","apt-get","install","-y","--no-install-recommends","tmux"]'
[[ ! -e "$tmp/install.log" ]] && pass=$((pass + 1)) || fail=$((fail + 1))

set +e
output=$(PATH="$tmp/apt" FROG_HOST_SETUP_OS=linux "$REAL_BASH" "$TOOL" --component tmux 2>&1)
status=$?
set -e
assert_status "$status" 5
assert_contains "$output" "refusing to install"

make_fake_path "$tmp/ready"
for command in ssh sshd mosh mosh-server; do
  cat >"$tmp/ready/$command" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmp/ready/$command"
done
cat >"$tmp/ready/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'tmux:%s\n' "$*" >>"${FROG_TEST_LOG:?}"
exit 0
EOF
chmod +x "$tmp/ready/tmux"
output=$(PATH="$tmp/ready" FROG_TEST_LOG="$tmp/tmux.log" FROG_HOST_SETUP_OS=linux "$REAL_BASH" "$TOOL" --verify-only --json)
assert_contains "$output" '"state":"ready"'
assert_contains "$output" '"missing":[]'
assert_contains "$(<"$tmp/tmux.log")" "-f /dev/null new-session -d -s frog-host-setup-verify sleep 30"
assert_contains "$(<"$tmp/tmux.log")" "has-session -t frog-host-setup-verify"
assert_contains "$(<"$tmp/tmux.log")" "kill-server"
assert_not_contains "$(<"$tmp/tmux.log")" ".tmux.conf"

make_fake_path "$tmp/broken-tmux"
cat >"$tmp/broken-tmux/tmux" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"has-session"* ]] && exit 1
exit 0
EOF
chmod +x "$tmp/broken-tmux/tmux"
set +e
output=$(PATH="$tmp/broken-tmux" FROG_HOST_SETUP_OS=linux "$REAL_BASH" "$TOOL" --component tmux --verify-only --json)
status=$?
set -e
assert_status "$status" 4
assert_contains "$output" '"state":"missing"'

set +e
output=$(PATH="$tmp/ready" "$REAL_BASH" "$TOOL" --component nope 2>&1)
status=$?
set -e
assert_status "$status" 2
assert_contains "$output" "unsupported component"

printf '%s assertions passed\n' "$pass"
((fail == 0))
