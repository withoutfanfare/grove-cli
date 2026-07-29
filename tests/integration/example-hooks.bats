#!/usr/bin/env bats
# Safe, disposable checks for the bundled lifecycle hooks.

load '../test-helper'

setup() {
  setup_test_environment
  export EXAMPLE_HOOKS="${HOOKS_UNDER_TEST:-$GROVE_ROOT/examples/hooks}"
  export TEST_HOME="$TEST_TEMP_DIR/home"
  export HOOK_TEST_DIR="$TEST_TEMP_DIR/hook-test"
  mkdir -p "$TEST_HOME" "$HOOK_TEST_DIR/bin" "$HOOK_TEST_DIR/worktree"
}

teardown() {
  teardown_test_environment
}

@test "hook config loader preserves hashes in passwords and strips real comments" {
  cat > "$TEST_HOME/.groverc" <<'EOF'
DB_PASSWORD="placeholder#fragment" # local credential
DB_USER='o\'connor' # escaped quote
DB_HOST=localhost # local server
HERD_ROOT=$HOME/Herd
EOF

  run env HOME="$TEST_HOME" GROVE_REPO="" bash -c '
    source "$1/_lib/load-config.sh"
    printf "password=%s\nuser=%s\nhost=%s\nroot=%s\n" "$DB_PASSWORD" "$DB_USER" "$DB_HOST" "$HERD_ROOT"
  ' _ "$EXAMPLE_HOOKS"

  [ "$status" -eq 0 ]
  [[ "$output" == *"password=placeholder#fragment"* ]]
  [[ "$output" == *"user=o\\'connor"* ]]
  [[ "$output" == *"host=localhost"* ]]
  [[ "$output" == *"root=$TEST_HOME/Herd"* ]]
}

@test "database hook rejects an unsafe database name before invoking mysql" {
  run env \
    HOME="$TEST_HOME" \
    GROVE_DB_NAME='app`; SELECT 1; --' \
    GROVE_REPO=app \
    bash "$EXAMPLE_HOOKS/post-add.d/03-create-database.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid database name"* ]]
}

@test "database backup blocks removal when mysql is unreachable" {
  cat > "$HOOK_TEST_DIR/bin/mysql" <<'EOF'
#!/bin/sh
exit 1
EOF
  cat > "$HOOK_TEST_DIR/bin/mysqldump" <<'EOF'
#!/bin/sh
touch "$HOOK_TEST_DIR/dump-called"
exit 0
EOF
  chmod +x "$HOOK_TEST_DIR/bin/mysql" "$HOOK_TEST_DIR/bin/mysqldump"

  run env \
    HOME="$TEST_HOME" \
    PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" \
    HOOK_TEST_DIR="$HOOK_TEST_DIR" \
    GROVE_DB_NAME=app__feature \
    GROVE_REPO=app \
    DB_BACKUP_DIR="$HOOK_TEST_DIR/backups" \
    bash "$EXAMPLE_HOOKS/pre-rm.d/01-backup-database.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Cannot reach MySQL"* ]]
  [[ "$output" != *"does not exist"* ]]
  [ ! -e "$HOOK_TEST_DIR/dump-called" ]
}

@test "database backup keeps the password out of command arguments" {
  cat > "$HOOK_TEST_DIR/bin/mysql" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >> "$HOOK_TEST_DIR/mysql-args"
case "$*" in
  *information_schema*) printf '1\n' ;;
esac
exit 0
EOF
  cat > "$HOOK_TEST_DIR/bin/mysqldump" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$HOOK_TEST_DIR/mysqldump-args"
printf '%s' "$MYSQL_PWD" > "$HOOK_TEST_DIR/mysql-pwd"
printf '%s\n' '-- disposable dump'
EOF
  chmod +x "$HOOK_TEST_DIR/bin/mysql" "$HOOK_TEST_DIR/bin/mysqldump"

  run env \
    HOME="$TEST_HOME" \
    PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" \
    HOOK_TEST_DIR="$HOOK_TEST_DIR" \
    GROVE_DB_NAME=app__feature \
    GROVE_REPO=app \
    DB_PASSWORD='placeholder#fragment' \
    DB_BACKUP_DIR="$HOOK_TEST_DIR/backups" \
    bash "$EXAMPLE_HOOKS/pre-rm.d/01-backup-database.sh"

  [ "$status" -eq 0 ]
  ! grep -q 'placeholder#fragment' "$HOOK_TEST_DIR/mysql-args"
  ! grep -q 'placeholder#fragment' "$HOOK_TEST_DIR/mysqldump-args"
  [ "$(cat "$HOOK_TEST_DIR/mysql-pwd")" = 'placeholder#fragment' ]
  dump_file="$(find "$HOOK_TEST_DIR/backups" -type f -name '*.sql' -print -quit)"
  [ -n "$dump_file" ]
  mode="$(stat -f '%Lp' "$dump_file" 2>/dev/null || stat -c '%a' "$dump_file")"
  [ "$mode" = "600" ]
}

