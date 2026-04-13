#!/usr/bin/env bats
# hooks.bats - Integration tests for the grove hook system
#
# Tests hook execution order, environment variables, repo-specific hooks,
# hook failure handling, permission checks, and graceful handling of
# missing hooks directories.

load '../test-helper'

setup() {
  setup_test_environment

  export GROVE_SCRIPT="$GROVE_ROOT/grove"

  # Create a worktree directory for hooks to cd into
  export TEST_WORKTREE="$TEST_TEMP_DIR/Herd/myapp--feature-login"
  mkdir -p "$TEST_WORKTREE"

  # Create a log file hooks can write to for verification
  export HOOK_LOG="$TEST_TEMP_DIR/hook-execution.log"
  : > "$HOOK_LOG"
}

teardown() {
  teardown_test_environment
}

# Helper to run grove's run_hooks function in isolation via zsh
# Arguments: hook_name repo branch wt_path app_url db_name
run_hooks_isolated() {
  local hook_name="$1"
  local repo="${2:-myapp}"
  local branch="${3:-feature/login}"
  local wt_path="${4:-$TEST_WORKTREE}"
  local app_url="${5:-https://myapp--feature-login.test}"
  local db_name="${6:-myapp__feature_login}"

  HERD_ROOT="$HERD_ROOT" \
  GROVE_HOOKS_DIR="$GROVE_HOOKS_DIR" \
  NO_COLOR=1 \
  run zsh -c "
    # Minimal environment to source hook functions
    C_CYAN='' C_RESET='' C_GREEN='' C_YELLOW='' C_DIM=''
    NO_BACKUP=false DROP_DB=false
    info() { echo \"\$*\"; }
    ok() { echo \"\$*\"; }
    warn() { echo \"WARN: \$*\" >&2; }
    dim() { echo \"\$*\"; }
    slugify_branch() { REPLY=\"\${1//\\//-}\"; }
    source '$GROVE_ROOT/lib/06-hooks.sh'
    run_hooks '$hook_name' '$repo' '$branch' '$wt_path' '$app_url' '$db_name'
  "
}

# Helper to create an executable hook script
create_hook() {
  local hook_path="$1"
  local script_content="$2"

  mkdir -p "$(dirname "$hook_path")"
  cat > "$hook_path" << HOOKEOF
#!/bin/sh
$script_content
HOOKEOF
  chmod +x "$hook_path"
}

# ============================================================================
# Hook execution order (.d/ scripts run in numeric/alphabetic order)
# ============================================================================

@test "hooks: .d/ scripts execute in numeric order" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/02-second.sh" \
    "echo '02-second' >> '$HOOK_LOG'"

  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-first.sh" \
    "echo '01-first' >> '$HOOK_LOG'"

  create_hook "$GROVE_HOOKS_DIR/post-add.d/03-third.sh" \
    "echo '03-third' >> '$HOOK_LOG'"

  run_hooks_isolated "post-add"
  [ "$status" -eq 0 ]

  # Verify execution order via the log file
  [ -f "$HOOK_LOG" ]
  local line1 line2 line3
  line1="$(sed -n '1p' "$HOOK_LOG")"
  line2="$(sed -n '2p' "$HOOK_LOG")"
  line3="$(sed -n '3p' "$HOOK_LOG")"

  [ "$line1" = "01-first" ]
  [ "$line2" = "02-second" ]
  [ "$line3" = "03-third" ]
}

@test "hooks: single hook file executes before .d/ directory hooks" {
  create_hook "$GROVE_HOOKS_DIR/post-add" \
    "echo 'single-hook' >> '$HOOK_LOG'"

  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-first.sh" \
    "echo 'dir-hook' >> '$HOOK_LOG'"

  run_hooks_isolated "post-add"
  [ "$status" -eq 0 ]

  local line1 line2
  line1="$(sed -n '1p' "$HOOK_LOG")"
  line2="$(sed -n '2p' "$HOOK_LOG")"

  [ "$line1" = "single-hook" ]
  [ "$line2" = "dir-hook" ]
}

# ============================================================================
# Hook environment variables
# ============================================================================

@test "hooks: GROVE_REPO is set correctly" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-env.sh" \
    "echo \"GROVE_REPO=\$GROVE_REPO\" >> '$HOOK_LOG'"

  run_hooks_isolated "post-add" "myapp"
  [ "$status" -eq 0 ]
  grep -q "GROVE_REPO=myapp" "$HOOK_LOG"
}

@test "hooks: GROVE_BRANCH is set correctly" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-env.sh" \
    "echo \"GROVE_BRANCH=\$GROVE_BRANCH\" >> '$HOOK_LOG'"

  run_hooks_isolated "post-add" "myapp" "feature/login"
  [ "$status" -eq 0 ]
  grep -q "GROVE_BRANCH=feature/login" "$HOOK_LOG"
}

@test "hooks: GROVE_BRANCH_SLUG is set correctly" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-env.sh" \
    "echo \"GROVE_BRANCH_SLUG=\$GROVE_BRANCH_SLUG\" >> '$HOOK_LOG'"

  run_hooks_isolated "post-add" "myapp" "feature/login"
  [ "$status" -eq 0 ]
  grep -q "GROVE_BRANCH_SLUG=feature-login" "$HOOK_LOG"
}

@test "hooks: GROVE_PATH is set correctly" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-env.sh" \
    "echo \"GROVE_PATH=\$GROVE_PATH\" >> '$HOOK_LOG'"

  run_hooks_isolated "post-add" "myapp" "feature/login" "$TEST_WORKTREE"
  [ "$status" -eq 0 ]
  grep -q "GROVE_PATH=$TEST_WORKTREE" "$HOOK_LOG"
}

