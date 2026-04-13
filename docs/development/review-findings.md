# Grove-CLI Code Review Findings

**Date**: 2026-02-07
**Branch**: develop
**Reviewed**: ~8,800 lines across 22 source modules
**Agents**: Bug detection (core libs), Bug detection (commands), Performance, Code quality

---

## Critical Bugs (Must Fix)

### BUG-01: Undefined variable in cmd_health .env check
- **File**: `lib/commands/info.sh:1065`
- **Severity**: Critical
- **Status**: [ ] Pending
- **Problem**: Variable `$path` is used but never defined - should be `$wt_path`. Outputs empty string instead of worktree name.
- **Fix**: Change `${path##*/}` to `${wt_path##*/}`
- **Verify**: `./grove health <repo>` and check .env warning output displays worktree names

### BUG-02: Config file permission race condition in cmd_setup
- **File**: `lib/commands/config.sh:414-439`
- **Severity**: Critical
- **Status**: [ ] Pending
- **Problem**: Config file created with default permissions (644) before `chmod 600`. Password appended after chmod which may fail silently. Window where password is world-readable.
- **Fix**: Create file with restrictive umask: `(umask 077; cat > "$config_file" << EOF ... EOF)` OR set umask before the heredoc and restore after.
- **Verify**: `ls -la ~/.groverc` after `./grove setup` shows `-rw-------` permissions

### BUG-03: cmd_clone --json returns exit code 0 on failure
- **File**: `lib/commands/lifecycle.sh:483`
- **Severity**: Critical
- **Status**: [ ] Pending
- **Problem**: `return 0` after outputting JSON failure message. Callers (including grove-app Tauri desktop) cannot detect clone failures via exit codes.
- **Fix**: Change `return 0` to `return 1` on the failure path (line 483)
- **Verify**: `./grove clone invalid-url --json; echo $?` should output non-zero exit code

---

## High Priority Bugs

### BUG-04: Missing Linux fallback for stat in fetch cache
- **File**: `lib/04-git.sh:27`
- **Severity**: High
- **Status**: [ ] Pending
- **Problem**: Uses macOS-specific `stat -f %m` without Linux `stat -c %Y` fallback. Fetch cache feature breaks on Linux.
- **Fix**: Add fallback: `cache_time="$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)" || return 1`
- **Verify**: Ensure existing macOS behaviour unchanged. If Linux available, test there too.

### BUG-05: Floating-point arithmetic failure with set -e
- **File**: `lib/12-deps.sh:329-334`
- **Severity**: High
- **Status**: [ ] Pending
- **Problem**: `$((saved_bytes / 1073741824.0))` uses floating-point which evaluates to 0.0 (falsy) for small values, causing early exit with `set -e`.
- **Fix**: Use integer-only arithmetic with conditional formatting:
  ```zsh
  if (( saved_bytes >= 1073741824 )); then
    saved_human="$(( saved_bytes / 1073741824 ))G"
  elif (( saved_bytes >= 1048576 )); then
    saved_human="$(( saved_bytes / 1048576 ))M"
  else
    saved_human="$(( saved_bytes / 1024 ))K"
  fi
  ```
- **Verify**: `./grove share-deps --cleanup` with small cache sizes doesn't exit prematurely

### BUG-06: Missing validate_name after fzf branch selection (14+ commands)
- **File**: Multiple - see list below
- **Severity**: High
- **Status**: [ ] Pending
- **Problem**: After `select_branch_fzf`, branch is used without `validate_name`. Inconsistent with security model.
- **Affected commands**:
  - `lib/commands/navigation.sh` - cmd_code, cmd_open, cmd_cd, cmd_switch
  - `lib/commands/lifecycle.sh` - cmd_rm, cmd_move, cmd_fresh
  - `lib/commands/git-ops.sh` - cmd_pull, cmd_sync, cmd_log, cmd_diff, cmd_summary, cmd_changes
  - `lib/commands/laravel.sh` - cmd_migrate, cmd_tinker