@test "environment backup blocks removal when the copy fails" {
  cat > "$HOOK_TEST_DIR/bin/cp" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$HOOK_TEST_DIR/bin/cp"
  printf 'APP_KEY=disposable\n' > "$HOOK_TEST_DIR/worktree/.env"
  mkdir -p \
    "$TEST_HOME/Code/Worktree/app/app-env" \
    "$TEST_HOME/Development/Code/Worktree/app/app-env"

  run env \
    HOME="$TEST_HOME" \
    PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" \
    GROVE_PATH="$HOOK_TEST_DIR/worktree" \
    GROVE_REPO=app \
    GROVE_BRANCH=feature/test \
    bash "$EXAMPLE_HOOKS/pre-rm.d/02-backup-env.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to backup .env - refusing removal"* ]]
  ! find "$TEST_HOME" -type f -name '.env.backup.*' | grep -q .
}

@test "composer and migrations use the same resolved Herd PHP" {
  local herd_php_dir="$TEST_HOME/Library/Application Support/Herd/bin"
  mkdir -p "$herd_php_dir"
  cat > "$herd_php_dir/php" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-r" ]; then
  exit 0
fi
printf '%s\n' "$*" >> "$HOOK_TEST_DIR/php-calls"
exit 0
EOF
  cat > "$HOOK_TEST_DIR/bin/composer" <<'EOF'
#!/bin/sh
exit 99
EOF
  chmod +x "$herd_php_dir/php" "$HOOK_TEST_DIR/bin/composer"
  touch "$HOOK_TEST_DIR/worktree/composer.json" "$HOOK_TEST_DIR/worktree/artisan"
  printf 'APP_KEY=base64:already-set\n' > "$HOOK_TEST_DIR/worktree/.env"

  run env \
    HOME="$TEST_HOME" \
    PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" \
    HOOK_TEST_DIR="$HOOK_TEST_DIR" \
    GROVE_PATH="$HOOK_TEST_DIR/worktree" \
    bash "$EXAMPLE_HOOKS/post-add.d/05-composer-install.sh"
  [ "$status" -eq 0 ]

  run env \
    HOME="$TEST_HOME" \
    PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" \
    HOOK_TEST_DIR="$HOOK_TEST_DIR" \
    GROVE_PATH="$HOOK_TEST_DIR/worktree" \
    bash "$EXAMPLE_HOOKS/post-add.d/08-run-migrations.sh"
  [ "$status" -eq 0 ]

  local expected_calls=2
  if [[ -f "$EXAMPLE_HOOKS/post-add.d/11-sanitise-emails.sh" ]]; then
    run env \
      HOME="$TEST_HOME" \
      PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" \
      HOOK_TEST_DIR="$HOOK_TEST_DIR" \
      GROVE_PATH="$HOOK_TEST_DIR/worktree" \
      bash "$EXAMPLE_HOOKS/post-add.d/11-sanitise-emails.sh"
    [ "$status" -eq 0 ]
    expected_calls=3
    grep -q 'artisan emails:sanitise' "$HOOK_TEST_DIR/php-calls"
  fi

  [ "$(wc -l < "$HOOK_TEST_DIR/php-calls" | tr -d ' ')" -eq "$expected_calls" ]
  grep -q "$HOOK_TEST_DIR/bin/composer install" "$HOOK_TEST_DIR/php-calls"
  grep -q 'artisan migrate' "$HOOK_TEST_DIR/php-calls"
  ! grep -q 'key:generate' "$HOOK_TEST_DIR/php-calls"
}

@test "composer generates a key for empty dotenv values" {
  cat > "$HOOK_TEST_DIR/bin/php" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HOOK_TEST_DIR/php-calls"
exit 0
EOF
  cat > "$HOOK_TEST_DIR/bin/composer" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$HOOK_TEST_DIR/bin/php" "$HOOK_TEST_DIR/bin/composer"
  touch "$HOOK_TEST_DIR/worktree/composer.json" "$HOOK_TEST_DIR/worktree/artisan"

  local env_line
  for env_line in 'APP_KEY=' 'APP_KEY=""' "APP_KEY=''" 'APP_KEY=   ' 'APP_KEY="   "' \
                  'APP_KEY="" # comment' "APP_KEY='' # comment" 'APP_KEY= # comment'; do
    printf '%s\n' "$env_line" > "$HOOK_TEST_DIR/worktree/.env"
    : > "$HOOK_TEST_DIR/php-calls"

    run env \
      HOME="$TEST_HOME" \
      PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" \
      HOOK_TEST_DIR="$HOOK_TEST_DIR" \
      GROVE_PATH="$HOOK_TEST_DIR/worktree" \
      GROVE_PHP_BIN="$HOOK_TEST_DIR/bin/php" \
      bash "$EXAMPLE_HOOKS/post-add.d/05-composer-install.sh"

    [ "$status" -eq 0 ]
    grep -q 'artisan key:generate --force' "$HOOK_TEST_DIR/php-calls"
  done
}