@test "hooks: GROVE_URL is set correctly" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-env.sh" \
    "echo \"GROVE_URL=\$GROVE_URL\" >> '$HOOK_LOG'"

  run_hooks_isolated "post-add" "myapp" "feature/login" "$TEST_WORKTREE" "https://myapp--feature-login.test"
  [ "$status" -eq 0 ]
  grep -q "GROVE_URL=https://myapp--feature-login.test" "$HOOK_LOG"
}

@test "hooks: GROVE_DB_NAME is set correctly" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-env.sh" \
    "echo \"GROVE_DB_NAME=\$GROVE_DB_NAME\" >> '$HOOK_LOG'"

  run_hooks_isolated "post-add" "myapp" "feature/login" "$TEST_WORKTREE" "" "myapp__feature_login"
  [ "$status" -eq 0 ]
  grep -q "GROVE_DB_NAME=myapp__feature_login" "$HOOK_LOG"
}

@test "hooks: GROVE_HOOK_NAME is set correctly" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-env.sh" \
    "echo \"GROVE_HOOK_NAME=\$GROVE_HOOK_NAME\" >> '$HOOK_LOG'"

  run_hooks_isolated "post-add"
  [ "$status" -eq 0 ]
  grep -q "GROVE_HOOK_NAME=post-add" "$HOOK_LOG"
}

@test "hooks: all environment variables set in single hook file" {
  create_hook "$GROVE_HOOKS_DIR/post-rm" \
    "echo \"REPO=\$GROVE_REPO BRANCH=\$GROVE_BRANCH SLUG=\$GROVE_BRANCH_SLUG HOOK=\$GROVE_HOOK_NAME\" >> '$HOOK_LOG'"

  run_hooks_isolated "post-rm" "backend" "bugfix/auth-issue"
  [ "$status" -eq 0 ]
  grep -q "REPO=backend" "$HOOK_LOG"
  grep -q "BRANCH=bugfix/auth-issue" "$HOOK_LOG"
  grep -q "SLUG=bugfix-auth-issue" "$HOOK_LOG"
  grep -q "HOOK=post-rm" "$HOOK_LOG"
}

# ============================================================================
# Repo-specific hooks in subdirectories
# ============================================================================

@test "hooks: repo-specific hooks in .d/<repo>/ are executed" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/myapp/01-setup.sh" \
    "echo 'repo-specific-hook' >> '$HOOK_LOG'"

  run_hooks_isolated "post-add" "myapp"
  [ "$status" -eq 0 ]
  grep -q "repo-specific-hook" "$HOOK_LOG"
}

@test "hooks: repo-specific hooks run after global hooks" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-global.sh" \
    "echo 'global' >> '$HOOK_LOG'"

  create_hook "$GROVE_HOOKS_DIR/post-add.d/myapp/01-specific.sh" \
    "echo 'repo-specific' >> '$HOOK_LOG'"

  run_hooks_isolated "post-add" "myapp"
  [ "$status" -eq 0 ]

  local line1 line2
  line1="$(sed -n '1p' "$HOOK_LOG")"
  line2="$(sed -n '2p' "$HOOK_LOG")"

  [ "$line1" = "global" ]
  [ "$line2" = "repo-specific" ]
}

@test "hooks: repo-specific hooks only run for matching repo" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/myapp/01-setup.sh" \
    "echo 'myapp-hook' >> '$HOOK_LOG'"

  create_hook "$GROVE_HOOKS_DIR/post-add.d/otherapp/01-setup.sh" \
    "echo 'otherapp-hook' >> '$HOOK_LOG'"

  run_hooks_isolated "post-add" "myapp"
  [ "$status" -eq 0 ]

  grep -q "myapp-hook" "$HOOK_LOG"
  ! grep -q "otherapp-hook" "$HOOK_LOG"
}