- **Fix**: Add `validate_name "$branch" "branch"` immediately after every `select_branch_fzf` call
- **Pattern**:
  ```zsh
  branch="$(select_branch_fzf "$repo" "...")" || die "No branch selected"
  validate_name "$branch" "branch"  # ADD THIS LINE
  ```
- **Verify**: Run tests, ensure fzf selection still works for valid branches

---

## Medium Priority Bugs

### BUG-07: Spinner/transaction EXIT trap conflict
- **File**: `lib/08-spinner.sh:100` and `lib/11-resilience.sh:82`
- **Severity**: Medium
- **Status**: [ ] Pending
- **Problem**: Both files set EXIT traps. Zsh LIFO order means spinner cleanup may interfere with transaction rollback.
- **Fix**: Use a coordinated trap handler or ensure spinner registers its cleanup within the transaction framework rather than a separate EXIT trap.
- **Verify**: Force a failure during a spinner operation and confirm rollback completes cleanly

### BUG-08: Variable reuse in cmd_branches loop
- **File**: `lib/commands/git-ops.sh:466-512`
- **Severity**: Medium
- **Status**: [ ] Pending
- **Problem**: Variables like `has_worktree`, `sha`, `last_commit` are reused across local and remote branch processing loops. Values from first loop can bleed into second if error occurs.
- **Fix**: Initialise all variables to empty string at the start of each loop iteration
- **Verify**: `./grove branches <repo> --json | python3 -c "import json,sys; json.load(sys.stdin)"`

### BUG-09: Transaction register pipe delimiter vulnerability
- **File**: `lib/11-resilience.sh:88-105`
- **Severity**: Medium
- **Status**: [ ] Pending
- **Problem**: Arguments containing `|` break rollback parsing on line 132.
- **Fix**: Use ASCII Unit Separator `\x1F` as delimiter instead of `|`
- **Verify**: Register a transaction with arguments containing `|` and verify rollback works

### BUG-10: cmd_upgrade leaves broken rebase state on failure
- **File**: `lib/commands/maintenance.sh:622-623`
- **Severity**: Medium
- **Status**: [ ] Pending
- **Problem**: Failed `git pull --rebase` exits with `die()` leaving repo in broken rebase state.
- **Fix**: Add `git -C "$repo_dir" rebase --abort 2>/dev/null` before dying, or catch the failure and offer recovery.
- **Verify**: Simulate a rebase conflict during upgrade and confirm clean error recovery

---

## Performance Improvements

### PERF-01: Redundant git worktree list calls
- **Files**: Multiple across `lib/commands/info.sh`, `lib/04-git.sh`
- **Impact**: High
- **Status**: [ ] Pending
- **Problem**: Same `git --git-dir="$git_dir" worktree list --porcelain` called 2-3 times per command execution for same repo.
- **Fix**: Use `collect_worktrees()` (lib/04-git.sh:492) consistently. Store result and reuse.
- **Safety**: High - pure caching, no functional change

### PERF-02: Redundant git status calls when cache has data
- **Files**: `lib/commands/info.sh:53,67,254,263`
- **Impact**: High
- **Status**: [ ] Pending
- **Problem**: `git status --porcelain` called even when `_GROVE_STATUS_CACHE` already has dirty/clean status.
- **Fix**: Extend cache format from `sha|dirty|ahead|behind|timestamp` to `sha|dirty|changes|ahead|behind|timestamp` to include change count.
- **Safety**: Medium - requires cache format change in both producer and consumer

### PERF-03: sed_inplace() checks GNU/BSD on every call
- **File**: `lib/03-paths.sh:4-11`
- **Impact**: Medium
- **Status**: [ ] Pending
- **Problem**: Spawns 3 processes per call to detect sed variant. Function is also unused (see QUALITY-04).
- **Fix**: Either remove (dead code) or cache detection at startup in `lib/00-header.sh`
- **Safety**: High

