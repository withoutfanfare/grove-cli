# Grove CLI — Code Review Findings

**Date:** 5 July 2026
**Scope:** All source in `lib/` and `lib/commands/`, plus `build.sh`, `run-tests.sh`, and the bats test helper (~11,500 lines of Zsh).
**Method:** Four parallel reviewers covered separate slices of the code. Every critical and high finding below was then verified against the actual source; items marked *(reproduced)* were additionally confirmed in a live shell.

---

## Summary

The codebase is in good shape overall — validation, JSON escaping in the newer code, and the security posture around config parsing and hooks are largely sound. But the review found **one critical bug** (bulk operations silently do nothing), **five high-severity bugs**, and a cluster of medium issues, many of them caused by the same root pattern: the script runs under `set -e` (exit on any error), and several places assume a failing command will fall through to their own error handling — it doesn't; the script just dies or skips the handler.

**Fix first, in this order:**

1. Parallel runner no-op (critical — `build-all`/`exec-all` report success while doing nothing)
2. Ctrl-C swallowed by the spinner trap
3. JSON contract contamination in `add`/`rm` and hooks
4. The `set -e` traps in `alias rm`, fzf menus, and `repair`

---

## Critical

### 1. Parallel operations never run their command — and report success *(reproduced)*

**[lib/09-parallel.sh:106](lib/09-parallel.sh:106)**

```zsh
if sh -c 'cd "$1" && shift && exec sh -c "$@"' _ "$wt_path" sh "$cmd" </dev/null >/dev/null 2>&1; then
```

After `shift`, `"$@"` is `(sh, $cmd)`, so the inner call becomes `sh -c "sh" "$cmd"` — the command string is the literal word `sh` (which reads end-of-file from `/dev/null` and exits 0), and the real command lands in `$0`, never executed. Reproduced live: the wrapper exits 0 without running anything.

**Impact:** `grove build-all`, `grove exec-all`, and `grove prune --all-repos` all report "ok" for every worktree while doing nothing at all.

**Fix:** pass the path and command as `$1`/`$2` and run them directly:

```zsh
sh -c 'cd "$1" && exec sh -c "$2"' _ "$wt_path" "$cmd"
```

---

## High severity

### 2. Ctrl-C doesn't stop grove *(reproduced)*

**[lib/08-spinner.sh:145](lib/08-spinner.sh:145)**

```zsh
trap 'spinner_stop 2>/dev/null' INT TERM
```

In Zsh, a trap handler that returns normally *resumes* the script. So once the spinner module has loaded, pressing Ctrl-C during any long operation stops the spinner and then carries on running. The handler needs to re-raise the signal after cleanup:

```zsh
trap 'spinner_stop 2>/dev/null; trap - INT; kill -INT $$' INT
trap 'spinner_stop 2>/dev/null; trap - TERM; kill -TERM $$' TERM
```

### 3. `--json` output contaminated by progress text and hook output

**[lib/commands/lifecycle.sh:302-312](lib/commands/lifecycle.sh:302)** (`cmd_add`), **[lib/commands/lifecycle.sh:419-445](lib/commands/lifecycle.sh:419)** (`cmd_rm`), **[lib/06-hooks.sh:89-94](lib/06-hooks.sh:89)**, **[lib/01-core.sh:214-220](lib/01-core.sh:214)**

The JSON output is a strict data contract for the Tauri app, but:

- `info()` / `ok()` / `warn()` / `dim()` all print to **stdout**, and `--json` does not set `QUIET` ([lib/99-main.sh:190](lib/99-main.sh:190)).
- `cmd_add --json` prints "Fetching latest branches...", "Creating worktree...", runs post-add hooks with stdout unredirected, and restarts Herd — all *before* emitting its JSON object.
- `cmd_rm --json` leaks git's own "Deleted branch ... (was ...)" line (line 420 redirects only stderr) plus hook and Herd output before the JSON.
- `_run_single_hook` never redirects hook stdout, so any chatty hook corrupts JSON for every command that runs hooks.

`cmd_pull` / `cmd_sync` already do this correctly (gate every message on `JSON_OUTPUT`, silence hooks) — `add`/`rm` should match. A more durable fix: make `info`/`ok`/`dim` write to stderr (or to stderr whenever `JSON_OUTPUT=true`).

### 4. Hook security check can be bypassed with a symlink

**[lib/06-hooks.sh:16,24](lib/06-hooks.sh:16)**

```zsh
owner="$(stat -f %u "$target" 2>/dev/null || stat -c %u "$target" 2>/dev/null)"
```

