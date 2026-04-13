# Grove-CLI Implementation Plan

**Date**: 2026-02-08
**Branch**: develop
**Review scope**: ~8,800 lines across 22 source modules + tests
**Agents**: 4 parallel reviewers (core bugs, command bugs, performance, code quality)
**Previous review**: [review-findings.md](review-findings.md) (2026-02-07) — status tracked below

---

## Status Legend

- `[ ]` Pending
- `[~]` In progress
- `[x]` Complete
- `[!]` Previous finding corrected/superseded

---

## Phase 1: Critical Bugs (Do First — Runtime Failures)

These cause crashes, wrong results, or security issues. All are low-risk fixes.

### 1.1 `[x]` Transaction rollback skips last step (Zsh 1-based array) — NEW
- **File**: `lib/11-resilience.sh:174`
- **Severity**: Critical
- **Source**: NEW-BUG-01 (core reviewer)
- **Problem**: Rollback loop `for ((i=${#GROVE_ROLLBACK_STEPS[@]}-1; i>=0; i--))` is 0-based but Zsh arrays are 1-indexed. With 3 steps at indices 1,2,3: loop visits i=2,1,0 — **skipping the last registered step** (index 3) and processing an empty element at index 0.
- **Fix**: Change to `for ((i=${#GROVE_ROLLBACK_STEPS[@]}; i>=1; i--))`
- **Verify**: Register 3 rollback steps, force failure, confirm all 3 execute in reverse order
- **Risk**: Very low (1 line)

### 1.2 `[x]` `check_worktree_mismatches()` called but never defined
- **File**: `lib/commands/info.sh:1142`
- **Severity**: Critical
- **Source**: CMD-BUG-10 (cmd reviewer), QUALITY-11 (quality reviewer)
- **Problem**: `cmd_health()` calls `check_worktree_mismatches "$git_dir"` but this function doesn't exist anywhere. The "Branch Consistency" section of `grove health` always fails with "command not found".
- **Fix**: Implement the function in `lib/04-git.sh` using existing `check_branch_directory_match()`, or inline the logic at the call site.
- **Verify**: `grove health <repo>` completes without errors, "Branch Consistency" section shows results

### 1.3 `[x]` `sed_inplace()` called but never defined (corrects QUALITY-04)
- **File**: `lib/commands/lifecycle.sh:445, 690`
- **Severity**: Critical
- **Source**: CMD-BUG-04 (cmd reviewer), QUALITY-12 (quality reviewer)
- **Previous**: QUALITY-04 incorrectly stated "defined but never called" — reality is **called but never defined**
- **Problem**: `cmd_move` (line 445) and `cmd_restructure` (line 690) call `sed_inplace` to update APP_URL in `.env`. Function doesn't exist, so these commands crash.
- **Fix**: Either define `sed_inplace()` in `lib/01-core.sh` with cross-platform support, or replace call sites with pure Zsh string replacement (preferred — avoids GNU/BSD sed portability issues).
- **Verify**: `grove move myrepo mybranch newname` updates APP_URL in .env correctly

### 1.4 `[x]` Undefined variable in cmd_health .env check
- **File**: `lib/commands/info.sh:1065`
- **Severity**: Critical
- **Source**: BUG-01 (previous review)
- **Problem**: `$path` used but should be `$wt_path`
- **Fix**: Change `${path##*/}` to `${wt_path##*/}`
- **Verify**: `grove health <repo>` shows correct worktree names in .env warning

### 1.5 `[x]` cmd_clone --json returns exit code 0 on failure
- **File**: `lib/commands/lifecycle.sh:483`
- **Severity**: Critical
- **Source**: BUG-03 (previous review)
- **Fix**: Change `return 0` to `return 1` on the failure path
- **Verify**: `grove clone invalid-url --json; echo $?` outputs non-zero

### 1.6 `[x]` Config file permission race condition in cmd_setup
- **File**: `lib/commands/config.sh:414-439`
- **Severity**: Critical
- **Source**: BUG-02 (previous review)
- **Fix**: Create file with restrictive umask: `(umask 077; cat > "$config_file" << EOF ... EOF)`
- **Verify**: `ls -la ~/.groverc` shows `-rw-------` after `grove setup`

---

## Phase 2: High Priority Bugs (Important, Moderate Scope)

