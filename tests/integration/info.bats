#!/usr/bin/env bats
# info.bats - Integration tests for info/reporting commands (lib/commands/info.sh).
#
# Covers two regressions:
#   1. cmd_report assembled the report with literal "\n" then emitted it via
#      `print -r --`, which does not interpret escapes — collapsing the whole
#      report to one unreadable line. It must now contain REAL newlines.
#   2. `grove dashboard --json` emitted the box-drawing TUI (invalid JSON).
#      dashboard is not in the documented JSON contract, so --json must be
#      rejected cleanly (clear stderr error, non-zero exit, no stdout output).

load '../test-helper'

setup() {
  setup_test_environment

  export GROVE_SCRIPT="$GROVE_ROOT/grove"
  export GROVE_TEMPLATES_DIR="$TEST_TEMP_DIR/.grove/templates"
  mkdir -p "$GROVE_TEMPLATES_DIR"

  # Stand up a real grove-style bare repo with a single worktree so the
  # info commands have something to report on. git_dir_for() expects the bare
  # repo at "$HERD_ROOT/<repo>.git".
  REPO_NAME="testrepo"
  export REPO_NAME
  GIT_DIR_PATH="$HERD_ROOT/${REPO_NAME}.git"
  export GIT_DIR_PATH

  # Seed a normal repo, then clone it bare into place (a bare repo is what
  # grove manages). Add a worktree off the bare repo.
  local seed="$TEST_TEMP_DIR/seed"
  git init -q -b main "$seed"
  git -C "$seed" config user.email t@t.t
  git -C "$seed" config user.name 'Test'
  git -C "$seed" commit -q --allow-empty -m "initial commit"

  git clone -q --bare "$seed" "$GIT_DIR_PATH"

  # Create a worktree on the main branch under the worktrees root.
  WT_PATH="$HERD_ROOT/${REPO_NAME}-worktrees/main"
  export WT_PATH
  mkdir -p "$HERD_ROOT/${REPO_NAME}-worktrees"
  git --git-dir="$GIT_DIR_PATH" worktree add -q "$WT_PATH" main
}

teardown() {
  teardown_test_environment
}

# Helper to run grove with the test environment.
run_grove() {
  HERD_ROOT="$HERD_ROOT" \
  GROVE_HOOKS_DIR="$GROVE_HOOKS_DIR" \
  GROVE_TEMPLATES_DIR="$GROVE_TEMPLATES_DIR" \
  DEFAULT_BASE="origin/main" \
  NO_COLOR=1 \
  run zsh "$GROVE_SCRIPT" "$@"
}

# ============================================================================
# cmd_report - must emit REAL newlines, not a single collapsed line
# ============================================================================

@test "grove report: output spans multiple real lines (not one collapsed line)" {
  run_grove report "$REPO_NAME"
  [ "$status" -eq 0 ]
  # The report has many sections; with real newlines BATS splits it into lines.
  [ "${#lines[@]}" -gt 1 ]
}

@test "grove report: contains the markdown section headings on their own lines" {
  run_grove report "$REPO_NAME"
  [ "$status" -eq 0 ]
  # Each heading must appear as its own line — proof the report wasn't collapsed.
  local found_title=false found_summary=false found_worktrees=false
  local l
  for l in "${lines[@]}"; do
    [[ "$l" == "# Worktree Report: $REPO_NAME" ]] && found_title=true
    [[ "$l" == "## Summary" ]] && found_summary=true
    [[ "$l" == "## Worktrees" ]] && found_worktrees=true
  done
  [ "$found_title" = true ]
  [ "$found_summary" = true ]
  [ "$found_worktrees" = true ]
}

@test "grove report --output: written file contains multiple real lines" {
  local out_file="$TEST_TEMP_DIR/report.md"
  run_grove report "$REPO_NAME" --output "$out_file"
  [ "$status" -eq 0 ]
  [ -f "$out_file" ]
  # A collapsed report would be a single line; a correct one is many.
  local line_count
  line_count="$(wc -l < "$out_file" | tr -d ' ')"
  [ "$line_count" -gt 1 ]
  # And no literal backslash-n should leak into the file.
  ! grep -q '\\n' "$out_file"
}

# ============================================================================
# cmd_dashboard --json - reject cleanly (not invalid JSON on stdout)
# ============================================================================

@test "grove dashboard --json: rejected with non-zero exit" {
  run_grove dashboard --json
  [ "$status" -ne 0 ]
}

@test "grove dashboard --json: error message mentions json is unsupported" {
  run_grove dashboard --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"dashboard"* ]]
}

@test "grove dashboard --json: emits no box-drawing TUI on stdout" {
  # `run` merges stdout+stderr by default; capture stdout alone to prove the
  # invalid-JSON TUI is not printed.
  local stdout_only
  stdout_only="$(HERD_ROOT="$HERD_ROOT" GROVE_HOOKS_DIR="$GROVE_HOOKS_DIR" \
    GROVE_TEMPLATES_DIR="$GROVE_TEMPLATES_DIR" NO_COLOR=1 \
    zsh "$GROVE_SCRIPT" dashboard --json 2>/dev/null || true)"
  [[ "$stdout_only" != *"grove Dashboard"* ]]
  [[ "$stdout_only" != *"╔"* ]]
}

# ============================================================================
# cmd_info --json - the unknown ahead/behind sentinel must map to JSON null,
# never leak a bare `?` (which would be invalid JSON). Regression for the
# sentinel-mapping that ls/status already had but cmd_info was missing.
# ============================================================================

@test "grove info --json: unresolved base emits null ahead/behind (valid JSON)" {
  # The base ref (origin/main here) has no remote-tracking ref in this hermetic
  # fixture, so get_ahead_behind returns the unknown "?" sentinel. cmd_info must
  # emit JSON null for ahead/behind rather than a bare `?`.
  run_grove info "$REPO_NAME" main --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["git"]["ahead"] is None, d["git"]["ahead"]
assert d["git"]["behind"] is None, d["git"]["behind"]
'
}
