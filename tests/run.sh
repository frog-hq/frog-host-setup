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

make_fake_path() {
  local dir=$1
  mkdir -p "$dir"
  ln -s "$REAL_UNAME" "$dir/uname"
  ln -s "$REAL_ID" "$dir/id"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_fake_path "$tmp/empty"
set +e
output=$(PATH="$tmp/empty" FROG_HOST_SETUP_OS=linux "$REAL_BASH" "$TOOL" --component tmux --verify-only 2>&1)
status=$?
set -e
assert_status "$status" 3
assert_contains "$output" "no supported package manager"

make_fake_path "$tmp/apt"
cat >"$tmp/apt/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-called:%s\n' "$*" >>"${FROG_TEST_LOG:?}"
EOF
chmod +x "$tmp/apt/apt-get"
output=$(PATH="$tmp/apt" FROG_HOST_SETUP_OS=linux "$REAL_BASH" "$TOOL" --component tmux --dry-run --json)
assert_contains "$output" '"state":"planned"'
assert_contains "$output" '"packages":["tmux"]'
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
exit 0
EOF
chmod +x "$tmp/ready/tmux"
output=$(PATH="$tmp/ready" FROG_HOST_SETUP_OS=linux "$REAL_BASH" "$TOOL" --verify-only --json)
assert_contains "$output" '"state":"ready"'
assert_contains "$output" '"missing":[]'

set +e
output=$(PATH="$tmp/ready" "$REAL_BASH" "$TOOL" --component nope 2>&1)
status=$?
set -e
assert_status "$status" 2
assert_contains "$output" "unsupported component"

printf '%s assertions passed\n' "$pass"
((fail == 0))