### 2.1 `[x]` bytes_to_human displays wrong unit (Zsh 1-based array) — NEW
- **File**: `lib/01-core.sh:291-313`
- **Severity**: High
- **Source**: NEW-BUG-02 (core reviewer)
- **Problem**: `units=("K" "M" "G" "T")` with `unit_idx=0`. Zsh arrays are 1-indexed, so `${units[0]}` is empty. All size displays are one unit too low (100KB shows as "100", 1MB shows as "1K").
- **Fix**: Change `local unit_idx=0` to `local unit_idx=1`, adjust loop bound from `< 3` to `< 4`
- **Verify**: `grove status`, `grove report`, `grove info` display correct size units
- **Affects**: Every command that displays file sizes

### 2.2 `[x]` Config values containing `#` are truncated — NEW
- **File**: `lib/01-core.sh:28-37`
- **Severity**: High
- **Source**: NEW-BUG-03 (core reviewer)
- **Problem**: `_clean_config_value()` strips quotes first, then strips everything after `#`. Password `"my#password"` becomes `my` after processing. Quote stripping runs before comment stripping, so even quoted values are truncated.
- **Fix**: Only strip `#` if it appears outside quotes (check if original value was quoted, skip `%%#*` if so)
- **Verify**: Set `DB_PASSWORD="test#123"` in `.groverc`, verify full password is used

### 2.3 `[x]` cmd_recent branch extraction wrong for new-style directories — NEW
- **File**: `lib/commands/discovery.sh:324,364`
- **Severity**: High
- **Source**: CMD-BUG-05 (cmd reviewer)
- **Problem**: Uses `branch="${folder#*--}"` which only works for old `repo--branch-slug` format. New worktree structure uses `site_name_for()` output. Branch is available from `collect_worktrees()` but discarded.
- **Fix**: Include branch in stored data: `worktrees+=("$atime|$repo_name|$wt_path|$wt_branch")`
- **Verify**: `grove recent --json` shows correct branch names for new-style directories

### 2.4 `[x]` cmd_health stale worktree detection logic is broken — NEW
- **File**: `lib/commands/info.sh:1065-1067`
- **Severity**: Medium (but produces false positives)
- **Source**: CMD-BUG-11 (cmd reviewer)
- **Problem**: `grep -A1 '^worktree '` then `grep -v '^worktree '` leaves lines like `HEAD abc123` or `branch refs/heads/main`, not paths. The `while read -r path` loop checks if these are directories (never true), giving false positives.
- **Fix**: Parse porcelain output properly — extract worktree path, check on empty-line boundary
- **Verify**: `grove health <repo>` should not report false stale worktrees

### 2.5 `[x]` cmd_health database orphan detection uses wrong branch extraction — NEW
- **File**: `lib/commands/info.sh:1095`
- **Severity**: Medium
- **Source**: CMD-BUG-14 (cmd reviewer)
- **Problem**: `${hw_path##*--}` uses old-style naming. Branch is available from `collect_worktrees()` but not used here.
- **Fix**: Use branch from `wt_entry` instead of parsing path
- **Verify**: `grove health <repo>` with new-style directories doesn't report false orphaned databases

### 2.6 `[x]` Missing Linux stat fallback in fetch cache
- **File**: `lib/04-git.sh:27`
- **Severity**: High
- **Source**: BUG-04 (previous review)
- **Fix**: `cache_time="$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)"`

### 2.7 `[x]` Floating-point arithmetic failure with set -e
- **File**: `lib/12-deps.sh:329-334`
- **Severity**: High
- **Source**: BUG-05 (previous review)
- **Fix**: Use integer-only arithmetic with conditional formatting

### 2.8 `[x]` cmd_clean format_size uses floating-point arithmetic — NEW
- **File**: `lib/commands/discovery.sh:401-412`
- **Severity**: Medium
- **Source**: CMD-BUG-06 (cmd reviewer)
- **Problem**: Same class of bug as BUG-05 — `$((bytes / 1073741824.0))` is invalid Zsh arithmetic
- **Fix**: Use integer-only arithmetic, or replace with existing `bytes_to_human()` (after fixing 2.1)

