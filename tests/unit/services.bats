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

# --- Malformed Config Handling ---

@test "svc_load_config skips a line with the wrong field count" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
goodapp|goodapp|horizon|goodapp-horizon|goodapp.test
badline|missing-fields
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    (( ${#SVC_APPS} == 1 ))                     || exit 1
    [[ "${SVC_APPS[goodapp]}" == "horizon" ]]   || exit 2
    (( ${+SVC_APPS[badline]} ))                 && exit 3
    exit 0
  '
  [ "$status" -eq 0 ]
}

@test "svc_load_config skips a line with an empty app name" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
goodapp|goodapp|horizon|goodapp-horizon|goodapp.test
|emptyname|horizon|x-horizon|x.test
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    (( ${#SVC_APPS} == 1 ))                   || exit 1
    [[ "${SVC_APPS[goodapp]}" == "horizon" ]] || exit 2
    exit 0
  '
  [ "$status" -eq 0 ]
}

@test "svc_load_config warns to stderr when skipping a malformed line" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
badline|missing-fields
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/01-core.sh" 2>/dev/null || true
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>&1 1>/dev/null
  '
  [[ "$output" == *"Skipping malformed registry line"* ]]
}

@test "svc_load_config trim preserves internal spaces (leading/trailing only)" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
spaced | sys name | horizon | proc name | dom.test
EOF

  run zsh -c '
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    [[ "${SVC_SYSTEM_NAMES[spaced]}" == "sys name" ]]          || exit 1
    [[ "${SVC_SUPERVISOR_PROCESSES[spaced]}" == "proc name" ]] || exit 2
    exit 0
  '
  [ "$status" -eq 0 ]
}

# --- JSON Output Contract ---

@test "services apps --json emits valid JSON" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myapp|myapp-repo|horizon|myapp-horizon|myapp.test
otherapp|otherapp|horizon:reverb|otherapp:*|otherapp.test
EOF

  run zsh -c '
    for f in 01-core 02-validation 07-templates; do
      source "$PROJECT_ROOT/lib/$f.sh" 2>/dev/null || true
    done
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    PRETTY_JSON=false
    cmd_services_apps_json
  '
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

@test "services apps --json honours --pretty (multi-line output)" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myapp|myapp-repo|horizon|myapp-horizon|myapp.test
EOF

  run zsh -c '
    for f in 01-core 02-validation 07-templates; do
      source "$PROJECT_ROOT/lib/$f.sh" 2>/dev/null || true
    done
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    PRETTY_JSON=true
    cmd_services_apps_json
  '
  [ "$status" -eq 0 ]
  # Pretty output is still valid JSON...
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
  # ...and is multi-line (one key per line) rather than the single-object compact form.
  line_count="$(printf '%s\n' "$output" | wc -l | tr -d ' ')"
  [ "$line_count" -gt 1 ]
  [[ "$output" == *$'\n'*'"name"'* ]]
}

@test "services status --json emits valid JSON with expected shape" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myapp|myapp-repo|horizon|myapp-horizon|myapp.test
noneapp|noneapp|none||noneapp.test
EOF

  run zsh -c '
    for f in 01-core 02-validation 07-templates; do
      source "$PROJECT_ROOT/lib/$f.sh" 2>/dev/null || true
    done
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    PRETTY_JSON=false
    cmd_services_status_json
  '
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert isinstance(data['supervisor_running'], bool)
assert isinstance(data['redis_running'], bool)
apps = {a['name']: a for a in data['apps']}
assert set(apps) == {'myapp', 'noneapp'}
# No -current symlink in the test HERD_ROOT
assert apps['myapp']['current_worktree'] is None
# supervisorctl is absent/empty in tests, so the named process is unmatched
assert apps['myapp']['supervisor_status'] == 'NOT_CONFIGURED'
# services=none apps have no supervisor process to report
assert apps['noneapp']['supervisor_status'] is None
assert isinstance(apps['myapp']['scheduler_loaded'], bool)
"
}

