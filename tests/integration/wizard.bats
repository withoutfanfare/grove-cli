#!/usr/bin/env bats
# wizard.bats - interactive_add / interactive_dashboard behaviour against the
# REAL lib sources, with fzf, git and every side-effecting command stubbed.
# Nothing here touches a real repository, database or network.

load '../test-helper'

setup() {
  setup_test_environment
  export GROVE_TEMPLATES_DIR="$TEST_TEMP_DIR/templates"
  mkdir -p "$GROVE_TEMPLATES_DIR"
}

teardown() {
  teardown_test_environment
}

# Run interactive_add with stdin from $1. fzf picks come from FZF_PICKS
# (one line per fzf call, "status:selection"); calls are counted in a file
# because fzf runs inside a command substitution.
_wizard() {
  cat > "$TEST_TEMP_DIR/wizard.zsh" <<'ZSH'
GROVE_BASE_DEFAULT=origin/main
source "$GROVE_ROOT/lib/00-header.sh"
source "$GROVE_ROOT/lib/01-core.sh"
source "$GROVE_ROOT/lib/02-validation.sh"
source "$GROVE_ROOT/lib/07-templates.sh"
source "$GROVE_ROOT/lib/10-interactive.sh"
fzf() {
  cat >/dev/null
  local -a picks=("${(@f)FZF_PICKS}")
  print -n x >> "$TEST_TEMP_DIR/fzf-calls"
  local n; n=$(wc -c < "$TEST_TEMP_DIR/fzf-calls")
  local pick="${picks[n]}"
  [[ -n "${pick#*:}" ]] && print -r -- "${pick#*:}"
  return "${pick%%:*}"
}
list_repos() { print app; }
git_dir_for() { print /nonexistent/app.git; }
ensure_bare_repo() { :; }
load_repo_config() { :; }
with_spinner() { :; }
git() {
  case "$*" in
    *'branch -r'*) print origin/main ;;
    check-ref-format*) command git "$@" ;;
    *) return 1 ;;
  esac
}
worktree_path_for() { print /tmp/wt; }
url_for() { print https://x.test; }
db_name_for() { print db; }
cmd_add() { print -r -- "CMD_ADD $*"; }
interactive_add app
ZSH
  run timeout 10 zsh "$TEST_TEMP_DIR/wizard.zsh" <<< "$1"
}

@test "wizard: invalid branch name reprompts instead of exiting" {
  export FZF_PICKS=$'0:origin/main'
  _wizard $'../bad\nfeature/ok\ny'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Invalid branch name"* ]]
  [[ "$output" == *"CMD_ADD app feature/ok origin/main"* ]]
}

@test "wizard: EOF at branch name cancels with nonzero status" {
  export FZF_PICKS=$'0:origin/main'
  _wizard ""
  [ "$status" -ne 124 ]
  [ "$status" -ne 0 ]
  [[ "$output" == *"cancelled"* ]]
  [[ "$output" != *"CMD_ADD"* ]]
}

@test "wizard: EOF at confirmation does not create" {
  export FZF_PICKS=$'0:origin/main'
  _wizard $'feature/ok'
  [ "$status" -ne 0 ]
  [[ "$output" != *"CMD_ADD"* ]]
}

@test "wizard: escape at base picker aborts" {
  export FZF_PICKS=$'130:'
  _wizard $'feature/ok\ny'
  [ "$status" -ne 0 ]
  [[ "$output" != *"CMD_ADD"* ]]
}

@test "wizard: escape at template picker aborts" {
  : > "$GROVE_TEMPLATES_DIR/laravel.conf"
  export FZF_PICKS=$'0:origin/main\n130:'
  _wizard $'feature/ok\ny'
  [ "$status" -ne 0 ]
  [[ "$output" != *"CMD_ADD"* ]]
}

@test "wizard: explicit (none) template still proceeds" {
  : > "$GROVE_TEMPLATES_DIR/laravel.conf"
  export FZF_PICKS=$'0:origin/main\n0:(none)'
  _wizard $'feature/ok\ny'
  [ "$status" -eq 0 ]
  [[ "$output" == *"No template selected"* ]]
  [[ "$output" == *"CMD_ADD app feature/ok origin/main"* ]]
}

@test "dashboard: no placeholder REFRESH reload binding" {
  ! grep -q 'REFRESH' "$GROVE_ROOT/lib/10-interactive.sh"
}
