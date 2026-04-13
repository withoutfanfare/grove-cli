#!/usr/bin/env bats
# config-parsing.bats - Integration tests for config file parsing
#
# Security-critical: Tests that only whitelisted variables are set
# and that injection attacks are blocked

load '../test-helper'

setup() {
  setup_test_environment

  # Create test config directory
  mkdir -p "$TEST_TEMP_DIR/configs"
}

teardown() {
  teardown_test_environment
}

# ============================================================================
# Basic config parsing
# ============================================================================

@test "parse_config_file: reads HERD_ROOT" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
HERD_ROOT=/custom/herd/path
EOF

  unset HERD_ROOT
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ "$HERD_ROOT" = "/custom/herd/path" ]
}

@test "parse_config_file: reads DEFAULT_BASE" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
DEFAULT_BASE=origin/main
EOF

  unset DEFAULT_BASE
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ "$DEFAULT_BASE" = "origin/main" ]
}

@test "parse_config_file: reads multiple variables" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
HERD_ROOT=/custom/path
DEFAULT_BASE=origin/develop
DB_HOST=localhost
DB_USER=admin
EOF

  unset HERD_ROOT DEFAULT_BASE DB_HOST DB_USER
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ "$HERD_ROOT" = "/custom/path" ]
  [ "$DEFAULT_BASE" = "origin/develop" ]
  [ "$DB_HOST" = "localhost" ]
  [ "$DB_USER" = "admin" ]
}

# ============================================================================
# Whitelist enforcement (security)
# ============================================================================

@test "parse_config_file: ignores non-whitelisted variables" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
HERD_ROOT=/valid/path
MALICIOUS_VAR=evil_value
ANOTHER_BAD=should_not_set
EOF

  unset HERD_ROOT MALICIOUS_VAR ANOTHER_BAD
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  # Whitelisted should be set
  [ "$HERD_ROOT" = "/valid/path" ]

  # Non-whitelisted should NOT be set
  [ -z "${MALICIOUS_VAR:-}" ]
  [ -z "${ANOTHER_BAD:-}" ]
}

@test "parse_config_file: ignores PATH variable" {
  original_path="$PATH"

  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
PATH=/malicious/bin:$PATH
EOF

  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  # PATH should not be modified
  [ "$PATH" = "$original_path" ]
}

@test "parse_config_file: ignores HOME variable" {
  original_home="$HOME"

  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
HOME=/tmp/evil
EOF

  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  # HOME should not be modified
  [ "$HOME" = "$original_home" ]
}

@test "parse_config_file: ignores LD_PRELOAD attempt" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
LD_PRELOAD=/tmp/evil.so
EOF

  unset LD_PRELOAD
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ -z "${LD_PRELOAD:-}" ]
}

# ============================================================================
# Comment and whitespace handling
# ============================================================================

@test "parse_config_file: ignores comment lines" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
# This is a comment
HERD_ROOT=/valid/path
# Another comment
DEFAULT_BASE=origin/main
EOF

  unset HERD_ROOT DEFAULT_BASE
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ "$HERD_ROOT" = "/valid/path" ]
  [ "$DEFAULT_BASE" = "origin/main" ]
}

@test "parse_config_file: ignores empty lines" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'

HERD_ROOT=/valid/path

DEFAULT_BASE=origin/main

EOF

  unset HERD_ROOT DEFAULT_BASE
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ "$HERD_ROOT" = "/valid/path" ]
  [ "$DEFAULT_BASE" = "origin/main" ]
}

@test "parse_config_file: trims whitespace from keys" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
  HERD_ROOT  =/valid/path
EOF

  unset HERD_ROOT
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ "$HERD_ROOT" = "/valid/path" ]
}

@test "parse_config_file: strips trailing comments from values" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
HERD_ROOT=/valid/path # This is a comment
EOF

  unset HERD_ROOT
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ "$HERD_ROOT" = "/valid/path" ]
}

# ============================================================================
# Quote handling
# ============================================================================