# ============================================================================
# Hook failure handling
# ============================================================================

@test "hooks: failed hook prints warning but run_hooks returns 0" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-fail.sh" \
    "exit 1"

  run_hooks_isolated "post-add"
  # run_hooks always returns 0 - failure is reported via warn()
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN:"* ]] || [[ "$output" == *"non-zero"* ]]
}

@test "hooks: subsequent hooks run after a failed hook" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-fail.sh" \
    "exit 1"

  create_hook "$GROVE_HOOKS_DIR/post-add.d/02-succeeds.sh" \
    "echo 'second-ran' >> '$HOOK_LOG'"

  run_hooks_isolated "post-add"
  [ "$status" -eq 0 ]
  grep -q "second-ran" "$HOOK_LOG"
}

@test "hooks: failed single hook does not prevent .d/ hooks from running" {
  create_hook "$GROVE_HOOKS_DIR/post-add" \
    "exit 1"

  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-after.sh" \
    "echo 'dir-hook-ran' >> '$HOOK_LOG'"

  run_hooks_isolated "post-add"
  [ "$status" -eq 0 ]
  grep -q "dir-hook-ran" "$HOOK_LOG"
}

# ============================================================================
# Hook permission checks
# ============================================================================

@test "hooks: non-executable hook file is skipped with message" {
  local hook_path="$GROVE_HOOKS_DIR/post-add"
  mkdir -p "$(dirname "$hook_path")"
  cat > "$hook_path" << 'EOF'
#!/bin/sh
echo "should not run" >> /dev/null
EOF
  chmod -x "$hook_path"

  run_hooks_isolated "post-add"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not executable"* ]]
}

@test "hooks: world-writable hook is skipped with security warning" {
  create_hook "$GROVE_HOOKS_DIR/post-add" \
    "echo 'should not run'"

  chmod o+w "$GROVE_HOOKS_DIR/post-add"

  run_hooks_isolated "post-add"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN:"* ]] || [[ "$output" == *"world-writable"* ]]
}

@test "hooks: world-writable .d/ script is skipped" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-safe.sh" \
    "echo 'safe-ran' >> '$HOOK_LOG'"

  create_hook "$GROVE_HOOKS_DIR/post-add.d/02-unsafe.sh" \
    "echo 'unsafe-ran' >> '$HOOK_LOG'"

  chmod o+w "$GROVE_HOOKS_DIR/post-add.d/02-unsafe.sh"

  run_hooks_isolated "post-add"
  [ "$status" -eq 0 ]

  grep -q "safe-ran" "$HOOK_LOG"
  ! grep -q "unsafe-ran" "$HOOK_LOG"
}

# ============================================================================
# Missing hooks directory
# ============================================================================

@test "hooks: missing hooks directory is handled gracefully" {
  export GROVE_HOOKS_DIR="$TEST_TEMP_DIR/nonexistent-hooks"

  run_hooks_isolated "post-add"
  [ "$status" -eq 0 ]
  # Should produce no error output
  [ -z "${output:-}" ] || [[ "$output" != *"ERROR"* ]]
}

@test "hooks: empty hooks directory produces no errors" {
  # GROVE_HOOKS_DIR exists but is empty (no hooks defined)
  run_hooks_isolated "post-add"
  [ "$status" -eq 0 ]
}

@test "hooks: empty .d/ directory produces no errors" {
  mkdir -p "$GROVE_HOOKS_DIR/post-add.d"
  # Directory exists but contains no scripts

  run_hooks_isolated "post-add"
  [ "$status" -eq 0 ]
}

