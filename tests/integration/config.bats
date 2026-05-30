#!/usr/bin/env bats
# config.bats - Integration tests for the real zsh helpers in
# lib/commands/config.sh.
#
# These exercise the ACTUAL zsh implementations (sourced via zsh against a real
# temp aliases/groups file), not bash reimplementations. They guard the
# regressions fixed in lib/commands/config.sh:
#   #12  cmd_config must emit bare true/false booleans (via to_json_bool).
#   #13  alias add/remove must anchor to line start so removing 'foo' never
#        clobbers an unrelated 'myfoo=...' line.
#   #33  group add must validate_name BEFORE git_dir_for, so 'add' never
#        persists a name that 'show' would later reject.
#   #10  resolve_alias / resolve_group echo the right value and return 0 when
#        found, non-zero when not.

load '../test-helper'

setup() {
  setup_test_environment

  # Build a sourceable zsh file: stub the cross-module dependencies that
  # lib/commands/config.sh expects (output/validation/git helpers live in other
  # modules), then append the real lib/commands/config.sh body. We deliberately
  # source ONLY this module so the test pins the helpers we are exercising.
  #
  # GROVE_GROUPS_FILE is declared `readonly` at the top of config.sh using
  # $HOME, so each snippet sets HOME into the temp dir before sourcing.
  CFG_FNS="$TEST_TEMP_DIR/config-fns.zsh"
  export CFG_FNS
  cat > "$CFG_FNS" <<'STUB'
# --- output helpers (no-ops / passthrough) ---
ok()   { print -r -- "OK: $1"; }
info() { print -r -- "INFO: $1"; }
warn() { print -r -- "WARN: $1" >&2; }
dim()  { :; }
# --- colour vars (config.sh interpolates these) ---
C_RESET="" C_BOLD="" C_DIM="" C_GREEN="" C_RED="" C_YELLOW=""
C_CYAN="" C_MAGENTA=""
# --- error_exit: print + exit non-zero (mirrors the real fatal contract) ---
error_exit() { print -r -- "ERROR[$1]: $2" >&2; exit "${3:-1}"; }
# --- to_json_bool: faithful copy of the real lib/01-core.sh helper ---
to_json_bool() {
  case "${1:l}" in
    true|1|yes|on) print -r -- "true" ;;
    *)             print -r -- "false" ;;
  esac
}
# --- validate_name: minimal stand-in that rejects names containing any
#     character outside the repo/branch whitelist (mirrors the real reject
#     decision for clearly-invalid input). Calls error_exit on reject, exactly
#     like the real helper, so config.sh's control flow is exercised. ---
validate_name() {
  if [[ ! "$1" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
    error_exit "INVALID_REPO" "Invalid repository name: '$1'" 2
  fi
  return 0
}
# --- git_dir_for / count_lines: cheap stand-ins ---
git_dir_for() { print -r -- "$TEST_TEMP_DIR/repos/$1/.git"; }
count_lines() { print -r -- 0; }
JSON_OUTPUT=false
STUB
  cat "$GROVE_ROOT/lib/commands/config.sh" >> "$CFG_FNS"
}

teardown() {
  teardown_test_environment
}

# Run a snippet against the sourced helpers in a clean zsh process, with HOME
# pointed at the temp dir so GROVE_GROUPS_FILE/aliases resolve there.
run_cfg() {
  run env HOME="$TEST_TEMP_DIR" GROVE_ALIASES_FILE="$TEST_TEMP_DIR/.grove/aliases" \
    JSON_OUTPUT="${JSON_OUTPUT:-false}" \
    zsh -c "source '$CFG_FNS'; $1"
}

# ============================================================================
# #13 — anchored alias removal must not clobber prefix-sharing names
# ============================================================================

@test "cmd_alias rm: removing 'foo' leaves 'myfoo' intact (anchored)" {
  mkdir -p "$TEST_TEMP_DIR/.grove"
  cat > "$TEST_TEMP_DIR/.grove/aliases" <<'EOF'
myfoo=repo/feature-a
foo=repo/feature-b
EOF

  run_cfg "cmd_alias rm foo"
  [ "$status" -eq 0 ]

  # 'foo' is gone, 'myfoo' survives.
  run grep -q '^foo=' "$TEST_TEMP_DIR/.grove/aliases"
  [ "$status" -ne 0 ]
  run grep -q '^myfoo=' "$TEST_TEMP_DIR/.grove/aliases"
  [ "$status" -eq 0 ]
}

@test "cmd_alias add: re-adding 'foo' leaves 'myfoo' intact (anchored)" {
  mkdir -p "$TEST_TEMP_DIR/.grove"
  cat > "$TEST_TEMP_DIR/.grove/aliases" <<'EOF'
myfoo=repo/feature-a
foo=repo/old
EOF

  run_cfg "cmd_alias add foo repo/new"
  [ "$status" -eq 0 ]

  # 'myfoo' must still be present, and 'foo' updated exactly once.
  run grep -q '^myfoo=repo/feature-a' "$TEST_TEMP_DIR/.grove/aliases"
  [ "$status" -eq 0 ]
  run grep -c '^foo=' "$TEST_TEMP_DIR/.grove/aliases"
  [ "$output" = "1" ]
  run grep -q '^foo=repo/new' "$TEST_TEMP_DIR/.grove/aliases"
  [ "$status" -eq 0 ]
}

# ============================================================================
# #13 / P3 — alias target validation rejects '=' and leading dash
# ============================================================================

@test "cmd_alias add: rejects target containing '='" {
  mkdir -p "$TEST_TEMP_DIR/.grove"
  : > "$TEST_TEMP_DIR/.grove/aliases"
  run_cfg "cmd_alias add bad 'repo=evil'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid alias target"* ]]
}

