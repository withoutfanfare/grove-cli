#!/usr/bin/env bats
# validation.bats - Tests for validate_name() function
#
# Security-critical tests for input validation that prevents:
# - Path traversal attacks
# - Git flag injection
# - Reserved reference exploitation

load '../test-helper'

setup() {
  setup_test_environment
}

teardown() {
  teardown_test_environment
}

# ============================================================================
# Valid names - should pass
# ============================================================================

@test "validate_name: accepts simple repo name" {
  run validate_name "myapp" "repository"
  [ "$status" -eq 0 ]
}

@test "validate_name: accepts repo name with dash" {
  run validate_name "my-app" "repository"
  [ "$status" -eq 0 ]
}

@test "validate_name: accepts repo name with underscore" {
  run validate_name "my_app" "repository"
  [ "$status" -eq 0 ]
}

@test "validate_name: accepts repo name with numbers" {
  run validate_name "app2" "repository"
  [ "$status" -eq 0 ]
}

@test "validate_name: accepts simple branch name" {
  run validate_name "main" "branch"
  [ "$status" -eq 0 ]
}

@test "validate_name: accepts feature branch with slash" {
  run validate_name "feature/login" "branch"
  [ "$status" -eq 0 ]
}

@test "validate_name: accepts nested feature branch" {
  run validate_name "feature/user/auth" "branch"
  [ "$status" -eq 0 ]
}

@test "validate_name: accepts branch with dots" {
  run validate_name "release/v1.2.3" "branch"
  [ "$status" -eq 0 ]
}

@test "validate_name: accepts bugfix branch" {
  run validate_name "bugfix/fix-123" "branch"
  [ "$status" -eq 0 ]
}

@test "validate_name: accepts deeply nested branch" {
  run validate_name "feature/dh/uat/build-test" "branch"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Path traversal - should fail
# ============================================================================

@test "validate_name: rejects absolute path" {
  run validate_name "/etc/passwd" "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"absolute paths not allowed"* ]]
}

@test "validate_name: rejects path starting with slash" {
  run validate_name "/myapp" "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"absolute paths not allowed"* ]]
}

@test "validate_name: rejects parent directory traversal" {
  run validate_name "../../../etc" "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"path traversal not allowed"* ]]
}

@test "validate_name: rejects double dot in path" {
  run validate_name "foo/../bar" "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"path traversal not allowed"* ]]
}

@test "validate_name: rejects hidden directory reference" {
  run validate_name "foo/.hidden" "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"path traversal not allowed"* ]]
}

@test "validate_name: rejects current directory reference" {
  run validate_name "foo/./bar" "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"path traversal not allowed"* ]]
}

# ============================================================================
# Git flag injection - should fail
# ============================================================================

@test "validate_name: rejects name starting with dash" {
  run validate_name "-f" "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot start with dash"* ]]
}

@test "validate_name: rejects --force flag injection" {
  run validate_name "--force" "branch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot start with dash"* ]]
}

@test "validate_name: rejects -D flag injection" {
  run validate_name "-D" "branch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot start with dash"* ]]
}

@test "validate_name: rejects --delete flag injection" {
  run validate_name "--delete" "branch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot start with dash"* ]]
}

# ============================================================================
# Reserved git references - should fail (branch only)
# ============================================================================

@test "validate_name: rejects HEAD as branch" {
  run validate_name "HEAD" "branch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reserved git reference"* ]]
}

@test "validate_name: rejects refs/ prefix as branch" {
  run validate_name "refs/heads/main" "branch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reserved git reference"* ]]
}

@test "validate_name: rejects @ as branch" {
  run validate_name "@" "branch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reserved git reference"* ]]
}

@test "validate_name: rejects @{upstream} as branch" {
  run validate_name "@{upstream}" "branch"
  [ "$status" -eq 1 ]
  # Either reserved or invalid chars
  [ "$status" -eq 1 ]
}

