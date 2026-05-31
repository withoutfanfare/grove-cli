# grove-cli — Internal Readiness Implementation Plan

**Goal:** make `grove` safe and friction-free for the wider internal team to adopt.
**Audited version:** 4.1.0 · **Branch:** `chore/internal-readiness-audit` · **Date:** 2026-05-29

> **Status (2026-05-30): implemented and shipped.** The P0–P3 work from this plan has
> landed on `chore/internal-readiness-audit` (see commits `590547c`, `76ef9be`). For
> example, P1-1 (`grove migrate` not wired into the dispatcher) is fixed —
> `migrate` now dispatches at `lib/99-main.sh:309` — and P1-6 (CONTRIBUTING telling
> contributors to edit the generated `grove` file) is resolved. **Treat this document as
> a historical audit record, not a list of open work**; the findings below describe the
> *pre-fix* state. For current behaviour, see the [documentation](docs/README.md).

> **How this was produced.** An 8-dimension review team (security, shell-correctness,
> JSON contract, git-ops, database, services, docs, setup/onboarding) read the `lib/`
> source. Every critical/high finding was then handed to an independent agent told to
> *refute* it; only findings that survived refutation appear here, at their
> verifier-adjusted severity. The headline critical and all P1 bugs were additionally
> reproduced by hand (commands shown inline).

> ## ✅ Implementation status — ALL FIXED (2026-05-29)
>
> Every finding below (P0 → P3) has been implemented on branch `chore/internal-readiness-audit`,
> editing `lib/` source then rebuilding via `./build.sh`. **Verified:** `grove` rebuilt and in
> sync, `zsh -n` clean, **271 tests pass** (incl. a new `tests/unit/env-rewrite.bats` exercising
> the real P0 fix), `shellcheck` installed and the **lint stage now runs and passes**, and **9/9
> `--json` commands validate** against a real repo+worktree fixture.
>
> **Three extra bugs found *during* implementation and also fixed:**
> 1. **`grove services doctor` aborted on the first failed check** — 7× `((issues++))` trip `set -e`
>    in zsh exactly like the installer bug (P1-5). Fixed to `issues=$((issues + 1))`.
> 2. **`get_commit_age` aborted for any worktree < 1 day old** — `(( age_days = age_seconds / 86400 ))`
>    returns exit 1 when the result is 0, truncating the age display. Fixed to the safe `var=$((…))` form.
> 3. **`status --json` returned text, not `[]`, for an empty repo** — fixed alongside P1-3.
>
> **Two structural notes for the team (not yet changed — flagged for a decision):**
> - **shellcheck cannot lint the zsh sources.** `grove`/`build.sh`/`lib/*` use zsh-only syntax
>   (`*.git(N)`, `${(k)arr}`) that shellcheck (a bash linter) cannot parse. `run-tests.sh` now
>   `zsh -n`-parses the zsh files and runs shellcheck only on the genuine bash scripts.
> - **The BATS unit tests reimplement functions in bash** (`tests/test-helper.bash`) rather than
>   exercising the shipped zsh — e.g. its `json_escape` uses `echo` while the real one sets `$REPLY`.
>   So coverage of the *actual* code is thinner than the count implies. The new `env-rewrite.bats`
>   sources the real `grove` instead; consider migrating other unit tests to that pattern.
> - **P2-5 dead transaction machinery** (`lib/11-resilience.sh`) was left in place; the concrete
>   safety win (reordering `cmd_move` so the worktree move precedes Herd teardown) is done. Wiring
>   or removing the unused rollback code is a follow-up decision.

---

## TL;DR

grove's **core is in good shape** — the build is reproducible, 267 tests pass, input
validation is strict, config is parsed as a whitelist (never sourced), and database
helpers use `MYSQL_PWD` rather than `-p`. The problems are concentrated in (a) **two
worktree commands that silently destroy `.env` files**, (b) **the newest `services`
module and the `--json` contract**, and (c) **onboarding docs/installer that mislead or
abort**. None of these are hard to fix; together they are exactly what would burn a new
teammate in their first week.

**Recommended gate for internal release:** ship P0 + all P1 first. They are the
trust-breakers.