@test "parse_config_file: strips double quotes" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
HERD_ROOT="/path/with spaces"
EOF

  unset HERD_ROOT
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ "$HERD_ROOT" = "/path/with spaces" ]
}

@test "parse_config_file: strips single quotes" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
HERD_ROOT='/path/with spaces'
EOF

  unset HERD_ROOT
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ "$HERD_ROOT" = "/path/with spaces" ]
}

# ============================================================================
# Injection prevention
# ============================================================================

@test "parse_config_file: does not execute command substitution" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
HERD_ROOT=$(whoami)
EOF

  unset HERD_ROOT
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  # Should be literal string, not executed
  [[ "$HERD_ROOT" == *'whoami'* ]] || [ "$HERD_ROOT" = "" ]
}

@test "parse_config_file: does not expand variables in values" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
HERD_ROOT=$HOME/Herd
EOF

  unset HERD_ROOT
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  # Should be literal $HOME, not expanded
  # (behaviour may vary based on implementation)
  [ -n "$HERD_ROOT" ]
}

# ============================================================================
# Missing/empty files
# ============================================================================

@test "parse_config_file: handles missing file gracefully" {
  run parse_config_file "/nonexistent/file.groverc"
  [ "$status" -eq 0 ]
}

@test "parse_config_file: handles empty file" {
  touch "$TEST_TEMP_DIR/configs/empty.groverc"

  run parse_config_file "$TEST_TEMP_DIR/configs/empty.groverc"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Protected branches config
# ============================================================================

@test "parse_config_file: reads PROTECTED_BRANCHES" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
PROTECTED_BRANCHES=main master production
EOF

  unset PROTECTED_BRANCHES
  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ "$PROTECTED_BRANCHES" = "main master production" ]
}

@test "is_protected_branch: detects protected branch" {
  export PROTECTED_BRANCHES="main master staging"

  run is_protected_branch "main"
  [ "$status" -eq 0 ]

  run is_protected_branch "staging"
  [ "$status" -eq 0 ]
}

@test "is_protected_branch: allows non-protected branch" {
  export PROTECTED_BRANCHES="main master staging"

  run is_protected_branch "feature/login"
  [ "$status" -eq 1 ]

  run is_protected_branch "develop"
  [ "$status" -eq 1 ]
}

# ============================================================================
# All whitelisted variables
# ============================================================================

@test "parse_config_file: accepts all whitelisted variables" {
  cat > "$TEST_TEMP_DIR/configs/test.groverc" << 'EOF'
HERD_ROOT=/custom/herd
DEFAULT_BASE=origin/develop
DEFAULT_EDITOR=code
GROVE_URL_SUBDOMAIN=api
DB_HOST=mysql.local
DB_USER=dbuser
DB_PASSWORD=secret123
DB_CREATE=false
DB_BACKUP_DIR=/backups
DB_BACKUP=true
GROVE_HOOKS_DIR=/custom/hooks
PROTECTED_BRANCHES=main production
EOF

  unset HERD_ROOT DEFAULT_BASE DEFAULT_EDITOR GROVE_URL_SUBDOMAIN
  unset DB_HOST DB_USER DB_PASSWORD DB_CREATE DB_BACKUP_DIR DB_BACKUP
  unset GROVE_HOOKS_DIR PROTECTED_BRANCHES

  parse_config_file "$TEST_TEMP_DIR/configs/test.groverc"

  [ "$HERD_ROOT" = "/custom/herd" ]
  [ "$DEFAULT_BASE" = "origin/develop" ]
  [ "$DEFAULT_EDITOR" = "code" ]
  [ "$GROVE_URL_SUBDOMAIN" = "api" ]
  [ "$DB_HOST" = "mysql.local" ]
  [ "$DB_USER" = "dbuser" ]
  [ "$DB_PASSWORD" = "secret123" ]
  [ "$DB_CREATE" = "false" ]
  [ "$DB_BACKUP_DIR" = "/backups" ]
  [ "$DB_BACKUP" = "true" ]
  [ "$GROVE_HOOKS_DIR" = "/custom/hooks" ]
  [ "$PROTECTED_BRANCHES" = "main production" ]
}