# Note: HEAD is allowed as a repo name (only restricted for branches)
@test "validate_name: allows HEAD as repo name" {
  run validate_name "HEAD" "repository"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Invalid characters - should fail
# ============================================================================

@test "validate_name: rejects spaces" {
  run validate_name "my app" "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"only alphanumeric"* ]]
}

@test "validate_name: rejects special characters" {
  run validate_name "my@app" "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"only alphanumeric"* ]]
}

@test "validate_name: rejects semicolon (command injection)" {
  run validate_name "foo;rm -rf /" "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"only alphanumeric"* ]]
}

@test "validate_name: rejects backticks (command substitution)" {
  run validate_name 'foo`whoami`' "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"only alphanumeric"* ]]
}

@test "validate_name: rejects dollar sign (variable expansion)" {
  run validate_name 'foo$HOME' "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"only alphanumeric"* ]]
}

@test "validate_name: rejects pipe (command piping)" {
  run validate_name "foo|cat /etc/passwd" "repository"
  [ "$status" -eq 1 ]
  [[ "$output" == *"only alphanumeric"* ]]
}

# ============================================================================
# Malformed paths - should fail
# ============================================================================

@test "validate_name: rejects double slashes" {
  run validate_name "feature//login" "branch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed path"* ]]
}

@test "validate_name: rejects trailing slash" {
  run validate_name "feature/login/" "branch"
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed path"* ]]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "validate_name: accepts single character name" {
  run validate_name "a" "repository"
  [ "$status" -eq 0 ]
}

@test "validate_name: accepts long name" {
  run validate_name "this-is-a-very-long-repository-name-that-should-still-be-valid" "repository"
  [ "$status" -eq 0 ]
}

@test "validate_name: accepts name starting with number" {
  run validate_name "123app" "repository"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Directory name validation (for grove move command)
# More restrictive than repo/branch names - no slashes allowed
# ============================================================================

@test "validate_directory_name: accepts simple name" {
  run validate_directory_name "my-new-directory"
  [ "$status" -eq 0 ]
}

@test "validate_directory_name: accepts name with underscore" {
  run validate_directory_name "my_directory"
  [ "$status" -eq 0 ]
}

@test "validate_directory_name: accepts name with numbers" {
  run validate_directory_name "directory123"
  [ "$status" -eq 0 ]
}

@test "validate_directory_name: rejects name starting with dash" {
  run validate_directory_name "-invalid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot start with dash"* ]]
}

@test "validate_directory_name: rejects --option flag" {
  run validate_directory_name "--delete"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot start with dash"* ]]
}

@test "validate_directory_name: rejects path traversal" {
  run validate_directory_name "../parent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"path traversal not allowed"* ]]
}

@test "validate_directory_name: rejects embedded path traversal" {
  run validate_directory_name "foo/../bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"path traversal not allowed"* ]]
}

@test "validate_directory_name: rejects slash in name" {
  run validate_directory_name "path/to/dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"slashes not allowed"* ]]
}

@test "validate_directory_name: rejects leading slash" {
  run validate_directory_name "/absolute"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot start with dash"* || "$output" == *"slashes not allowed"* ]]
}

@test "validate_directory_name: rejects empty name" {
  run validate_directory_name ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be empty"* ]]
}

@test "validate_directory_name: rejects whitespace-only name" {
  run validate_directory_name "   "
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be empty"* ]]
}

# ============================================================================
# validate_identifier_common tests
# ============================================================================

@test "validate_identifier_common: accepts valid input" {
  run validate_identifier_common "valid-name" "test type"
  [ "$status" -eq 0 ]
}

@test "validate_identifier_common: rejects empty input" {
  run validate_identifier_common "" "test type"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be empty"* ]]
}

@test "validate_identifier_common: rejects leading dash" {
  run validate_identifier_common "-flag" "test type"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot start with dash"* ]]
}

@test "validate_identifier_common: rejects path traversal" {
  run validate_identifier_common "foo/../bar" "test type"
  [ "$status" -eq 1 ]
  [[ "$output" == *"path traversal not allowed"* ]]
}