| Priority | Count | Theme |
|---|---|---|
| 🔴 **P0 — Critical** | 1 | Silent `.env` data loss |
| 🟠 **P1 — High** | 6 | Broken documented commands, JSON-contract breaks, installer abort, contributor footgun |
| 🟡 **P2 — Medium** | 22 | Correctness, safety rails, doc drift, config consistency |
| ⚪ **P3 — Low** | 13 | Polish, latent traps, completeness |

*(42 unique findings; several raw findings were merged across review dimensions — see Appendix.)*

### Baseline verified before the audit (all green — keep it that way)

| Check | Command | Result |
|---|---|---|
| Build reproducible | `./build.sh --output /tmp/g && diff grove /tmp/g` | ✅ in sync |
| Parses | `zsh -n grove` | ✅ clean |
| Tests | `./run-tests.sh` | ✅ 267 passed |
| Version | `./grove --version` | ✅ 4.1.0 |

> ⚠️ **`shellcheck` was not installed**, so the lint stage was silently skipped while
> still printing "All tests passed" (see P2-13). Install it before trusting a green run:
> `brew install shellcheck`.

---

## 🔴 P0 — Critical (fix before anyone else uses `move`/`restructure`)

### P0-1 · `grove move` and `grove restructure` destroy the entire `.env` below `APP_URL=`
- **Where:** `lib/commands/lifecycle.sh:458` (`cmd_move`), `lib/commands/lifecycle.sh:715` (`cmd_restructure`)
- **Category:** data-loss · **Confidence:** confirmed (reproduced by hand)
- **The bug:** the URL rewrite uses a greedy zsh glob over the whole-file string:
  ```zsh
  content="${content/APP_URL=*/APP_URL=$new_url}"
  ```
  `APP_URL=*` matches greedily **across newlines**, so everything from the first
  `APP_URL=` to end-of-file is collapsed into one line.
- **Reproduced:**
  ```text
  Input  (7 lines): APP_NAME, APP_ENV, APP_URL, DB_CONNECTION, DB_PASSWORD, MAIL_HOST, QUEUE_CONNECTION
  Output (3 lines): APP_NAME, APP_ENV, APP_URL=http://new.test
  → DB_CONNECTION, DB_PASSWORD, MAIL_HOST, QUEUE_CONNECTION silently deleted.
  ```

  The file is overwritten in place with **no backup**. `restructure` does this to *every*
  migrated worktree in one bulk run.
- **Fix:** rewrite line-by-line, replacing only the line that begins with `APP_URL=`, and
  write via a temp file. e.g.:
  ```zsh
  local out="" line
  while IFS= read -r line; do
    if [[ "$line" == APP_URL=* ]]; then out+="APP_URL=$new_url"$'\n'
    else out+="$line"$'\n'; fi
  done < "$env_file"
  print -rn -- "$out" > "$env_file.tmp" && mv "$env_file.tmp" "$env_file"
  ```
  Apply at **both** sites. Rebuild with `./build.sh`.
- **Regression test:** add a bats test asserting a multi-line `.env` retains all
  non-`APP_URL` keys after `move`. This is the single most important test to add.
- **Verify:** the reproduction snippet above should keep all 7 lines.

---

## 🟠 P1 — High (onboarding trust-breakers)

### P1-1 · Documented `grove migrate` is not wired into the dispatcher — every call fails
- **Where:** `lib/99-main.sh` `case` block (no `migrate)` branch); `cmd_migrate` exists at `lib/commands/laravel.sh:4`
- **Confirmed:** `./grove migrate` → `✖ ERROR: Unknown command: migrate`. It is documented in
  `--help` (`99-main.sh:40`), `README.md:172`, `docs/reference/commands.md`, and the `_grove` completion.
- **Fix:** add `migrate)      cmd_migrate "$@" ;;` to the `case` in `lib/99-main.sh` (next to `fresh`/`tinker`); `./build.sh`.
- **Verify:** `./grove migrate <repo> <branch>` reaches the function.

### P1-2 · `--json` data-contract break #1: `services apps --json` returns all-empty fields
- **Where:** `lib/commands/services.sh:371-376`
- **The bug:** `json_escape` **sets `$REPLY`** and prints nothing, but `services` calls it via
  command substitution `"$(json_escape "$app_name")"` — so every field captures empty stdout.
  This is the **only** site in the codebase misusing the helper; ~70 other call sites use the
  correct `json_escape "$x"; var="$REPLY"` form.
