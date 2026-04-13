#!/usr/bin/env bats
# services.bats - Unit tests for services module config parsing and helpers
#
# All tests invoke zsh subshells because services.sh uses zsh-specific features
# (associative arrays, print -r, ${(k)array[@]}, etc.)

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PROJECT_ROOT

  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR

  # GROVE_SERVICES_CONF is derived from GROVE_SERVICES_DIR inside services.sh,
  # so only GROVE_SERVICES_DIR needs to be exported.
  export GROVE_SERVICES_DIR="$TEST_TMPDIR"
  export HERD_ROOT="$TEST_TMPDIR/Herd"
  mkdir -p "$HERD_ROOT"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# --- Config Loading ---

@test "svc_load_config with no config file returns success" {
  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config
    [[ "$SVC_CONFIG_LOADED" == true ]] || exit 1
    (( ${#SVC_APPS} == 0 )) || exit 2
  '
  [ "$status" -eq 0 ]
}

@test "svc_load_config parses pipe-delimited format" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myapp|myapp-repo|horizon|myapp-horizon|myapp.test
otherapp|otherapp|horizon:reverb|otherapp:*|otherapp.test
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config
    [[ "${SVC_APPS[myapp]}" == "horizon" ]]        || exit 1
    [[ "${SVC_SYSTEM_NAMES[myapp]}" == "myapp-repo" ]] || exit 2
    [[ "${SVC_SERVICES[otherapp]}" == "horizon:reverb" ]] || exit 3
    [[ "${SVC_DOMAINS[myapp]}" == "myapp.test" ]]  || exit 4
  '
  [ "$status" -eq 0 ]
}

@test "svc_load_config skips comments and empty lines" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
# This is a comment
myapp|myapp|horizon|myapp-horizon|myapp.test

# Another comment
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config
    (( ${#SVC_APPS} == 1 ))             || exit 1
    [[ "${SVC_APPS[myapp]}" == "horizon" ]] || exit 2
  '
  [ "$status" -eq 0 ]
}

@test "svc_load_config defaults domain to system_name.test when domain field is empty" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myapp|myapp-repo|horizon|myapp-horizon|
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config
    [[ "${SVC_DOMAINS[myapp]}" == "myapp-repo.test" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "svc_load_config sets SVC_CONFIG_LOADED true after loading" {
  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config
    [[ "$SVC_CONFIG_LOADED" == true ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "svc_load_config is idempotent when called twice" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myapp|myapp|horizon|myapp-horizon|myapp.test
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config
    svc_load_config
    (( ${#SVC_APPS} == 1 )) || exit 1
  '
  [ "$status" -eq 0 ]
}

# --- Validation Helpers ---

@test "svc_has_apps returns false with no apps registered" {
  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_has_apps && exit 1
    exit 0
  '
  [ "$status" -eq 0 ]
}

@test "svc_has_apps returns true when apps are registered" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myapp|myapp|horizon|myapp-horizon|myapp.test
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config
    svc_has_apps || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "svc_app_uses_horizon returns true for horizon service" {
  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    typeset -A SVC_SERVICES
    SVC_SERVICES[myapp]="horizon"
    svc_app_uses_horizon "myapp" || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "svc_app_uses_horizon returns true for horizon:reverb service" {
  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    typeset -A SVC_SERVICES
    SVC_SERVICES[myapp]="horizon:reverb"
    svc_app_uses_horizon "myapp" || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "svc_app_uses_horizon returns false for none service" {
  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    typeset -A SVC_SERVICES
    SVC_SERVICES[myapp]="none"
    svc_app_uses_horizon "myapp" && exit 1
    exit 0
  '
  [ "$status" -eq 0 ]
}

@test "svc_get_app_list returns sorted app names" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
zebra|zebra|horizon|zebra-horizon|zebra.test
alpha|alpha|horizon|alpha-horizon|alpha.test
middle|middle|none||middle.test
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config
    result="$(svc_get_app_list)"
    first_line="$(print -r -- "$result" | head -1)"
    [[ "$first_line" == "alpha" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "svc_get_system_name returns system name for app" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myapp|myapp-repo|horizon|myapp-horizon|myapp.test
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config
    result="$(svc_get_system_name "myapp")"
    [[ "$result" == "myapp-repo" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "svc_get_system_name falls back to app name when not set" {
  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    typeset -A SVC_SYSTEM_NAMES
    result="$(svc_get_system_name "myapp")"
    [[ "$result" == "myapp" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "svc_get_supervisor_process returns configured process" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myapp|myapp|horizon|myapp-horizon|myapp.test
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config
    result="$(svc_get_supervisor_process "myapp")"
    [[ "$result" == "myapp-horizon" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}

@test "svc_get_supervisor_process falls back to app-horizon default" {
  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    typeset -A SVC_SUPERVISOR_PROCESSES
    result="$(svc_get_supervisor_process "myapp")"
    [[ "$result" == "myapp-horizon" ]] || exit 1
  '
  [ "$status" -eq 0 ]
}
