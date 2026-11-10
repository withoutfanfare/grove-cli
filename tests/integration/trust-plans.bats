#!/usr/bin/env bats
load '../test-helper'
setup() { setup_test_environment; }
teardown() { teardown_test_environment; }

@test "prune plan excludes stale unmerged and checked-out branches and execution never expands scope" {
  git init -qb main "$TEST_TEMP_DIR/source"
  git -C "$TEST_TEMP_DIR/source" commit -qm initial --allow-empty
  git -C "$TEST_TEMP_DIR/source" branch merged
  git -C "$TEST_TEMP_DIR/source" branch other-merged
  git -C "$TEST_TEMP_DIR/source" checkout -qb stale-unmerged
  git -C "$TEST_TEMP_DIR/source" commit -qm unmerged --allow-empty
  git -C "$TEST_TEMP_DIR/source" checkout -q main
  git clone --bare -q "$TEST_TEMP_DIR/source" "$TEST_TEMP_DIR/bare.git"
  git --git-dir="$TEST_TEMP_DIR/bare.git" worktree add -q "$TEST_TEMP_DIR/occupied" other-merged
  run python3 "$GROVE_ROOT/tools/prune-plan.py" plan fixture "$TEST_TEMP_DIR/bare.git" main main
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$TEST_TEMP_DIR/plan-envelope.json"
  python3 - "$TEST_TEMP_DIR" <<'PY'
import json,sys
root=sys.argv[1]; p=json.load(open(root+'/plan-envelope.json'))['data']
assert [t['name'] for t in p['targets']]==['merged'],p
assert {s['name'] for s in p['skipped']}=={'main','other-merged','stale-unmerged'},p
json.dump(p,open(root+'/plan.json','w'))
PY
  run python3 "$GROVE_ROOT/tools/prune-plan.py" execute fixture "$TEST_TEMP_DIR/bare.git" main main "$TEST_TEMP_DIR/plan.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "deleted"'* ]]
  ! git --git-dir="$TEST_TEMP_DIR/bare.git" show-ref --verify --quiet refs/heads/merged
  git --git-dir="$TEST_TEMP_DIR/bare.git" show-ref --verify --quiet refs/heads/other-merged
  git --git-dir="$TEST_TEMP_DIR/bare.git" show-ref --verify --quiet refs/heads/stale-unmerged
}

@test "changed branch evidence refuses a confirmed prune plan" {
  git init -qb main "$TEST_TEMP_DIR/repo"
  git -C "$TEST_TEMP_DIR/repo" commit -qm initial --allow-empty
  git -C "$TEST_TEMP_DIR/repo" branch merged
  run python3 "$GROVE_ROOT/tools/prune-plan.py" plan fixture "$TEST_TEMP_DIR/repo/.git" main main
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys;json.dump(json.load(sys.stdin)["data"],open(sys.argv[1],"w"))' "$TEST_TEMP_DIR/plan.json"
  git -C "$TEST_TEMP_DIR/repo" commit -qm advanced --allow-empty
  run python3 "$GROVE_ROOT/tools/prune-plan.py" execute fixture "$TEST_TEMP_DIR/repo/.git" main main "$TEST_TEMP_DIR/plan.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *'Comparison base changed'* ]]
  git -C "$TEST_TEMP_DIR/repo" show-ref --verify --quiet refs/heads/merged
}

@test "bundled removal checker blocks failed Git queries and malformed leases" {
  mkdir -p "$TEST_TEMP_DIR/bin" "$TEST_TEMP_DIR/worktree"
  printf '#!/bin/sh\ncase "$*" in *--is-inside-work-tree*) echo true;; *--absolute-git-dir*) echo /fixture;; *) exit 128;; esac\n' > "$TEST_TEMP_DIR/bin/git"
  chmod +x "$TEST_TEMP_DIR/bin/git"
  run env PATH="$TEST_TEMP_DIR/bin:$PATH" python3 "$GROVE_ROOT/tools/wt-removal-check" "$TEST_TEMP_DIR/worktree"
  [ "$status" -eq 2 ]
  [[ "$output" == *'Unknown'* ]]
  git init -qb main "$TEST_TEMP_DIR/worktree"
  git -C "$TEST_TEMP_DIR/worktree" commit -qm initial --allow-empty
  printf 'not-json' > "$TEST_TEMP_DIR/worktree/.git/worktree-lease.json"
  run python3 "$GROVE_ROOT/tools/wt-removal-check" "$TEST_TEMP_DIR/worktree"
  [ "$status" -eq 2 ]
  [[ "$output" == *'Lease unreadable or malformed'* ]]
}

