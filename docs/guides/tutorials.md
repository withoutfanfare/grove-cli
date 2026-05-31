# grove Tutorials (Onboarding + Recipes)

This document is a **recipe-style onboarding guide** for `grove`, a command-line git worktree manager with optional Laravel Herd integration. It is aimed at someone learning by doing: start with the 10-minute Quick Start, skim the Concepts, then dip into the Command cookbook for a runnable recipe for every command. Every command shown is copy/paste-able, and each `grove` command has at least one working example.

A few terms used throughout:

- **Worktree** — a checked-out branch in its own directory. grove gives each branch its own folder so you can work on several branches at once without stashing or switching.
- **Bare repo** — a git repository with no working tree of its own (just the `.git` data). grove clones projects as bare repos and hangs worktrees off them.
- **Slug** — a filesystem-safe version of a branch name (`feature/login` → `feature-login`) used for directory and database names.
- **Herd** — [Laravel Herd](https://herd.laravel.com/), a local PHP dev environment. grove can register/unregister Herd `.test` sites for each worktree, but Herd is optional.

If you’re brand new to worktrees, skim the “Golden Rule” section in `README.md` first.

## Table of Contents

- [Quick Start (10 minutes)](#quick-start-10-minutes)
- [Concepts (the 30-second mental model)](#concepts-the-30-second-mental-model)
- [Core workflow](#core-workflow)
- [Command cookbook (all commands)](#command-cookbook-all-commands)
  - [System & info](#system--info)
  - [Worktree lifecycle](#worktree-lifecycle)
  - [Listing & status](#listing--status)
  - [Git operations](#git-operations)
  - [Bulk operations](#bulk-operations)
  - [Laravel](#laravel)
  - [Navigation](#navigation)
  - [Discovery](#discovery)
  - [Maintenance](#maintenance)
  - [Configuration](#configuration)
  - [Services](#services)
  - [Self-update & version](#self-update--version)
- [Templates](#templates)
- [Hooks](#hooks)
- [Automation (JSON output)](#automation-json-output)
- [Cache control (--no-cache / --refresh)](#cache-control---no-cache----refresh)
- [Troubleshooting recipes](#troubleshooting-recipes)
- [Development & Testing](#development--testing)

## Quick Start (10 minutes)

```bash
# 1) Install / update grove
git clone https://github.com/withoutfanfare/grove-cli.git ~/Projects/grove-cli
cd ~/Projects/grove-cli
./install.sh

# 2) New terminal (so PATH updates), then sanity check
grove --version
grove doctor

# 3) Clone a project into Herd (creates a bare repo + a default worktree)
grove clone git@github.com:org/myapp.git

# 4) Create a new worktree for a feature branch
#    (or run `grove add -i` / `grove -i` for a guided wizard)
grove add myapp feature/login

# 5) Jump into it
cd "$(grove cd myapp feature/login)"
```

> **Why `cd "$(grove cd ...)"`?** grove runs in a subprocess and a child process cannot change your shell's current directory. So `grove cd` *prints* the path and you wrap it in `cd "$(...)"` to actually move there. To avoid typing the idiom each time, add a shell alias/function (see `README.md`).

## Concepts (the 30-second mental model)

- `grove clone` creates a **bare** git repo at `~/Herd/<repo>.git` (by default).
- Every branch you work on gets its own folder: `~/Herd/<repo>-worktrees/<site-name>/`.
- Main branches (staging/main/master) use the repo name as site-name, feature branches use just the feature name.
- **One branch per worktree**: don't `git checkout` to another branch inside a worktree; use `grove add` / `grove switch` instead.
- **Security**: All user input is validated with defence-in-depth protection against command injection, path traversal, and other attacks. See the [Security section in the Advanced Guide](advanced.md#security) for details.

---

## Core workflow

### Create → open → keep in sync

```bash
# Create worktree for a new branch (base defaults to GROVE_BASE_DEFAULT / DEFAULT_BASE)
# If you pass an explicit base (3rd arg), grove stores it for the worktree (git config: grove.base)
grove add myapp feature/payments

# Open it in your editor (auto-detects when run inside a worktree)
grove code myapp feature/payments

# Open its URL in a browser (uses APP_URL from .env if present, otherwise https://<folder>.test)
grove open myapp feature/payments

# Keep your feature branch up to date with the base branch
# (uses stored grove.base if set, otherwise GROVE_BASE_DEFAULT / DEFAULT_BASE)
grove sync myapp feature/payments
```

### Remove when done

```bash
# Remove the worktree directory and git worktree entry
grove rm myapp feature/payments

# Also delete the local git branch (use with care; the remote branch is left untouched)
grove rm myapp feature/payments --delete-branch
```

---

## Command cookbook (all commands)

One runnable recipe per command, grouped into the same families used in the source tree. Notes:
- Commands marked “auto-detect” can infer `<repo>` / `<branch>` if you run them *inside a worktree directory* (the worktree must live under `HERD_ROOT`). Auto-detecting commands: `pull`, `sync`, `diff`, `summary`, `log`, `changes`, `fresh`, `migrate`, `tinker`, `code`, `open`, `cd`, `info`, `clean`, `share-deps`.
- If `fzf` is installed, many commands will let you omit `<branch>` and pick interactively.

### System & info

#### `grove doctor` — check system requirements

```bash
grove doctor
```

Checks that grove's environment is sane: git, Herd, MySQL, and friends.

#### `grove repos` — list bare repositories

```bash
grove repos
grove repos --json
```

#### `grove branches` — list available branches for a repo

```bash
grove branches myapp
grove branches myapp --json
```

### Worktree lifecycle

#### `grove clone` — clone as a bare repo (and create a default worktree)

```bash
# Uses the repo name inferred from URL ("myapp")
grove clone git@github.com:org/myapp.git

# Explicit name + create a worktree for an initial branch
grove clone git@github.com:org/myapp.git myapp feature/login
```

#### `grove add` — create a worktree

```bash
# Create (or check out) a branch worktree
grove add myapp feature/login

# Create using an explicit base
grove add myapp feature/login origin/main

# Preview without changing anything
grove add myapp feature/login --dry-run

# Guided interactive wizard (these three are equivalent)
grove add --interactive
grove add -i
grove -i
```

If you pass a base (the 3rd argument), `grove` stores it in the worktree’s local git config as `grove.base`. Commands like `grove summary`, `grove diff`, `grove sync`, and `grove log` will use it automatically when you don’t specify a base.

```bash
# View the stored base for a worktree
git -C /path/to/worktree config --local --get grove.base

# Set/change it
git -C /path/to/worktree config --local grove.base origin/main
```

#### `grove rm` — remove a worktree

```bash
grove rm myapp feature/login

# Force removal of protected branches (defaults: staging, main, master)
grove rm -f myapp staging

# Also delete the LOCAL branch (use with care; the remote branch is untouched)
grove rm myapp feature/login --delete-branch

# Hook-friendly database flags (used by the example hooks)
grove rm myapp feature/login --drop-db
grove rm myapp feature/login --no-backup
```

Flag notes:
- `--delete-branch` runs `git branch -D` on the worktree's branch — a **local** delete only. grove never pushes a deletion to the remote.
- `--drop-db` / `--no-backup` set request flags that grove exports to your `pre-rm`/`post-rm` hooks (`GROVE_DROP_DB`, `GROVE_NO_BACKUP`). grove delegates the actual drop/backup to those hooks and cannot itself confirm the drop ran — the JSON output reports `db_drop_requested` (intent), not a verified result.

#### `grove move` — rename or move a worktree

Renames a worktree directory, re-securing the Herd site with SSL **if the old site was already secured**.

```bash
# Move with explicit new name
grove move myapp feature/login myapp-login

# Interactive branch selection (requires fzf)
grove move myapp

# Force move without confirmation
grove move -f myapp feature/login myapp-login
```

**Common use cases:**

```bash
# Rename a worktree to a custom name
# Before: /Users/you/Herd/myapp-worktrees/dashboard
# After:  /Users/you/Herd/myapp-worktrees/main-dashboard
grove move myapp feature/dashboard main-dashboard

# Shorten a long worktree name
# Before: /Users/you/Herd/myapp-worktrees/very-long-feature-name
# After:  /Users/you/Herd/myapp-worktrees/short
grove move myapp feature/very-long-feature-name short
```

The command:
- Moves the worktree using `git worktree move`
- Unsecures the old site (only if it was secured) and cleans up old Herd nginx configs
- Re-secures the new site with SSL (only if the old site was secured)

#### `grove restructure` — migrate worktrees to the nested layout

Migrates a repo's worktrees from an older flat layout into the nested `<repo>-worktrees/` structure.

```bash
grove restructure myapp
```

### Listing & status

#### `grove ls` — list worktrees for a repo

```bash
grove ls myapp
grove ls myapp --json
```

#### `grove status` — dashboard for a single repo

```bash
grove status myapp
grove status myapp --json

# Force a fresh fetch (ignore the short-lived fetch cache)
grove status myapp --no-cache
```

`grove status` requires a `<repo>` — it does **not** auto-detect from the current directory.

#### `grove dashboard` — overview of all repos

```bash
grove dashboard

# Interactive mode with quick actions (requires fzf)
grove dashboard -i
```

In interactive mode, select a worktree and press:
- `p` to pull, `s` to sync, `o` to open in browser
- `c` to open in editor, `r` to remove, `i` for info

### Git operations

#### `grove pull` — pull latest changes (auto-detect)

```bash
# From inside a worktree: auto-detect repo/branch
grove pull

# Or specify explicitly
grove pull myapp feature/login
```

#### `grove pull-all` — pull every worktree (parallel)

```bash
grove pull-all myapp

# Across all repositories
grove pull-all --all-repos
```

#### `grove sync` — rebase onto a base branch (auto-detect)

```bash
# From inside a worktree
grove sync

# Explicit base
grove sync myapp feature/login origin/main
```

#### `grove diff` — compare against base (auto-detect)

```bash
# From inside a worktree
grove diff

# Explicit base
grove diff myapp feature/login origin/main
```

#### `grove summary` — overview vs base (auto-detect)

```bash
# From inside a worktree
grove summary

# Explicit
grove summary myapp feature/login

# Explicit base override
grove summary myapp feature/login origin/main

# JSON output
grove summary --json myapp feature/login
```

#### `grove log` — recent commits (auto-detect)

```bash
# From inside a worktree
grove log

# Explicit
grove log myapp feature/login

# Limit the number of commits (default 5; -nN with no space also works)
grove log myapp feature/login -n 20
```

#### `grove changes` — list uncommitted file changes (auto-detect)

```bash
# From inside a worktree
grove changes

# Explicit
grove changes myapp feature/login
```

#### `grove prune` — clean up stale worktree references

```bash
# Single repo (required — does NOT auto-detect)
grove prune myapp

# Across all repositories (in parallel)
grove prune --all-repos
```

### Bulk operations

#### `grove exec` — run any command inside a worktree

```bash
grove exec myapp feature/login php artisan migrate
grove exec myapp feature/login npm test

# Use `--` to pass a command containing dashes
grove exec myapp feature/login -- ls -la
```

#### `grove exec-all` — run a command on all worktrees

```bash
grove exec-all myapp "php artisan about"

# Across all repositories
grove exec-all --all-repos "git status --porcelain"
```

#### `grove build-all` — `npm run build` for all worktrees

```bash
grove build-all myapp
grove build-all --all-repos
```

### Laravel

These commands run from inside a worktree (auto-detect) or with an explicit `<repo> <branch>`.

#### `grove fresh` — `migrate:fresh --seed` + `npm ci` + `npm run build` (auto-detect)

```bash
# From inside a worktree
grove fresh

# Or explicit
grove fresh myapp feature/login

# Skip the migrate:fresh confirmation prompt
grove fresh -f myapp feature/login
```

`grove fresh` runs `php artisan migrate:fresh --seed` (prompting for confirmation unless `-f`/`--force` is given, since it drops all tables), then `npm ci`, then `npm run build`.

#### `grove migrate` — run `php artisan migrate` (auto-detect)

```bash
grove migrate
grove migrate myapp feature/login
```

#### `grove tinker` — run `php artisan tinker` (auto-detect)

```bash
grove tinker
grove tinker myapp feature/login
```

### Navigation

#### `grove code` — open worktree in your editor (auto-detect)

```bash
grove code
grove code myapp feature/login
```

Uses the editor in `DEFAULT_EDITOR` (env override `GROVE_EDITOR`). With a repo but no branch and `fzf` installed, shows a picker; also resolves aliases, `@N` shortcuts and fuzzy branch matches.

#### `grove open` — open worktree URL in browser (auto-detect)

```bash
grove open
grove open myapp feature/login
```

#### `grove cd` — print the worktree path (auto-detect)

```bash
cd "$(grove cd myapp feature/login)"

# From inside a worktree (prints the current worktree path)
cd "$(grove cd)"
```

`grove cd` prints a path rather than changing directory because a child process cannot move the parent shell — wrap it in `cd "$(...)"` (see the note in Quick Start).

#### `grove switch` — cd path + open editor + open browser

```bash
# With fzf installed, omit branch to pick interactively
grove switch myapp

# Or explicit
cd "$(grove switch myapp feature/login)"
```

`grove switch` always requires a `<repo>` (it switches *to* a different worktree, so it does not auto-detect by design).

### Discovery

#### `grove info` — detailed worktree information (auto-detect)

```bash
grove info myapp feature/login
grove info              # from inside a worktree
```

#### `grove recent` — recently accessed worktrees

```bash
grove recent
grove recent 10
grove recent --json
```

#### `grove clean` — remove `node_modules/` and `vendor/` from inactive worktrees

Reclaim disk space by removing dependency directories from worktrees that haven't been committed to in 30+ days. These can be reinstalled with `npm install` or `composer install` when you return to the worktree. The threshold defaults to 30 days; override it with the `GROVE_CLEAN_INACTIVE_DAYS` environment variable.

```bash
# Preview what would be removed for one repo (shows sizes)
grove clean myapp --dry-run

# Actually remove node_modules/ and vendor/ from that repo's inactive worktrees
grove clean myapp

# From inside a worktree, clean just that worktree's repo (auto-detect)
grove clean

# Preview and confirm removal across ALL repositories
# (destructive — prompts before deleting; auto-confirms under --force)
grove clean   # run from OUTSIDE any worktree
```

> **Heads up:** bare `grove clean` run from outside a worktree previews and then, after a confirmation prompt, deletes dependency caches across **every** repository. It is not a quiet local clean.

### Maintenance

#### `grove health` — repository health checks

```bash
grove health myapp
grove health myapp --json
```

`grove health` requires a `<repo>` — it does **not** auto-detect.

#### `grove report` — generate a markdown report

```bash
# Print to stdout
grove report myapp

# Save to a file
grove report myapp --output /tmp/grove-report-myapp.md
```

`grove report` always emits markdown — there is no `--json` mode.

#### `grove cleanup-herd` — remove orphaned Herd nginx configs

```bash
grove cleanup-herd
```

#### `grove unlock` — remove stale git lock files

```bash
grove unlock myapp

# Across all repositories
grove unlock
```

#### `grove repair` — fix common issues

```bash
# Repair all repositories (no repo given)
grove repair

# Repair a single repository
grove repair myapp

# Attempt more aggressive recovery
grove repair myapp --recovery
```

`grove repair` does not auto-detect from the current directory.

### Configuration

#### `grove templates` — view available templates

```bash
grove templates
grove templates minimal
```

#### `grove alias` — manage branch aliases

Aliases are stored as `name=repo/branch` lines in `~/.grove/aliases`.

```bash
# List
grove alias
grove alias list

# Add (or overwrite)
grove alias add login myapp/feature/login
grove alias set staging myapp/staging

# Remove
grove alias rm login
grove alias remove staging
```

#### `grove config` — show current configuration

```bash
grove config
```

Prints the resolved configuration (HERD_ROOT, editor, base branch, database settings, and any active `GROVE_SKIP_*` flags).

#### `grove setup` — first-time configuration wizard

```bash
grove setup
```

Guides you through HERD_ROOT, base branch, database settings, and creates `~/.groverc`.

#### `grove share-deps` — share dependencies across worktrees

```bash
# Check status (the default action)
grove share-deps

# Enable shared deps (auto-detects when run inside a worktree, otherwise fzf picker)
grove share-deps enable

# Disable and restore local copies
grove share-deps disable

# Global cleanup of unused shared-deps caches
# (undocumented in `grove share-deps --help`; affects ALL repos, not just this worktree)
grove share-deps clean
```

##### `grove group` — manage repository groups

```bash
# Create a group
grove group add frontend myapp otherapp

# List groups
grove group list

# Show repos in a group
grove group show frontend

# Use with multi-repo commands
grove pull-all @frontend
grove build-all @backend

# Remove a group
grove group rm frontend
```

### Services

#### `grove services` — manage app services (Supervisor, Horizon, Reverb, scheduler)

Register Laravel apps and control their background services. Configuration is lazy-loaded from `~/.grove/services/apps.conf`. Run `grove services` with no arguments to see status (if any apps are registered) or the full subcommand help. For the in-depth guide see [services.md](./services.md).

```bash
# Register an app. Options:
#   --system-name=<name>          internal/system name (defaults to the app name)
#   --services=horizon|horizon:reverb|none   which services this app runs
#   --domain=<domain>             domain for Horizon/links (e.g. myapp.test)
#   --supervisor=<process>        Supervisor process name to manage
grove services add myapp --services=horizon:reverb --domain=myapp.test

# Inspect and control services ([app] defaults to all where applicable)
grove services status
grove services start all
grove services restart myapp
grove services stop myapp

# List registered apps (supports --json: array of {name, system_name, services,
# supervisor_process, domain})
grove services apps
grove services apps --json

# Open Horizon in the browser, tail a log, check dependencies
grove services horizon myapp
grove services logs myapp horizon      # type: horizon (default) | queue | reverb | scheduler
grove services doctor

# Remove an app from the registry (worktrees/configs are left untouched)
grove services remove myapp
```

> `grove services logs <app> queue` tails the same `horizon.log` file as `horizon` (it is an alias).

### Self-update & version

#### `grove upgrade` — self-update

```bash
grove upgrade
```

#### `grove version` / `grove --version` — show the version

```bash
# All three print the version string
grove version
grove --version
grove -v

# Check for available updates
grove --version --check
```

---

## Templates

A template is a small `.conf` file in `GROVE_TEMPLATES_DIR` (default `~/.grove/templates/`) that sets `GROVE_SKIP_*` flags (e.g. `GROVE_SKIP_DB=true`, `GROVE_SKIP_NPM=true`, `GROVE_SKIP_BUILD=true`). grove exports those flags when it runs your hooks during `grove add`, so your hooks can skip the setup steps you don't want for that worktree.

> **No templates ship enabled.** On a fresh install `~/.grove/templates/` is empty and `grove templates` shows "(no templates found)". Four examples are bundled under `examples/templates/` — copy them in (the `cp` step below) to make them available.

```bash
# Install the example templates bundled with this repo
mkdir -p ~/.grove/templates
cp examples/templates/*.conf ~/.grove/templates/

# List all templates, then inspect one (shows the flags it sets)
grove templates
grove templates laravel

# Use a template when creating a worktree
grove add myapp feature/api --template=backend
```

The bundled examples are `laravel.conf` (MySQL, Composer, NPM, migrations), `minimal.conf` (git worktree only, no setup), `backend.conf` (PHP + database, no npm/build) and `node.conf` (npm only, no PHP/database).

---

## Hooks

Hooks are optional scripts under `~/.grove/hooks/` that run during the worktree lifecycle (pre/post add, pre/post rm, pre/post move, post switch, post pull, post sync).

```bash
# Install the example hooks shipped with this repo (recommended starting point)
./install.sh

# Manual install (if you prefer)
mkdir -p ~/.grove/hooks
cp -R examples/hooks/* ~/.grove/hooks/
chmod +x ~/.grove/hooks/* ~/.grove/hooks/*/*.sh 2>/dev/null || true
```

Common hook points:
- `pre-add`, `post-add`
- `pre-rm`, `post-rm`
- `pre-move`, `post-move`
- `post-switch`
- `post-pull`, `post-sync`

Every hook runs with these environment variables exported:
`GROVE_REPO`, `GROVE_BRANCH`, `GROVE_BRANCH_SLUG`, `GROVE_PATH`, `GROVE_URL`, `GROVE_DB_NAME`, `GROVE_HOOK_NAME`.

On `grove rm`, two further flags are exported **only when the matching flag was passed**:
- `GROVE_DROP_DB=true` — set when `--drop-db` is used (tells your hook to drop the database).
- `GROVE_NO_BACKUP=true` — set when `--no-backup` is used (tells your hook to skip the backup).

### Consolidated Laravel Hooks (advanced, optional)

> This subsection describes an opinionated multi-project setup. You can skip it entirely — the basic install above plus the hook environment contract is all most users need.

For multiple Laravel projects, use the shared `_laravel/` hooks to avoid duplication:

```bash
# Install the shared Laravel hooks
cp -R examples/hooks/post-add.d/_laravel ~/.grove/hooks/post-add.d/

# Link each Laravel repo (one command per repo)
~/.grove/hooks/post-add.d/_laravel/link-repo.sh myapp
~/.grove/hooks/post-add.d/_laravel/link-repo.sh another-app
```

This creates symlinks from each repo directory to the shared hooks. Benefits:
- Update one hook, all repos benefit
- One command to onboard new Laravel projects
- Hooks skip gracefully if their source files don't exist

Expected resource structure per repo (all optional):
```text
~/Code/Worktree/myapp/
├── myapp-env/.env          # Pre-built .env (symlinked into worktrees)
├── myapp-db/myapp.sql.gz   # Database dump (imported on worktree creation)
├── myapp-llm/              # AI/LLM config files (copied into worktrees)
└── storage/app/            # Shared uploads (symlinked into worktrees)
```

See the [shared Laravel hooks](../../examples/hooks/README.md#shared-laravel-hooks-post-addd_laravel) and [Laravel quick-start](../../examples/hooks/README.md#laravel-quick-start-optional) sections of `examples/hooks/README.md` for full documentation.

---

## Automation (JSON output)

These commands support `--json` (and optionally `--pretty`) for scripting:
`repos`, `ls`, `status`, `summary`, `branches`, `health`, and `recent`.

> The JSON output is a **stable data contract** consumed by the grove-app desktop application and other integrations. Treat the documented shapes as part of grove's public surface — they should not change without a deliberate version bump.

Note: `--json` is **not** supported together with `--all-repos` (e.g. on `pull-all`, `prune`).

```bash
grove repos --json
grove ls myapp --json
grove status myapp --json
grove summary myapp feature/login --json
grove branches myapp --json
grove health myapp --json
grove recent --json

# Pretty-print JSON (useful for humans)
grove ls myapp --json --pretty
```

---

## Cache control (--no-cache / --refresh)

To speed up commands that fetch from the remote (e.g. `status`, `dashboard`), grove caches `git fetch` results briefly (`GROVE_FETCH_CACHE_TTL`, default 30 seconds; `0` disables it). Two global flags let you bypass that cache when you need up-to-the-second ahead/behind counts:

```bash
# Bypass the cache for this run (always fetch fresh; sets GROVE_FETCH_CACHE_TTL=0)
grove status myapp --no-cache

# Clear the cache first, then run the command
grove dashboard --refresh
```

Reach for these if `grove status` shows ahead/behind numbers that look stale.

---

## Troubleshooting recipes

### “I’m in the wrong branch in this folder”

If you switched branches inside a worktree by accident, the folder name and branch won’t match. Use:

```bash
grove status myapp
```

Then either:
- checkout the correct branch for that folder, or
- remove/recreate the worktree with `grove rm` / `grove add`.

### “Git says: index.lock exists” / “could not lock config file”

```bash
grove unlock myapp
```

### "Herd has configs for worktrees that no longer exist"

```bash
grove cleanup-herd
```

---

## Development & Testing

### Running the test suite

The project includes 448 tests (across 26 `.bats` files) covering security validation, git operations, and edge cases:

```bash
# Run all tests (lint + unit + integration)
cd ~/Projects/grove-cli
./run-tests.sh

# Run only the shellcheck static analysis
./run-tests.sh lint

# Run only unit tests
./run-tests.sh unit

# Run only integration tests
./run-tests.sh integration

# Run a specific test file
./run-tests.sh validation.bats
```

### Building from source

> **Never edit the `grove` file directly.** It is a generated artifact. Edit the modular sources in `lib/`, then run `./build.sh` to regenerate `grove` — any direct edits to `grove` are overwritten by the build.

After making changes to files in `lib/`:

```bash
# Rebuild the grove executable
./build.sh

# Test it
./grove --version
./grove doctor
```

The build process concatenates all `lib/` modules into a single `grove` file for distribution.

### Security validation

All security improvements are tested:
- Git ref validation (prevents command injection)
- Path traversal protection (blocks `../` attacks)
- Dot-based attack prevention (blocks hidden files, trailing dots)
- Overflow protection (age calculations bounded)
- Null byte filtering (config parser security)
- Password protection (MySQL credentials never exposed)

See the [Security section in the Advanced Guide](advanced.md#security) for full details.