@test "services status --json filters to a single app" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myapp|myapp-repo|horizon|myapp-horizon|myapp.test
otherapp|otherapp|horizon|otherapp-horizon|otherapp.test
EOF

  run zsh -c '
    for f in 01-core 02-validation 07-templates; do
      source "$PROJECT_ROOT/lib/$f.sh" 2>/dev/null || true
    done
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    PRETTY_JSON=false
    cmd_services_status_json myapp
  '
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert [a['name'] for a in data['apps']] == ['myapp']
"
}

@test "services status --json rejects an unknown app" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myapp|myapp-repo|horizon|myapp-horizon|myapp.test
EOF

  run zsh -c '
    for f in 01-core 02-validation 07-templates; do
      source "$PROJECT_ROOT/lib/$f.sh" 2>/dev/null || true
    done
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    PRETTY_JSON=false
    cmd_services_status_json nosuchapp
  '
  [ "$status" -ne 0 ]
}

# --- Field Validation (registry integrity) ---

@test "services add rejects a system name containing a pipe" {
  run zsh -c '
    for f in 01-core 02-validation 07-templates; do
      source "$PROJECT_ROOT/lib/$f.sh" 2>/dev/null || true
    done
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    cmd_services_add goodname --system-name="bad|name"
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid system name"* ]]
  # Nothing should have been persisted.
  [ ! -f "$GROVE_SERVICES_DIR/apps.conf" ] || ! grep -q "goodname" "$GROVE_SERVICES_DIR/apps.conf"
}

@test "services add rejects a domain containing a pipe" {
  run zsh -c '
    for f in 01-core 02-validation 07-templates; do
      source "$PROJECT_ROOT/lib/$f.sh" 2>/dev/null || true
    done
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    cmd_services_add goodname --domain="bad|domain.test"
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid domain"* ]]
}

@test "services add rejects a domain with a newline" {
  run zsh -c '
    for f in 01-core 02-validation 07-templates; do
      source "$PROJECT_ROOT/lib/$f.sh" 2>/dev/null || true
    done
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    cmd_services_add goodname --domain="line1
line2.test"
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid domain"* ]]
}

@test "services add rejects a domain with disallowed characters" {
  run zsh -c '
    for f in 01-core 02-validation 07-templates; do
      source "$PROJECT_ROOT/lib/$f.sh" 2>/dev/null || true
    done
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    cmd_services_add goodname --domain="bad domain!"
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid domain"* ]]
}

@test "services add persists a valid registration" {
  run zsh -c '
    for f in 01-core 02-validation 07-templates; do
      source "$PROJECT_ROOT/lib/$f.sh" 2>/dev/null || true
    done
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    cmd_services_add goodname --system-name=good-sys --domain=good.test
  '
  [ "$status" -eq 0 ]
  grep -q "^goodname|good-sys|horizon|good-sys-horizon|good.test$" "$GROVE_SERVICES_DIR/apps.conf"
}

# --- Registry Removal (literal prefix match) ---

@test "services remove uses a literal prefix and does not over-match" {
  cat > "$GROVE_SERVICES_DIR/apps.conf" << 'EOF'
myXapp|myXapp|horizon|myXapp-horizon|myXapp.test
my.app|my.app|horizon|my.app-horizon|my.app.test
EOF

  run zsh -c '
    for f in 01-core 02-validation 07-templates; do
      source "$PROJECT_ROOT/lib/$f.sh" 2>/dev/null || true
    done
    source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
    svc_load_config 2>/dev/null
    cmd_services_remove "my.app" >/dev/null 2>&1
  '
  [ "$status" -eq 0 ]
  # The dot in my.app must not be treated as a regex wildcard matching myXapp.
  # Assert with fixed-string matches so the test itself can't over-match either.
  grep -qF "myXapp|myXapp|" "$GROVE_SERVICES_DIR/apps.conf"
  ! grep -qF "my.app|my.app|" "$GROVE_SERVICES_DIR/apps.conf"
}
