#!/usr/bin/env bats
# template-load.bats - load_template against the REAL zsh source (the bash
# copy in test-helper.bash does not exercise lib/07-templates.sh).

load '../test-helper'

setup() {
  setup_test_environment
  export GROVE_TEMPLATES_DIR="$TEST_TEMP_DIR/templates"
  mkdir -p "$GROVE_TEMPLATES_DIR"
}

teardown() {
  teardown_test_environment
}

_load() {
  run zsh -c "
    source '$GROVE_ROOT/lib/00-header.sh'
    source '$GROVE_ROOT/lib/01-core.sh'
    source '$GROVE_ROOT/lib/02-validation.sh'
    source '$GROVE_ROOT/lib/07-templates.sh'
    load_template t
    print -r -- \"DB=\${GROVE_SKIP_DB:-unset} NPM=\${GROVE_SKIP_NPM:-unset} BUILD=\${GROVE_SKIP_BUILD:-unset}\"
  "
}

@test "load_template: quoted booleans with trailing comments apply" {
  cat > "$GROVE_TEMPLATES_DIR/t.conf" <<'CONF'
GROVE_SKIP_DB="true" # no database
GROVE_SKIP_NPM='false'   # keep npm
GROVE_SKIP_BUILD=true # plain
CONF
  _load
  [ "$status" -eq 0 ]
  [[ "$output" == *"DB=true NPM=false BUILD=true"* ]]
  [[ "$output" != *"Invalid value"* ]]
}

@test "load_template: injection stays rejected and unexecuted" {
  cat > "$GROVE_TEMPLATES_DIR/t.conf" <<CONF
GROVE_SKIP_DB=\$(touch $TEST_TEMP_DIR/pwned)
GROVE_SKIP_NPM="true; touch $TEST_TEMP_DIR/pwned"
GROVE_SKIP_BUILD=\`touch $TEST_TEMP_DIR/pwned\`
CONF
  _load
  [ "$status" -eq 0 ]
  [[ "$output" == *"Invalid value"* ]]
  [[ "$output" == *"DB=unset NPM=unset BUILD=unset"* ]]
  [ ! -e "$TEST_TEMP_DIR/pwned" ]
}
