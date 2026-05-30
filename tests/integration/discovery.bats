#!/usr/bin/env bats
# discovery.bats - Integration tests for lib/commands/discovery.sh
#
# Exercises the real zsh implementations of `grove clean` and `grove recent`
# end-to-end against temp bare repos + worktrees. Guards three behaviours:
#   1. Bare `grove clean` (no repo) requires confirmation before deleting, and
#      proceeds non-interactively under --force (#31 safety rail).
#   2. `grove recent --limit <non-numeric>` does not abort (limit validation).
#   3. `grove recent --json` emits valid JSON whose `url` is resolved per-entry
#      from each repo's own config (not the last-loaded repo's subdomain).

load '../test-helper'

setup() {
  setup_test_environment

  export GROVE_SCRIPT="$GROVE_ROOT/grove"
  # Neutralise any real ~/.groverc / global state so tests are hermetic.
  export GROVE_CONFIG="$TEST_TEMP_DIR/no-such-groverc"
  unset GROVE_URL_SUBDOMAIN
}

teardown() {
  teardown_test_environment
}

# Run grove with the test environment (real zsh, full script).
run_grove() {
  HERD_ROOT="$HERD_ROOT" \
  GROVE_HOOKS_DIR="$GROVE_HOOKS_DIR" \
  GROVE_CONFIG="$GROVE_CONFIG" \
  NO_COLOR=1 \
  run zsh "$GROVE_SCRIPT" "$@"
}

# Create a bare repo at $HERD_ROOT/<repo>.git plus one worktree.
#
# Args: $1 = repo name, $2 = branch, $3 = worktree dir name (under HERD_ROOT),
#       $4 = "old" to backdate the commit (>30d) and add a node_modules dir.
make_repo_worktree() {
  local repo="$1" branch="$2" wt_dir="$3" age="${4:-new}"
  local bare="$HERD_ROOT/${repo}.git"
  local wt="$HERD_ROOT/$wt_dir"
  local seed="$TEST_TEMP_DIR/seed-$repo"

  # Seed a normal repo, then push into a bare repo so worktrees can be added.
  git init -q -b main "$seed"
  git -C "$seed" config user.email t@t.t
  git -C "$seed" config user.name 'Test'
  if [[ "$age" == "old" ]]; then
    GIT_AUTHOR_DATE="2000-01-01T00:00:00" GIT_COMMITTER_DATE="2000-01-01T00:00:00" \
      git -C "$seed" commit -q --allow-empty -m init
  else
    git -C "$seed" commit -q --allow-empty -m init
  fi

  git init -q --bare -b main "$bare"
  git -C "$seed" remote add origin "$bare"
  git -C "$seed" push -q origin main

  # Create the named branch and a worktree checked out to it from the bare repo.
  git --git-dir="$bare" worktree add -q -b "$branch" "$wt" main

  if [[ "$age" == "old" ]]; then
    # Backdate the worktree commit so get_commit_age_days() sees it as inactive,
    # and add a node_modules dir with content so du reports a non-zero size.
    GIT_AUTHOR_DATE="2000-01-01T00:00:00" GIT_COMMITTER_DATE="2000-01-01T00:00:00" \
      git -C "$wt" commit -q --allow-empty -m old
    mkdir -p "$wt/node_modules/pkg"
    printf 'x%.0s' {1..2000} > "$wt/node_modules/pkg/file.js"
  fi
}

# ============================================================================
# #31 — bare `grove clean` requires confirmation before deleting
# ============================================================================

@test "grove clean (bare): aborts without confirmation, keeps node_modules" {
  make_repo_worktree "alpha" "feature/x" "alpha-wt" old
  local nm="$HERD_ROOT/alpha-wt/node_modules"
  [ -d "$nm" ]

  # Answer "n" to the confirmation prompt — nothing must be deleted.
  HERD_ROOT="$HERD_ROOT" GROVE_HOOKS_DIR="$GROVE_HOOKS_DIR" \
    GROVE_CONFIG="$GROVE_CONFIG" NO_COLOR=1 \
    run zsh -c "printf 'n\n' | zsh '$GROVE_SCRIPT' clean"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Delete node_modules/vendor"* ]]
  [ -d "$nm" ]
}

@test "grove clean (bare) --force: proceeds without prompting, deletes node_modules" {
  make_repo_worktree "alpha" "feature/x" "alpha-wt" old
  local nm="$HERD_ROOT/alpha-wt/node_modules"
  [ -d "$nm" ]

  run_grove --force clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cleaned"* ]]
  [ ! -d "$nm" ]
}

@test "grove clean (bare) --dry-run: previews without confirmation or deletion" {
  make_repo_worktree "alpha" "feature/x" "alpha-wt" old
  local nm="$HERD_ROOT/alpha-wt/node_modules"

  run_grove --dry-run clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would clean"* ]]
  # Dry-run must not prompt for confirmation.
  [[ "$output" != *"Delete node_modules/vendor"* ]]
  [ -d "$nm" ]
}

# ============================================================================
# cmd_recent limit validation
#
# `recent` takes the count as a positional argument (`grove recent <count>`);
# the dispatcher rejects unknown --flags before they reach cmd_recent, so the
# count is what we must validate. A non-numeric value must fall back to the
# default rather than aborting on the array slice (the bug under test).
# ============================================================================

@test "grove recent abc: non-numeric limit does not abort" {
  make_repo_worktree "alpha" "feature/x" "alpha-wt" new

  run_grove recent abc
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recently Accessed Worktrees"* ]]
}

@test "grove recent abc --json: non-numeric limit still yields valid JSON" {
  make_repo_worktree "alpha" "feature/x" "alpha-wt" new

  run_grove recent abc --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

# ============================================================================
# cmd_recent --json — valid JSON with per-entry urls
# ============================================================================

@test "grove recent --json: emits valid JSON" {
  make_repo_worktree "alpha" "feature/x" "alpha-wt" new

  run_grove recent --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "grove recent --json: resolves url per-entry from each repo's own config" {
  # Two repos: only alpha sets a URL subdomain. The per-entry fix must give each
  # worktree its OWN url; the old bug applied the last-loaded subdomain to all.
  make_repo_worktree "alpha" "feature/a" "alpha-wt" new
  make_repo_worktree "bravo" "feature/b" "bravo-wt" new
  printf 'GROVE_URL_SUBDOMAIN=alpha\n' > "$HERD_ROOT/alpha.git/.groveconfig"

  run_grove recent --json
  [ "$status" -eq 0 ]

  # Valid JSON, and each repo's url reflects its own config.
  echo "$output" | python3 -c '
import json,sys
data = json.load(sys.stdin)
urls = {d["repo"]: d["url"] for d in data}
assert "alpha" in urls and "bravo" in urls, urls
assert urls["alpha"].startswith("https://alpha."), urls["alpha"]
assert "alpha." not in urls["bravo"], urls["bravo"]
'
}

# ============================================================================
# Skipped: cases requiring Herd / MySQL
# ============================================================================

@test "grove info --json database.exists (requires MySQL) - skipped" {
  skip "Requires a live MySQL server and Herd-provisioned database"
}