- **Impact:** the grove-app Tauri client receives structurally-valid JSON with every
  `name`/`system_name`/`services`/`supervisor_process`/`domain` blank — silent data loss.
- **Fix:** switch to the REPLY pattern (or accumulate into an array joined with `${(j:,:)items}`
  like `cmd_ls`). Rebuild.
- **Verify:** `./grove services apps --json | python3 -c 'import json,sys; print(json.load(sys.stdin))'` shows real values.

### P1-3 · `--json` data-contract break #2: `status --json` and `summary --json` print progress text first
- **Where:** `lib/commands/info.sh:348-349` (`cmd_status`), `lib/commands/git-ops.sh:726-727` (`cmd_summary`)
- **The bug:** both call `info "Fetching latest..."` + `cached_fetch` (which `dim`s a cache-age line)
  **unconditionally**, before the JSON branch. `info()`/`dim()` write to stdout gated only by `QUIET`,
  never by `JSON_OUTPUT`. So the first stdout line is `→ Fetching latest...` and `json.load` fails.
- **Pattern to copy:** `cmd_pull`, `cmd_sync`, `cmd_prune`, `cmd_branches` already guard with
  `[[ "$JSON_OUTPUT" != true ]] && info ...`. `status` and `summary` are the two that forgot.
- **Fix:** add the same guard at both sites; route `cached_fetch`'s `dim` to stderr or suppress it in JSON mode. Rebuild.
- **Verify:** `./grove status <repo> --json | python3 -c 'import json,sys; json.load(sys.stdin)'` parses.

### P1-4 · `grove services restart all` is a silent no-op
- **Where:** `lib/commands/services.sh:306-328`
- **The bug:** the "unregistered app → return silently" guard runs **before** the `if [[ "$app" == "all" ]]`
  branch. `all` is never a registered key, so the function returns 0 without restarting anything.
  `services stop all` / `start all` put the `all` check first and work correctly.
- **Impact:** `README.md:182` advertises `restart all # restart everything`. After a deploy a teammate
  believes workers restarted; stale workers keep running old code. False success, exit 0.
- **Fix:** move the `all` handling **before** the registration guard, mirroring `cmd_services_stop`. Rebuild.
- **Verify:** `grove services restart all` iterates and prints each app.

### P1-5 · `install.sh` aborts mid-install: `((installed++))` trips `set -e`
- **Where:** `install.sh:511`, `:516` (`((skipped++))`), `:569`; `set -e` at `install.sh:2`
- **The bug:** `((expr))` returns exit 1 when the result is 0; post-increment from 0 yields 0, so the
  **first** increment aborts the script under `set -e`. Confirmed by hand.
- **Impact:** first-time hook install dies after copying one hook; PATH check, completions check, and the
  "Installation complete / quick start" guidance never print. Looks like a silent crash.
- **Fix:** use `installed=$((installed+1))` (and `skipped=$((skipped+1))`) — the safe form already used in
  `migrate-from-wt.sh`.
- **Verify:** run `install.sh` against a clean `~/.grove`; it copies all hooks and prints the completion banner.

### P1-6 · `CONTRIBUTING.md` tells contributors to edit the **generated** `grove` file
- **Where:** `CONTRIBUTING.md:32-95`
- **The bug:** Dev Setup symlinks `grove` as `grove-dev`; "Architecture Notes" describe a single
  monolithic script and say to add commands by editing `main()` and `show_help()`. It never mentions
  `lib/`, `build.sh`, or that `grove` is generated — the exact opposite of CLAUDE.md's #1 rule.
- **Impact:** a new contributor edits `grove` directly; `./build.sh` (also auto-run by `grove upgrade`)
  silently overwrites their work.
- **Fix:** rewrite Development Setup + Architecture Notes to mirror CLAUDE.md (edit `lib/`, run `./build.sh`,
  never edit `grove`); list the module layout; add `./build.sh` + `./run-tests.sh` to the PR checklist.

---

## 🟡 P2 — Medium (correctness, safety rails, accuracy)

> All cite `lib/` source. After any code change: `./build.sh` then re-run the relevant `--json`/command check.

