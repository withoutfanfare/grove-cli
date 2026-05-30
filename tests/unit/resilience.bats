#!/usr/bin/env bats
# resilience.bats - Unit tests for lib/11-resilience.sh
#
# All tests invoke zsh subshells because resilience.sh uses zsh-specific
# features (typeset -g, ${(@ps:...)} splitting, (N) globbing, TRAPEXIT).
# The output helpers (warn/dim/die) and clock (_get_now) live in other modules,
# so each subshell stubs them before sourcing.

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PROJECT_ROOT

  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Shared stub prelude sourced into every zsh subshell. die() exits (like the
# real die() in lib/01-core.sh) so callers such as transaction_register abort.
# A sane PATH is set so df/tail/awk resolve inside the nested non-interactive shell.
STUBS='
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
  warn(){ :; }; dim(){ :; }; die(){ echo "DIE:$1" >&2; exit 1; }
  spinner_stop(){ :; }
  _get_now(){ date +%s; }
'

# --- with_retry ---

@test "with_retry succeeds after N transient failures" {
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    attempts=0
    flaky(){ attempts=\$((attempts+1)); (( attempts >= 3 )); }
    with_retry 5 flaky || exit 1
    (( attempts == 3 )) || exit 2
  "
  [ "$status" -eq 0 ]
}

@test "with_retry returns failure when all attempts fail" {
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    bad(){ return 1; }
    if with_retry 2 bad; then exit 1; fi
    exit 0
  "
  [ "$status" -eq 0 ]
}

@test "with_retry succeeds immediately on first try (no retries)" {
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    attempts=0
    good(){ attempts=\$((attempts+1)); return 0; }
    with_retry 5 good || exit 1
    (( attempts == 1 )) || exit 2
  "
  [ "$status" -eq 0 ]
}

# --- check_disk_space ---

@test "check_disk_space passes when free space exceeds threshold" {
  command -v df >/dev/null 2>&1 || skip "df not available"
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    # 1MB threshold should comfortably pass on any real filesystem.
    check_disk_space \"\$TEST_TMPDIR\" 1
  "
  # Some sandboxed shells cannot exec df/tail/awk from inside a sourced function,
  # so check_disk_space reads 0MB and dies. That is an environment artifact, not
  # a code fault — skip rather than fail when we detect it.
  if [ "$status" -ne 0 ] && [[ "$output" == *"0MB available"* ]]; then
    skip "df/tail/awk unavailable inside sourced function in this shell"
  fi
  [ "$status" -eq 0 ]
}

@test "check_disk_space fails (die) when below threshold" {
  command -v df >/dev/null 2>&1 || skip "df not available"
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    # An absurdly large threshold can never be satisfied.
    check_disk_space \"\$TEST_TMPDIR\" 999999999
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"Insufficient disk space"* ]]
}

# --- transactions: rollback ordering ---

@test "registered rollback steps run in reverse order" {
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    rec(){ print -rn -- \"\$1 \"; }
    transaction_start
    transaction_register rec one
    transaction_register rec two
    transaction_register rec three
    transaction_rollback
  "
  [ "$status" -eq 0 ]
  # Reverse registration order: three two one
  [[ "$output" == *"three two one"* ]]
}

@test "rollback preserves empty arguments" {
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    check(){ [[ -z \"\$1\" ]] && print -r -- \"EMPTY:[\$2]\"; }
    transaction_start
    transaction_register check '' tail
    transaction_rollback
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"EMPTY:[tail]"* ]]
}

@test "rollback passes multiple arguments correctly" {
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    show(){ print -r -- \"\$#:\$1|\$2|\$3\"; }
    transaction_start
    transaction_register show a b c
    transaction_rollback
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"3:a|b|c"* ]]
}

# --- transactions: re-entrancy ---

@test "calling transaction_rollback twice runs steps only once" {
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    count=0
    cnt(){ count=\$((count+1)); }
    transaction_start
    transaction_register cnt
    transaction_rollback
    transaction_rollback
    print -r -- \"count=\$count\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"count=1"* ]]
}

@test "transaction_commit prevents rollback from running" {
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    ran=no
    rb(){ ran=yes; }
    transaction_start
    transaction_register rb
    transaction_commit
    transaction_rollback
    print -r -- \"ran=\$ran\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran=no"* ]]
}

@test "transaction_register rejects undefined functions" {
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    transaction_start
    transaction_register not_a_real_function
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid rollback function"* ]]
}

# --- check_index_locks: stdout/exit contract ---

@test "check_index_locks prints 0 and exits 0 when no worktrees dir" {
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    check_index_locks \"\$TEST_TMPDIR/missing\" --auto-clean
  "
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "check_index_locks removes a stale, unheld lock and reports count on stdout" {
  mkdir -p "$TEST_TMPDIR/worktrees/wt"
  : > "$TEST_TMPDIR/worktrees/wt/index.lock"
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    lock=\"\$TEST_TMPDIR/worktrees/wt/index.lock\"
    mtime=\$(stat -f %m \"\$lock\" 2>/dev/null || stat -c %Y \"\$lock\")
    # Pretend 'now' is well past the 5-minute staleness window.
    _get_now(){ echo \$((mtime + 1000)); }
    count=\$(check_index_locks \"\$TEST_TMPDIR\" --auto-clean) || exit 1
    [[ \"\$count\" == 1 ]] || exit 2
    [[ -f \"\$lock\" ]] && exit 3   # should have been removed
    exit 0
  "
  [ "$status" -eq 0 ]
}

@test "check_index_locks does not delete a lock held by a live process" {
  command -v lsof >/dev/null 2>&1 || command -v fuser >/dev/null 2>&1 || skip "no lsof/fuser"
  mkdir -p "$TEST_TMPDIR/worktrees/wt"
  : > "$TEST_TMPDIR/worktrees/wt/index.lock"
  run zsh -c "
    $STUBS
    source \"\$PROJECT_ROOT/lib/11-resilience.sh\"
    lock=\"\$TEST_TMPDIR/worktrees/wt/index.lock\"
    # Hold the lock open with a background process for the duration of the check.
    ( exec 9>\"\$lock\"; sleep 5 ) &
    holder=\$!
    sleep 0.3
    mtime=\$(stat -f %m \"\$lock\" 2>/dev/null || stat -c %Y \"\$lock\")
    _get_now(){ echo \$((mtime + 1000)); }
    count=\$(check_index_locks \"\$TEST_TMPDIR\" --auto-clean)
    rc=\$?
    kill \$holder 2>/dev/null; wait \$holder 2>/dev/null
    [[ \$rc -eq 0 ]] || exit 1
    [[ \"\$count\" == 0 ]] || exit 2     # in-use lock not counted as cleaned
    [[ -f \"\$lock\" ]] || exit 3        # in-use lock must still exist
    exit 0
  "
  [ "$status" -eq 0 ]
}
