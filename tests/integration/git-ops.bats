#!/usr/bin/env bats
# git-ops.bats - Integration tests for the real zsh implementations in
# lib/commands/git-ops.sh, exercised against real temp git repos.
#
# These guard the JSON data contract and parallel correctness fixes:
#   1. _pull_all_for_repo --json must emit VALID JSON even when `git pull --rebase`
#      output contains quotes, backslashes and newlines (a rebase conflict does).
#      The old code re-parsed the per-worktree message and re-embedded it WITHOUT
#      re-escaping, corrupting the JSON for the Tauri consumer.
#   2. cmd_prune --all-repos must route through the shared parallel_run helper and
#      process every repo when there are MORE repos than GROVE_MAX_PARALLEL, with
#      total == succeeded + failed.

load '../test-helper'

setup() {
  setup_test_environment

  # Build a sourceable zsh file that pulls in the REAL helpers we exercise, with
  # thin stubs for the cross-module dependencies that are not under test. We source
  # whole lib files (they only define functions) rather than extracting bodies,
  # because several function bodies contain column-0 '}' lines inside JSON strings.
  GIT_OPS_FNS="$TEST_TEMP_DIR/git-ops-fns.zsh"
  export GIT_OPS_FNS
  cat > "$GIT_OPS_FNS" <<'STUB'
QUIET=true
PRETTY_JSON=false
JSON_OUTPUT=false
GROVE_MAX_PARALLEL=4
NO_COLOR=1
C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""
C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""
info() { :; }
ok()   { print -r -- "OK:$*"; }
warn() { print -r -- "WARN:$*" >&2; }
dim()  { :; }
notify() { print -r -- "NOTIFY:$*" >&2; }
url_for() { print -r -- "https://example.test"; }
db_name_for() { print -r -- "db"; }
run_hooks() { :; }
error_exit() { print -r -- "ERR:$2" >&2; return "${3:-1}"; }
# Minimal faithful re-implementations of the two JSON readers from lib/01-core.sh
# (sourcing all of 01-core pulls in colour/config machinery we don't need here).
json_get_string() {
  local json="$1" key="$2"
  local pattern="\"$key\":\"([^\"]*)\""
  if [[ "$json" =~ $pattern ]]; then print -r -- "${match[1]}"; return 0; fi
  return 1
}
json_get_value() {
  local json="$1" key="$2"
  local pattern="\"$key\":([^,\"}]+)"
  if [[ "$json" =~ $pattern ]]; then
    local val="${match[1]}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    print -r -- "$val"; return 0
  fi
  return 1
}
STUB
  # Real helpers: json_escape/format_json, worktree iteration, and the commands.
  printf "source '%s/lib/07-templates.sh'\n"        "$GROVE_ROOT" >> "$GIT_OPS_FNS"
  printf "source '%s/lib/04-git.sh'\n"              "$GROVE_ROOT" >> "$GIT_OPS_FNS"
  printf "source '%s/lib/09-parallel.sh'\n"         "$GROVE_ROOT" >> "$GIT_OPS_FNS"
  printf "source '%s/lib/commands/git-ops.sh'\n"    "$GROVE_ROOT" >> "$GIT_OPS_FNS"

  # Keep test git invocations hermetic and English (LC_ALL=C parity with the code).
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=t@t.t
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=t@t.t
}

teardown() {
  teardown_test_environment
}

