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

@test "rm and move refuse a worktree selected by a current-site link" {
  add_worktree feature/live feature-live
  ln -s demo-worktrees/feature-live "$HERD_ROOT/demo-current"
  record_hooks

  grove_run rm demo feature/live --json
  assert_json_error
  [[ "$output" == *WORKTREE_IN_USE* ]]
  [ -d "$HERD_ROOT/demo-worktrees/feature-live" ]

  grove_run move demo feature/live renamed --json
  assert_json_error
  [[ "$output" == *WORKTREE_IN_USE* ]]
  [ -d "$HERD_ROOT/demo-worktrees/feature-live" ]
  [ ! -e "$HERD_ROOT/hook-events" ]
}

@test "rm --drop-db refuses a legacy env-only database before running hooks" {
  add_worktree feature/shared feature-shared
  printf 'DB_DATABASE=shared\n' > "$HERD_ROOT/demo-worktrees/feature-shared/.env"
  printf '.env\n' >> "$(git -C "$HERD_ROOT/demo-worktrees/feature-shared" rev-parse --git-path info/exclude)"
  record_hooks

  grove_run rm demo feature/shared --force --drop-db --json
  assert_json_error
  [[ "$output" == *DATABASE_UNSAFE* ]]
  [ -d "$HERD_ROOT/demo-worktrees/feature-shared" ]
  [ ! -e "$HERD_ROOT/hook-events" ]
}

@test "fresh rebuilds assets without invoking php even with inherited or cached database settings" {
  add_worktree feature/shared feature-shared
  local wt="$HERD_ROOT/demo-worktrees/feature-shared"
  printf 'DB_DATABASE=primary\n' > "$wt/.env"
  touch "$wt/artisan"
  mkdir -p "$wt/bootstrap/cache"
  printf '<?php return ["database" => ["default" => "production"]];\n' > "$wt/bootstrap/cache/config.php"
  printf '{}\n' > "$wt/package.json"
  printf 'demo__feature_shared\n' > "$(git -C "$wt" rev-parse --git-path grove-database)"
  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/php" <<'PHP'
#!/bin/sh
touch "$HERD_ROOT/php-was-called"
PHP
  chmod +x "$TEST_TEMP_DIR/bin/php"
  cat > "$TEST_TEMP_DIR/bin/npm" <<'NPM'
#!/bin/sh
printf '%s\n' "$*" >> "$HERD_ROOT/npm-calls"
NPM
  chmod +x "$TEST_TEMP_DIR/bin/npm"

  run --separate-stderr env HOME="$TEST_TEMP_DIR/home" PATH="$TEST_TEMP_DIR/bin:/usr/bin:/bin" \
    DB_URL=mysql://example.invalid/shared DB_DATABASE=shared \
    zsh "$GROVE_ROOT/grove" fresh demo feature/shared --force

  [ "$status" -eq 0 ]
  [[ "$stderr" == *"Fresh complete"* ]]
  [ ! -e "$HERD_ROOT/php-was-called" ]
  [ "$(cat "$HERD_ROOT/npm-calls")" = $'ci\nrun build' ]
  grep -qx DB_DATABASE=primary "$wt/.env"
}

@test "fresh propagates an asset install failure without claiming success" {
  add_worktree feature/assets feature-assets
  printf '{}\n' > "$HERD_ROOT/demo-worktrees/feature-assets/package.json"
  mkdir -p "$TEST_TEMP_DIR/bin"
  printf '#!/bin/sh\ntouch "%s/npm-ran"\nexit 1\n' "$TEST_TEMP_DIR" > "$TEST_TEMP_DIR/bin/npm"
  chmod +x "$TEST_TEMP_DIR/bin/npm"
  run --separate-stderr env HOME="$TEST_TEMP_DIR/home" PATH="$TEST_TEMP_DIR/bin:/usr/bin:/bin" \
    zsh "$GROVE_ROOT/grove" fresh demo feature/assets
  [ "$status" -ne 0 ]
  [ -e "$TEST_TEMP_DIR/npm-ran" ]
  [[ "$output$stderr" != *"Fresh complete"* ]]
}