`stat` without `-L` inspects the symlink itself, not its target — but the execution gates (`[[ -x ]]`, the `*(N-.x)` glob) *do* follow symlinks. A user-owned symlink in `~/.grove/hooks/post-add.d/` pointing at a world-writable script passes the ownership/permission check and gets executed. Also, `$GROVE_HOOKS_DIR` itself is never permission-checked — only the `.d` subdirectories are.

**Fix:** use `stat -L` (both variants), or resolve first with `${target:A}`; add a check on the hooks root directory.

### 5. Removing the last alias or group silently fails *(reproduced)*

**[lib/commands/config.sh:215,235,620,640](lib/commands/config.sh:235)**

```zsh
grep -v "^${alias_name}=" "$GROVE_ALIASES_FILE" > "$temp_file"
if (( $? <= 1 )); then
```

`grep -v` exits 1 when no lines remain — and under `set -e` the script aborts on that line, so the `(( $? <= 1 ))` tolerance check written for exactly this case is unreachable. `grove alias rm <last-alias>` / `grove group rm <last-group>` exit with an error, leak the mktemp file, and leave the entry in place. Fix: `grep -v ... > "$temp_file" || rc=$?` (or wrap in `if ! grep ...`).

### 6. Pressing ESC in any fzf menu crashes the command *(same `set -e` root cause)*

**[lib/10-interactive.sh:47,106,245](lib/10-interactive.sh:47)**

