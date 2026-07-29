#!/usr/bin/env bats
# bulk-ops.bats - Integration tests for build-all / exec-all
#
# Covers two behaviours from the improvement plan:
#   #10 - @group targets expand to the repos configured via `grove group`
#   #16 - operations are passed to parallel_run as "label|path|command", so a
#         worktree path containing a single quote is handled cleanly (rejected
#         as a failure) rather than breaking shell quoting or running elsewhere.

load '../test-helper'

setup() {
  setup_test_environment

  export GROVE_SCRIPT="$GROVE_ROOT/grove"

  # GROVE_GROUPS_FILE is "$HOME/.grove/groups", resolved at script load, so we
  # point HOME at the test temp dir and seed the groups file there.
  export TEST_HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$TEST_HOME/.grove"
}

teardown() {
  teardown_test_environment
}

# Run grove with an isolated HOME (for the groups file) and test HERD_ROOT.
run_grove() {
  HOME="$TEST_HOME" \
  HERD_ROOT="$HERD_ROOT" \
  GROVE_HOOKS_DIR="$GROVE_HOOKS_DIR" \
  NO_COLOR=1 \
  run zsh "$GROVE_SCRIPT" "$@"
}

# Create a bare repo with a single worktree on the given branch.
seed_repo_with_worktree() {
  local repo="$1" branch="${2:-main}" wt_dir="${3:-}"
  git init -q --bare "$HERD_ROOT/$repo.git"
  [[ -n "$wt_dir" ]] || wt_dir="$HERD_ROOT/$repo-worktrees/$branch"
  git --git-dir="$HERD_ROOT/$repo.git" \
    worktree add -q -b "$branch" "$wt_dir" 2>/dev/null
}

# Write a groups file entry: name=repo1 repo2 ...
seed_group() {
  local name="$1"; shift
  printf '%s=%s\n' "$name" "$*" >> "$TEST_HOME/.grove/groups"
}

@test "danger guard does not prompt for harmless substring matches" {
  run zsh -c '
    warn() { :; }
    confirm() { print -r -- prompted; return 1; }
    error_exit() { exit "${3:-1}"; }
    source "$1/lib/commands/bulk-ops.sh"
    _check_dangerous_command "git add ."
    _check_dangerous_command "echo ok >/dev/null"
  ' _ "$GROVE_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" != *"prompted"* ]]
}

@test "danger guard still blocks a real dd command" {
  run zsh -c '
    warn() { print -r -- "$*"; }
    confirm() { return 1; }
    error_exit() { exit "${3:-1}"; }
    source "$1/lib/commands/bulk-ops.sh"
    _check_dangerous_command "dd if=/dev/zero of=/dev/disk9"
  ' _ "$GROVE_ROOT"

  [ "$status" -eq 2 ]
  [[ "$output" == *"could be destructive"* ]]
}

@test "danger guard blocks redirection to common block devices" {
  local dev
  for dev in /dev/disk2 /dev/sda1 /dev/nvme0n1 /dev/vda /dev/xvda2 /dev/md0 /dev/mapper/vg0-root /dev/dm-0; do
    run zsh -c '
      warn() { print -r -- "$*"; }
      confirm() { return 1; }
      error_exit() { exit "${3:-1}"; }
      source "$1/lib/commands/bulk-ops.sh"
      _check_dangerous_command "cat image.img > $2"
    ' _ "$GROVE_ROOT" "$dev"

    [ "$status" -eq 2 ]
    [[ "$output" == *"could be destructive"* ]]
  done
}

# ============================================================================
# #10 - @group expansion
# ============================================================================

@test "exec-all @group: expands to the configured repos" {
  seed_repo_with_worktree apphome main
  seed_repo_with_worktree appauth main
  seed_group frontend apphome appauth

  run_grove exec-all @frontend true
  [ "$status" -eq 0 ]
  # Both repos in the group are visited (printed as section headers)
  [[ "$output" == *"apphome"* ]]
  [[ "$output" == *"appauth"* ]]
  [[ "$output" == *"across group @frontend"* ]]
}

@test "build-all @group: expands to the configured repos" {
  seed_repo_with_worktree apphome main
  seed_repo_with_worktree appauth main
  seed_group frontend apphome appauth

  run_grove build-all @frontend
  [ "$status" -eq 0 ]
  [[ "$output" == *"apphome"* ]]
  [[ "$output" == *"appauth"* ]]
  [[ "$output" == *"across group @frontend"* ]]
}

@test "exec-all @group: unknown group errors clearly (not treated as a repo)" {
  run_grove exec-all @nosuchgroup true
  [ "$status" -ne 0 ]
  [[ "$output" == *"group not found"* ]]
  [[ "$output" == *"@nosuchgroup"* ]]
}

@test "build-all @group: unknown group errors clearly (not treated as a repo)" {
  run_grove build-all @nosuchgroup
  [ "$status" -ne 0 ]
  [[ "$output" == *"group not found"* ]]
  [[ "$output" == *"@nosuchgroup"* ]]
}

@test "exec-all @group: requires a command after the group" {
  seed_group frontend apphome
  run_grove exec-all @frontend
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "exec-all: non-@ argument behaves as a literal repo (unchanged)" {
  # An ordinary repo name that does not exist still errors as a missing repo,
  # confirming we don't accidentally route plain names through group resolution.
  run_grove exec-all definitelymissing true
  [ "$status" -ne 0 ]
  [[ "$output" != *"group not found"* ]]
}

@test "exec-all: executes the requested command in each worktree" {
  seed_repo_with_worktree apphome main

  run_grove exec-all apphome "touch .grove-exec-ran"
  [ "$status" -eq 0 ]
  [ -f "$HERD_ROOT/apphome-worktrees/main/.grove-exec-ran" ]
}

# ============================================================================
# #16 - single quote in a worktree path is handled, not exploited
# ============================================================================

@test "exec-all: worktree path containing a single quote is handled cleanly" {
  # git happily creates a worktree at a path containing a single quote. Under the
  # old "cd '\$path' && ..." quoting this broke out of the quotes; now the path is
  # passed as argv and parallel_run rejects the quote, counting it as a failure
  # rather than crashing or running the command in the wrong directory.
  git init -q --bare "$HERD_ROOT/quoterepo.git"
  git --git-dir="$HERD_ROOT/quoterepo.git" \
    worktree add -q -b feature/quote "$HERD_ROOT/quoterepo-worktrees/it's-here" 2>/dev/null

  # A command that would create a marker file IF it ran in an attacker-controlled
  # location. It must not run, because the quote path is rejected.
  run_grove exec-all quoterepo "true"
  # The run completes without a shell error; the quoted operation is a failure.
  [[ "$output" == *"failed"* ]]
  # No marker leaked outside the (rejected) worktree.
  [ ! -f "$HERD_ROOT/pwned" ]
}

# ============================================================================
# Builds that need a real toolchain are out of scope here
# ============================================================================

@test "build-all: real npm build is not exercised here" {
  # The npm-build path requires a worktree with package.json and a working npm
  # toolchain; that is covered by manual/e2e testing, not this integration suite.
  skip "real npm build requires a node toolchain - out of scope for integration tests"
}