@test "rm --drop-db refuses a recorded database selected by a sibling worktree" {
  add_worktree feature/owner feature-owner
  add_worktree feature/borrower feature-borrower
  local wt="$HERD_ROOT/demo-worktrees/feature-owner"
  printf 'shared\n' > "$(git -C "$wt" rev-parse --git-path grove-database)"
  printf 'DB_DATABASE=shared\n' > "$HERD_ROOT/demo-worktrees/feature-borrower/.env"
  record_hooks

  grove_run rm demo feature/owner --force --drop-db --json

  assert_json_error
  [[ "$output" == *DATABASE_UNSAFE* ]]
  [ -d "$wt" ]
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

@test "rm --path: a detached worktree is removed by its folder, keeping its branch" {
  add_worktree feature/parked feature-parked
  git -C "$HERD_ROOT/demo-worktrees/feature-parked" checkout -q --detach
  grove_run rm -f --delete-branch --path="$HERD_ROOT/demo-worktrees/feature-parked" demo --json
  [ "$status" -eq 0 ]
  [ ! -d "$HERD_ROOT/demo-worktrees/feature-parked" ]
  git --git-dir="$HERD_ROOT/demo.git" rev-parse -q --verify refs/heads/feature/parked
}

@test "rm --path: a worktree on a branch must be removed by its branch" {
  add_worktree feature/attached feature-attached
  grove_run rm -f --path="$HERD_ROOT/demo-worktrees/feature-attached" demo --json
  assert_json_error
  [[ "$output" == *WORKTREE_NOT_FOUND* ]]
  [ -d "$HERD_ROOT/demo-worktrees/feature-attached" ]
}

@test "rm --path: a folder that is not one of the repo's worktrees is refused" {
  mkdir -p "$HERD_ROOT/demo-worktrees/not-a-worktree"
  grove_run rm -f --path="$HERD_ROOT/demo-worktrees/not-a-worktree" demo --json
  assert_json_error
  [[ "$output" == *WORKTREE_NOT_FOUND* ]]
  [ -d "$HERD_ROOT/demo-worktrees/not-a-worktree" ]
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

@test "legacy alias: ambiguous database identity blocks unforced removal before hooks" {
  add_worktree feature/legacy old-alias
  record_hooks
  grove_run rm demo feature/legacy --drop-db --json
  assert_json_error
  [[ "$output" == *DATABASE_UNKNOWN* ]]
  [ -d "$HERD_ROOT/demo-worktrees/old-alias" ]
  [ ! -e "$HERD_ROOT/hook-events" ]
}

@test "removal-check: an unknown database only blocks when a drop is requested" {
  add_worktree feature/legacy old-alias
  grove_run removal-check demo feature/legacy --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"clear"'* ]]
  grove_run removal-check demo feature/legacy --drop-db --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"unknown"'* ]]
}

@test "removal-check: an unknown database never downgrades a blocked verdict" {
  add_worktree feature/legacy old-alias
  ln -s "$HERD_ROOT/demo-worktrees/old-alias" "$HERD_ROOT/demo-current"
  grove_run removal-check demo feature/legacy --drop-db --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"blocked"'* ]]
}

@test "removal-check honours -f on a protected branch, as rm does" {
  add_worktree staging staging
  printf 'demo_staging\n' > "$(git -C "$HERD_ROOT/demo-worktrees/staging" rev-parse --git-path grove-database)"
  grove_run removal-check demo staging --json
  [[ "$output" == *'"verdict":"blocked"'* ]]
  grove_run removal-check -f demo staging --json
  [ "$status" -eq 0 ]
  [[ "$output" != *'Protected branch requires'* ]]
  [[ "$output" == *'"verdict":"clear"'* ]]
}

@test "rm --drop-db refuses while a sibling's folder is missing, and names it" {
  add_worktree feature/owner feature-owner
  add_worktree feature/gone feature-gone
  printf 'owned\n' > "$(git -C "$HERD_ROOT/demo-worktrees/feature-owner" rev-parse --git-path grove-database)"
  rm -rf "$HERD_ROOT/demo-worktrees/feature-gone"
  grove_run rm demo feature/owner --force --drop-db --json
  assert_json_error
  [[ "$output" == *DATABASE_UNSAFE* && "$output" == *feature-gone* ]]
  [ -d "$HERD_ROOT/demo-worktrees/feature-owner" ]
  git --git-dir="$HERD_ROOT/demo.git" worktree prune
  grove_run rm demo feature/owner --force --drop-db --json
  [ "$status" -eq 0 ]
  [ ! -d "$HERD_ROOT/demo-worktrees/feature-owner" ]
}

@test "rm --drop-db refuses when a sibling's recorded database cannot be read" {
  [ "$(id -u)" -ne 0 ] || skip "root reads a mode-000 file"
  add_worktree feature/owner feature-owner
  add_worktree feature/locked feature-locked
  printf 'owned\n' > "$(git -C "$HERD_ROOT/demo-worktrees/feature-owner" rev-parse --git-path grove-database)"
  local sidecar; sidecar="$(git -C "$HERD_ROOT/demo-worktrees/feature-locked" rev-parse --git-path grove-database)"
  # A different name, so only the unreadable read itself can block the drop.
  printf 'other\n' > "$sidecar"
  chmod 000 "$sidecar"
  grove_run rm demo feature/owner --force --drop-db --json
  assert_json_error
  [[ "$output" == *DATABASE_UNSAFE* && "$output" == *"cannot read"*feature-locked* ]]
  [ -d "$HERD_ROOT/demo-worktrees/feature-owner" ]
}

@test "python helpers never import modules from the current folder" {
  mkdir "$TEST_TEMP_DIR/hostile"
  printf 'open("%s/imported", "w")\n' "$TEST_TEMP_DIR" > "$TEST_TEMP_DIR/hostile/json.py"
  add_worktree feature/hostile hostile-wt
  cd "$TEST_TEMP_DIR/hostile"
  grove_run prune-plan demo
  [[ "$output" == *'"success"'* ]]
  [ ! -e "$TEST_TEMP_DIR/imported" ]
  GROVE_REMOVAL_CHECK_BIN="" grove_run removal-check demo feature/hostile --json
  [[ "$output" == *'"verdict"'* ]]
  [ ! -e "$TEST_TEMP_DIR/imported" ]
}

@test "health: an unknown base is neither averaged as zero nor marked critical" {
  add_worktree feature/known known
  add_worktree feature/unknown unknown
  printf 'main\n' > "$(git -C "$HERD_ROOT/demo-worktrees/known" rev-parse --git-path grove-base)"
  grove_run health demo --json
  [ "$status" -eq 0 ]
  OUTPUT="$output" python3 -c '
import json,os
data = json.loads(os.environ["OUTPUT"])
data = data.get("data", data)
assert data["worktree_count"] == 2, data
assert data["overall_grade"] == "?", data
assert data["overall_score"] >= 60, data
assert not [i for i in data["issues"] if i["severity"] == "critical"], data'
}

# A forced removal must not depend on the database: it removes the worktree but
# never backs up or drops a database it cannot identify.
record_db_flags() {
  cat > "$GROVE_HOOKS_DIR/post-rm" <<'HOOK'
#!/bin/sh
printf 'db=%s|drop=%s|nobackup=%s\n' "$GROVE_DB_NAME" "${GROVE_DROP_DB:-}" "${GROVE_NO_BACKUP:-}" >> "$HERD_ROOT/db-flags"
HOOK
  chmod +x "$GROVE_HOOKS_DIR/post-rm"
}

@test "legacy alias: forced removal with an unknown database leaves databases alone" {
  add_worktree feature/legacy old-alias
  record_db_flags
  grove_run rm demo feature/legacy --force --drop-db --json
  [ "$status" -eq 0 ]
  [ ! -d "$HERD_ROOT/demo-worktrees/old-alias" ]
  grep -qx 'db=|drop=|nobackup=true' "$HERD_ROOT/db-flags"
}

@test "rm: a broken database record cannot fall back to a guessed name" {
  add_worktree feature/broken feature-broken
  local sidecar
  sidecar="$(git -C "$HERD_ROOT/demo-worktrees/feature-broken" rev-parse --git-path grove-database)"
  ln -s "$TEST_TEMP_DIR/missing-record" "$sidecar"
  record_hooks
  grove_run rm demo feature/broken --drop-db --json
  assert_json_error
  [[ "$output" == *DATABASE_UNKNOWN* ]]
  [ -d "$HERD_ROOT/demo-worktrees/feature-broken" ]
  [ ! -e "$HERD_ROOT/hook-events" ]
}

@test "rm: forced removal with a broken database record drops nothing" {
  add_worktree feature/broken feature-broken
  local sidecar
  sidecar="$(git -C "$HERD_ROOT/demo-worktrees/feature-broken" rev-parse --git-path grove-database)"
  ln -s "$TEST_TEMP_DIR/missing-record" "$sidecar"
  record_db_flags
  grove_run rm demo feature/broken --force --drop-db --json
  [ "$status" -eq 0 ]
  [ ! -d "$HERD_ROOT/demo-worktrees/feature-broken" ]
  grep -qx 'db=|drop=|nobackup=true' "$HERD_ROOT/db-flags"
}

# --allow-protected lifts ONLY the protected-branch check. It is what a typed
# branch-name confirmation maps to, so it must never carry -f's other powers.
add_protected_worktree() {
  add_worktree staging "$1"
  printf 'demo__staging\n' > "$(git -C "$HERD_ROOT/demo-worktrees/$1" rev-parse --git-path grove-database)"
}

@test "rm --allow-protected removes a protected branch with a recorded database and a clear gate" {
  add_protected_worktree staging
  record_hooks
  grove_run rm demo staging --json
  assert_json_error
  [[ "$output" == *PROTECTED_BRANCH* ]]

  grove_run rm demo staging --allow-protected --json
  [ "$status" -eq 0 ]
  [ ! -d "$HERD_ROOT/demo-worktrees/staging" ]
  grep -q '^pre-rm|demo__staging|' "$HERD_ROOT/hook-events"
}

@test "rm --allow-protected still refuses a worktree selected by a current-site link" {
  add_protected_worktree staging
  ln -s demo-worktrees/staging "$HERD_ROOT/demo-current"
  record_hooks
  grove_run rm demo staging --allow-protected --json
  assert_json_error
  [[ "$output" == *WORKTREE_IN_USE* ]]
  [ -d "$HERD_ROOT/demo-worktrees/staging" ]
  [ ! -e "$HERD_ROOT/hook-events" ]
}

@test "rm: an unknown database does not block a removal that keeps the database" {
  add_worktree feature/legacy old-alias
  record_db_flags
  grove_run rm demo feature/legacy --json
  [ "$status" -eq 0 ]
  [ ! -d "$HERD_ROOT/demo-worktrees/old-alias" ]
}

@test "rm --allow-protected still refuses to drop an unknown database" {
  add_worktree staging old-staging
  record_hooks
  grove_run rm demo staging --allow-protected --drop-db --json
  assert_json_error
  [[ "$output" == *DATABASE_UNKNOWN* ]]
  [ -d "$HERD_ROOT/demo-worktrees/old-staging" ]
  [ ! -e "$HERD_ROOT/hook-events" ]
}

@test "rm --allow-protected still stops at the removal gate" {
  add_protected_worktree staging
  touch "$HERD_ROOT/demo-worktrees/staging/unsaved"
  record_hooks
  grove_run rm demo staging --allow-protected --json
  assert_json_error
  [[ "$output" == *REMOVAL_BLOCKED* ]]
  [ -f "$HERD_ROOT/demo-worktrees/staging/unsaved" ]
  [ ! -e "$HERD_ROOT/hook-events" ]
}

@test "rm --allow-protected does not force git past a locked worktree" {
  add_protected_worktree staging
  git --git-dir="$HERD_ROOT/demo.git" worktree lock "$HERD_ROOT/demo-worktrees/staging"
  grove_run rm demo staging --allow-protected --json
  assert_json_error
  [[ "$output" == *GIT_ERROR* ]]
  [ -d "$HERD_ROOT/demo-worktrees/staging" ]
}

# Pull and sync never touch a database, so an agent worktree with no database
# of its own (or one sharing a local database through .env) must still update.
# Their hooks might migrate, so they run only against a recorded database.
add_tracking_worktree() {
  git --git-dir="$HERD_ROOT/demo.git" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git --git-dir="$HERD_ROOT/demo.git" fetch -q origin
  add_worktree "$1" "$2"
  git -C "$HERD_ROOT/demo-worktrees/$2" branch -q --set-upstream-to=origin/main
  git -C "$TEST_TEMP_DIR/seed" commit -q --allow-empty -m upstream
}

database_sidecar() {
  git -C "$HERD_ROOT/demo-worktrees/$1" rev-parse --git-path grove-database
}

@test "pull and sync: a worktree with no database updates and skips its hooks" {
  add_tracking_worktree t3/review-ci-test-tiers review-ci-test-tiers
  # No hooks installed: nothing is skipped, so nothing to warn about.
  grove_run pull demo t3/review-ci-test-tiers --json
  [ "$status" -eq 0 ]
  [[ "$stderr" != *Skipped* ]]
  OUTPUT="$output" python3 -c 'import json,os; d=json.loads(os.environ["OUTPUT"]); assert d["success"] is True and d["commits_pulled"] == 1'

  record_hooks
  git -C "$TEST_TEMP_DIR/seed" commit -q --allow-empty -m again
  grove_run pull demo t3/review-ci-test-tiers --json
  [ "$status" -eq 0 ]
  OUTPUT="$output" python3 -c 'import json,os; assert json.loads(os.environ["OUTPUT"])["success"] is True'
  [[ "$stderr" == *'Skipped post-pull hooks'* ]]
  grove_run sync demo t3/review-ci-test-tiers main --json
  [ "$status" -eq 0 ]
  [[ "$stderr" == *'Skipped post-sync hooks'* ]]
  grove_run pull demo t3/review-ci-test-tiers
  [ "$status" -eq 0 ]
  [[ "$stderr" == *'Skipped post-pull hooks'* ]]

  [ ! -e "$HERD_ROOT/hook-events" ]
  [ ! -e "$(database_sidecar review-ci-test-tiers)" ]
  [ ! -e "$HERD_ROOT/demo-worktrees/review-ci-test-tiers/.env" ]
}

@test "pull and sync: a worktree sharing a database leaves it unrecorded and unchanged" {
  add_tracking_worktree codex/ci-test-tiers ci-test-tiers
  # As in a real app, .env is ignored, so it does not make the worktree dirty.
  mkdir -p "$HERD_ROOT/demo.git/info" && printf '.env\n' >> "$HERD_ROOT/demo.git/info/exclude"
  printf 'DB_DATABASE=demo__main\n' > "$HERD_ROOT/demo-worktrees/ci-test-tiers/.env"
  record_hooks
  grove_run pull demo codex/ci-test-tiers --json
  [ "$status" -eq 0 ]
  grove_run sync demo codex/ci-test-tiers main --json
  [ "$status" -eq 0 ]
  # The database .env names explicitly is passed on, never rewritten or recorded.
  grep -qx 'post-pull|demo__main|https://ci-test-tiers.test' "$HERD_ROOT/hook-events"
  grep -qx 'post-sync|demo__main|https://ci-test-tiers.test' "$HERD_ROOT/hook-events"
  [ "$(cat "$HERD_ROOT/demo-worktrees/ci-test-tiers/.env")" = 'DB_DATABASE=demo__main' ]
  [ ! -e "$(database_sidecar ci-test-tiers)" ]
}

@test "pull and sync: a worktree with its own recorded database runs its hooks" {
  add_tracking_worktree feature/own own-db
  printf 'demo__own\n' > "$(database_sidecar own-db)"
  record_hooks
  grove_run pull demo feature/own --json
  [ "$status" -eq 0 ]
  grove_run sync demo feature/own main --json
  [ "$status" -eq 0 ]
  grep -qx 'post-pull|demo__own|https://own-db.test' "$HERD_ROOT/hook-events"
  grep -qx 'post-sync|demo__own|https://own-db.test' "$HERD_ROOT/hook-events"
  [ "$(cat "$(database_sidecar own-db)")" = 'demo__own' ]
}

@test "pull and sync: real git failures still fail for a worktree with no database" {
  add_tracking_worktree t3/review-ci-cost-plan review-ci-cost-plan
  git -C "$HERD_ROOT/demo-worktrees/review-ci-cost-plan" branch -q --unset-upstream
  record_hooks
  grove_run pull demo t3/review-ci-cost-plan --json
  [ "$status" -eq 4 ]
  OUTPUT="$output" python3 -c 'import json,os; assert json.loads(os.environ["OUTPUT"])["success"] is False'
  [[ "$stderr" != *Skipped* ]]

  printf 'unsaved\n' > "$HERD_ROOT/demo-worktrees/review-ci-cost-plan/dirty"
  grove_run sync demo t3/review-ci-cost-plan main --json
  [ "$status" -eq 4 ]
  OUTPUT="$output" python3 -c 'import json,os; d=json.loads(os.environ["OUTPUT"]); assert d["success"] is False and d["dirty"] is True'
  [ ! -e "$HERD_ROOT/hook-events" ]
}

# A worktree whose files are offloaded to iCloud stalls `git status`; the
# listing must report it and return, not wait on it once per fallback.
@test "ls --json: a worktree whose git status hangs does not hang the listing" {
  add_worktree feature/fine fine
  add_worktree feature/stuck stuck
  mkdir -p "$TEST_TEMP_DIR/slowbin"
  cat > "$TEST_TEMP_DIR/slowbin/git" <<'GIT'
#!/bin/sh
case "$*" in *"/stuck status"*) exec sleep 60 ;; esac
exec /usr/bin/git "$@"
GIT
  chmod +x "$TEST_TEMP_DIR/slowbin/git"
  local started=$SECONDS
  run --separate-stderr env HOME="$TEST_TEMP_DIR/home" PATH="$TEST_TEMP_DIR/slowbin:/usr/bin:/bin" \
    GROVE_STATUS_TIMEOUT=2 zsh "$GROVE_ROOT/grove" ls demo --json
  [ "$status" -eq 0 ]
  [ $((SECONDS - started)) -lt 15 ]
  [[ "$output" == *feature/fine* && "$output" == *feature/stuck* ]]
}

@test "ls and status --json: a worktree whose status cannot be read is not reported clean" {
  add_worktree feature/fine fine
  add_worktree feature/stuck stuck
  echo uncommitted > "$HERD_ROOT/demo-worktrees/stuck/UNSAVED"
  mkdir -p "$TEST_TEMP_DIR/slowbin"
  cat > "$TEST_TEMP_DIR/slowbin/git" <<'GIT'
#!/bin/sh
case "$*" in *"/stuck status"*) exec sleep 60 ;; esac
exec /usr/bin/git "$@"
GIT
  chmod +x "$TEST_TEMP_DIR/slowbin/git"
  local command
  for command in ls status; do
    run --separate-stderr env HOME="$TEST_TEMP_DIR/home" PATH="$TEST_TEMP_DIR/slowbin:/usr/bin:/bin" \
      GROVE_STATUS_TIMEOUT=2 zsh "$GROVE_ROOT/grove" "$command" demo --json
    [ "$status" -eq 0 ]
    OUTPUT="$output" python3 -c '
import json,os
rows = {row["branch"]: row for row in json.loads(os.environ["OUTPUT"])}
assert rows["feature/stuck"]["dirty"] is True
assert rows["feature/fine"]["dirty"] is False'
  done
}

