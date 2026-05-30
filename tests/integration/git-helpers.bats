#!/usr/bin/env bats
# git-helpers.bats - Integration tests for the real zsh helpers in lib/04-git.sh.
#
# These exercise the ACTUAL zsh implementations (sourced via zsh against a real
# temp git repo + worktrees), not bash reimplementations. They guard three
# regressions fixed in lib/04-git.sh:
#   1. iterate_worktrees silently dropped detached-HEAD worktrees.
#   2. get_ahead_behind returned "0 0" when the base ref was unresolved,
#      indistinguishable from a genuinely level branch.
#   3. remote_branch_exists used an unanchored grep that false-positived on
#      branches whose names are prefixes of one another.

load '../test-helper'

setup() {
  setup_test_environment

  # Build a sourceable zsh file: stub the cross-module dependencies that
  # lib/04-git.sh expects (validation/output/time helpers live in other modules),
  # then append the real lib/04-git.sh body. We deliberately source ONLY this
  # module so the test pins the helpers we are exercising.
  GIT_FNS="$TEST_TEMP_DIR/git-fns.zsh"
  export GIT_FNS
  cat > "$GIT_FNS" <<'STUB'
validate_git_ref() { return 0; }
warn() { print -r -- "WARN: $1" >&2; }
dim()  { :; }
_get_now() { date +%s; }
JSON_OUTPUT=false
STUB
  cat "$GROVE_ROOT/lib/04-git.sh" >> "$GIT_FNS"

  # A real repo with a normal worktree and a detached-HEAD worktree.
  REPO="$TEST_TEMP_DIR/repo"
  export REPO
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name 'Test'
  git -C "$REPO" commit -q --allow-empty -m init
  HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
  export HEAD_SHA
  git -C "$REPO" worktree add -q --detach "$TEST_TEMP_DIR/wt-detached" "$HEAD_SHA"
}

teardown() {
  teardown_test_environment
}

# Run a snippet against the sourced helpers in a clean zsh process.
run_zsh() {
  run zsh -c "source '$GIT_FNS'; $1"
}

# ============================================================================
# iterate_worktrees — detached HEAD must remain visible
# ============================================================================

@test "iterate_worktrees: visits a detached-HEAD worktree (not dropped)" {
  run_zsh "cb() { print -r -- \"\$1\"; }; iterate_worktrees '$REPO/.git' cb"
  [ "$status" -eq 0 ]
  # Both the main worktree and the detached one must appear.
  [[ "$output" == *"$REPO"* ]]
  [[ "$output" == *"wt-detached"* ]]
}

@test "iterate_worktrees: detached worktree reports the (detached) sentinel branch" {
  run_zsh "cb() { print -r -- \"\$1|\$2\"; }; iterate_worktrees '$REPO/.git' cb"
  [ "$status" -eq 0 ]
  # The detached worktree's branch field is the documented sentinel.
  [[ "$output" == *"wt-detached|(detached)"* ]]
  # The normal worktree still reports its real branch.
  [[ "$output" == *"|main"* ]]
}

# ============================================================================
# get_ahead_behind — unknown vs zero
# ============================================================================

@test "get_ahead_behind: returns the unknown sentinel when base is unresolved" {
  # origin/does-not-exist cannot be resolved -> must NOT look level (0 0).
  run_zsh "get_ahead_behind '$REPO' 'origin/does-not-exist'"
  [ "$status" -eq 0 ]
  [ "$output" = '? ?' ]
}

@test "get_ahead_behind: returns numeric 0 0 when base resolves and is level" {
  run_zsh "get_ahead_behind '$REPO' 'HEAD'"
  [ "$status" -eq 0 ]
  [ "$output" = '0 0' ]
}

@test "get_commits_behind: returns the unknown sentinel when base is unresolved" {
  run_zsh "get_commits_behind '$REPO' 'origin/does-not-exist'"
  [ "$status" -eq 0 ]
  [ "$output" = '?' ]
}

# ============================================================================
# remote_branch_exists — exact ref match only
# ============================================================================

@test "remote_branch_exists: matches exact refs, not prefixes" {
  # Stand up a bare remote with two branches whose names are prefixes of each
  # other: 'feature' and 'feature-extra'.
  local remote="$TEST_TEMP_DIR/origin.git"
  git init -q --bare -b main "$remote"
  git -C "$REPO" branch feature
  git -C "$REPO" branch feature-extra
  git -C "$REPO" remote add origin "$remote"
  git -C "$REPO" push -q origin main feature feature-extra

  # A consumer repo whose origin points at the bare remote.
  git clone -q "$remote" "$TEST_TEMP_DIR/consumer"
  local gitdir="$TEST_TEMP_DIR/consumer/.git"

  # Exact existing branch -> success.
  run_zsh "remote_branch_exists '$gitdir' 'feature'"
  [ "$status" -eq 0 ]

  # 'featur' is a strict prefix of 'feature'; the old unanchored grep gave a
  # false positive here. The fixed awk match must reject it.
  run_zsh "remote_branch_exists '$gitdir' 'featur'"
  [ "$status" -ne 0 ]

  # A name that simply does not exist.
  run_zsh "remote_branch_exists '$gitdir' 'totallymissing'"
  [ "$status" -ne 0 ]
}