#### Correctness & safety
| ID | Finding | Where | Fix |
|---|---|---|---|
| P2-1 | `grove health` aborts before the Summary on a branch/dir mismatch (`set -e` + a function that `return`s a count) | `info.sh:1222`, `04-git.sh:520-542` | Guard the call with `if`/`||`, or print the count and `return 0` |
| P2-2 | Interactive `add` wizard dies on a failed `git fetch` | `10-interactive.sh:40` | `... || warn ...` fallback; line 43 already tolerates stale data |
| P2-3 | `grove status` aborts when fetch fails (offline + `--no-cache`) | `info.sh:349` | `cached_fetch ... || dim ...`; status is read-only |
| P2-4 | `grove repair` reports "No stale locks" **after** deleting `index.lock` files (counter never incremented on the auto-clean path) | `11-resilience.sh:44` | Increment `locks_found` in the auto-clean branch too |
| P2-5 | `move`/`restructure` have **no rollback**; the whole `transaction_*`/`with_retry`/`check_disk_space` machinery is dead code (zero call sites) | `11-resilience.sh:5-143`; `lifecycle.sh:417-465` | Wire it into `move`/`restructure`, or delete it and reorder `cmd_move` so `git worktree move` succeeds *before* tearing down the Herd site |
| P2-6 | `prune` hardcodes `origin/staging` and excludes branches with an **unanchored** `grep -v 'staging\|main\|master'` (wrongly skips `feature/main-nav`, `remaster`; finds nothing on main-based repos) | `git-ops.sh:467` | Use the configured base; anchor with `grep -vE '^(staging|main|master)$'`; fix the JSON `reason` field |
| P2-7 | `restructure` bulk-moves worktrees with no confirmation and no dirty-tree check (compounds P0-1); `git` errors hidden by `2>/dev/null` | `lifecycle.sh:651-760` | Add a `FORCE`-gated confirm; surface per-worktree failures |
| P2-8 | `sync` leaves a conflicted rebase in place (no `git rebase --abort`), unlike `cmd_upgrade` | `git-ops.sh:326,356` | On rebase failure run `git -C "$wt_path" rebase --abort` and report the conflict |
| P2-9 | `diff --json` is silently ignored — always prints human text, never JSON | `git-ops.sh:623-686` | Add a JSON branch mirroring `cmd_summary`, **or** reject `--json` with a clear error |

#### Database & security
| ID | Finding | Where | Fix |
|---|---|---|---|
| P2-10 | `grove health` and `grove info` leak the MySQL password via `-p"$DB_PASSWORD"` (visible in `ps aux`) — inconsistent with the rest of the code, which uses `MYSQL_PWD` | `info.sh:1163-1164`, `discovery.sh:122-123` | Drop the `-p` line; invoke `MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" -e ...` |
| P2-11 | `docs/guides/advanced.md:667-668` guarantees credentials are "**never** visible in `ps aux`" — false given P2-10 and the example hooks | `docs/guides/advanced.md:667-668` | Fix P2-10 **and** convert the example DB hooks to `MYSQL_PWD`, then the doc becomes true |
| P2-12 | `lib/05-database.sh` `create/backup/drop_database` are **dead code** (never called) — real DB work lives in `examples/hooks/`, which use the less-safe `-p` form. Misleads anyone reading "how does grove manage DBs?" | `05-database.sh:37-141` | Either wire the safe functions into `add`/`rm`, or delete them and add a header pointing to `examples/hooks/`; reflect the chosen model in CLAUDE.md |
| P2-15 | `services add` validation is bypassed: calls the **non-existent** `validate_repo_name` masked by `2>/dev/null \|\| true`, so app names get zero validation (a `\|` corrupts the pipe-delimited `apps.conf`). *(No path-traversal risk — grove never writes a plist — so this is config-integrity, not an exploit.)* | `services.sh:407` | Replace with `validate_name "$name" "repository"` (no error mask); add a rejection test |

