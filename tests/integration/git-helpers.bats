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

# A worktree whose files are offloaded to iCloud can stall `git status` for
# minutes; the listing must give up on it rather than hang.
@test "_worktree_status_record: gives up on a git status that hangs" {
  mkdir -p "$TEST_TEMP_DIR/slowbin"
  printf '#!/bin/sh\nexec sleep 15\n' > "$TEST_TEMP_DIR/slowbin/git"
  chmod +x "$TEST_TEMP_DIR/slowbin/git"
  local started=$SECONDS
  run env PATH="$TEST_TEMP_DIR/slowbin:$PATH" GROVE_STATUS_TIMEOUT=1 \
    zsh -c "source '$GIT_FNS'; _worktree_status_record '$REPO' ''"
  [ "$status" -eq 1 ]
  [ $((SECONDS - started)) -lt 10 ]
}

@test "git_status_bounded: refuses at once a worktree the collection already failed on" {
  mkdir -p "$TEST_TEMP_DIR/slowbin"
  printf '#!/bin/sh\nexec sleep 15\n' > "$TEST_TEMP_DIR/slowbin/git"
  chmod +x "$TEST_TEMP_DIR/slowbin/git"
  local started=$SECONDS
  run env PATH="$TEST_TEMP_DIR/slowbin:$PATH" GROVE_STATUS_TIMEOUT=5 \
    zsh -c "source '$GIT_FNS'; _GROVE_STATUS_UNREADABLE[$REPO]=1; git_status_bounded '$REPO' --porcelain"
  [ "$status" -eq 1 ]
  [ $((SECONDS - started)) -lt 3 ]
}

# iCloud-offloaded files keep their size and modified time but change ctime and
# inode. Comparing those would make git read, and so download, every file.
@test "git_status_bounded: compares only size and modified time" {
  mkdir -p "$TEST_TEMP_DIR/argsbin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s/git-args"\n' "$TEST_TEMP_DIR" > "$TEST_TEMP_DIR/argsbin/git"
  chmod +x "$TEST_TEMP_DIR/argsbin/git"
  run env PATH="$TEST_TEMP_DIR/argsbin:$PATH" zsh -c "source '$GIT_FNS'; git_status_bounded '$REPO' --porcelain"
  [ "$status" -eq 0 ]
  grep -q 'core.checkStat=minimal' "$TEST_TEMP_DIR/git-args"
  grep -q 'core.trustctime=false' "$TEST_TEMP_DIR/git-args"
}

@test "git_status_bounded: still sees an edit that keeps the file's size" {
  echo one > "$REPO/tracked-same-size"
  touch -t 202001010101 "$REPO/tracked-same-size"
  git -C "$REPO" add tracked-same-size
  git -C "$REPO" -c user.name=t -c user.email=t@example.test commit -qm tracked
  echo two > "$REPO/tracked-same-size"
  touch -t 202002020202 "$REPO/tracked-same-size"
  run zsh -c "source '$GIT_FNS'; git_status_bounded '$REPO' --porcelain"
  [ "$status" -eq 0 ]
  [[ "$output" == *"M tracked-same-size"* ]]
}

@test "git_status_bounded: a git that cannot start is a failure, not a clean result" {
  mkdir -p "$TEST_TEMP_DIR/nogit"
  ln -s "$(command -v perl)" "$TEST_TEMP_DIR/nogit/perl"
  run env PATH="$TEST_TEMP_DIR/nogit" "$(command -v zsh)" -c "source '$GIT_FNS'; git_status_bounded '$REPO' --porcelain"
  [ "$status" -ne 0 ]
}

@test "git_status_bounded: a time limit that would disable the alarm falls back to 10s" {
  mkdir -p "$TEST_TEMP_DIR/perlbin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$3" >> "%s/limit"\n' "$TEST_TEMP_DIR" > "$TEST_TEMP_DIR/perlbin/perl"
  chmod +x "$TEST_TEMP_DIR/perlbin/perl"
  local bad
  for bad in 0 0.5 abc; do
    run env PATH="$TEST_TEMP_DIR/perlbin:$PATH" GROVE_STATUS_TIMEOUT="$bad" zsh -c "source '$GIT_FNS'; git_status_bounded '$REPO' --porcelain"
    [ "$status" -eq 0 ]
  done
  [ "$(sort -u "$TEST_TEMP_DIR/limit")" = "10" ]
}

@test "git_status_bounded: still reads status where perl is not installed" {
  mkdir -p "$TEST_TEMP_DIR/noperl"
  printf '#!/bin/sh\necho read-without-perl\n' > "$TEST_TEMP_DIR/noperl/git"
  chmod +x "$TEST_TEMP_DIR/noperl/git"
  run env PATH="$TEST_TEMP_DIR/noperl" "$(command -v zsh)" -c "source '$GIT_FNS'; git_status_bounded '$REPO' --porcelain"
  [ "$status" -eq 0 ]
  [[ "$output" == *read-without-perl* ]]
}

@test "git_status_bounded: without perl, timeout carries the time limit" {
  mkdir -p "$TEST_TEMP_DIR/noperl"
  printf '#!/bin/sh\necho "limit=$1 via timeout"\n' > "$TEST_TEMP_DIR/noperl/timeout"
  chmod +x "$TEST_TEMP_DIR/noperl/timeout"
  run env PATH="$TEST_TEMP_DIR/noperl" GROVE_STATUS_TIMEOUT=7 "$(command -v zsh)" -c "source '$GIT_FNS'; git_status_bounded '$REPO' --porcelain"
  [ "$status" -eq 0 ]
  [[ "$output" == *"limit=7 via timeout"* ]]
}
