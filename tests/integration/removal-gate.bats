#!/usr/bin/env bats
# removal-gate.bats - Integration tests for the worktree removal gate in
# lib/13-removal-gate.sh and its use by cmd_rm.
#
# These exercise the REAL zsh helpers against a stub `wt-removal-check` whose
# exit code and output each test controls. A stub rather than the real gate on
# purpose: this suite must not depend on whether the developer has it
# installed, and a bare clone of a local seed has no remote-tracking refs, so
# the real gate would call every worktree here unsaved.
#
# The behaviours that matter, and why:
#   - Blocked (exit 1) stops the removal, however forceful the caller was.
#     -f forces git; it does not accept the loss of unsaved work.
#   - The block is relayed verbatim. A gate that refuses without saying what
#     it protects is what teaches people to reach for -f.
#   - An absent gate refuses. "No gate ran" and "the gate passed" must never
#     look alike.

load '../test-helper'

setup() {
  setup_test_environment

  STUB_BIN="$TEST_TEMP_DIR/stub-bin"
  export STUB_BIN
  mkdir -p "$STUB_BIN"

  GATE_FNS="$TEST_TEMP_DIR/gate-fns.zsh"
  export GATE_FNS
  cat > "$GATE_FNS" <<'STUB'
info() { print -r -- "INFO: $*" >&2; }
ok()   { print -r -- "OK: $*" >&2; }
warn() { print -r -- "WARN: $*" >&2; }
dim()  { print -r -- "DIM: $*" >&2; }
QUIET=false
STUB
  cat "$GROVE_ROOT/lib/13-removal-gate.sh" >> "$GATE_FNS"

  # A worktree for the gate to be asked about.
  WT="$TEST_TEMP_DIR/wt"
  export WT
  mkdir -p "$WT"
}

teardown() {
  teardown_test_environment
}

# Write a stub `wt-removal-check` that exits with $1 and prints $2.
stub_gate() {
  local exit_code="$1" message="$2"
  cat > "$STUB_BIN/wt-removal-check" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TEST_TEMP_DIR/gate-argv.log"
printf '%s\n' '$message'
exit $exit_code
EOF
  chmod +x "$STUB_BIN/wt-removal-check"
}

run_zsh() {
  run env GROVE_REMOVAL_CHECK_BIN="$STUB_BIN/wt-removal-check" \
    zsh -c "source '$GATE_FNS'; $1"
}

# Run with no gate discoverable: a PATH holding only the system tools zsh
# needs, and a HOME with no ~/.local/bin or ~/.claude/bin in it.
run_zsh_without_gate() {
  mkdir -p "$TEST_TEMP_DIR/nohome"
  run env PATH="/usr/bin:/bin" GROVE_REMOVAL_CHECK_BIN="" HOME="$TEST_TEMP_DIR/nohome" \
    zsh -c "source '$GATE_FNS'; $1"
}

@test "gate: a clear check permits removal and says nothing" {
  stub_gate 0 "Safe to remove"
  run_zsh "removal_gate '$WT'; print -r -- \"REPLY=[\$REPLY]\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"REPLY=[]"* ]]
}

@test "gate: a block refuses removal and relays the loss verbatim" {
  stub_gate 1 "Removing $WT would lose: 2 uncommitted change(s)"
  run_zsh "removal_gate '$WT' || { print -r -- \"\$REPLY\"; exit 1; }"
  [ "$status" -ne 0 ]
  [[ "$output" == *"would lose: 2 uncommitted change(s)"* ]]
}

@test "gate: the gate is asked about the worktree path" {
  stub_gate 0 "Safe to remove"
  run_zsh "removal_gate '$WT'"
  [ "$status" -eq 0 ]
  [[ "$(cat "$TEST_TEMP_DIR/gate-argv.log")" == "$WT" ]]
}

