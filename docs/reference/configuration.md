# Configuration Guide

This document describes the complete configuration system for `grove`, including global settings, project-level overrides, and repo-specific configurations.

## Configuration Hierarchy

Configuration is loaded in order, with later sources overriding earlier ones:

1. **Built-in defaults** - Sensible defaults for all settings
2. **Global config** (`~/.groverc`) - Your personal settings for all repositories
3. **Project config** (`$HERD_ROOT/.groveconfig`) - Settings for all repos in a Herd folder
4. **Repo-specific config** (`<bare-repo>/.groveconfig`) - Settings for a single repository

## Configuration Files

### Global Config (`~/.groverc`)

Your primary configuration file. Create this during first-time setup or manually:

```bash
# Where your Herd sites live
HERD_ROOT=/Users/yourname/Herd

# Default base branch for new worktrees
DEFAULT_BASE=origin/staging

# Editor to open with 'grove code' (cursor, code, zed, etc.)
DEFAULT_EDITOR=cursor

# Database connection (for auto-creating databases)
DB_HOST=127.0.0.1
DB_USER=root
DB_PASSWORD=
DB_CREATE=true  # Set to 'false' to disable auto-creation

# Database backup on removal
DB_BACKUP=true  # Set to 'false' to disable backups
DB_BACKUP_DIR="$HOME/Code/Project Support/Worktree/Database/Backup"

# Protected branches (require -f to remove)
PROTECTED_BRANCHES="staging main master"

# Hooks directory (default: ~/.grove/hooks)
GROVE_HOOKS_DIR="$HOME/.grove/hooks"

# Maximum parallel operations
GROVE_MAX_PARALLEL=4

# Branch naming pattern (optional regex)
BRANCH_PATTERN="^(feature|fix|hotfix|release)/[a-z0-9-]+$"
BRANCH_EXAMPLES="feature/login-form, fix/broken-auth"
```

### Project Config (`$HERD_ROOT/.groveconfig`)

Optional file for settings that apply to all repositories in your Herd folder. Uses the same format as `~/.groverc`.

### Repo-Specific Config (`<bare-repo>/.groveconfig`)

Each repository can have its own configuration file inside the bare git directory. This is useful for:

- Setting a different default base branch per repo
- Customising URL patterns for specific repos
- Defining repo-specific protected branches

**Location:** Inside the bare repo directory, e.g.:
- `~/Herd/myapp.git/.groveconfig`
- `~/Herd/api-service.git/.groveconfig`

**Supported settings** (these can be overridden per-repo):

| Setting | Description | Example |
|---------|-------------|---------|
| `DEFAULT_BASE` | Base branch for new worktrees | `origin/develop` |
| `GROVE_URL_SUBDOMAIN` | URL subdomain pattern | `api` |
| `PROTECTED_BRANCHES` | Branches requiring `-f` to remove | `main master` |
| `DB_CREATE` | Enable/disable database creation for this repo | `true` |

**Example repo config:**

```bash
# ~/Herd/modernprintworks.git/.groveconfig

# This repo uses develop as the default base branch
DEFAULT_BASE=origin/develop

# Optional: custom protected branches for this repo
# PROTECTED_BRANCHES="main develop"

# Enable database creation for this repo (overrides global DB_CREATE=false)
# DB_CREATE=true
```

## All Configuration Options

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `HERD_ROOT` | `$HOME/Herd` | Directory containing your sites and bare repos |
| `HERD_CONFIG` | `$HOME/Library/Application Support/Herd/config` | Herd configuration directory |
| `DEFAULT_BASE` | `origin/staging` | Default branch for new worktrees |
| `DEFAULT_EDITOR` | `cursor` | Editor for `grove code` command |
| `GROVE_CONFIG` | `~/.groverc` | Path to global config file |

### Database Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` | `127.0.0.1` | MySQL host for database operations |
| `DB_USER` | `root` | MySQL user for database operations |
| `DB_PASSWORD` | (empty) | MySQL password |
| `DB_CREATE` | `true` | Auto-create database on `grove add` |
| `DB_BACKUP` | `true` | Backup database before `grove rm` |
| `DB_BACKUP_DIR` | `~/Code/Project Support/Worktree/Database/Backup` | Backup directory |

### Hook Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `GROVE_HOOKS_DIR` | `~/.grove/hooks` | Directory for hook scripts |
| `GROVE_TEMPLATES_DIR` | `~/.grove/templates` | Directory for worktree templates |

### Hook Resolution Order

When a lifecycle event occurs (e.g., `post-add`), hooks are discovered and executed in this order:

1. **Single hook file**: `$GROVE_HOOKS_DIR/<hook>` (if exists and executable)
2. **Global hook directory**: `$GROVE_HOOKS_DIR/<hook>.d/*.sh` (files in alphabetical order)
3. **Repo-specific directory**: `$GROVE_HOOKS_DIR/<hook>.d/<repo>/*.sh` (files in alphabetical order)

**Important notes:**
- Directory scanning is **non-recursive** — only files directly in these locations are executed
- Subdirectories are ignored except for the exact `<repo>/` folder matching the current repository
- Use numbered prefixes (`00-`, `01-`, etc.) to control execution order within each phase

See `examples/hooks/README.md` for detailed hook documentation and examples.