fzf exits 130 on ESC; a failing command-substitution assignment trips `set -e` before the coded fallbacks (`base="$DEFAULT_BASE"`, the "(none)" template path, dashboard's "No selection made") can run. Append `|| true` to each fzf assignment.

### 7. `grove repair` miscounts and hides lock cleanup

**[lib/commands/maintenance.sh:469-471](lib/commands/maintenance.sh:469)**

`locks_cleaned="$(check_index_locks ...)"` captures the count **plus** the `warn`/`dim` human messages, because those helpers print to stdout. When a stale lock exists, the variable holds multi-line text, `(( locks_cleaned > 0 ))` throws "bad math expression", the removal message vanishes, and `repair` reports "No stale locks" after actually deleting one (JSON counts also come out wrong). Fix: send `warn`/`dim` in `check_index_locks` to stderr, or return the count via `$REPLY`.

### 8. `grove recent` dies on paths containing spaces

**[lib/commands/discovery.sh:348](lib/commands/discovery.sh:348)**

```zsh
sorted_all=($(printf '%s\n' "${worktrees[@]}" | sort -t'|' -k1 -rn))
```

Unquoted command substitution splits on *all* whitespace, not just newlines. A worktree path (or `HERD_ROOT`) with a space fractures a record; the fragment's timestamp field becomes text, `$((now - atime))` is a fatal math error under `set -e`, and `grove recent --json` dies with partial output. Fix:

```zsh
sorted_all=("${(f)$(printf '%s\n' "${worktrees[@]}" | sort -t'|' -k1 -rn)}")
```

---

## Medium severity

### Bugs

| # | Where | Issue |
|---|-------|-------|
| 9 | [lib/99-main.sh:217](lib/99-main.sh:217) | `parse_flags` matches `help` (and `-*` flags) in **every** positional arg, so `grove exec myrepo mybranch php artisan help` prints usage instead of running *(reproduced against the built grove)*. Only treat `help` as help when it's the first token. |
| 10 | [lib/05-database.sh:113,157-174](lib/05-database.sh:157) | `create/backup/drop_database` interpolate raw `$1` into SQL — the backtick/quote defence lives only in `db_name_for`, but these helpers are documented as callable from user hooks. Add a strict `^[a-zA-Z0-9_]+$` gate in each. |
| 11 | [lib/commands/info.sh:56-74](lib/commands/info.sh:56) + [lib/04-git.sh:159](lib/04-git.sh:159) | Cached `dirty` uses `git diff --quiet` (ignores untracked files) while the fallback and health score use `status --porcelain` (includes them) — `ls --json` reports `dirty: false` for worktrees with only untracked files, contradicting the health score. Align both on porcelain. |
| 12 | [lib/commands/info.sh:294](lib/commands/info.sh:294) | `grove status` feeds the `"(detached)"` sentinel into the branch/directory match check, flagging every detached worktree as a spurious MISMATCH. Skip the check for the sentinel. |
| 13 | [lib/commands/lifecycle.sh:747](lib/commands/lifecycle.sh:747) | Declining the `migrate:fresh` confirmation in `cmd_fresh` returns early, also skipping `npm ci`/`npm run build` despite the message saying only the migration is skipped. |
| 14 | [lib/commands/bulk-ops.sh:18-21](lib/commands/bulk-ops.sh:18) | Danger patterns `"dd "` and `">/dev/"` false-positive on `git add .` (a**dd-space**) and any `>/dev/null` redirect; in non-interactive mode this aborts legitimate `exec-all` runs. Anchor `dd` as a word; tighten `>/dev/` to `sd*`/`disk*`. |
| 15 | [lib/commands/maintenance.sh:776](lib/commands/maintenance.sh:776) | `git rebase --abort` exiting 128 (no rebase in progress) under `set -e` kills `cmd_upgrade` before the captured error and guidance are shown. Append `\|\| true`. |
| 16 | [lib/11-resilience.sh:147-153](lib/11-resilience.sh:147) | `check_disk_space`: if `df` fails or output is unparseable, `available_kb` is empty → treated as 0 → `die "Insufficient disk space: 0MB"` with plenty of space (and under pipefail the failing pipeline can kill the script outright). Skip the check when `df` can't answer. |
| 17 | [lib/07-templates.sh:159-164](lib/07-templates.sh:159) | Quote stripping runs before comment stripping, so `GROVE_SKIP_DB="true" # note` parses as `true"` and is rejected as invalid. Same order bug in [config.sh:134-137](lib/commands/config.sh:134). Related: [navigation.sh:33-42](lib/commands/navigation.sh:33) leaves a trailing `"` on a quoted `APP_URL` with a trailing comment, so `grove open` opens a malformed URL. |
| 18 | [build.sh:93,104](build.sh:93) | A missing lib module only warns and the build exits 0 — a renamed/deleted module produces a broken `grove` that `./build.sh && ./run-tests.sh` won't catch. Make it fatal like the 99-main.sh check. |
| 19 | [lib/03-paths.sh:289](lib/03-paths.sh:289) | `local out="$(git ...)" \|\| return 1` — `local` masks the exit status, so the `\|\| return 1` is dead. Split declaration and assignment (as done correctly at line 120). |
| 20 | [lib/04-git.sh:19](lib/04-git.sh:19) | Fetch cache at world-shared `/tmp/grove-fetch-cache`: on multi-user Linux another user can pre-own the directory (caching then silently never works) or plant fresh cache files to suppress fetches. Key by UID or move under `~/.grove/`. |

### Performance

| # | Where | Issue |
|---|-------|-------|
| P1 | [lib/commands/info.sh:56-129, 816-889](lib/commands/info.sh:816) | **The dominant cost in `ls`/`health`/`dashboard`:** the status-cache pass forks ~6 git calls per worktree, then `_display_worktree`/`calculate_health_score` largely re-compute the same data (ahead/behind, porcelain, commit age, merged/stale checks) — roughly 12–14 git forks per worktree. Passing the cached values through would about halve runtime. `cmd_dashboard` triples up the same work across every repo. |
| P2 | [lib/commands/info.sh:559-589](lib/commands/info.sh:559) | `cmd_branches` forks two git processes per branch (`rev-parse` + `log -1`). One `git for-each-ref --format='%(refname:short)\|%(objectname:short)\|%(committerdate:unix)'` gets all fields for all branches in a single fork — the big win for repos with hundreds of remote branches. |
| P3 | [lib/commands/services.sh:208,230,241](lib/commands/services.sh:208) | Text-mode `services status` forks `supervisorctl`, `launchctl list`, and `php artisan horizon:status` once **per app** — the artisan probe boots the whole Laravel framework each time (0.5–2 s per app). The JSON path (line 271-273) already snapshots once; the text path and `services doctor` (lines 882, 902) should reuse the same snapshots. |
| P4 | [lib/commands/git-ops.sh:126,163](lib/commands/git-ops.sh:126) | `pull` fetches at repo level then `git pull --rebase` per worktree re-fetches — N+1 network round-trips per repo. After the shared fetch, `git rebase origin/<branch>` per worktree avoids the extras. Also `cmd_sync` (line 333) uses a raw fetch where siblings use `cached_fetch`. |
| P5 | [lib/commands/info.sh:368](lib/commands/info.sh:368) | `status --json` performs a network fetch in the GUI's polling hot path. Consider a `--no-fetch` opt-out for JSON consumers. |
| P6 | [lib/03-paths.sh:255-319](lib/03-paths.sh:293) | `resolve_recent_shortcut` forks a `stat` per worktree plus `sort`/`sed`; zsh's `zstat` and `${(On)...}` sorting need zero subprocesses. Minor next to P1–P3. |

Startup cost is already lean (two subshells plus a pure-zsh config parse before dispatch) — no action needed there.

---

## Low severity (worth a batch pass when convenient)

- [lib/02-validation.sh:172-180](lib/02-validation.sh:172) — pattern-mismatch errors render literal `\n\n` (needs `$'\n'` with `print -r`).
- [lib/commands/laravel.sh:43-45](lib/commands/laravel.sh:43) — `php artisan "$@"` unguarded under `set -e`; the status-capture/`popd` code after it is dead.
- [lib/09-parallel.sh:91-92](lib/09-parallel.sh:91) — the `wait -n` path is dead code: Zsh has no `wait -n` at any version *(verified on zsh 5.9)*; the limiter always falls back to the 100 ms sleep. Just use the sleep.
- [lib/commands/info.sh:221,324,989](lib/commands/info.sh:221) — branch names containing `|` (legal in git, possible via manually created worktrees) corrupt the pipe-delimited records.
- [lib/commands/services.sh:208,302,882](lib/commands/services.sh:302) — supervisor process names are interpolated unescaped into `grep -E` patterns; a name with `(`/`+`/`[` misreports the app as "Not configured".
- [lib/commands/services.sh:281 etc.](lib/commands/services.sh:281) — `for app in $(svc_get_app_list)` word-splits app names with spaces (possible via hand-edited `apps.conf`).
- [lib/commands/maintenance.sh:288,303](lib/commands/maintenance.sh:288) — unguarded `rm`/`herd restart` under `set -e` can abort `cleanup_herd` mid-run, silently leaving orphans.
- [lib/commands/lifecycle.sh:501](lib/commands/lifecycle.sh:501) — site name used as a regex in `grep -q`; use `grep -qF`.
- [lib/commands/lifecycle.sh:833-843](lib/commands/lifecycle.sh:833) — restructure's `.env` APP_URL rewrite only runs when Herd is installed; `cmd_move` does it unconditionally and restructure should match.
- [lib/01-core.sh:236-241](lib/01-core.sh:236) — `die_json` passes raw control characters (other than `\n`/`\r`/`\t`) through, which would produce invalid JSON.
- [lib/01-core.sh:499-515](lib/01-core.sh:499) — `json_get_string` only matches compact `"key":"value"`; grove's own output uses `"key": "value"` with a space, so any future round-trip silently returns empty.
- [lib/05-database.sh:112-113](lib/05-database.sh:112) — `mysql ... | grep -q` under pipefail can theoretically SIGPIPE mysql and skip the pre-removal backup; capture output and string-match instead.
- [lib/10-interactive.sh:237](lib/10-interactive.sh:237) — the dashboard's Ctrl-R binding reloads the list to the literal line "REFRESH".
- [run-tests.sh:50-68](run-tests.sh:50) — lint parse-checks the compiled `grove`, never `lib/*.sh`, so a lib syntax error passes until someone rebuilds; and a merely-absent shellcheck exits rc 2, which reads as failure in CI.

## Test-helper drift (tests/test-helper.bash)

The bats tests exercise bash re-implementations, and three have drifted from the real Zsh code:

1. **`validate_template_name`** (helper:568 vs lib/07:5) — helper lacks the leading-dash rejection; `-evil` passes in tests but is rejected by the real code.
2. **`load_template`** (helper:593 vs lib/07:106) — the real implementation now unsets stale skip-flags first; the helper doesn't, so stale-flag-bleed behaviour is untestable.
3. **`json_escape`** (helper:217 vs lib/07:214) — helper omits control-character escaping (`\u00XX`) and the `$REPLY` return convention.

`validate_name`, `validate_identifier_common`, `slugify_string`, and `is_reserved_ref_segment` were spot-checked and are in sync.

---

## Recurring patterns worth a sweep

1. **`set -e` + expected non-zero exits** — findings 5, 6, 15, 16, and three low items share this root cause. Any command that can legitimately fail (`grep`, fzf, `git rebase --abort`, `df`, `rm`) needs `|| true` / `|| rc=$?`, or its handler is dead code. Worth grepping the whole codebase for this shape once.
2. **Output helpers write to stdout** — findings 3 and 7 both stem from `info`/`ok`/`warn`/`dim` printing to stdout. Routing them to stderr (at least when `JSON_OUTPUT=true`) fixes a whole class of contract breaks at once.
3. **Compute-once, use-everywhere** — P1–P3 are all the same shape: data is gathered per item, then re-gathered by the display/scoring layer. Threading the cached values through is the single biggest speed-up available.
