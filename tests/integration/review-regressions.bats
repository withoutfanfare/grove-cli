#!/usr/bin/env bats
# Exercise lifecycle safety and JSON against real disposable Git worktrees.

load '../test-helper'

setup() {
  bats_require_minimum_version 1.5.0
  setup_test_environment
  mkdir -p "$TEST_TEMP_DIR/home"
  export GROVE_SKIP_PUSH=true
  export GROVE_INFO_FAST=true
  git init -q -b main "$TEST_TEMP_DIR/seed"
  git -C "$TEST_TEMP_DIR/seed" config user.email test@example.invalid
  git -C "$TEST_TEMP_DIR/seed" config user.name Test
  git -C "$TEST_TEMP_DIR/seed" commit -q --allow-empty -m init
  git clone -q --bare "$TEST_TEMP_DIR/seed" "$HERD_ROOT/demo.git"
}

teardown() {
  teardown_test_environment
}

grove_run() {
  run --separate-stderr env HOME="$TEST_TEMP_DIR/home" PATH="/usr/bin:/bin" \
    zsh "$GROVE_ROOT/grove" "$@"
}

add_worktree() {
  git --git-dir="$HERD_ROOT/demo.git" worktree add -q -b "$1" \
    "$HERD_ROOT/demo-worktrees/$2" main
}

assert_json_error() {
  [ "$status" -ne 0 ]
  OUTPUT="$output" python3 -c 'import json,os; assert json.loads(os.environ["OUTPUT"])["success"] is False'
}

record_hooks() {
  local event
  for event in pre-rm post-rm pre-move post-move post-pull post-sync; do
    cat > "$GROVE_HOOKS_DIR/$event" <<'HOOK'
#!/bin/sh
printf '%s|%s|%s\n' "$GROVE_HOOK_NAME" "$GROVE_DB_NAME" "$GROVE_URL" >> "$HERD_ROOT/hook-events"
HOOK
    chmod +x "$GROVE_HOOKS_DIR/$event"
  done
}

@test "rm: a slash/dash collision cannot remove a different branch" {
  add_worktree feature/collision feature-collision
  record_hooks
  grove_run rm demo feature-collision --json
  assert_json_error
  [ -d "$HERD_ROOT/demo-worktrees/feature-collision" ]
  [ ! -e "$HERD_ROOT/hook-events" ]
}

@test "rm: a folder name cannot bypass protection of main" {
  git --git-dir="$HERD_ROOT/demo.git" worktree add -q "$HERD_ROOT/demo-worktrees/demo" main
  grove_run rm demo demo --json
  assert_json_error
  [ -d "$HERD_ROOT/demo-worktrees/demo" ]
}

@test "rm: a case collision cannot remove a different branch" {
  add_worktree Feature/Case feature-case
  grove_run rm demo feature/case --force --json
  assert_json_error
  [ -d "$HERD_ROOT/demo-worktrees/feature-case" ]
}

@test "existing-worktree mutations reject an unregistered branch before running commands" {
  add_worktree feature/collision feature-collision
  local command
  for command in move exec fresh pull sync migrate; do
    case "$command" in
      move) grove_run move demo feature-collision moved --force --json ;;
      exec) grove_run exec demo feature-collision touch ran --json ;;
      *) grove_run "$command" demo feature-collision --json ;;
    esac
    assert_json_error
    [[ "$output" == *WORKTREE_NOT_FOUND* ]]
    [ -d "$HERD_ROOT/demo-worktrees/feature-collision" ]
    [ ! -e "$HERD_ROOT/demo-worktrees/feature-collision/ran" ]
  done
}

@test "rm: a detached worktree cannot be selected by its old branch" {
  add_worktree feature/collision feature-collision
  git -C "$HERD_ROOT/demo-worktrees/feature-collision" checkout -q --detach
  grove_run rm demo feature/collision --json
  assert_json_error
  [ -d "$HERD_ROOT/demo-worktrees/feature-collision" ]
}

@test "add --json: a new branch emits one JSON document" {
  grove_run add demo feature/new main --force --json
  [ "$status" -eq 0 ]
  OUTPUT="$output" python3 -c 'import json,os; assert json.loads(os.environ["OUTPUT"])["branch"] == "feature/new"'
  [ -d "$HERD_ROOT/demo-worktrees/feature-new" ]
}

@test "add --json: refused new-branch creation emits one JSON error" {
  grove_run add demo feature/new main --json
  assert_json_error
  [ ! -d "$HERD_ROOT/demo-worktrees/feature-new" ]
}

@test "rm --json: a dirty worktree is refused without prompting or running hooks" {
  add_worktree feature/dirty feature-dirty
  printf 'keep\n' > "$HERD_ROOT/demo-worktrees/feature-dirty/untracked"
  record_hooks
  grove_run rm demo feature/dirty --json
  assert_json_error
  [[ "$output" == *REMOVAL_BLOCKED* ]]
  # The gate's account of the loss travels in the message, newlines intact.
  [[ "$output" == *'would lose:'* ]]
  [[ "$output" == *'\n'* ]]
  [ -f "$HERD_ROOT/demo-worktrees/feature-dirty/untracked" ]
  [ ! -e "$HERD_ROOT/hook-events" ]
}