### URL Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `GROVE_URL_SUBDOMAIN` | (empty) | Optional subdomain prefix (e.g., `api` → `api.feature.test`) |

### Branch Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `PROTECTED_BRANCHES` | `staging main master` | Space-separated list of protected branches |
| `BRANCH_PATTERN` | (empty) | Regex pattern for branch name validation |
| `BRANCH_EXAMPLES` | (empty) | Examples shown when validation fails |

### Performance Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `GROVE_MAX_PARALLEL` | `4` | Maximum concurrent parallel operations |
| `GROVE_SHARED_DEPS_DIR` | `~/.grove/shared-deps` | Directory for shared dependencies |

### Repository Groups

| Variable | Default | Description |
|----------|---------|-------------|
| `REPO_GROUPS` | (empty) | Comma-separated repo group definitions |

## Command-Line Flags

Some behaviours are controlled by command-line flags rather than configuration:

| Flag | Command | Description |
|------|---------|-------------|
| `--drop-db` | `grove rm` | Drop the database when removing worktree (default: false) |
| `--no-backup` | `grove rm` | Skip database backup (default: backup if `DB_BACKUP=true`) |
| `--delete-branch` | `grove rm` | Delete the git branch after removing worktree |
| `-f, --force` | `grove rm` | Force removal of protected branches |
| `--dry-run` | various | Show what would be done without executing |

## Environment Variables for Hooks

When hooks run, these environment variables are available:

| Variable | Example | Description |
|----------|---------|-------------|
| `GROVE_REPO` | `myapp` | Repository name |
| `GROVE_BRANCH` | `feature/new-feature` | Branch name |
| `GROVE_BRANCH_SLUG` | `feature-new-feature` | URL-safe branch slug (/ replaced with -) |
| `GROVE_PATH` | `/Users/you/Herd/myapp-worktrees/new-feature` | Worktree directory path |
| `GROVE_URL` | `https://new-feature.test` | Application URL |
| `GROVE_DB_NAME` | `myapp__feature_new_feature` | Database name |
| `GROVE_HOOK_NAME` | `post-add` | Name of the current hook |
| `GROVE_DROP_DB` | `true` | Set to `true` if `--drop-db` flag was used |
| `GROVE_NO_BACKUP` | `true` | Set to `true` if `--no-backup` flag was used |

### Skip Variables

Set these before running `grove add` to skip certain setup steps:

| Variable | Effect |
|----------|--------|
| `GROVE_SKIP_HERD=true` | Skip Herd link/secure |
| `GROVE_SKIP_CURRENT_LINK=true` | Skip updating `{repo}-current` symlink |
| `GROVE_SKIP_DB=true` | Skip database creation |
| `GROVE_SKIP_COMPOSER=true` | Skip composer install |
| `GROVE_SKIP_NPM=true` | Skip npm install |
| `GROVE_SKIP_BUILD=true` | Skip npm build |
| `GROVE_SKIP_MIGRATE=true` | Skip Laravel migrations |
| `GROVE_SKIP_DEVCTL=true` | Skip devctl service restart |

## Shared Config Loader for Hooks

Hooks that need to respect the configuration hierarchy should use the shared config loader at `~/.grove/hooks/_lib/load-config.sh`.

### Usage

```bash
#!/bin/bash
# At the start of your hook:
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../_lib/load-config.sh"

# Now these variables are available and properly overridden:
# DB_HOST, DB_USER, DB_PASSWORD, DB_CREATE, DB_BACKUP, DB_BACKUP_DIR
# HERD_ROOT, HERD_CONFIG, DEFAULT_BASE, PROTECTED_BRANCHES

if [[ "$DB_CREATE" != "true" ]]; then
  echo "  Skipping - database management disabled"
  exit 0
fi
```

### How It Works

The loader reads configuration files in order:
1. Sets sensible defaults
2. Loads `~/.groverc` (global config)
3. Loads `$HERD_ROOT/.groveconfig` (project config)
4. Loads `$HERD_ROOT/${GROVE_REPO}.git/.groveconfig` (repo-specific config)

Each file can override values from previous files, allowing repo-specific overrides.

## Viewing Current Configuration

Use `grove config` to view your current configuration:

```bash
grove config
```

Use `grove doctor` for a comprehensive check of your configuration and hooks:

```bash
grove doctor
```

## Example Setup

### Typical Global Config (`~/.groverc`)

```bash
HERD_ROOT=/Users/danny/Herd
DEFAULT_BASE=origin/staging
DEFAULT_EDITOR=zed

DB_HOST=127.0.0.1
DB_USER=root
DB_PASSWORD=
DB_CREATE=false
DB_BACKUP=false

PROTECTED_BRANCHES="staging main master"
```

### Repo Using develop Branch (`~/Herd/myapp.git/.groveconfig`)

```bash
# myapp uses develop instead of staging
DEFAULT_BASE=origin/develop
```

### API Service with Subdomain (`~/Herd/api.git/.groveconfig`)

```bash
# API service configuration
DEFAULT_BASE=origin/main
GROVE_URL_SUBDOMAIN=api
```

## Tips

1. **Run `grove setup`** for an interactive configuration wizard
2. **Check config with `grove doctor`** to verify everything is set up correctly
3. **Keep repo configs minimal** - only override what's different from global settings
4. **Use comments** in config files to document why settings are different