### 2.9 `[x]` Missing validate_name after fzf branch selection (14+ commands)
- **File**: Multiple — see BUG-06 in [review-findings.md](review-findings.md)
- **Severity**: High
- **Source**: BUG-06 (previous review)
- **Fix**: Add `validate_name "$branch" "branch"` after every `select_branch_fzf` call

---

## Phase 3: Cross-Platform Fixes (Linux Compatibility)

All use the same pattern: add `|| stat -c` fallback after macOS `stat -f`.

### 3.1 `[x]` Hook security check uses macOS-only stat — NEW
- **File**: `lib/06-hooks.sh:10-18`
- **Severity**: Medium
- **Source**: NEW-BUG-05 (core reviewer), QUALITY-17 (quality reviewer)
- **Problem**: `stat -f %u` and `stat -f %Lp` have no Linux fallback. On Linux, ALL hooks are silently skipped (ownership check always fails with empty string).
- **Fix**: Add Linux fallbacks: `stat -f %u ... 2>/dev/null || stat -c %u ... 2>/dev/null`
- **Verify**: On Linux, hooks execute correctly

### 3.2 `[x]` db_name_for uses macOS-only md5 command — NEW
- **File**: `lib/05-database.sh:15`
- **Severity**: Medium
- **Source**: NEW-BUG-04 (core reviewer)
- **Fix**: Use `md5sum 2>/dev/null || md5 2>/dev/null` pattern (already used in `_calculate_lockfile_hash`)

### 3.3 `[x]` site_name_for md5 fallback pipeline error handling — NEW
- **File**: `lib/03-paths.sh:55-56`
- **Severity**: Medium
- **Source**: NEW-BUG-06 (core reviewer)
- **Fix**: Group first pipeline: `{ md5sum 2>/dev/null || md5 2>/dev/null; } | cut -c1-6`

---

## Phase 4: Medium Priority Bugs & JSON Fixes

### 4.1 `[x]` cmd_exec doesn't propagate command exit code — NEW
- **File**: `lib/commands/navigation.sh:209-210`
- **Severity**: Medium
- **Source**: CMD-BUG-02 (cmd reviewer)
- **Fix**: Capture exit code before `popd`, return it

### 4.2 `[x]` cmd_info uses worktree_path_for instead of resolve_worktree_path — NEW
- **File**: `lib/commands/discovery.sh:32`
- **Severity**: Medium
- **Source**: CMD-BUG-03 (cmd reviewer)
- **Fix**: Change to `resolve_worktree_path` (handles moved worktrees)

### 4.3 `[x]` --version --check flag ordering breaks version check — NEW
- **File**: `lib/99-main.sh:204-212`
- **Severity**: Medium
- **Source**: CMD-BUG-01 (cmd reviewer)
- **Fix**: Defer version action to after full flag parsing loop

### 4.4 `[x]` cmd_config JSON output missing json_escape — NEW
- **File**: `lib/commands/config.sh:33-34`
- **Severity**: Medium
- **Source**: CMD-BUG-07 (cmd reviewer)
- **Fix**: Apply `json_escape` to all string values in JSON output

### 4.5 `[x]` cmd_alias regex injection in grep pattern — NEW
- **File**: `lib/commands/config.sh:192,206`
- **Severity**: Medium
- **Source**: CMD-BUG-13 (cmd reviewer)
- **Fix**: Use `grep -F` for fixed-string matching

### 4.6 `[x]` Variable reuse in cmd_branches loop
- **File**: `lib/commands/git-ops.sh:466-512`
- **Severity**: Medium
- **Source**: BUG-08 (previous review)
- **Fix**: Initialise all variables at start of each loop iteration

### 4.7 `[x]` Transaction register pipe delimiter vulnerability
- **File**: `lib/11-resilience.sh:88-105`
- **Severity**: Medium
- **Source**: BUG-09 (previous review)
- **Fix**: Use ASCII Unit Separator `\x1F` instead of `|`

### 4.8 `[x]` cmd_upgrade leaves broken rebase state on failure
- **File**: `lib/commands/maintenance.sh:622-623`
- **Severity**: Medium
- **Source**: BUG-10 (previous review)
- **Fix**: Add `git rebase --abort` before dying

### 4.9 `[x]` Spinner/transaction EXIT trap conflict
- **File**: `lib/08-spinner.sh:100` and `lib/11-resilience.sh:82`
- **Severity**: Medium
- **Source**: BUG-07 (previous review)
- **Fix**: Coordinate trap handlers

