#!/usr/bin/env bats
# worktree-base.bats - Integration tests for the per-worktree base sidecar in
# lib/04-git.sh, exercising the REAL zsh helpers against real git worktrees.
#
# The bug these pin: grove stored the base ref with `git config --local
# grove.base`. On a bare-repository layout — which is exactly how the Scooda
# worktrees are set up — `--local` resolves from the *common* config, so every
# linked worktree read the same value. A worktree branched from `origin/staging`
# would silently report whatever base the last one happened to set.
#
# The fix is `git rev-parse --git-path grove-base`, which resolves to each
# worktree's own administrative directory. The legacy config is still read, so
# worktrees created before the change keep working.

load '../test-helper'

setup() {
  setup_test_environment

  # Source only lib/04-git.sh, stubbing its cross-module dependencies, so these
  # tests pin the helpers under test rather than the whole binary.
  GIT_FNS="$TEST_TEMP_DIR/git-fns.zsh"
  export GIT_FNS
  cat > "$GIT_FNS" <<'STUB'
validate_git_ref() { return 0; }
warn() { print -r -- "WARN: $1" >&2; }
dim()  { :; }
_get_now() { date +%s; }
JSON_OUTPUT=false
DEFAULT_BASE="origin/main"
STUB
  cat "$GROVE_ROOT/lib/04-git.sh" >> "$GIT_FNS"

  # A bare repository with two linked worktrees — the layout that exposed the bug.
  BARE="$TEST_TEMP_DIR/repo.git"
  export BARE
  git init -q --bare "$BARE"

  SEED="$TEST_TEMP_DIR/seed"
  git clone -q "$BARE" "$SEED"
  git -C "$SEED" config user.email t@t.t
  git -C "$SEED" config user.name 'Test'
  git -C "$SEED" commit -q --allow-empty -m init
  git -C "$SEED" push -q origin HEAD:main

  WT_A="$TEST_TEMP_DIR/wt-a"
  WT_B="$TEST_TEMP_DIR/wt-b"
  export WT_A WT_B
  git --git-dir="$BARE" worktree add -q -b feature-a "$WT_A" main
  git --git-dir="$BARE" worktree add -q -b feature-b "$WT_B" main
}

teardown() {
  teardown_test_environment
}

# Run a zsh snippet with lib/04-git.sh sourced.
run_zsh() {
  run zsh -c "source '$GIT_FNS'; $1"
}

@test "worktree_base_for: two linked worktrees keep different base refs" {
  # The regression this whole change exists for.
  run_zsh "set_worktree_base '$WT_A' 'origin/staging'; set_worktree_base '$WT_B' 'origin/develop'; print -r -- \"\$(worktree_base_for '$WT_A')|\$(worktree_base_for '$WT_B')\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"origin/staging|origin/develop"* ]]
}

@test "worktree_base_for: the sidecar lives in the worktree's own git directory" {
  run_zsh "set_worktree_base '$WT_A' 'origin/staging'"
  [ "$status" -eq 0 ]

  local sidecar
  sidecar="$(git -C "$WT_A" rev-parse --git-path grove-base)"
  [ -f "$sidecar" ]
  [[ "$(cat "$sidecar")" == "origin/staging" ]]

  # And it is NOT in the shared common directory, which is what caused the bug.
  [ ! -f "$BARE/grove-base" ]
}

@test "set_worktree_base: never enables extensions.worktreeConfig" {
  run_zsh "set_worktree_base '$WT_A' 'origin/staging'"
  [ "$status" -eq 0 ]

  run git -C "$WT_A" config --get extensions.worktreeConfig
  [ "$status" -ne 0 ]
}

@test "worktree_base_for: reads a legacy grove.base when no sidecar exists" {
  # A worktree created before the sidecar existed must keep working.
  git -C "$WT_A" config --local grove.base 'origin/legacy'

  run_zsh "worktree_base_for '$WT_A'"
  [ "$status" -eq 0 ]
  [[ "$output" == "origin/legacy" ]]
}

@test "worktree_base_for: the sidecar wins over the legacy config" {
  git -C "$WT_A" config --local grove.base 'origin/legacy'
  run_zsh "set_worktree_base '$WT_A' 'origin/staging'; worktree_base_for '$WT_A'"
  [ "$status" -eq 0 ]
  [[ "$output" == "origin/staging" ]]
}

@test "worktree_base_for: falls back to the supplied default when nothing is recorded" {
  run_zsh "worktree_base_for '$WT_A' 'origin/fallback'"
  [ "$status" -eq 0 ]
  [[ "$output" == "origin/fallback" ]]
}

@test "worktree_base_for: an empty sidecar falls through rather than returning nothing" {
  local sidecar
  sidecar="$(git -C "$WT_A" rev-parse --git-path grove-base)"
  : > "$sidecar"

  run_zsh "worktree_base_for '$WT_A' 'origin/fallback'"
  [ "$status" -eq 0 ]
  [[ "$output" == "origin/fallback" ]]
}

@test "set_worktree_base: writing twice replaces rather than appends" {
  run_zsh "set_worktree_base '$WT_A' 'origin/staging'; set_worktree_base '$WT_A' 'origin/develop'; worktree_base_for '$WT_A'"
  [ "$status" -eq 0 ]
  [[ "$output" == "origin/develop" ]]

  local sidecar
  sidecar="$(git -C "$WT_A" rev-parse --git-path grove-base)"
  [ "$(wc -l < "$sidecar" | tr -d ' ')" -eq 1 ]
}

@test "set_worktree_base: an empty base is a no-op, not an empty sidecar" {
  run_zsh "set_worktree_base '$WT_A' ''; worktree_base_for '$WT_A' 'origin/fallback'"
  [ "$status" -eq 0 ]
  [[ "$output" == "origin/fallback" ]]
}

@test "set_worktree_base: still records the legacy config so an older grove finds a base" {
  # Compatibility for at least one release (specification §Rollback strategy).
  run_zsh "set_worktree_base '$WT_A' 'origin/staging'"
  [ "$status" -eq 0 ]

  run git -C "$WT_A" config --local --get grove.base
  [ "$status" -eq 0 ]
  [[ "$output" == "origin/staging" ]]
}

@test "worktree_base_for: a non-worktree path degrades to the fallback without erroring" {
  run_zsh "worktree_base_for '$TEST_TEMP_DIR/not-a-worktree' 'origin/fallback'"
  [ "$status" -eq 0 ]
  [[ "$output" == "origin/fallback" ]]
}
