#!/usr/bin/env bats
# core-config.bats - Tests for the P3 config-parsing hardening in lib/01-core.sh.
#
# These exercise the REAL zsh functions from lib/01-core.sh (sourced via zsh), not
# bash reimplementations, because the behaviour under test is zsh-specific:
#   - to_json_bool (case-insensitive ${1:l} mapping)
#   - DB_CREATE/DB_BACKUP normalisation + GROVE_STALE_THRESHOLD validation
#   - _read_config_pairs inline-comment stripping and path-only HOME expansion
#   - bytes_to_human decimal handling at unit boundaries / the T cap
#
# Each test sources lib/01-core.sh (not the built grove) so it validates the source
# directly, independent of the build artifact.

load '../test-helper'

setup() {
  setup_test_environment
}

teardown() {
  teardown_test_environment
}

# Run a zsh snippet with the real lib/01-core.sh functions in scope.
# Minimal globals are predeclared so the file sources cleanly without main().
_core() {
  run zsh -c "
    QUIET=false
    DB_CREATE=true
    DB_BACKUP=true
    GROVE_STALE_THRESHOLD=50
    source '$GROVE_ROOT/lib/01-core.sh'
    $1
  "
}

# ============================================================================
# to_json_bool — loose value -> strict JSON boolean
# ============================================================================

@test "to_json_bool: true/1/yes/on map to true (case-insensitive)" {
  for v in true TRUE True 1 yes YES on ON; do
    _core "to_json_bool '$v'"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "to_json_bool: false/0/no/off/empty/garbage map to false" {
  for v in false FALSE 0 no off "" garbage maybe 2; do
    _core "to_json_bool '$v'"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
  done
}

# ============================================================================
# DB_CREATE / DB_BACKUP normalisation via load_config
# ============================================================================

@test "DB_CREATE=1 normalises to true" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf 'DB_CREATE=1\n' > "$cfg"
  _core "GROVE_CONFIG='$cfg' load_config; print -r -- \"\$DB_CREATE\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"true"* ]]
}

@test "DB_CREATE=yes normalises to true" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf 'DB_CREATE=yes\n' > "$cfg"
  _core "GROVE_CONFIG='$cfg' load_config; print -r -- \"\$DB_CREATE\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"true"* ]]
}

@test "DB_CREATE= (explicit empty) normalises to false" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf 'DB_CREATE=\n' > "$cfg"
  _core "GROVE_CONFIG='$cfg' load_config; print -r -- \"VAL=\$DB_CREATE\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAL=false"* ]]
}

@test "DB_CREATE with no config override keeps header default true" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf '# no DB_CREATE here\n' > "$cfg"
  _core "GROVE_CONFIG='$cfg' load_config; print -r -- \"VAL=\$DB_CREATE\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAL=true"* ]]
}

@test "DB_BACKUP=off normalises to false with a warning" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf 'DB_BACKUP=off\n' > "$cfg"
  _core "GROVE_CONFIG='$cfg' load_config; print -r -- \"VAL=\$DB_BACKUP\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAL=false"* ]]
}

@test "DB_CREATE=garbage warns and falls back to false" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf 'DB_CREATE=garbage\n' > "$cfg"
  _core "GROVE_CONFIG='$cfg' load_config; print -r -- \"VAL=\$DB_CREATE\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAL=false"* ]]
  [[ "$output" == *"Unrecognised DB_CREATE"* ]]
}

# ============================================================================
# GROVE_STALE_THRESHOLD validation
# ============================================================================

@test "GROVE_STALE_THRESHOLD=abc is rejected and falls back to default 50" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf 'GROVE_STALE_THRESHOLD=abc\n' > "$cfg"
  _core "GROVE_CONFIG='$cfg' load_config; print -r -- \"VAL=\$GROVE_STALE_THRESHOLD\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAL=50"* ]]
  [[ "$output" == *"Invalid GROVE_STALE_THRESHOLD"* ]]
}

@test "GROVE_STALE_THRESHOLD=100 is accepted unchanged" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf 'GROVE_STALE_THRESHOLD=100\n' > "$cfg"
  _core "GROVE_CONFIG='$cfg' load_config; print -r -- \"VAL=\$GROVE_STALE_THRESHOLD\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAL=100"* ]]
}

# ============================================================================
# Inline-comment stripping — bare '#' mid-value must survive
# ============================================================================

@test "config value pass#word is preserved (not truncated at #)" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf 'DB_PASSWORD=pass#word\n' > "$cfg"
  _core "_apply() { [[ \"\$1\" == DB_PASSWORD ]] && print -r -- \"VAL=\$2\"; }; _read_config_pairs '$cfg' _apply"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAL=pass#word"* ]]
}

@test "config value with trailing ' # comment' strips only the comment" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf 'DB_HOST=localhost   # primary host\n' > "$cfg"
  _core "_apply() { [[ \"\$1\" == DB_HOST ]] && print -r -- \"VAL=\$2\"; }; _read_config_pairs '$cfg' _apply"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAL=localhost"* ]]
  [[ "$output" != *"primary host"* ]]
}

# ============================================================================
# HOME/~ expansion restricted to path-typed keys only
# ============================================================================

@test "path-typed key HERD_ROOT expands \$HOME" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf 'HERD_ROOT=$HOME/Herd\n' > "$cfg"
  _core "HOME=/tmp/fakehome; _apply() { [[ \"\$1\" == HERD_ROOT ]] && print -r -- \"VAL=\$2\"; }; _read_config_pairs '$cfg' _apply"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAL=/tmp/fakehome/Herd"* ]]
}

@test "non-path key GROVE_URL_SUBDOMAIN is NOT HOME/~ expanded" {
  local cfg="$TEST_TEMP_DIR/.groverc"
  printf 'GROVE_URL_SUBDOMAIN=~weird\n' > "$cfg"
  _core "HOME=/tmp/fakehome; _apply() { [[ \"\$1\" == GROVE_URL_SUBDOMAIN ]] && print -r -- \"VAL=\$2\"; }; _read_config_pairs '$cfg' _apply"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAL=~weird"* ]]
}

# ============================================================================
# bytes_to_human — decimals at unit boundaries and the T cap
# ============================================================================

@test "bytes_to_human: exact 1M boundary has no spurious decimal" {
  _core "bytes_to_human 1024"
  [ "$status" -eq 0 ]
  [ "$output" = "1M" ]
}

@test "bytes_to_human: 1.5M keeps the decimal" {
  _core "bytes_to_human 1536"
  [ "$status" -eq 0 ]
  [ "$output" = "1.5M" ]
}

@test "bytes_to_human: T cap retains its fraction (regression)" {
  # 1610612736 KB = 1.5 TiB. The old code dropped the decimal at the T cap.
  _core "bytes_to_human 1610612736"
  [ "$status" -eq 0 ]
  [ "$output" = "1.5T" ]
}

@test "bytes_to_human: zero and invalid input return 0K" {
  _core "bytes_to_human 0"
  [ "$status" -eq 0 ]
  [ "$output" = "0K" ]
  _core "bytes_to_human notanumber"
  [ "$status" -eq 0 ]
  [ "$output" = "0K" ]
}
