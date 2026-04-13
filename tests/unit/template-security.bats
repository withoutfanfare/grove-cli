#!/usr/bin/env bats
# template-security.bats - Security tests for template loading and validation
#
# Tests for path traversal prevention, template name validation, and
# template variable injection prevention.

load '../test-helper'

setup() {
  setup_test_environment

  # Create templates directory
  export GROVE_TEMPLATES_DIR="$TEST_TEMP_DIR/.grove/templates"
  mkdir -p "$GROVE_TEMPLATES_DIR"

  # Create a valid test template
  cat > "$GROVE_TEMPLATES_DIR/valid.conf" << 'EOF'
TEMPLATE_DESC="Valid test template"
GROVE_SKIP_DB=true
GROVE_SKIP_NPM=false
EOF
}

teardown() {
  teardown_test_environment
}

# ============================================================================
# Template name validation - valid names
# ============================================================================

@test "validate_template_name: accepts simple alphanumeric name" {
  run validate_template_name "laravel"
  [ "$status" -eq 0 ]
}

@test "validate_template_name: accepts name with dashes" {
  run validate_template_name "my-template"
  [ "$status" -eq 0 ]
}

@test "validate_template_name: accepts name with underscores" {
  run validate_template_name "my_template"
  [ "$status" -eq 0 ]
}

@test "validate_template_name: accepts mixed alphanumeric" {
  run validate_template_name "template123"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Template name validation - path traversal attacks
# ============================================================================

@test "validate_template_name: rejects path traversal with .." {
  run validate_template_name "../etc/passwd"
  [ "$status" -eq 1 ]
  [[ "$output" == *"path traversal"* ]]
}

@test "validate_template_name: rejects double dot anywhere" {
  run validate_template_name "foo..bar"
  [ "$status" -eq 1 ]
}

@test "validate_template_name: rejects forward slashes" {
  run validate_template_name "path/to/template"
  [ "$status" -eq 1 ]
  [[ "$output" == *"path traversal"* ]]
}

@test "validate_template_name: rejects backslashes" {
  run validate_template_name 'path\to\template'
  [ "$status" -eq 1 ]
  [[ "$output" == *"path traversal"* ]]
}

@test "validate_template_name: rejects absolute path" {
  run validate_template_name "/etc/passwd"
  [ "$status" -eq 1 ]
}

@test "validate_template_name: rejects deeply nested traversal" {
  run validate_template_name "../../../../../../etc/shadow"
  [ "$status" -eq 1 ]
}

# ============================================================================
# Template name validation - empty and whitespace
# ============================================================================

@test "validate_template_name: rejects empty string" {
  run validate_template_name ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty"* ]]
}

@test "validate_template_name: rejects only spaces" {
  run validate_template_name "   "
  [ "$status" -eq 1 ]
}

@test "validate_template_name: rejects only tabs" {
  run validate_template_name "	"
  [ "$status" -eq 1 ]
}

# ============================================================================
# Template name validation - special characters
# ============================================================================

@test "validate_template_name: rejects shell metacharacters $" {
  run validate_template_name 'test$(whoami)'
  [ "$status" -eq 1 ]
}

@test "validate_template_name: rejects backticks" {
  run validate_template_name 'test`id`'
  [ "$status" -eq 1 ]
}

@test "validate_template_name: rejects semicolons" {
  run validate_template_name "test;ls"
  [ "$status" -eq 1 ]
}

@test "validate_template_name: rejects pipes" {
  run validate_template_name "test|cat"
  [ "$status" -eq 1 ]
}

@test "validate_template_name: rejects ampersands" {
  run validate_template_name "test&&id"
  [ "$status" -eq 1 ]
}

@test "validate_template_name: rejects angle brackets" {
  run validate_template_name "test<file"
  [ "$status" -eq 1 ]
}

@test "validate_template_name: rejects spaces in name" {
  run validate_template_name "my template"
  [ "$status" -eq 1 ]
}

# ============================================================================
# Template variable value validation
# ============================================================================

@test "template variables: only accepts true for GROVE_SKIP_*" {
  cat > "$GROVE_TEMPLATES_DIR/test-true.conf" << 'EOF'
GROVE_SKIP_DB=true
EOF
  # This should not cause an error when loaded
  run load_template "test-true"
  [ "$status" -eq 0 ]
}

@test "template variables: only accepts false for GROVE_SKIP_*" {
  cat > "$GROVE_TEMPLATES_DIR/test-false.conf" << 'EOF'
GROVE_SKIP_NPM=false
EOF
  run load_template "test-false"
  [ "$status" -eq 0 ]
}

@test "template variables: rejects command injection in value" {
  cat > "$GROVE_TEMPLATES_DIR/test-injection.conf" << 'EOF'
GROVE_SKIP_DB=$(whoami)
EOF
  run load_template "test-injection"
  # Should warn about invalid value but not crash
  [[ "$output" == *"Invalid value"* || "$output" == *"must be true or false"* ]]
}

@test "template variables: rejects arbitrary strings" {
  cat > "$GROVE_TEMPLATES_DIR/test-string.conf" << 'EOF'
GROVE_SKIP_DB=yes
EOF
  run load_template "test-string"
  [[ "$output" == *"Invalid value"* || "$output" == *"must be true or false"* ]]
}

@test "template variables: rejects numeric values" {
  cat > "$GROVE_TEMPLATES_DIR/test-number.conf" << 'EOF'
GROVE_SKIP_DB=1
EOF
  run load_template "test-number"
  [[ "$output" == *"Invalid value"* || "$output" == *"must be true or false"* ]]
}

# ============================================================================
# Template file security
# ============================================================================

@test "template loading: fails for non-existent template" {
  run load_template "nonexistent"
  [ "$status" -eq 1 ]
}

@test "template loading: ignores comment lines" {
  cat > "$GROVE_TEMPLATES_DIR/with-comments.conf" << 'EOF'
# This is a comment
TEMPLATE_DESC="Test"
# Another comment
GROVE_SKIP_DB=true
EOF
  run load_template "with-comments"
  [ "$status" -eq 0 ]
}

@test "template loading: ignores empty lines" {
  cat > "$GROVE_TEMPLATES_DIR/with-blanks.conf" << 'EOF'
TEMPLATE_DESC="Test"

GROVE_SKIP_DB=true

EOF
  run load_template "with-blanks"
  [ "$status" -eq 0 ]
}