@test "composer keeps an existing key that has a trailing comment" {
  cat > "$HOOK_TEST_DIR/bin/php" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HOOK_TEST_DIR/php-calls"
exit 0
EOF
  cat > "$HOOK_TEST_DIR/bin/composer" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$HOOK_TEST_DIR/bin/php" "$HOOK_TEST_DIR/bin/composer"
  touch "$HOOK_TEST_DIR/worktree/composer.json" "$HOOK_TEST_DIR/worktree/artisan"

  local env_line
  for env_line in 'APP_KEY="base64:keep" # comment' "APP_KEY='base64:keep' # comment" 'APP_KEY=base64:keep # comment'; do
    printf '%s\n' "$env_line" > "$HOOK_TEST_DIR/worktree/.env"
    : > "$HOOK_TEST_DIR/php-calls"

    run env \
      HOME="$TEST_HOME" \
      PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" \
      HOOK_TEST_DIR="$HOOK_TEST_DIR" \
      GROVE_PATH="$HOOK_TEST_DIR/worktree" \
      GROVE_PHP_BIN="$HOOK_TEST_DIR/bin/php" \
      bash "$EXAMPLE_HOOKS/post-add.d/05-composer-install.sh"

    [ "$status" -eq 0 ]
    ! grep -q 'key:generate' "$HOOK_TEST_DIR/php-calls"
  done
}

@test "clean hook does not delete git index locks" {
  [[ -f "$EXAMPLE_HOOKS/post-add.d/99-clean-worktree.sh" ]] || skip "local clean hook is not bundled"

  local lock="$TEST_HOME/Herd/app.git/worktrees/feature/index.lock"
  mkdir -p "${lock%/*}"
  touch "$lock"

  run env \
    HOME="$TEST_HOME" \
    GROVE_PATH="$HOOK_TEST_DIR/worktree" \
    bash "$EXAMPLE_HOOKS/post-add.d/99-clean-worktree.sh"

  [ "$status" -eq 0 ]
  [ -f "$lock" ]
}

@test "clean hook preserves tracked setup changes" {
  [[ -f "$EXAMPLE_HOOKS/post-add.d/99-clean-worktree.sh" ]] || skip "local clean hook is not bundled"

  git -C "$HOOK_TEST_DIR/worktree" init -q
  git -C "$HOOK_TEST_DIR/worktree" config user.email test@example.com
  git -C "$HOOK_TEST_DIR/worktree" config user.name Test
  mkdir -p "$HOOK_TEST_DIR/worktree/storage"
  printf 'original\n' > "$HOOK_TEST_DIR/worktree/storage/state.txt"
  printf 'original\n' > "$HOOK_TEST_DIR/worktree/package-lock.json"
  git -C "$HOOK_TEST_DIR/worktree" add storage/state.txt package-lock.json
  git -C "$HOOK_TEST_DIR/worktree" commit -qm fixture
  printf 'generated\n' > "$HOOK_TEST_DIR/worktree/storage/state.txt"
  printf 'generated\n' > "$HOOK_TEST_DIR/worktree/package-lock.json"

  run env GROVE_PATH="$HOOK_TEST_DIR/worktree" \
    bash "$EXAMPLE_HOOKS/post-add.d/99-clean-worktree.sh"

  [ "$status" -eq 0 ]
  [ "$(cat "$HOOK_TEST_DIR/worktree/storage/state.txt")" = "generated" ]
  [ "$(cat "$HOOK_TEST_DIR/worktree/package-lock.json")" = "generated" ]
}

@test "image symlink hook refuses to delete a populated directory" {
  local images_source="$HOOK_TEST_DIR/images"
  mkdir -p "$images_source" "$HOOK_TEST_DIR/worktree/storage/app/public"
  printf 'keep\n' > "$HOOK_TEST_DIR/worktree/storage/app/public/image.jpg"

  local source_script fixture_script
  local found=false
  for source_script in \
    "$EXAMPLE_HOOKS/post-add.d/modernprintworks/05-symlink-images.sh" \
    "$EXAMPLE_HOOKS/post-switch.d/modernprintworks/01-symlink-images.sh"; do
    [[ -f "$source_script" ]] || continue
    found=true
    fixture_script="$HOOK_TEST_DIR/$(basename "$source_script")"
    sed "s|^IMAGES_SOURCE=.*|IMAGES_SOURCE=\"$images_source\"|" "$source_script" > "$fixture_script"

    run env GROVE_PATH="$HOOK_TEST_DIR/worktree" bash "$fixture_script"

    [ "$status" -eq 1 ]
    [ -f "$HOOK_TEST_DIR/worktree/storage/app/public/image.jpg" ]
    [ ! -L "$HOOK_TEST_DIR/worktree/storage/app/public" ]
  done

  [[ "$found" == "true" ]] || skip "local image hooks are not bundled"
}

@test "repo link helpers reject traversal, reserved names, and symlinked targets" {
  local fixture_root="$HOOK_TEST_DIR/link-hooks/post-add.d"
  mkdir -p "$fixture_root"

  local kind
  for kind in _laravel _node; do
    [[ -d "$EXAMPLE_HOOKS/post-add.d/$kind" ]] || continue
    cp -R "$EXAMPLE_HOOKS/post-add.d/$kind" "$fixture_root/$kind"

    run bash "$fixture_root/$kind/link-repo.sh" ../escape
    [ "$status" -eq 1 ]
    [ ! -e "$HOOK_TEST_DIR/link-hooks/escape" ]

    run bash "$fixture_root/$kind/link-repo.sh" "$kind"
    [ "$status" -eq 1 ]

    mkdir -p "$HOOK_TEST_DIR/outside-$kind"
    ln -s "$HOOK_TEST_DIR/outside-$kind" "$fixture_root/safe-$kind"
    run bash "$fixture_root/$kind/link-repo.sh" "safe-$kind"
    [ "$status" -eq 1 ]
    [ -z "$(find "$HOOK_TEST_DIR/outside-$kind" -mindepth 1 -print -quit)" ]

    local repo_name="app-$kind"
    mkdir -p "$fixture_root/$repo_name"
    printf 'custom hook\n' > "$fixture_root/$repo_name/01-ai-files.sh"
    run bash "$fixture_root/$kind/link-repo.sh" "$repo_name"
    [ "$status" -eq 0 ]
    [ "$(cat "$fixture_root/$repo_name/01-ai-files.sh")" = "custom hook" ]
  done
}

