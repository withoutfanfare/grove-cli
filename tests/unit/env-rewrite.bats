#!/usr/bin/env bats
# env-rewrite.bats - Regression tests for the .env APP_URL rewrite used by
# `grove move` and `grove restructure`.
#
# These exercise the REAL zsh _update_env_app_url() from the built grove (sourced via zsh),
# not a bash reimplementation, because the original bug (a greedy ${content/APP_URL=*/...}
# glob that matched across newlines) silently deleted every .env line after APP_URL=.

load '../test-helper'

setup() {
  setup_test_environment
}

teardown() {
  teardown_test_environment
}

# Run _update_env_app_url from the actual grove script against $1 (.env path), $2 (new url)
_run_real_update_env() {
  local env_file="$1" new_url="$2"
  local fns="$TEST_TEMP_DIR/grove-fns.zsh"
  # Strip the main() invocation so sourcing only defines functions / sets defaults
  sed '/^main "\$@"$/d' "$GROVE_ROOT/grove" > "$fns"
  zsh -c "source '$fns'; _update_env_app_url '$env_file' '$new_url'"
}

@test "env rewrite: updates APP_URL and preserves all other keys" {
  local env="$TEST_TEMP_DIR/.env"
  cat > "$env" <<'EOF'
APP_NAME=Acme
APP_ENV=local
APP_URL=http://old.test
DB_CONNECTION=mysql
DB_DATABASE=acme
DB_PASSWORD=secret123
MAIL_HOST=localhost
QUEUE_CONNECTION=redis
EOF

  _run_real_update_env "$env" "http://new.test"

  # All 8 key=value lines must survive (the original bug left only 3)
  run grep -c '=' "$env"
  [ "$output" -eq 8 ]

  # APP_URL updated...
  grep -q '^APP_URL=http://new.test$' "$env"
  # ...and every key after it preserved verbatim
  grep -q '^DB_CONNECTION=mysql$' "$env"
  grep -q '^DB_DATABASE=acme$' "$env"
  grep -q '^DB_PASSWORD=secret123$' "$env"
  grep -q '^MAIL_HOST=localhost$' "$env"
  grep -q '^QUEUE_CONNECTION=redis$' "$env"
}

@test "env rewrite: only the APP_URL line changes, others byte-identical" {
  local env="$TEST_TEMP_DIR/.env"
  printf 'A=1\nAPP_URL=old\nB=2\nC=3\n' > "$env"

  _run_real_update_env "$env" "https://x.test"

  run cat "$env"
  [ "${lines[0]}" = 'A=1' ]
  [ "${lines[1]}" = 'APP_URL=https://x.test' ]
  [ "${lines[2]}" = 'B=2' ]
  [ "${lines[3]}" = 'C=3' ]
}

@test "env rewrite: leaves a file without APP_URL unchanged (returns non-zero)" {
  local env="$TEST_TEMP_DIR/.env"
  printf 'A=1\nB=2\n' > "$env"

  run _run_real_update_env "$env" "https://x.test"
  [ "$status" -ne 0 ]

  run cat "$env"
  [ "${lines[0]}" = 'A=1' ]
  [ "${lines[1]}" = 'B=2' ]
}

@test "env rewrite: preserves keys whose values contain '=' and special chars" {
  local env="$TEST_TEMP_DIR/.env"
  cat > "$env" <<'EOF'
APP_URL=http://old.test
APP_KEY=base64:AAA=BBB=
MAIL_FROM="Acme <no-reply@acme.test>"
EOF

  _run_real_update_env "$env" "http://new.test"

  grep -q '^APP_URL=http://new.test$' "$env"
  grep -q '^APP_KEY=base64:AAA=BBB=$' "$env"
  grep -q '^MAIL_FROM="Acme <no-reply@acme.test>"$' "$env"
}
