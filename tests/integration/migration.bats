#!/usr/bin/env bats
# migration.bats - migrate-from-wt.sh against a disposable HOME and Herd root.
# Git fixtures are throwaway repos under TEST_TEMP_DIR; no symlink is created.

load '../test-helper'

setup() {
  setup_test_environment
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME"
  unset GROVE_CONFIG
}

teardown() {
  chmod -R u+rwx "$TEST_TEMP_DIR" 2>/dev/null || true
  teardown_test_environment
}

_migrate() {
  run bash "$GROVE_ROOT/migrate-from-wt.sh" --force --no-symlink "$@"
}

# Bare repo <root>/app.git with one linked worktree <root>/app-wt (branch wt).
_bare_repo() {
  local root="$1"
  git init -q -b main "$TEST_TEMP_DIR/seed"
  git -C "$TEST_TEMP_DIR/seed" commit -q --allow-empty -m init
  git clone -q --bare "$TEST_TEMP_DIR/seed" "$root/app.git"
  git --git-dir="$root/app.git" worktree add -q -b wt "$root/app-wt" main
}

# --- HERD_ROOT resolution (finding 6) ---------------------------------------

@test "migration: HERD_ROOT from ~/.groverc is honoured when env is unset" {
  unset HERD_ROOT
  mkdir -p "$HOME/Sites/app.git"
  echo 'WT_SKIP_DB=true' > "$HOME/Sites/app.git/.wtconfig"
  printf 'HERD_ROOT="$HOME/Sites" # mine\n' > "$HOME/.groverc"
  _migrate
  [ "$status" -eq 0 ]
  [ -f "$HOME/Sites/app.git/.groveconfig" ]
  [ ! -f "$HOME/Sites/app.git/.wtconfig" ]
}

@test "migration: HERD_ROOT from ~/.wtrc is honoured (dry run)" {
  unset HERD_ROOT
  mkdir -p "$HOME/Sites/app.git"
  echo 'WT_SKIP_DB=true' > "$HOME/Sites/app.git/.wtconfig"
  echo 'HERD_ROOT=~/Sites' > "$HOME/.wtrc"
  _migrate --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/Sites/app.git/.wtconfig"* ]]
}

@test "migration: environment HERD_ROOT beats config" {
  mkdir -p "$HERD_ROOT/app.git" "$HOME/Sites/app.git"
  echo 'WT_SKIP_DB=true' > "$HERD_ROOT/app.git/.wtconfig"
  echo 'WT_SKIP_DB=true' > "$HOME/Sites/app.git/.wtconfig"
  echo "HERD_ROOT=$HOME/Sites" > "$HOME/.groverc"
  _migrate
  [ "$status" -eq 0 ]
  [ -f "$HERD_ROOT/app.git/.groveconfig" ]
  [ -f "$HOME/Sites/app.git/.wtconfig" ]
}

@test "migration: config HERD_ROOT is never executed" {
  unset HERD_ROOT
  printf 'HERD_ROOT=$(touch %s/pwned)\n' "$TEST_TEMP_DIR" > "$HOME/.groverc"
  _migrate --dry-run
  [ ! -e "$TEST_TEMP_DIR/pwned" ]
}

# --- .wtconfig backup failure (finding 5) -----------------------------------

@test "migration: Herd-root .wtconfig is untouched when its backup fails" {
  echo 'WT_SKIP_DB=true' > "$HERD_ROOT/.wtconfig"
  chmod 000 "$HERD_ROOT/.wtconfig"
  _migrate
  [ -e "$HERD_ROOT/.wtconfig" ]
  [ ! -e "$HERD_ROOT/.groveconfig" ]
}

# --- wt.base migration (findings 4 and 7) -----------------------------------

@test "migration: per-worktree wt.base moves to the grove-base sidecar" {
  _bare_repo "$HERD_ROOT"
  local admin="$HERD_ROOT/app.git/worktrees/app-wt"
  git config --file "$admin/config.worktree" wt.base origin/develop
  _migrate
  [ "$status" -eq 0 ]
  [ "$(cat "$admin/grove-base")" = "origin/develop" ]
  ! git config --file "$admin/config.worktree" --get wt.base
  ! git --git-dir="$HERD_ROOT/app.git" config --get grove.base
}

