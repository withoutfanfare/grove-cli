# Grove CLI — Improvement Plan

> **Generated:** 2026-05-30 · **Branch:** `chore/internal-readiness-audit` · **Method:** multi-agent code+docs audit (30 reviewers, adversarial verification), findings cross-checked against source by hand.

## Provenance & confidence

This plan is the output of the **second** audit run. An earlier run was discarded: it executed during a window of transient empty tool-results and its reviewers hallucinated a "broken" grove (claiming empty source files, a placeholder binary, a missing `esac`, a stray `clear`) — none of which exist. Those claims were verified false against disk. The verifiers in this run explicitly **corrected** those earlier verdicts once tools returned real file contents.

**Repository health at time of audit (verified):**
- `./run-tests.sh unit` → **197/197 pass**
- `zsh -n grove` and `zsh -n lib/99-main.sh` → **no parse errors**
- JSON contract commands valid: `repos`, `recent`, `ls <repo>`, `branches <repo>`, `health <repo>`, `report`, `services apps` → **all parse as valid JSON**
- `git status` → clean

**Counts:** 257 raw findings → 241 kept after adversarial verification (16 rejected) → deduplicated/merged below. Severity: **0 P0, 2 P1, ~37 P2, ~180 P3.** No broken/security-hole/contract-breakage with confirmed exploitability in default flows.

Every finding below cites `file:line`. App fixes must edit `lib/` sources then run `./build.sh` + `./run-tests.sh` — never edit the compiled `grove`. Re-validate every touched `--json` command with `python3 -m json.tool`.

---

# Grove CLI — Consolidated Improvement Plan

Verified against source. Findings deduplicated and merged where they share a root cause. Items ordered by severity, then area (app before docs).

## P0 — none confirmed
No findings rise to broken/security-hole/contract-breakage with confirmed exploitability in default flows. The closest data-contract risks are tracked as P1 below.

---

## P1 — Important correctness, safety, or contract integrity