@test "Laravel storage hook preserves a populated worktree directory" {
  local hook="$EXAMPLE_HOOKS/post-add.d/_laravel/05-symlink-storage.sh"
  local shared="$TEST_HOME/Development/Code/Worktree/app/storage/app"
  mkdir -p "$shared" "$HOOK_TEST_DIR/worktree/storage/app"
  printf 'keep\n' > "$HOOK_TEST_DIR/worktree/storage/app/upload.txt"

  run env \
    HOME="$TEST_HOME" \
    GROVE_REPO=app \
    GROVE_PATH="$HOOK_TEST_DIR/worktree" \
    bash "$hook"

  [ "$status" -eq 1 ]
  [ -f "$HOOK_TEST_DIR/worktree/storage/app/upload.txt" ]
  [ ! -L "$HOOK_TEST_DIR/worktree/storage/app" ]
}

@test "shared storage hooks preserve a symlink to another target" {
  local hook worktree other_target original_target
  for hook in \
    "$EXAMPLE_HOOKS/post-add.d/_laravel/05-symlink-storage.sh" \
    "$EXAMPLE_HOOKS/post-add.d/myapp/05-symlink-storage.sh"; do
    [[ -f "$hook" ]] || continue
    worktree="$HOOK_TEST_DIR/storage-link-$(basename "$(dirname "$hook")")"
    other_target="$HOOK_TEST_DIR/existing-storage-$(basename "$(dirname "$hook")")"
    mkdir -p "$worktree/storage" "$other_target"
    printf 'keep\n' > "$other_target/upload.txt"
    ln -s "$other_target" "$worktree/storage/app"
    original_target="$(readlink "$worktree/storage/app")"

    run env HOME="$TEST_HOME" GROVE_REPO=app GROVE_PATH="$worktree" bash "$hook"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Refusing to replace storage/app symlink"* ]]
    [ "$(readlink "$worktree/storage/app")" = "$original_target" ]
    [ -f "$worktree/storage/app/upload.txt" ]
  done
}

@test "local documentation hook preserves populated docs and specs" {
  local hook="$EXAMPLE_HOOKS/post-add.d/knotbook/05-symlink-docs.sh"
  [[ -f "$hook" ]] || skip "local documentation hook is not bundled"

  local cloud="$TEST_HOME/Library/Mobile Documents/com~apple~CloudDocs/Wedding Planner/Build"
  mkdir -p "$cloud/Documentation" "$cloud/Specification"
  mkdir -p "$HOOK_TEST_DIR/worktree/docs" "$HOOK_TEST_DIR/worktree/specs"
  printf 'keep docs\n' > "$HOOK_TEST_DIR/worktree/docs/local.md"
  printf 'keep specs\n' > "$HOOK_TEST_DIR/worktree/specs/local.md"

  run env HOME="$TEST_HOME" GROVE_PATH="$HOOK_TEST_DIR/worktree" bash "$hook"

  [ "$status" -eq 1 ]
  [ -f "$HOOK_TEST_DIR/worktree/docs/local.md" ]
  [ -f "$HOOK_TEST_DIR/worktree/specs/local.md" ]
}

@test "Laravel scaffold keeps runtime files owner-only" {
  local hook="$EXAMPLE_HOOKS/post-add.d/04-laravel-scaffold.sh"
  touch "$HOOK_TEST_DIR/worktree/artisan"
  mkdir -p \
    "$HOOK_TEST_DIR/worktree/bootstrap/cache" \
    "$HOOK_TEST_DIR/worktree/storage/framework/cache/data" \
    "$HOOK_TEST_DIR/worktree/storage/framework/sessions" \
    "$HOOK_TEST_DIR/worktree/storage/framework/testing" \
    "$HOOK_TEST_DIR/worktree/storage/framework/views" \
    "$HOOK_TEST_DIR/worktree/storage/logs"
  printf 'private\n' > "$HOOK_TEST_DIR/worktree/storage/logs/laravel.log"
  chmod 0666 "$HOOK_TEST_DIR/worktree/storage/logs/laravel.log"

  run env GROVE_PATH="$HOOK_TEST_DIR/worktree" bash "$hook"

  [ "$status" -eq 0 ]
  mode="$(stat -f '%Lp' "$HOOK_TEST_DIR/worktree/storage/logs/laravel.log" 2>/dev/null || \
    stat -c '%a' "$HOOK_TEST_DIR/worktree/storage/logs/laravel.log")"
  [ "$mode" = "600" ]
}