#### Config, install & doc accuracy
| ID | Finding | Where | Fix |
|---|---|---|---|
| P2-13 | `run-tests.sh` silently skips `shellcheck` when absent yet prints "All tests passed" | `run-tests.sh:40-44,111,168` | Treat missing shellcheck as a hard error on a full run (like `check_bats`), or print a clear "LINT SKIPPED" and qualify the summary; document `brew install shellcheck` as required |
| P2-14 | `services apps --json` prints a human sentence (not `[]`) when no apps are registered → parse error for every new teammate's first run | `services.sh:330-339` | Move the `JSON_OUTPUT` check above the `svc_has_apps` short-circuit (`cmd_services_apps_json` already emits `[]`) |
| P2-16 | `.groverc.example:12` sets `HERD_ROOT=$HOME/Herd`, but the config parser never expands `$HOME`; copying it to `~/.groverc` (per README) gives a literal `$HOME/Herd` path and `grove repos` finds nothing | `.groverc.example:12`, `01-core.sh:35-65` | Expand `$HOME`/`~` in `load_config`, **or** ship an absolute edit-me path. (`grove setup` already writes expanded paths.) |
| P2-17 | `DB_BACKUP_DIR` default differs three ways: header/installer use `~/Code/Project Support/...` (a personal path), the setup wizard uses `~/.grove/backups` | `00-header.sh:24`, `install.sh:383`, `config.sh:489` | Standardise on `~/.grove/backups` everywhere; drop the personal path |
| P2-18 | `install.sh` symlinks `grove` without checking it exists and never runs `build.sh` — a missing/stale artifact installs silently as success | `install.sh:303-307,657-669` | Guard: if `grove` is missing run `build.sh` (or die); verify `grove --version` before printing success |
| P2-19 | `--help` omits the dispatched `restructure` and `dashboard` commands | `lib/99-main.sh` `usage()` | Add both to `usage()`; also add `restructure` to README |
| P2-20 | `_grove` completion missing 5 real commands (`branches`, `changes`, `config`, `summary`, `restructure`) and still offers the broken `migrate` | `_grove:83-125` | Add the 5; fix/remove `migrate` after P1-1 |
| P2-21 | CLAUDE.md says "168 tests" (actual **267**) and never mentions `lib/commands/services.sh` (largest module) | `CLAUDE.md:164`, `CLAUDE.md:60-130` | Update the count (or "~270"); add a `services.sh` line to the architecture tree + placement guide |
| P2-22 | `.groverc.example` documents only 1 of 9 lifecycle hooks | `.groverc.example:68-88` | List all 9 (`pre/post-add`, `pre/post-rm`, `post-pull`, `post-sync`, `post-switch`, `pre/post-move`) to match `README.md:334-344` |

---

## ⚪ P3 — Low (polish, latent traps, completeness)

