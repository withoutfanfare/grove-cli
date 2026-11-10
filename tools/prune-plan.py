#!/usr/bin/env python3
"""Non-mutating branch plans and exact, revalidated execution for Grove."""
import datetime
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def git(root, *args):
    result = subprocess.run(["git", "--git-dir=" + root, *args], capture_output=True, text=True, timeout=20)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Git check failed: " + args[0])
    return result.stdout.strip()


def checked_out(root):
    refs = {line[7:] for line in git(root, "worktree", "list", "--porcelain").splitlines() if line.startswith("branch ")}
    # A bare repository's own HEAD branch has no "branch" line in that listing.
    head = git(root, "branch", "--show-current")
    return refs | {"refs/heads/" + head} if head else refs


def plan(repo, root, base, protected):
    base_sha = git(root, "rev-parse", "--verify", base + "^{commit}")
    comparison_ref = git(root, "rev-parse", "--symbolic-full-name", base)
    occupied = checked_out(root)
    merged = set(git(root, "for-each-ref", "--merged=" + base_sha, "--format=%(refname)", "refs/heads/").splitlines())
    targets, skipped = [], []
    for line in git(root, "for-each-ref", "--format=%(refname) %(objectname)", "refs/heads/").splitlines():
        ref, sha = line.split(" ", 1)
        name = ref.removeprefix("refs/heads/")
        reason = "Comparison base" if ref == comparison_ref else "Protected branch" if name in protected else "Checked out in a worktree" if ref in occupied else "Not merged into the comparison base" if ref not in merged else None
        if reason:
            skipped.append({"name": name, "reason": reason})
        else:
            targets.append({"kind": "branch", "ref": ref, "name": name, "sha": sha})
    # Registration cleanup is intentionally excluded from this branch-only operation.
    # A global git worktree prune could expand beyond the displayed target list.
    return {"schema_version": 1, "repo": repo, "git_dir": os.path.realpath(root), "base_ref": base, "base_sha": base_sha,
            "checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "evidence_state": "clear",
            "targets": targets, "skipped": skipped, "stale_registrations": []}


def delete_confirmed(root, ref, sha, base, base_sha):
    # Git's native worktree guard remains in charge. A transaction hook adds
    # expected-SHA validation at the locked ref update, so branch tracking
    # configuration cannot approve a concurrently changed, unconfirmed tip.
    original_dir = git(root, "rev-parse", "--git-path", "hooks")
    original = os.path.join(original_dir, "reference-transaction")
    if not os.path.isabs(original):
        original = os.path.join(root, original)
    payload = {"root": root, "ref": ref, "sha": sha, "base": base, "base_sha": base_sha, "original": original}
    hook_source = r'''#!/usr/bin/env python3
import json,os,subprocess,sys
p=json.loads(os.environ["GROVE_PRUNE_TRANSACTION"])
text=sys.stdin.read()
original=p["original"]
if os.path.isfile(original) and os.access(original,os.X_OK):
    result=subprocess.run([original,*sys.argv[1:]],input=text,text=True)
    if result.returncode: sys.exit(result.returncode)
if sys.argv[1] != "prepared": sys.exit(0)
def git(*args):
    result=subprocess.run(["git","--git-dir="+p["root"],*args],capture_output=True,text=True,timeout=10)
    if result.returncode: raise RuntimeError(result.stderr.strip() or "Git safety check failed")
    return result.stdout.strip()
try:
    changes=[line.split() for line in text.splitlines()]
    if len(changes)!=1 or len(changes[0])!=3: raise RuntimeError("Unexpected branch transaction")
    old,new,ref=changes[0]
    if ref!=p["ref"] or old not in (p["sha"], "0"*len(p["sha"])) or len(new)!=len(p["sha"]) or any(c!='0' for c in new): raise RuntimeError("Confirmed branch changed; preview again")
    if git("rev-parse","--verify",ref)!=p["sha"]: raise RuntimeError("Confirmed branch changed; preview again")
    if git("rev-parse","--verify",p["base"]+"^{commit}")!=p["base_sha"]: raise RuntimeError("Comparison base changed; preview again")
    if "branch "+ref in git("worktree","list","--porcelain").splitlines(): raise RuntimeError("Branch is now checked out")
except Exception as error:
    print(str(error),file=sys.stderr);sys.exit(1)
'''
    with tempfile.TemporaryDirectory(prefix="grove-prune-hook-") as hooks:
        hook = Path(hooks) / "reference-transaction"
        hook.write_text(hook_source)
        hook.chmod(0o700)
        env = os.environ.copy()
        env["GROVE_PRUNE_TRANSACTION"] = json.dumps(payload)
        result = subprocess.run(["git", "--git-dir="+root, "-c", "core.hooksPath="+hooks,
                                 "branch", "--delete", "--force", "--", ref.removeprefix("refs/heads/")],
                                capture_output=True, text=True, timeout=20, env=env)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or "Git refused branch deletion")