@test "aliased worktree: info and removal keep the database through a move" {
  printf 'GROVE_URL_SUBDOMAIN=api\n' > "$HERD_ROOT/demo.git/.groveconfig"
  record_hooks
  grove_run add demo feature/long main --dir short --force --json
  [ "$status" -eq 0 ]
  printf 'APP_URL=https://short.test\n' > "$HERD_ROOT/demo-worktrees/short/.env"
  grove_run info demo feature/long --json
  [ "$status" -eq 0 ]
  OUTPUT="$output" python3 -c 'import json,os; d=json.loads(os.environ["OUTPUT"]); assert d["database"]["name"] == "demo__short"; assert d["url"] == "https://api.short.test"'
  git -C "$HERD_ROOT/demo-worktrees/short" add -f .env
  git -C "$HERD_ROOT/demo-worktrees/short" -c user.name=Test -c user.email=test@example.invalid commit -q -m env
  git -C "$HERD_ROOT/demo-worktrees/short" branch --set-upstream-to=origin/main >/dev/null
  grove_run pull demo feature/long --json
  [ "$status" -eq 0 ]
  OUTPUT="$output" python3 -c 'import json,os; assert json.loads(os.environ["OUTPUT"])["success"] is True'
  grove_run sync demo feature/long main --json
  [ "$status" -eq 0 ]
  OUTPUT="$output" python3 -c 'import json,os; assert json.loads(os.environ["OUTPUT"])["success"] is True'
  grep -qx 'post-pull|demo__short|https://api.short.test' "$HERD_ROOT/hook-events"
  grep -qx 'post-sync|demo__short|https://api.short.test' "$HERD_ROOT/hook-events"
  grove_run move demo feature/long renamed --force
  [ "$status" -eq 0 ]
  grove_run info demo feature/long --json
  [ "$status" -eq 0 ]
  OUTPUT="$output" python3 -c 'import json,os; d=json.loads(os.environ["OUTPUT"]); assert d["database"]["name"] == "demo__short"; assert d["url"] == "https://api.renamed.test"'
  # The move rewrote APP_URL in .env. The removal gate blocks on any
  # uncommitted change and --force does not bypass it, so save that first.
  git -C "$HERD_ROOT/demo-worktrees/renamed" -c user.name=Test -c user.email=test@example.invalid commit -q -am env-moved
  grove_run rm demo feature/long --force --drop-db --json
  [ "$status" -eq 0 ]
  [ ! -d "$HERD_ROOT/demo-worktrees/renamed" ]
  grep -qx 'pre-move|demo__short|https://api.short.test' "$HERD_ROOT/hook-events"
  grep -qx 'post-move|demo__short|https://api.renamed.test' "$HERD_ROOT/hook-events"
  grep -qx 'pre-rm|demo__short|https://api.renamed.test' "$HERD_ROOT/hook-events"
  grep -qx 'post-rm|demo__short|https://api.renamed.test' "$HERD_ROOT/hook-events"
}

@test "legacy alias: an explicit database in env survives a move" {
  add_worktree feature/legacy old-alias
  printf 'DB_DATABASE="demo__original" # selected earlier\n' > "$HERD_ROOT/demo-worktrees/old-alias/.env"
  record_hooks
  grove_run move demo feature/legacy new-alias --force
  [ "$status" -eq 0 ]
  # Once migrated, the per-worktree identity survives even without .env.
  rm "$HERD_ROOT/demo-worktrees/new-alias/.env"
  grove_run rm demo feature/legacy --force --json
  [ "$status" -eq 0 ]
  grep -qx 'pre-rm|demo__original|https://new-alias.test' "$HERD_ROOT/hook-events"
}

@test "legacy alias: ambiguous database identity blocks removal before hooks" {
  add_worktree feature/legacy old-alias
  record_hooks
  grove_run rm demo feature/legacy --force --drop-db --json
  assert_json_error
  [[ "$output" == *DATABASE_UNKNOWN* ]]
  [ -d "$HERD_ROOT/demo-worktrees/old-alias" ]
  [ ! -e "$HERD_ROOT/hook-events" ]
}

@test "rm: a broken database record cannot fall back to a guessed name" {
  add_worktree feature/broken feature-broken
  local sidecar
  sidecar="$(git -C "$HERD_ROOT/demo-worktrees/feature-broken" rev-parse --git-path grove-database)"
  ln -s "$TEST_TEMP_DIR/missing-record" "$sidecar"
  record_hooks
  grove_run rm demo feature/broken --force --drop-db --json
  assert_json_error
  [[ "$output" == *DATABASE_UNKNOWN* ]]
  [ -d "$HERD_ROOT/demo-worktrees/feature-broken" ]
  [ ! -e "$HERD_ROOT/hook-events" ]
}
