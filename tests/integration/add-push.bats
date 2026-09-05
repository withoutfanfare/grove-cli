#!/usr/bin/env bats
# add-push.bats - `grove add` and the push of a brand-new branch to origin.
#
# A new branch has always been pushed the moment its worktree exists, with no
# way to opt out; GROVE_SKIP_PUSH=true in a template now keeps it local. These
# tests run the REAL compiled grove against a real bare repository whose origin
# is a plain seed repository, so "was it pushed?" is answered by looking in the
# seed rather than by trusting a message.

load '../test-helper'

setup() {
  bats_require_minimum_version 1.5.0
  setup_test_environment
  export GROVE_SCRIPT="$GROVE_ROOT/grove"

  SEED="$TEST_TEMP_DIR/seed"
  export SEED
  mkdir -p "$TEST_TEMP_DIR/home" "$TEST_TEMP_DIR/.grove/templates"
  git init -q -b main "$SEED"
  git -C "$SEED" config user.email test@example.invalid
  git -C "$SEED" config user.name Grove-Test
  git -C "$SEED" commit -q --allow-empty -m init
  git clone -q --bare "$SEED" "$HERD_ROOT/testrepo.git"

  cat > "$TEST_TEMP_DIR/.grove/templates/local-only.conf" << 'EOF'
TEMPLATE_DESC="Keep new branches off the remote"
GROVE_SKIP_PUSH=true
EOF
}

teardown() {
  teardown_test_environment
}

# Run the compiled grove in the hermetic environment the other integration
# tests use. QUIET=false so the info/dim lines under test reach stderr.
grove_run() {
  run --separate-stderr env \
    HOME="$TEST_TEMP_DIR/home" \
    PATH="/usr/bin:/bin" \
    HERD_ROOT="$HERD_ROOT" \
    GROVE_HOOKS_DIR="$GROVE_HOOKS_DIR" \
    GROVE_TEMPLATES_DIR="$TEST_TEMP_DIR/.grove/templates" \
    NO_COLOR=1 QUIET=false \
    zsh "$GROVE_SCRIPT" "$@"
}

@test "add: a brand-new branch is pushed to origin by default" {
  grove_run add testrepo feature/pushed main --dir pushed --force
  [ "$status" -eq 0 ]
  [ -n "$(git -C "$SEED" branch --list feature/pushed)" ]
  [[ "$stderr" == *"Remote branch created"* ]]
}

@test "add: GROVE_SKIP_PUSH=true keeps the new branch local and names the push it skipped" {
  grove_run -t local-only add testrepo feature/quiet main --dir quiet --force
  [ "$status" -eq 0 ]
  [ -z "$(git -C "$SEED" branch --list feature/quiet)" ]
  [ "$(git -C "$HERD_ROOT/testrepo-worktrees/quiet" branch --show-current)" = "feature/quiet" ]
  [[ "$stderr" == *"Skipping push (GROVE_SKIP_PUSH=true): git push -u origin feature/quiet"* ]]
  [[ "$stderr" != *"Remote branch created"* ]]
}

@test "add --dry-run: shows GROVE_SKIP_PUSH and the skipped push step" {
  grove_run -t local-only add testrepo feature/quiet main --dir quiet --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"GROVE_SKIP_PUSH=true"* ]]
  [[ "$output" == *"Skip the push (GROVE_SKIP_PUSH=true)"* ]]
  [[ "$output" != *"Push branch to remote"* ]]
}

@test "add --dry-run: without the flag the push step is still listed" {
  grove_run add testrepo feature/quiet main --dir quiet --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Push branch to remote and set up tracking"* ]]
}