@test "cmd_alias add: rejects target with a leading dash" {
  mkdir -p "$TEST_TEMP_DIR/.grove"
  : > "$TEST_TEMP_DIR/.grove/aliases"
  run_cfg "cmd_alias add bad -- '-rf'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid alias target"* ]]
}

# ============================================================================
# #33 — group add validates repo names BEFORE persisting
# ============================================================================

@test "cmd_group add: rejects an invalid repo name (does not persist)" {
  mkdir -p "$TEST_TEMP_DIR/.grove"
  : > "$TEST_TEMP_DIR/.grove/groups"

  # 'bad;name' fails validate_name, so add must abort before writing.
  run_cfg "cmd_group add mygroup 'bad;name'"
  [ "$status" -ne 0 ]

  # Nothing should have been written for the group.
  run grep -q '^mygroup=' "$TEST_TEMP_DIR/.grove/groups"
  [ "$status" -ne 0 ]
}

# ============================================================================
# #10 — resolve_alias / resolve_group contract
# ============================================================================

@test "resolve_alias: echoes the target and returns 0 when found" {
  mkdir -p "$TEST_TEMP_DIR/.grove"
  cat > "$TEST_TEMP_DIR/.grove/aliases" <<'EOF'
myfoo=repo/feature-a
foo=repo/feature-b
EOF

  run_cfg "resolve_alias foo"
  [ "$status" -eq 0 ]
  [ "$output" = "repo/feature-b" ]
}

@test "resolve_alias: returns non-zero when not found" {
  mkdir -p "$TEST_TEMP_DIR/.grove"
  cat > "$TEST_TEMP_DIR/.grove/aliases" <<'EOF'
foo=repo/feature-b
EOF

  run_cfg "resolve_alias missing"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "resolve_alias: does not prefix-match (foo != myfoo)" {
  mkdir -p "$TEST_TEMP_DIR/.grove"
  cat > "$TEST_TEMP_DIR/.grove/aliases" <<'EOF'
myfoo=repo/feature-a
EOF

  # Asking for 'foo' must NOT resolve to the 'myfoo' line.
  run_cfg "resolve_alias foo"
  [ "$status" -ne 0 ]
}

@test "resolve_group: echoes the space-separated repo list and returns 0" {
  mkdir -p "$TEST_TEMP_DIR/.grove"
  cat > "$TEST_TEMP_DIR/.grove/groups" <<'EOF'
api=repo-one repo-two repo-three
EOF

  run_cfg "resolve_group api"
  [ "$status" -eq 0 ]
  [ "$output" = "repo-one repo-two repo-three" ]
}

@test "resolve_group: returns non-zero when not found" {
  mkdir -p "$TEST_TEMP_DIR/.grove"
  cat > "$TEST_TEMP_DIR/.grove/groups" <<'EOF'
api=repo-one repo-two
EOF

  run_cfg "resolve_group nope"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# ============================================================================
# #12 — boolean normalisation: to_json_bool always yields bare true/false
# ============================================================================

@test "to_json_bool: maps truthy values to bare true" {
  run_cfg "to_json_bool 1"
  [ "$output" = "true" ]
  run_cfg "to_json_bool yes"
  [ "$output" = "true" ]
  run_cfg "to_json_bool true"
  [ "$output" = "true" ]
  run_cfg "to_json_bool ON"
  [ "$output" = "true" ]
}

@test "to_json_bool: maps empty / other values to bare false" {
  run_cfg "to_json_bool ''"
  [ "$output" = "false" ]
  run_cfg "to_json_bool nope"
  [ "$output" = "false" ]
  run_cfg "to_json_bool 0"
  [ "$output" = "false" ]
}

@test "cmd_config --json: db/herd booleans are bare true (not '1'/'yes')" {
  # A loosely-typed config (DB_CREATE=1, HERD_ENABLED=yes) must still produce
  # valid JSON with bare booleans, not the raw 1/yes that would break parsers.
  run_cfg "JSON_OUTPUT=true DB_CREATE=1 HERD_ENABLED=yes cmd_config"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"enabled": true'* ]]
  [[ "$output" == *'"herd_enabled": true'* ]]
  # And must never leak the raw values into the JSON.
  [[ "$output" != *'"enabled": 1'* ]]
  [[ "$output" != *'"herd_enabled": yes'* ]]
}