@test "migration: wt.base-only setup is detected, not 'nothing to migrate'" {
  _bare_repo "$HERD_ROOT"
  git config --file "$HERD_ROOT/app.git/worktrees/app-wt/config.worktree" wt.base origin/develop
  _migrate --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"Nothing to migrate"* ]]
  [[ "$output" == *"Would migrate"*"app-wt"* ]]
}

@test "migration: shared wt.base is preserved, not fanned out to worktrees" {
  _bare_repo "$HERD_ROOT"
  git --git-dir="$HERD_ROOT/app.git" config wt.base origin/develop
  _migrate
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$HERD_ROOT/app.git" config --get wt.base)" = "origin/develop" ]
  ! git --git-dir="$HERD_ROOT/app.git" config --get grove.base
  [ ! -e "$HERD_ROOT/app.git/worktrees/app-wt/grove-base" ]
}

@test "migration: failed sidecar write keeps legacy wt.base" {
  _bare_repo "$HERD_ROOT"
  local admin="$HERD_ROOT/app.git/worktrees/app-wt"
  git config --file "$admin/config.worktree" wt.base origin/develop
  mkdir "$admin/grove-base"   # a directory where the sidecar file must go
  _migrate
  [ "$(git config --file "$admin/config.worktree" --get wt.base)" = "origin/develop" ]
}

@test "migration: existing grove-base sidecar is never overwritten by wt.base" {
  _bare_repo "$HERD_ROOT"
  local admin="$HERD_ROOT/app.git/worktrees/app-wt"
  git config --file "$admin/config.worktree" wt.base origin/develop
  echo origin/release > "$admin/grove-base"
  _migrate
  [ "$status" -eq 0 ]
  [ "$(cat "$admin/grove-base")" = "origin/release" ]
  [ "$(git config --file "$admin/config.worktree" --get wt.base)" = "origin/develop" ]
  [[ "$output" == *"differ"* ]]
}

@test "migration: matching grove-base sidecar just drops the duplicate wt.base" {
  _bare_repo "$HERD_ROOT"
  local admin="$HERD_ROOT/app.git/worktrees/app-wt"
  git config --file "$admin/config.worktree" wt.base origin/develop
  echo origin/develop > "$admin/grove-base"
  _migrate
  [ "$status" -eq 0 ]
  [ "$(cat "$admin/grove-base")" = "origin/develop" ]
  ! git config --file "$admin/config.worktree" --get wt.base
}

# --- dry-run template discovery (finding 7) ---------------------------------

@test "migration: dry run reports unmigrated ~/.wt templates" {
  mkdir -p "$HOME/.wt/templates"
  echo 'WT_SKIP_DB=true' > "$HOME/.wt/templates/laravel.conf"
  _migrate --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would update WT_ variable name(s) in: $HOME/.wt/templates/laravel.conf"* ]]
}

@test "migration: dry run reports content rewrites in configs being renamed" {
  mkdir -p "$HERD_ROOT/app.git"
  for file in "$HOME/.wtrc" "$HERD_ROOT/.wtconfig" "$HERD_ROOT/app.git/.wtconfig"; do
    echo 'WT_SKIP_DB=true' > "$file"
  done
  _migrate --dry-run
  [ "$status" -eq 0 ]
  for file in "$HOME/.wtrc" "$HERD_ROOT/.wtconfig" "$HERD_ROOT/app.git/.wtconfig"; do
    [[ "$output" == *"Would update WT_ variable name(s) in: $file"* ]]
    [ "$(cat "$file")" = 'WT_SKIP_DB=true' ]
  done
  [ ! -e "$HOME/.groverc" ]
  [ ! -e "$HERD_ROOT/.groveconfig" ]
  [ ! -e "$HERD_ROOT/app.git/.groveconfig" ]
}
