# Configuration Reference

This is the complete reference for configuring `grove`: every recognised config key (with its type, default, and effect), the precedence order between the global, project and repo-specific config files, the environment variables available to lifecycle hooks, and the shared config loader for hook authors.

It is written for two audiences:

- **Users** customising grove via `~/.groverc`, a project `.groveconfig`, or a per-repo `.groveconfig`.
- **Hook authors** writing lifecycle scripts that need to read grove's configuration.

> **Terminology.** A *worktree* is a checked-out working copy of a branch that grove manages under `HERD_ROOT`. A *bare repo* is the shared git directory (`<repo>.git/`) all of a project's worktrees attach to. *Herd* is Laravel Herd, the local PHP environment grove optionally integrates with. A *slug* is a filesystem-safe form of a branch name (`feature/login` → `feature-login`).

## Contents

- [Configuration hierarchy](#configuration-hierarchy)
- [Config-file keys vs environment variables](#config-file-keys-vs-environment-variables)
- [Value syntax and path expansion](#value-syntax-and-path-expansion)
- [Config files](#config-files)
  - [Global config (`~/.groverc`)](#global-config-groverc)
  - [Project config (`$HERD_ROOT/.groveconfig`)](#project-config-herd_rootgroveconfig)
  - [Repo-specific config (`<bare-repo>/.groveconfig`)](#repo-specific-config-bare-repogroveconfig)
- [All configuration keys](#all-configuration-keys)
  - [Core settings](#core-settings)
  - [Database settings](#database-settings)
  - [Hook settings](#hook-settings)
  - [URL settings](#url-settings)
  - [Branch settings](#branch-settings)
  - [Performance and behaviour settings](#performance-and-behaviour-settings)
  - [Repository groups](#repository-groups)
- [Environment-only variables](#environment-only-variables)
- [Command-line flags that affect configuration](#command-line-flags-that-affect-configuration)
- [Hooks](#hooks)
  - [Hook resolution order](#hook-resolution-order)
  - [Hook gating behaviour](#hook-gating-behaviour)
  - [Environment variables for hooks](#environment-variables-for-hooks)
  - [Skip variables (consumed by the example hooks)](#skip-variables-consumed-by-the-example-hooks)
- [Shared config loader for hooks](#shared-config-loader-for-hooks)
- [Viewing the current configuration](#viewing-the-current-configuration)
- [Worked examples](#worked-examples)
- [Tips](#tips)

## Configuration hierarchy

Configuration is loaded in order, with later sources overriding earlier ones:

1. **Built-in defaults** — sensible defaults for all settings (see the tables below).
2. **Global config** (`~/.groverc`) — your personal settings for all repositories.
3. **Project config** (`$HERD_ROOT/.groveconfig`) — settings for all repos in your Herd folder.
4. **Repo-specific config** (`<bare-repo>/.groveconfig`) — overrides for a single repository.

The repo-specific config is the `.groveconfig` file inside that repository's *bare* git directory (e.g. `~/Herd/example-app.git/.groveconfig`). It is consulted only when grove resolves a specific repository for a command, and **only four keys can be overridden there** (see [Repo-specific config](#repo-specific-config-bare-repogroveconfig)). Before applying each repo's overrides, grove resets those four keys to the global baseline, so a per-repo override never leaks into the next repo during multi-repo loops (e.g. `grove recent`, `grove dashboard`).

## Config-file keys vs environment variables

> **Important:** the name you use inside a config file is often **not** the same as the environment variable that overrides it.

Config-file keys carry their plain names (e.g. `DEFAULT_BASE`). The equivalent environment variable that you would `export` in your shell is frequently prefixed or reordered (e.g. `GROVE_BASE_DEFAULT`). Setting `GROVE_BASE_DEFAULT` in a `.groverc` file does nothing, and setting `DEFAULT_BASE` in your shell environment does nothing — each name works in exactly one context.

| Config-file key | Environment-variable override |
|---|---|
| `HERD_ROOT` | `HERD_ROOT` (same) |
| `HERD_CONFIG` | `HERD_CONFIG` (same) |
| `DEFAULT_BASE` | `GROVE_BASE_DEFAULT` |
| `DEFAULT_EDITOR` | `GROVE_EDITOR` |
| `DB_HOST` | `GROVE_DB_HOST` |
| `DB_PORT` | `GROVE_DB_PORT` |
| `DB_USER` | `GROVE_DB_USER` |
| `DB_PASSWORD` | `GROVE_DB_PASSWORD` |
| `DB_CREATE` | `GROVE_DB_CREATE` |
| `DB_BACKUP` | `GROVE_DB_BACKUP` |
| `DB_BACKUP_DIR` | `GROVE_DB_BACKUP_DIR` |
| `GROVE_URL_SUBDOMAIN` | `GROVE_URL_SUBDOMAIN` (same) |
| `GROVE_HOOKS_DIR` | `GROVE_HOOKS_DIR` (same) |
| `GROVE_TEMPLATES_DIR` | `GROVE_TEMPLATES_DIR` (same) |
| `GROVE_MAX_PARALLEL` | `GROVE_MAX_PARALLEL` (same) |
| `GROVE_SHARED_DEPS_DIR` | `GROVE_SHARED_DEPS_DIR` (same) |
| `GROVE_STALE_THRESHOLD` | `GROVE_STALE_THRESHOLD` (same) |
| `PROTECTED_BRANCHES` | `GROVE_PROTECTED_BRANCHES` |
| `BRANCH_PATTERN` | `GROVE_BRANCH_PATTERN` |
| `BRANCH_EXAMPLES` | `GROVE_BRANCH_EXAMPLES` |
| `REPO_GROUPS` | `GROVE_REPO_GROUPS` |

The **Env override** column in the [All configuration keys](#all-configuration-keys) tables repeats this mapping per key.

## Value syntax and path expansion

Config files are **parsed as `key=value` pairs against a whitelist — they are never sourced as shell.** Any key that is not in the recognised list is silently ignored, and no shell expansion or command substitution runs. This is a deliberate security boundary: a malformed or hostile config file cannot execute code.

Consequences for writing values:

- **Quoting is optional.** `DEFAULT_BASE=origin/staging` and `DEFAULT_BASE="origin/staging"` are equivalent. Quote values that contain spaces (e.g. `PROTECTED_BRANCHES="staging main master"`).
- **Inline comments after an *unquoted* value are stripped.** ` # comment` (whitespace, then `#`) is removed from the end of an unquoted value. Inside a quoted value the `#` is kept, so `DB_PASSWORD="my#pass"` survives intact.
- **`$HOME` and a leading `~` are expanded for path-typed keys only.** The parser expands them for exactly these seven keys:

  `HERD_ROOT`, `HERD_CONFIG`, `DEFAULT_EDITOR`, `DB_BACKUP_DIR`, `GROVE_HOOKS_DIR`, `GROVE_TEMPLATES_DIR`, `GROVE_SHARED_DEPS_DIR`

  For **all other keys**, `$HOME` and `~` are taken **verbatim** — they are not expanded. For example `PROTECTED_BRANCHES="~/foo"` would store the literal string `~/foo`.

## Config files

### Global config (`~/.groverc`)

Your primary configuration file. Create it during first-time setup (`grove setup`) or by hand. A copy with annotated defaults ships as `.groverc.example` in the repository.

```bash
# Where your Herd sites and bare repos live (path-typed: $HOME / ~ are expanded)
HERD_ROOT=$HOME/Herd

# Default base branch for new worktrees and the rebase target for `grove sync`
DEFAULT_BASE=origin/staging

# Editor opened by `grove code` / `grove switch` (cursor, code, zed, etc.)
DEFAULT_EDITOR=cursor

# MySQL connection details (read by the reference DB helpers, not by grove core)
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=

# Gates for the reference DB helpers that lifecycle hooks invoke
DB_CREATE=true            # gate for the DB-create helper (run by example hooks)
DB_BACKUP=true            # gate for the DB-backup helper (run by example hooks)
DB_BACKUP_DIR="$HOME/.grove/backups"

# Branches that require -f / --force to remove (quote: contains spaces)
PROTECTED_BRANCHES="staging main master"

# Hooks directory (path-typed)
GROVE_HOOKS_DIR="$HOME/.grove/hooks"

# Maximum concurrent operations for parallel commands
GROVE_MAX_PARALLEL=4

# Optional branch-name validation (empty = no enforcement)
BRANCH_PATTERN="^(feature|fix|hotfix|release)/[a-z0-9-]+$"
BRANCH_EXAMPLES="feature/login-form, fix/broken-auth"
```

> **Note on the bundled `.groverc.example`.** Its comments still say database creation/backup happen "when running `grove add`/`grove rm`". That wording is slightly out of date: grove core does **not** create, back up, or drop databases itself — those actions live entirely in the reference helpers run by lifecycle hooks (see [Database settings](#database-settings)). This reference is the accurate description; the example file's comments are the thing to reconcile, not this doc.

### Project config (`$HERD_ROOT/.groveconfig`)

Optional file for settings that apply to all repositories in your Herd folder. It uses the same format and the same whitelist as `~/.groverc`, and is loaded immediately after it (so it overrides global values and is overridden by repo-specific config). Useful for team-shared defaults committed alongside a project.

### Repo-specific config (`<bare-repo>/.groveconfig`)

Each repository can carry its own configuration inside its bare git directory, e.g.:

- `~/Herd/example-app.git/.groveconfig`
- `~/Herd/api-service.git/.groveconfig`

Unlike the global/project files, the repo config uses a **restricted whitelist** — only these four keys are honoured. **Any other key in a repo `.groveconfig` is silently ignored.**

| Setting | Effect | Example |
|---|---|---|
| `DEFAULT_BASE` | Base branch for new worktrees / `grove sync` target | `origin/develop` |
| `GROVE_URL_SUBDOMAIN` | URL subdomain prefix (e.g. `api` → `api.feature.test`) | `api` |
| `PROTECTED_BRANCHES` | Branches requiring `-f` to remove | `main master` |
| `GROVE_STALE_THRESHOLD` | Commits behind base before a branch is marked stale | `30` |

Before applying a repo's overrides, grove resets these four keys to their global baseline, so an override from one repo cannot bleed into the next during multi-repo operations.

**Example repo config:**

```bash
# ~/Herd/example-app.git/.groveconfig

# This repo uses develop as the default base branch
DEFAULT_BASE=origin/develop

# Optional: custom protected branches for this repo
# PROTECTED_BRANCHES="main develop"

# Optional: mark a branch stale once it is this many commits behind base
# GROVE_STALE_THRESHOLD=30
```

## All configuration keys

These tables cover every key in grove's config-file whitelist. For each: its type, default, the environment variable that overrides it, whether the parser expands `$HOME`/`~` in its value (the *Path* column), and whether it may be overridden in a repo-specific `.groveconfig` (the *Repo* column).

### Core settings

| Key | Type | Default | Env override | Path | Repo | Description |
|---|---|---|---|:--:|:--:|---|
| `HERD_ROOT` | path | `$HOME/Herd` | `HERD_ROOT` | ✓ | | Directory containing your Herd sites and bare repos. Worktrees must live under this path to be auto-detected. |
| `HERD_CONFIG` | path | `$HOME/Library/Application Support/Herd/config` | `HERD_CONFIG` | ✓ | | Herd configuration directory. |
| `DEFAULT_BASE` | string | `origin/staging` | `GROVE_BASE_DEFAULT` | | ✓ | Default base branch for `grove add`; rebase target for `grove sync`. |
| `DEFAULT_EDITOR` | string (command/path) | `cursor` | `GROVE_EDITOR` | ✓ | | Editor opened by `grove code` and `grove switch`. |

### Database settings

> grove core never touches MySQL. These keys configure the **reference DB helpers** that the bundled example lifecycle hooks invoke (see `examples/hooks/`). They have no effect unless those hooks — or your own — are installed.

| Key | Type | Default | Env override | Path | Repo | Description |
|---|---|---|---|:--:|:--:|---|
| `DB_HOST` | string | `127.0.0.1` | `GROVE_DB_HOST` | | | MySQL host. |
| `DB_PORT` | integer | `3306` | `GROVE_DB_PORT` | | | MySQL port. |
| `DB_USER` | string | `root` | `GROVE_DB_USER` | | | MySQL user. |
| `DB_PASSWORD` | string | (empty) | `GROVE_DB_PASSWORD` | | | MySQL password. |
| `DB_CREATE` | boolean | `true` | `GROVE_DB_CREATE` | | | Gate for the reference DB-create helper. Normalised to strict `true`/`false` (truthy synonyms `1`/`yes`/`on` accepted; anything else becomes `false` with a warning). |
| `DB_BACKUP` | boolean | `true` | `GROVE_DB_BACKUP` | | | Gate for the reference DB-backup helper that runs on removal. Same normalisation as `DB_CREATE`. |
| `DB_BACKUP_DIR` | path | `$HOME/.grove/backups` | `GROVE_DB_BACKUP_DIR` | ✓ | | Backup directory used by the reference DB-backup helper. Backups are organised as `<dir>/<repo>/<db>_<timestamp>.sql`. |

### Hook settings

| Key | Type | Default | Env override | Path | Repo | Description |
|---|---|---|---|:--:|:--:|---|
| `GROVE_HOOKS_DIR` | path | `$HOME/.grove/hooks` | `GROVE_HOOKS_DIR` | ✓ | | Directory containing lifecycle hook scripts and their `.d/` subdirectories. |
| `GROVE_TEMPLATES_DIR` | path | `$HOME/.grove/templates` | `GROVE_TEMPLATES_DIR` | ✓ | | Directory containing worktree template `.conf` files. Empty on a fresh install — example templates ship under `examples/templates/` and must be copied in. |

See [Hooks](#hooks) below for resolution order, gating behaviour, and the environment variables available to hook scripts.

### URL settings

| Key | Type | Default | Env override | Path | Repo | Description |
|---|---|---|---|:--:|:--:|---|
| `GROVE_URL_SUBDOMAIN` | string | (empty) | `GROVE_URL_SUBDOMAIN` | | ✓ | Optional subdomain prefix for generated URLs (e.g. `api` → `api.feature.test`). |

### Branch settings

| Key | Type | Default | Env override | Path | Repo | Description |
|---|---|---|---|:--:|:--:|---|
| `PROTECTED_BRANCHES` | string (space-separated) | `staging main master` | `GROVE_PROTECTED_BRANCHES` | | ✓ | Branch names that require `-f`/`--force` to remove. |
| `BRANCH_PATTERN` | string (regex) | (empty) | `GROVE_BRANCH_PATTERN` | | | Optional pattern enforced on new branch names; empty disables enforcement. |
| `BRANCH_EXAMPLES` | string | `feature/my-feature, bugfix/fix-login` | `GROVE_BRANCH_EXAMPLES` | | | Example branch names shown in the message when `BRANCH_PATTERN` validation fails. |

### Performance and behaviour settings

| Key | Type | Default | Env override | Path | Repo | Description |
|---|---|---|---|:--:|:--:|---|
| `GROVE_MAX_PARALLEL` | integer | `4` | `GROVE_MAX_PARALLEL` | | | Maximum concurrent operations for parallel commands (`pull-all`, `build-all`, `exec-all`, `prune --all-repos`). Validated as a positive integer. |
| `GROVE_STATUS_PARALLEL` | integer | `8` | `GROVE_STATUS_PARALLEL` | | | Maximum concurrent per-worktree status lookups in `grove ls` (git status, ahead/behind, and health). Deliberately separate from `GROVE_MAX_PARALLEL`, which bounds *mutating* work against a remote; gathering status is read-only and local, so it runs wider. Set to `1` for a serial walk. A non-numeric or zero value falls back to serial rather than failing. |
| `GROVE_STALE_THRESHOLD` | integer | `50` | `GROVE_STALE_THRESHOLD` | | ✓ | Commits behind base before a branch is marked **stale** in `grove status`/`grove dashboard`. Validated as a non-negative integer; invalid values fall back to `50` with a warning. |
| `GROVE_SHARED_DEPS_DIR` | path | `$HOME/.grove/shared-deps` | `GROVE_SHARED_DEPS_DIR` | ✓ | | Cache directory used by `grove share-deps` for shared `vendor`/`node_modules`. |

### Repository groups

| Key | Type | Default | Env override | Path | Repo | Description |
|---|---|---|---|:--:|:--:|---|
| `REPO_GROUPS` | string | (empty) | `GROVE_REPO_GROUPS` | | | Predefined repository groups for multi-repo operations. Groups can also be managed with `grove group add`. |

## Environment-only variables

These are read from the **shell environment only** — they are not config-file keys, so setting them inside `~/.groverc` has no effect.

| Variable | Default | Description |
|---|---|---|
| `GROVE_CONFIG` | `~/.groverc` | Path to the global config file. grove reads this from the environment to locate the file *before* parsing it, so it cannot itself live inside a config file. |
| `GROVE_FETCH_CACHE_TTL` | `30` | Seconds that a `git fetch` result is reused before refetching. `0` disables the cache (always fetch fresh). The `--no-cache` flag sets this to `0` for one invocation; `--refresh` clears the cache before running. |
| `GROVE_INFO_FAST` | `false` | When `true`, `grove info --json` skips the heavy disk-size and MySQL probes and emits metadata only. |
| `GROVE_SKIP_*` | (unset) | Per-step skip flags consumed by the bundled example hooks — see [Skip variables](#skip-variables-consumed-by-the-example-hooks). |

## Command-line flags that affect configuration

A few flags override config-derived behaviour at runtime. This is **not** the full flag reference — see the command reference for every flag.

| Flag | Applies to | Effect |
|---|---|---|
| `-f, --force` | `grove rm` (and others) | Skip confirmation and allow removal of a protected branch. |
| `--delete-branch` | `grove rm` | Delete the git branch after removing the worktree. |
| `--drop-db` | `grove rm` | Drop the worktree's database instead of leaving it (exposed to hooks as `GROVE_DROP_DB`). |
| `--no-backup` | `grove rm` | Skip the DB backup that normally runs on removal (exposed to hooks as `GROVE_NO_BACKUP`). |
| `--no-cache` | git-fetching commands | Bypass the fetch cache for this run (sets `GROVE_FETCH_CACHE_TTL=0`). |
| `--refresh` | git-fetching commands | Clear the fetch cache before running. |
| `--dry-run` | `grove add` | Preview the worktree creation without making changes. |

## Hooks

Lifecycle hooks are scripts grove runs at defined points in a worktree's life. They live under `GROVE_HOOKS_DIR` (default `~/.grove/hooks`). The hook events are: `pre-add`, `post-add`, `pre-rm`, `post-rm`, `post-pull`, `post-sync`, `post-switch`, `pre-move`, `post-move`.

For security, grove only runs a hook that is owned by the current user and is **not** group- or world-writable; anything failing that check is skipped with a warning.

### Hook resolution order

When a lifecycle event occurs (e.g. `post-add`), hooks are discovered and executed in this order:

1. **Single hook file:** `$GROVE_HOOKS_DIR/<hook>` (if it exists and is owner-executable).
2. **Global hook directory:** `$GROVE_HOOKS_DIR/<hook>.d/*.sh` (executable files, numeric-sorted).
3. **Repo-specific directory:** `$GROVE_HOOKS_DIR/<hook>.d/<repo>/*.sh` (executable files, numeric-sorted).

**Notes:**

- Directory scanning is **non-recursive** — only files directly in those locations run.
- Subdirectories are ignored except the exact `<repo>/` folder matching the current repository.
- Use numbered prefixes (`00-`, `01-`, …) to control order. Sorting is numeric, so `2-foo.sh` runs before `10-foo.sh`.

See `examples/hooks/README.md` for worked hook examples.

### Hook gating behaviour

The `pre-*` hooks are **gating**: if any `pre-add`, `pre-rm`, or `pre-move` hook exits non-zero, the operation is **aborted**. Use this to veto an action (e.g. a pre-add preflight that refuses to proceed if a dependency is missing).

All `post-*` hooks (`post-add`, `post-rm`, `post-pull`, `post-sync`, `post-switch`, `post-move`) are **non-fatal**: a non-zero exit produces a warning but does not undo or stop the operation.

Each hook runs in its own subshell with stdin redirected from `/dev/null`, so a hook cannot block waiting for input.

### Environment variables for hooks

grove exports these into every hook's environment:

| Variable | Example | Description |
|---|---|---|
| `GROVE_REPO` | `example-app` | Repository name. |
| `GROVE_BRANCH` | `feature/new-feature` | Branch name. |
| `GROVE_BRANCH_SLUG` | `feature-new-feature` | Filesystem-safe branch slug (`/` replaced with `-`). |
| `GROVE_PATH` | `/Users/you/Herd/example-app-worktrees/new-feature` | Worktree directory path. |
| `GROVE_URL` | `https://new-feature.test` | Application URL. |
| `GROVE_DB_NAME` | `example_app__feature_new_feature` | Database name. |
| `GROVE_HOOK_NAME` | `post-add` | Name of the current hook event. |
| `GROVE_DROP_DB` | `true` | Set only when `--drop-db` was passed. |
| `GROVE_NO_BACKUP` | `true` | Set only when `--no-backup` was passed. |

### Skip variables (consumed by the example hooks)

`GROVE_SKIP_*` variables are **not interpreted by grove core** — grove itself does not run composer, npm, build, migrate, Herd, or database steps. They only take effect when the corresponding bundled example hook (in `examples/hooks/`) is installed, or when a template sets them (templates may set the first six, which `load_template` resets between runs).

When the matching example hook is installed, set the variable before `grove add` (or `grove switch`) to skip that step. For example:

```bash
GROVE_SKIP_DB=true GROVE_SKIP_COMPOSER=true grove add example-app feature/ui
```

| Variable | Skips | Honoured by example hook |
|---|---|---|
| `GROVE_SKIP_DB=true` | Database creation | `post-add.d/03-create-database.sh` |
| `GROVE_SKIP_HERD=true` | Herd link/secure | `post-add.d/04-herd-secure.sh` |
| `GROVE_SKIP_COMPOSER=true` | `composer install` | `post-add.d/05-composer-install.sh` |
| `GROVE_SKIP_NPM=true` | `npm install` | `post-add.d/06-npm-install.sh` |
| `GROVE_SKIP_BUILD=true` | Asset build | `post-add.d/07-build-assets.sh` |
| `GROVE_SKIP_MIGRATE=true` | Laravel migrations | `post-add.d/08-run-migrations.sh` |
| `GROVE_SKIP_CURRENT_LINK=true` | `{repo}-current` symlink update | `post-add.d/09-update-current-link.sh`, `post-switch.d/01-update-current-link.sh` |
| `GROVE_SKIP_HOOKS_PATH=true` | Git hooks-path configuration | `post-add.d/10-set-hooks-path.sh` |
| `GROVE_SKIP_SERVICES=true` | Service restart on switch | `post-switch.d/02-services-restart.sh` |
| `GROVE_SKIP_PUSH=true` | Pushing a brand-new branch to `origin` during `grove add` | built into `grove add` itself, not a hook |
| `GROVE_SKIP_PREFLIGHT=true` | Laravel preflight checks | `pre-add.d/00-laravel-preflight.sh` |

> Because each hook runs in its own subshell, exporting a skip variable *from inside one hook* will not affect later hooks. Set it on the `grove` command line (as above) so the whole run sees it.

## Shared config loader for hooks

Hooks that need to read grove's configuration with the same global → project → repo precedence can use the shared loader. It **ships at `examples/hooks/_lib/load-config.sh`** in the repository and must be **copied into `$GROVE_HOOKS_DIR/_lib/`** (default `~/.grove/hooks/_lib/`), alongside your hooks, before the source line below resolves.

```bash
cp examples/hooks/_lib/load-config.sh ~/.grove/hooks/_lib/
```

### Usage

```bash
#!/bin/bash
# At the start of a hook in a .d/ subdirectory (e.g. post-add.d/03-foo.sh):
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../_lib/load-config.sh"

# After sourcing, these are populated with hierarchy-resolved values:
#   DB_HOST, DB_USER, DB_PASSWORD, DB_CREATE, DB_BACKUP, DB_BACKUP_DIR
#   HERD_ROOT, HERD_CONFIG, DEFAULT_BASE, PROTECTED_BRANCHES

if [[ "$DB_CREATE" != "true" ]]; then
  echo "  Skipping - database management disabled"
  exit 0
fi
```

The relative path depends on where the hook lives:

- **`.d/` hook** at `$GROVE_HOOKS_DIR/<event>.d/NN-x.sh` → use `../_lib/load-config.sh` (the example above).
- **Top-level hook** at `$GROVE_HOOKS_DIR/<event>` → use `./_lib/load-config.sh` (one directory up would be wrong).

### How it works

The loader reads configuration files in order, each overriding the last:

1. Sets its own defaults.
2. Loads `~/.groverc` (global config).
3. Loads `$HERD_ROOT/.groveconfig` (project config).
4. Loads `$HERD_ROOT/${GROVE_REPO}.git/.groveconfig` (repo-specific config, using `GROVE_REPO` from the hook environment).

> **The loader is a standalone bash reimplementation — its defaults and whitelist differ from grove core.** In particular:
>
> - Its default `DB_BACKUP_DIR` is `$HOME/Code/Project Support/Worktree/Database/Backup`, **not** `~/.grove/backups`. To avoid surprises, set `DB_BACKUP_DIR` explicitly in `~/.groverc`.
> - It expands `$HOME` in values but does **not** expand a leading `~`.
> - It whitelists a smaller key set (the `DB_*`/Herd/`DEFAULT_BASE`/`PROTECTED_BRANCHES` keys listed above) — no `DB_PORT`, and none of the other `GROVE_*` keys.
>
> Values still follow the same global → project → repo precedence as grove, but the defaults are not identical.

## Viewing the current configuration

Show the effective configuration (resolved defaults plus config-file and environment overrides):

```bash
grove config
```

Run a full environment and configuration check:

```bash
grove doctor
```

## Worked examples

### Typical global config (`~/.groverc`)

```bash
HERD_ROOT=$HOME/Herd
DEFAULT_BASE=origin/staging
DEFAULT_EDITOR=zed

DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=
DB_CREATE=false
DB_BACKUP=false

PROTECTED_BRANCHES="staging main master"
```

### Repo using `develop` (`~/Herd/example-app.git/.groveconfig`)

```bash
# example-app uses develop instead of staging
DEFAULT_BASE=origin/develop
```

### API service with a subdomain (`~/Herd/api-service.git/.groveconfig`)

```bash
# Serve this repo's worktrees under api.<branch>.test
DEFAULT_BASE=origin/main
GROVE_URL_SUBDOMAIN=api
```

## Tips

1. **Run `grove setup`** for an interactive first-time configuration wizard.
2. **Verify with `grove doctor`** to confirm everything is set up correctly.
3. **Keep repo configs minimal** — only override the four keys that genuinely differ from your global settings.
4. **Mind the namespace split** — config files use names like `DEFAULT_BASE`; the matching shell environment variable is `GROVE_BASE_DEFAULT`. See the [mapping table](#config-file-keys-vs-environment-variables).
5. **Quote values with spaces** (e.g. `PROTECTED_BRANCHES`), and remember `~`/`$HOME` only expand for path-typed keys.

## Removal gate

`grove rm` asks `wt-removal-check` whether removing the worktree would lose
anything — uncommitted changes, commits no remote has, or a live agent session —
and refuses when it would. See the `rm` entry in [Commands](commands.md).

| Key | Default | Meaning |
|---|---|---|
| `GROVE_REMOVAL_CHECK_BIN` | *(unset)* | Explicit path to `wt-removal-check`. Otherwise `PATH` is searched, then `~/.local/bin` and `~/.claude/bin` — a GUI-launched process does not inherit the shell `PATH`. |

`grove rm -f` does **not** bypass the gate, and a gate that cannot be found
blocks too. Interactively the loss is shown and you are asked to confirm; with
`--json` the removal fails with `REMOVAL_BLOCKED` and there is no override.
