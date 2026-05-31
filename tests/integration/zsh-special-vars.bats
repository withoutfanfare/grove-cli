#!/usr/bin/env bats
# zsh-special-vars.bats - Guard against shadowing zsh special parameters
# (path, status, prompt, options, cdpath, fpath, ...) with local/typeset/declare
# in lib/.
#
# In zsh these names are SPECIAL parameters. `local path=...` clobbers $PATH for
# the function scope, so external commands silently fail ("command not found").
# This bit `check_disk_space` / `lookup_worktree_path` and broke `grove add` in
# fresh non-interactive shells (cron, CI). The bash test-mirrors cannot catch it
# because the names are not special in bash, so this enforces it statically
# against the real zsh sources via tests/lint-zsh-special-vars.sh.

load '../test-helper'

@test "lib/ does not shadow zsh special parameters (path/status/prompt/options/...)" {
  run bash "$GROVE_ROOT/tests/lint-zsh-special-vars.sh" "$GROVE_ROOT/lib"
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output"
    false
  fi
}