---

## Phase 5: Performance Improvements (Safe Optimisations)

### Tier 1: High-Impact Subshell Elimination

These affect the most commands and provide the greatest cumulative speedup.

### 5.1 `[x]` json_escape via REPLY pattern — NEW
- **File**: `lib/01-core.sh` (json_escape definition)
- **Impact**: Medium-High (~40 call sites, affects every JSON command)
- **Source**: PERF-15
- **Fix**: Set `REPLY` instead of `print -r --`, update all call sites
- **Saves**: 5-15 subshells per JSON command (50-150ms)

### 5.2 `[x]` slugify_branch via REPLY pattern — NEW
- **File**: `lib/03-paths.sh:11-14`
- **Impact**: Medium-High (called dozens of times)
- **Source**: PERF-06
- **Fix**: Set `REPLY="${1//\//-}"`, update all call sites

### 5.3 `[x]` site_name_for inline subshell chain — NEW
- **File**: `lib/03-paths.sh:30-50`
- **Impact**: Medium
- **Source**: PERF-20
- **Fix**: Inline `extract_feature_name` and `slugify_branch` (both are one-liners)

### 5.4 `[x]` fuzzy_match_branch loop subshells — NEW
- **File**: `lib/03-paths.sh:413-432`
- **Impact**: Medium (saves 1 subshell per branch)
- **Source**: PERF-17, PERF-18
- **Fix**: Inline `slugify_branch`, use REPLY for `_fuzzy_score`

### Tier 2: Pipeline & Redundancy Elimination

### 5.5 `[x]` APP_URL extraction — replace 5-process pipeline with pure Zsh — NEW
- **File**: `lib/commands/navigation.sh:89,168`
- **Impact**: Medium
- **Source**: PERF-09
- **Fix**: Pure Zsh while-read loop (pattern already used elsewhere in codebase)

### 5.6 `[x]` cmd_report double-pass elimination — NEW
- **File**: `lib/commands/info.sh:666-732`
- **Impact**: Medium-High
- **Source**: PERF-10
- **Fix**: Single-pass collection into arrays, then format

### 5.7 `[x]` cmd_status — cache is_branch_merged result — NEW
- **File**: `lib/commands/info.sh:323,343`
- **Impact**: Medium
- **Source**: PERF-11
- **Fix**: Call once, store in variable, use for both text and JSON paths

### 5.8 `[x]` Reduce redundant git worktree list calls
- **Source**: PERF-01 (previous review)
- **Fix**: Use `collect_worktrees()` consistently, store and reuse results

### 5.9 `[x]` Reduce redundant git status calls
- **Source**: PERF-02 (previous review)
- **Fix**: Extend cache format to include change count

### Tier 3: Caching & Minor Optimisations

### 5.10 `[x]` Cache OS detection at startup — NEW
- **Source**: PERF-04 (previous review), PERF-13 (new)
- **Fix**: `readonly GROVE_OS="$(uname -s)"` and `_GROVE_UID="$(id -u)"` in `lib/00-header.sh`

### 5.11 `[x]` Cache JSON formatter detection — NEW
- **File**: `lib/07-templates.sh:212-227`
- **Source**: PERF-16
- **Fix**: Detect once on first use, store in global

### 5.12 `[x]` extract_template_desc — replace 4-process pipeline — NEW
- **File**: `lib/07-templates.sh:23-26`
- **Source**: PERF-14
- **Fix**: Pure Zsh while-read loop

### 5.13 `[x]` format_grade/format_health_indicator via REPLY — NEW
- **File**: `lib/commands/info.sh:857-878`
- **Source**: PERF-19
- **Fix**: Set REPLY instead of print

### 5.14 `[x]` cached_fetch — reuse cache age from validation — NEW
- **File**: `lib/04-git.sh:52-54`
- **Source**: PERF-12
- **Fix**: Have `_fetch_cache_valid` set `_FETCH_CACHE_AGE` global

### 5.15 `[x]` Improve parallel wait with `wait -n` — NEW
- **Source**: PERF-05 (previous review)
- **Fix**: Replace `sleep 0.1` with `wait -n` (Zsh 5.0.8+)