def execute(repo, root, base, protected, filename):
    with open(filename) as source:
        confirmed = json.load(source)
    if confirmed.get("schema_version") != 1 or confirmed.get("evidence_state") != "clear" or confirmed.get("repo") != repo or confirmed.get("git_dir") != os.path.realpath(root):
        raise RuntimeError("Plan identity is invalid; preview again")
    current = plan(repo, root, base, protected)
    if confirmed.get("base_ref") != current["base_ref"] or confirmed.get("base_sha") != current["base_sha"]:
        raise RuntimeError("Comparison base changed; preview again")
    available = {(item["ref"], item["sha"]) for item in current["targets"]}
    targets = confirmed.get("targets")
    if not isinstance(targets, list) or len(targets) > 10000:
        raise RuntimeError("Invalid target list")
    seen = set()
    for item in targets:
        pair = (item.get("ref"), item.get("sha"))
        if pair not in available or pair[0] in seen:
            raise RuntimeError("A confirmed branch changed, became protected or is checked out; preview again")
        seen.add(pair[0])
    results = []
    for index, item in enumerate(targets):
        ref, sha = item["ref"], item["sha"]
        name = ref.removeprefix("refs/heads/")
        try:
            # Recheck at the write boundary, then let Git enforce its checked-out-branch guard.
            occupied = checked_out(root)
        except (subprocess.TimeoutExpired, RuntimeError, OSError) as error:
            # Nothing was deleted here, and a listing that failed once would fail for every later branch too.
            reason = "Could not list worktrees, so nothing further was deleted: " + str(error)
            results.extend({"name": rest["ref"].removeprefix("refs/heads/"), "status": "refused", "reason": reason} for rest in targets[index:])
            break
        try:
            if ref in occupied:
                results.append({"name": name, "status": "refused", "reason": "Branch is now checked out"})
                continue
            if git(root, "rev-parse", "--verify", ref) != sha:
                raise RuntimeError("Confirmed branch changed; preview again")
            delete_confirmed(root, ref, sha, base, confirmed["base_sha"])
            results.append({"name": name, "status": "deleted"})
        except subprocess.TimeoutExpired:
            results.append({"name": name, "status": "unknown", "reason": "Command deadline exceeded; the branch may already have changed. Refresh before retrying"})
        except (RuntimeError, OSError) as error:
            results.append({"name": name, "status": "refused", "reason": str(error)})
    return {"repo": repo, "base": base, "branches": results, "stale_refs_pruned": 0}


def main():
    mode, repo, root, base, protected, *rest = sys.argv[1:]
    try:
        data = plan(repo, root, base, protected.split()) if mode == "plan" else execute(repo, root, base, protected.split(), rest[0])
        print(json.dumps({"success": True, "data": data}))
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"success": False, "error": {"code": "PLAN_UNAVAILABLE", "message": str(error)}}))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
