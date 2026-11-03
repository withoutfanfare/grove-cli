#!/usr/bin/env bats
# install.bats - install.sh helpers, exercised without running the installer.
#
# install.sh runs its whole install at the bottom, so it is never executed
# here: the function under test is extracted and evaluated in isolation
# against a disposable HOME.

load '../test-helper'

setup() {
  setup_test_environment
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME/.grove/hooks/post-add.d" "$TEST_TEMP_DIR/examples/post-add.d"
  INSTALL_FN="$TEST_TEMP_DIR/install-fn.bash"
  {
    printf "RED='' GREEN='' YELLOW='' BLUE='' DIM='' NC='' QUIET=true\n"
    sed -n '/^install_hooks_overwrite() {/,/^}/p' "$GROVE_ROOT/install.sh"
  } > "$INSTALL_FN"
}

teardown() {
  chmod -R u+rw "$TEST_TEMP_DIR" 2>/dev/null || true
  teardown_test_environment
}

@test "install_hooks_overwrite: backs up hooks, keeping their folders, before replacing them" {
  printf 'mine\n' > "$HOME/.grove/hooks/post-add.d/10-mine.sh"
  printf 'example\n' > "$TEST_TEMP_DIR/examples/post-add.d/05-example.sh"

  run bash -c "source '$INSTALL_FN'; install_hooks_overwrite '$HOME/.grove/hooks' '$TEST_TEMP_DIR/examples'"
  [ "$status" -eq 0 ]
  local backup; backup="$(echo "$HOME"/.grove/hooks.backup.*)"
  [ "$(cat "$backup/post-add.d/10-mine.sh")" = "mine" ]
  [ ! -e "$HOME/.grove/hooks/post-add.d/10-mine.sh" ]
  [ -f "$HOME/.grove/hooks/post-add.d/05-example.sh" ]
}

@test "install_hooks_overwrite: a backup copy failure aborts before any hook is deleted" {
  [ "$(id -u)" -ne 0 ] || skip "root can read unreadable files"
  printf 'mine\n' > "$HOME/.grove/hooks/post-add.d/10-mine.sh"
  printf 'secret\n' > "$HOME/.grove/hooks/post-add.d/99-sentinel.sh"
  chmod 000 "$HOME/.grove/hooks/post-add.d/99-sentinel.sh"   # cp cannot read it
  printf 'example\n' > "$TEST_TEMP_DIR/examples/post-add.d/05-example.sh"

  run bash -c "source '$INSTALL_FN'; install_hooks_overwrite '$HOME/.grove/hooks' '$TEST_TEMP_DIR/examples'"
  [ "$status" -ne 0 ]
  # Nothing deleted, nothing installed over the user's hooks.
  [ -e "$HOME/.grove/hooks/post-add.d/99-sentinel.sh" ]
  [ -f "$HOME/.grove/hooks/post-add.d/10-mine.sh" ]
  [ ! -e "$HOME/.grove/hooks/post-add.d/05-example.sh" ]
  [[ "$output" != *"Backed up existing hooks"* ]]
}