### 5.16 `[x]` _clean_config_value — inline into caller — NEW
- **File**: `lib/01-core.sh:61`
- **Source**: PERF-08
- **Fix**: Inline the 5 parameter expansions directly in `_read_config_pairs`

---

## Phase 6: Code Quality & Maintainability

### 6.1 `[x]` Extract hook environment setup into helper — NEW
- **File**: `lib/06-hooks.sh:56-145`
- **Priority**: High
- **Source**: QUALITY-13
- **Fix**: Extract `_run_single_hook()` — reduces ~60 lines of duplication to ~20 + 3 calls
- **Effort**: Small-Medium

### 6.2 `[x]` Standardise cmd_config output — NEW
- **File**: `lib/commands/config.sh:33-59`
- **Priority**: High
- **Source**: QUALITY-14, CMD-BUG-08
- **Fix**: Replace `echo` with `print -r --`, replace `cat <<EOF` JSON with `format_json` pattern
- **Effort**: Small

### 6.3 `[x]` Standardise die() vs error_exit() usage
- **Priority**: High
- **Source**: QUALITY-03 (previous review)
- **Fix**: Make `die()` JSON-aware or migrate all calls to `error_exit()`
- **Effort**: Medium

### 6.4 `[x]` Extract duplicated config parsing logic
- **Priority**: High
- **Source**: QUALITY-01 (previous review)
- **Fix**: Have `load_repo_config()` call `parse_config_file()` with a mode flag
- **Effort**: Medium

### 6.5 `[ ]` Rename wt_ function prefixes to worktree_
- **Priority**: High
- **Source**: QUALITY-02 (previous review)
- **Fix**: Rename `wt_path_for` → `worktree_path_for`, etc. Update all call sites
- **Effort**: Medium (mechanical but wide-reaching)

### 6.6 `[x]` Extract dangerous command detection — NEW
- **File**: `lib/commands/bulk-ops.sh:77-125`
- **Priority**: Medium
- **Source**: QUALITY-15
- **Fix**: Extract `_check_dangerous_command()` helper
- **Effort**: Small

### 6.7 `[x]` Eliminate nested function definitions — NEW
- **Files**: `lib/commands/discovery.sh:401-477`, `lib/commands/info.sh:32-175,257-349`
- **Priority**: Medium
- **Source**: QUALITY-16, QUALITY-22
- **Fix**: Extract as standalone `_`-prefixed functions with explicit parameters
- **Effort**: Medium

### 6.8 `[x]` Update test helper path patterns — NEW
- **File**: `tests/test-helper.bash:94-115`
- **Priority**: Medium
- **Source**: QUALITY-18
- **Fix**: Mirror `site_name_for()` and `worktree_path_for()` from real code
- **Effort**: Small

### 6.9 `[x]` Extract score_to_grade helper — NEW
- **File**: `lib/commands/info.sh` (3 locations)
- **Priority**: Low
- **Source**: QUALITY-20
- **Fix**: Extract function, call from 3 locations
- **Effort**: Small

### 6.10 `[x]` cmd_repos local variables inside while-loop — NEW
- **File**: `lib/commands/info.sh:401-404`
- **Priority**: Medium
- **Source**: QUALITY-21
- **Fix**: Declare `git_dir`, `wt_list`, `wt_count` before loop
- **Effort**: Trivial

### 6.11 `[x]` Remove dead code (sed_inplace definition, redundant validation check)
- **Source**: QUALITY-04 (corrected — see 1.3), QUALITY-09 (previous review)
- **Fix**: Remove sed_inplace definition if it exists; remove redundant `..` check in validate_name

### 6.12 `[x]` Add function docstrings
- **Source**: QUALITY-05 (previous review)
- **Effort**: Medium

### 6.13 `[x]` Add hook integration tests
- **Source**: QUALITY-07 (previous review)
- **Effort**: Medium

### 6.14 `[x]` Audit error messages for consistency
- **Source**: QUALITY-08 (previous review)
- **Effort**: Small

### 6.15 `[x]` Configurable stale branch threshold
- **Source**: QUALITY-10 (previous review)
- **Fix**: Add `GROVE_STALE_THRESHOLD` config variable
- **Effort**: Small

### 6.16 `[x]` Dashboard header alignment — NEW
- **File**: `lib/commands/info.sh:1178-1180`
- **Priority**: Low
- **Source**: QUALITY-19
- **Effort**: Trivial