@test "Laravel setup stores the environment template as 0600" {
  local fixture="$HOOK_TEST_DIR/setup-hooks"
  mkdir -p "$fixture/post-add.d"
  cp "$EXAMPLE_HOOKS/setup-laravel-repo.sh" "$fixture/setup-laravel-repo.sh"
  cp -R "$EXAMPLE_HOOKS/_lib" "$fixture/_lib"
  cp -R "$EXAMPLE_HOOKS/post-add.d/_laravel" "$fixture/post-add.d/_laravel"

  local primary="$TEST_HOME/Herd/app-worktrees/app"
  mkdir -p "$TEST_HOME/Herd/app.git" "$primary"
  touch "$primary/artisan"
  printf 'APP_KEY=private\n' > "$primary/.env"

  run env HOME="$TEST_HOME" HERD_ROOT="$TEST_HOME/Herd" bash "$fixture/setup-laravel-repo.sh" app

  [ "$status" -eq 0 ]
  local template="$TEST_HOME/Development/Code/Worktree/app/app-env/.env"
  mode="$(stat -f '%Lp' "$template" 2>/dev/null || stat -c '%a' "$template")"
  [ "$mode" = "600" ]
}

@test "project registry hooks treat metacharacters as literal key text" {
  local remove_hook="$EXAMPLE_HOOKS/post-rm"
  local add_hook
  local registry
  if grep -q '\.zsh_projects' "$remove_hook"; then
    registry="$TEST_HOME/.zsh_projects"
    add_hook="$EXAMPLE_HOOKS/post-add.d/00-zsh-projects.sh"
  else
    registry="$TEST_HOME/.projects"
    add_hook="$EXAMPLE_HOOKS/post-add.d/00-register-project.sh"
  fi

  printf '%s\n' \
    'a1Xtest=/keep-one' \
    'a[1].test=/remove' \
    'other=/keep-two' > "$registry"

  run env HOME="$TEST_HOME" GROVE_PATH='/tmp/a[1].test' bash "$remove_hook"

  [ "$status" -eq 0 ]
  grep -Fxq 'a1Xtest=/keep-one' "$registry"
  grep -Fxq 'other=/keep-two' "$registry"
  ! grep -Fq 'a[1].test=' "$registry"

  run env HOME="$TEST_HOME" GROVE_PATH='/tmp/a[1].test' bash "$add_hook"

  [ "$status" -eq 0 ]
  grep -Fxq 'a[1].test=/tmp/a[1].test' "$registry"
}

@test "environment backup creates a private destination when setup is missing" {
  printf 'APP_KEY=disposable\n' > "$HOOK_TEST_DIR/worktree/.env"

  run env \
    HOME="$TEST_HOME" \
    GROVE_PATH="$HOOK_TEST_DIR/worktree" \
    GROVE_REPO=app \
    GROVE_BRANCH=feature/test \
    bash "$EXAMPLE_HOOKS/pre-rm.d/02-backup-env.sh"

  [ "$status" -eq 0 ]
  backup="$(find "$TEST_HOME" -type f -name '.env.backup.*' -print -quit)"
  [ -n "$backup" ]
  mode="$(stat -f '%Lp' "$backup" 2>/dev/null || stat -c '%a' "$backup")"
  [ "$mode" = "600" ]
}

@test "environment copy is private, preserves existing data, and reports install failure" {
  printf 'APP_KEY=fallback\n' > "$HOOK_TEST_DIR/worktree/.env.example"

  run env GROVE_PATH="$HOOK_TEST_DIR/worktree" bash "$EXAMPLE_HOOKS/post-add.d/01-copy-env.sh"
  [ "$status" -eq 0 ]
  mode="$(stat -f '%Lp' "$HOOK_TEST_DIR/worktree/.env" 2>/dev/null || \
    stat -c '%a' "$HOOK_TEST_DIR/worktree/.env")"
  [ "$mode" = "600" ]

  mkdir -p \
    "$TEST_HOME/Code/Worktree/app/app-env" \
    "$TEST_HOME/Code/Worktree/myapp/myapp-env" \
    "$TEST_HOME/Development/Code/Worktree/app/app-env"
  printf 'APP_KEY=template\n' > "$TEST_HOME/Code/Worktree/app/app-env/.env"
  printf 'APP_KEY=template\n' > "$TEST_HOME/Code/Worktree/myapp/myapp-env/.env"
  printf 'APP_KEY=template\n' > "$TEST_HOME/Development/Code/Worktree/app/app-env/.env"

  run env HOME="$TEST_HOME" GROVE_PATH="$HOOK_TEST_DIR/worktree" GROVE_REPO=app \
    bash "$EXAMPLE_HOOKS/post-add.d/_laravel/02-copy-env.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOOK_TEST_DIR/worktree/.env")" = "APP_KEY=template" ]

  printf 'APP_KEY=fallback\n' > "$HOOK_TEST_DIR/worktree/.env"
  run env HOME="$TEST_HOME" GROVE_PATH="$HOOK_TEST_DIR/worktree" GROVE_REPO=myapp \
    bash "$EXAMPLE_HOOKS/post-add.d/myapp/02-symlink-env.sh"
  [ "$status" -eq 0 ]
  [ -L "$HOOK_TEST_DIR/worktree/.env" ]
  [ "$(readlink "$HOOK_TEST_DIR/worktree/.env")" = "$TEST_HOME/Code/Worktree/myapp/myapp-env/.env" ]

  rm "$HOOK_TEST_DIR/worktree/.env"
  printf 'APP_KEY=custom\n' > "$HOOK_TEST_DIR/worktree/.env"
  run env HOME="$TEST_HOME" GROVE_PATH="$HOOK_TEST_DIR/worktree" GROVE_REPO=app \
    bash "$EXAMPLE_HOOKS/post-add.d/_laravel/02-copy-env.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOOK_TEST_DIR/worktree/.env")" = "APP_KEY=custom" ]

  rm "$HOOK_TEST_DIR/worktree/.env"
  cat > "$HOOK_TEST_DIR/bin/install" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$HOOK_TEST_DIR/bin/install"
  run env PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" GROVE_PATH="$HOOK_TEST_DIR/worktree" \
    bash "$EXAMPLE_HOOKS/post-add.d/01-copy-env.sh"
  [ "$status" -eq 1 ]
  [ ! -e "$HOOK_TEST_DIR/worktree/.env" ]
}