@test "native branch deletion refuses a worktree created after the last preview occupancy check" {
  git init -qb main "$TEST_TEMP_DIR/race"
  git -C "$TEST_TEMP_DIR/race" commit -qm initial --allow-empty
  git -C "$TEST_TEMP_DIR/race" branch candidate
  run python3 - "$GROVE_ROOT/tools/prune-plan.py" "$TEST_TEMP_DIR" <<'PY'
import importlib.util,json,sys
source,root=sys.argv[1:]
spec=importlib.util.spec_from_file_location('prune',source);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
bare=root+'/race/.git'; plan=module.plan('fixture',bare,'main',['main']); filename=root+'/plan.json';json.dump(plan,open(filename,'w'))
original=module.git; calls=0
def racing_git(directory,*args):
    global calls
    output=original(directory,*args)
    if args[:3]==('worktree','list','--porcelain'):
        calls+=1
        if calls==2:
            original(directory,'worktree','add',root+'/raced-worktree','candidate')
    return output
module.git=racing_git
result=module.execute('fixture',bare,'main',['main'],filename)
assert result['branches'][0]['status']=='refused',result
original(bare,'show-ref','--verify','refs/heads/candidate')
print('Concurrent checkout retained its branch')
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *'Concurrent checkout retained its branch'* ]]
}

@test "locked deletion rejects a changed tip and preserves the repository transaction hook" {
  git init -qb main "$TEST_TEMP_DIR/transaction"
  git -C "$TEST_TEMP_DIR/transaction" commit -qm initial --allow-empty
  git -C "$TEST_TEMP_DIR/transaction" branch candidate
  git -C "$TEST_TEMP_DIR/transaction" checkout -qb unmerged
  git -C "$TEST_TEMP_DIR/transaction" commit -qm unmerged --allow-empty
  git -C "$TEST_TEMP_DIR/transaction" checkout -q main
  run python3 - "$GROVE_ROOT/tools/prune-plan.py" "$TEST_TEMP_DIR" <<'PY'
import importlib.util,json,os,sys
source,root=sys.argv[1:]
spec=importlib.util.spec_from_file_location('prune',source);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
bare=root+'/transaction/.git'; p=module.plan('fixture',bare,'main',['main']); filename=root+'/transaction-plan.json';json.dump(p,open(filename,'w'))
hook=bare+'/hooks/reference-transaction'; marker=root+'/original-hook'
open(hook,'w').write('#!/bin/sh\necho "$1" >> "'+marker+'"\n[ "$1" != prepared ]\n');os.chmod(hook,0o700)
result=module.execute('fixture',bare,'main',['main'],filename)
assert result['branches'][0]['status']=='refused',result
assert 'prepared' in open(marker).read()
module.git(bare,'show-ref','--verify','refs/heads/candidate')
os.unlink(hook)
original=module.delete_confirmed
new_tip=module.git(bare,'rev-parse','unmerged')
def change_tip(directory,ref,sha,base,base_sha):
    module.git(directory,'update-ref',ref,new_tip,sha)
    return original(directory,ref,sha,base,base_sha)
module.delete_confirmed=change_tip
result=module.execute('fixture',bare,'main',['main'],filename)
assert result['branches'][0]['status']=='refused',result
assert module.git(bare,'rev-parse','candidate')==new_tip
print('Original hook and unconfirmed tip both preserved')
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *'Original hook and unconfirmed tip both preserved'* ]]
}

