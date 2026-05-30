#!/usr/bin/env bats
# lifecycle.bats - Integration tests for lib/commands/lifecycle.sh against the
# REAL zsh implementations (sourced into a zsh process with the cross-module
# helpers stubbed), not bash reimplementations.
#
# Coverage:
#   1. Transactions (#27): a failing step runs the registered undo functions in
#      reverse order — the mechanism cmd_add/cmd_clone/cmd_move rely on.
#   2. cmd_rm JSON (#32): "branch_deleted" reflects the REAL deletion outcome
#      (not the --delete-branch request flag), and the DB field is reported as
#      "db_drop_requested" (intent, since the drop is hook-delegated).

load '../test-helper'

setup() {
  setup_test_environment

  # A sourceable zsh file: stub the cross-module helpers that lifecycle.sh and
  # 11-resilience.sh expect, then append the real module bodies so we exercise
  # the actual code paths.
  LIFE_FNS="$TEST_TEMP_DIR/life-fns.zsh"
  export LIFE_FNS
  cat > "$LIFE_FNS" <<'STUB'
# --- output helpers (quiet) ---
info() { :; }
ok()   { :; }
warn() { print -r -- "WARN: $*" >&2; }
dim()  { :; }
notify() { :; }
# --- colours (unset) ---
C_RESET='' C_BOLD='' C_DIM='' C_CYAN='' C_MAGENTA='' C_GREEN='' C_YELLOW='' C_RED='' C_BLUE=''
# --- flags / globals ---
JSON_OUTPUT=false
FORCE=false
DELETE_BRANCH=false
DROP_DB=false
INTERACTIVE=false
GROVE_URL_SUBDOMAIN=''
# --- error_exit: print JSON-ish error and exit (mirrors real die_json shape) ---
error_exit() { print -r -- "ERROR:$1:$2" >&2; exit "${3:-1}"; }
die() { print -r -- "ERROR:$*" >&2; exit 1; }
# --- spinner stub (referenced by resilience TRAPEXIT) ---
spinner_stop() { :; }
# --- JSON helpers: real-ish, pure ---
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  REPLY="$s"
}
format_json() { print -r -- "$1"; }
# --- to_json_bool: faithful copy of lib/01-core.sh ---
to_json_bool() {
  case "${1:l}" in
    true|1|yes|on) print -r -- "true" ;;
    *)             print -r -- "false" ;;
  esac
}
# --- cross-module path/validation helpers used by cmd_rm ---
validate_name() { return 0; }
ensure_bare_repo() { return 0; }
restart_herd_service() { return 0; }
run_hooks() { return 0; }
cleanup_herd_site() { return 0; }
count_lines() { print -r -- 1; }
STUB
  cat "$GROVE_ROOT/lib/11-resilience.sh" >> "$LIFE_FNS"
  cat "$GROVE_ROOT/lib/commands/lifecycle.sh" >> "$LIFE_FNS"
}

teardown() {
  teardown_test_environment
}

run_zsh() {
  run zsh -c "source '$LIFE_FNS'; $1"
}

# Build a real bare repo at <git_dir> with one worktree on <branch>.
# Echoes nothing; sets up files under TEST_TEMP_DIR.
make_bare_with_worktree() {
  local git_dir="$1" wt_path="$2" branch="$3"
  local seed="$TEST_TEMP_DIR/seed"
  git init -q -b main "$seed"
  git -C "$seed" config user.email t@t.t
  git -C "$seed" config user.name 'Test'
  git -C "$seed" commit -q --allow-empty -m init
  git clone -q --bare "$seed" "$git_dir"
  git --git-dir="$git_dir" worktree add -q -b "$branch" "$wt_path" HEAD
}

# ============================================================================
# #27 — Transactions: registered undo runs (in reverse) on rollback
# ============================================================================

@test "transaction: a failing step rolls back registered undo functions" {
  # marker_dir exists; the undo function removes it. After rollback it must be gone.
  run_zsh '
    marker="'"$TEST_TEMP_DIR"'/marker"
    mkdir -p "$marker"
    undo_remove() { /bin/rm -rf "$1"; }
    transaction_start
    transaction_register undo_remove "$marker"
    # Simulate a mid-operation failure: roll back without committing.
    transaction_rollback
    [[ -d "$marker" ]] && print -r -- "STILL_THERE" || print -r -- "ROLLED_BACK"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"ROLLED_BACK"* ]]
}

@test "transaction: commit prevents rollback from running undo" {
  run_zsh '
    marker="'"$TEST_TEMP_DIR"'/marker2"
    mkdir -p "$marker"
    undo_remove() { /bin/rm -rf "$1"; }
    transaction_start
    transaction_register undo_remove "$marker"
    transaction_commit
    # A rollback after commit must be a no-op.
    transaction_rollback
    [[ -d "$marker" ]] && print -r -- "KEPT" || print -r -- "WRONGLY_REMOVED"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"KEPT"* ]]
}