@test "AI import preserves files and refuses destination symlinks" {
  local kind source target symlink_target outside
  for kind in _laravel _node; do
    [[ -f "$EXAMPLE_HOOKS/post-add.d/$kind/01-ai-files.sh" ]] || continue
    source="$TEST_HOME/Development/Code/Worktree/app/app-llm"
    target="$HOOK_TEST_DIR/ai-$kind"
    mkdir -p "$source" "$target"
    printf 'source instructions\n' > "$source/AGENTS.md"
    printf 'new file\n' > "$source/new.txt"
    printf 'branch instructions\n' > "$target/AGENTS.md"

    run env HOME="$TEST_HOME" GROVE_REPO=app GROVE_PATH="$target" \
      bash "$EXAMPLE_HOOKS/post-add.d/$kind/01-ai-files.sh"
    [ "$status" -eq 0 ]
    [ "$(cat "$target/AGENTS.md")" = "branch instructions" ]
    [ "$(cat "$target/new.txt")" = "new file" ]

    mkdir -p "$source/config"
    printf 'source config\n' > "$source/config/settings"
    outside="$HOOK_TEST_DIR/outside-ai-$kind"
    symlink_target="$HOOK_TEST_DIR/ai-link-$kind"
    mkdir -p "$outside" "$symlink_target"
    ln -s "$outside" "$symlink_target/config"

    run env HOME="$TEST_HOME" GROVE_REPO=app GROVE_PATH="$symlink_target" \
      bash "$EXAMPLE_HOOKS/post-add.d/$kind/01-ai-files.sh"
    [ "$status" -eq 1 ]
    [ -L "$symlink_target/config" ]
    [ ! -e "$outside/settings" ]
  done
}

@test "database import skips a retained database with tables" {
  local dump_dir="$TEST_HOME/Development/Code/Worktree/app/app-db"
  mkdir -p "$dump_dir"
  printf '%s\n' 'DROP TABLE important;' | gzip > "$dump_dir/app.sql.gz"
  cat > "$HOOK_TEST_DIR/bin/mysql" <<'EOF'
#!/bin/sh
case "$*" in
  *information_schema.TABLES*) printf '1\n'; exit 0 ;;
esac
touch "$HOOK_TEST_DIR/import-called"
exit 0
EOF
  chmod +x "$HOOK_TEST_DIR/bin/mysql"

  run env \
    HOME="$TEST_HOME" \
    PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" \
    HOOK_TEST_DIR="$HOOK_TEST_DIR" \
    GROVE_REPO=app \
    GROVE_DB_NAME=app__feature \
    DB_CREATE=true \
    bash "$EXAMPLE_HOOKS/post-add.d/_laravel/04-import-database.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"already contains tables"* ]]
  [ ! -e "$HOOK_TEST_DIR/import-called" ]
}

@test "local Herd cleanup removes only the exact legacy site" {
  local hook="$EXAMPLE_HOOKS/post-add.d/04-herd-secure.sh"
  grep -q 'cleanup_stale_configs' "$hook" || skip "local legacy cleanup is not bundled"
  local herd_config="$HOOK_TEST_DIR/herd-config"
  mkdir -p "$herd_config/valet/Nginx" "$herd_config/valet/Certificates" "$HOOK_TEST_DIR/fix"
  touch \
    "$herd_config/valet/Nginx/repo--fix.test" \
    "$herd_config/valet/Nginx/repo--prefix-fix-other.test" \
    "$herd_config/valet/Certificates/repo--fix.test.crt" \
    "$herd_config/valet/Certificates/repo--prefix-fix-other.test.crt"
  cat > "$HOOK_TEST_DIR/bin/herd" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$HOOK_TEST_DIR/bin/herd"

  run env \
    PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" \
    GROVE_PATH="$HOOK_TEST_DIR/fix" \
    GROVE_REPO=repo \
    GROVE_URL=https://fix.test \
    HERD_CONFIG="$herd_config" \
    bash "$hook"

  [ "$status" -eq 0 ]
  [ ! -e "$herd_config/valet/Nginx/repo--fix.test" ]
  [ ! -e "$herd_config/valet/Certificates/repo--fix.test.crt" ]
  [ -e "$herd_config/valet/Nginx/repo--prefix-fix-other.test" ]
  [ -e "$herd_config/valet/Certificates/repo--prefix-fix-other.test.crt" ]
}