### 1. `cmd_report` markdown emits literal `\n`, collapsing the whole report to one line
- **Area:** app · **Category:** bug · **Effort:** S
- **Files:** `lib/commands/info.sh:696-816`
- **Problem:** Report assembled with two-char `\n` sequences then emitted via `print -r --` (verified at lines 696, 782-796, 813, 816). `print -r` does not interpret escapes, so both stdout and `--output` file produce a single unreadable line. The feature is effectively broken.
- **Fix:** Build with real newlines (`$'\n'` or actual breaks) keeping `print -r`, or emit with `printf '%b\n'`. Add a test asserting output contains real newlines. **Also** fixes the duplicated last-entry block (see #6).

### 2. `parallel pull-all` JSON round-trips the message through a hand-rolled parser and re-embeds it unescaped
- **Area:** app · **Category:** json-contract · **Effort:** M
- **Files:** `lib/commands/git-ops.sh:180-181, 201-219` (`_pull_all_for_repo`); related naive parsers `lib/01-core.sh:432-459`
- **Problem:** Verified: subshell writes `json_escape`'d message (line 181); parent re-parses with `json_get_string`/`json_get_value` (203-206) then re-embeds `$msg` at line 219 **without re-escaping**. Validity depends on the pure-zsh parser perfectly inverting `json_escape`. `git pull --rebase` output routinely contains quotes/backslashes/newlines — exactly where these parsers break — producing malformed JSON to the Tauri consumer. This is the most fragile JSON path in the tree.
- **Fix:** Don't parse-then-reuse. Either write the already-escaped message to a separate plain file and read verbatim, or re-run `json_escape` on the parsed value before embedding at 219. Add a test pulling with multi-line/quoted output validated via `python3 json.load`. The same drop-on-missing-result-file issue (total ≠ succeeded+failed) should be fixed in the same pass: emit an explicit failed entry when `$tmpdir/$idx` is absent (lines 198-232).

### 3. `pre-add` / `pre-rm` / `pre-move` hook veto is non-functional (dead error path)
- **Area:** app · **Category:** bug/safety · **Effort:** M
- **Files:** `lib/06-hooks.sh:64-68, 138`; `lib/commands/lifecycle.sh:182, 315, 442`
- **Problem:** Verified: `run_hooks` unconditionally `return 0` (06-hooks.sh:138); `_run_single_hook` only `warn`s on non-zero (64-68). So `if ! run_hooks "pre-add" ...; then error_exit ...` (lifecycle.sh:182, confirmed) is dead code. README's "Can abort?" column, help text (99-main.sh:153), and the lifecycle.sh:181 comment all advertise a veto that cannot fire. A `pre-rm` hook exiting 1 to block removal of a dirty worktree is ignored. (Merges two findings describing the same bug from `06-hooks.sh` and `lifecycle.sh`.)
- **Fix:** Make pre-* phases gating: have `_run_single_hook` return the hook's status and `run_hooks` return non-zero when any pre-* hook fails. Keep post-* non-fatal. Add a regression test. If advisory-only is intended instead, remove the dead `error_exit` branches and correct README/help.

### 4. `check_index_locks` deletes `index.lock` by age alone — can corrupt a live git process
- **Area:** app · **Category:** bug/safety · **Effort:** M
- **Files:** `lib/11-resilience.sh:41-55`; caller `lib/commands/maintenance.sh:442` (`--auto-clean`)
- **Problem:** Verified: comment at line 41 promises "older than 5 minutes **and no git process**", but code only tests `lock_age > 300` (line 43) with no process check before `rm -f` (line 45). A legitimate long-running fetch/checkout/rebase/CI clone holding the lock >5min is deleted under `--auto-clean`, risking index corruption. (Note: `return $locks_found` at line 55 also overloads exit status as a count — fix together.)
- **Fix:** Implement the promised process check (`lsof`/`fuser` on the lock, or any git process against that git_dir) before deletion, or require interactive confirmation. At minimum raise the threshold and correct the comment. Emit the count on stdout, reserve exit status for success/failure.

### 5. `cmd_upgrade` rebases whatever branch is checked out onto `origin/main`
- **Area:** app · **Category:** bug · **Effort:** M
- **Files:** `lib/commands/maintenance.sh:660-666, 690`
- **Problem:** Runs `git pull --rebase origin main` with no current-branch or clean-tree check. With the documented symlink dev install, a developer on a feature branch (e.g. the current `chore/internal-readiness-audit`) gets that branch silently rebased onto main; the behind-check compares HEAD to origin/main so it almost always thinks an upgrade exists. Uncommitted work can be lost.
- **Fix:** Verify the repo is on the default branch and the tree is clean before rebasing; compute the upstream ref once (main/master fallback) and reuse it for behind-check, log preview, and pull. Surface git stderr instead of discarding it (related finding at L690-693).

### 6. Worktree porcelain parse loop duplicated 4× with divergent last-entry handling
- **Area:** app · **Category:** maintainability · **Effort:** M
- **Files:** `lib/commands/info.sh` cmd_ls (190-213), cmd_branches (496-519), cmd_report (706-780), cmd_health (1136-1153); shared helpers in `lib/04-git.sh` (`iterate_worktrees`/`collect_worktrees`)
- **Problem:** The "parse porcelain, skip `*.git`, re-handle final entry" pattern is reimplemented at least four times (verified cmd_report at 710-780 duplicates the entire per-worktree status block). `cmd_status`/`cmd_health` already use the shared helpers. This is exactly where the zsh loop-variable JSON pitfall recurs via copy-paste, and where `cmd_restructure`'s last-entry block already drifted (see #8). Also note `iterate_worktrees` silently drops detached-HEAD worktrees from every consumer.
- **Fix:** Route cmd_ls/cmd_branches/cmd_report through `iterate_worktrees`/`collect_worktrees`. Handle the `detached` porcelain marker with a sentinel branch so detached worktrees stay visible. Single source of truth for parsing.

### 7. `ls --json` `url` field is verbatim attacker/committer-controlled `.env` `APP_URL`
- **Area:** app · **Category:** security · **Effort:** S
- **Files:** `lib/commands/info.sh:23-35, 121, 126`
- **Problem:** When no subdomain is configured the contract `url` is read from a worktree's `.env` `APP_URL`, only stripped of quotes/spaces/comments. `json_escape` keeps JSON valid but the value is untrusted: a committed `.env` could set `javascript:` or an unrelated host. A desktop consumer that opens `url` honours whatever `.env` contains.
- **Fix:** Validate against `http(s)://` scheme before using; fall back to `https://${folder}.test` on mismatch. At minimum document `url` as untrusted for the desktop app. (Pair with the open/switch URL-resolution consolidation, #14.)

### 8. `cmd_restructure` last-entry handler omits Herd re-secure + APP_URL rewrite
- **Area:** app · **Category:** consistency · **Effort:** M
- **Files:** `lib/commands/lifecycle.sh:726-746` (loop) vs `762-778` (last-entry)
- **Problem:** Main loop does git move + Herd unsecure/secure + `_update_env_app_url`; the duplicated last-entry block does only the move. Whether the final worktree hits the loop body or the last-entry branch depends on a trailing blank line in porcelain output, so the last repo can non-deterministically be left with stale SSL and a stale APP_URL.
- **Fix:** Extract one per-worktree migration helper and call it from both paths (or append a terminating blank line so the loop handles all entries).

### 9. `get_ahead_behind` / `get_commits_behind` conflate "base unresolved" with "in sync"
- **Area:** app · **Category:** bug · **Effort:** M
- **Files:** `lib/04-git.sh:312-318, 480-484, 488-499`; related `_collect_status_cb:148` (no-upstream → 0/0); `is_branch_merged:429-435`
- **Problem:** When `rev-parse --verify "$base"` fails (base not fetched / `DEFAULT_BASE` misconfigured) the functions return the initialised `0 0` / `0`, so `is_branch_stale` reports false and JSON shows ahead=0 behind=0 — indistinguishable from a branch genuinely level. A wildly stale worktree is reported up-to-date. `collect_worktree_statuses` has the mirror bug for no-upstream branches (never-pushed looks synced).
- **Fix:** Distinguish "unknown" from "zero" — sentinel `?` for human output, agree a null/"unknown" JSON representation with the Tauri app, and have `is_branch_merged` add the same `rev-parse --verify` guard. Coerce rev-list output to integer before arithmetic/JSON (`[[ $behind =~ ^[0-9]+$ ]] || behind=0`).

### 10. Aliases and groups documented as usable, but the resolvers are dead code
- **Area:** docs (root cause is app) · **Category:** docs-accuracy/bug · **Effort:** M
- **Files:** `lib/commands/config.sh:243` (`resolve_alias`, no callers), `:672` (`resolve_group`, no callers); `docs/guides/advanced.md:112-126, 169-182`
- **Problem:** Verified no call sites: navigation/path resolution never invoke `resolve_alias`; bulk-ops has no `@group` handling. `grove code login` treats `login` as a repo and fails `validate_name`/lookup; `grove build-all @frontend` rejects `@frontend` as an invalid repo. Aliases/groups can be created/listed but not *used* as the advanced guide claims.
- **Fix (decision required):** Either wire `resolve_alias` into repo/branch resolution and `resolve_group` into bulk/git-ops entry points (then add tests + CHANGELOG), or remove the "Using an Alias"/"Using Groups" doc sections and mark not-yet-implemented. This is the single biggest doc/code contradiction.

### 11. `services apps --json` ignores `PRETTY_JSON`; unvalidated fields can corrupt the registry & contract
- **Area:** app · **Category:** json-contract/consistency · **Effort:** M
- **Files:** `lib/commands/services.sh:376-399` (no `format_json`), `427-431, 473` (only `name` validated), `38-53` (`svc_load_config` trusts registry)
- **Problem:** Two merged issues: (a) `cmd_services_apps_json` hand-rolls output and never calls `format_json`, so `--pretty` is silently ignored unlike every other JSON command. (b) `--system-name`/`--supervisor`/`--domain` are written verbatim into the pipe-delimited 5-field registry; a `|` or newline corrupts `svc_load_config` and produces wrong/duplicated apps in `services apps --json`.
- **Fix:** Build the array and emit via `format_json`. Validate system-name/supervisor/domain (reject `|` and newlines; host whitelist for domain) before persisting. Skip malformed registry lines with a stderr warn in `svc_load_config`.

### 12. `cmd_config` emits unvalidated config values as bare JSON booleans
- **Area:** app · **Category:** json-contract · **Effort:** S
- **Files:** `lib/commands/config.sh:15, 18, 43`
- **Problem:** `db_enabled="${DB_CREATE:-false}"` / `herd_enabled="${HERD_ENABLED:-false}"` are interpolated unquoted (`"enabled": $db_enabled`). A `.groverc` with `DB_CREATE=1`/`yes`/empty yields `"enabled": 1` / `yes` / nothing — invalid JSON that throws in the Tauri parser. (Root cause shared with #18: boolean config keys aren't normalised at parse time.)
- **Fix:** Normalise both to strict `true`/`false` before emitting (or add a `to_json_bool` helper). Re-validate with `DB_CREATE=1` via `grove config --json | python3 -m json.load`.

### 13. Alias removal uses an unanchored grep, deleting unrelated aliases
- **Area:** app · **Category:** bug · **Effort:** S
- **Files:** `lib/commands/config.sh:203-207, 217-220`
- **Problem:** Verified: `grep -Fq "${alias_name}="` / `grep -Fv "${alias_name}="` are not anchored to line start, so removing/re-adding `foo` also deletes `myfoo=...` or any line whose value contains `foo=`. `cmd_group` correctly uses `^${name}=` (593-611), so the paths are inconsistent. Compounded by no error handling on the `grep > temp + mv` rewrite — a failed redirect overwrites the file with garbage.
- **Fix:** Anchor: `grep -q "^${alias_name}="` / `grep -v "^${alias_name}="`. Only `mv` when the redirect succeeded (treat grep rc≤1 as OK). Apply the same guard to `cmd_group`.

### 14. `cmd_open` vs `cmd_switch` `.env` URL parsing duplicated with diverging fallback
- **Area:** app · **Category:** consistency · **Effort:** M
- **Files:** `lib/commands/navigation.sh:88-107` vs `177-192`
- **Problem:** The APP_URL parse block is copied; the no-APP_URL fallback differs — `cmd_open` builds `https://${folder}.test` inline (ignoring `GROVE_URL_SUBDOMAIN`), `cmd_switch` uses `url_for`. The same worktree resolves to two different URLs depending on the command. The value cleaning also strips quotes/spaces globally and truncates at any `#`, inconsistent with the 01-core.sh parser.
- **Fix:** Extract `worktree_url <repo> <branch> <wt_path>` used by open/switch/info, mirroring 01-core.sh value cleaning. Resolve #7's validation in the same helper.

### 15. `cmd_prune --all-repos` throttle waits on the wrong PID; dead `_prune_single_repo` payload
- **Area:** app · **Category:** bug/maintainability · **Effort:** M
- **Files:** `lib/commands/git-ops.sh:392, 408-413, 419-423`
- **Problem:** Throttle does `wait "${pids[1]}"; shift pids` — jobs don't finish in launch order, so the concurrency cap isn't enforced. Separately, `operations+=("$repo_name|_prune_single_repo '$repo_name' '$git_dir'")` references a helper that doesn't exist and is never eval'd; the real worker recomputes git_dir. The shared `lib/09-parallel.sh` helper already does bounded parallelism correctly. (Note `parallel_run` itself silently drops jobs with a missing result file — fix together.)
- **Fix:** Route through `lib/09-parallel.sh` (and treat missing result files as failures there). Remove the dead payload. Add a test pruning >`GROVE_MAX_PARALLEL` repos.

### 16. `parallel_run` runs user/path strings via `sh -c` with unescaped interpolation
- **Area:** app · **Category:** security · **Effort:** M
- **Files:** `lib/09-parallel.sh:64-72`; callers `lib/commands/bulk-ops.sh:77, 150`
- **Problem:** Operations built as `"$wt_branch|cd '$wt_path' && ..."` then run via `sh -c "$cmd"`. A single quote in a worktree path breaks quoting; for exec-all the raw `$cmd_str` is concatenated unescaped. `_check_dangerous_command` is a trivially bypassable substring denylist, not a boundary.
- **Fix:** Pass path and command as separate argv to a fixed wrapper (`sh -c 'cd "$1" && shift && exec "$@"' _ "$wt_path" ...`) or use `${(q)wt_path}`. At minimum reject paths containing single quotes before building the op string.

### 17. `cmd_pull`/`cmd_sync` JSON mode return git's raw exit code, inconsistent with text mode
- **Area:** app · **Category:** consistency · **Effort:** S
- **Files:** `lib/commands/git-ops.sh:64, 356` vs `70`
- **Problem:** JSON paths `return $pull_exit_code` (raw git status, often 1) while text mode uses grove's curated `GIT_ERROR` code 4. A consumer switching on exit code sees a mode-dependent contract for the same failure.
- **Fix:** Normalise the JSON failure exit to code 4 after emitting the JSON body; keep 0 on success.

### 18 (merged docs cluster). `DB_BACKUP_DIR` default disagrees across 4 sources, and DB lifecycle is misdocumented as automatic
- **Area:** docs · **Category:** docs-accuracy · **Effort:** S
- **Files:** code default `lib/00-header.sh:24` (`~/.grove/backups`); wrong/divergent in `lib/99-main.sh:138` (`~/Code/Project Support/...`), `docs/reference/commands.md:2014`, `docs/reference/configuration.md:38,115`, `README.md:323`; DB-auto claims in `configuration.md:113-114, 30-37`, `README.md:496-501`, `.groverc.example:32`
- **Problem:** Four sources state three different `DB_BACKUP_DIR` defaults; `.groverc.example` is the only doc matching code. Separately, docs imply `DB_CREATE=true` auto-creates databases on `grove add`, but `lib/05-database.sh:4-9` explicitly delegates all DB work to user hooks — out of the box nothing happens.
- **Fix:** Standardise on `~/.grove/backups` everywhere (including the help string in 99-header). Reword DB_CREATE/DB_BACKUP docs to "gate reference helpers invoked by lifecycle hooks (see examples/hooks/), not automatic on add/rm".

### 19 (merged docs cluster). Roadmap & CHANGELOG materially misrepresent shipped state
- **Area:** docs · **Category:** docs-accuracy · **Effort:** M
- **Files:** `docs/development/roadmap.md:9-22, 78-100, 183-204, 245-251, 328-336, 442-462, 477-486`; `CHANGELOG.md:8-60`
- **Problem:** Roadmap "Current State" understates the test count (187 vs actual 271), lists non-existent `utility.sh`, omits `12-deps.sh` and real command modules, and marks shipped features (services, move, restructure, changes, dashboard, dependency-sharing, multi-repo, health score, fuzzy/@N matching) as not-done — risking duplicate reimplementation. CHANGELOG has a dated released-looking `[4.2.0]` above `[4.1.0]` while code is 4.1.0, the entire rebrand + services suite sits under `[Unreleased]` (implying absent from 4.1.0, which is false), and `move`/`setup` commands have no entry.
- **Fix:** Refresh roadmap module map and feature status from CLAUDE.md/code; tick shipped sections with versions. Reconcile CHANGELOG version order with `lib/00-header.sh`, fold `[4.2.0]`/`[Unreleased]` into the version that actually shipped them, add `move`/`setup` entries.

### 20. `_grove` completion drifts from the dispatcher (no enforcing test)
- **Area:** app · **Category:** consistency/maintainability · **Effort:** S
- **Files:** `_grove:124` (`version` not dispatched), `:204` (alias offers non-existent `get`, omits `add`/`rm`), `:241` (`share-deps` omits `clean`, prompts a non-existent repo arg)
- **Problem:** `grove version` falls through to the `*)` unknown-command arm (99-main.sh:316). Alias/share-deps completions advertise wrong subcommands. CLAUDE.md lists completion as a required maintained artefact but nothing enforces it.
- **Fix:** Correct the three completion entries (and either add a `version)` arm or remove it). Add a bats test extracting case labels from `lib/99-main.sh` and `commands=()` from `_grove`, asserting every dispatchable command appears in completion. Edit `_grove` (maintained), not compiled `grove`.

### 21. Uninstaller never removes the `wt` symlink the migration creates
- **Area:** app · **Category:** bug · **Effort:** S
- **Files:** `uninstall.sh:35-75`; `migrate-from-wt.sh:538`
- **Problem:** Migration creates a persistent `wt → grove` symlink and advertises it; uninstall only removes `grove`/`_grove`, leaving a dangling `wt` on PATH pointing at a deleted binary. Verified install.sh does not create `wt`, so it's purely a migrate/uninstall mismatch.
- **Fix:** In each candidate bin dir, remove `wt` only when `[[ -L "$dir/wt" ]]` and it resolves into the grove install. Keep the artefact list in sync across install/migrate/uninstall.

### 22 (merged docs cluster). Reference-doc accuracy: missing per-repo `GROVE_STALE_THRESHOLD`, wrong `DB_CREATE` per-repo claim, dead `share-deps clean`, fictional upgrade output
- **Area:** docs · **Category:** docs-accuracy · **Effort:** M
- **Files:** `docs/reference/configuration.md:72-77`; `docs/guides/advanced.md:315, 364-407`; `lib/01-core.sh:116-121`; `lib/12-deps.sh:243-277, 311`; `lib/commands/maintenance.sh:622-655, 729`
- **Problem:** Per-repo settings table lists `DB_CREATE` (NOT in the repo whitelist) and omits `GROVE_STALE_THRESHOLD` (which IS), so docs both promise an ignored override and hide a real one. `grove share-deps clean` is documented but `cmd_share_deps` dispatches only status/enable/disable and dies on `clean` (the implementing `cmd_share_deps_clean` is never wired). The advanced-guide upgrade output invents "Downloading/Verifying checksum/Installing/Release notes" steps the code never performs (misrepresenting the security model).
- **Fix:** Correct the per-repo table; add `clean) cmd_share_deps_clean` (and to usage/completion) or delete the doc line; replace upgrade sample output with the real steps.

---

## P2 — Notable correctness, security hardening, or consistency

### 23. `validate_name` under- and over-blocks reserved refs; `validate_git_ref` is weaker than `validate_name`
- **Area:** app · **Category:** security · **Effort:** M
- **Files:** `lib/02-validation.sh:75` (anchor-only `^(HEAD|refs/|@)`), `160-181`
- **Problem (merged 3 findings):** Verified the regex is prefix-anchored: it over-blocks `HEADER`/`HEADLESS-cms` (legitimate) and under-blocks mid-path `feature/heads/HEAD` and any trailing `.lock` (git-reserved lock form that reaches `git worktree add`/`git branch`). Separately `validate_git_ref` omits the leading-dot, trailing-dot, hidden-segment, reserved-ref and `.lock` checks `validate_name` enforces on the same token type, so the same value is judged differently per entry point.
- **Fix:** After cheap injection/charset pre-checks, delegate the authoritative decision to `git check-ref-format "refs/heads/$input"` in both validators. If staying pure-shell: match HEAD/refs as whole `/`-segments and block trailing `.lock`. Add tests: `HEADER` allow; `main.lock`, `feature/x.lock`, `feature/HEAD` block; bring `validate_git_ref` to parity.

### 24. `slugify_branch` only replaces `/`; spaces/dots/case/unicode flow into hostnames, URLs, DB names
- **Area:** app · **Category:** bug · **Effort:** M
- **Files:** `lib/03-paths.sh:5-7`; consumers 232-252; `lib/05-database.sh`; duplicate-logic `lib/02-validation.sh:138-157`
- **Problem (merged with the duplicate-implementation finding):** Verified `slugify_branch` is just `${1//\//-}`. `release/v1.2.3` → `v1.2.3.test` (extra DNS labels), `Feature/Login_Form` → invalid host, spaces/unicode reach the host/dir for branches created outside `grove add` or auto-detected. `normalize_branch_name` already implements the proper transform but path/host/DB use the weaker one — two divergent slug notions.
- **Fix:** Make `slugify_branch` lowercase, replace non-`[a-z0-9]` with `-`, collapse `--`, trim. Factor the shared transform so validation and path generation use one routine. Add `tests/unit/slugify.bats` for the cases above. Edit `lib/`, rebuild.

### 25. `site_name_for` collapses distinct branches sharing a final segment to one site/path/URL
- **Area:** app · **Category:** bug · **Effort:** M
- **Files:** `lib/03-paths.sh:20-31` (uses `${branch##*/}`)
- **Problem:** Verified `alice/dashboard` and `bob/dashboard` both → `dashboard`, hence same worktree dir, same `.test` URL, possible DB collision. The disambiguating hash only applies in the >max_length truncation branch (line 41), so short colliding names never get it. Two developers can silently point at one another's worktree.
- **Fix:** Slugify the full branch for the site name (`alice/dashboard` → `alice-dashboard`), or unconditionally append a short full-branch hash. Guard against empty/all-separator site names (`https://.test`, worktrees root) with a deterministic fallback.

### 26. `remote_branch_exists` hard-codes `/usr/bin/git` and `/usr/bin/ssh`; unanchored regex match
- **Area:** app · **Category:** portability/bug · **Effort:** S
- **Files:** `lib/04-git.sh:253`
- **Problem:** Pins `/usr/bin/git` + `GIT_SSH_COMMAND=/usr/bin/ssh` while the rest of the file uses PATH `git`; on Homebrew/Apple-Silicon/nix this can fail every remote check while everything else works. The `grep -q "refs/heads/$branch"` interpolates the branch as an unanchored regex, so `.` matches any char (false positives). Pull/sync paths share the `/usr/bin` pinning (cmd_pull:36, cmd_sync, `_pull_all_for_repo:142`).
- **Fix:** Use PATH-resolved `git`/`ssh` consistently; match the exact ref with `awk '$2==b'`.

### 27. Transaction/rollback system is entirely dead code and double-runs on EXIT+INT
- **Area:** app · **Category:** bug/maintainability · **Effort:** M
- **Files:** `lib/11-resilience.sh:76-144`
- **Problem:** Verified no callers in `lib/commands/`; the advertised crash-safety for `grove add`/`clone`/`move` does nothing. Same handler on EXIT+INT+TERM runs `transaction_rollback` twice on Ctrl-C; `${=remaining}` split drops empty args. Sits alongside other unused helpers (`with_retry`, `check_disk_space`, `step_progress`/`step_complete`).
- **Fix (decision):** Either wire the API into `cmd_add`/`cmd_clone`/`cmd_move` (and use `with_retry` for upgrade/clone fetch, `check_disk_space` before worktree creation), or delete the unused modules. If kept: trap EXIT only, set `GROVE_TRANSACTION_ACTIVE=false` at the top of rollback, split with `${(@ps:$US:)remaining}`.

### 28. Branch truncated to 30 chars makes fzf dashboard act on the wrong worktree
- **Area:** app · **Category:** bug · **Effort:** M
- **Files:** `lib/10-interactive.sh:193-196, 210-213, 256-262`
- **Problem:** Display line built from `${branch:0:30}`; reverse lookup matches the visible string back to the first matching entry. Two same-repo branches sharing a 30-char prefix produce identical lines, so the `r` (remove) action can delete the wrong worktree.
- **Fix:** Pass the full pipe record to fzf with `--delimiter='|' --with-nth=1` and parse the returned full line, or embed a unique token (wt_path/index). (Also fix the non-functional ctrl-r "refresh" bind and the `echo|fzf` → `print -r --|fzf` consistency in the same module.)

### 29. Pre-removal backup skipped when MySQL is merely unreachable (data-loss-adjacent)
- **Area:** app · **Category:** bug · **Effort:** M
- **Files:** `lib/05-database.sh:93, 133`
- **Problem:** Existence tested with `USE \`$db\``; any non-zero exit is treated as "doesn't exist" and the backup is silently skipped right before the worktree (and possibly the DB) is removed. A connection/auth failure is indistinguishable from absence. `info.sh:124`/`discovery.sh:124` already use the more accurate `information_schema` pattern.
- **Fix:** Probe connectivity (`SELECT 1`) first and warn loudly on failure; use `information_schema.SCHEMATA` to decide existence.

### 30. `cmd_cleanup_herd` orphan detection tests a possibly-relative symlink target against grove's cwd
- **Area:** app · **Category:** bug · **Effort:** S
- **Files:** `lib/commands/maintenance.sh:226-231` (also single-level `readlink` at 634-635, 739-740)
- **Problem:** `target="$(readlink ...)"` may be relative; `[[ ... && ! -d "$target" ]]` evaluates relative to grove's cwd, so a live site with a relative link can be judged orphaned and have its nginx config/certs/symlink removed (256-281), breaking a working site. Related: `cmd_upgrade`/`cmd_version_check` use single-level `readlink`, mis-resolving symlink chains.
- **Fix:** Canonicalise with zsh `:A` (`${site_link:A}`, `${wt_path:A:h}`) before the existence test and for repo-dir discovery.

### 31. `cmd_clean` deletes node_modules/vendor across all repos with no confirmation
- **Area:** app · **Category:** bug/safety · **Effort:** S
- **Files:** `lib/commands/discovery.sh:500-503, 538-544`
- **Problem:** Bare `grove clean` (no repo) iterates every repo under HERD_ROOT and `rm -rf`s node_modules/vendor for all inactive worktrees with no prompt. A `confirm()` helper that honours `--force` already exists (01-core.sh:280) and the recent commit added confirms for other destructive ops.
- **Fix:** Show the summary and call `confirm()` (auto-passes under `--force`) before deleting, or require `--yes`. Consider dry-run default + explicit apply flag.

### 32. `branch_deleted` JSON can report true when deletion didn't happen
- **Area:** app · **Category:** json-contract · **Effort:** S
- **Files:** `lib/commands/lifecycle.sh:350-353, 368` (and `db_dropped` at 368)
- **Problem:** `git branch -D ... || warn` swallows failure, then JSON unconditionally emits `"branch_deleted": $DELETE_BRANCH` (the request flag). Branch list in the consuming app desyncs. Same intent-vs-outcome issue for `"db_dropped": $DROP_DB` (DB drop is hook-delegated; grove can't know it happened).
- **Fix:** Track the real `git branch -D` result and emit that. Rename `db_dropped` → `db_drop_requested` and document the hook-delegated model.

### 33. `cmd_group add` skips `validate_name` that `cmd_group show` enforces
- **Area:** app · **Category:** consistency/security · **Effort:** S
- **Files:** `lib/commands/config.sh:582-590` vs `638-643`
- **Problem:** Add only checks `git_dir_for` + `[[ -d ]]` on raw input (running `git_dir_for` on un-gated input); show defensively calls `validate_name` and skips invalid names. Add persists names show later rejects.
- **Fix:** Call `validate_name "$repo" "repository"` at the top of the add loop, before `git_dir_for`.

### 34 (merged docs cluster). Docs-index omits the most important reference docs; surfaces archived snapshots as current
- **Area:** docs · **Category:** docs-accuracy/quality · **Effort:** S
- **Files:** `docs/README.md:7-27`
- **Problem:** `reference/commands.md` (43 KB, the per-command reference), `guides/advanced.md` (28 KB), `guides/services.md` (14 KB), and `release-packaging-verification.md` exist but are unlinked from the index. Meanwhile archived point-in-time review artefacts (implementation-plan, review-findings) are presented as current developer docs with a brittle hard-coded "71 items" count, and an internal `docs/superpowers/` tree sits unreferenced.
- **Fix:** Add the missing links (with a one-line "exhaustive per-command reference" note); move archived artefacts under a clearly labelled "Internal / historical" heading and drop the brittle count; relocate or explicitly label `superpowers/`.

### 35 (merged docs cluster). Advanced-guide repository/architecture trees list a non-existent `utility.sh` and omit real modules; broken example links; stale counts
- **Area:** docs · **Category:** docs-accuracy · **Effort:** S
- **Files:** `docs/guides/advanced.md:473-483, 840, 858-895`; `docs/guides/tutorials.md:586, 638`
- **Problem:** Repository-structure tree lists `utility.sh` (doesn't exist; it's `maintenance.sh`) and omits bulk-ops/config/discovery/services; services subsystem absent from both Architecture and docs trees; examples tree references the wrong repo-specific folder name and omits real hooks. tutorials.md links `examples/hooks/README.md` with a path that 404s from `docs/guides/` and quotes a stale "204 tests" (actual 271).
- **Fix:** Regenerate trees from the actual layout (CLAUDE.md as source of truth); fix the relative link to `../../examples/hooks/README.md`; replace fixed test counts with "270+".

### 36. Tutorials "all commands" cookbook omits 5 real commands; hook lists omit move/switch hooks
- **Area:** docs · **Category:** docs-accuracy · **Effort:** S
- **Files:** `docs/guides/tutorials.md:81-514, 539, 551-554`; `README.md:346`; `docs/guides/getting-started.md:188-198`
- **Problem:** "Command cookbook (all commands)" omits `changes`, `branches`, `restructure`, `config`, `services` (all dispatched in 99-main.sh). Multiple hook lists (tutorials, getting-started, README) omit `post-switch`/`pre-move`/`post-move` though the code fires them, and README's hook-variable list drops `GROVE_BRANCH_SLUG`/`GROVE_HOOK_NAME` that `.groverc.example` documents.
- **Fix:** Add the missing cookbook entries (or retitle "common commands" + point to `grove --help`/services.md); add the three lifecycle hooks and the two hook variables across the doc set.

### 37. Example hook "non-Laravel skip via exported env from a sibling hook" cannot work
- **Area:** docs · **Category:** docs-accuracy · **Effort:** S
- **Files:** `examples/hooks/README.md:419-430`; behaviour from `lib/06-hooks.sh:49-69, 109-135`
- **Problem:** Verified each hook runs in its own subshell and repo-specific hooks run *after* all global hooks. So `export GROVE_SKIP_*` in a repo-specific hook neither propagates to siblings nor runs before the global Laravel hooks it tries to skip — broken on both counts.
- **Fix:** Replace with a working mechanism: `GROVE_SKIP_DB=true grove add ...`, `.groveconfig` (`DB_CREATE=false`), or simply not installing the Laravel hooks. Remove the broken export example.

### 38. Migration rewrites real shell rc files in place with unanchored sed, under-communicated
- **Area:** docs/app (aux script) · **Category:** bug · **Effort:** M
- **Files:** `migrate-from-wt.sh:138-186, 428-489, 519-533`
- **Problem:** `sed -i` runs against `~/.zshrc`/`~/.bashrc`/etc. whenever they contain substring `WT_`, with global unanchored expressions, so unrelated identifiers (`WT_EDITOR_THEME`), comments, and strings are silently rewritten. The confirmation prompt never warns startup files will be edited. Double-backup/double-count and a redundant/loose `create_symlink` guard compound the fragility.
- **Fix:** Make rc rewriting opt-in/advisory or anchor to assignment/reference boundaries (`export WT_...`, `WT_...=`, `${WT_...}`); list every file to be edited and require explicit confirmation; take one backup per item.

### 39 (merged docs cluster). Release-packaging-verification doc: validates 2 of 12 endpoints, lint dimension unstated, frozen one-PR snapshot framed as reusable
- **Area:** docs · **Category:** docs-accuracy/quality · **Effort:** S
- **Files:** `docs/release-packaging-verification.md:78-96, 111, 122-127, 184-185`
- **Problem:** The only scripted pre-flight loop iterates `repos recent` while the matrix claims all 11+ JSON endpoints are verified; `./run-tests.sh` can report green with shellcheck silently SKIPPED; the doc is scoped to one merged PR yet titled as a reusable guide; the Python `json.load` idiom is duplicated ~13×.
- **Fix:** Expand the loop to the full matrix (split single-arg from repo/branch endpoints) or relabel it a smoke sample; note shellcheck must be installed for a complete gate; split reusable checklist from PR-specific retrospective; provide one parameterised verification script.

---

## P3 — Minor correctness, polish, robustness

Grouped for brevity; each is low-risk and individually small.

**Config parsing hardening (`lib/01-core.sh`)** — S each:
- `GROVE_STALE_THRESHOLD` unvalidated before arithmetic (98/120 → 04-git.sh:489); validate `^[0-9]+$` like `validate_max_parallel`.
- `DB_CREATE`/`DB_BACKUP` accept any string; normalise to strict `true`/`false` with a warn (root cause of #12).
- Inline-`#` stripping mangles unquoted values with `#` (passwords); strip only ` #...`.
- `$HOME`/`~` expansion applied to every value; restrict to path-typed keys.
- `bytes_to_human` drops decimals at unit boundaries/T cap; `json_get_*` naive — document flat-JSON-only.

**Shared-deps module (`lib/12-deps.sh`)** — S each: `_calculate_lockfile_hash` ignores pipefail / truncates to 48 bits; `_check_deps_shared` ignores dep-type subdir & relative targets; `cmd_share_deps` recursion mutates `DETECTED_*` globals; `cmd_share_deps_clean` reimplements `bytes_to_human` with empty-size abort risk.

**git-ops library (`lib/04-git.sh`)** — S each: `cached_fetch` hides fetch stderr (inconsistent with `force_fetch`); `ensure_fetch_refspec` unchecked `git config --add`; `set_worktree_base` swallows write failure; `get_cached_status` no default arm; `check_worktree_mismatches` overloads exit code as count; `get_last_accessed_iso` uses `echo` vs file's `print -r` idiom; `stale_refs_pruned` screen-scrapes localised "Removing" lines (force `LC_ALL=C`).

**Database (`lib/05-database.sh`)** — S each: `db_name_for` doesn't neutralise backticks (defence-in-depth); empty md5 → non-unique truncated name; reserve-space comment (11) vs maths (10); create/drop exit-code semantics disagree; `cleanup_herd_site` removes paths from unvalidated `site_name`; bare `rm` vs `/bin/rm` inconsistency.

**Hooks security/portability (`lib/06-hooks.sh`)** — S each: rejects only world-writable (not group-writable hooks or untrusted hook dirs); single-hook any-exec vs `.d` owner-exec mismatch; `.d` lexical sort (non-zero-padded `2` after `10`) — use `n` glob qualifier or document zero-padding; bare glob qualifiers without `setopt local_options bare_glob_qual no_nomatch`; hooks inherit stdin with no timeout (deadlock risk in bulk/JSON flows — `< /dev/null`).

**Infra libs (`lib/07-08-09`)** — S each: `load_template` exports/leaks `GROVE_SKIP_*` into hooks without reset; `format_json` colourisation corrupts values with `:`/quotes (use `jq -C`); spinner relies on MULTIBYTE & disown-only stop (add `kill -0 $PPID` backstop, array frames); `wait -n` gated on major version (needs `is-at-least 5.9`); `parallel_run` hardcodes `/usr/bin/mktemp`/`/bin/rm` & no tmpdir check.

**Interactive (`lib/10-interactive.sh`)** — S each: hardcoded `--query=origin/staging` ignores `DEFAULT_BASE`; create-confirm only matches `^[Nn]$` (typing "no" still creates); detached-HEAD dropped from dashboard/select; undeclared loop var `entry`; empty remote-branch list opens empty fzf silently.

**Main dispatch (`lib/99-main.sh`)** — S each: `templates` command missing from help; `-n` split-ownership keeps non-numeric arg; no `--` end-of-options sentinel (breaks `exec`/`exec-all` pass-through); global flags silently accepted on any command (warn on destructive-flag misuse).

**Lifecycle polish (`lib/commands/lifecycle.sh`)** — S each: `_update_env_app_url` `mv` drops original `.env` perms/symlink (preserve mode with `stat`, or rewrite in place); `cmd_move` tears down old Herd site without asserting new path landed; `cmd_move` hand-builds `new_url` (drift from `url_for` — add `url_for_site_name`); `cmd_clone` duplicates base-branch ladder ignoring `DEFAULT_BASE`; `cmd_fresh` `pushd` without restore trap; `cmd_add` cleanup trap uses misleading `local`.

**Discovery/nav polish (`lib/commands/discovery.sh`, `navigation.sh`)** — S each: `GROVE_ALIASES_FILE` declared in discovery.sh but consumed only in config.sh (move it); `cmd_recent --limit` unvalidated into array slice (validate `<->`); `cmd_recent` URL uses last-loaded repo config for all entries (resolve url during collection loop — **note this is a JSON-contract `url` corruption, arguably P2**); APP_URL global quote/space strip + `#` truncation; `open`/`xdg-open` portability; `cmd_clean` hardcoded 30-day window; `cmd_info` Laravel version regex picks wrong package (use `jq`); `cmd_info` eager du×3 + sync MySQL even for `--json`; non-actionable `[N]` index.

**Services polish (`lib/commands/services.sh`)** — S each: `remove` unescaped grep regex (`my.app` matches `myXapp`); `doctor` parses `ls|wc -l` (use glob); Horizon reported Inactive without checking php/artisan; trim deletes internal spaces; malformed `apps.conf` line registers bogus app.

**Maintenance/Laravel polish (`lib/commands/maintenance.sh`, `laravel.sh`)** — S each: `cmd_upgrade` discards git stderr then says "resolve conflicts manually"; `cleanup_herd_site` counts failed `rm` as success; missing origin/master fallback for "recent changes" log; `migrate`/`tinker` don't check `php` or propagate artisan exit status; `migrate`/`tinker` near-identical (extract helper); `doctor` MySQL check ignores non-default port (add `DB_PORT`); `doctor` always returns 0 (return non-zero on issues for CI).

**Bulk-ops/config polish (`lib/commands/bulk-ops.sh`, `config.sh`)** — S each: exec_all/build_all single-quoted `cd` breaks on quote in path (use `${(q)}`); alias target allows `=`/leading dash (use whitelist); `_check_dangerous_command` overstated wording; `customization` → `customisation` (British English).

**Build/install scripts** — S each: `run-tests.sh` masks bats exit via `set -e`+`local exit_code=$?`; relies on unset nullglob; `build.sh` blindly strips line 2 (gate on actual shebang) and loose `--output` parsing; `install.sh` only rebuilds when `grove` absent (not when lib/ newer); install scaffolds `post-switch.d` but not `pre-move.d`/`post-move.d`; `install.sh local var=$(...)` masks failures; `_grove` services completion offers no app-name candidates.

**Remaining doc accuracy (P3)** — S each: `grove report` missing from README Quick Reference + `--output` flag; "No extra configuration needed" overstates services auto-restart; global flags `--no-cache`/`--refresh` and `GROVE_FETCH_CACHE_TTL` undocumented in commands.md; fuzzy branch matching undocumented; `DEFAULT_EDITOR`/`GROVE_EDITOR` not noted as the same setting; no shell-completion section; `--pretty` per-command table inaccurate; `GROVE_CONFIG` documented as file-settable (env-only); config-value expansion rule undocumented; setup-wizard steps overstate behaviour; platform table understates the hard non-macOS block; undocumented example hooks `09`/`10`; `post-rm.d/myapp` undocumented; inconsistent worktree-template paths; "Available in all hooks" overstates conditional vars; architecture-diagram hook-list inconsistencies; branch-validation sample output doesn't match real text; v4.0.0/v4.1.0 version drift in advanced.md; IMPLEMENTATION.md internal contradictions (271 vs 267, shellcheck status, "ALL FIXED" vs deferred items); CHANGELOG dash style + `wt`/`grove` prefix mixing; services-guide "Not configured"/horizon-URL clarity.

---

## Cross-cutting themes

1. **Intent-vs-outcome dishonesty in the JSON contract.** Multiple commands emit request flags as if they were results (`branch_deleted`, `db_dropped`), report `0/0` for "base unresolved", drop missing-result jobs so `total ≠ succeeded+failed`, and pass through untrusted `.env` `url`. The contract is *syntactically* protected by `json_escape` but *semantically* unreliable. Fixes #2, #7, #9, #11, #12, #15, #32.

2. **The hook model is documented as more capable and automatic than it is.** Pre-hooks can't veto (#3), DB lifecycle is hook-delegated not automatic (#18), the skip-via-export example can't work (#37), and aliases/groups resolvers are never wired (#10). Either close the code gap or correct the docs — but the two must agree.

3. **Copy-paste divergence is the dominant maintainability risk.** Porcelain parsing (4×, #6), open/switch URL parsing (#14), migrate/tinker (#42-cluster), clone base ladder, prune's hand-rolled parallelism vs the shared helper (#15), and two slug notions (#24) all drift independently — and several have already drifted (restructure last-entry #8, recent per-repo URL). Extract shared helpers and route everything through them.

4. **Authoritative-source delegation is underused for git semantics.** Validation reinvents `check-ref-format` and gets edge cases wrong (#23), stale counts screen-scrape localised git output, and remote checks use regex substring matching (#26). Delegating to git (with cheap pre-checks) is both safer and simpler.

5. **Destructive operations lack the project's own safety rails.** `cmd_clean` (#31), `check_index_locks` (#4), `cmd_upgrade` rebase (#5), and `cleanup_herd_site` relative-symlink test (#30) all destroy state without the `confirm()`/process-check/assert-end-state guards used elsewhere.

6. **Documentation has drifted from a fast-moving codebase.** Roadmap/CHANGELOG mark shipped features as pending (#19), the docs index omits its largest references (#34), trees list non-existent modules (#35), and four sources disagree on one default (#18). A single "regenerate from code/CLAUDE.md" pass plus a sync test (#20) would retire most of these.

---

## Quick wins (high value, low effort)

1. **#1** Fix `cmd_report` newlines (`printf '%b\n'` or real newlines) — broken feature, S.
2. **#12** Normalise `cmd_config` booleans to `true`/`false` — prevents invalid JSON throwing in the Tauri app, S.
3. **#13** Anchor alias-removal grep to `^name=` — stops deleting unrelated aliases, S.
4. **#17** Return GIT_ERROR code 4 from JSON pull/sync failures — exit-code contract parity, S.
5. **#21** Remove the dangling `wt` symlink in uninstall — broken command left on PATH, S.
6. **#32** Emit real `branch_deleted`/`db_drop_requested` — stops desyncing the app's branch list, S.
7. **#26** Use PATH `git`/`ssh` + exact-ref `awk` in `remote_branch_exists` — fixes silent remote-check failures, S.
8. **#11 (partial)** Route `services apps --json` through `format_json` — honours `--pretty` like every other command, S.
9. **#18 / #34 / #35** Batch doc fixes: standardise `DB_BACKUP_DIR` default, add the missing docs-index links, replace `utility.sh` with `maintenance.sh` — pure docs, S.
10. **#20** Correct the three `_grove` completion entries and add the dispatcher-vs-completion sync test — converts a manual CLAUDE.md step into an enforced invariant, S.
11. **P3** Validate `GROVE_STALE_THRESHOLD`/`cmd_recent --limit` as integers — prevents `set -e` aborts on bad input, S.
12. **P3** `customization` → `customisation` in `lib/commands/config.sh:2` — British-English convention, trivial.

All app fixes must edit `lib/` sources and run `./build.sh` + `./run-tests.sh`; never edit the compiled `grove`. Validate every touched `--json` command with `python3 -m json.load` per CLAUDE.md.

---

## Appendix A — Additional finding caught during verification (not in the agent output)

### `grove dashboard --json` emits the interactive TUI instead of JSON
- **Area:** app · **Category:** json-contract/consistency · **Effort:** S · **Severity:** P3
- **File:** `lib/commands/info.sh` `cmd_dashboard` (the `--json` flag is not honoured; the box-drawing dashboard renders to stdout)
- **Problem:** `grove dashboard --json` outputs raw terminal escape sequences (the dashboard UI), which is not valid JSON. Confirmed live: `./grove dashboard --json | python3 -m json.tool` → `JSONDecodeError`. `dashboard` is **not** in the documented JSON data contract (CLAUDE.md lists repos/recent/ls/branches/health and services apps), so this is a consistency nit rather than a contract breakage — but a consumer that blindly appends `--json` gets garbage rather than an error or an empty array.
- **Fix:** Either emit a JSON representation of the dashboard when `--json` is set, or reject `--json` for `dashboard` with a clear error. Whichever, document the decision.

## Appendix B — Method notes

- The first (discarded) run is a cautionary example: large fan-out audits can produce confident, well-formatted, entirely fictional findings when subagent tools degrade. Treat any audit's "EXECUTION-VERIFIED" claims as unverified until reproduced.
- The retained findings in this plan were additionally spot-checked by hand against the live tree (P1s, a sample of P2 security/json-contract/portability items, and the docs-accuracy `DB_BACKUP_DIR` / aliases-groups / roadmap items). They held up.
