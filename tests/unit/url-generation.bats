#!/usr/bin/env bats
# url-generation.bats - Tests for url_for(), worktree_path_for(), and site_name_for()
#
# Tests URL, path, and site name generation for worktrees.
# These mirror the real implementations in lib/03-paths.sh.

load '../test-helper'

setup() {
  setup_test_environment
  # Reset subdomain for each test
  unset GROVE_URL_SUBDOMAIN
}

teardown() {
  teardown_test_environment
}

# ============================================================================
# site_name_for() tests
# ============================================================================

@test "site_name_for: main branch returns repo name" {
  result="$(site_name_for "myapp" "main")"
  [ "$result" = "myapp" ]
}

@test "site_name_for: staging branch returns repo name" {
  result="$(site_name_for "myapp" "staging")"
  [ "$result" = "myapp" ]
}

@test "site_name_for: master branch returns repo name" {
  result="$(site_name_for "myapp" "master")"
  [ "$result" = "myapp" ]
}

@test "site_name_for: feature branch uses full slugified branch" {
  result="$(site_name_for "myapp" "feature/login")"
  [ "$result" = "feature-login" ]
}

@test "site_name_for: nested branch uses full slugified branch" {
  result="$(site_name_for "myapp" "feature/user/auth")"
  [ "$result" = "feature-user-auth" ]
}

@test "site_name_for: deeply nested branch uses full slugified branch" {
  result="$(site_name_for "myapp" "feature/dh/uat/build-test")"
  [ "$result" = "feature-dh-uat-build-test" ]
}

@test "site_name_for: simple branch without slash returns branch name" {
  result="$(site_name_for "myapp" "develop")"
  [ "$result" = "develop" ]
}

@test "site_name_for: bugfix branch uses full slugified branch" {
  result="$(site_name_for "myapp" "bugfix/fix-login")"
  [ "$result" = "bugfix-fix-login" ]
}

@test "site_name_for: release branch with dots is slugified" {
  result="$(site_name_for "myapp" "release/v1.2.3")"
  [ "$result" = "release-v1-2-3" ]
}

# Distinct branches that share a final segment must not collide (#25)
@test "site_name_for: branches sharing a final segment do not collide" {
  alice="$(site_name_for "myapp" "alice/dashboard")"
  bob="$(site_name_for "myapp" "bob/dashboard")"
  [ "$alice" = "alice-dashboard" ]
  [ "$bob" = "bob-dashboard" ]
  [ "$alice" != "$bob" ]
}

# ============================================================================
# worktree_path_for() tests
# ============================================================================

@test "worktree_path_for: main branch uses repo name as site name" {
  result="$(worktree_path_for "myapp" "main")"
  [ "$result" = "$HERD_ROOT/myapp-worktrees/myapp" ]
}

@test "worktree_path_for: feature branch uses full slugified branch" {
  result="$(worktree_path_for "myapp" "feature/login")"
  [ "$result" = "$HERD_ROOT/myapp-worktrees/feature-login" ]
}

@test "worktree_path_for: nested branch uses full slugified branch" {
  result="$(worktree_path_for "myapp" "feature/user/auth")"
  [ "$result" = "$HERD_ROOT/myapp-worktrees/feature-user-auth" ]
}

@test "worktree_path_for: repo with dashes" {
  result="$(worktree_path_for "my-app" "main")"
  [ "$result" = "$HERD_ROOT/my-app-worktrees/my-app" ]
}

@test "worktree_path_for: uses HERD_ROOT from environment" {
  export HERD_ROOT="/custom/path"
  result="$(worktree_path_for "myapp" "main")"
  [ "$result" = "/custom/path/myapp-worktrees/myapp" ]
}

@test "worktree_path_for: staging branch" {
  result="$(worktree_path_for "myapp" "staging")"
  [ "$result" = "$HERD_ROOT/myapp-worktrees/myapp" ]
}

@test "worktree_path_for: simple non-main branch" {
  result="$(worktree_path_for "myapp" "develop")"
  [ "$result" = "$HERD_ROOT/myapp-worktrees/develop" ]
}

# ============================================================================
# grove_path_for() backward compatibility
# ============================================================================

@test "grove_path_for: aliases worktree_path_for" {
  result1="$(grove_path_for "myapp" "feature/login")"
  result2="$(worktree_path_for "myapp" "feature/login")"
  [ "$result1" = "$result2" ]
}

# ============================================================================
# url_for() tests - without subdomain
# ============================================================================

@test "url_for: main branch uses repo name" {
  result="$(url_for "myapp" "main")"
  [ "$result" = "https://myapp.test" ]
}

@test "url_for: feature branch uses full slugified branch" {
  result="$(url_for "myapp" "feature/login")"
  [ "$result" = "https://feature-login.test" ]
}

@test "url_for: nested branch uses full slugified branch" {
  result="$(url_for "myapp" "feature/user/auth")"
  [ "$result" = "https://feature-user-auth.test" ]
}

@test "url_for: uses https" {
  result="$(url_for "myapp" "main")"
  [[ "$result" == "https://"* ]]
}

@test "url_for: ends with .test" {
  result="$(url_for "myapp" "main")"
  [[ "$result" == *".test" ]]
}

@test "url_for: repo with dashes preserved in main branch" {
  result="$(url_for "my-app" "main")"
  [ "$result" = "https://my-app.test" ]
}

@test "url_for: simple non-main branch" {
  result="$(url_for "myapp" "develop")"
  [ "$result" = "https://develop.test" ]
}