| ID | Finding | Where | Fix |
|---|---|---|---|
| P3-1 | `move` validates the new dir name with the weaker `validate_identifier_common` (allows leading dots, spaces, shell-specials) instead of `validate_name` | `lifecycle.sh:371-375` | Use `validate_name "$new_name" "directory name"` |
| P3-2 | `BRANCH_PATTERN` from config used as an unquoted regex (regex-injection/ReDoS on a shared `HERD_ROOT/.groveconfig`) | `02-validation.sh:98` | Validate it is well-formed at load; document it is treated as a regex |
| P3-3 | `local var; var=$(...)` inside loops (the documented JSON footgun) — harmless today (text path only) but latent | `info.sh:1175`, `lifecycle.sh:688` | Declare the loop var once outside the loop |
| P3-4 | `json_escape` doesn't `\u`-escape generic control chars (U+0000–U+001F); not fully RFC 8259-compliant | `07-templates.sh:208-218` | Strip/escape remaining control chars, or document the assumption |
| P3-5 | `cached_fetch` ignores fetch args on a cache hit and keys only on repo basename | `04-git.sh:37-64` | Include args in the cache key, or bypass cache for `diff`/`summary` |
| P3-6 | Supervisor status uses an unanchored prefix regex — can report an unrelated process's health | `services.sh:126,626` | Anchor the match (`^${process%:*}[: ]`) or compare fields literally |
| P3-7 | `services start/stop/restart` print a green tick even when `supervisorctl` errors (`\|\| true` + discarded stderr) | `services.sh:211-212,259-260,299-301` | Branch on the command's exit code; show captured errors |
| P3-8 | `grove services` help only shows when zero apps registered and never lists `remove` | `services.sh:670-695` | Add an always-available `help`/`-h` case listing all subcommands incl. `remove` |
| P3-9 | GitHub org is inconsistent: README uses `withoutfanfare`; `install.sh:34/52/63/364`, docs/guides, README footer use `dannyharding10`; the linked root `ROADMAP.md` doesn't exist (it's `docs/development/roadmap.md`) | `install.sh`, `docs/guides/*`, `README.md:519` | **Decide the canonical org first**, then sweep all refs; point "See" links at the real roadmap path |
| P3-10 | `--help` hooks section lists 7 of 9 hooks (omits `pre-move`/`post-move`) | `99-main.sh:151-157` | Add both |
| P3-11 | README Flags table omits `--no-cache` and `--refresh` | `README.md:379-395` | Add both rows |
| P3-12 | `docs/development/implementation-plan.md` & `roadmap.md` describe an already-fixed `sed_inplace` crash and label v4.0.0 as "CURRENT" | `docs/development/*` | Mark historical/archived; bump version markers |
| P3-13 | `db-backup-dir` `$HOME` not expanded in the **core** parser (diverges from the hook loader, which does expand) | `01-core.sh:42-66` | Add `value="${value//\$HOME/$HOME}"` (same as P2-16's root cause) |

---

## Recommended implementation phases

**Phase 1 — Stop the bleeding (P0 + P1, ~½–1 day).** These are the trust-breakers a new
teammate hits first.
1. P0-1 `.env` data loss (+ regression test) — *highest priority, irreversible.*
2. P1-1 `migrate` dispatch (one line).
3. P1-2 / P1-3 `--json` contract breaks (services apps, status/summary).
4. P1-4 `services restart all` ordering.
5. P1-5 installer `set -e` abort.
6. P1-6 rewrite `CONTRIBUTING.md`.
7. `brew install shellcheck`, run `./run-tests.sh`, validate every `--json` command.

**Phase 2 — Safety rails & accuracy (P2, ~1–2 days).** Group by file to minimise rebuilds:
`services.sh` (P2-14/15), `info.sh`+`discovery.sh` (P2-1/3/10), `git-ops.sh` (P2-6/8/9),
`11-resilience.sh` (P2-4/5), then the docs/config batch (P2-11/12/13/16–22).

**Phase 3 — Polish (P3, opportunistic).** Fold into normal work; P3-9 (org decision) and
P3-1/2 (validation consistency) are the most worthwhile.

### Definition of done for internal release
- [ ] P0-1 fixed at both sites **with a regression test**; reproduction keeps all `.env` keys.
- [ ] All P1 fixed; `./build.sh` clean; `git diff grove` shows only intended changes.
- [ ] `shellcheck` installed; `./run-tests.sh` green **including** lint (no silent skip).
- [ ] Every `--json` command validates: `repos`, `recent`, `ls`, `branches`, `health`, `status`, `summary`, `services apps` (incl. the empty case → `[]`).
- [ ] `CONTRIBUTING.md`, CLAUDE.md (test count + `services.sh`), `_grove` completion, `--help`, and `.groverc.example` reflect reality.
- [ ] GitHub org references unified (P3-9) so the README clone command actually works.

---

## Notes & non-issues (things that are *fine*)

These were checked and are **not** problems — recorded so they aren't re-flagged:
- **Validation core** (`02-validation.sh`): strict whitelist, blocks `../`, absolute paths,
  leading/trailing dots, reserved refs, flag injection. Solid.
- **Config parsing**: key/value whitelist, never `source`d, skips null bytes. Solid.
- **DB name generation** (`db_name_for`): `<repo>__<slug>`, deterministic 64-char truncation
  with an 8-char md5 suffix, collision-safe within a repo. No SQL injection (names are
  validated to `[A-Za-z0-9_]` before reaching backticked SQL).
- **`grove upgrade`**: self-updates via `git pull --rebase origin main` on the local clone
  (which `install.sh` symlinks) — **resilient** to the GitHub org rename, not broken by it.
- **Hook security**: ownership + world-writable checks before execution; runs in a subshell.
- **`du`/space utilities, json array join** (`${(j:,:)items}`): correctly avoid trailing
  commas and handle embedded quotes/newlines.

## Appendix — duplicates consolidated
Several dimensions surfaced the same root cause; merged above:
`services apps --json` empty fields (P1-2) was reported by the security, json-contract, and
services reviewers; the org-URL drift (P3-9) by docs and setup; the missing-`services.sh`
doc gap (P2-21) by docs and services; the incomplete `.groverc.example` hooks (P2-22) by docs
and setup; the loop-local footgun (P3-3) by shell-correctness and database.
