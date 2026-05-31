# Advanced Guide

> Power features and developer documentation for grove. For getting started, see the [README](../../README.md). For command reference, see [commands.md](../reference/commands.md).

This guide is for experienced users and contributors who want to bend grove to their workflow. It covers the power features (templates, aliases, repository groups, multi-repo and parallel operations, branch-naming validation, dependency sharing, stable service paths, self-update), the maintenance and recovery commands, the per-repo configuration mechanism, and the developer/build notes for working on grove itself.

A few terms are used throughout:

- **Worktree** — a separate working directory checked out from one shared git repository, so several branches can be checked out at once. grove manages a directory of these per repository.
- **Bare repo** — a `.git` directory with no working tree of its own; grove keeps one bare repo per project under `HERD_ROOT` and creates worktrees from it.
- **Slug** — a branch name made filesystem-safe (for example `feature/login-form` becomes `feature-login-form`) for use in directory names and database names.
- **Herd** — [Laravel Herd](https://herd.laravel.com), the optional local PHP environment grove can integrate with to serve each worktree at its own `.test` domain.

## Contents

- [Worktree Templates](#worktree-templates)
- [Branch Aliases](#branch-aliases)
- [Repository Groups](#repository-groups)
- [Multi-Repository Operations](#multi-repository-operations)
- [Branch Naming Validation](#branch-naming-validation)
- [Dependency Sharing](#dependency-sharing)
- [Stable Paths for Services](#stable-paths-for-services)
- [Per-Repo Configuration Overrides](#per-repo-configuration-overrides)
- [Maintenance & Recovery](#maintenance--recovery)
- [Self-Update](#self-update)
- [Directory Structure](#directory-structure)
- [Developer Guide](#developer-guide)
- [Security](#security)
- [Using grove with Claude Code](#using-grove-with-claude-code)
- [Repository Structure](#repository-structure)

---

## Worktree Templates

Templates let you predefine which setup hooks run when creating worktrees. This is useful when you have different project types or want quick minimal checkouts. Templates are user-supplied `.conf` files in `GROVE_TEMPLATES_DIR` (default `~/.grove/templates`).

**No templates ship enabled by default.** A fresh install creates `~/.grove/templates` empty, so `grove templates` prints `(no templates found)` until you copy some in. The four examples below live in `examples/templates/` in the repo — install them with:

```bash
cp examples/templates/*.conf ~/.grove/templates/
```

### Listing Templates

```bash
grove templates
```

On a fresh install (no templates copied in yet):
```text
Available Templates

  (no templates found)

Usage: grove templates <name>  - Show template details
       grove add <repo> <branch> --template=<name>
```

After copying the example templates in:
```text
Available Templates

  backend - Backend only - PHP, database, no npm/build
  laravel - Laravel with MySQL, Composer, NPM, and migrations
  minimal - Minimal - git worktree only, no setup
  node - Node.js project (npm only, no PHP/database)

Usage: grove templates <name>  - Show template details
       grove add <repo> <branch> --template=<name>
```

### Using a Template

```bash
# Use --template or -t flag when adding a worktree
grove add example-app feature/quick-fix --template=minimal

# Short form
grove add example-app feature/api-work -t backend
```

### Viewing Template Details

```bash
grove templates minimal
```

Output:
```text
Template: minimal

Description: Minimal - git worktree only, no setup

File: /Users/you/.grove/templates/minimal.conf

Settings:
  GROVE_SKIP_DB = true (skipped)
  GROVE_SKIP_COMPOSER = true (skipped)
  GROVE_SKIP_NPM = true (skipped)
  GROVE_SKIP_BUILD = true (skipped)
  GROVE_SKIP_MIGRATE = true (skipped)
  GROVE_SKIP_HERD = true (skipped)

Usage: grove add <repo> <branch> --template=minimal
```

### Creating Custom Templates

Templates are simple key=value files in `~/.grove/templates/`:

```bash
# ~/.grove/templates/api-only.conf
TEMPLATE_DESC="API backend - database and PHP only"

GROVE_SKIP_NPM=true
GROVE_SKIP_BUILD=true
GROVE_SKIP_HERD=true
```

### Example Templates

The repo bundles these templates in `examples/templates/`. They are **not** copied into `~/.grove/templates` by the installer — copy in the ones you want:

| Template | Description |
|----------|-------------|
| `laravel.conf` | Full Laravel setup - database, composer, npm, build, migrations |
| `node.conf` | Node.js projects - npm only, skips PHP and database |
| `minimal.conf` | Git worktree only - skips all setup hooks |
| `backend.conf` | Backend API work - PHP and database, no frontend build |

To install all of them:
```bash
cp examples/templates/*.conf ~/.grove/templates/
```

---

## Branch Aliases

Aliases are **repository-name shortcuts**. They save you typing a long repository name; they do not encode a branch.

> **What an alias actually substitutes:** alias resolution (`resolve_repo_arg`) is applied only to the *first* positional argument — the repo — of `code`, `open`, `cd` and `switch`. If the argument is not a real repository, it is looked up as an alias and replaced with the **repo segment** of the target (`example-app` from `example-app/anything`). The branch part of a stored target is **discarded**. A real repository of the same name always wins over an alias.

### Creating an Alias

```bash
grove alias add <name> <repo>

# Examples
grove alias add app example-app
grove alias add api example-api
```

The target is validated (alphanumerics plus `/ _ - .`, no leading dash, no `..`). You can store a longer target such as `example-app/staging`, but only the leading repo segment is ever used — so prefer a bare repo name to avoid confusion.

### Using an Alias

Aliases work as the repo argument of the navigation commands. The branch is still given explicitly or chosen via fzf:

```bash
# `app` resolves to repo `example-app`, so these are equivalent:
grove cd app feature/login
grove cd example-app feature/login

# Open a worktree's URL in the browser
grove open app feature/login

# Switch (cd + editor + browser) — branch picked via fzf if omitted
cd "$(grove switch app)"
```

Because the branch is never part of an alias, `grove code app` with no branch behaves exactly like `grove code example-app` with no branch: it shows the fzf picker (or errors if fzf is not installed).

### Managing Aliases

```bash
# List all aliases (bare command, or `grove alias list`)
grove alias
```

Output:
```text
Branch Aliases

  app  → example-app
  api  → example-api
```

```bash
# Remove an alias (rm / remove / delete are equivalent)
grove alias rm app
```

### Alias Storage

Aliases are stored in `GROVE_ALIASES_FILE` (default `~/.grove/aliases`) as simple `name=target` pairs:

```text
app=example-app
api=example-api
```

---

## Repository Groups

Create named groups of repositories for batch operations. Groups work alongside the `--all-repos` flag and multi-repository commands.

### Creating a Group

```bash
grove group add frontend example-app example-api
```

### Using Groups

The `@<group>` prefix is accepted by **`build-all` and `exec-all` only**. `pull-all` and `prune` reject `@` (their repo argument is validated as a plain name) — use `--all-repos` for those instead.

```bash
# Build all worktrees across every repo in the 'frontend' group
grove build-all @frontend

# Execute a command across a group
grove exec-all @frontend "npm run lint"
```

### Managing Groups

```bash
# List all groups (bare command, or `grove group list`)
grove group
```

Output (groups are shown with an `@` prefix):
```text
Repository Groups

  @frontend → example-app example-api
```

```bash
# Show the repos in a group (with worktree counts)
grove group show frontend

# Delete an entire group (rm / remove / delete are equivalent)
grove group rm frontend
```

`grove group add` validates that every named repo exists before saving. To change which repos are in a group, run `grove group add ...` again with the new list.

### Group Storage

Groups are stored in `~/.grove/groups` as simple `name=repos` pairs (the `@` is added only for display):

```text
frontend=example-app example-api
```

---

## Multi-Repository Operations

grove offers two ways to operate across more than one repository:

- **`--all-repos`** — run the command against *every* bare repo under `HERD_ROOT`. Supported by `pull-all`, `prune`, `build-all` and `exec-all`. Not supported with `--json`.
- **`@<group>`** — run against just the repos in a named group (see [Repository Groups](#repository-groups)). Supported by `build-all` and `exec-all` only.

### Supported Commands

| Command | `--all-repos` | `@group` |
|---------|---------------|----------|
| `grove pull-all` | Pull every worktree in every repo | — |
| `grove prune` | Prune every repo in parallel | — |
| `grove build-all` | Build every worktree in every repo | Build the group |
| `grove exec-all` | Run a command in every repo | Run in the group |

### Examples

```bash
# Pull all worktrees across all repositories
grove pull-all --all-repos
```

Output:
```text
→ Pulling all repositories...

example-app (3 worktrees)
  ✔ staging
  ✔ feature/login
  ✔ feature/dashboard

example-api (2 worktrees)
  ✔ main
  ✔ feature/api

✔ Pulled 5 worktrees across 2 repositories
```

```bash
# Build all worktrees everywhere
grove build-all --all-repos

# Run a command in all repos
grove exec-all --all-repos "php artisan cache:clear"

# Prune stale worktree entries across all repos
grove prune --all-repos
```

### Parallel Execution

Multi-repo and bulk operations run in parallel for efficiency. Concurrency is set by `GROVE_MAX_PARALLEL`, which can be a `~/.groverc` value or an environment variable:

```bash
GROVE_MAX_PARALLEL=8  # Default: 4
```

It is validated as a positive integer; an invalid value falls back to `4` with a warning, and values above `20` warn but are honoured.

### Fetch Cache Flags

Commands that fetch from the remote share a short-lived fetch cache (TTL `GROVE_FETCH_CACHE_TTL`, default 30s, `0` disables). Two global flags control it for a single run:

- `--no-cache` — bypass the cache and always fetch fresh (sets the TTL to `0` for this invocation).
- `--refresh` — clear the cache before running the command.

---

## Branch Naming Validation

Configure branch naming patterns to enforce team conventions.

### Setting a Pattern

Add to `~/.groverc`:

```bash
# Require feature/, bugfix/, or hotfix/ prefix
BRANCH_PATTERN="^(feature|bugfix|hotfix)/[a-z0-9-]+$"
```

### Pattern Validation

When you try to create a worktree with a non-conforming branch name:

```bash
grove add example-app my-branch
```

Output:
```text
Branch name 'my-branch' doesn't match required pattern

Pattern: ^(feature|bugfix|hotfix)/[a-z0-9-]+$
Examples: feature/my-feature, bugfix/fix-login

Suggestion: feature/my-branch

Use --force to bypass this check
```

The `Examples:` line is drawn from `BRANCH_EXAMPLES` (default `feature/my-feature, bugfix/fix-login`). The single `Suggestion:` line is grove's best guess — it slugifies the name and, unless it already starts with a known prefix (`feature/`, `bugfix/`, `hotfix/`, `release/`), prepends `feature/`.

### Bypassing Validation

Use `--force` (or `-f`) when you need to create a branch that doesn't match the pattern. grove still warns, but proceeds:

```bash
grove add -f example-app special-case-branch
```

---

## Dependency Sharing

The `share-deps` command shares `vendor/` and `node_modules/` directories across worktrees with identical lockfiles, saving disk space when working across many worktrees. The local directory is moved into the shared cache (`GROVE_SHARED_DEPS_DIR`, default `~/.grove/shared-deps`) and symlinked back, keyed by a short hash of the worktree's lockfiles (`composer.lock`, `package-lock.json`, `yarn.lock`).

```bash
grove share-deps          # Check current sharing status (default action)
grove share-deps enable   # Enable shared dependencies (from within a worktree)
grove share-deps disable  # Disable and restore local copies
grove share-deps clean    # Remove unused shared caches across all repos
```

`share-deps` **auto-detects** the worktree from the current directory. If you run it with a repo name from outside a worktree, it uses an fzf picker to choose the worktree (and errors if fzf is not installed). The `clean` action is global and needs no worktree context.

Run `composer install` or `npm ci` after enabling to populate the shared cache.

> **PHP/Laravel: `vendor/` is intentionally skipped.** When a worktree contains a `composer.json`, `share-deps enable` does **not** share `vendor/` — Composer's autoloader resolves the project root from `vendor/` using relative paths, which break under a symlink. You'll see `Skipping vendor - sharing breaks PHP autoloader paths`, and only `node_modules` is linked. `node_modules` is unaffected by this.

> **Replacing an existing local directory:** if a shared cache for that lockfile hash already exists and the worktree still has a local directory, `enable` refuses and prints `Use --force to replace local with shared`. Re-run with `-f`/`--force` to delete the local copy and link the shared cache.

---

## Stable Paths for Services

When using Laravel queue workers or schedulers with LaunchAgents, you need a stable path that doesn't change when you create new worktrees. The `{repo}-current` symlink provides this.

The example hook `examples/hooks/post-add.d/09-update-current-link.sh` updates the symlink whenever you create a worktree, and its companion `examples/hooks/post-switch.d/01-update-current-link.sh` updates it on `grove switch`. These are only present if you installed the example hooks (`./install.sh --merge`, or copy them in manually) — see [Installing Example Hooks](#installing-example-hooks). The symlink looks like:

```text
~/Herd/example-app-current -> ~/Herd/example-app-worktrees/feature-login
```

**Example LaunchAgent configuration** (`~/Library/LaunchAgents/com.example-app.queue.plist`):

```xml
<key>ProgramArguments</key>
<array>
  <string>/opt/homebrew/bin/php</string>
  <string>/Users/you/Herd/example-app-current/artisan</string>
  <string>queue:work</string>
</array>
```

Using `example-app-current` instead of a specific worktree path means the queue worker always runs from your most recently created worktree. This is useful during active development when you want queue jobs to use your current feature branch.

**Skip the current link update** for a specific worktree by setting `GROVE_SKIP_CURRENT_LINK=true` in the environment. Hooks inherit grove's environment, so the example hook reads it and skips:

```bash
GROVE_SKIP_CURRENT_LINK=true grove add example-app hotfix/quick-fix
```

---

## Per-Repo Configuration Overrides

Most configuration lives in `~/.groverc` and applies to every repository. For settings that should differ per project, grove reads an optional `.groveconfig` file inside the **bare repo directory** (`~/Herd/<repo>.git/.groveconfig`). It is parsed as key-value pairs against a strict whitelist — never sourced as shell.

Only these four keys may be overridden per-repo:

| Key | Effect |
|-----|--------|
| `DEFAULT_BASE` | Base branch for `grove add` and the rebase target for `grove sync` |
| `GROVE_URL_SUBDOMAIN` | Subdomain prefix for generated `.test` URLs |
| `PROTECTED_BRANCHES` | Space-separated branches that need `-f` to remove |
| `GROVE_STALE_THRESHOLD` | Commits-behind-base before a branch is flagged stale |

Example `~/Herd/example-app.git/.groveconfig`:

```text
DEFAULT_BASE=origin/main
PROTECTED_BRANCHES=main develop
GROVE_STALE_THRESHOLD=20
```

A per-repo override applies only while grove is operating on that repository; the global baseline is restored for the next repo in multi-repo loops. (A `HERD_ROOT/.groveconfig` is also read, applying to all repos under that root.)

---

## Self-Update

Keep grove up-to-date with the built-in upgrade command.

### Checking for Updates

```bash
grove --version --check
```

This fetches from the remote and compares your installed commit against the default branch (`origin/main`, falling back to `origin/master`). It does not modify your installation.

Output:
```text
Checking for updates...

ℹ Installed: v4.1.0
✔ You're running the latest version!
```

Or if an update is available:
```text
Checking for updates...

ℹ Installed: v4.1.0
⚠ Update available: 3 new commit(s)
  Run: grove upgrade
```

### Upgrading

```bash
grove upgrade
```

`grove upgrade` is a guarded self-update over your local clone — it runs `git pull --rebase` on the default branch and rebuilds. There are no downloads or checksum steps. Before pulling it will:

- Refuse to upgrade if the repo is on a feature branch (not `main`/`master`), so your work isn't rebased onto the default branch.
- Refuse to upgrade if the working tree has uncommitted changes (commit or stash them first).

Output:
```text
grove upgrade

ℹ Repository: /Users/you/Projects/grove-cli
ℹ Current version: v4.1.0
ℹ Fetching updates...
ℹ Updates available: 3 new commit(s)

Recent changes:
  • a1b2c3d fix: correct database backup path
  • e4f5g6h feat: add services doctor check
  • i7j8k9l docs: update tutorials

Upgrade now? [y/N] y
ℹ Pulling updates...
ℹ Rebuilding...

✔ Upgraded: v4.1.0 → v4.2.0

Verify with: grove --version
```

### Manual Update

If you cloned the repository, you can update manually. To mirror what `grove upgrade` does, run it on the default branch (`main`, falling back to `master`) with a rebase:

```bash
cd ~/Projects/grove-cli
git checkout main          # grove upgrade refuses to run on a feature branch
git pull --rebase
./build.sh
```

---

## Directory Structure

After setting up, your Herd directory will look like:

```text
~/Herd/
├── example-app.git/                    # Bare repository
├── example-app-worktrees/              # Worktrees for example-app
│   ├── example-app/                    # staging branch (uses repo name)
│   │   ├── .env                  # APP_URL=https://example-app.test
│   │   ├── vendor/
│   │   └── ...
│   └── login/                    # feature/login branch
│       ├── .env                  # APP_URL=https://login.test
│       ├── vendor/
│       └── ...
├── example-app-current -> example-app-worktrees/login  # Symlink to most recent worktree
└── example-api.git/                 # Another project
```

Each worktree:
- Has its own `.env` with unique `APP_URL`
- Has its own `vendor/` and `node_modules/`
- Is served by Herd at its own `.test` domain
- Can run simultaneously with other worktrees

---

## Maintenance & Recovery

These commands keep a repository's worktrees and Herd state healthy. They are power-user tools — most users won't need them day to day.

### `restructure` — migrate to the nested layout

```bash
grove restructure <repo>
```

Migrates a repository's worktrees from the old flat layout (`HERD_ROOT/<repo>--<branch>`) to the current nested layout (`HERD_ROOT/<repo>-worktrees/<site>`). For each worktree it moves the directory, refreshes the Herd SSL site, and rewrites only the `APP_URL=` line in the worktree's `.env` (every other key is preserved). It prompts for confirmation before touching anything; `-f`/`--force` skips the prompt, and a non-interactive run without `--force` fails safe.

### `repair` — fix common worktree issues

```bash
grove repair [repo]            # one repo, or all repos if omitted
grove repair --recovery [repo] # also attempt aggressive recovery
```

Scans for and fixes common problems: prunes orphaned worktree administrative entries, clears stale `index.lock` files, and checks worktree integrity (`.git` pointer files, gitdir references, `HEAD` files). When no repo is given it repairs every repo under `HERD_ROOT`; it does **not** auto-detect from the current directory. Adding `--recovery` enables aggressive recovery, which attempts to rebuild corrupted worktrees (for example a broken `.git/HEAD`).

### `unlock` — remove stale git lock files

```bash
grove unlock [repo]   # one repo, or all repos if omitted
```

Removes stale `index.lock` files left behind when a git operation is interrupted. Run from inside a worktree it auto-detects the repo; given a repo name it unlocks just that repo; with no argument it scans every repo under `HERD_ROOT`.

### `cleanup-herd` — remove orphaned Herd configs

```bash
grove cleanup-herd
```

Finds Herd nginx site configs, SSL certificates and site symlinks that point at worktree directories which no longer exist, and removes them, then restarts Herd's nginx. It prompts for confirmation (skip with `-f`/`--force`) and requires Herd to be installed.

---

## Developer Guide

This section is for developers who want to contribute to grove or understand its internal architecture.

### Architecture

As of v4.1.0, grove uses a modular architecture. The source code is split into focused modules in `lib/`, then concatenated into a single `grove` file for distribution.

```text
lib/
├── 00-header.sh       # Shebang, version, global defaults
├── 01-core.sh         # Config loading, colours, output helpers, error message standards
├── 02-validation.sh   # Input validation, security checks, git ref validation
├── 03-paths.sh        # Path resolution, URL generation
├── 04-git.sh          # Git operations, branch helpers, overflow-safe age calculations
├── 05-database.sh     # MySQL operations with secure password handling
├── 06-hooks.sh        # Hook system with security verification
├── 07-templates.sh    # Template loading
├── 08-spinner.sh      # Progress indicators (spinners)
├── 09-parallel.sh     # Parallel execution framework with race condition prevention
├── 10-interactive.sh  # Interactive wizard (fzf-based)
├── 11-resilience.sh   # Retry logic, function-based transactions, lock cleanup
├── 12-deps.sh         # Dependency sharing (vendor/node_modules)
├── 99-main.sh         # Entry point, usage, flag parsing
└── commands/
    ├── lifecycle.sh      # add (with cleanup trap), rm, move, clone, fresh, restructure
    ├── git-ops.sh        # pull, pull-all, sync, prune, log, diff, summary, changes
    ├── navigation.sh     # code, open, cd, switch, exec
    ├── info.sh           # ls, status, repos, branches, health, report, dashboard
    ├── maintenance.sh    # doctor, cleanup-herd, unlock, repair, upgrade
    ├── bulk-ops.sh       # build-all, exec-all (with dangerous command detection)
    ├── discovery.sh      # info, recent, clean
    ├── config.sh         # config, templates, alias, setup, group (with injection prevention)
    ├── laravel.sh        # migrate, tinker
    └── services.sh       # services: status/start/stop/restart/add/remove/apps/horizon/logs/doctor
```

### Building from Source

The `build.sh` script concatenates all modules into a single executable:

```bash
# Build the grove script (writes ./grove)
./build.sh

# Build to a custom location
./build.sh --output /path/to/output

# A single positional path is also accepted (back-compat)
./build.sh /path/to/output
```

`--output` requires a non-empty path — a bare `--output` (or a whitespace-only value) is a usage error rather than writing to a file literally named `--output`.

The build process:
1. Starts with `00-header.sh` (the only module whose shebang is kept)
2. Concatenates the core modules in `MODULES` order (stripping any leading shebang)
3. Concatenates the command modules in `COMMAND_MODULES` order (from `lib/commands/`)
4. Appends `99-main.sh` (entry point)
5. Makes the output executable

### Development Workflow

```bash
# 1. Edit modules in lib/
vim lib/02-validation.sh

# 2. Build the script
./build.sh

# 3. Test your changes
./grove doctor

# 4. Run the test suite
./run-tests.sh

# 5. Run specific tests
./run-tests.sh unit
./run-tests.sh integration
./run-tests.sh validation.bats
```

### Module Dependencies

Modules are sourced in numeric order. Each module may depend on functions from earlier modules:

| Module | Dependencies |
|--------|--------------|
| `00-header.sh` | None |
| `01-core.sh` | None |
| `02-validation.sh` | core |
| `03-paths.sh` | core, validation |
| `04-git.sh` | core, paths |
| `05-database.sh` | core |
| `06-hooks.sh` | core, validation |
| `07-templates.sh` | core, validation, paths |
| `08-spinner.sh` | core |
| `09-parallel.sh` | core, spinner |
| `10-interactive.sh` | core, paths, templates |
| `11-resilience.sh` | core |
| `12-deps.sh` | core |
| `commands/*.sh` | All above |

### Adding a New Command

1. Determine which command module fits your command (or create a new one)
2. Add your function with the `cmd_` prefix:
   ```zsh
   cmd_mycommand() {
     local repo="${1:-}"
     # ... implementation
   }
   ```
3. Register it in `lib/99-main.sh` in the `main()` function's case statement
4. Add help text in the `usage()` function
5. Add tests in `tests/`
6. Run `./build.sh` and test

### Adding a New Module

1. Create the module file. A **core** module gets a numeric prefix in `lib/` (e.g. `lib/13-newmodule.sh`); a **command** module goes in `lib/commands/`.
2. Add a shebang and module comment:
   ```zsh
   #!/usr/bin/env zsh
   # 13-newmodule.sh - Description of module purpose
   ```
3. Register it in the right array in `build.sh`, **preserving dependency order**: core modules go in `MODULES`, command modules go in `COMMAND_MODULES`.
4. Run `./build.sh` and test

### Test Structure

The test runner (`run-tests.sh`) lives at the repository root, not inside `tests/`.

```text
run-tests.sh                  # Test runner (repo root): lint + unit + integration
tests/
├── unit/                     # Pure-function tests (12 files)
│   ├── core-config.bats      # Config loading / reset between repos
│   ├── database.bats         # Database create/backup/remove helpers
│   ├── db-naming.bats        # Database name generation
│   ├── deps.bats             # Shared dependency management
│   ├── env-rewrite.bats      # .env APP_URL rewrite (move/restructure)
│   ├── json-escape.bats      # JSON escaping
│   ├── resilience.bats       # Lock files / transaction rollback
│   ├── services.bats         # Service management helpers
│   ├── slugify.bats          # Branch slugification
│   ├── template-security.bats # Template variable validation
│   ├── url-generation.bats   # URL/path generation
│   └── validation.bats       # Input validation / security
├── integration/              # Command integration tests (14 files)
│   ├── bulk-ops.bats         # build-all / exec-all
│   ├── commands.bats         # CLI parsing, help, validation
│   ├── completion-sync.bats  # _grove completion stays in sync with commands
│   ├── config-parsing.bats   # Config file parsing
│   ├── config.bats           # config / setup / alias / group
│   ├── discovery.bats        # recent / clean / info
│   ├── git-helpers.bats      # Shared git operations
│   ├── git-ops.bats          # pull / sync / prune / log / diff
│   ├── hooks.bats            # Lifecycle hook execution
│   ├── info.bats             # ls / status / repos / report / health
│   ├── laravel.bats          # migrate / tinker / fresh
│   ├── lifecycle.bats        # add / rm / move / clone
│   ├── maintenance.bats      # doctor / cleanup / unlock / repair
│   └── navigation.bats       # cd / open / code / switch
├── test-helper.bash          # Shared test utilities (bash mirrors of zsh lib functions)
└── fixtures/                 # Sample config fixtures
```

To run tests:

```bash
# Run all tests (shellcheck + unit + integration)
./run-tests.sh

# Run specific test categories
./run-tests.sh unit         # Unit tests only
./run-tests.sh integration  # Integration tests only
./run-tests.sh lint         # Shellcheck static analysis only

# Run a specific test file
./run-tests.sh validation.bats
```

Install BATS if needed:

```bash
# macOS (Homebrew)
brew install bats-core

# npm
npm install -g bats

# Or use the bundled version
git clone https://github.com/bats-core/bats-core.git test_modules/bats
```

### Code Style

- Use zsh syntax (this is not a POSIX shell script)
- Prefer `local` for function-scoped variables
- Use `readonly` for constants
- Quote variables: `"$var"` not `$var`
- Use `[[ ]]` for conditionals (not `[ ]`)
- Use meaningful function and variable names
- Add comments for non-obvious logic
- 2-space indentation
- British English in user-facing text (colour, behaviour, honour)
- Use existing output helpers: `die()`, `info()`, `ok()`, `warn()`, `dim()`

---

## Security

grove is designed with defence-in-depth security.

### Input Validation

- **Path traversal protection** - Repository and branch names are validated to prevent `../` attacks
- **Git flag injection prevention** - Names starting with `-` are rejected to prevent flag injection
- **Reserved reference blocking** - Special git references (`HEAD`, `refs/`) are blocked as branch names
- **Dot-based attack prevention** - Leading dots, trailing dots, and consecutive dots are blocked
- **Git ref validation** - All user-provided git refs (branches, remotes) are validated before use
- **Alias and group validation** - Prevents command injection through alias targets and group files

### Configuration Security

- **Config whitelist** - Only specific configuration variables are loaded from `.groverc` files
- **No code execution** - Config files are parsed as key-value pairs, not sourced as shell scripts
- **Null byte filtering** - Config parser filters null bytes to prevent injection attempts
- **Hook verification** - Hooks must be owned by the current user and not world-writable

### Template Security

- **Template name validation** - Only alphanumeric characters, dashes, and underscores allowed
- **Path traversal prevention** - Template names cannot contain `..`, `/`, or `\`
- **Variable injection protection** - Template variables only accept `true` or `false` values

### Command Execution Security

- **No eval usage** - Command injection vulnerabilities eliminated through function-based approaches
- **Safe parallel execution** - Uses `sh -c` instead of `eval` for better isolation
- **Dangerous command detection** - Warns about potentially destructive commands in `exec-all`
- **Transaction rollback safety** - Uses validated function names instead of arbitrary code strings

### Database Security

- **Password protection** - Uses `MYSQL_PWD` environment variable instead of command-line arguments
- **Prevents password exposure** - Database credentials never visible in `ps aux` output
- **SQL injection prevention** - All database names are validated and escaped

### Resilience and Safety

- **Race condition prevention** - Proper synchronisation in parallel operations
- **Overflow protection** - Age calculations bounded to prevent integer overflow
- **Cleanup traps** - Partial worktree state cleaned up on failure
- **Bounds checking** - Database name truncation validated for minimum length

### Reporting Security Issues

If you discover a security vulnerability, please report it responsibly by opening a private issue or contacting the maintainer directly.

---

## Using grove with Claude Code

Git worktrees and Claude Code are a powerful combination. Each worktree runs as a **completely isolated Claude Code session**, enabling true parallel AI-assisted development.

### Basic Workflow

```bash
# Create worktree
grove add example-app feature/user-avatars

# Navigate to it and start Claude Code
cd "$(grove cd example-app feature/user-avatars)"
claude

# In another terminal, work on a different feature with another Claude session
cd "$(grove cd example-app feature/payments)"
claude
```

### Session Management Across Worktrees

Claude Code recognises sessions across all worktrees in the same repository:

```bash
# Inside Claude, see sessions from ALL worktrees
/resume

# Name sessions for easy switching
/rename user-avatars-feature

# Resume by name from command line
claude --resume user-avatars-feature

# Continue most recent session in this worktree
claude --continue
```

### The `switch` + Claude Pattern

The `grove switch` command pairs perfectly with Claude Code:

```bash
# Switch context completely (opens editor + browser, prints path)
cd "$(grove switch example-app)"
claude    # Start or resume Claude session
```

### CLAUDE.md with Worktrees

| File | Scope | Use case |
|------|-------|----------|
| `./CLAUDE.md` | Shared across all worktrees | Project conventions, committed to repo |
| `./.claude/CLAUDE.local.md` | Per-worktree only | Personal preferences, gitignored |
| `~/.claude/CLAUDE.md` | Global, all projects | Your personal defaults |

Since all worktrees share the same Git history, your project `CLAUDE.md` is automatically available in every worktree.

### Parallel Development Patterns

**Pattern 1: Claude works while you review**

```bash
# Terminal 1: Claude implements a feature
cd "$(grove cd example-app feature/auth)"
claude
# "Implement OAuth2 login with Google..."

# Terminal 2: You review and test another feature
cd "$(grove cd example-app feature/dashboard)"
grove open example-app feature/dashboard  # Test in browser
```

**Pattern 2: Multiple Claude sessions**

```bash
# Terminal 1: Claude on backend
cd "$(grove cd example-app feature/api-endpoints)"
claude --resume api-work

# Terminal 2: Claude on frontend
cd "$(grove cd example-app feature/frontend-components)"
claude --resume frontend-work
```

**Pattern 3: Quick context switch**

```bash
# Working on feature, need to check something on staging
cd "$(grove switch example-app staging)"
claude
# "Show me how the payment flow currently works"

# Switch back to your feature
cd "$(grove switch example-app feature/payments)"
claude --continue
```

### Tips for Claude Code and Worktrees

1. **Name your sessions early** - Use `/rename feature-name` so you can easily resume later
2. **Use descriptive branch names** - They help Claude understand context
3. **One task per worktree** - Keep Claude sessions focused on specific features
4. **Document in CLAUDE.md** - Add your worktree workflow to help Claude understand your setup

### Example CLAUDE.md Addition

Add this to your project's `CLAUDE.md`:

```markdown
## Worktree Development

This project uses Git worktrees for parallel development:
- Each feature gets its own worktree via `grove add`
- Worktrees are at `~/Herd/<repo>-worktrees/<site-name>/`
- Each worktree has its own database: `<repo>__<branch_slug>`
- URLs follow pattern: `https://<site-name>.test`

Common commands:
- `grove ls example-app` - List all worktrees
- `grove switch example-app` - Switch to a worktree (with fzf)
- `grove fresh example-app <branch>` - Reset database and rebuild
```

---

## Repository Structure

This section describes the files in the grove-cli repository itself.

```text
grove-cli/
│
├── grove                          # Built executable (generated by build.sh)
├── _grove                         # Zsh tab completion definitions
├── build.sh                    # Build script - concatenates lib/ into grove
│
├── lib/                        # Source modules (v4.1.0+)
│   ├── 00-header.sh           # Version, global defaults
│   ├── 01-core.sh             # Config, colours, output helpers
│   ├── 02-validation.sh       # Input validation, security
│   ├── 03-paths.sh            # Path resolution, URL generation
│   ├── 04-git.sh              # Git operations, branch helpers
│   ├── 05-database.sh         # MySQL operations
│   ├── 06-hooks.sh            # Hook system with security
│   ├── 07-templates.sh        # Template loading
│   ├── 08-spinner.sh          # Progress indicators
│   ├── 09-parallel.sh         # Parallel execution
│   ├── 10-interactive.sh      # Interactive wizard
│   ├── 11-resilience.sh       # Retry, transactions, locks
│   ├── 12-deps.sh             # Dependency sharing
│   ├── 99-main.sh             # Entry point, usage, flags
│   └── commands/
│       ├── lifecycle.sh       # add, rm, move, clone, fresh, restructure
│       ├── git-ops.sh         # pull, pull-all, sync, prune, changes
│       ├── navigation.sh      # code, open, cd, switch, exec
│       ├── info.sh            # ls, status, repos, branches, health
│       ├── maintenance.sh     # doctor, cleanup-herd, unlock, repair, upgrade
│       ├── bulk-ops.sh        # build-all, exec-all
│       ├── discovery.sh       # info, recent, clean
│       ├── config.sh          # config, templates, alias, setup, group
│       ├── laravel.sh         # migrate, tinker
│       └── services.sh        # services (Supervisor, Horizon, Reverb, scheduler)
│
├── tests/                      # BATS test suite
│   ├── unit/                  # Unit tests
│   ├── integration/           # Integration tests
│   ├── test-helper.bash       # Shared utilities
│   └── run-tests.sh           # Test runner
│
├── install.sh                  # Installer - sets up symlinks, config, hooks
├── uninstall.sh                # Uninstaller - removes symlinks, preserves data
│
├── .groverc.example               # Example configuration file
├── README.md                   # Project documentation
├── CHANGELOG.md                # Version history and release notes
├── CONTRIBUTING.md             # Contribution guidelines
├── LICENSE                     # MIT licence
│
├── docs/
│   ├── guides/
│   │   ├── getting-started.md  # Detailed setup guide
│   │   └── tutorials.md        # Onboarding tutorials and recipes
│   ├── reference/
│   │   └── configuration.md    # Comprehensive configuration docs
│   └── development/
│       ├── roadmap.md           # Feature roadmap
│       ├── implementation-plan.md
│       └── review-findings.md
│
└── examples/
    ├── templates/              # Example worktree templates
    │   ├── laravel.conf
    │   ├── node.conf
    │   ├── minimal.conf
    │   └── backend.conf
    └── hooks/                  # Example lifecycle hooks
        ├── README.md           # Comprehensive hooks documentation
        ├── _lib/               # Shared helpers sourced by example hooks
        ├── pre-add.d/          # Scripts run before worktree creation (gating)
        │   └── 00-laravel-preflight.sh
        ├── post-add.d/         # Scripts run after worktree creation
        │   ├── 00-register-project.sh
        │   ├── 01-copy-env.sh
        │   ├── 01a-inherit-db-from-primary.sh
        │   ├── 02-configure-env.sh
        │   ├── 03-create-database.sh
        │   ├── 04-herd-secure.sh
        │   ├── 04-laravel-scaffold.sh
        │   ├── 05-composer-install.sh
        │   ├── 06-npm-install.sh
        │   ├── 07-build-assets.sh
        │   ├── 08-run-migrations.sh
        │   ├── 09-update-current-link.sh   # Updates {repo}-current symlink
        │   ├── 10-set-hooks-path.sh
        │   ├── _laravel/             # Generic Laravel template (copy into <repo>/)
        │   └── myapp/                # Repo-specific hooks example
        ├── post-switch.d/      # Scripts run after `grove switch`
        │   └── 01-update-current-link.sh   # Updates {repo}-current on switch
        ├── pre-rm.d/
        │   ├── 01-backup-database.sh
        │   └── 02-backup-env.sh
        └── post-rm.d/
            ├── 01-herd-unsecure.sh
            └── 02-drop-database.sh
```

### Key Files

| File | Purpose |
|------|---------|
| `grove` | The built executable (generated by `build.sh`) |
| `lib/` | Source modules - edit these to modify grove |
| `build.sh` | Builds `grove` from modules in `lib/` |
| `_grove` | Zsh completion script for tab completion |
| `install.sh` | Sets up symlinks, creates config and hooks directory |
| `uninstall.sh` | Removes symlinks, preserves user data |
| `.groverc.example` | Template for `~/.groverc` configuration |
| `examples/hooks/` | Example lifecycle hooks you can copy to `~/.grove/hooks/` |
| `examples/templates/` | Example worktree templates |

### User Data Locations

After installation, your personal data lives in these locations:

| Location | Purpose | Backed up? |
|----------|---------|------------|
| `~/.groverc` | Your configuration (HERD_ROOT, editor, database settings) | You should |
| `~/.grove/hooks/` | Your lifecycle hooks (post-add, post-rm, etc.) | You should |
| `~/Herd/*.git/` | Your bare git repositories | Git remote |
| `~/Herd/*/` | Your worktrees (working directories) | Git remote |

### Installing Example Hooks

The installer handles hook installation. For existing installations, re-run it with `--merge`:

```bash
# Add new example hooks without overwriting your existing ones
cd ~/Projects/grove-cli
./install.sh --merge

# Or replace all hooks (backs up existing to ~/.grove/hooks.backup.<timestamp>/)
./install.sh --overwrite
```

You can also copy specific hooks manually:

```bash
# Copy a specific hook
cp ~/Projects/grove-cli/examples/hooks/post-add.d/03-create-database.sh ~/.grove/hooks/post-add.d/

# Create repo-specific hooks (folder name must match your repo name)
mkdir -p ~/.grove/hooks/post-add.d/example-app

# Copy the generic Laravel examples, then tweak as needed
cp ~/Projects/grove-cli/examples/hooks/post-add.d/_laravel/* ~/.grove/hooks/post-add.d/example-app/
```

See [examples/hooks/README.md](../../examples/hooks/README.md) for detailed hook documentation.