### PERF-04: Duplicate stat/date calls per worktree
- **File**: `lib/04-git.sh:440-459`
- **Impact**: Medium
- **Status**: [ ] Pending
- **Problem**: Two separate stat calls (macOS then Linux fallback) and two date calls for each worktree.
- **Fix**: Cache OS detection at startup:
  ```zsh
  # In lib/00-header.sh
  readonly GROVE_OS="$(uname -s)"
  ```
  Then use conditional format strings based on `$GROVE_OS`.
- **Safety**: High - only changes implementation, not behaviour

### PERF-05: Sleep polling in parallel operations
- **File**: `lib/09-parallel.sh:56`
- **Impact**: Medium
- **Status**: [ ] Pending
- **Problem**: `sleep 0.1` busy-wait loop instead of `wait -n`.
- **Fix**: Use `wait -n` (Zsh 5.0.8+) to wait for any child to finish. Add version check fallback.
- **Safety**: Medium - requires Zsh version verification

---

## Code Quality Improvements

### QUALITY-01: Duplicated config parsing logic
- **File**: `lib/01-core.sh:26-82` and `lib/01-core.sh:85-115`
- **Priority**: High
- **Status**: [ ] Pending
- **Problem**: ~47 lines of identical key/value parsing in `parse_config_file()` and `load_repo_config()`. Only the `case` whitelist differs.
- **Fix**: Have `load_repo_config()` call `parse_config_file()` with a mode/flag to control which variables are set. OR extract the key/value cleaning into a shared helper and keep separate case statements.
- **Note**: Be careful not to break config loading order or whitelist security

### QUALITY-02: Function naming - wt_ prefix remnants
- **File**: `lib/03-paths.sh`
- **Priority**: High
- **Status**: [ ] Pending
- **Problem**: Functions still use `wt_` prefix from pre-rename era:
  - `wt_path_for()` (line 243) - called 20+ times
  - `resolve_wt_path()` (line 139) - called 15+ times
  - `lookup_wt_path()` (line 105) - called 5+ times
- **Fix**: Rename to `worktree_path_for()`, `resolve_worktree_path()`, `lookup_worktree_path()`. Update all call sites across all lib/ files.
- **Verify**: `./run-tests.sh` passes, `./build.sh` succeeds, spot-check commands

### QUALITY-03: Inconsistent die() vs error_exit() usage
- **Files**: Multiple across `lib/commands/`
- **Priority**: High
- **Status**: [ ] Pending
- **Problem**: `die()` outputs coloured text which breaks `--json` mode. `error_exit()` is JSON-aware. Mixed usage means some commands produce non-JSON errors in JSON mode.
- **Fix**: Either make `die()` JSON-aware (check `$JSON_OUTPUT` and call `die_json` if true) OR migrate all `die()` calls to `error_exit()`.
- **Verify**: Run failing commands with `--json` and verify all output is valid JSON

### QUALITY-04: Dead code - unused sed_inplace()
- **File**: `lib/03-paths.sh:4-11`
- **Priority**: Medium
- **Status**: [ ] Pending
- **Problem**: Function defined but never called anywhere in codebase.
- **Fix**: Remove the function entirely
- **Verify**: `./run-tests.sh` passes, grep confirms no references

### QUALITY-05: Missing function docstrings
- **Files**: All `lib/*.sh`
- **Priority**: Medium
- **Status**: [ ] Pending
- **Problem**: Complex functions lack parameter/return documentation:
  - `collect_worktree_statuses()` (lib/04-git.sh:89)
  - `fuzzy_match_branch()` (lib/03-paths.sh:321)
  - `site_name_for()` (lib/03-paths.sh:23)
  - `calculate_health_score()` (lib/commands/info.sh)
  - `parallel_run()` (lib/09-parallel.sh)
- **Fix**: Add docstring headers with params, returns, side effects, usage examples

