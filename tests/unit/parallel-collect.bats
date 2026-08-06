#!/usr/bin/env bats
# parallel-collect.bats - Tests for parallel_collect in lib/09-parallel.sh.
#
# parallel_collect fans per-worktree work out across subshells. It exists because
# `grove ls` walked worktrees one at a time, which put a repo with fifteen of them
# at ~30s and read as a hang from the Grove desktop app.
#
# The property that matters is ORDER. Results are indexed by input position and
# read back in that order, never in completion order, so `grove ls` output does
# not depend on which worktree's git calls happened to finish first. Every test
# here that involves timing deliberately makes completion order DISAGREE with
# input order, because a naive implementation passes if they happen to match.
#
# These source lib/09-parallel.sh directly (not the built grove) so they validate
# the source, independent of the build artifact.

load '../test-helper'

setup() {
  setup_test_environment
}

teardown() {
  teardown_test_environment
}

# Run a zsh snippet with the real lib/09-parallel.sh functions in scope.
#
# A watchdog kills the shell rather than letting it spin: the drain regression
# below is an INFINITE LOOP when it reappears, and a hung suite is far worse to
# diagnose than a failed assertion.
_parallel() {
  run zsh -c "
    set -uo pipefail
    { sleep 20; kill -9 \$\$ 2>/dev/null } &
    _watchdog=\$!
    source '$GROVE_ROOT/lib/09-parallel.sh'
    $1
    kill \$_watchdog 2>/dev/null
  "
}

# ============================================================================
# Ordering — the reason this primitive exists
# ============================================================================

@test "parallel_collect: replies are in INPUT order, not completion order" {
  # Item 1 finishes LAST. If replies were gathered as workers finished, this
  # would come back reversed.
  _parallel '
    cb() {
      case "$2" in
        1) sleep 0.45 ;;
        2) sleep 0.25 ;;
        3) sleep 0.05 ;;
      esac
      REPLY="r-$1"
    }
    items=(alpha beta gamma)
    replies=()
    GROVE_STATUS_PARALLEL=3
    parallel_collect cb items replies
    print -r -- "${replies[*]}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "r-alpha r-beta r-gamma" ]
}

@test "parallel_collect: stdout is replayed in INPUT order" {
  # Text-mode `grove ls` prints its rows rather than returning them, so the
  # captured stdout has to be replayed in the same order as the replies.
  _parallel '
    cb() {
      case "$2" in
        1) sleep 0.45 ;;
        2) sleep 0.25 ;;
        3) sleep 0.05 ;;
      esac
      print -r -- "row-$1"
    }
    items=(alpha beta gamma)
    replies=()
    GROVE_STATUS_PARALLEL=3
    parallel_collect cb items replies
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "row-alpha" ]
  [ "${lines[1]}" = "row-beta" ]
  [ "${lines[2]}" = "row-gamma" ]
}

@test "parallel_collect: the callback receives the 1-based input index" {
  # `grove ls` numbers its rows from this index, so it must track input
  # position rather than the order work completed.
  _parallel '
    cb() { REPLY="$2:$1" }
    items=(a b c)
    replies=()
    parallel_collect cb items replies
    print -r -- "${replies[*]}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "1:a 2:b 3:c" ]
}

# ============================================================================
# Throttle draining — regression
# ============================================================================

@test "parallel_collect: a concurrency limit of 1 terminates" {
  # REGRESSION: the throttle drained with _pc_pids=("${_pc_pids[2,-1]}"), and on
  # a ONE-element array that slice expands to a single EMPTY word — so the array
  # never shrank below one, the while loop spun forever, and the command hung.
  # A default limit of 8 hid it, because the array only reaches one element when
  # the limit is one. Draining with `shift` is what fixes it.
  _parallel '
    cb() { REPLY="r-$1" }
    items=(a b c d)
    replies=()
    GROVE_STATUS_PARALLEL=1
    parallel_collect cb items replies
    print -r -- "${replies[*]}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "r-a r-b r-c r-d" ]
}

@test "parallel_collect: a limit of 2 drains without stalling" {
  # The neighbouring case: the array reaches one element mid-run and must still
  # fall below the limit.
  _parallel '
    cb() { REPLY="r-$1" }
    items=(a b c d e)
    replies=()
    GROVE_STATUS_PARALLEL=2
    parallel_collect cb items replies
    print -r -- "${replies[*]}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "r-a r-b r-c r-d r-e" ]
}

@test "parallel_collect: a non-numeric or zero limit falls back to serial, not a stall" {
  for bad in 0 "" abc -3; do
    _parallel "
      cb() { REPLY=\"r-\$1\" }
      items=(a b c)
      replies=()
      GROVE_STATUS_PARALLEL='$bad'
      parallel_collect cb items replies
      print -r -- \"\${replies[*]}\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "r-a r-b r-c" ]
  done
}

# ============================================================================
# Work actually runs concurrently
# ============================================================================

@test "parallel_collect: work runs concurrently, not one at a time" {
  # Four items sleeping 0.4s each: serial is >=1.6s, four-wide should land well
  # under 1s. Without this the whole change could regress to a serial walk and
  # every other test here would still pass.
  _parallel '
    cb() { sleep 0.4; REPLY="r-$1" }
    items=(a b c d)
    replies=()
    GROVE_STATUS_PARALLEL=4
    start=$SECONDS
    parallel_collect cb items replies
    elapsed=$(( SECONDS - start ))
    print -r -- "${replies[*]} elapsed=$elapsed"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "r-a r-b r-c r-d elapsed=0" ]]
}

# ============================================================================
# Failure and edge cases
# ============================================================================

@test "parallel_collect: a failing callback yields an empty reply, never a partial one" {
  # Callers treat an empty reply as "no row". A half-built value escaping here
  # would put a truncated object into the JSON array.
  _parallel '
    cb() {
      REPLY="partial-$1"
      [[ "$1" == bad ]] && return 1
      REPLY="r-$1"
    }
    items=(good bad other)
    replies=()
    parallel_collect cb items replies
    print -r -- "[${replies[1]}][${replies[2]}][${replies[3]}]"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "[r-good][][r-other]" ]
}

@test "parallel_collect: an empty item list yields an empty reply array" {
  _parallel '
    cb() { REPLY="r-$1" }
    items=()
    replies=(stale)
    parallel_collect cb items replies
    print -r -- "count=${#replies[@]}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "count=0" ]
}

@test "parallel_collect: a callback setting no REPLY yields an empty string" {
  _parallel '
    cb() { : }
    items=(a b)
    replies=()
    parallel_collect cb items replies
    print -r -- "count=${#replies[@]} [${replies[1]}][${replies[2]}]"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "count=2 [][]" ]
}

@test "parallel_collect: REPLY does not leak between items" {
  # Each item runs in its own subshell, so a value set by one must never be
  # visible to the next — otherwise a worktree that sets nothing would inherit
  # its predecessor's row.
  _parallel '
    cb() {
      [[ "$1" == first ]] && REPLY="sticky"
    }
    items=(first second)
    replies=()
    GROVE_STATUS_PARALLEL=1
    parallel_collect cb items replies
    print -r -- "[${replies[1]}][${replies[2]}]"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "[sticky][]" ]
}

@test "parallel_collect: items containing spaces survive intact" {
  # Worktree paths can contain spaces; splitting one would silently list the
  # wrong directory.
  _parallel '
    cb() { REPLY="[$1]" }
    items=("a b" "c  d")
    replies=()
    parallel_collect cb items replies
    print -r -- "${replies[1]}${replies[2]}"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "[a b][c  d]" ]
}