@test "transaction: undo steps run in REVERSE registration order" {
  run_zsh '
    log="'"$TEST_TEMP_DIR"'/order.log"
    : > "$log"
    step_a() { print -r -- "a" >> "'"$TEST_TEMP_DIR"'/order.log"; }
    step_b() { print -r -- "b" >> "'"$TEST_TEMP_DIR"'/order.log"; }
    transaction_start
    transaction_register step_a
    transaction_register step_b
    transaction_rollback
    # Emit a uniquely-marked line so the assertion is immune to warn() noise
    # that bats merges from stderr into $output.
    print -r -- "ORDER=$(tr -d "\n" < "$log")"
  '
  [ "$status" -eq 0 ]
  # b registered last -> runs first.
  [[ "$output" == *"ORDER=ba"* ]]
}

@test "transaction: _undo_worktree_add removes a created worktree" {
  local git_dir="$TEST_TEMP_DIR/repo.git"
  local wt_path="$TEST_TEMP_DIR/wt-undo"
  make_bare_with_worktree "$git_dir" "$wt_path" "feature/x"
  [ -d "$wt_path" ]

  run_zsh "_undo_worktree_add '$git_dir' '$wt_path'"
  [ "$status" -eq 0 ]
  [ ! -d "$wt_path" ]
}

# ============================================================================
# #32 — cmd_rm JSON: branch_deleted reflects the REAL outcome
# ============================================================================

@test "cmd_rm --json: branch_deleted is true when the branch is actually deleted" {
  local git_dir="$TEST_TEMP_DIR/app.git"
  local wt_path="$TEST_TEMP_DIR/Herd/app-worktrees/feature-login"
  make_bare_with_worktree "$git_dir" "$wt_path" "feature/login"

  run_zsh "
    git_dir_for() { print -r -- '$git_dir'; }
    resolve_worktree_path() { print -r -- '$wt_path'; }
    url_for() { print -r -- 'https://feature-login.test'; }
    db_name_for() { print -r -- 'app__feature_login'; }
    is_protected_branch() { return 1; }
    JSON_OUTPUT=true FORCE=true DELETE_BRANCH=true DROP_DB=false
    cmd_rm 'app' 'feature/login'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *'"branch_deleted": true'* ]]
  # Field renamed: db_drop_requested (intent), and no stale db_dropped key.
  [[ "$output" == *'"db_drop_requested": false'* ]]
  [[ "$output" != *'db_dropped'* ]]
}

@test "cmd_rm --json: branch_deleted is false when --delete-branch not requested" {
  local git_dir="$TEST_TEMP_DIR/app2.git"
  local wt_path="$TEST_TEMP_DIR/Herd/app2-worktrees/feature-x"
  make_bare_with_worktree "$git_dir" "$wt_path" "feature/x"

  run_zsh "
    git_dir_for() { print -r -- '$git_dir'; }
    resolve_worktree_path() { print -r -- '$wt_path'; }
    url_for() { print -r -- 'https://feature-x.test'; }
    db_name_for() { print -r -- 'app2__feature_x'; }
    is_protected_branch() { return 1; }
    JSON_OUTPUT=true FORCE=true DELETE_BRANCH=false DROP_DB=true
    cmd_rm 'app2' 'feature/x'
  "
  [ "$status" -eq 0 ]
  # Request flag was false -> no deletion attempted -> false.
  [[ "$output" == *'"branch_deleted": false'* ]]
  # DROP_DB request intent surfaces under the new key.
  [[ "$output" == *'"db_drop_requested": true'* ]]
}

@test "cmd_rm --json: branch_deleted is false when the branch does not exist" {
  # The worktree is on branch 'feature/real', but we tell cmd_rm the branch is
  # 'feature/missing'. After the worktree is removed, 'git branch -D
  # feature/missing' fails (no such branch). The old code emitted the request
  # flag (true); the fix emits the real outcome (false).
  local git_dir="$TEST_TEMP_DIR/app3.git"
  local wt_path="$TEST_TEMP_DIR/Herd/app3-worktrees/feature-real"
  make_bare_with_worktree "$git_dir" "$wt_path" "feature/real"

  run_zsh "
    git_dir_for() { print -r -- '$git_dir'; }
    resolve_worktree_path() { print -r -- '$wt_path'; }
    url_for() { print -r -- 'https://feature-real.test'; }
    db_name_for() { print -r -- 'app3__feature_real'; }
    is_protected_branch() { return 1; }
    JSON_OUTPUT=true FORCE=true DELETE_BRANCH=true DROP_DB=false
    cmd_rm 'app3' 'feature/missing'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *'"branch_deleted": false'* ]]
}