@test "a timed-out prune target remains unknown and retains earlier successful outcomes" {
  git init -qb main "$TEST_TEMP_DIR/outcomes"
  git -C "$TEST_TEMP_DIR/outcomes" commit -qm initial --allow-empty
  git -C "$TEST_TEMP_DIR/outcomes" branch a-completed
  git -C "$TEST_TEMP_DIR/outcomes" branch b-uncertain
  run python3 - "$GROVE_ROOT/tools/prune-plan.py" "$TEST_TEMP_DIR" <<'PY'
import importlib.util,json,subprocess,sys
source,root=sys.argv[1:]
spec=importlib.util.spec_from_file_location('prune',source);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
bare=root+'/outcomes/.git'; plan=module.plan('fixture',bare,'main',['main']); filename=root+'/outcome-plan.json';json.dump(plan,open(filename,'w'))
original=module.delete_confirmed
def timeout_second(directory,ref,*args):
    if ref.endswith('/b-uncertain'): raise subprocess.TimeoutExpired('git',20)
    return original(directory,ref,*args)
module.delete_confirmed=timeout_second
result=module.execute('fixture',bare,'main',['main'],filename)
assert [item['status'] for item in result['branches']]==['deleted','unknown'],result
assert 'Refresh before retrying' in result['branches'][1]['reason']
print('Completed result retained; timed-out outcome unknown')
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *'Completed result retained; timed-out outcome unknown'* ]]
}

@test "prune plan never targets the branch a bare repository's HEAD points at" {
  git init -qb develop "$TEST_TEMP_DIR/source"
  git -C "$TEST_TEMP_DIR/source" commit -qm initial --allow-empty
  git -C "$TEST_TEMP_DIR/source" branch release
  git -C "$TEST_TEMP_DIR/source" branch merged
  git clone --bare -q "$TEST_TEMP_DIR/source" "$TEST_TEMP_DIR/bare.git"
  run python3 "$GROVE_ROOT/tools/prune-plan.py" plan fixture "$TEST_TEMP_DIR/bare.git" release main
  [ "$status" -eq 0 ]
  OUTPUT="$output" python3 -c '
import json,os
plan = json.loads(os.environ["OUTPUT"])["data"]
assert [t["name"] for t in plan["targets"]] == ["merged"], plan'
}

@test "a failed occupancy recheck keeps earlier prune results" {
  git init -qb main "$TEST_TEMP_DIR/repo"
  git -C "$TEST_TEMP_DIR/repo" commit -qm initial --allow-empty
  git -C "$TEST_TEMP_DIR/repo" branch a
  git -C "$TEST_TEMP_DIR/repo" branch b
  run python3 - "$GROVE_ROOT/tools/prune-plan.py" "$TEST_TEMP_DIR" <<'PY'
import importlib.util,json,sys
spec = importlib.util.spec_from_file_location("prune_plan", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
root = sys.argv[2] + "/repo/.git"
plan = m.plan("fixture", root, "main", ["main"])
json.dump(plan, open(sys.argv[2] + "/plan.json", "w"))
real, calls = m.checked_out, []
def flaky(r):
    calls.append(r)
    if len(calls) == 3: raise RuntimeError("worktree listing failed")
    return real(r)
m.checked_out = flaky
result = m.execute("fixture", root, "main", ["main"], sys.argv[2] + "/plan.json")
assert [(b["name"], b["status"]) for b in result["branches"]] == [("a", "deleted"), ("b", "refused")], result
PY
  [ "$status" -eq 0 ]
}

@test "a malformed or missing prune plan returns the JSON error envelope" {
  git init -qb main "$TEST_TEMP_DIR/repo"
  git -C "$TEST_TEMP_DIR/repo" commit -qm initial --allow-empty
  printf '[]' > "$TEST_TEMP_DIR/bad.json"
  run python3 "$GROVE_ROOT/tools/prune-plan.py" execute fixture "$TEST_TEMP_DIR/repo/.git" main main "$TEST_TEMP_DIR/bad.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *PLAN_UNAVAILABLE* ]]
  run python3 "$GROVE_ROOT/tools/prune-plan.py" execute fixture "$TEST_TEMP_DIR/repo/.git" main main
  [ "$status" -eq 2 ]
  [[ "$output" == *PLAN_UNAVAILABLE* ]]
}

@test "bundled removal checker sees untracked files whatever the user's git config says" {
  git init -qb main "$TEST_TEMP_DIR/worktree"
  git -C "$TEST_TEMP_DIR/worktree" commit -qm initial --allow-empty
  git -C "$TEST_TEMP_DIR/worktree" config status.showUntrackedFiles no
  echo new > "$TEST_TEMP_DIR/worktree/NEVER_ADDED"
  run python3 "$GROVE_ROOT/tools/wt-removal-check" "$TEST_TEMP_DIR/worktree"
  [ "$status" -eq 1 ]
  [[ "$output" == *NEVER_ADDED* ]]
}
