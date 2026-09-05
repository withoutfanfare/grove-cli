# Grove CLI review and improvement plan

Reviewed on 4 September 2026 against `develop` at `aee2213`. The four findings are now implemented in the current working tree. The original evidence below is retained as historical review evidence.

## Scope and approach

Reviewed lifecycle and target resolution, hooks, bulk execution, status and ledger integration, upgrade handling, command parsing, and test coverage. This is a prioritised review, not an exhaustive security audit. The findings were checked against the source reviewed at the time and reproduced with the generated CLI in disposable local Git repositories. No production repositories, databases, hooks, or services were used.

The existing review documents contain historical findings whose fixes are already present. This document records current findings; it does not treat old unchecked lists as current defects.

## 1. P1 — Require an exact worktree identity before removal

**Disposition: implemented.** Existing-worktree commands now require an exact registered Git identity. Computed paths remain available only for creation. Missing, mismatched, detached, and colliding branch identities fail before hooks or mutations.

**Locations:** `lib/commands/lifecycle.sh:374-385`; shared fallback in `lib/03-paths.sh:148-160`.

`cmd_rm` uses `resolve_worktree_path`, which falls back to a computed folder when Git has no worktree for the requested branch. Branch names can produce the same folder name. Removal then checks protection against the requested branch, rather than the branch actually checked out in the resolved directory.

**Reproduced:** a clean worktree on `feature/collision`, stored at `demo-worktrees/feature-collision`, was removed by `grove rm demo feature-collision --json`. The requested branch did not exist. The command exited 0 and reported successful removal without `--force`.

Also reproduced with a protected branch: a `main` worktree at `demo-worktrees/demo` was removed by `grove rm demo demo --json`, again without `--force`. Its Git branch remained, but its worktree directory was deleted. Ledger integration was explicitly off, a supported configuration; the optional ledger must not be the only protection against resolving the wrong target.

**Original suggested change:** existing-worktree operations must resolve an exact Git worktree record and reject missing or mismatched identities before hooks or mutations. Keep computed paths for creation. Audit sibling callers such as `move`, `exec`, `fresh`, `pull`, and `sync`, which use the same fallback. Base protection checks on the verified record.

**Original acceptance checks:** slash/dash collisions, case collisions, nonexistent branches, protected-branch folder aliases, and detached targets must never silently select another worktree. Legitimate `--dir` and moved worktrees must still resolve through Git. Assert hook non-execution and unchanged directories/refs on rejection.

## 2. P1 — Preserve the database and URL selected by `add --dir`

**Disposition: implemented.** New worktrees store the selected database in the per-worktree Git administrative `grove-database` file, which survives folder moves. Legacy worktrees use a literal `DB_DATABASE` from `.env`; otherwise the canonical branch fallback is accepted only for an unambiguous canonical folder. Ambiguous renamed or aliased folders fail with `DATABASE_UNKNOWN` until the database is confirmed and recorded.

**Locations:** creation at `lib/commands/lifecycle.sh:124-143`; removal at `lib/commands/lifecycle.sh:375-377`; sibling calculations in `cmd_move` and `lib/commands/discovery.sh:42-43`.

Creation derives the database and URL from the custom directory alias. Removal resolves the correct directory, but derives the hook database and URL afresh from the branch name. The bundled backup and drop hooks act on `GROVE_DB_NAME`, so this can skip the intended backup, leave the real database behind, or act on another database if that derived name exists.

**Reproduced:** `add demo feature/long-name main --dir short --force --json` reported database `demo__short` and URL `https://short.test`. A recording `pre-rm` hook subsequently received `demo__feature_long_name` and `https://feature-long-name.test`. The hook exited 1 to prevent deletion; no database commands ran.

**Original suggested change:** resolve lifecycle metadata consistently and preserve the database identity chosen at creation. Follow the existing per-worktree metadata pattern where appropriate. Do not simply derive the database from the current folder: a subsequent move can change the folder while the database remains the same. Define a compatibility fallback for existing worktrees and use it consistently in hooks and information commands.

**Original acceptance checks:** add with an alias, inspect, move, and remove; assert that backup/drop hooks receive the intended database throughout. Use recording hooks or stub database binaries. Cover an existing unrelated database with the branch-derived name and verify it is never selected.

## 3. P1 — Keep new-branch JSON output parseable

**Disposition: implemented.** New-branch notices now go to stderr. Dirty `rm --json` requests return `DIRTY_WORKTREE` without prompting. Explicit `--force` keeps the independent Worktree Ledger gate, and the published JSON result and error shapes are unchanged.

**Location:** `lib/commands/lifecycle.sh:247-260`.

The new-branch warning block writes directly to stdout before the result object. `--force` bypasses the refusal but does not suppress the explanatory text. The earlier branch-creation refusal path also mixes prose with its JSON error.

**Reproduced:** `add demo feature/long-name main --dir short --force --json` exited 0 but stdout began with `This will CREATE a new branch from main`, followed by the JSON object. A consumer cannot parse the complete stdout as JSON, even though the worktree has already been created.

**Original suggested change:** send explanatory output to stderr and reserve stdout for one JSON document. Also check dirty-worktree removal prompts and other lifecycle branches that use direct `print` or `git status` calls. Define non-interactive behaviour for JSON requests requiring a decision.