### QUALITY-06: Duplicated worktree list parsing pattern
- **Files**: Multiple (8+ locations)
- **Priority**: Medium
- **Status**: [ ] Pending
- **Problem**: The `git worktree list --porcelain` parsing pattern is repeated with slight variations.
- **Fix**: Extract into `iterate_worktrees()` callback function in `lib/04-git.sh`
- **Note**: Larger refactor - consider doing this as a separate PR

### QUALITY-07: No integration tests for hook execution
- **Files**: `tests/integration/`
- **Priority**: Medium
- **Status**: [ ] Pending
- **Problem**: Hook execution flow, environment variables, repo-specific hooks, and failure handling are untested.
- **Fix**: Create `tests/integration/hooks.bats` covering execution order, env vars, abort logic

### QUALITY-08: Inconsistent error message formatting
- **Files**: Multiple across `lib/commands/`
- **Priority**: Medium
- **Status**: [ ] Pending
- **Problem**: Despite documented standards in `lib/01-core.sh:133-139`, messages use inconsistent quoting, capitalisation, and terminology.
- **Fix**: Audit all `die()`, `error_exit()`, `warn()` calls against documented standards

### QUALITY-09: Redundant double-dot check in validate_name
- **File**: `lib/02-validation.sh:95-97`
- **Priority**: Low
- **Status**: [ ] Pending
- **Problem**: Line 95 checks for `..` but this is already checked in `validate_identifier_common()` on line 52.
- **Fix**: Remove the redundant check on lines 94-97

### QUALITY-10: Magic number for stale branch threshold
- **File**: `lib/commands/info.sh:115`
- **Priority**: Low
- **Status**: [ ] Pending
- **Problem**: Hardcoded `50` for stale branch commits-behind threshold.
- **Fix**: Add `GROVE_STALE_THRESHOLD` config variable with default of 50

---

## Suggested Implementation Order

### Phase 1: Critical Bug Fixes (do first, low risk)
1. BUG-01 - Fix undefined variable (1 line change)
2. BUG-03 - Fix clone exit code (1 line change)
3. BUG-02 - Fix config permission race (small change)

### Phase 2: High Priority Fixes (important, moderate scope)
4. BUG-04 - Add Linux stat fallback (1 line change)
5. BUG-05 - Fix floating-point arithmetic (small change)
6. BUG-06 - Add fzf validation (repetitive but straightforward, ~14 locations)
7. QUALITY-04 - Remove dead code sed_inplace (deletion only)
8. QUALITY-09 - Remove redundant validation check (deletion only)

### Phase 3: Quality & Consistency (larger scope, lower risk)
9. QUALITY-03 - Standardise die/error_exit (audit + refactor)
10. QUALITY-01 - Extract config parsing (refactor)
11. QUALITY-02 - Rename wt_ functions (rename + update call sites)

### Phase 4: Performance (safe optimisations)
12. PERF-04 - Cache OS detection
13. PERF-03 - Remove or fix sed_inplace (already dead code)
14. PERF-01 - Reduce redundant git calls
15. PERF-05 - Improve parallel wait

### Phase 5: Polish (documentation, tests, style)
16. QUALITY-05 - Add function docstrings
17. QUALITY-07 - Add hook integration tests
18. QUALITY-08 - Audit error messages
19. QUALITY-10 - Configurable stale threshold
20. QUALITY-06 - Extract worktree iterator (larger refactor)

### After Each Phase
```bash
./build.sh
./run-tests.sh
# Validate JSON output for any modified commands:
./grove repos --json | python3 -c "import json,sys; json.load(sys.stdin)"
./grove ls <repo> --json | python3 -c "import json,sys; json.load(sys.stdin)"
```

---

## Notes

- **Never edit `grove` directly** - all changes go in `lib/` files, then `./build.sh`
- **JSON output is a data contract** - validate after every change
- **Zsh loop variable rule** - always declare `local` variables outside loops to prevent debug output
- The `wt_` prefix in **local variable names** (e.g., `wt_path`) is fine - only function names need renaming
- `migrate-from-wt.sh` intentionally contains `wt`/`WT_` references (it's a migration tool)
