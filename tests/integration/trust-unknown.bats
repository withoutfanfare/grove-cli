#!/usr/bin/env bats
load '../test-helper'
setup() { setup_test_environment; }
teardown() { teardown_test_environment; }
@test "failed comparison remains unknown in counts stale and ancestry" {
  run zsh -c '
    source "$GROVE_ROOT/lib/04-git.sh"
    GROVE_UNKNOWN="?"
    validate_git_ref() { return 0; }
    cached_base_behind() { return 1; }
    git() { [[ "$*" == *rev-parse* ]] && return 0; return 128; }
    get_commits_behind /fixture main
    get_ahead_behind /fixture main
    is_branch_stale /fixture main 5
    is_branch_merged /fixture main
    print -- "merge:$?"
  '
  [ "$status" -eq 0 ]
  [ "$output" = $'?\n? ?\nnull\nmerge:2' ]
}

@test "health cannot award a healthy grade when comparisons or status checks fail" {
  run zsh -c '
    for module in "$GROVE_ROOT"/lib/[0-9][0-9]-*.sh; do [[ "$module" == */99-main.sh ]] || source "$module"; done
    source "$GROVE_ROOT/lib/commands/info.sh"
    worktree_base_for() { print main; }
    get_commits_behind() { print "?"; }
    get_cached_status() { return 1; }
    git() { return 128; }
    get_commit_age_days() { print 0; }
    is_branch_merged() { return 2; }
    calculate_health_score /fixture'
  [ "$status" -eq 0 ]
  [[ "$output" == '?|0|'* ]]
  [[ "$output" == *behind-unknown* ]]
  [[ "$output" == *status-unknown* ]]
  [[ "$output" == *merge-unknown* ]]
}