**Original acceptance checks:** parse the entire stdout for successful new-branch creation, existing-branch creation, refused creation, and dirty removal. Assert the exit status and actual filesystem outcome. The current `--dir` JSON integration test creates its branch in advance, which avoids this new-branch path.

## 4. P2 — Retain the executable in `exec-all --all-repos`

**Disposition: implemented.** All-repository mode no longer consumes the executable after global flag parsing.

**Location:** `lib/commands/bulk-ops.sh:128-133`.

Global flag parsing removes `--all-repos` before dispatch. The multi-repository branch then shifts once more as though a repository argument were present, discarding the executable.

**Reproduced:** `grove exec-all --all-repos true` exited 2 with a usage error. `grove exec-all --all-repos printf hello` announced `Executing 'hello' across all repositories`, confirming that `printf` had been discarded. The latter execution also encountered a sandbox `nice(5)` restriction; the argument-loss finding is independently established by the first reproduction and the captured command string.

**Original suggested change:** do not consume a repository positional argument in all-repository mode. Preserve existing single-repository and group argument handling.

**Original acceptance checks:** single-word and multiword commands, the `--` sentinel, multiple repositories, empty repository sets, and a failing worker. Check command effects in every intended worktree, not merely summary text.

## Deferred suggestions

1. **Test the real Zsh functions instead of Bash copies.** `tests/test-helper.bash:60` onwards reimplements production helpers; `tests/unit/database.bats` carries another database-name implementation. These can stay green when production code changes. Gradually migrate affected tests to source the real modules in `zsh`, following the newer integration tests. Add the lifecycle combinations above first.
2. **Retain useful bulk-operation errors.** `lib/09-parallel.sh` discards worker stdout and stderr and retains only success/failure. Capture per-worker output in its existing temporary directory and show a bounded stderr excerpt on failure, with explicit cleanup. This would make a failed build actionable without manually repeating it in every worktree.
3. **Automate release checks on macOS.** No `.github` workflow is present in this checkout. If GitHub Actions is the intended CI platform, add a macOS gate for lint, BATS, source/generated artefact parity, and full-stdout JSON parsing. Avoid a packaging or language rewrite; the modular Zsh implementation already supports focused fixes.

The test-helper migration, bounded worker diagnostics, and a macOS CI gate remain separate improvements. They are not required to close the four findings above.

## Verification

### Implementation verification

- `./run-tests.sh lint`: passed with `Static analysis passed`, including Zsh parsing and ShellCheck.
- BATS coverage across split runs: **618 passed, 9 skipped, 0 unresolved failures** across 627 cases. The final `bats --tap` run selected every unit and integration file except `parallel-collect.bats`: 606 passed, 9 skipped, exit 0 (`/private/tmp/grove-final-tests.log`). All 12 unchanged parallel-collector cases passed in the preceding run (`/private/tmp/grove-implementation-tests.log`), whose wrapper timed out after 300 seconds. These tests have slow watchdog waits; this is split-run evidence, not a claim that one full-suite invocation completed. Temporary logs are local evidence and may be cleared by the operating system.
- The test environment used an isolated home and temporary `ZDOTDIR` with `unsetopt BG_NICE` to avoid the sandbox background-priority restriction. Skips cover unavailable or deliberately unbundled npm, MySQL, PHP, Herd and local-hook integrations.
- All 12 new lifecycle/identity regressions passed, including branch collisions, detached targets, JSON refusals, aliased database identity through pull/sync/move/removal, configured subdomains, legacy metadata and a dangling sidecar. Bulk execution regressions cover executable retention, multiple repositories, the `--` sentinel and worker failure.
- A disposable real-CLI matrix parsed the complete stdout of 17 supported JSON commands as a single document, with successful exit statuses. Pull and sync JSON were additionally exercised by the lifecycle regression.
- Rebuilt `grove` through `./build.sh`; a separate temporary build matched it byte for byte. `git diff --check` passed.
- Independent code review passed after correcting and retesting configured subdomain precedence. The changes remain uncommitted. No background server or service was started; test subprocesses have stopped.

### Original review verification

The entries below describe the original review and reproduction work before implementation.

- Rebuilt into a temporary output path: byte-for-byte identical to the checked-in `grove` executable.
- Reproduced all four findings using disposable local Git fixtures and the real CLI. Database evidence used a recording hook that vetoed deletion.
- Confirmed both slash/dash target confusion and the protected-`main` variant. Only disposable worktrees were deleted; their temporary repositories were cleaned up.
- `./run-tests.sh lint`: passed, including Zsh parse checks and ShellCheck for the Bash scripts and hooks.
- Selected integration coverage: `commands.bats`, `lifecycle.bats`, `add-push.bats`, `ledger.bats`, `bulk-ops.bats`, and `build.bats` — 104 cases selected. The 58 non-ledger cases produced 57 passes and one intentional skip (a real npm build).
- The initial ledger run encountered sandbox `nice(5)` warnings on background launches, contaminating BATS' combined stdout/stderr JSON input. A focused diagnostic confirmed this cause. All 46 ledger tests then passed with `unsetopt BG_NICE` in a temporary `.zshenv` supplied through `ZDOTDIR`; production code and the tests were unchanged. Combined verified coverage: 103 passed, one skipped. This is not a full-suite pass.
- No source edits, commits, or background servers were created.