# ============================================================================
# Hostname length budget (subdomain + .test must fit Herd's limit)
# ============================================================================

@test "site_name_for: short branch with subdomain is not truncated" {
  export GROVE_URL_SUBDOMAIN="charity-meals"
  result="$(site_name_for "scooda" "scooda-1799")"
  [ "$result" = "scooda-1799" ]
}

@test "url_for: long branch with subdomain keeps full hostname within budget" {
  export GROVE_URL_SUBDOMAIN="charity-meals"
  url="$(url_for "scooda" "danielharding/scooda-1799-some-very-long-descriptive-branch-name")"
  host="${url#https://}"
  # Full hostname must stay safely under Herd's ~60-char limit (buffer included).
  [ "${#host}" -le 56 ]
}

@test "site_name_for: long branch with subdomain still ends in uniqueness hash" {
  export GROVE_URL_SUBDOMAIN="charity-meals"
  result="$(site_name_for "scooda" "danielharding/scooda-1799-some-very-long-descriptive-branch-name")"
  [[ "$result" =~ -[0-9a-f]{6}$ ]]
}

@test "site_name_for: tighter budget when subdomain is set than when not" {
  branch="feature/a-fairly-long-branch-name-that-exceeds-the-tighter-budget-easily"
  without="$(site_name_for "myapp" "$branch")"
  export GROVE_URL_SUBDOMAIN="charity-meals"
  with="$(site_name_for "myapp" "$branch")"
  # The subdomain eats into the label budget, so the label must be shorter.
  [ "${#with}" -lt "${#without}" ]
}

@test "folder name and url label match for a long subdomain branch" {
  export GROVE_URL_SUBDOMAIN="charity-meals"
  branch="danielharding/scooda-1799-some-very-long-descriptive-branch-name"
  path="$(worktree_path_for "scooda" "$branch")"
  url="$(url_for "scooda" "$branch")"
  path_site="${path##*/}"
  url_site="${url#https://charity-meals.}"
  url_site="${url_site%.test}"
  [ "$path_site" = "$url_site" ]
}

# ============================================================================
# url_for() tests - with subdomain
# ============================================================================

@test "url_for: with subdomain prefix" {
  export GROVE_URL_SUBDOMAIN="api"
  result="$(url_for "myapp" "main")"
  [ "$result" = "https://api.myapp.test" ]
}

@test "url_for: subdomain with feature branch" {
  export GROVE_URL_SUBDOMAIN="api"
  result="$(url_for "myapp" "feature/login")"
  [ "$result" = "https://api.feature-login.test" ]
}

@test "url_for: empty subdomain produces no prefix" {
  export GROVE_URL_SUBDOMAIN=""
  result="$(url_for "myapp" "main")"
  [ "$result" = "https://myapp.test" ]
}

@test "url_for: subdomain appears before site name" {
  export GROVE_URL_SUBDOMAIN="admin"
  result="$(url_for "myapp" "main")"
  # Format: https://subdomain.site-name.test
  [[ "$result" == "https://admin."* ]]
}

# ============================================================================
# Path and URL consistency
# ============================================================================

@test "path and url use same site name" {
  repo="myapp"
  branch="feature/login"

  path="$(worktree_path_for "$repo" "$branch")"
  url="$(url_for "$repo" "$branch")"

  # Extract site name from path (after last /)
  path_site="${path##*/}"

  # Extract site name from URL (between // and .test)
  url_site="${url#https://}"
  url_site="${url_site%.test}"

  # They should match (path uses directory, URL uses hostname)
  [ "$path_site" = "$url_site" ]
}

@test "path and url consistent for complex branch" {
  repo="scooda"
  branch="feature/dh/uat/build-test"

  path="$(worktree_path_for "$repo" "$branch")"
  url="$(url_for "$repo" "$branch")"

  # Both should use the full slugified branch
  [[ "$path" == *"/feature-dh-uat-build-test" ]]
  [[ "$url" == *"feature-dh-uat-build-test.test" ]]
}

@test "path and url consistent for main branch" {
  repo="myapp"
  branch="main"

  path="$(worktree_path_for "$repo" "$branch")"
  url="$(url_for "$repo" "$branch")"

  # Both should use repo name for main branches
  [[ "$path" == *"/myapp" ]]
  [ "$url" = "https://myapp.test" ]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "worktree_path_for: single char names" {
  result="$(worktree_path_for "a" "b")"
  [ "$result" = "$HERD_ROOT/a-worktrees/b" ]
}

@test "url_for: single char names" {
  result="$(url_for "a" "b")"
  [ "$result" = "https://b.test" ]
}

@test "worktree_path_for: branch with dots is slugified" {
  result="$(worktree_path_for "myapp" "release/v1.2.3")"
  [ "$result" = "$HERD_ROOT/myapp-worktrees/release-v1-2-3" ]
}

@test "url_for: branch with dots is slugified" {
  result="$(url_for "myapp" "release/v1.2.3")"
  [ "$result" = "https://release-v1-2-3.test" ]
}

@test "worktree_path_for: branch with slash gets full slugified branch" {
  result="$(worktree_path_for "myapp" "feature/my-great-feature")"
  [ "$result" = "$HERD_ROOT/myapp-worktrees/feature-my-great-feature" ]
}

@test "url_for: bugfix branch uses full slugified branch" {
  result="$(url_for "myapp" "bugfix/fix-auth")"
  [ "$result" = "https://bugfix-fix-auth.test" ]
}