@test "gate: an absent wt-removal-check refuses rather than passing silently" {
  run_zsh_without_gate "removal_gate '$WT' || { print -r -- \"\$REPLY\"; exit 1; }"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "gate: GROVE_REMOVAL_CHECK_BIN overrides discovery" {
  cat > "$TEST_TEMP_DIR/custom-gate" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$TEST_TEMP_DIR/custom-gate"
  run env GROVE_REMOVAL_CHECK_BIN="$TEST_TEMP_DIR/custom-gate" PATH="/usr/bin:/bin" \
    zsh -c "source '$GATE_FNS'; removal_check_binary"
  [ "$status" -eq 0 ]
  [[ "$output" == "$TEST_TEMP_DIR/custom-gate" ]]
}

# ============================================================================
# cmd_rm: the gate as the lifecycle actually uses it
# ============================================================================

setup_cmd_rm_harness() {
  RM_FNS="$TEST_TEMP_DIR/rm-fns.zsh"
  export RM_FNS
  cat > "$RM_FNS" <<'STUB'
info() { :; }
ok()   { :; }
warn() { print -r -- "WARN: $*" >&2; }
dim()  { :; }
notify() { :; }
C_RESET='' C_BOLD='' C_DIM='' C_CYAN='' C_MAGENTA='' C_GREEN='' C_YELLOW='' C_RED='' C_BLUE=''
JSON_OUTPUT=false
FORCE=false
DELETE_BRANCH=false
DROP_DB=false
INTERACTIVE=false
GROVE_URL_SUBDOMAIN=''
error_exit() { print -r -- "ERROR:$1:$2" >&2; exit "${3:-1}"; }
die() { print -r -- "ERROR:$*" >&2; exit 1; }
spinner_stop() { :; }
json_escape() { REPLY="$1"; }
format_json() { print -r -- "$1"; }
to_json_bool() { case "${1:l}" in true|1|yes|on) print -r -- true ;; *) print -r -- false ;; esac }
validate_name() { return 0; }
ensure_bare_repo() { return 0; }
load_repo_config() { return 0; }
restart_herd_service() { return 0; }
worktree_url() { url_for "$1" "$2"; }
count_lines() { print -r -- 0; }
# Every hook phase leaves a trace, so a test can prove the gate ran first.
run_hooks() { print -r -- "HOOK:$1" >&2; return 0; }
is_protected_branch() { return 1; }
slugify_branch() { REPLY="$1"; }
STUB
  cat "$GROVE_ROOT/lib/11-resilience.sh" >> "$RM_FNS"
  cat "$GROVE_ROOT/lib/13-removal-gate.sh" >> "$RM_FNS"
  cat "$GROVE_ROOT/lib/commands/lifecycle.sh" >> "$RM_FNS"

  GIT_DIR_FIXTURE="$TEST_TEMP_DIR/app.git"
  WT_FIXTURE="$TEST_TEMP_DIR/wt-app"
  export GIT_DIR_FIXTURE WT_FIXTURE
  local seed="$TEST_TEMP_DIR/seed"
  git init -q -b main "$seed"
  git -C "$seed" config user.email t@t.t
  git -C "$seed" config user.name 'Test'
  git -C "$seed" commit -q --allow-empty -m init
  git clone -q --bare "$seed" "$GIT_DIR_FIXTURE"
  git --git-dir="$GIT_DIR_FIXTURE" worktree add -q -b feature/login "$WT_FIXTURE" HEAD

  # What the interactive prompt reads; /dev/null unless a test answers.
  STDIN_FILE=/dev/null
}

run_cmd_rm() {
  run env GROVE_REMOVAL_CHECK_BIN="$STUB_BIN/wt-removal-check" zsh -c "
    source '$RM_FNS'
    git_dir_for() { print -r -- '$GIT_DIR_FIXTURE'; }
    resolve_worktree_path() { print -r -- '$WT_FIXTURE'; }
    url_for() { print -r -- 'https://x.test'; }
    db_name_for() { print -r -- 'app__x'; }
    $1
    cmd_rm 'app' 'feature/login' < '$STDIN_FILE'
  "
}

