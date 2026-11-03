#!/usr/bin/env bats
load '../test-helper'

setup() {
  setup_test_environment
  export WT_A="$TEST_TEMP_DIR/a" WT_B="$TEST_TEMP_DIR/b"
  git init -q "$WT_A"
  git -C "$WT_A" commit -qm initial --allow-empty
  git -C "$WT_A" branch old
  for i in {1..12}; do git -C "$WT_A" commit -qm advance --allow-empty; done
  git -C "$WT_A" branch newer
  git -C "$WT_A" worktree add -qb sibling "$WT_B" newer
  export FNS="$TEST_TEMP_DIR/functions.zsh"
  cat > "$FNS" <<'ZSH'
for module in "$GROVE_ROOT"/lib/[0-9][0-9]-*.sh; do
  [[ "$module" == */99-main.sh ]] || source "$module"
done
source "$GROVE_ROOT/lib/commands/info.sh"
source "$GROVE_ROOT/lib/commands/navigation.sh"
DEFAULT_BASE=old
JSON_OUTPUT=true
GROVE_STALE_THRESHOLD=5
set_worktree_base "$WT_A" newer
set_worktree_base "$WT_B" old
ZSH
}
teardown() { teardown_test_environment; }

@test "health and ls/status rows compare each worktree with its own base" {
  run zsh -c '
    source "$FNS"
    for wt in "$WT_A" "$WT_B"; do
      calculate_health_score "$wt"
      _display_worktree 1 "$wt" feature "" repo
      print -r -- "$REPLY"
      _display_status_row "$wt" feature repo 5 30
      print -r -- "$REPLY"
    done'
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | python3 -c '
import json,sys
lines=sys.stdin.read().splitlines()
assert lines[0]=="A|100|", lines
assert "unmerged" in lines[3], lines
for i,merged in [(1,True),(2,True),(4,False),(5,False)]:
    assert json.loads(lines[i])["merged"] is merged, lines
'
  # Reverse the worktree tips to exercise behind/stale against newer.
  git -C "$WT_A" checkout -q --detach old
  run zsh -c 'source "$FNS"; calculate_health_score "$WT_A"; _display_worktree 1 "$WT_A" feature "" repo; print -r -- "$REPLY"; _display_status_row "$WT_A" feature repo 5 30; print -r -- "$REPLY"'
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | python3 -c 'import json,sys; x=sys.stdin.read().splitlines(); assert "behind:12" in x[0]; assert all(json.loads(v)["stale"] for v in x[1:])'
}

@test "switch passes recorded database identity without launching applications" {
  run zsh -c '
    source "$FNS"
    set_worktree_database "$WT_A" retained_database
    resolve_repo_arg() { print repo; }
    resolve_branch_ref() { print feature; }
    resolve_worktree_path() { print -r -- "$WT_A"; }
    worktree_url() { print https://fixture.test; }
    run_hooks() { print -r -- "database=$6"; }
    nohup() { :; }
    DEFAULT_EDITOR=true
    cmd_switch repo feature'
  [ "$status" -eq 0 ]
  [[ "$output" == *"database=retained_database"* ]]
}

@test "example switch hook refuses missing database before changing env" {
  printf 'APP_URL=old\nSESSION_DOMAIN=old\nDB_DATABASE=retained\n' > "$WT_A/.env"
  cp "$WT_A/.env" "$TEST_TEMP_DIR/expected"
  run env HOME="$TEST_TEMP_DIR/home" GROVE_PATH="$WT_A" GROVE_URL=https://new.test GROVE_DB_NAME= DB_CREATE=true bash "$GROVE_ROOT/examples/hooks/post-switch.d/myapp/01-configure-env.sh"
  [ "$status" -ne 0 ]
  cmp "$WT_A/.env" "$TEST_TEMP_DIR/expected"
}
