#!/usr/bin/env bats
# commands.bats - Integration tests for grove commands
#
# These tests verify command-line parsing, help output, and validation
# without requiring a full git repository setup

load '../test-helper'

setup() {
  setup_test_environment

  # Export grove script path for testing
  export GROVE_SCRIPT="$GROVE_ROOT/grove"

  # Create templates directory with test templates
  mkdir -p "$TEST_TEMP_DIR/.grove/templates"

  cat > "$TEST_TEMP_DIR/.grove/templates/laravel.conf" << 'EOF'
TEMPLATE_DESC="Laravel full setup"
GROVE_SKIP_DB=false
GROVE_SKIP_COMPOSER=false
EOF

  cat > "$TEST_TEMP_DIR/.grove/templates/node.conf" << 'EOF'
TEMPLATE_DESC="Node.js only"
GROVE_SKIP_COMPOSER=true
GROVE_SKIP_DB=true
EOF

  cat > "$TEST_TEMP_DIR/.grove/templates/minimal.conf" << 'EOF'
TEMPLATE_DESC="Minimal setup"
GROVE_SKIP_DB=true
GROVE_SKIP_NPM=true
GROVE_SKIP_COMPOSER=true
GROVE_SKIP_BUILD=true
GROVE_SKIP_MIGRATE=true
GROVE_SKIP_HERD=true
EOF
}

teardown() {
  teardown_test_environment
}

# Helper to run grove with test environment
run_grove() {
  HERD_ROOT="$HERD_ROOT" \
  GROVE_HOOKS_DIR="$GROVE_HOOKS_DIR" \
  GROVE_TEMPLATES_DIR="$TEST_TEMP_DIR/.grove/templates" \
  NO_COLOR=1 \
  run zsh "$GROVE_SCRIPT" "$@"
}

# ============================================================================
# Help and version
# ============================================================================

@test "grove --help: shows usage information" {
  run_grove --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"CORE COMMANDS"* ]]
}

@test "grove --version: shows version number" {
  run_grove --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"grove version"* ]]
  [[ "$output" == *"4."* ]]
}

@test "grove help: shows usage (alternative syntax)" {
  run_grove help
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
}

@test "grove --help: lists available templates" {
  run_grove --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"AVAILABLE TEMPLATES"* ]]
  [[ "$output" == *"laravel"* ]]
  [[ "$output" == *"node"* ]]
  [[ "$output" == *"minimal"* ]]
}

@test "grove --help: shows new flags" {
  run_grove --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--pretty"* ]]
  [[ "$output" == *"--template"* ]]
}

@test "grove --help: lists summary command" {
  run_grove --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"summary"* ]]
}

# ============================================================================
# grove templates - Template management
# ============================================================================

@test "grove templates: lists available templates" {
  run_grove templates
  [ "$status" -eq 0 ]
  [[ "$output" == *"laravel"* ]]
  [[ "$output" == *"node"* ]]
  [[ "$output" == *"minimal"* ]]
}

@test "grove templates: shows template descriptions" {
  run_grove templates
  [ "$status" -eq 0 ]
  [[ "$output" == *"Laravel full setup"* ]]
  [[ "$output" == *"Node.js only"* ]]
}

@test "grove templates <name>: shows detailed template info" {
  run_grove templates laravel
  [ "$status" -eq 0 ]
  [[ "$output" == *"laravel"* ]]
  [[ "$output" == *"Laravel full setup"* ]]
}

@test "grove templates: handles nonexistent template" {
  run_grove templates nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"Template"* ]]
}

# ============================================================================
# Flag parsing
# ============================================================================

@test "flag parsing: unknown flag rejected" {
  run_grove --unknown-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown flag"* ]]
}

@test "flag parsing: -t requires argument" {
  run_grove add testrepo feature/test -t
  [ "$status" -ne 0 ]
  [[ "$output" == *"Template name required"* ]] || [[ "$output" == *"-t"* ]]
}

@test "flag parsing: --template= requires value" {
  run_grove add testrepo feature/test --template=
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

# ============================================================================
# Validation - error cases
# ============================================================================

@test "validation: rejects path traversal in repo name" {
  run_grove ls "../etc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"path traversal"* ]] || [[ "$output" == *"Invalid"* ]]
}

@test "validation: rejects absolute path in repo name" {
  run_grove ls "/etc/passwd"
  [ "$status" -ne 0 ]
  [[ "$output" == *"absolute"* ]] || [[ "$output" == *"Invalid"* ]]
}

@test "validation: rejects path with double dots" {
  run_grove add testrepo "feature/../../../etc" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"path traversal"* ]] || [[ "$output" == *"Invalid"* ]]
}

# ============================================================================
# Template validation (unit tests via test-helper validate_template_name)
# ============================================================================

@test "template validation: rejects path traversal" {
  run validate_template_name "../etc/passwd"
  [ "$status" -ne 0 ]
  [[ "$output" == *"path"* ]] || [[ "$output" == *"Invalid"* ]] || [[ "$output" == *"not allowed"* ]]
}

@test "template validation: rejects slashes in template name" {
  run validate_template_name "path/to/template"
  [ "$status" -ne 0 ]
  [[ "$output" == *"path"* ]] || [[ "$output" == *"Invalid"* ]] || [[ "$output" == *"not allowed"* ]]
}

@test "template validation: rejects special characters" {
  run validate_template_name 'test$(whoami)'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid"* ]] || [[ "$output" == *"only"* ]]
}

# ============================================================================
# grove doctor - System check
# ============================================================================

@test "grove doctor: runs and produces output" {
  run_grove doctor
  # doctor may return warnings (non-zero) but should produce output
  [[ "$output" == *"Checking"* ]] || [[ "$output" == *"System"* ]] || [[ "$output" == *"git"* ]]
}

@test "grove summary: errors with usage when missing args" {
  run_grove summary
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: grove summary"* ]]
}
