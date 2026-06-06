#!/usr/bin/env bats
# maintenance.bats - Integration tests for the real zsh helpers in
# lib/commands/maintenance.sh.
#
# These exercise the ACTUAL zsh implementations (sourced via zsh against real
# temp git repos / symlinks), not bash reimplementations. They guard the
# readiness-audit fixes:
#   1. cmd_upgrade refuses to rebase when not on the default branch.
#   2. cmd_upgrade refuses to rebase when the tree is dirty.
#   3. cmd_cleanup_herd does not judge a live site with a RELATIVE symlink
#      as orphaned.
#   4. cmd_doctor returns non-zero when it finds a seeded problem.

load '../test-helper'

setup() {
  setup_test_environment

  # Build a sourceable zsh file: stub the cross-module helpers that
  # lib/commands/maintenance.sh expects (output helpers, error_exit, colours),
  # then append the real module body. We source ONLY this module so the tests
  # pin the helpers we are exercising.
  MAINT_FNS="$TEST_TEMP_DIR/maint-fns.zsh"
  export MAINT_FNS
  cat > "$MAINT_FNS" <<'STUB'
# Output helpers (print to stderr so they never pollute captured STDOUT).
info() { print -r -- "INFO: $1" >&2; }
ok()   { print -r -- "OK: $1" >&2; }
warn() { print -r -- "WARN: $1" >&2; }
dim()  { print -r -- "$1" >&2; }
# error_exit must abort the process with a non-zero status (the real one exits).
error_exit() { print -r -- "ERR: $2" >&2; exit "${3:-1}"; }
# Colour variables are empty in tests (NO_COLOR).
C_BOLD="" C_RESET="" C_CYAN="" C_YELLOW="" C_GREEN="" C_MAGENTA="" C_DIM="" C_RED=""
VERSION="0.0.0-test"
FORCE=true
STUB
  cat "$GROVE_ROOT/lib/commands/maintenance.sh" >> "$MAINT_FNS"
}

teardown() {
  teardown_test_environment
}

# Run a snippet against the sourced helpers in a clean zsh process.
run_zsh() {
  run zsh -c "source '$MAINT_FNS'; $1"
}

# Stand up a grove git repo with an 'origin' that is one commit ahead, plus a
# 'grove' symlink on PATH pointing at a marker file in the repo. Echoes a
# snippet prefix that puts the fake bin dir on PATH.
#
# Sets in the calling shell: REPO_DIR, BIN_DIR
setup_grove_repo() {
  REPO_DIR="$TEST_TEMP_DIR/grove-src"
  local origin="$TEST_TEMP_DIR/origin.git"

  git init -q -b main "$REPO_DIR"
  git -C "$REPO_DIR" config user.email t@t.t
  git -C "$REPO_DIR" config user.name 'Test'
  # The grove script lives at the repo root; :h of its resolved path is the repo.
  # It must be executable so `command -v grove` resolves the PATH symlink.
  printf '#!/usr/bin/env zsh\n' > "$REPO_DIR/grove"
  chmod +x "$REPO_DIR/grove"
  git -C "$REPO_DIR" add grove
  git -C "$REPO_DIR" commit -q -m init

  git init -q --bare -b main "$origin"
  git -C "$REPO_DIR" remote add origin "$origin"
  git -C "$REPO_DIR" push -q -u origin main

  # Make origin/main one commit ahead so an upgrade is "available".
  local clone="$TEST_TEMP_DIR/clone"
  git clone -q "$origin" "$clone"
  git -C "$clone" config user.email t@t.t
  git -C "$clone" config user.name 'Test'
  git -C "$clone" commit -q --allow-empty -m 'newer'
  git -C "$clone" push -q origin main
  git -C "$REPO_DIR" fetch -q origin

  # A fake bin dir with a 'grove' symlink -> the repo's grove script.
  BIN_DIR="$TEST_TEMP_DIR/bin"
  mkdir -p "$BIN_DIR"
  ln -s "$REPO_DIR/grove" "$BIN_DIR/grove"
}

# ============================================================================
# cmd_upgrade — safety rails (#5)
# ============================================================================

@test "cmd_upgrade: refuses to rebase when not on the default branch" {
  setup_grove_repo
  # Move the repo onto a feature branch — upgrade must refuse rather than rebase
  # it onto main.
  git -C "$REPO_DIR" checkout -q -b feature/work

  # Put the fake 'grove' symlink first on PATH while keeping the rest (so git is
  # still found). $BIN_DIR and $PATH are expanded by bats here, not the inner zsh.
  run_zsh "export PATH=\"$BIN_DIR:$PATH\"; cmd_upgrade"
  [ "$status" -ne 0 ]
  [[ "$output" == *"default branch"* ]]
  # The repo must still be on the feature branch (no rebase happened).
  [ "$(git -C "$REPO_DIR" symbolic-ref --short HEAD)" = "feature/work" ]
}

@test "cmd_upgrade: refuses to rebase when the tree is dirty" {
  setup_grove_repo
  # Dirty the working tree while on the default branch.
  printf 'dirty\n' >> "$REPO_DIR/grove"

  run_zsh "export PATH=\"$BIN_DIR:$PATH\"; cmd_upgrade"
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted changes"* ]]
}

# ============================================================================
# cmd_cleanup_herd — relative-symlink live site is NOT orphaned (#30)
# ============================================================================

