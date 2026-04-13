#!/usr/bin/env bats
# slugify.bats - Tests for slugify_branch() and extract_feature_name() functions
#
# These functions transform branch names for filesystem and URL usage

load '../test-helper'

setup() {
  setup_test_environment
}

teardown() {
  teardown_test_environment
}

# ============================================================================
# slugify_branch() tests
# ============================================================================

@test "slugify_branch: simple name unchanged" {
  result="$(slugify_branch "main")"
  [ "$result" = "main" ]
}

@test "slugify_branch: replaces single slash with dash" {
  result="$(slugify_branch "feature/login")"
  [ "$result" = "feature-login" ]
}

@test "slugify_branch: replaces multiple slashes" {
  result="$(slugify_branch "feature/user/auth")"
  [ "$result" = "feature-user-auth" ]
}

@test "slugify_branch: preserves dashes" {
  result="$(slugify_branch "bugfix/fix-123")"
  [ "$result" = "bugfix-fix-123" ]
}

@test "slugify_branch: preserves underscores" {
  result="$(slugify_branch "feature/new_feature")"
  [ "$result" = "feature-new_feature" ]
}

@test "slugify_branch: preserves dots" {
  result="$(slugify_branch "release/v1.2.3")"
  [ "$result" = "release-v1.2.3" ]
}

@test "slugify_branch: handles deeply nested branches" {
  result="$(slugify_branch "feature/dh/uat/build-test")"
  [ "$result" = "feature-dh-uat-build-test" ]
}

@test "slugify_branch: handles leading slash (edge case)" {
  # This would be caught by validation, but test slugify behaviour
  result="$(slugify_branch "/feature/test")"
  [ "$result" = "-feature-test" ]
}

# ============================================================================
# extract_feature_name() tests
# ============================================================================

@test "extract_feature_name: simple name unchanged" {
  result="$(extract_feature_name "main")"
  [ "$result" = "main" ]
}

@test "extract_feature_name: extracts from feature branch" {
  result="$(extract_feature_name "feature/login")"
  [ "$result" = "login" ]
}

@test "extract_feature_name: extracts from bugfix branch" {
  result="$(extract_feature_name "bugfix/fix-123")"
  [ "$result" = "fix-123" ]
}

@test "extract_feature_name: extracts last segment from nested" {
  result="$(extract_feature_name "feature/dh/uat/build-test")"
  [ "$result" = "build-test" ]
}

@test "extract_feature_name: extracts from release branch" {
  result="$(extract_feature_name "release/v1.2.3")"
  [ "$result" = "v1.2.3" ]
}

@test "extract_feature_name: extracts from hotfix branch" {
  result="$(extract_feature_name "hotfix/critical-bug")"
  [ "$result" = "critical-bug" ]
}

@test "extract_feature_name: handles multiple levels" {
  result="$(extract_feature_name "team/user/feature/awesome")"
  [ "$result" = "awesome" ]
}

@test "extract_feature_name: handles name with dashes" {
  result="$(extract_feature_name "feature/my-awesome-feature")"
  [ "$result" = "my-awesome-feature" ]
}

@test "extract_feature_name: handles name with underscores" {
  result="$(extract_feature_name "feature/my_awesome_feature")"
  [ "$result" = "my_awesome_feature" ]
}

# ============================================================================
# Combined slugify + extract tests
# ============================================================================

@test "slugify then extract: feature branch" {
  slugified="$(slugify_branch "feature/sms-unsubscribe")"
  [ "$slugified" = "feature-sms-unsubscribe" ]

  extracted="$(extract_feature_name "feature/sms-unsubscribe")"
  [ "$extracted" = "sms-unsubscribe" ]
}

@test "slugify then extract: complex nested branch" {
  branch="feature/dh/campaigns/email-templates"

  slugified="$(slugify_branch "$branch")"
  [ "$slugified" = "feature-dh-campaigns-email-templates" ]

  extracted="$(extract_feature_name "$branch")"
  [ "$extracted" = "email-templates" ]
}