@test "shared storage hook preserves tracked sentinel layouts" {
  local hook worktree
  for hook in \
    "$EXAMPLE_HOOKS/post-add.d/_laravel/05-symlink-storage.sh" \
    "$EXAMPLE_HOOKS/post-add.d/myapp/05-symlink-storage.sh"; do
    [[ -f "$hook" ]] || continue
    worktree="$HOOK_TEST_DIR/storage-$(basename "$(dirname "$hook")")"
    mkdir -p "$worktree/storage/app"
    printf '*\n!.gitignore\n' > "$worktree/storage/app/.gitignore"

    run env HOME="$TEST_HOME" GROVE_REPO=app GROVE_PATH="$worktree" bash "$hook"

    [ "$status" -eq 1 ]
    [ -f "$worktree/storage/app/.gitignore" ]
    [ ! -L "$worktree/storage/app" ]
  done
}

@test "Laravel preflight blocks shared storage conflicts even when warnings are skipped" {
  local fixture="$HOOK_TEST_DIR/preflight-hooks"
  local primary="$TEST_HOME/Herd/app-worktrees/app"
  mkdir -p \
    "$fixture/pre-add.d" \
    "$fixture/post-add.d/app" \
    "$fixture/post-add.d/_laravel" \
    "$fixture/_lib" \
    "$primary/storage/app"
  cp "$EXAMPLE_HOOKS/pre-add.d/00-laravel-preflight.sh" "$fixture/pre-add.d/"
  cp "$EXAMPLE_HOOKS/_lib/load-config.sh" "$fixture/_lib/"
  cp "$EXAMPLE_HOOKS/post-add.d/_laravel/05-symlink-storage.sh" \
    "$fixture/post-add.d/_laravel/05-symlink-storage.sh"
  ln -s ../_laravel/05-symlink-storage.sh \
    "$fixture/post-add.d/app/05-symlink-storage.sh"
  touch "$primary/artisan"
  printf '*\n!.gitignore\n' > "$primary/storage/app/.gitignore"

  run env \
    HOME="$TEST_HOME" \
    HERD_ROOT="$TEST_HOME/Herd" \
    GROVE_REPO=app \
    GROVE_PATH="$TEST_HOME/Herd/app-worktrees/feature" \
    GROVE_SKIP_PREFLIGHT=true \
    bash "$fixture/pre-add.d/00-laravel-preflight.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"contains local files"* ]]

  rm "$primary/storage/app/.gitignore"
  run env \
    HOME="$TEST_HOME" \
    HERD_ROOT="$TEST_HOME/Herd" \
    GROVE_REPO=app \
    GROVE_PATH="$TEST_HOME/Herd/app-worktrees/feature" \
    GROVE_SKIP_PREFLIGHT=true \
    bash "$fixture/pre-add.d/00-laravel-preflight.sh"

  [ "$status" -eq 0 ]

  printf '*\n!.gitignore\n' > "$primary/storage/app/.gitignore"
  rm "$fixture/post-add.d/app/05-symlink-storage.sh"
  printf '#!/bin/sh\nexit 0\n' > "$fixture/post-add.d/app/05-symlink-storage.sh"
  chmod +x "$fixture/post-add.d/app/05-symlink-storage.sh"
  run env \
    HOME="$TEST_HOME" \
    HERD_ROOT="$TEST_HOME/Herd" \
    GROVE_REPO=app \
    GROVE_PATH="$TEST_HOME/Herd/app-worktrees/feature" \
    GROVE_SKIP_PREFLIGHT=true \
    bash "$fixture/pre-add.d/00-laravel-preflight.sh"

  [ "$status" -eq 0 ]
}

