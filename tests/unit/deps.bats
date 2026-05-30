#!/usr/bin/env bats
# deps.bats - Unit tests for shared-dependency helpers (lib/12-deps.sh)
#
# All tests invoke zsh subshells because 12-deps.sh uses zsh-specific features
# (glob qualifiers, print -r, the :A modifier, etc.). Output helpers (warn, ok,
# dim, die) and the shared 01-core helpers are stubbed in each subshell.

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PROJECT_ROOT

  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR

  export GROVE_SHARED_DEPS_DIR="$TEST_TMPDIR/shared"
  export HERD_ROOT="$TEST_TMPDIR/Herd"
  mkdir -p "$HERD_ROOT"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Common preamble: stub output helpers, then source the module.
PRELUDE='
  warn(){ :; }; info(){ :; }; ok(){ :; }; dim(){ :; }
  die(){ print -r -- "DIE:$1" >&2; return 1; }
  C_BOLD=""; C_RESET=""; C_GREEN=""; C_YELLOW=""; C_DIM=""
  source "$PROJECT_ROOT/lib/12-deps.sh" 2>/dev/null || true
'

# --- _calculate_lockfile_hash ---

@test "_calculate_lockfile_hash is stable for identical input" {
  mkdir -p "$TEST_TMPDIR/wt"
  printf 'lock-content-one\n' > "$TEST_TMPDIR/wt/composer.lock"

  run zsh -c "$PRELUDE"'
    h1="$(_calculate_lockfile_hash "$TEST_TMPDIR/wt")"
    h2="$(_calculate_lockfile_hash "$TEST_TMPDIR/wt")"
    [[ -n "$h1" ]]        || exit 1
    [[ "$h1" == "$h2" ]]  || exit 2
  '
  [ "$status" -eq 0 ]
}

@test "_calculate_lockfile_hash differs for changed input" {
  mkdir -p "$TEST_TMPDIR/wt"

  run zsh -c "$PRELUDE"'
    printf "lock-content-one\n" > "$TEST_TMPDIR/wt/composer.lock"
    before="$(_calculate_lockfile_hash "$TEST_TMPDIR/wt")"
    printf "lock-content-two-different\n" > "$TEST_TMPDIR/wt/composer.lock"
    after="$(_calculate_lockfile_hash "$TEST_TMPDIR/wt")"
    [[ "$before" != "$after" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "_calculate_lockfile_hash returns 12-char hash" {
  mkdir -p "$TEST_TMPDIR/wt"
  printf 'lock\n' > "$TEST_TMPDIR/wt/package-lock.json"

  run zsh -c "$PRELUDE"'
    h="$(_calculate_lockfile_hash "$TEST_TMPDIR/wt")"
    (( ${#h} == 12 )) || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "_calculate_lockfile_hash returns non-zero when no lockfiles present" {
  mkdir -p "$TEST_TMPDIR/wt"

  run zsh -c "$PRELUDE"'
    _calculate_lockfile_hash "$TEST_TMPDIR/wt"
  '
  [ "$status" -ne 0 ]
}

# --- _check_deps_shared ---

@test "_check_deps_shared reports shared for absolute symlink into dep-type subdir" {
  mkdir -p "$HERD_ROOT/wt" "$GROVE_SHARED_DEPS_DIR/node_modules/abc"
  ln -s "$GROVE_SHARED_DEPS_DIR/node_modules/abc" "$HERD_ROOT/wt/node_modules"

  run zsh -c "$PRELUDE"'
    [[ "$(_check_deps_shared "$HERD_ROOT/wt" node_modules)" == "shared" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "_check_deps_shared resolves relative symlink target" {
  mkdir -p "$HERD_ROOT/wt" "$GROVE_SHARED_DEPS_DIR/node_modules/abc"
  ( cd "$HERD_ROOT/wt" && ln -s "../../shared/node_modules/abc" node_modules )

  run zsh -c "$PRELUDE"'
    [[ "$(_check_deps_shared "$HERD_ROOT/wt" node_modules)" == "shared" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "_check_deps_shared honours the dep-type subdir (wrong type is not shared)" {
  mkdir -p "$HERD_ROOT/wt" "$GROVE_SHARED_DEPS_DIR/vendor/xyz"
  # A node_modules link pointing into the vendor subdir must not count as shared.
  ln -s "$GROVE_SHARED_DEPS_DIR/vendor/xyz" "$HERD_ROOT/wt/node_modules"

  run zsh -c "$PRELUDE"'
    [[ "$(_check_deps_shared "$HERD_ROOT/wt" node_modules)" == "local" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "_check_deps_shared reports local for a plain directory" {
  mkdir -p "$HERD_ROOT/wt/node_modules"

  run zsh -c "$PRELUDE"'
    [[ "$(_check_deps_shared "$HERD_ROOT/wt" node_modules)" == "local" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "_check_deps_shared reports missing when nothing is present" {
  mkdir -p "$HERD_ROOT/wt"

  run zsh -c "$PRELUDE"'
    [[ "$(_check_deps_shared "$HERD_ROOT/wt" node_modules)" == "missing" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

# --- clean subcommand wiring (#22) ---

@test "share-deps clean is recognised (does not die) with no shared dir" {
  run zsh -c "$PRELUDE"'
    out="$(cmd_share_deps clean 2>&1)"
    rc=$?
    [[ "$out" != *DIE* ]] || exit 1
    (( rc == 0 ))         || exit 2
  '
  [ "$status" -eq 0 ]
}

@test "cmd_share_deps_clean keeps in-use caches and removes orphans" {
  # bytes_to_human/get_dir_size_kb come from 01-core; stub them locally.
  run zsh -c '
    warn(){ :; }; info(){ :; }; ok(){ :; }; dim(){ :; }
    die(){ print -r -- "DIE:$1" >&2; return 1; }
    C_BOLD=""; C_RESET=""; C_GREEN=""; C_YELLOW=""; C_DIM=""
    get_dir_size_kb(){ print -r -- 1; }
    bytes_to_human(){ print -r -- "${1}K"; }
    source "$PROJECT_ROOT/lib/12-deps.sh" 2>/dev/null || true

    cd "$HERD_ROOT"
    git init -q --bare myapp.git
    git --git-dir=myapp.git symbolic-ref HEAD refs/heads/main
    mkdir -p myapp-worktrees
    git --git-dir=myapp.git worktree add -q myapp-worktrees/wt -b main 2>/dev/null

    mkdir -p "$GROVE_SHARED_DEPS_DIR/node_modules/inuse" "$GROVE_SHARED_DEPS_DIR/node_modules/orphan"
    ln -s "$GROVE_SHARED_DEPS_DIR/node_modules/inuse" "$HERD_ROOT/myapp-worktrees/wt/node_modules"

    cmd_share_deps_clean >/dev/null 2>&1

    [[ -d "$GROVE_SHARED_DEPS_DIR/node_modules/inuse" ]]   || exit 1
    [[ ! -d "$GROVE_SHARED_DEPS_DIR/node_modules/orphan" ]] || exit 2
  '
  [ "$status" -eq 0 ]
}