### 6.17 `[x]` British English consistency in comments — NEW
- **Priority**: Low
- **Source**: QUALITY-23
- **Effort**: Trivial

---

## Phase 7: Low Priority / Defence-in-Depth

### 7.1 `[x]` osascript injection in notify() — NEW
- **File**: `lib/01-core.sh:214`
- **Source**: NEW-BUG-07
- **Fix**: Escape quotes before interpolation
- **Risk**: Low (currently only called with hardcoded strings)

### 7.2 `[x]` validate_config returns warning count as exit code — NEW
- **File**: `lib/02-validation.sh:39`
- **Source**: NEW-BUG-08
- **Fix**: Return 0, output count via print (currently dead code)

### 7.3 `[x]` collect_worktrees eval without input validation — NEW
- **File**: `lib/04-git.sh:647-650`
- **Source**: NEW-BUG-09
- **Fix**: Validate `_cw_target` is a valid variable name before eval

### 7.4 `[x]` cmd_repos JSON negative worktree count edge case — NEW
- **File**: `lib/commands/info.sh:403-404`
- **Source**: CMD-BUG-09
- **Fix**: Add floor check `(( wt_count < 0 )) && wt_count=0`

### 7.5 `[x]` cmd_report missing handling of last porcelain entry — NEW
- **File**: `lib/commands/info.sh:667-732`
- **Source**: CMD-BUG-15
- **Fix**: Add "Handle last entry" block after loop

---

## Verification Checklist (After Each Phase)

```bash
# Build
./build.sh

# Run all tests
./run-tests.sh

# Validate JSON output for modified commands
./grove repos --json | python3 -c "import json,sys; json.load(sys.stdin)"
./grove recent --json | python3 -c "import json,sys; json.load(sys.stdin)"
./grove ls <repo> --json | python3 -c "import json,sys; json.load(sys.stdin)"
./grove branches <repo> --json | python3 -c "import json,sys; json.load(sys.stdin)"
./grove health <repo> --json | python3 -c "import json,sys; json.load(sys.stdin)"
./grove config --json | python3 -c "import json,sys; json.load(sys.stdin)"
./grove info <repo> <branch> --json | python3 -c "import json,sys; json.load(sys.stdin)"
```

---

## Summary Statistics

| Category | Critical | High | Medium | Low | Total |
|----------|----------|------|--------|-----|-------|
| Bugs (new) | 3 | 3 | 8 | 4 | 18 |
| Bugs (previous, open) | 3 | 3 | 4 | 0 | 10 |
| Performance (new) | — | 4 | 9 | 2 | 15 |
| Performance (previous, open) | — | 2 | 3 | 0 | 5 |
| Quality (new) | 2 | 2 | 5 | 4 | 13 |
| Quality (previous, open) | — | 3 | 5 | 2 | 10 |
| **Totals** | **8** | **17** | **34** | **12** | **71** |

### Corrections to Previous Review
- **QUALITY-04**: Was "defined but never called" — corrected to "**called but never defined**" (see 1.3)
- **PERF-03**: Linked to QUALITY-04 — also corrected. `sed_inplace()` is called in 2 locations.

---

## Recommended Priority Order

1. **Phase 1** (Critical bugs) — 6 items, all small fixes, immediate value
2. **Phase 2** (High priority bugs) — 9 items, moderate scope
3. **Phase 3** (Linux compatibility) — 3 items, same pattern applied 3 times
4. **Phase 5 Tier 1** (High-impact perf) — REPLY pattern for json_escape + slugify_branch gives biggest speedup
5. **Phase 4** (Medium bugs) — 9 items
6. **Phase 6** (Quality) — 17 items, mix of sizes
7. **Phase 5 Tier 2-3** (Remaining perf) — 11 items
8. **Phase 7** (Defence-in-depth) — 5 items, low urgency

---

## Notes

- **Never edit `grove` directly** — all changes go in `lib/` files, then `./build.sh`
- **JSON output is a data contract** for grove-app Tauri desktop — validate after every change
- **Zsh loop variable rule** — always declare `local` variables outside loops
- **REPLY pattern** — standard Zsh convention for returning values without subshells
- The `wt_` prefix in local variable names is fine — only function names need renaming
- `migrate-from-wt.sh` intentionally contains `wt`/`WT_` references