@test "pre-removal storage guard only permits tracked sentinels and external links" {
  local hook="$EXAMPLE_HOOKS/pre-rm.d/02a-guard-local-storage.sh"
  mkdir -p "$HOOK_TEST_DIR/worktree/storage/app/uploads"
  printf 'keep\n' > "$HOOK_TEST_DIR/worktree/storage/app/uploads/photo.jpg"

  run env GROVE_PATH="$HOOK_TEST_DIR/worktree" bash "$hook"

  [ "$status" -eq 1 ]
  [[ "$output" == *"contains local data"* ]]
  [ -f "$HOOK_TEST_DIR/worktree/storage/app/uploads/photo.jpg" ]

  rm "$HOOK_TEST_DIR/worktree/storage/app/uploads/photo.jpg"
  printf '*\n!.gitignore\n' > "$HOOK_TEST_DIR/worktree/storage/app/.gitignore"

  run env GROVE_PATH="$HOOK_TEST_DIR/worktree" bash "$hook"

  [ "$status" -eq 1 ]
  [[ "$output" == *"is not tracked by Git"* ]]

  git -C "$HOOK_TEST_DIR/worktree" init -q
  git -C "$HOOK_TEST_DIR/worktree" config user.email test@example.com
  git -C "$HOOK_TEST_DIR/worktree" config user.name Test
  git -C "$HOOK_TEST_DIR/worktree" add -f storage/app/.gitignore
  git -C "$HOOK_TEST_DIR/worktree" commit -qm fixture

  run env GROVE_PATH="$HOOK_TEST_DIR/worktree" bash "$hook"

  [ "$status" -eq 0 ]

  printf '# local tweak\n' >> "$HOOK_TEST_DIR/worktree/storage/app/.gitignore"

  run env GROVE_PATH="$HOOK_TEST_DIR/worktree" bash "$hook"

  [ "$status" -eq 1 ]
  [[ "$output" == *"has uncommitted changes"* ]]

  git -C "$HOOK_TEST_DIR/worktree" add -f storage/app/.gitignore

  run env GROVE_PATH="$HOOK_TEST_DIR/worktree" bash "$hook"

  [ "$status" -eq 1 ]
  [[ "$output" == *"has uncommitted changes"* ]]

  git -C "$HOOK_TEST_DIR/worktree" checkout -q HEAD -- storage/app/.gitignore

  rm "$HOOK_TEST_DIR/worktree/storage/app/.gitignore"
  rmdir "$HOOK_TEST_DIR/worktree/storage/app/uploads"
  rmdir "$HOOK_TEST_DIR/worktree/storage/app"
  mkdir -p "$HOOK_TEST_DIR/worktree/local-uploads"
  printf 'keep\n' > "$HOOK_TEST_DIR/worktree/local-uploads/photo.jpg"
  ln -s ../local-uploads "$HOOK_TEST_DIR/worktree/storage/app"

  run env GROVE_PATH="$HOOK_TEST_DIR/worktree" bash "$hook"

  [ "$status" -eq 1 ]
  [[ "$output" == *"points inside the worktree"* ]]
  [ -f "$HOOK_TEST_DIR/worktree/local-uploads/photo.jpg" ]

  rm "$HOOK_TEST_DIR/worktree/storage/app"
  mkdir -p "$HOOK_TEST_DIR/shared-storage"
  printf 'shared\n' > "$HOOK_TEST_DIR/shared-storage/photo.jpg"
  ln -s "$HOOK_TEST_DIR/shared-storage" "$HOOK_TEST_DIR/worktree/storage/app"

  run env GROVE_PATH="$HOOK_TEST_DIR/worktree" bash "$hook"

  [ "$status" -eq 0 ]
  [ -f "$HOOK_TEST_DIR/shared-storage/photo.jpg" ]
}

@test "hooks-path setup preserves an effective custom configuration" {
  local hook="$EXAMPLE_HOOKS/post-add.d/10-set-hooks-path.sh"
  local herd="$HOOK_TEST_DIR/herd"
  local worktree="$herd/app-worktrees/feature"
  local global_config="$HOOK_TEST_DIR/global.gitconfig"
  mkdir -p "$worktree" "$herd/app.git"
  git -C "$worktree" init -q
  GIT_CONFIG_GLOBAL="$global_config" git config --global core.hooksPath /custom-hooks

  run env \
    GIT_CONFIG_GLOBAL="$global_config" \
    GROVE_REPO=app \
    GROVE_PATH="$worktree" \
    bash "$hook"

  [ "$status" -eq 0 ]
  [ "$(GIT_CONFIG_GLOBAL="$global_config" git -C "$worktree" config --get core.hooksPath)" = "/custom-hooks" ]
  ! GIT_CONFIG_GLOBAL="$global_config" git -C "$worktree" config --local --get core.hooksPath >/dev/null
}

@test "project removal refuses to replace a symlinked registry" {
  local remove_hook="$EXAMPLE_HOOKS/post-rm"
  local registry target
  if grep -q '\.zsh_projects' "$remove_hook"; then
    registry="$TEST_HOME/.zsh_projects"
  else
    registry="$TEST_HOME/.projects"
  fi
  target="$TEST_HOME/registry-target"
  printf 'app=/tmp/app\n' > "$target"
  ln -s "$target" "$registry"

  run env HOME="$TEST_HOME" GROVE_PATH=/tmp/app bash "$remove_hook"

  [ "$status" -eq 1 ]
  [ -L "$registry" ]
  grep -Fxq 'app=/tmp/app' "$target"
}

@test "local PHP policy rejects non-8.4 fallbacks" {
  grep -q 'PHP 8.4' "$EXAMPLE_HOOKS/_lib/php-runtime.sh" || skip "generic hook runtime has no 8.4 policy"
  local herd_php_dir="$TEST_HOME/Library/Application Support/Herd/bin"
  mkdir -p "$herd_php_dir"
  cat > "$herd_php_dir/php" <<'EOF'
#!/bin/sh
exit 1
EOF
  cat > "$HOOK_TEST_DIR/bin/php" <<'EOF'
#!/bin/sh
exit 1
EOF
  cat > "$HOOK_TEST_DIR/bin/composer" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$herd_php_dir/php" "$HOOK_TEST_DIR/bin/php" "$HOOK_TEST_DIR/bin/composer"
  touch "$HOOK_TEST_DIR/worktree/composer.json"

  run env \
    HOME="$TEST_HOME" \
    PATH="$HOOK_TEST_DIR/bin:/usr/bin:/bin" \
    GROVE_PATH="$HOOK_TEST_DIR/worktree" \
    bash "$EXAMPLE_HOOKS/post-add.d/05-composer-install.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"PHP not found"* ]]
}
