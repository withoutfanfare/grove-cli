#!/usr/bin/env bats
# navigation.bats - Integration tests for the real zsh navigation helpers.
#
# These exercise the ACTUAL zsh implementations (sourced via zsh against a real
# temp HERD_ROOT, .env, and aliases file), not bash reimplementations. They pin
# two behaviours introduced in lib/commands/navigation.sh:
#
#   1. worktree_url() resolves a worktree's URL from its .env APP_URL, cleaning
#      the value the SAME way lib/01-core.sh cleans config values, and falling
#      back to url_for() (which honours GROVE_URL_SUBDOMAIN) when APP_URL is
#      absent, empty, or not a well-formed http(s) URL. This unifies what were
#      two divergent inline blocks in cmd_open and cmd_switch.
#
#   2. An alias resolves to its repo before validation/lookup, so navigation
#      commands like `grove open <alias>` target the aliased repo. A real repo
#      of the same name always wins over an alias.
#
# Anything needing a live editor or browser (the actual open/xdg-open/$EDITOR
# launches in cmd_open/cmd_switch) is out of scope here and is exercised only
# at the URL-resolution layer.

load '../test-helper'

setup() {
  setup_test_environment

  # Build a sourceable zsh file: stub the cross-module output helpers that the
  # real functions reference, then append the real lib/03-paths.sh (url_for,
  # git_dir_for, site_name_for, slugify_*) plus the two functions under test
  # extracted from lib/commands/navigation.sh and resolve_alias from
  # lib/commands/config.sh. We deliberately source ONLY these so the test pins
  # the helpers we are exercising.
  NAV_FNS="$TEST_TEMP_DIR/nav-fns.zsh"
  export NAV_FNS

  export GROVE_ALIASES_FILE="$TEST_TEMP_DIR/aliases"

  cat > "$NAV_FNS" <<STUB
warn() { print -r -- "WARN: \$1" >&2; }
dim()  { :; }
error_exit() { print -r -- "ERR: \$2" >&2; return 1; }
JSON_OUTPUT=false
HERD_ROOT="$HERD_ROOT"
GROVE_ALIASES_FILE="$GROVE_ALIASES_FILE"
STUB

  cat "$GROVE_ROOT/lib/03-paths.sh" >> "$NAV_FNS"
  awk '/^resolve_alias\(\) \{/,/^\}/' "$GROVE_ROOT/lib/commands/config.sh" >> "$NAV_FNS"
  awk '/^worktree_url\(\) \{/,/^\}/' "$GROVE_ROOT/lib/commands/navigation.sh" >> "$NAV_FNS"
  awk '/^resolve_repo_arg\(\) \{/,/^\}/' "$GROVE_ROOT/lib/commands/navigation.sh" >> "$NAV_FNS"

  # A worktree directory whose .env we vary per test.
  WT="$TEST_TEMP_DIR/feature-login"
  export WT
  mkdir -p "$WT"
}

teardown() {
  teardown_test_environment
}

# Run a snippet against the sourced helpers in a clean zsh process.
# $1 - GROVE_URL_SUBDOMAIN value (may be empty)
# $2 - snippet to evaluate
run_zsh() {
  run zsh -c "source '$NAV_FNS'; GROVE_URL_SUBDOMAIN='$1'; $2"
}

# ============================================================================
# worktree_url — uses a valid .env APP_URL verbatim
# ============================================================================

@test "worktree_url: returns a valid .env APP_URL verbatim" {
  printf '%s\n' 'APP_URL=https://custom.test' > "$WT/.env"
  run_zsh "" "worktree_url myrepo feature/login '$WT'"
  [ "$status" -eq 0 ]
  [ "$output" = "https://custom.test" ]
}

@test "worktree_url: strips surrounding quotes from APP_URL" {
  printf '%s\n' 'APP_URL="https://quoted.test"' > "$WT/.env"
  run_zsh "" "worktree_url myrepo feature/login '$WT'"
  [ "$status" -eq 0 ]
  [ "$output" = "https://quoted.test" ]
}

@test "worktree_url: strips a trailing ' #...' comment on unquoted values" {
  printf '%s\n' 'APP_URL=https://withcomment.test # the app url' > "$WT/.env"
  run_zsh "" "worktree_url myrepo feature/login '$WT'"
  [ "$status" -eq 0 ]
  [ "$output" = "https://withcomment.test" ]
}

@test "worktree_url: preserves a bare mid-value '#' (URL fragment)" {
  printf '%s\n' 'APP_URL=https://frag.test/#/route' > "$WT/.env"
  run_zsh "" "worktree_url myrepo feature/login '$WT'"
  [ "$status" -eq 0 ]
  [ "$output" = "https://frag.test/#/route" ]
}

# ============================================================================
# worktree_url — falls back to url_for when APP_URL is unusable
# ============================================================================

@test "worktree_url: falls back to url_for when APP_URL is absent" {
  printf '%s\n' 'OTHER=foo' > "$WT/.env"
  run_zsh "" "worktree_url myrepo feature/login '$WT'"
  [ "$status" -eq 0 ]
  [ "$output" = "https://feature-login.test" ]
}

@test "worktree_url: fallback honours GROVE_URL_SUBDOMAIN" {
  printf '%s\n' 'OTHER=foo' > "$WT/.env"
  run_zsh "admin" "worktree_url myrepo feature/login '$WT'"
  [ "$status" -eq 0 ]
  [ "$output" = "https://admin.feature-login.test" ]
}

@test "worktree_url: falls back when there is no .env file" {
  rm -f "$WT/.env"
  run_zsh "" "worktree_url myrepo feature/login '$WT'"
  [ "$status" -eq 0 ]
  [ "$output" = "https://feature-login.test" ]
}

@test "worktree_url: rejects a non-http(s) APP_URL and falls back" {
  # Untrusted .env: a javascript: scheme must not be used.
  printf '%s\n' 'APP_URL=javascript:alert(1)' > "$WT/.env"
  run_zsh "" "worktree_url myrepo feature/login '$WT'"
  [ "$status" -eq 0 ]
  [ "$output" = "https://feature-login.test" ]
}

# ============================================================================
# resolve_repo_arg — alias resolution for navigation commands
# ============================================================================

@test "resolve_repo_arg: a real repo passes through unchanged" {
  mkdir -p "$HERD_ROOT/realrepo.git"
  run_zsh "" "resolve_repo_arg realrepo"
  [ "$status" -eq 0 ]
  [ "$output" = "realrepo" ]
}

@test "resolve_repo_arg: an alias resolves to its repo segment" {
  printf '%s\n' 'login=aliasedrepo/feature-login' > "$GROVE_ALIASES_FILE"
  run_zsh "" "resolve_repo_arg login"
  [ "$status" -eq 0 ]
  [ "$output" = "aliasedrepo" ]
}

@test "resolve_repo_arg: an unknown arg is returned verbatim" {
  run_zsh "" "resolve_repo_arg neither-repo-nor-alias"
  [ "$status" -eq 0 ]
  [ "$output" = "neither-repo-nor-alias" ]
}

@test "resolve_repo_arg: a real repo wins over an identically-named alias" {
  mkdir -p "$HERD_ROOT/shadowed.git"
  printf '%s\n' 'shadowed=otherrepo/feature-x' > "$GROVE_ALIASES_FILE"
  run_zsh "" "resolve_repo_arg shadowed"
  [ "$status" -eq 0 ]
  [ "$output" = "shadowed" ]
}
