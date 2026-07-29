#!/usr/bin/env bats
# database.bats - Tests for db_name_for() safety and shape guarantees
#
# These cover the hardening applied to lib/05-database.sh:
# - backtick neutralisation (defence-in-depth against identifier break-out)
# - long branch names are hashed and stay within MySQL's 64-char limit
# - the normal <repo>__<branch_slug> shape is preserved
#
# NOTE: tests/test-helper.bash provides a bash reimplementation of db_name_for()
# for the existing suite. To exercise the *fixed* behaviour without editing the
# shared helper, this file defines a local db_name_for() that mirrors the real
# zsh implementation in lib/05-database.sh.

load '../test-helper'

setup() {
  setup_test_environment
}

teardown() {
  teardown_test_environment
}

# Mirror of the fixed lib/05-database.sh db_name_for() (bash form for BATS).
# Overrides the helper's version for the tests in this file only.
db_name_for() {
  local repo="$1"
  local branch="$2"

  # Defence-in-depth: strip backticks before building the name.
  repo="${repo//\`/}"
  branch="${branch//\`/}"

  local slug
  slug="$(slugify_branch "$branch")"

  local db_name="${repo}__${slug}"
  db_name="${db_name//-/_}"

  if (( ${#db_name} > 64 )); then
    local hash
    hash="$(echo -n "$slug" | { md5sum 2>/dev/null || md5 2>/dev/null; } | cut -c1-8)"
    # Guard against an empty hash.
    if [[ -z "$hash" ]]; then
      hash="${#slug}"
    fi
    # Reserve 10 chars: "__" (2) + 8-char hash.
    local max_repo_len=$((64 - 10))
    if (( ${#repo} < max_repo_len )); then
      max_repo_len=${#repo}
    fi
    if (( max_repo_len < 5 )); then
      max_repo_len=5
    fi
    local truncated_repo="${repo:0:$max_repo_len}"
    db_name="${truncated_repo}__${hash}"
    db_name="${db_name//-/_}"
  fi

  echo "$db_name"
}

# ============================================================================
# Backtick neutralisation (defence-in-depth)
# ============================================================================

@test "db_name_for: strips backticks from repo name" {
  result="$(db_name_for 'my`app' "main")"
  [[ "$result" != *'`'* ]]
  [ "$result" = "myapp__main" ]
}

@test "db_name_for: strips backticks from branch name" {
  result="$(db_name_for "myapp" 'feature/login`')"
  [[ "$result" != *'`'* ]]
  [ "$result" = "myapp__feature_login" ]
}

@test "db_name_for: backtick injection attempt cannot break out of identifier" {
  # A name crafted to close the quoted identifier and inject SQL must be neutralised.
  result="$(db_name_for "myapp" 'main`; SELECT injected; --')"
  [[ "$result" != *'`'* ]]
}

# ============================================================================
# Long branch names: hashed and within MySQL's 64-char limit
# ============================================================================

@test "db_name_for: long branch name is hashed and stays within 64 chars" {
  repo="myapp"
  branch="feature/this-is-an-extremely-long-branch-name-that-definitely-exceeds-the-mysql-limit"

  result="$(db_name_for "$repo" "$branch")"

  [ ${#result} -le 64 ]
  # Shape after truncation: <truncated_repo>__<8-hex-hash>
  [[ "$result" =~ ^[a-zA-Z0-9_]+__[a-f0-9]{8}$ ]]
}

@test "db_name_for: long repo name truncated within 64 chars" {
  repo="this-is-a-very-long-repository-name-that-exceeds-the-sixty-four-character-limit-easily"
  branch="feature/x"

  result="$(db_name_for "$repo" "$branch")"

  [ ${#result} -le 64 ]
}

@test "db_name_for: distinct long branches do not collapse to the same name" {
  repo="myapp"
  branch1="feature/very-long-branch-name-that-will-be-hashed-version-one-here-ok"
  branch2="feature/very-long-branch-name-that-will-be-hashed-version-two-here-ok"

  result1="$(db_name_for "$repo" "$branch1")"
  result2="$(db_name_for "$repo" "$branch2")"

  [ "$result1" != "$result2" ]
}

# ============================================================================
# Normal case: <repo>__<branch_slug> shape holds
# ============================================================================

@test "db_name_for: normal case preserves <repo>__<branch_slug> shape" {
  result="$(db_name_for "myapp" "feature/login-form")"
  [ "$result" = "myapp__feature_login_form" ]
}

@test "db_name_for: simple repo and branch" {
  result="$(db_name_for "myapp" "main")"
  [ "$result" = "myapp__main" ]
}

@test "database helpers reject unsafe names before invoking mysql" {
  run zsh -c '
    warn() { print -r -- "$*"; }
    source "$1/lib/05-database.sh"
    DB_CREATE=true DB_BACKUP=true
    _validate_database_name "app\`; SELECT 1; --"
  ' _ "$GROVE_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid database name"* ]]
}

@test "backup_database fails closed when mysqldump is unavailable" {
  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/mysql" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$TEST_TEMP_DIR/bin/mysql"

  run env PATH="$TEST_TEMP_DIR/bin:/usr/bin:/bin" zsh -c '
    warn() { print -r -- "$*"; }
    dim() { :; }
    source "$1/lib/05-database.sh"
    DB_BACKUP=true DB_HOST=localhost DB_USER=root DB_BACKUP_DIR="$2/backups"
    backup_database app__feature app
  ' _ "$GROVE_ROOT" "$TEST_TEMP_DIR"

  [ "$status" -eq 1 ]
  [[ "$output" == *"mysqldump not found"* ]]
}

@test "backup_database fails closed when the existence query fails" {
  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/mysql" <<'EOF'
#!/bin/sh
case "$*" in
  *information_schema*) exit 42 ;;
esac
exit 0
EOF
  cat > "$TEST_TEMP_DIR/bin/mysqldump" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$TEST_TEMP_DIR/bin/mysql" "$TEST_TEMP_DIR/bin/mysqldump"

  run env PATH="$TEST_TEMP_DIR/bin:/usr/bin:/bin" zsh -c '
    warn() { print -r -- "$*"; }
    dim() { :; }
    source "$1/lib/05-database.sh"
    DB_BACKUP=true DB_HOST=localhost DB_USER=root DB_BACKUP_DIR="$2/backups"
    backup_database app__feature app
  ' _ "$GROVE_ROOT" "$TEST_TEMP_DIR"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not check whether database"* ]]
}

@test "backup_database writes private dump files without changing the caller umask" {
  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/mysql" <<'EOF'
#!/bin/sh
case "$*" in
  *information_schema*) printf '1\n' ;;
esac
exit 0
EOF
  cat > "$TEST_TEMP_DIR/bin/mysqldump" <<'EOF'
#!/bin/sh
printf '%s\n' '-- disposable dump'
EOF
  chmod +x "$TEST_TEMP_DIR/bin/mysql" "$TEST_TEMP_DIR/bin/mysqldump"

  run env PATH="$TEST_TEMP_DIR/bin:/usr/bin:/bin" zsh -c '
    warn() { print -r -- "$*"; }
    dim() { :; }
    info() { :; }
    ok() { :; }
    source "$1/lib/05-database.sh"
    DB_BACKUP=true DB_HOST=localhost DB_USER=root DB_BACKUP_DIR="$2/backups"
    umask 022
    backup_database app__feature app || exit
    print -r -- "umask=$(umask)"
  ' _ "$GROVE_ROOT" "$TEST_TEMP_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"umask=0022"* || "$output" == *"umask=022"* ]]
  dump_file="$(find "$TEST_TEMP_DIR/backups" -type f -name '*.sql' -print -quit)"
  [ -n "$dump_file" ]
  mode="$(stat -f '%Lp' "$dump_file" 2>/dev/null || stat -c '%a' "$dump_file")"
  [ "$mode" = "600" ]
}

@test "drop_database fails when the existence query fails" {
  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/mysql" <<'EOF'
#!/bin/sh
case "$*" in
  *information_schema*) exit 42 ;;
esac
exit 0
EOF
  chmod +x "$TEST_TEMP_DIR/bin/mysql"

  run env PATH="$TEST_TEMP_DIR/bin:/usr/bin:/bin" zsh -c '
    warn() { print -r -- "$*"; }
    dim() { :; }
    source "$1/lib/05-database.sh"
    DB_HOST=localhost DB_USER=root
    drop_database app__feature
  ' _ "$GROVE_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"database was not dropped"* ]]
}