@test "removal-check -f agrees with rm -f about a worktree the live site selects" {
  add_worktree feature/live live
  ln -s "$HERD_ROOT/demo-worktrees/live" "$HERD_ROOT/demo-current"
  grove_run removal-check demo feature/live --json
  [[ "$output" == *'"verdict":"blocked"'* ]]
  grove_run removal-check -f demo feature/live --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"clear"'* && "$output" == *'will break'* ]]
}

@test "dashboard: one unreadable worktree means no overall grade" {
  add_worktree feature/fine fine
  add_worktree feature/stuck stuck
  printf 'main\n' > "$(git -C "$HERD_ROOT/demo-worktrees/fine" rev-parse --git-path grove-base)"
  mkdir -p "$TEST_TEMP_DIR/slowbin"
  cat > "$TEST_TEMP_DIR/slowbin/git" <<'GIT'
#!/bin/sh
case "$*" in *"/stuck status"*) exec sleep 60 ;; esac
exec /usr/bin/git "$@"
GIT
  chmod +x "$TEST_TEMP_DIR/slowbin/git"
  run --separate-stderr env HOME="$TEST_TEMP_DIR/home" PATH="$TEST_TEMP_DIR/slowbin:/usr/bin:/bin" \
    GROVE_STATUS_TIMEOUT=2 zsh "$GROVE_ROOT/grove" dashboard
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep '(2 worktrees)' | grep -q '?'
  [[ "$stderr" == *stuck*GROVE_STATUS_TIMEOUT* ]]
}
