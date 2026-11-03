#!/usr/bin/env bats
load '../test-helper'
setup() { setup_test_environment; }
teardown() { teardown_test_environment; }
@test "config reports environment root and repository values from selected file layers" {
  mkdir -p "$TEST_TEMP_DIR/root/fixture.git" "$TEST_TEMP_DIR/home"
  printf 'HERD_ROOT=/incorrect\nDEFAULT_BASE=global\n' > "$TEST_TEMP_DIR/selected"
  printf 'DEFAULT_BASE=project\n' > "$TEST_TEMP_DIR/root/.groveconfig"
  printf 'DEFAULT_BASE=topic-base\nGROVE_URL_SUBDOMAIN=api\n' > "$TEST_TEMP_DIR/root/fixture.git/.groveconfig"
  git init --bare -q "$TEST_TEMP_DIR/root/fixture.git"
  run env HERD_ROOT="$TEST_TEMP_DIR/root" GROVE_CONFIG="$TEST_TEMP_DIR/selected" zsh -c '
    for module in "$GROVE_ROOT"/lib/[0-9][0-9]-*.sh; do [[ "$module" == */99-main.sh ]] || source "$module"; done
    source "$GROVE_ROOT/lib/commands/config.sh"
    load_config
    JSON_OUTPUT=true
    cmd_config fixture'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,os,sys; d=json.load(sys.stdin)["data"]; assert d["herd_root"]==os.environ["TEST_TEMP_DIR"]+"/root",d; assert d["default_base_branch"]=="topic-base",d; assert d["config_sources"]["HERD_ROOT"]=="environment",d; assert d["config_sources"]["DEFAULT_BASE"].endswith("fixture.git/.groveconfig"),d'
}
