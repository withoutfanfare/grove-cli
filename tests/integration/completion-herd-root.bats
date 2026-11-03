#!/usr/bin/env bats
# completion-herd-root.bats - _grove resolves HERD_ROOT like grove does:
# environment first, then the config file (read literally, never sourced).

load '../test-helper'

setup() {
  setup_test_environment
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME/Sites/fromconfig.git" "$HERD_ROOT/fromenv.git"
  sed '/^_grove "\$@"$/d' "$GROVE_ROOT/_grove" > "$TEST_TEMP_DIR/_grove.zsh"
}

teardown() {
  teardown_test_environment
}

_repos() {
  run zsh -c "
    source '$TEST_TEMP_DIR/_grove.zsh'
    _describe() { print -rl -- \"\${(@P)2}\"; }
    _grove_repos
  "
}

@test "completion: HERD_ROOT from the config file when env is unset" {
  unset HERD_ROOT
  printf 'HERD_ROOT="~/Sites" # mine\n' > "$GROVE_CONFIG"
  _repos
  [ "$status" -eq 0 ]
  [ "$output" = "fromconfig" ]
}

@test "completion: environment HERD_ROOT beats the config file" {
  printf 'HERD_ROOT=$HOME/Sites\n' > "$GROVE_CONFIG"
  _repos
  [ "$output" = "fromenv" ]
}

@test "completion: config HERD_ROOT is never executed" {
  unset HERD_ROOT
  printf 'HERD_ROOT=$(touch %s/pwned)\n' "$TEST_TEMP_DIR" > "$GROVE_CONFIG"
  _repos
  [ ! -e "$TEST_TEMP_DIR/pwned" ]
}

@test "completion: all branches reads local refs without fetching" {
  run zsh -c '
    source "$TEST_TEMP_DIR/_grove.zsh"
    git() {
      print -r -- "$*" >> "$TEST_TEMP_DIR/git-calls"
      [[ "$*" == *"branch -r" ]] && print "  origin/feature/example"
      return 0
    }
    _describe() { print -rl -- "${(@P)2}"; }
    _grove_all_branches fromenv
    wait
  '
  [ "$status" -eq 0 ]
  [ "$output" = "feature/example" ]
  ! grep -q fetch "$TEST_TEMP_DIR/git-calls"
}