@test "cmd_rm: a block stops the removal before git touches anything, and before the pre-rm hooks" {
  setup_cmd_rm_harness
  stub_gate 1 "Removing $WT_FIXTURE would lose: 1 uncommitted change(s)"

  run_cmd_rm "FORCE=false"

  [ "$status" -ne 0 ]
  [[ "$output" == *"would lose"* ]]
  [[ "$output" != *"HOOK:pre-rm"* ]]
  [ -d "$WT_FIXTURE" ]
}

@test "cmd_rm: -f alone cannot bypass the gate" {
  # The single most important test in this file. -f forces git; it is not
  # consent to lose unsaved work.
  setup_cmd_rm_harness
  stub_gate 1 "Removing $WT_FIXTURE would lose: 3 commit(s) no remote has"

  run_cmd_rm "FORCE=true"

  [ "$status" -ne 0 ]
  [[ "$output" == *"would lose"* ]]
  [ -d "$WT_FIXTURE" ]
}

@test "cmd_rm: --json fails with REMOVAL_BLOCKED and carries the loss, never prompting" {
  setup_cmd_rm_harness
  stub_gate 1 "Removing $WT_FIXTURE would lose: a live agent session working here"

  run_cmd_rm "JSON_OUTPUT=true; FORCE=true"

  [ "$status" -eq 6 ]
  [[ "$output" == *"ERROR:REMOVAL_BLOCKED:"*"would lose"* ]]
  [[ "$output" != *"Remove anyway"* ]]
  [ -d "$WT_FIXTURE" ]
}

@test "cmd_rm: answering y at the prompt accepts the loss and removes" {
  setup_cmd_rm_harness
  stub_gate 1 "Removing $WT_FIXTURE would lose: 1 uncommitted change(s)"
  STDIN_FILE="$TEST_TEMP_DIR/answer"
  printf 'y\n' > "$STDIN_FILE"

  run_cmd_rm "FORCE=false"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Remove anyway"* ]]
  [ ! -d "$WT_FIXTURE" ]
}

@test "cmd_rm: answering n at the prompt aborts and keeps the worktree" {
  setup_cmd_rm_harness
  stub_gate 1 "Removing $WT_FIXTURE would lose: 1 uncommitted change(s)"
  STDIN_FILE="$TEST_TEMP_DIR/answer"
  printf 'n\n' > "$STDIN_FILE"

  run_cmd_rm "FORCE=false"

  [ "$status" -ne 0 ]
  [[ "$output" == *"INVALID_INPUT:aborted by user"* ]]
  [ -d "$WT_FIXTURE" ]
}

@test "cmd_rm: an absent gate refuses the removal" {
  setup_cmd_rm_harness
  mkdir -p "$TEST_TEMP_DIR/nohome"

  run env PATH="/usr/bin:/bin" GROVE_REMOVAL_CHECK_BIN="" HOME="$TEST_TEMP_DIR/nohome" zsh -c "
    source '$RM_FNS'
    git_dir_for() { print -r -- '$GIT_DIR_FIXTURE'; }
    resolve_worktree_path() { print -r -- '$WT_FIXTURE'; }
    url_for() { print -r -- 'https://x.test'; }
    db_name_for() { print -r -- 'app__x'; }
    JSON_OUTPUT=true; FORCE=true
    cmd_rm 'app' 'feature/login' < /dev/null
  "

  [ "$status" -eq 6 ]
  [[ "$output" == *"REMOVAL_BLOCKED"*"not found"* ]]
  [ -d "$WT_FIXTURE" ]
}

@test "cmd_rm: a clear gate lets the removal through" {
  setup_cmd_rm_harness
  stub_gate 0 "Safe to remove"

  run_cmd_rm "FORCE=true"

  [ "$status" -eq 0 ]
  [[ "$output" == *"HOOK:pre-rm"* ]]
  [ ! -d "$WT_FIXTURE" ]
}
