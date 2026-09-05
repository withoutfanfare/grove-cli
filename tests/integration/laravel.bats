#!/usr/bin/env bats
# laravel.bats - Integration tests for grove Laravel commands (migrate, tinker)
#
# These tests exercise the artisan wrappers' guards and exit-status
# propagation. They create a registered worktree under HERD_ROOT and put a
# stub `artisan` file in it.

load '../test-helper'

setup() {
  setup_test_environment

  export GROVE_SCRIPT="$GROVE_ROOT/grove"

  # Build a registered worktree the artisan wrappers will resolve to.
  # worktree_path_for() = $HERD_ROOT/<repo>-worktrees/<site_name>
  # For branch "feature/test" the site name slugifies to "feature-test".
  WT_PATH="$HERD_ROOT/testrepo-worktrees/feature-test"
  git init -q -b main "$TEST_TEMP_DIR/seed"
  git -C "$TEST_TEMP_DIR/seed" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m init
  git clone -q --bare "$TEST_TEMP_DIR/seed" "$HERD_ROOT/testrepo.git"
  git --git-dir="$HERD_ROOT/testrepo.git" worktree add -q -b feature/test "$WT_PATH" main
  # A stub artisan file so the "not a Laravel project" guard passes.
  printf '#!/usr/bin/env php\n' > "$WT_PATH/artisan"

  # A clean directory we can point PATH at to hide the real `php`.
  export FAKE_BIN="$TEST_TEMP_DIR/fakebin"
  mkdir -p "$FAKE_BIN"

  # PATH that keeps core tools (date, git, bash) available but excludes the
  # Herd/Homebrew locations where php normally lives, so `command -v php` fails.
  export PHP_ABSENT_PATH="$FAKE_BIN:/usr/bin:/bin"

  # Neutralise any real ~/.groverc so it cannot override our test HERD_ROOT
  # (load_config reads $GROVE_CONFIG, defaulting to ~/.groverc).
  export GROVE_CONFIG="$TEST_TEMP_DIR/empty-groverc"
  : > "$GROVE_CONFIG"
}

teardown() {
  teardown_test_environment
}

# Run grove with the test environment and a controlled PATH.
# $1 = PATH to use, remaining args passed to grove.
run_grove_with_path() {
  local use_path="$1"; shift
  HERD_ROOT="$HERD_ROOT" \
  GROVE_HOOKS_DIR="$GROVE_HOOKS_DIR" \
  GROVE_CONFIG="$GROVE_CONFIG" \
  NO_COLOR=1 \
  PATH="$use_path" \
  run zsh "$GROVE_SCRIPT" "$@"
}

# ============================================================================
# php-missing guard
# ============================================================================

@test "grove migrate: errors clearly when php is absent" {
  run_grove_with_path "$PHP_ABSENT_PATH" migrate testrepo feature/test
  [ "$status" -ne 0 ]
  [[ "$output" == *"php"* ]]
  [[ "$output" == *"not found"* ]]
}

@test "grove tinker: errors clearly when php is absent" {
  run_grove_with_path "$PHP_ABSENT_PATH" tinker testrepo feature/test
  [ "$status" -ne 0 ]
  [[ "$output" == *"php"* ]]
  [[ "$output" == *"not found"* ]]
}

# ============================================================================
# artisan exit-status propagation
# ============================================================================

@test "grove migrate: propagates a non-zero artisan exit code" {
  # Stub php that exits 17 regardless of arguments.
  cat > "$FAKE_BIN/php" << 'EOF'
#!/usr/bin/env bash
exit 17
EOF
  chmod +x "$FAKE_BIN/php"

  run_grove_with_path "$FAKE_BIN:$PATH" migrate testrepo feature/test
  [ "$status" -eq 17 ]
}

@test "grove migrate: returns success when artisan succeeds" {
  # Stub php that exits 0.
  cat > "$FAKE_BIN/php" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FAKE_BIN/php"

  run_grove_with_path "$FAKE_BIN:$PATH" migrate testrepo feature/test
  [ "$status" -eq 0 ]
}