@test "cmd_cleanup_herd: a live site with a RELATIVE symlink is not orphaned" {
  if ! command -v herd >/dev/null 2>&1; then
    skip "herd not installed (cmd_cleanup_herd requires the herd binary)"
  fi

  # Lay out a Herd config tree: a Sites symlink that points at a LIVE worktree
  # directory via a RELATIVE path. The bug judged such a link orphaned because
  # the relative target was tested against grove's cwd.
  local herd_cfg="$TEST_TEMP_DIR/herd-config"
  local sites="$herd_cfg/valet/Sites"
  local nginx="$herd_cfg/valet/Nginx"
  mkdir -p "$sites" "$nginx"

  # The real (live) worktree directory.
  local live="$TEST_TEMP_DIR/myapp-worktrees/feature-live"
  mkdir -p "$live"

  # Relative symlink from inside Sites to the live dir.
  ln -s "../../../myapp-worktrees/feature-live" "$sites/feature-live"

  run_zsh "export HERD_CONFIG='$herd_cfg' FORCE=true; cd /; cmd_cleanup_herd"
  [ "$status" -eq 0 ]
  # The live site must NOT be reported as orphaned, and its symlink must survive.
  [[ "$output" != *"orphaned config"* ]] || [[ "$output" == *"No orphaned configs found"* ]]
  [ -L "$sites/feature-live" ]
}

# ============================================================================
# cmd_doctor — non-zero exit on a seeded problem (P3)
# ============================================================================

@test "cmd_doctor: returns non-zero when a required tool is missing" {
  # Seed a problem: a non-existent HERD_ROOT and an empty PATH so the required
  # tools (git, composer) are reported missing. doctor must exit non-zero.
  run zsh -c "source '$MAINT_FNS'; export HERD_ROOT='$TEST_TEMP_DIR/does-not-exist' DB_BACKUP_DIR='$TEST_TEMP_DIR/nodir' GROVE_HOOKS_DIR='$TEST_TEMP_DIR/nohooks' DEFAULT_EDITOR='nonesuch'; PATH=/nonexistent cmd_doctor"
  [ "$status" -ne 0 ]
  [[ "$output" == *"issue(s) found"* ]]
}

# ============================================================================
# cmd_repair --json — RepairResult contract for the Grove desktop app
# ============================================================================

# Create a bare repo in HERD_ROOT with two healthy worktrees. Two are needed
# to regression-test the zsh `local var;` re-declaration leak inside the
# integrity loop (it only fires from the second iteration onward).
setup_repair_repo() {
  local src="$TEST_TEMP_DIR/repair-src"
  git init -q -b main "$src"
  git -C "$src" config user.email t@t.t
  git -C "$src" config user.name 'Test'
  git -C "$src" commit -q --allow-empty -m init
  git clone -q --bare "$src" "$HERD_ROOT/myrepo.git"
  git --git-dir="$HERD_ROOT/myrepo.git" worktree add -q "$TEST_TEMP_DIR/wt-main" main
  git --git-dir="$HERD_ROOT/myrepo.git" worktree add -q -b feature "$TEST_TEMP_DIR/wt-feature" main
}

# Like run_zsh but with stubs for the cross-module helpers cmd_repair needs.
run_repair_zsh() {
  run zsh -c "source '$MAINT_FNS'
validate_name() { :; }
git_dir_for() { print -r -- \"\$HERD_ROOT/\$1.git\"; }
ensure_bare_repo() { :; }
check_index_locks() { print -r -- 0; }
json_escape() { REPLY=\"\$1\"; }
format_json() { print -r -- \"\$1\"; }
$1"
}

@test "cmd_repair: --json emits a pure RepairResult object on stdout" {
  setup_repair_repo
  # stderr discarded: stdout must be EXACTLY one valid JSON object — any
  # banner, blank line or gitdir_content='...' typeset leak fails the parse.
  run_repair_zsh "JSON_OUTPUT=true cmd_repair myrepo 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['success'] is True, d
assert d['repo'] == 'myrepo', d
assert d['issues_found'] == 0, d
assert d['issues_fixed'] == 0, d
assert d['message'], d
"
}

@test "cmd_repair: human output is unchanged without --json and has no typeset leak" {
  setup_repair_repo
  run_repair_zsh "cmd_repair myrepo 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Repairing:"*"myrepo"* ]]
  [[ "$output" == *"No issues found in myrepo"* ]]
  [[ "$output" != *"gitdir_content="* ]]
}

@test "cmd_repair: --json with no repo (repair-all) is rejected" {
  setup_repair_repo
  run_repair_zsh "JSON_OUTPUT=true cmd_repair 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"JSON output"* ]]
}

@test "cmd_repair: --json counts an integrity issue on the LAST worktree (loop off-by-one)" {
  setup_repair_repo
  # Corrupt the final worktree listed by porcelain output: the old loop
  # never processed the last entry (here-string drops the trailing blank
  # line), so this issue went undetected.
  echo "garbage" > "$TEST_TEMP_DIR/wt-feature/.git"
  run_repair_zsh "JSON_OUTPUT=true cmd_repair myrepo 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['success'] is False, d
assert d['issues_found'] == 1, d
assert d['issues_fixed'] == 0, d
assert 'recovery' in d['message'], d
"
}