@test "hooks: nonexistent hook name is handled gracefully" {
  run_hooks_isolated "post-nonexistent"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Hook types (verify different hook names work)
# ============================================================================

@test "hooks: pre-add hooks execute" {
  create_hook "$GROVE_HOOKS_DIR/pre-add.d/01-check.sh" \
    "echo 'pre-add-ran' >> '$HOOK_LOG'"

  run_hooks_isolated "pre-add"
  [ "$status" -eq 0 ]
  grep -q "pre-add-ran" "$HOOK_LOG"
}

@test "hooks: post-rm hooks execute" {
  create_hook "$GROVE_HOOKS_DIR/post-rm.d/01-cleanup.sh" \
    "echo 'post-rm-ran' >> '$HOOK_LOG'"

  run_hooks_isolated "post-rm"
  [ "$status" -eq 0 ]
  grep -q "post-rm-ran" "$HOOK_LOG"
}

@test "hooks: post-pull hooks execute" {
  create_hook "$GROVE_HOOKS_DIR/post-pull.d/01-update.sh" \
    "echo 'post-pull-ran' >> '$HOOK_LOG'"

  run_hooks_isolated "post-pull"
  [ "$status" -eq 0 ]
  grep -q "post-pull-ran" "$HOOK_LOG"
}

@test "hooks: post-sync hooks execute" {
  create_hook "$GROVE_HOOKS_DIR/post-sync.d/01-sync.sh" \
    "echo 'post-sync-ran' >> '$HOOK_LOG'"

  run_hooks_isolated "post-sync"
  [ "$status" -eq 0 ]
  grep -q "post-sync-ran" "$HOOK_LOG"
}

@test "hooks: post-switch hooks execute" {
  create_hook "$GROVE_HOOKS_DIR/post-switch.d/01-switch.sh" \
    "echo 'post-switch-ran' >> '$HOOK_LOG'"

  run_hooks_isolated "post-switch"
  [ "$status" -eq 0 ]
  grep -q "post-switch-ran" "$HOOK_LOG"
}

# ============================================================================
# _run_single_hook control flags and working directory
# ============================================================================

@test "hooks: hook runs from worktree directory" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/01-pwd.sh" \
    "pwd >> '$HOOK_LOG'"

  run_hooks_isolated "post-add" "myapp" "feature/login" "$TEST_WORKTREE"
  [ "$status" -eq 0 ]
  grep -q "$TEST_WORKTREE" "$HOOK_LOG"
}

@test "hooks: GROVE_NO_BACKUP is set when NO_BACKUP=true" {
  create_hook "$GROVE_HOOKS_DIR/pre-rm.d/01-check.sh" \
    "echo \"NO_BACKUP=\${GROVE_NO_BACKUP:-unset}\" >> '$HOOK_LOG'"

  HERD_ROOT="$HERD_ROOT" \
  GROVE_HOOKS_DIR="$GROVE_HOOKS_DIR" \
  NO_COLOR=1 \
  run zsh -c "
    C_CYAN='' C_RESET='' C_GREEN='' C_YELLOW='' C_DIM=''
    NO_BACKUP=true DROP_DB=false
    info() { echo \"\$*\"; }
    ok() { echo \"\$*\"; }
    warn() { echo \"WARN: \$*\" >&2; }
    dim() { echo \"\$*\"; }
    slugify_branch() { REPLY=\"\${1//\\//-}\"; }
    source '$GROVE_ROOT/lib/06-hooks.sh'
    run_hooks 'pre-rm' 'myapp' 'feature/login' '$TEST_WORKTREE' '' ''
  "
  [ "$status" -eq 0 ]
  grep -q "NO_BACKUP=true" "$HOOK_LOG"
}

@test "hooks: GROVE_DROP_DB is set when DROP_DB=true" {
  create_hook "$GROVE_HOOKS_DIR/pre-rm.d/01-check.sh" \
    "echo \"DROP_DB=\${GROVE_DROP_DB:-unset}\" >> '$HOOK_LOG'"

  HERD_ROOT="$HERD_ROOT" \
  GROVE_HOOKS_DIR="$GROVE_HOOKS_DIR" \
  NO_COLOR=1 \
  run zsh -c "
    C_CYAN='' C_RESET='' C_GREEN='' C_YELLOW='' C_DIM=''
    NO_BACKUP=false DROP_DB=true
    info() { echo \"\$*\"; }
    ok() { echo \"\$*\"; }
    warn() { echo \"WARN: \$*\" >&2; }
    dim() { echo \"\$*\"; }
    slugify_branch() { REPLY=\"\${1//\\//-}\"; }
    source '$GROVE_ROOT/lib/06-hooks.sh'
    run_hooks 'pre-rm' 'myapp' 'feature/login' '$TEST_WORKTREE' '' ''
  "
  [ "$status" -eq 0 ]
  grep -q "DROP_DB=true" "$HOOK_LOG"
}

@test "hooks: multiple repo-specific hooks execute in order" {
  create_hook "$GROVE_HOOKS_DIR/post-add.d/myapp/01-first.sh" \
    "echo 'repo-first' >> '$HOOK_LOG'"

  create_hook "$GROVE_HOOKS_DIR/post-add.d/myapp/02-second.sh" \
    "echo 'repo-second' >> '$HOOK_LOG'"

  run_hooks_isolated "post-add" "myapp"
  [ "$status" -eq 0 ]

  local line1 line2
  line1="$(sed -n '1p' "$HOOK_LOG")"
  line2="$(sed -n '2p' "$HOOK_LOG")"

  [ "$line1" = "repo-first" ]
  [ "$line2" = "repo-second" ]
}
