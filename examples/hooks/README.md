# Lifecycle Hooks

grove is a **generic git worktree manager**. A *worktree* is a separate working
directory backed by one shared git repository, so you can have several branches
checked out at once. grove keeps each repository as a *bare repo* (a `.git`
directory with no working files of its own) and creates worktrees beside it.

grove deliberately ships with **no framework-specific behaviour built in**. All
setup — copying `.env`, creating databases, running `composer`/`npm`, securing a
Laravel [Herd](https://herd.laravel.com) site (Herd is Laravel's local
development environment) — is performed by **lifecycle hooks**: ordinary scripts
that grove runs at well-defined points during worktree operations. This document
explains how the hook system works, which hook points exist, what environment
each hook receives, the example hooks bundled in this directory, and how to write
your own.

**Audience:** anyone writing or customising grove lifecycle hooks. The bundled
examples are Laravel-oriented, but the hook *mechanism* is framework-agnostic —
the [Non-Laravel Projects](#non-laravel-projects) section shows how to use grove
without any of them.

## Contents

- [Quick start](#quick-start)
- [How hooks work](#how-hooks-work)
  - [Hook execution model](#hook-execution-model)
  - [Hook resolution order](#hook-resolution-order)
  - [Security model](#security-model)
- [Available hook points](#available-hook-points)
- [Environment variables](#environment-variables)
- [Directory structure](#directory-structure)
- [Execution order example](#execution-order-example)
- [Bundled example hooks](#bundled-example-hooks)
- [Configuration for hooks](#configuration-for-hooks)
  - [Configuration hierarchy](#configuration-hierarchy)
  - [Shared config loader](#shared-config-loader)
  - [Database hook behaviour](#database-hook-behaviour)
- [Control flags (skipping hooks)](#control-flags-skipping-hooks)
- [Laravel quick-start (optional)](#laravel-quick-start-optional)
- [Common patterns](#common-patterns)
- [Creating repo-specific hooks](#creating-repo-specific-hooks)
- [Non-Laravel projects](#non-laravel-projects)
- [Tips](#tips)
- [Migrating from built-in setup](#migrating-from-built-in-setup)

## Quick start

Run these commands **from the root of your `grove-cli` checkout** (the installer
and the example files are relative to it):

```bash
cd /path/to/grove-cli

# Install all example hooks (recommended for Laravel projects)
./install.sh --merge

# Or manually copy specific hooks and their shared helpers
mkdir -p ~/.grove/hooks/_lib ~/.grove/hooks/post-add.d
cp examples/hooks/_lib/*.sh ~/.grove/hooks/_lib/
cp examples/hooks/post-add.d/03-create-database.sh ~/.grove/hooks/post-add.d/
cp examples/hooks/post-add.d/05-composer-install.sh ~/.grove/hooks/post-add.d/
```

The `--merge` flag installs the example hooks without overwriting any custom
hooks you may already have. By default hooks live under `~/.grove/hooks/`
(configurable via `GROVE_HOOKS_DIR`).

## How hooks work

### Hook execution model

When grove reaches a lifecycle point it runs the matching hooks one at a time.
Each hook runs:

- **In its own subshell.** Variables a hook `export`s do **not** reach the next
  hook. (This is why a hook cannot set a "skip" flag for its siblings — see
  [Non-Laravel Projects](#non-laravel-projects).)
- **With stdin redirected from `/dev/null`.** Hooks **cannot prompt for
  interactive input**; a `read` will return immediately. This keeps bulk and
  `--json` flows from deadlocking.
- **With the worktree directory as the current working directory** (`cd`-ing
  into `$GROVE_PATH`, falling back to `$HOME` if that path does not exist).
  Relative paths and bare `.env` references in a hook therefore resolve inside
  the worktree.

`pre-*` hooks are **gating**: if any of them exits non-zero, grove aborts the
operation. `post-*` hooks are **non-fatal**: a failing one prints a warning and
grove continues to the next hook.

### Hook resolution order

For a given event (e.g. `post-add`), grove looks in three places:

1. **Single hook file** — `~/.grove/hooks/<hook>` (if it exists and is
   owner-executable). Always runs first.
2. **Global hook directory** — `~/.grove/hooks/<hook>.d/*.sh`.
3. **Repo-specific directory** — `~/.grove/hooks/<hook>.d/<repo>/*.sh`.

The global and repo-specific scripts run as **one merged sequence ordered by
script filename** (numeric-aware: `02-` runs before `10-`), so a repo hook
numbered `02-` runs between global `01-` and `03-` hooks. When a global and a
repo hook share the same filename, the global one runs first, then the repo
one — so a repo hook can override the global hook's work.

`<repo>` is the repository name (e.g. `example-app`).

**Directory scanning is non-recursive.** Only files directly inside these
locations run; nested subdirectories are ignored, with the single exception of
the repo-specific `<repo>/` folder. Folders named with a leading underscore
(such as `_lib/` and `post-add.d/_laravel/`) are shared libraries — they are not
a repo name, so grove never executes them directly; their scripts are symlinked
into a `<repo>/` folder to run.

### Security model

Before running anything, grove rejects any hook **file or directory** that is
not safe to trust. A hook (or one of its containing directories — the `.d`
directory, the repo subdirectory) is **skipped with a warning** if it is:

- **not owned by the current user**, or
- **group-writable**, or
- **world-writable**.

This prevents a co-located user or a loosely-permissioned directory from
injecting code into your worktree setup. Keep hooks owned by you and mode `0755`
(or `0700`); keep their parent directories likewise not group/other-writable.

## Available hook points

| Hook | When | Can abort? | Typical use |
|------|------|------------|-------------|
| `pre-add` | Before worktree creation | Yes (non-zero exit) | Validation, resource checks |
| `post-add` | After worktree creation | No | Setup: `.env`, database, composer, npm |
| `pre-rm` | Before worktree removal | Yes (non-zero exit) | Database backup, validation |
| `post-rm` | After worktree removal | No | Cleanup: Herd, database drop |
| `pre-move` | Before worktree move/rename | Yes (non-zero exit) | Validation before relocating |
| `post-move` | After worktree move/rename | No | Re-secure Herd, update `.env` URL |
| `post-pull` | After `grove pull` succeeds | No | Cache clear, migrations |
| `post-switch` | After `grove switch` succeeds | No | Configure `.env`, update symlinks |
| `post-sync` | After `grove sync` succeeds | No | Rebuild after rebase |

"Can abort?" means a non-zero exit stops the operation. Note that being *able* to
abort does not mean a hook *will*: the bundled Laravel preflight normally warns,
but blocks creation when linked shared storage would strand local files — see
[Pre-add hooks](#pre-add-hooks-pre-addd).

## Environment variables

grove exports the following into every hook's subshell:

| Variable | Example | Description |
|----------|---------|-------------|
| `GROVE_REPO` | `example-app` | Repository name |
| `GROVE_BRANCH` | `feature/new-feature` | Branch name |
| `GROVE_BRANCH_SLUG` | `feature-new-feature` | Filesystem-safe branch slug (`/` replaced with `-`) |
| `GROVE_PATH` | `/Users/you/Herd/example-app-worktrees/new-feature` | Worktree directory path (and the hook's working directory) |
| `GROVE_URL` | `https://new-feature.test` | Local development URL |
| `GROVE_DB_NAME` | `example_app__feature_new_feature` | Generated database name |
| `GROVE_HOOK_NAME` | `post-add` | The event currently being run |
| `GROVE_NO_BACKUP` | `true` | Set only when `--no-backup` was passed |
| `GROVE_DROP_DB` | `true` | Set only when `--drop-db` was passed |

`GROVE_NO_BACKUP` and `GROVE_DROP_DB` are exported **only** when the
corresponding flag is present; otherwise they are unset.

## Directory structure

A fully populated hooks directory looks like this. (The bundled examples target
the Laravel workflow; you only need the hooks relevant to your projects.)

```text
~/.grove/hooks/
├── _lib/                          # Shared utilities (not a hook; never run directly)
│   ├── load-config.sh             # Config loader (global → project → repo override)
│   └── php-runtime.sh             # Shared Herd/system PHP resolver
│
├── pre-add                        # Single script (runs first, can abort)
├── pre-add.d/                     # Multiple scripts (numeric order, can abort)
│   └── 00-laravel-preflight.sh    # Laravel setup warnings + shared-storage safety gate
│
├── post-add                       # Single script
├── post-add.d/                    # Multiple scripts (numeric order)
│   ├── 00-register-project.sh     # Register in ~/.projects
│   ├── 01-copy-env.sh             # Copy .env.example → .env
│   ├── 01a-inherit-db-from-primary.sh  # Inherit DB_DATABASE when DB_CREATE=false
│   ├── 02-configure-env.sh        # Set APP_URL / VITE_APP_URL (early pass)
│   ├── 03-create-database.sh      # Create MySQL database
│   ├── 04-herd-secure.sh          # Secure site with Herd HTTPS
│   ├── 04-laravel-scaffold.sh     # Create missing Laravel runtime dirs
│   ├── 05-composer-install.sh     # composer install + key:generate when APP_KEY is missing or empty
│   ├── 06-npm-install.sh          # npm install
│   ├── 07-build-assets.sh         # npm run build
│   ├── 08-run-migrations.sh       # php artisan migrate
│   ├── 09-update-current-link.sh  # Update {repo}-current symlink
│   ├── 10-set-hooks-path.sh       # Point worktree at the bare repo's git hooks
│   │
│   ├── _laravel/                  # Shared Laravel hooks (symlinked into <repo>/)
│   │   ├── 01-ai-files.sh
│   │   ├── 02-copy-env.sh
│   │   ├── 03-configure-env.sh
│   │   ├── 04-import-database.sh
│   │   ├── 05-symlink-storage.sh
│   │   └── link-repo.sh
│   │
│   └── example-app/               # Repo-specific hooks for 'example-app' (interleaved by number)
│       ├── 02-symlink-env.sh      # Replace .env with a symlink
│       ├── 04-import-database.sh
│       ├── 05-symlink-storage.sh
│       └── 08a-seed-data.sh
│
├── pre-rm                         # Before worktree removal (can abort)
├── pre-rm.d/
│   ├── 01-backup-database.sh      # Back up database before removal
│   ├── 02-backup-env.sh           # Back up .env for review
│   └── 02a-guard-local-storage.sh  # Refuse removal while local storage data remains
│
├── post-rm                        # After worktree removal
├── post-rm.d/
│   ├── 01-herd-unsecure.sh        # Remove Herd SSL / nginx config
│   ├── 02-drop-database.sh        # Drop database (only with --drop-db)
│   └── example-app/
│       └── 01-cleanup-symlinks.sh # Repo-specific removal cleanup / audit log
│
├── pre-move                       # Before worktree move/rename (can abort)
├── pre-move.d/
│   └── *.sh
│
├── post-move                      # After worktree move/rename
├── post-move.d/
│   └── *.sh                       # Re-secure Herd, update .env URL
│
├── post-pull.d/                   # After grove pull succeeds
│   └── *.sh
│
├── post-switch.d/                 # After grove switch succeeds
│   ├── 01-update-current-link.sh  # Update {repo}-current symlink
│   ├── 02-services-restart.sh       # Restart grove services (Supervisor/Horizon)
│   └── example-app/
│       └── 01-configure-env.sh    # Set APP_URL, SESSION_DOMAIN, DB_DATABASE
│
└── post-sync.d/                   # After grove sync succeeds
    └── *.sh
```

> The [Bundled example hooks](#bundled-example-hooks) tables are the single
> source of truth for what each file does; this tree is just the layout.

## Execution order example

For the `example-app` repo, `grove add example-app feature/login` runs the
`post-add` hooks in this order:

```text
post-add                          (single file, if it exists)
post-add.d/00-register-project.sh         (global)
post-add.d/01-copy-env.sh                 (global)
post-add.d/01a-inherit-db-from-primary.sh (global)
post-add.d/02-configure-env.sh            (global)
post-add.d/example-app/02-symlink-env.sh      (repo-specific)
post-add.d/03-create-database.sh          (global)
post-add.d/04-herd-secure.sh              (global)
post-add.d/example-app/04-import-database.sh  (repo-specific)
post-add.d/04-laravel-scaffold.sh         (global)
post-add.d/05-composer-install.sh         (global)
post-add.d/example-app/05-symlink-storage.sh  (repo-specific)
post-add.d/06-npm-install.sh              (global)
post-add.d/07-build-assets.sh             (global)
post-add.d/08-run-migrations.sh           (global)
post-add.d/example-app/08a-seed-data.sh       (repo-specific)
post-add.d/09-update-current-link.sh      (global)
post-add.d/10-set-hooks-path.sh           (global)
```

Global and repo-specific hooks form **one merged sequence sorted by script
filename**, so `example-app/04-import-database.sh` runs after the database is
created at `03-` and `example-app/08a-seed-data.sh` runs after migrations at
`08-`. Files sharing a numeric prefix (e.g. `04-herd-secure.sh`,
`example-app/04-import-database.sh`, `04-laravel-scaffold.sh`) order by the
remaining characters; an exact filename tie runs the global hook first.

## Bundled example hooks

Each subsection below lists exactly the files shipped under `examples/hooks/`.

### Pre-add hooks (`pre-add.d/`)

| Hook | Purpose |
|------|---------|
| `00-laravel-preflight.sh` | Warns when a Laravel repo is missing setup and prints the exact fixes. If the shared-storage hook is linked, it blocks creation while the primary `storage/app` contains local files; `GROVE_SKIP_PREFLIGHT=true` silences warnings but does not bypass this safety gate. |

### Global post-add hooks (`post-add.d/`)

| Hook | Purpose | Skip flag |
|------|---------|-----------|
| `00-register-project.sh` | Register the worktree in `~/.projects` for quick navigation | — |
| `01-copy-env.sh` | Install a missing `.env` from `.env.example` with mode `0600` | — |
| `01a-inherit-db-from-primary.sh` | When `DB_CREATE=false`, sync `DB_DATABASE` from the primary worktree's `.env` (prevents stale `.env.example` DB names cascading into new worktrees) | — |
| `02-configure-env.sh` | Early `.env` pass: set `APP_URL`, `VITE_APP_URL`, and (for multi-tenant apps) `MULTITENANCY_LANDLORD_DOMAIN` / `MULTITENANCY_TENANT_PROTOCOL`. **Does not set `DB_DATABASE`** — that is deliberately deferred to a repo-specific hook that runs after any `.env` symlink. | — |
| `03-create-database.sh` | Create the MySQL database | `GROVE_SKIP_DB` |
| `04-herd-secure.sh` | Link and secure the site with Herd HTTPS | `GROVE_SKIP_HERD` |
| `04-laravel-scaffold.sh` | Create missing Laravel runtime dirs and keep the runtime tree owner-only before composer runs | — |
| `05-composer-install.sh` | Run `composer install` and generate an app key only when `APP_KEY` is missing or empty | `GROVE_SKIP_COMPOSER` |
| `06-npm-install.sh` | Run `npm install` | `GROVE_SKIP_NPM` |
| `07-build-assets.sh` | Run `npm run build` if a build script exists | `GROVE_SKIP_BUILD` |
| `08-run-migrations.sh` | Run Laravel migrations (only when `artisan` is present) | `GROVE_SKIP_MIGRATE` |
| `09-update-current-link.sh` | Update the `{repo}-current` symlink (a stable path for queue workers / schedulers) to point at the new worktree | `GROVE_SKIP_CURRENT_LINK` |
| `10-set-hooks-path.sh` | Set the bare repo hooks path only when no different effective `core.hooksPath` is already configured | `GROVE_SKIP_HOOKS_PATH` |

### Shared Laravel hooks (`post-add.d/_laravel/`)

Laravel-specific hooks you opt into **per repo** by symlinking them via
`link-repo.sh`. Because they live one directory deeper than the global hooks,
they source the shared loader with **two** `../` segments
(`$SCRIPT_DIR/../../_lib/load-config.sh`) — see
[Shared config loader](#shared-config-loader) for why the depth matters.

| Hook | Purpose |
|------|---------|
| `01-ai-files.sh` | Import missing AI/LLM context files without overwriting worktree files or symlink/type collisions |
| `02-copy-env.sh` | Replace the global `.env.example` fallback with the pre-built template; preserve any other existing worktree `.env` |
| `03-configure-env.sh` | Set `APP_URL`, `VITE_APP_URL`, `SESSION_DOMAIN`, and `DB_DATABASE` for the worktree |
| `04-import-database.sh` | Import a gzipped SQL dump only when the target database has no tables (`GROVE_FORCE_DB_IMPORT=true` overrides) |
| `05-symlink-storage.sh` | Symlink an absent or empty `storage/app`; refuse real files and tracked sentinel layouts |
| `link-repo.sh` | Link missing shared hooks for a safe repo name while preserving existing repo-specific hooks |

### Repo-specific post-add hooks (`post-add.d/example-app/`)

These ship under `examples/hooks/post-add.d/myapp/`; copy them under a folder
named after your own repo.

| Hook | Purpose |
|------|---------|
| `02-symlink-env.sh` | Replace the global `.env.example` fallback with a symlink to a pre-built version; preserve any other existing `.env` |
| `04-import-database.sh` | Import a database from a gzipped SQL dump |
| `05-symlink-storage.sh` | Symlink `storage/app` to a shared directory |
| `08a-seed-data.sh` | Seed the database with development data (after migrations) |

### Pre-removal hooks (`pre-rm.d/`)

| Hook | Purpose |
|------|---------|
| `01-backup-database.sh` | Back up the database before removal; stop removal if a required backup cannot be made (respects `DB_BACKUP`) |
| `02-backup-env.sh` | Back up a real `.env` as `0600`; stop removal if its private backup cannot be made |
| `02a-guard-local-storage.sh` | Stop removal unless a real `storage/app` contains only directories and Git-tracked `.gitignore` sentinels with no uncommitted changes; symlinks are allowed only when they resolve outside the worktree |

### Post-removal hooks (`post-rm.d/`)

| Hook | Purpose | Condition |
|------|---------|-----------|
| `01-herd-unsecure.sh` | Remove the Herd SSL certificate and nginx config | — |
| `02-drop-database.sh` | Drop the database | Only when `--drop-db` (`GROVE_DROP_DB`) was passed |
| `example-app/01-cleanup-symlinks.sh` | Repo-specific removal cleanup: logs the removal for audit purposes and is the place to add bespoke teardown (it includes a commented Slack-notification example) | Repo-specific |

### Post-switch hooks (`post-switch.d/`)

| Hook | Purpose | Skip flag |
|------|---------|-----------|
| `01-update-current-link.sh` | Update the `{repo}-current` symlink to point at the active worktree | `GROVE_SKIP_CURRENT_LINK` |
| `02-services-restart.sh` | Restart grove services (Supervisor/Horizon/Reverb) so they pick up the new worktree; exits silently if the repo has no registered service app | `GROVE_SKIP_SERVICES` |
| `example-app/01-configure-env.sh` | Set `APP_URL`, `SESSION_DOMAIN`, and (only when `DB_CREATE=true`) `DB_DATABASE` in `.env` | — |

## Configuration for hooks

### Configuration hierarchy

Database hooks and other configuration-aware hooks read settings from a
**hierarchy**, loaded in order with later values overriding earlier ones:

1. **Defaults** (built into the loader)
2. **Global config** — `~/.groverc`
3. **Project config** — `$HERD_ROOT/.groveconfig`
4. **Repo-specific config** — `$HERD_ROOT/<repo>.git/.groveconfig`

The repo-specific file is resolved using `$GROVE_REPO`, which is only set when
the loader runs inside a hook. In practice the path is
`$HERD_ROOT/${GROVE_REPO}.git/.groveconfig`, so this fourth level only applies in
a hook context.

This lets you, for example:

- Disable database management globally (`DB_CREATE=false` in `~/.groverc`), then
- Re-enable it for a specific repo (`DB_CREATE=true` in that repo's
  `.groveconfig`).

### Shared config loader

Hooks that need configuration should source the shared loader. The relative path
depends on **how deeply nested the hook is**:

```bash
#!/bin/bash
# Resolve the loader relative to this script, then source it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# A hook directly in post-add.d/ (or a repo subdirectory post-add.d/<repo>/):
source "$SCRIPT_DIR/../_lib/load-config.sh"      # one level up

# A hook in post-add.d/_laravel/ (one directory deeper):
# source "$SCRIPT_DIR/../../_lib/load-config.sh" # two levels up
```

Get the depth wrong and the `source` silently sources nothing (or errors), so
the variables below stay at their environment defaults. After sourcing, these
variables are available:

```text
DB_HOST, DB_USER, DB_PASSWORD, DB_CREATE, DB_BACKUP, DB_BACKUP_DIR
HERD_ROOT, HERD_CONFIG, DEFAULT_BASE, PROTECTED_BRANCHES
```

Three caveats:

- **The loader supplies built-in defaults only for** `DB_HOST`, `DB_USER`,
  `DB_PASSWORD`, `DB_CREATE`, `DB_BACKUP`, `DB_BACKUP_DIR`, `HERD_ROOT`, and
  `HERD_CONFIG`. `DEFAULT_BASE` and `PROTECTED_BRANCHES` are set **only if a
  config file defines them** — a hook reading `$DEFAULT_BASE` will get an empty
  value otherwise.
- **`DB_BACKUP_DIR` defaults to `$HOME/Code/Project Support/Worktree/Database/Backup`
  in this loader**, which differs from grove core's own `DB_BACKUP_DIR` default
  of `$HOME/.grove/backups`. If you rely on the default, set `DB_BACKUP_DIR`
  explicitly in `~/.groverc` so the two agree.
- **`#` remains part of quoted values and bare mid-value text**, such as
  `DB_PASSWORD=secret#fragment`. In unquoted values, whitespace before `#`
  starts an inline comment: `DB_HOST=localhost # local server`. `$HOME` and a
  leading `~` expand only in `HERD_ROOT`, `HERD_CONFIG`, and `DB_BACKUP_DIR`.
  Other values remain literal.

Composer and Artisan hooks source `_lib/php-runtime.sh`. Set `GROVE_PHP_BIN` to
an executable path for an explicit runtime; otherwise the helper prefers Herd's
`php` binary and then falls back to `php` on `PATH`.

### Database hook behaviour

| Global `DB_CREATE` | Repo `DB_CREATE` | Result |
|--------------------|------------------|--------|
| `true` (default) | (not set) | Database created, managed by grove |
| `true` | `false` | No database management for this repo |
| `false` | (not set) | No database management |
| `false` | `true` | Database created for this repo only |

The create, import, backup, and drop hooks validate `GROVE_DB_NAME` before
invoking MySQL. Names must contain 1–64 ASCII letters, digits, underscores, or
periods. Empty or unsafe names stop the hook.

For a managed database, the pre-removal backup stops removal if it cannot load
the shared config, reach MySQL, find the backup tools, create the backup
directory, or complete the dump. A confirmed missing database needs no backup.
`--no-backup`, `DB_CREATE=false`, and `DB_BACKUP=false` remain explicit opt-outs.
Seed imports run only against a database with no tables. Set
`GROVE_FORCE_DB_IMPORT=true` only when deliberately replacing an existing
database from the configured dump.

## Control flags (skipping hooks)

Set an environment variable on the `grove` command line to skip individual hooks
for a single run. Because each flag is read inside the hook's own subshell, it
must be present in the environment of the whole `grove` invocation:

```bash
# Skip database creation for one add
GROVE_SKIP_DB=true grove add example-app feature/no-db

# Skip composer install
GROVE_SKIP_COMPOSER=true grove add example-app feature/quick

# Skip all asset work
GROVE_SKIP_NPM=true GROVE_SKIP_BUILD=true grove add example-app feature/backend-only
```

The bundled hooks honour these skip flags:

| Flag | Skips |
|------|-------|
| `GROVE_SKIP_PREFLIGHT` | `pre-add.d/00-laravel-preflight.sh` (silences the warnings) |
| `GROVE_SKIP_DB` | Database creation and seed import |
| `GROVE_SKIP_HERD` | `04-herd-secure.sh` |
| `GROVE_SKIP_COMPOSER` | `05-composer-install.sh` |
| `GROVE_SKIP_NPM` | `06-npm-install.sh` |
| `GROVE_SKIP_BUILD` | `07-build-assets.sh` |
| `GROVE_SKIP_MIGRATE` | `08-run-migrations.sh` |
| `GROVE_SKIP_CURRENT_LINK` | `09-update-current-link.sh` and `post-switch.d/01-update-current-link.sh` |
| `GROVE_SKIP_HOOKS_PATH` | `10-set-hooks-path.sh` |
| `GROVE_SKIP_SERVICES` | `post-switch.d/02-services-restart.sh` |

To disable database behaviour **permanently** for a repo, prefer configuration
over a per-run flag:

```bash
# In ~/.groverc (global) or ~/Herd/example-app.git/.groveconfig (per-repo)
DB_CREATE=false    # Disable database creation/management
DB_BACKUP=false    # Disable database backups on removal
```

## Laravel quick-start (optional)

> Skip this section if you are not using Laravel — nothing here is required for
> the generic hook model above.

Once the example hooks are installed, each Laravel repo needs a one-time setup so
new worktrees get a matching `.env` and the Laravel-specific `post-add` symlinks.
Shared storage is linked only when the repo does not track files under
`storage/app`:

```bash
# After cloning the repo with grove and creating the primary worktree:
grove clone <url> <repo>
grove add <repo> <default-branch>

# Then run once:
bash ~/.grove/hooks/setup-laravel-repo.sh <repo>
```

`setup-laravel-repo.sh` is idempotent and:

- Symlinks `_laravel/*.sh` into `post-add.d/<repo>/`
- Snapshots `.env` and `.env.example` from the primary worktree into
  `~/Development/Code/Worktree/<repo>/<repo>-env/` (`.env` is mode `0600`)
- Ensures the shared `storage/app/` directory exists

If you forget this step, `pre-add.d/00-laravel-preflight.sh` prints the exact
command to run the next time you attempt `grove add`. Setup gaps only warn, but
the hook blocks creation if linked shared storage would strand local files.

> **Note on paths:** the bundled `setup-laravel-repo.sh` and the `_laravel`
> hooks hard-code `~/Development/Code/Worktree` as their template root. Some
> helper output (e.g. `link-repo.sh`) and the [Common patterns](#common-patterns)
> snippets below use a shorter `~/Code/Worktree` for brevity. The exact location
> is a convention you choose — pick one root and use it consistently across your
> own hooks.

## Common patterns

The snippets below choose `~/Code/Worktree` as the template root. This is just a
convention — use whatever directory you prefer, but keep it consistent (the
bundled Laravel hooks use `~/Development/Code/Worktree`, as noted above).

### Pre-built `.env` files

Keep your secrets in one place and symlink them into each worktree:

```bash
# Create private env storage
install -d -m 700 ~/Code/Worktree/example-app/example-app-env

# Install your .env with all secrets
install -m 600 /path/to/configured/.env ~/Code/Worktree/example-app/example-app-env/.env

# Create a repo-specific hook to symlink it
mkdir -p ~/.grove/hooks/post-add.d/example-app
cat > ~/.grove/hooks/post-add.d/example-app/02-symlink-env.sh << 'EOF'
#!/bin/bash
ENV_SOURCE="$HOME/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-env/.env"
ENV_TARGET="${GROVE_PATH}/.env"
ENV_FALLBACK="${GROVE_PATH}/.env.example"
if [[ -f "$ENV_SOURCE" ]]; then
  if [[ -f "$ENV_TARGET" && ! -L "$ENV_TARGET" && -f "$ENV_FALLBACK" ]] &&
     cmp -s "$ENV_FALLBACK" "$ENV_TARGET"; then
    rm -f "$ENV_TARGET" || exit 1
  fi
  if [[ -e "$ENV_TARGET" || -L "$ENV_TARGET" ]]; then
    echo "  Preserved existing .env"
  elif ln -s "$ENV_SOURCE" "$ENV_TARGET"; then
    echo "  Linked .env → $ENV_SOURCE"
  else
    exit 1
  fi
fi
EOF
chmod +x ~/.grove/hooks/post-add.d/example-app/02-symlink-env.sh
```

To repair older templates and backups created before private modes were
enforced, first review the explicit roots, then apply `0600` only to files owned
by your account (add your configured `DB_BACKUP_DIR` if it differs):

```bash
roots=(
  "$HOME/Development/Code/Worktree"
  "$HOME/Code/Worktree"
  "$HOME/.grove/backups"
  "$HOME/Development/Code/Project Support/Worktree/Database/Backup"
)
for root in "${roots[@]}"; do
  [[ -d "$root" ]] || continue
  find "$root" -type f -user "$USER" \
    \( -name .env -o -name '.env.backup.*' -o -name '*.sql' -o -name '*.sql.gz' \) \
    -exec chmod 600 {} +
done
```

### Shared storage directory

Preserve uploaded files and generated content across worktrees:

```bash
# Create shared storage directory
mkdir -p ~/Code/Worktree/example-app/storage/app/public

# Create a repo-specific hook to symlink it
mkdir -p ~/.grove/hooks/post-add.d/example-app
cat > ~/.grove/hooks/post-add.d/example-app/05-symlink-storage.sh << 'EOF'
#!/bin/bash
STORAGE_APP_SOURCE="$HOME/Code/Worktree/${GROVE_REPO}/storage/app"
if [[ -d "$STORAGE_APP_SOURCE" ]]; then
  mkdir -p "${GROVE_PATH}/storage"
  target="${GROVE_PATH}/storage/app"
  if [[ -e "$target" || -L "$target" ]]; then
    echo "  Refusing to replace existing storage/app"
    exit 1
  elif ln -s "$STORAGE_APP_SOURCE" "$target"; then
    echo "  Linked storage/app → $STORAGE_APP_SOURCE"
  else
    exit 1
  fi
fi
EOF
chmod +x ~/.grove/hooks/post-add.d/example-app/05-symlink-storage.sh
```

The bundled hook refuses any populated `storage/app`, including a standard
Laravel tracked `.gitignore` sentinel layout. Replacing that parent with a
symlink would make the worktree dirty and can hide real files; configure an
external storage root in the application instead when sentinels are tracked.

This is useful for:

- User uploads you need to test with
- Generated PDFs, images, or exports
- Cached files that take time to regenerate
- Any files in `storage/app` you want persisted

### Import a database from an SQL dump

For repos that need a baseline database:

```bash
# Store your SQL dump
install -d -m 700 ~/Code/Worktree/example-app/example-app-db
(umask 077; mysqldump example_app_reference | gzip > ~/Code/Worktree/example-app/example-app-db/example-app.sql.gz)

# Install the guarded example hook (it refuses to import over existing tables)
cp ~/.grove/hooks/post-add.d/myapp/04-import-database.sh \
  ~/.grove/hooks/post-add.d/example-app/04-import-database.sh
chmod +x ~/.grove/hooks/post-add.d/example-app/04-import-database.sh
```

### Quick project navigation

Register worktrees for quick access with a `cproj` shell function (works with the
bundled `00-register-project.sh` hook, which writes to `~/.projects`):

```bash
# Add to ~/.zshrc:
cproj() {
  local dir=$(grep "^$1=" ~/.projects 2>/dev/null | cut -d= -f2)
  if [[ -n "$dir" && -d "$dir" ]]; then
    cd "$dir"
  else
    echo "Project not found: $1"
    echo "Available: $(cut -d= -f1 ~/.projects | tr '\n' ' ')"
  fi
}

# Tab completion for cproj
_cproj() {
  compadd $(cut -d= -f1 ~/.projects 2>/dev/null)
}
compdef _cproj cproj
```

Then use: `cproj login-feature`

## Creating repo-specific hooks

To add custom hooks for a specific repository:

1. **Create the repo directory** (named after the repo):

   ```bash
   mkdir -p ~/.grove/hooks/post-add.d/example-app
   ```

2. **Add your hook scripts** (numbered prefixes control execution order):

   ```bash
   cat > ~/.grove/hooks/post-add.d/example-app/01-custom-setup.sh << 'EOF'
   #!/bin/bash
   echo "  Running custom setup for ${GROVE_REPO}..."
   # Your custom logic here
   EOF
   chmod +x ~/.grove/hooks/post-add.d/example-app/01-custom-setup.sh
   ```

3. **Optionally copy the examples as a starting point:**

   ```bash
   cp examples/hooks/post-add.d/myapp/*.sh ~/.grove/hooks/post-add.d/example-app/
   # Edit as needed
   ```

Repo-specific hooks run **after** all global hooks, so you can:

- Override earlier setup (e.g. replace the copied `.env` with a symlink)
- Add extra steps specific to that project
- Import project-specific data

## Non-Laravel projects

The hook *mechanism* has nothing to do with Laravel — the bundled examples just
happen to target it. For projects without Laravel/PHP, skip the framework hooks
using one of the mechanisms below.

> **Why not a sibling "skip" hook?** It is tempting to drop a
> `00-skip-laravel.sh` into the repo's hook directory that does
> `export GROVE_SKIP_DB=true`. **This cannot work.** Each hook runs in its own
> subshell, so an `export` never reaches the sibling hooks it is meant to
> influence — even though a repo hook numbered `00-` would run early in the
> merged sequence. Use one of the following instead.

**Per-invocation (one-off):** set the skip flag(s) on the `grove` command line
itself, so they are present in the environment for every hook in that run (see
[Control flags](#control-flags-skipping-hooks) for the full list):

```bash
GROVE_SKIP_DB=true GROVE_SKIP_COMPOSER=true grove add frontend-app feature/ui
```

**Per-repo via `.groveconfig`:** for database management, disable it permanently
for the repo:

```bash
# In ~/Herd/frontend-app.git/.groveconfig
DB_CREATE=false    # No database created/managed for this repo
DB_BACKUP=false    # No database backup on removal
```

**Don't install them at all:** simply don't install the Laravel hooks for this
repo and only use the ones you need.

## Tips

- **Numbering:** use `00-`, `01-`, etc. to control execution order (sorted
  numerically, so `10-` runs after `2-`).
- **Permissions:** every hook must be executable (`chmod +x`) **and** owned by
  you, **and** not group- or world-writable (see
  [Security model](#security-model)).
- **No prompts:** stdin is `/dev/null`, so hooks cannot ask for interactive
  input — read from the environment or config files instead.
- **Conditionals:** check that files exist before acting on them.
- **Output:** prefix messages with spaces (`echo "  message"`) for clean,
  indented output.
- **Failures:** `post-*` hooks continue even if one fails; `pre-*` hooks can
  abort the operation by exiting non-zero.

## Migrating from built-in setup

If you used grove before hooks existed, the old built-in Laravel setup is now
performed entirely by hooks. Run the installer with `--merge` to add the example
hooks without overwriting any custom ones:

```bash
cd /path/to/grove-cli
./install.sh --merge
```

This installs the example hooks without overwriting any custom hooks you may
have.