# Build a grove-style bare repo ($repo.git) with one linked worktree on `feature`
# whose upstream (origin/feature) has DIVERGED conflictingly, so `git pull --rebase`
# fails with conflict output that contains quotes, backslashes and newlines.
_setup_conflict_repo() {
  local root="$1"

  git init -q -b main --bare "$root/remote.git"
  git clone -q "$root/remote.git" "$root/seed"
  git -C "$root/seed" config user.email t@t.t
  git -C "$root/seed" config user.name Test
  printf 'line1\nline2\n' > "$root/seed/f.txt"
  git -C "$root/seed" add f.txt
  git -C "$root/seed" commit -qm init
  git -C "$root/seed" branch feature
  git -C "$root/seed" push -q origin main feature

  # The grove-style bare repo, with a standard origin fetch refspec.
  git clone -q --bare "$root/remote.git" "$root/repo.git"
  git --git-dir="$root/repo.git" config remote.origin.url "$root/remote.git"
  git --git-dir="$root/repo.git" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git --git-dir="$root/repo.git" fetch -q origin

  # Linked worktree on feature, tracking origin/feature.
  git --git-dir="$root/repo.git" worktree add -q "$root/wt-feature" feature
  git -C "$root/wt-feature" config user.email t@t.t
  git -C "$root/wt-feature" config user.name Test
  git -C "$root/wt-feature" branch --set-upstream-to=origin/feature feature >/dev/null 2>&1

  # Local commit whose SUBJECT carries the troublesome characters; the rebase
  # conflict output echoes the subject (with quotes/backslashes), giving us a
  # message field that the old re-embed path would have corrupted.
  printf 'line1\nLOCAL change\n' > "$root/wt-feature/f.txt"
  git -C "$root/wt-feature" commit -qam 'local "quoted" and \backslash\ change'

  # Conflicting upstream advance on origin/feature.
  git -C "$root/seed" checkout -q feature
  printf 'line1\nUPSTREAM change\n' > "$root/seed/f.txt"
  git -C "$root/seed" commit -qam 'upstream change'
  git -C "$root/seed" push -q origin feature
}

# ============================================================================
# #2 — _pull_all_for_repo --json: valid JSON with quoted/multiline pull output
# ============================================================================

@test "pull-all --json: emits valid JSON when pull output has quotes/backslashes/newlines" {
  local root="$TEST_TEMP_DIR/conflict"
  mkdir -p "$root"
  _setup_conflict_repo "$root"

  # Run the real _pull_all_for_repo in JSON mode against the conflicting worktree.
  run zsh -c "source '$GIT_OPS_FNS'; JSON_OUTPUT=true; _pull_all_for_repo 'repo' '$root/repo.git'"
  [ "$status" -eq 0 ]

  # The single line of stdout must be valid JSON (the critical data contract).
  printf '%s\n' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'

  # And the contract invariants must hold: total == succeeded + failed, the
  # conflicting worktree is reported as a failure, and the message survives intact.
  printf '%s\n' "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
s=d["summary"]
assert s["total"]==s["succeeded"]+s["failed"], s
assert s["total"]==1, s
assert s["failed"]==1, s
w=d["worktrees"][0]
assert w["branch"]=="feature", w
assert w["success"] is False, w
# The raw conflict message contained a double-quote, a backslash and newlines;
# json.load above already proved they were escaped correctly, but assert the
# decoded content actually round-tripped rather than being truncated at the first
# quote. (In the decoded string a literal backslash is a single "\\".)
assert "\"" in w["message"], w["message"]
assert "\\" in w["message"], w["message"]
assert "\n" in w["message"], w["message"]
'
}

@test "pull-all --json: no debug text leaks before the JSON object" {
  local root="$TEST_TEMP_DIR/conflict2"
  mkdir -p "$root"
  _setup_conflict_repo "$root"

  run zsh -c "source '$GIT_OPS_FNS'; JSON_OUTPUT=true; _pull_all_for_repo 'repo' '$root/repo.git'"
  [ "$status" -eq 0 ]
  # stdout must begin with '{' — a leaked `local var=...` would print `var=...` first.
  [[ "${output:0:1}" == "{" ]]
}

# ============================================================================
# #15 — cmd_prune --all-repos: parallel_run over more repos than GROVE_MAX_PARALLEL
# ============================================================================

@test "prune --all-repos: processes every repo when count exceeds GROVE_MAX_PARALLEL" {
  # Five bare repos, concurrency cap of two — every repo must still be pruned.
  local repo
  for repo in alpha bravo charlie delta echo; do
    git init -q -b main --bare "$HERD_ROOT/$repo.git"
  done

  run zsh -c "source '$GIT_OPS_FNS'; HERD_ROOT='$HERD_ROOT'; ALL_REPOS=true; GROVE_MAX_PARALLEL=2; cmd_prune"
  [ "$status" -eq 0 ]

  # One success line per repo (parallel_run reports via the stubbed ok()).
  [[ "$output" == *"OK:  alpha"* ]]
  [[ "$output" == *"OK:  bravo"* ]]
  [[ "$output" == *"OK:  charlie"* ]]
  [[ "$output" == *"OK:  delta"* ]]
  [[ "$output" == *"OK:  echo"* ]]

  # The summary notification reports all five as succeeded, none failed.
  [[ "$output" == *"5 success, 0 failed"* ]]
}
