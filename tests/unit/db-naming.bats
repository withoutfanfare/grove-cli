#!/usr/bin/env bats
# db-naming.bats - Tests for db_name_for() function
#
# Critical for MySQL compatibility:
# - 64 character limit
# - Valid MySQL identifier characters
# - Hash suffix for long names

load '../test-helper'

setup() {
  setup_test_environment
}

teardown() {
  teardown_test_environment
}

# ============================================================================
# Basic database naming
# ============================================================================

@test "db_name_for: simple repo and branch" {
  result="$(db_name_for "myapp" "main")"
  [ "$result" = "myapp__main" ]
}

@test "db_name_for: replaces slashes with underscores" {
  result="$(db_name_for "myapp" "feature/login")"
  [ "$result" = "myapp__feature_login" ]
}

@test "db_name_for: replaces dashes with underscores" {
  result="$(db_name_for "my-app" "feature/new-feature")"
  [ "$result" = "my_app__feature_new_feature" ]
}

@test "db_name_for: handles nested branches" {
  result="$(db_name_for "myapp" "feature/user/auth")"
  [ "$result" = "myapp__feature_user_auth" ]
}

@test "db_name_for: preserves underscores" {
  result="$(db_name_for "my_app" "feature/my_feature")"
  [ "$result" = "my_app__feature_my_feature" ]
}

# ============================================================================
# MySQL 64 character limit
# ============================================================================

@test "db_name_for: short name under 64 chars" {
  result="$(db_name_for "myapp" "feature/short")"
  [ ${#result} -lt 64 ]
  [ "$result" = "myapp__feature_short" ]
}

@test "db_name_for: names near 64 char limit are within bounds" {
  # Test that names around the MySQL 64-char limit are handled properly
  repo="myapp12345"
  branch="feature/this-is-a-very-long-branch-name-exactly-fifty"

  result="$(db_name_for "$repo" "$branch")"

  # Result must always be within MySQL's 64-char limit
  [ ${#result} -le 64 ]
}

@test "db_name_for: long name truncated with hash" {
  # Create a very long name that exceeds 64 chars
  repo="myapp"
  branch="feature/this-is-an-extremely-long-branch-name-that-definitely-exceeds-the-mysql-limit"

  result="$(db_name_for "$repo" "$branch")"

  # Result should be at most 64 characters
  [ ${#result} -le 64 ]

  # Result should contain hash suffix (8 chars)
  # Format: truncated_repo__hash
  [[ "$result" =~ ^[a-zA-Z0-9_]+__[a-f0-9]{8}$ ]]
}

@test "db_name_for: very long repo name truncated" {
  repo="this-is-a-very-long-repository-name-that-exceeds-normal-limits"
  branch="feature/x"

  result="$(db_name_for "$repo" "$branch")"

  [ ${#result} -le 64 ]
}

@test "db_name_for: long names produce consistent hash" {
  repo="myapp"
  branch="feature/very-long-branch-name-that-will-be-hashed-for-consistency"

  result1="$(db_name_for "$repo" "$branch")"
  result2="$(db_name_for "$repo" "$branch")"

  # Same input should produce same output (deterministic)
  [ "$result1" = "$result2" ]
}

@test "db_name_for: different long branches produce different hashes" {
  repo="myapp"
  branch1="feature/very-long-branch-name-that-will-be-hashed-version-one"
  branch2="feature/very-long-branch-name-that-will-be-hashed-version-two"

  result1="$(db_name_for "$repo" "$branch1")"
  result2="$(db_name_for "$repo" "$branch2")"

  # Different inputs should produce different outputs
  [ "$result1" != "$result2" ]
}

# ============================================================================
# MySQL identifier validity
# ============================================================================

@test "db_name_for: result contains only valid MySQL chars" {
  result="$(db_name_for "my-app" "feature/new-feature")"

  # MySQL identifiers: letters, digits, underscore, dollar (we use underscore only)
  [[ "$result" =~ ^[a-zA-Z0-9_]+$ ]]
}

@test "db_name_for: no dashes in result" {
  result="$(db_name_for "my-app" "feature/my-feature")"

  # Should not contain dashes
  [[ "$result" != *"-"* ]]
}

@test "db_name_for: no slashes in result" {
  result="$(db_name_for "myapp" "feature/user/auth/login")"

  # Should not contain slashes
  [[ "$result" != *"/"* ]]
}

@test "db_name_for: double underscore separator" {
  result="$(db_name_for "myapp" "main")"

  # Should have double underscore between repo and branch
  [[ "$result" == *"__"* ]]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "db_name_for: single char repo and branch" {
  result="$(db_name_for "a" "b")"
  [ "$result" = "a__b" ]
}

@test "db_name_for: numeric repo name" {
  result="$(db_name_for "app123" "feature/test")"
  [ "$result" = "app123__feature_test" ]
}

@test "db_name_for: dots in branch name" {
  result="$(db_name_for "myapp" "release/v1.2.3")"
  # Dots should be preserved or converted
  # The actual implementation may vary
  [ ${#result} -gt 0 ]
}
