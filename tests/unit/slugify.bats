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

@test "slugify_branch: underscores become dashes" {
  result="$(slugify_branch "feature/new_feature")"
  [ "$result" = "feature-new-feature" ]
}

@test "slugify_branch: dots become dashes" {
  result="$(slugify_branch "hotfix/v2.0")"
  [ "$result" = "hotfix-v2-0" ]
}

@test "slugify_branch: handles deeply nested branches" {
  result="$(slugify_branch "feature/dh/uat/build-test")"
  [ "$result" = "feature-dh-uat-build-test" ]
}

@test "slugify_branch: trims leading separator (edge case)" {
  # This would be caught by validation, but test slugify behaviour: a leading
  # separator run collapses to a single dash and is then trimmed.
  result="$(slugify_branch "/feature/test")"
  [ "$result" = "feature-test" ]
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

# ============================================================================
# Real zsh slugify_branch / site_name_for (lib/03-paths.sh)
#
# These exercise the ACTUAL zsh implementation (which sets REPLY rather than
# echoing, and now lowercases + replaces every non-[a-z0-9] run with a single
# dash) — not the bash mirror in test-helper. Pattern mirrors env-rewrite.bats.
# ============================================================================

# Print the REPLY set by the real zsh slugify_branch for $1.
_real_slug() {
  zsh -c '
    source "'"$GROVE_ROOT"'/lib/03-paths.sh"
    slugify_branch "$1"
    print -r -- "$REPLY"
  ' _ "$1"
}

# Print the real zsh site_name_for $1=repo $2=branch.
_real_site_name() {
  zsh -c '
    source "'"$GROVE_ROOT"'/lib/03-paths.sh"
    site_name_for "$1" "$2"
  ' _ "$1" "$2"
}

@test "slugify_branch(real): release/v1.2.3 -> release-v1-2-3" {
  run _real_slug "release/v1.2.3"
  [ "$status" -eq 0 ]
  [ "$output" = "release-v1-2-3" ]
}

@test "slugify_branch(real): Feature/Login_Form -> feature-login-form" {
  run _real_slug "Feature/Login_Form"
  [ "$status" -eq 0 ]
  [ "$output" = "feature-login-form" ]
}

@test "slugify_branch(real): spaces become single dashes" {
  run _real_slug "hello world"
  [ "$status" -eq 0 ]
  [ "$output" = "hello-world" ]
}

@test "slugify_branch(real): unicode chars are stripped to dashes" {
  run _real_slug "café/münch"
  [ "$status" -eq 0 ]
  # Non-[a-z0-9] runs (including the accented chars) collapse to single dashes
  [ "$output" = "caf-m-nch" ]
}

@test "slugify_branch(real): leading/trailing separators trimmed" {
  run _real_slug "--lead--trail--"
  [ "$status" -eq 0 ]
  [ "$output" = "lead-trail" ]
}

@test "slugify_branch(real): simple name lowercased, unchanged otherwise" {
  run _real_slug "Main"
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
}

# --- site_name_for collision avoidance (#25) ---

@test "site_name_for(real): alice/dashboard and bob/dashboard do not collide" {
  run _real_site_name "myrepo" "alice/dashboard"
  [ "$status" -eq 0 ]
  alice="$output"

  run _real_site_name "myrepo" "bob/dashboard"
  [ "$status" -eq 0 ]
  bob="$output"

  [ "$alice" = "alice-dashboard" ]
  [ "$bob" = "bob-dashboard" ]
  [ "$alice" != "$bob" ]
}

@test "site_name_for(real): main branch uses repo name" {
  run _real_site_name "myrepo" "main"
  [ "$status" -eq 0 ]
  [ "$output" = "myrepo" ]
}

@test "site_name_for(real): all-separator branch gets deterministic fallback" {
  run _real_site_name "myrepo" "---"
  [ "$status" -eq 0 ]
  # Must never be empty (would yield https://.test) — deterministic wt-<hash>
  [ -n "$output" ]
  [[ "$output" == wt-* ]]
}
