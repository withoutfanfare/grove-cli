# grove - Git Worktree Manager

A command-line tool for managing git worktrees with optional Laravel Herd integration. Work on multiple branches at once without stash gymnastics.

**Framework-agnostic by design.** The core `grove` tool handles git worktree operations only. Framework setup (Laravel, Node.js, etc.) happens in lifecycle hooks that you can use, tweak, or ignore.

## At a glance

- Keep multiple branches open at the same time, each in its own folder
- Create and clean worktrees with one command
- Optional Laravel Herd URLs, database setup, and artisan shortcuts
- Safe by default: health checks, branch protection, mismatch warnings
- Batch commands for pulling, building, and syncing across worktrees

## Installation (recommended)

```bash
# 1) Clone the repo
git clone https://github.com/dannyharding10/grove-cli.git ~/Projects/grove-cli

# 2) Run the installer
cd ~/Projects/grove-cli
./install.sh

# 3) Open a new terminal, then sanity-check
grove --version
grove doctor
```

That's it. If you need options, manual install, or Linux/Windows notes, see [docs/guides/getting-started.md](docs/guides/getting-started.md).

## First-time onboarding (simple version)

1. **Run the setup wizard**
   ```bash
   grove setup
   ```
   This asks a few friendly questions and creates your `~/.groverc` config.

2. **Clone your project as a bare repo**
   A quick heads-up: there are two different “clone” concepts here.

   **Recommended:** let `grove` do it (it creates a *bare repo* and your first worktree)

   ```bash
   grove clone <git-url> <repo-name> [branch]
   # Example:
   grove clone git@github.com:your-org/example-app.git example-app staging
   ```
   Use `main` instead of `staging` if that's your default branch.

   - `<git-url>` is the remote URL (GitHub/GitLab/etc.)
   - `<repo-name>` is the short handle you will type in most `grove` commands (like `grove add example-app ...`)
   - Tip: if your bare repo folder is `example-app.git`, the repo name is `example-app`
   - `grove clone` creates a bare repo at `$HERD_ROOT/<repo-name>.git/` (default `$HERD_ROOT` is `~/Herd`) and a worktree for the branch you asked for

   **Manual option:** if you prefer doing the bare clone yourself

   ```bash
   git clone --bare <repo-url> <target-dir>
   # Example (inside your Herd root, usually `~/Herd`):
   cd ~/Herd
   git clone --bare git@github.com:your-org/example-app.git example-app.git
   ```
   Then create your first worktree:
   ```bash
   grove add example-app staging
   ```

3. **Jump in**
   ```bash
   cd "$(grove switch example-app staging)"
   ```

4. **Daily flow**
   ```bash
   grove add example-app feature/my-branch
   grove switch example-app feature/my-branch
   ```

**Golden rule:** one worktree = one branch. Do not run `git checkout` inside a worktree. Switch worktrees instead.

## Table of Contents

- [Tutorials (Onboarding + Recipes)](docs/guides/tutorials.md)
- [Detailed Setup Guide](docs/guides/getting-started.md)
- [What are Git Worktrees?](#what-are-git-worktrees)
- [The Golden Rule](#️-the-golden-rule-one-branch-per-worktree)
- [Installation](#installation)
- [Configuration](#configuration)
- [Getting Started](#getting-started)
- [Commands Reference](#commands-reference)
- [Dashboard and Monitoring](#dashboard-and-monitoring)
- [Health Score System](#health-score-system)
- [Branch Aliases](#branch-aliases)
- [Multi-Repository Operations](#multi-repository-operations)
- [Repository Groups](#repository-groups)
- [Branch Naming Validation](#branch-naming-validation)
- [Dependency Sharing](#the-share-deps-command)
- [Self-Update](#self-update)
- [Worktree Templates](#worktree-templates)
- [Testing](#testing)
- [Developer Guide](#developer-guide)
- [Security](#security)
- [Common Workflows](#common-workflows)
- [Directory Structure](#directory-structure)
- [Repository Structure](#repository-structure)
- [Troubleshooting](#troubleshooting)
- [Using with Claude Code](#using-grove-with-claude-code)

---

## What are Git Worktrees?

Normally, you have one working directory per repository. If you're working on a feature and need to fix a bug on another branch, you have to stash your changes, switch branches, fix the bug, switch back, and unstash.

**With worktrees**, you can have multiple branches checked out at the same time, each in its own directory:

```bash
~/Herd/
├── example-app.git/                    # Bare repo (stores all git data)
└── example-app-worktrees/              # Worktrees organised by repo
    ├── example-app/                    # Worktree for staging branch (uses repo name)
    ├── login/                    # Worktree for feature/login branch
    └── bugfix-123/               # Worktree for bugfix/123 branch
```

Each worktree is a fully functional working directory with its own `.env`, `vendor/`, `node_modules/`, etc. You can have them all running simultaneously with different URLs in Laravel Herd.

## ⚠️ The Golden Rule: One Branch Per Worktree

**Each worktree is the permanent home for ONE specific branch.** The directory name tells you which branch belongs there.

This is the most important thing to understand about worktrees. If you break this rule, things get confusing fast.

### ❌ DON'T: Switch branches inside a worktree

```bash
# You're in example-app-worktrees/login worktree
cd ~/Herd/example-app-worktrees/login

# DON'T DO THIS:
git checkout staging                    # ❌ Wrong!
git checkout feature/other-thing        # ❌ Wrong!
git switch main                         # ❌ Wrong!
```

**Also avoid switching branches via GUI tools** (GitKraken, SourceTree, VS Code Git panel, etc.) when you have a worktree open. The GUI doesn't know about the worktree naming convention.

**Why this breaks things:**
- The directory `login` now contains the `staging` branch
- The directory name is now misleading
- `grove` commands may behave unexpectedly
- You might accidentally commit to the wrong branch
- `grove status` will show a mismatch warning

### ✅ DO: Use grove commands to work on different branches

```bash
# Want to work on a different branch? Create/switch to its worktree:
cd "$(grove switch example-app)"                # Pick with fzf
cd "$(grove switch example-app staging)"        # Go to staging worktree
cd "$(grove cd example-app feature/payments)"   # Navigate to specific worktree

# Need a worktree for a new branch? Create one:
grove add example-app feature/new-thing

# Done with a branch? Remove its worktree:
grove rm example-app feature/old-thing
```

### ✅ DO: Use git commands that don't change the checked-out branch

These are all safe inside any worktree:

```bash
# Safe git operations (don't change which branch is checked out):
git status                              # ✅ Check status
git add / git commit                    # ✅ Make commits
git push / git pull                     # ✅ Sync with remote
git stash / git stash pop               # ✅ Stash changes
git log / git diff                      # ✅ View history
git rebase origin/staging               # ✅ Rebase (or use: grove sync)
git merge --no-ff feature/x             # ✅ Merge another branch in
git cherry-pick abc123                  # ✅ Cherry-pick commits
git show other-branch:file.php         # ✅ View file from another branch
git diff staging..HEAD                  # ✅ Compare branches
```

### What about the staging worktree?

The staging worktree (`example-app-worktrees/example-app`) should **always** have the `staging` branch checked out. The same rules apply:

```bash
# In the staging worktree, you can:
git pull                                # ✅ Get latest staging
git merge --no-ff feature/done          # ✅ Merge a feature in
git push                                # ✅ Push to remote

# But don't:
git checkout feature/something          # ❌ Don't switch branches here either
```

If you need to look at or work on a feature, switch to that feature's worktree (or create one).

### Quick mental model

Think of each worktree directory as a **dedicated workspace** for one branch:

| Directory | Branch | Purpose |
|-----------|--------|---------|
| `example-app-worktrees/example-app` | `staging` | Integration testing, merges |
| `example-app-worktrees/login` | `feature/login` | Login feature development |
| `example-app-worktrees/bugfix-cart` | `bugfix/cart` | Cart bug fix |

You don't "switch branches" - you **switch worktrees**. Each branch has its own directory, its own editor window, its own browser tab, its own database.

### If you accidentally switched branches

If you've already run `git checkout` inside a worktree, `grove status` and `grove ls` will warn you:

```text
⚠ Branch/Directory Mismatches Detected:
  example-app-worktrees/login
    Current branch:  staging
    Expected dir:    example-app-worktrees/example-app
    Fix: Checkout correct branch or recreate worktree
```

**To fix it:**

```bash
# Option 1: Checkout the correct branch back
cd ~/Herd/example-app-worktrees/login
git checkout feature/login              # Put the right branch back

# Option 2: If you've made commits on the wrong branch,
#           you may need to cherry-pick or reset
```

## Installation

### Platform Support

| Platform | Status |
|----------|--------|
| **macOS** | ✅ Fully supported |
| **Linux** | 🚧 Planned (see [ROADMAP](docs/development/roadmap.md)) |
| **Windows** | 🚧 Planned via WSL (see [ROADMAP](docs/development/roadmap.md)) |

### Dependencies

The installer will check for these dependencies and show installation instructions for any that are missing.

**Required:**

| Dependency | Purpose | Installation |
|------------|---------|--------------|
| `zsh` | Shell interpreter (grove is written in zsh) | Pre-installed on macOS |
| `git` | Version control | `xcode-select --install` (macOS) |

**Optional (for full functionality):**

| Dependency | Purpose | Installation |
|------------|---------|--------------|
| `fzf` | Interactive selection (`grove add -i`, `grove switch`) | `brew install fzf` |
| `jq` | Pretty JSON output (`--pretty` flag) | `brew install jq` |
| `mysql` | Database creation/backup in hooks | `brew install mysql` |

**Framework-specific (for hooks):**

| Dependency | Purpose | Installation |
|------------|---------|--------------|
| `herd` | Laravel Herd HTTPS sites | [Laravel Herd](https://herd.laravel.com) |
| `composer` | PHP dependency management | `brew install composer` |
| `npm` | Node.js package management | Included with Node.js |

### Using the Installer (Recommended)

```bash
# Clone the repository
git clone https://github.com/dannyharding10/grove-cli.git ~/Projects/grove-cli

# Run the installer
cd ~/Projects/grove-cli
./install.sh
```

The installer will:
1. Check requirements (git, zsh, and optional tools)
2. Create symlink at `/usr/local/bin/grove`
3. Install zsh completions to Homebrew's site-functions
4. Create `~/.groverc` config file (if it doesn't exist)
5. Create `~/.grove/hooks/` directory structure for lifecycle hooks
6. Install example hooks (interactive choice for existing installs)

Open a **new terminal** after installation for changes to take effect.

### Installer Options

The installer is **idempotent** - you can run it again to update or install new example hooks.

```bash
# Interactive mode (default) - prompts when hooks already exist
./install.sh

# Merge mode - add new example hooks, keep your existing ones
./install.sh --merge

# Overwrite mode - replace all hooks with examples (backs up existing)
./install.sh --overwrite

# Skip hooks - don't install or modify any hooks
./install.sh --skip-hooks

# Quiet mode - minimal output
./install.sh --quiet

# Show help
./install.sh --help
```

**Hook installation modes:**

| Mode | Behaviour |
|------|-----------|
| Interactive | Fresh install: installs all examples. Existing hooks: prompts for choice |
| `--merge` | Only copies new example hooks, preserves your existing hooks |
| `--overwrite` | Backs up existing hooks to `~/.grove/hooks.backup.<timestamp>/`, then installs all examples |
| `--skip-hooks` | Doesn't touch hooks at all |

### What Gets Installed

| Location | Purpose |
|----------|---------|
| `/usr/local/bin/grove` | Main executable (symlink to repo) |
| `/opt/homebrew/share/zsh/site-functions/_grove` | Tab completions (symlink to repo) |
| `~/.groverc` | Your configuration file |
| `~/.grove/hooks/` | Lifecycle hooks directory |

Because the installed files are symlinks, pulling updates to the repo automatically updates the tool.

### Manual Installation

If you prefer not to use the installer:

```bash
# Clone the repo
git clone https://github.com/dannyharding10/grove-cli.git ~/Projects/grove-cli

# Symlink the script
sudo ln -sf ~/Projects/grove-cli/grove /usr/local/bin/grove

# Symlink completions (Apple Silicon Mac)
ln -sf ~/Projects/grove-cli/_grove /opt/homebrew/share/zsh/site-functions/_grove

# Create config
cp ~/Projects/grove-cli/.groverc.example ~/.groverc

# Create hooks directory
mkdir -p ~/.grove/hooks/post-add.d
```

### Install fzf (Recommended)

fzf enables interactive branch selection with fuzzy search:

```bash
brew install fzf
```

### Uninstalling

```bash
cd ~/Projects/grove-cli
./uninstall.sh
```

This removes symlinks but preserves your config (`~/.groverc`), hooks (`~/.grove/`), repositories, and worktrees.

### First-Time Setup Wizard

For a guided first-time setup, use the setup wizard:

```bash
grove setup
```

The wizard will:
1. Prompt for HERD_ROOT directory (default: `~/Herd`)
2. Configure default base branch (e.g., `origin/staging` or `origin/main`)
3. Set up database connection settings
4. Create `~/.grove/hooks/` and `~/.grove/templates/` directories
5. Write `~/.groverc` configuration file
6. Run `grove doctor` to verify the setup

### Tab Completion

After installation, tab completion works automatically:

```bash
grove pu<Tab>             # completes to 'pull' or 'pull-all'
grove pull ex<Tab>        # completes to 'example-app'
grove pull example-app f<Tab>  # completes to available branches
```

## Configuration

### Config file

Create `~/.groverc` with your preferences:

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
```

You can also create `$HERD_ROOT/.groveconfig` for project-specific settings, or `~/Herd/repo.git/.groveconfig` for repo-specific settings (supports `DEFAULT_BASE`, `GROVE_URL_SUBDOMAIN`, `PROTECTED_BRANCHES`).

For comprehensive configuration documentation, see [docs/reference/configuration.md](docs/reference/configuration.md).

### Environment variables

These can be set in your shell or config file:

| Variable | Default | Description |
|----------|---------|-------------|
| `HERD_ROOT` | `$HOME/Herd` | Directory containing your sites |
| `GROVE_BASE_DEFAULT` | `origin/staging` | Default branch for new worktrees |
| `GROVE_EDITOR` | `cursor` | Editor for `grove code` command |
| `GROVE_CONFIG` | `~/.groverc` | Path to config file |
| `GROVE_DB_HOST` | `127.0.0.1` | MySQL host for database operations |
| `GROVE_DB_USER` | `root` | MySQL user for database operations |
| `GROVE_DB_PASSWORD` | (empty) | MySQL password for database operations |
| `GROVE_DB_CREATE` | `true` | Auto-create database on `grove add` |
| `GROVE_DB_BACKUP` | `true` | Backup database on `grove rm` |
| `GROVE_DB_BACKUP_DIR` | `~/Code/Project Support/Worktree/Database/Backup` | Backup directory |
| `GROVE_PROTECTED_BRANCHES` | `staging main master` | Space-separated list of protected branches |
| `GROVE_HOOKS_DIR` | `~/.grove/hooks` | Directory for hook scripts |
| `GROVE_URL_SUBDOMAIN` | (empty) | Optional subdomain prefix (e.g., `api` → `api.feature.test`) |
| `GROVE_MAX_PARALLEL` | `4` | Maximum concurrent parallel operations |
| `BRANCH_PATTERN` | (empty) | Regex pattern for branch name validation |

### Hooks

Hooks allow you to run custom scripts at various points in the worktree lifecycle. Create executable scripts in `~/.grove/hooks/`:

| Hook | When it runs | Can abort? |
|------|--------------|------------|
| `pre-add` | Before worktree creation | Yes |
| `post-add` | After worktree creation | No |
| `pre-rm` | Before worktree removal | Yes |
| `post-rm` | After worktree removal | No |
| `post-pull` | After `grove pull` succeeds | No |
| `post-sync` | After `grove sync` succeeds | No |
| `post-switch` | After `grove switch` succeeds | No |
| `pre-move` | Before `grove move` | Yes |
| `post-move` | After `grove move` succeeds | No |

**Available environment variables in hooks:**

| Variable | Description |
|----------|-------------|
| `GROVE_REPO` | Repository name |
| `GROVE_BRANCH` | Branch name |
| `GROVE_PATH` | Worktree directory path |
| `GROVE_URL` | Application URL |
| `GROVE_DB_NAME` | Database name |

**Skip variables:** Some hooks can be skipped by setting environment variables before running `grove add`:

| Variable | Effect |
|----------|--------|
| `GROVE_SKIP_HERD=true` | Skip Herd link/secure |
| `GROVE_SKIP_CURRENT_LINK=true` | Skip updating `{repo}-current` symlink |

**Example: post-add hook**

```bash
#!/bin/bash
# ~/.grove/hooks/post-add

echo "Setting up $GROVE_BRANCH..."
cd "$GROVE_PATH"
npm ci
npm run build
php artisan migrate
```

**Example: pre-rm hook (with abort)**

```bash
#!/bin/bash
# ~/.grove/hooks/pre-rm

# Prevent removal if there are uncommitted changes
cd "$GROVE_PATH"
if ! git diff --quiet; then
    echo "ERROR: Uncommitted changes in $GROVE_BRANCH"
    exit 1  # Non-zero exit aborts the removal
fi
```

**Multiple hooks:** Create a `.d` directory (e.g., `~/.grove/hooks/post-add.d/`) with numbered scripts:

```text
~/.grove/hooks/post-add.d/
├── 01-npm-install.sh
├── 02-build-assets.sh
└── 03-run-migrations.sh
```

**Repo-specific hooks:** Create subdirectories matching repo names for hooks that only run for specific repositories:

```text
~/.grove/hooks/post-add.d/
├── 01-npm-install.sh       # Global - runs for ALL repos
├── 02-build-assets.sh      # Global
└── example-app/             # Only runs for the 'example-app' repo
    ├── 01-import-ai.sh
    └── 02-seed-database.sh
```

Execution order: global hooks run first (alphabetically), then repo-specific hooks.

**Security:** Hooks are verified before execution - they must be owned by the current user and not be world-writable.

### Service Management (Optional)

Grove includes optional service management for Laravel apps that use Supervisor, Horizon, Reverb, or scheduled tasks. This is entirely opt-in -- if you don't register any apps, the feature stays invisible.

#### Quick Setup

```bash
# Register an app
grove services add myapp

# With options
grove services add myapp --system-name=myapp-repo --services=horizon:reverb --domain=myapp.test

# Check dependencies
grove services doctor
```

#### Daily Use

```bash
grove services status              # Show all app status
grove services start myapp         # Start services for an app
grove services stop myapp          # Stop services
grove services restart all         # Restart all registered apps
grove services horizon myapp       # Open Horizon dashboard
grove services logs myapp          # Tail Horizon logs
grove services logs myapp reverb   # Tail Reverb logs
```

#### App Registry

Apps are registered in `~/.grove/services/apps.conf`:

```text
# app_name|system_name|services|supervisor_process|domain
myapp|myapp|horizon|myapp-horizon|myapp.test
```

| Field | Description | Default |
|-------|-------------|---------|
| `app_name` | Short name for commands | (required) |
| `system_name` | Directory name in Herd | Same as app_name |
| `services` | `horizon`, `horizon:reverb`, or `none` | `horizon` |
| `supervisor_process` | Supervisor process pattern | `<system_name>-horizon` |
| `domain` | Local .test domain | `<system_name>.test` |

#### Integration with `grove switch`

When you run `grove switch`, the post-switch hook automatically restarts services for the switched app (if registered). No additional configuration needed.

#### Service Types

| Service | What it manages |
|---------|----------------|
| `horizon` | Laravel Horizon queue worker via Supervisor |
| `horizon:reverb` | Horizon + Laravel Reverb WebSocket server |
| `none` | App registered but no queue services |

## Getting Started

### Setting up a new project

1. **Clone as a bare repository:**

   ```bash
   grove clone git@github.com:your-org/example-app.git
   ```

   This creates `~/Herd/example-app.git/` by default (a bare repo that stores all git data).

2. **Create your first worktree:**

   ```bash
   grove add example-app staging
   ```

   This creates `~/Herd/example-app-worktrees/example-app/` with:
   - The staging branch checked out
   - `.env` created from `.env.example`
   - `APP_URL` set to `https://example-app-worktrees/example-app.test`
   - `composer install` run automatically

3. **Open in browser:**

   ```bash
   grove open example-app staging
   # Opens https://example-app-worktrees/example-app.test
   ```

### Working on a feature

```bash
# Create a new worktree for your feature
grove add example-app feature/login

# Open in your editor
grove code example-app feature/login

# Or navigate to it
cd "$(grove cd example-app feature/login)"
```

### Quick access with fzf

If you have fzf installed, omit the branch to get an interactive picker:

```bash
grove code example-app      # Pick from list of worktrees
grove pull example-app      # Pick which one to pull
grove rm example-app        # Pick which one to remove
```

## Quick Reference

```bash
# Example repo name used throughout: `example-app`

# Setup + sanity checks
grove clone git@github.com:your-org/example-app.git example-app
grove setup
grove doctor
grove config
grove repos

# Create / rename / remove worktrees
grove add example-app staging
grove add example-app feature/login
grove add example-app feature/api origin/staging
grove add -i
grove add example-app feature/api --template=backend --dry-run
grove move example-app feature/login login
grove rm example-app feature/login
grove rm --drop-db --delete-branch example-app feature/login

# Navigate (auto-detects repo/branch if you're already inside a worktree)
cd "$(grove cd example-app feature/login)"
grove code example-app feature/login
grove open example-app feature/login
grove switch example-app feature/login
grove exec example-app feature/login php artisan migrate

# Git ops + visibility
grove ls example-app
grove status example-app
grove dashboard
grove dashboard -i
grove info example-app feature/login
grove pull example-app feature/login
grove pull-all example-app
grove pull-all --all-repos
grove sync example-app feature/login
grove diff example-app feature/login
grove summary example-app feature/login
grove log example-app feature/login -n 10
grove changes example-app feature/login
grove branches example-app
grove prune example-app
grove prune --all-repos
grove recent 10
grove health example-app
grove report example-app --output /tmp/grove-report.md

# Parallel commands
grove build-all example-app
grove exec-all example-app npm test

# Laravel shortcuts
grove migrate example-app feature/login
grove tinker example-app feature/login
grove fresh example-app feature/login

# Templates
grove templates
grove templates laravel

# Shortcuts
grove @1

# Utilities + maintenance
grove clean example-app
grove alias add login example-app/feature/login
grove alias rm login
grove group add client-work example-app
grove group show client-work
grove group rm client-work
grove repair example-app
grove repair --recovery example-app
grove restructure example-app
grove cleanup-herd
grove unlock example-app
grove share-deps status
grove share-deps enable
grove share-deps disable

# Version + self-update
grove --version
grove --version --check
grove upgrade
```

## Commands Reference

### Core Commands

| Command | Description |
|---------|-------------|
| `grove add <repo> <branch> [base]` | Create a new worktree |
| `grove add -i` / `--interactive` | Interactive worktree creation wizard |
| `grove add ... --template=<name>` | Create worktree using a template |
| `grove add ... --dry-run` | Preview worktree creation without executing |
| `grove rm <repo> [branch]` | Remove a worktree |
| `grove move <repo> <branch> <new-name>` | Rename/move a worktree with Herd SSL handling |
| `grove ls <repo>` | List all worktrees with status |
| `grove status <repo>` | Dashboard view with age, sync, merged status |
| `grove repos` | List all repositories in HERD_ROOT |
| `grove templates [name]` | List templates or show template details |
| `grove clone <url> [name] [branch]` | Clone as bare repo (create specific worktree) |
| `grove dashboard` | Visual overview of all repositories **(v4.0.0)** |
| `grove info <repo> [branch]` | Detailed worktree information **(v4.0.0)** |
| `grove recent [limit]` | List recently accessed worktrees **(v4.0.0)** |
| `grove clean <repo>` | Remove `node_modules/` and `vendor/` from worktrees inactive 30+ days **(v4.0.0)** |
| `grove alias <subcommand>` | Manage branch aliases **(v4.0.0)** |
| `grove group <subcommand>` | Manage repository groups **(v4.0.0)** |
| `grove setup` | First-time configuration wizard **(v4.0.0)** |
| `grove share-deps [action]` | Share vendor/node_modules across worktrees **(v4.0.0)** |
| `grove upgrade` | Self-update to latest version **(v4.0.0)** |
| `grove --version --check` | Check for available updates |

#### The `repos` command

Lists all bare repositories in your HERD_ROOT directory.

```bash
grove repos
```

Output:
```text
📦 Repositories in /Users/you/Herd

  example-app (3 worktrees)
  example-api (1 worktrees)
```

JSON output:
```bash
grove repos --json
```

#### The `doctor` command

Checks your system configuration and available tools.

```bash
grove doctor
```

Output:
```text
🩺 grove doctor

Configuration
✔ HERD_ROOT: /Users/you/Herd
  DB_BACKUP_DIR does not exist (will be created on first backup)

Required Tools
✔ git: git version 2.43.0
✔ composer: Composer version 2.7.1

Optional Tools
✔ mysql: mysql Ver 8.0.36
✔   MySQL connection: OK
✔ herd: installed
✔ fzf: installed
✔ editor: cursor

Config Files
✔ User config: /Users/you/.groverc
  Project config: /Users/you/Herd/.groveconfig (not found)

✔ All checks passed!
```

### Navigation Commands

| Command | Description |
|---------|-------------|
| `grove cd <repo> [branch]` | Print worktree path (for use with `cd`) |
| `grove code <repo> [branch]` | Open in editor (Cursor/VS Code) |
| `grove open <repo> [branch]` | Open URL in browser |
| `grove switch <repo> [branch]` | cd + code + browser in one command |

#### The `switch` command

Opens a worktree in your editor and browser simultaneously. Prints the path for use with `cd`.

```bash
# With fzf picker
cd "$(grove switch example-app)"

# Explicit branch
cd "$(grove switch example-app feature/login)"
```

This single command:
1. Prints the worktree path (for `cd`)
2. Opens the worktree in your editor
3. Opens the URL in your browser

#### The `add` command in detail

Creates a new worktree for a branch, setting up a complete Laravel development environment.

```bash
# Create from existing remote branch
grove add example-app feature/existing-branch

# Create new branch from staging (default base)
grove add example-app feature/new-work

# Create new branch from a specific base
grove add example-app feature/new-work origin/main
```

**What it does automatically:**

1. Fetches all branches from remote
2. If using `origin/...` as base, explicitly fetches that branch with `--force` to ensure it's up-to-date
3. Creates the worktree directory at `~/Herd/<repo>-worktrees/<site-name>/`
4. **Pushes new branch to remote and sets up tracking** (prevents accidental pushes to wrong branch)
5. Runs `post-add` lifecycle hooks (see below)

**With the example Laravel hooks installed, it also:**

6. Copies `.env.example` to `.env`
7. Sets `APP_URL` and `DB_DATABASE` in `.env`
8. Creates a MySQL database named `<repo>__<branch_slug>`
9. Secures the site with HTTPS via `herd secure`
10. Runs `composer install` and generates app key
11. Runs `npm install` and `npm run build`
12. Runs Laravel migrations

**Database naming:** Branch slashes become underscores, dashes become underscores:
- `example-app` + `feature/login` → `example_app__feature_login`
- `example-app` + `bugfix-123` → `example_app__bugfix_123`

**Output with `--json`:**
```json
{"path": "/Users/you/Herd/example-app-worktrees/login", "url": "https://login.test", "branch": "feature/login", "database": "example_app__feature_login"}
```

#### The `rm` command in detail

Removes a worktree with automatic cleanup of associated resources.

```bash
# Interactive selection (with fzf)
grove rm example-app

# Explicit branch
grove rm example-app feature/done

# Force remove (skip uncommitted changes warning)
grove rm -f example-app feature/done

# Remove worktree AND delete the local branch
grove rm --delete-branch example-app feature/done

# Combine flags
grove rm -f --delete-branch example-app feature/done
```

**What it does automatically:**

1. Runs `pre-rm` lifecycle hooks (can abort removal)
2. Removes the worktree directory
3. Optionally deletes the local branch (with `--delete-branch`)
4. Prunes stale worktree references
5. Runs `post-rm` lifecycle hooks

**With the example Laravel hooks installed, it also:**

- Backs up the database to `$DB_BACKUP_DIR/<repo>/<db_name>_<timestamp>.sql` (skip with `--no-backup`)
- Unsecures the site via `herd unsecure`
- Drops the database (only with `--drop-db` flag)

**Backup location:**
```text
~/Code/Project Support/Worktree/Database/Backup/
└── example-app/
    ├── example_app__feature_login_20241220_143052.sql
    └── example_app__feature_dashboard_20241220_150312.sql
```

**Safety:**

- **Protected branches** (`staging`, `main`, `master`) require `-f` flag to remove
- Warns if there are uncommitted changes (override with `-f`)
- Database backup happens before removal
- `--delete-branch` only deletes the local branch, not remote
- Set `GROVE_DB_BACKUP=false` to disable database backups
- Customise protected branches via `GROVE_PROTECTED_BRANCHES`

#### The `move` command in detail

Renames or moves a worktree to a new directory, automatically handling Laravel Herd SSL certificates.

```bash
# Interactive selection (with fzf)
grove move example-app

# Explicit branch and new name
grove move example-app feature/login example-app-login

# Force move (skip confirmation)
grove move -f example-app feature/login example-app-login
```

**What it does automatically:**

1. Validates the source worktree exists and destination doesn't
2. Detects if the old site has an SSL certificate via Herd
3. Runs `pre-move` lifecycle hooks (can abort)
4. Unsecures the old site if it was secured
5. Cleans up old Herd nginx configs and certificates
6. Moves the worktree using `git worktree move`
7. Re-secures the new site with SSL if the old one was secured
8. Runs `post-move` lifecycle hooks

**Example use case - simplified directory names:**

```bash
# Before: /Users/you/Herd/example-app-worktrees/dashboard
# After:  /Users/you/Herd/example-app-dashboard
grove move example-app feature/dashboard example-app-dashboard
```

**Example use case - promoting to primary:**

```bash
# Before: /Users/you/Herd/example-app-worktrees/develop
# After:  /Users/you/Herd/example-app
grove move example-app develop example-app
```

**Hooks:** Supports `pre-move` and `post-move` hooks in `~/.grove/hooks/`.

### Git Operations

| Command | Description |
|---------|-------------|
| `grove pull <repo> [branch]` | Pull latest changes with rebase |
| `grove pull-all <repo>` | Pull all worktrees for a repo |
| `grove sync <repo> [branch] [base]` | Rebase branch onto base branch |
| `grove diff <repo> [branch] [base]` | Show diff against base branch |
| `grove summary <repo> [branch] [base]` | Summarise changes vs base branch |
| `grove log <repo> [branch]` | Show recent commits (vs base) |
| `grove status <repo>` | Dashboard of all worktrees |

#### The `pull` command

Pulls latest changes for a specific worktree using `git pull --rebase`.

```bash
# Interactive selection (with fzf)
grove pull example-app

# Explicit branch
grove pull example-app feature/login
```

#### The `pull-all` command

Pulls all worktrees for a repository **in parallel** for faster updates. Great for your morning routine.

```bash
grove pull-all example-app
```

Shows success/failure for each worktree:
```text
→ Fetching latest...
→ Pulling 3 worktree(s) in parallel...
✔   feature/login
✔   feature/dashboard
✔   staging

✔ Pulled 3 worktree(s)
```

**Features:**

- **Parallel execution** - All worktrees are pulled simultaneously
- **macOS notification** - Sends a desktop notification when complete (useful for large repos)
- **Error reporting** - Failed pulls are clearly marked with ✖

#### The `status` command

Shows a dashboard view of all worktrees with their state and sync status.

```bash
grove status example-app
```

Output:
```text
📊 Worktree Status: example-app

  BRANCH                         STATE        SYNC       SHA
  ──────────────────────────────────────────────────────────────────────
  staging                        ●            ↑0 ↓0      a1b2c3d
  feature/login                  ◐ 3          ↑5 ↓12     e4f5g6h
  feature/dashboard              ●            ↑2 ↓0      i7j8k9l

⚠ Branch/Directory Mismatches Detected:
  example-app--old-feature-name
    Current branch:  feature/new-name
    Expected dir:    example-app-worktrees/new-name
    Fix: Checkout correct branch or recreate worktree
```

- **State**: `●` = clean, `◐ N` = N uncommitted changes
- **Sync**: `↑N` = commits ahead, `↓N` = commits behind (vs `origin/staging`)
- **Mismatch warning**: Shown when a worktree's directory name doesn't match its branch (e.g., someone ran `git checkout` inside the worktree)

#### The `ls` command

Lists all worktrees with detailed information.

```bash
grove ls example-app
```

Output:
```text
[1] 📁 /Users/you/Herd/example-app-worktrees/example-app
    branch  🌿 staging
    sha     a1b2c3d
    state   ● clean
    sync    ↑0 ↓0
    url     🌐 https://example-app.test
    cd      cd '/Users/you/Herd/example-app-worktrees/example-app'

[2] 📁 /Users/you/Herd/example-app-worktrees/login
    branch  🌿 feature/login
    sha     e4f5g6h
    state   ◐ 3 uncommitted
    sync    ↑5 ↓12
    url     🌐 https://login.test
    cd      cd '/Users/you/Herd/example-app-worktrees/login'

[3] 📁 /Users/you/Herd/example-app-worktrees/old-name
    branch  🌿 feature/renamed-branch
    sha     m1n2o3p
    state   ● clean
    url     🌐 https://example-app-worktrees/old-name.test
    cd      cd '/Users/you/Herd/example-app-worktrees/old-name'
    ⚠ MISMATCH Directory name doesn't match branch!
      Expected: example-app-worktrees/renamed-branch
```

**Mismatch warnings**: If someone runs `git checkout` inside a worktree, the directory name no longer matches the branch. This warning helps catch these issues.

**JSON output:**
```bash
grove ls --json example-app
```
```json
[{"path": "/Users/you/Herd/example-app-worktrees/example-app", "branch": "staging", "sha": "a1b2c3d", "url": "https://example-app.test", "dirty": false, "ahead": 0, "behind": 0, "mismatch": false}]
```

#### The `sync` command in detail

The `sync` command rebases your feature branch onto a base branch, keeping your branch up to date.

**How the base branch is chosen:**

1. If you pass `[base]`, that is used
2. Otherwise, if the worktree has a stored base (`git config --local grove.base`), that is used
3. Otherwise, it falls back to `GROVE_BASE_DEFAULT` / `DEFAULT_BASE` (default: `origin/staging`)

```bash
# Interactive (fzf picker for branch)
grove sync example-app

# Explicit branch, default base (origin/staging)
grove sync example-app feature/login

# Explicit branch and custom base
grove sync example-app feature/login origin/main
```

**Safety measures:**

1. **Fetches first** - Always gets the latest remote state before rebasing
2. **Uncommitted changes check** - Refuses to run if you have uncommitted work:
   ```text
   ✖ ERROR: Worktree has uncommitted changes. Commit or stash them first.
   ```

3. **Standard rebase** - Uses regular `git rebase`, no force or destructive options

**What to expect:**

- **Rebase conflicts** - If your commits conflict with changes in the base branch, Git will pause and ask you to resolve them. After resolving, run `git rebase --continue`.
- **Already pushed?** - If you've already pushed your branch to remote, you'll need to force push after syncing: `git push --force-with-lease`

**Under the hood**, `sync` is equivalent to:
```bash
git fetch --all --prune
git rebase <base>
```

**Tip:** To view or change the stored base for an existing worktree:
```bash
git -C /path/to/worktree config --local --get grove.base
git -C /path/to/worktree config --local grove.base origin/main
```

#### The `summary` command

The `summary` command gives you a compact overview of how a worktree differs from its base branch — useful when switching worktrees for context.

It includes:
- ahead/behind counts
- uncommitted changes summary
- recent commits ahead/behind (last 10)
- diffstat (top files + totals)

```bash
# From inside a worktree (auto-detect)
grove summary

# Explicit
grove summary example-app feature/login

# Explicit base override
grove summary example-app feature/login origin/main

# JSON output
grove summary --json example-app feature/login
```

### Laravel Commands

| Command | Description |
|---------|-------------|
| `grove fresh <repo> [branch]` | Reset database and rebuild frontend |
| `grove migrate <repo> [branch]` | Run database migrations |
| `grove tinker <repo> [branch]` | Open Laravel Tinker REPL |
| `grove log <repo> [branch]` | Show recent git commits |

#### The `fresh` command

Resets your Laravel application to a clean state. Useful when switching to a branch with significant database changes.

```bash
# Interactive selection (with fzf)
grove fresh example-app

# Explicit branch
grove fresh example-app feature/login
```

**What it does:**

1. Runs `php artisan migrate:fresh --seed`
2. Runs `npm ci` (clean install of dependencies)
3. Runs `npm run build`

**Note:** This command drops all tables and recreates them. Use with caution on worktrees with data you want to keep.

#### The `migrate` command

Runs Laravel migrations for a worktree.

```bash
# Interactive selection (with fzf)
grove migrate example-app

# Explicit branch
grove migrate example-app feature/login
```

Equivalent to running `php artisan migrate` in the worktree directory.

#### The `tinker` command

Opens Laravel Tinker, the interactive REPL for your Laravel application.

```bash
# Interactive selection (with fzf)
grove tinker example-app

# Explicit branch
grove tinker example-app feature/login
```

Tinker opens in the worktree's context, so models and services are available.

#### The `log` command

Shows recent commits on a worktree branch (compared to its base).

```bash
# Interactive selection (with fzf)
grove log example-app

# Explicit branch
grove log example-app feature/login
```

If the worktree has a stored base (`grove.base`), `grove log` will use that automatically; otherwise it falls back to `GROVE_BASE_DEFAULT` / `DEFAULT_BASE`.

### Maintenance

| Command | Description |
|---------|-------------|
| `grove clone <url> [name] [branch]` | Clone as bare repo (create specific worktree) |
| `grove prune <repo>` | Clean up stale worktrees and merged branches |
| `grove exec <repo> <branch> <cmd>` | Run command in worktree |
| `grove health <repo>` | Check repository health |
| `grove report <repo> [--output <file>]` | Generate markdown status report |
| `grove repair [repo]` | Fix orphaned worktrees, remove stale locks |
| `grove doctor` | Check system requirements |
| `grove cleanup-herd` | Remove orphaned Herd nginx configs |
| `grove unlock [repo]` | Remove stale git lock files |
| `grove restructure [repo]` | Migrate worktrees to new directory structure |

### Parallel Operations

| Command | Description |
|---------|-------------|
| `grove build-all <repo>` | Run `npm run build` on all worktrees |
| `grove exec-all <repo> <cmd>` | Execute command across all worktrees |
| `grove pull-all <repo>` | Pull all worktrees (parallel) |

#### Parallel concurrency

Configure the maximum number of parallel operations via the `GROVE_MAX_PARALLEL` environment variable (default: 4):

```bash
# In ~/.groverc
GROVE_MAX_PARALLEL=8
```

#### The `clone` command

Clones a repository as a bare repo and creates an initial worktree.

```bash
# Syntax:
#   grove clone <git-url> [repo-name] [branch]
#
# - <git-url>    is the remote repository URL
# - [repo-name]  is the short name you will use in most `grove` commands (e.g. `grove add <repo-name> ...`)
# - [branch]     is the branch to create a worktree for (optional)
#
# Example:
#   grove clone git@github.com:your-org/example-app.git example-app feature/auth
#   ^git url                              ^repo name you will type a lot   ^branch

# Clone with auto-detected name (creates staging/main/master worktree)
grove clone git@github.com:your-org/example-app.git

# Clone with custom name
grove clone git@github.com:your-org/example-app.git example-app

# Clone and create worktree for specific existing branch
grove clone git@github.com:your-org/example-app.git example-app feature/auth

# Clone and create new feature branch (based on staging/main/master)
grove clone git@github.com:your-org/example-app.git example-app feature/new-dashboard
```

**What it does:**

1. Clones as a bare repository to `$HERD_ROOT/<repo>.git/` (default: `~/Herd`)
2. Configures fetch to get all branches
3. Fetches all remote branches
4. Creates the initial worktree:
   - If `[branch]` specified and exists on remote: creates worktree for that branch
   - If `[branch]` specified but doesn't exist: creates new branch from staging/main/master
   - If no branch specified: auto-creates worktree for staging, main, or master (first found)

This means you can clone and start working on a specific feature immediately:

```bash
# Start working on an existing feature
grove clone git@github.com:your-org/example-app.git example-app feature/auth
cd "$(grove cd example-app feature/auth)"

# Or start a new feature
grove clone git@github.com:your-org/example-app.git example-app feature/new-work
```

#### The `exec` command

Runs a command inside a worktree directory.

```bash
# Run artisan commands
grove exec example-app feature/login php artisan migrate
grove exec example-app feature/login php artisan test

# Run npm commands
grove exec example-app feature/login npm run dev

# Run any command
grove exec example-app feature/login git status
```

The command runs in the worktree directory, so relative paths work correctly.

#### The `prune` command in detail

The `prune` command cleans up your repository by removing stale worktree references and optionally deleting merged branches.

```bash
# Show stale worktrees and merged branches (dry run)
grove prune example-app

# Actually delete merged branches
grove prune example-app -f
```

**What it does:**

1. **Prunes stale worktrees** - Removes worktree entries that point to directories that no longer exist
2. **Finds merged branches** - Identifies local branches that have been merged into `origin/staging`
3. **Deletes merged branches** (with `-f`) - Force-deletes branches confirmed as merged

**Note on squash/rebase merges:** The prune command uses force-delete (`git branch -D`) for merged branches. This is necessary because squash-merged or rebase-merged branches have different commit SHAs than what ends up in staging, even though the content is merged.

**Safety:**

- Without `-f`, it only shows what would be deleted
- Never deletes `staging`, `main`, or `master` branches
- Only deletes **local** branches (never touches remote branches)
- Branches checked out in a worktree cannot be deleted until the worktree is removed

#### The `health` command

Performs a comprehensive health check on a repository, identifying potential issues.

```bash
grove health example-app
```

**What it checks:**

1. **Stale worktrees** - Worktree references pointing to directories that no longer exist
2. **Orphaned databases** - MySQL databases matching the repo pattern without corresponding worktrees
3. **Missing .env files** - Worktrees with `.env.example` but no `.env` file
4. **Branch consistency** - Directory names that don't match their checked-out branch

**Example output:**
```text
🏥 Health Check: example-app

Stale Worktrees
✔ No stale worktrees

Database Health
✔ No orphaned databases found

Environment Files
✔ All worktrees have .env files

Branch Consistency
✔ All worktrees match their expected branches

Summary
✔ No issues found - repository is healthy! 🎉
```

#### The `report` command

Generates a markdown status report for all worktrees in a repository.

```bash
# Output to console
grove report example-app

# Save to file
grove report example-app --output ~/Desktop/worktree-report.md
```

**What's included:**

- Summary table with total, clean, and dirty worktree counts
- Per-worktree details: branch, status, ahead/behind counts, last commit
- List of available lifecycle hooks

**Example output:**
```markdown
# Worktree Report: example-app

Generated: 2025-12-24 10:30:00

## Summary

| Metric | Count |
|--------|-------|
| Total worktrees | 5 |
| Clean | 3 |
| With changes | 2 |

## Worktrees

| Branch | Status | Ahead | Behind | Last Commit |
|--------|--------|-------|--------|-------------|
| `staging` | ✅ | 0 | 0 | Merge pull request #123... |
| `feature/auth` | ⚠️ 3 changes | 2 | 0 | Add login validation |

## Hooks Available

- ✅ `pre-add`
- ✅ `post-add`
- ⬜ `pre-rm`
- ⬜ `post-rm`
- ⬜ `post-pull`
- ⬜ `post-sync`
```

#### The `restructure` command

Migrates existing worktrees from the old directory structure (`repo--branch`) to the new hierarchical structure (`repo-worktrees/feature-name`).

```bash
# Migrate all worktrees for a specific repo
grove restructure example-app

# Migrate worktrees for all repositories
grove restructure
```

**What it does:**
1. Moves worktree directories to `~/Herd/<repo>-worktrees/`
2. Renames directories to use simplified site names (e.g., `feature-login`)
3. Updates git worktree references
4. Updates Herd SSL certificates and nginx configs
5. Preserves all data, ignored files, and environment settings

This is a one-time migration command for users upgrading from v3.x to v4.x.

### Flags

| Flag | Description |
|------|-------------|
| `-q, --quiet` | Suppress informational output |
| `-f, --force` | Skip confirmations, force operations |
| `-i, --interactive` | Interactive worktree creation wizard |
| `--dry-run` | Preview worktree creation without executing |
| `--json` | Output in JSON format (supported by `ls`, `status`, `repos`, `summary`, and `add`) |
| `--pretty` | Colourised, formatted JSON output |
| `-t, --template=<name>` | Use a template when creating worktree |
| `--delete-branch` | Delete branch when removing worktree |
| `--drop-db` | Drop database after backup (with `rm`) |
| `--no-backup` | Skip database backup (with `rm`) |
| `--all-repos` | Apply operation to all repositories **(v4.0.0)** |
| `--check` | Check for updates (with `version` command) **(v4.0.0)** |
| `-v, --version` | Show version |
| `-h, --help` | Show help |

**Flag position:** Flags can appear anywhere in the command line:

```bash
grove -f prune example-app        # ✔
grove prune -f example-app        # ✔
grove prune example-app -f        # ✔
```

**Flag usage by command:**

| Command | Useful flags |
|---------|--------------|
| `add` | `-i` (interactive), `--dry-run`, `--json`, `-t`/`--template` |
| `rm` | `-f` (force), `--delete-branch`, `--drop-db`, `--no-backup` |
| `ls` | `--json`, `--pretty` |
| `status` | `--json`, `--pretty` |
| `summary` | `--json`, `--pretty` |
| `prune` | `-f` (actually delete merged branches) |
| `repos` | `--json` |
| `templates` | View template details |
| `pull-all` | `--all-repos` (operate on all repositories) |
| `build-all` | `--all-repos` (operate on all repositories) |
| `exec-all` | `--all-repos` (operate on all repositories) |
| `clean` | `-f` (skip confirmation) |
| `version` | `--check` (check for updates) |
| All | `-q` (quiet mode) |

---

## Dashboard and Monitoring

v4.0.0 introduces powerful monitoring commands to give you a bird's-eye view of all your repositories and worktrees.

### The `dashboard` Command

Get a visual overview of all repositories with health grades, worktree counts, and status indicators.

```bash
grove dashboard

# Interactive mode with quick actions (requires fzf)
grove dashboard -i
```

Output:
```text
╔════════════════════════════════════════════════════════════════════╗
║                    grove Dashboard                                    ║
╚════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────┐
│ example-app                                           3 worktrees    A     │
├──────────────────────────────────────────────────────────────────────┤
│   staging              A    ●                                        │
│   feature/login        B    ◐ 3                                      │
│   feature/dashboard    A    ●                                        │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ example-api                                        1 worktrees    C     │
├──────────────────────────────────────────────────────────────────────┤
│   main                 C    ●  (12 behind)                           │
└──────────────────────────────────────────────────────────────────────┘

Summary: 2 repos, 4 worktrees, 1 dirty, 0 stale
```

**What the dashboard shows:**

| Element | Meaning |
|---------|---------|
| Repository name | The bare repo name (e.g., `example-app`) |
| Worktree count | Number of active worktrees for this repo |
| Average grade | Health grade averaged across all worktrees (A-F) |
| Per-worktree status | Branch name, health grade, dirty state, sync status |

**Health grades are colour-coded:**
- **Green** (A, B) - Healthy worktrees
- **Yellow** (C, D) - Needs attention
- **Red** (F) - Significant issues

### Interactive Dashboard (`-i`)

The interactive dashboard lets you select a worktree and perform quick actions with keyboard shortcuts:

```bash
grove dashboard -i
```

Output:
```text
🌳 Interactive Dashboard
Select a worktree and press a key to perform an action

REPO            │ BRANCH                         │ ⚕ │ Δ │ AGE
────────────────┼────────────────────────────────┼───┼───┼───────
Actions: [p]ull [s]ync [o]pen [c]ode [r]emove [i]nfo [Enter]=cd

> example-app           │ feature/login                  │ B │ ◐ │ 2h
  example-app           │ staging                        │ A │   │ 1d
  example-api        │ main                           │ C │   │ 5d
```

**Quick actions:**

| Key | Action |
|-----|--------|
| `p` | Pull the selected worktree |
| `s` | Sync (rebase onto base branch) |
| `o` | Open in browser |
| `c` | Open in editor |
| `r` | Remove worktree (with confirmation) |
| `i` | Show detailed info |
| `Enter` | Print path for `cd` |

### The `info` Command

Get detailed information about a specific worktree.

```bash
# Show info for a specific worktree
grove info example-app feature/login

# Use fzf picker
grove info example-app
```

Output:
```text
📋 Worktree Info: example-app / feature/login

Path:       /Users/you/Herd/example-app-worktrees/login
URL:        https://feature-login.test
Database:   example_app__feature_login
Branch:     feature/login
SHA:        a1b2c3d4

Health Score: 85/100 (B)
  ├─ Commits behind base: -10 (5 commits behind origin/staging)
  ├─ Uncommitted changes: -5 (3 files modified)
  ├─ Days since commit:   0 (committed today)
  ├─ Merge status:        0 (no conflicts)
  └─ Untracked files:     0 (none)

Sync Status:
  ├─ Ahead:  2 commits
  └─ Behind: 5 commits (vs origin/staging)

Last Commit: Fix login validation (2 hours ago)
```

### The `recent` Command

List recently accessed worktrees sorted by last access time.

```bash
# Show 5 most recent (default)
grove recent

# Show 10 most recent
grove recent 10
```

Output:
```text
📅 Recently Accessed Worktrees

  1. example-app / feature/login         2 hours ago
  2. example-app / staging               5 hours ago
  3. example-api / main               1 day ago
  4. example-app / feature/dashboard     2 days ago
  5. example-app / bugfix/cart           5 days ago
```

**Tip:** Use `grove recent` at the start of your day to quickly see what you were working on.

### The `clean` Command

Free up disk space by removing `node_modules/` and `vendor/` from inactive worktrees.

```bash
# Clean worktrees with no commits in 30+ days
grove clean example-app

# Force clean without confirmation
grove clean -f example-app
```

Output:
```text
🧹 Cleaning inactive worktrees: example-app

Scanning for worktrees inactive >30 days...

  feature/old-work (45 days inactive)
    ├─ node_modules: 312 MB
    └─ vendor: 89 MB
    Total: 401 MB

  bugfix/ancient (62 days inactive)
    ├─ node_modules: 298 MB
    └─ vendor: 87 MB
    Total: 385 MB

Total space to free: 786 MB

Clean these directories? [y/N]: y

✔ Cleaned feature/old-work (401 MB freed)
✔ Cleaned bugfix/ancient (385 MB freed)

✔ Cleaned 2 worktrees, freed 786 MB
```

**Notes:**
- Only affects worktrees not accessed in the last 30 days
- Worktrees remain functional - just run `composer install` / `npm install` when you return to them
- Use `-f` flag to skip confirmation

### The `share-deps` Command

Share `vendor/` and `node_modules/` directories across worktrees with identical lockfiles. This can save significant disk space when working on many worktrees.

```bash
# Check current sharing status
grove share-deps

# Enable shared dependencies (from within a worktree)
grove share-deps enable

# Disable and restore local copies
grove share-deps disable

# Clean up unused shared caches
grove share-deps clean
```

**How it works:**

1. Dependencies are moved to `~/.grove/shared-deps/` and symlinked back
2. Cache is keyed by MD5 hash of lockfiles (composer.lock, package-lock.json, yarn.lock)
3. If lockfiles change, a new cache is created automatically
4. Multiple worktrees with identical dependencies share a single copy

**Example output:**
```text
Dependency Status

  ● vendor: shared (a1b2c3d4e5f6)
  ● node_modules: shared (f6e5d4c3b2a1)
```

**Notes:**
- Run `composer install` / `npm ci` after enabling to populate the shared cache
- Use `grove share-deps clean` periodically to remove unused caches
- Shared deps are stored in `~/.grove/shared-deps/`

---

## Health Score System

Every worktree receives a health score from 0-100, displayed as a letter grade (A-F). This helps you quickly identify worktrees that need attention.

### How Scores are Calculated

The health score starts at 100 and deducts points based on various factors:

| Factor | Max Deduction | Calculation |
|--------|---------------|-------------|
| **Commits behind base** | -30 points | -2 points per commit behind `origin/staging` |
| **Uncommitted changes** | -20 points | -5 points per uncommitted file (max 4) |
| **Days since last commit** | -25 points | -1 point per day (max 25) |
| **Merge conflicts** | -10 points | -10 if unmerged/conflicted state |
| **Untracked files** | -5 points | -1 point per untracked file (max 5) |

### Grade Scale

| Grade | Score Range | Meaning |
|-------|-------------|---------|
| **A** | 90-100 | Excellent - worktree is up-to-date and clean |
| **B** | 80-89 | Good - minor issues, generally healthy |
| **C** | 70-79 | Fair - needs some attention |
| **D** | 60-69 | Poor - significant issues to address |
| **F** | 0-59 | Failing - urgent attention needed |

### Where Health Scores Appear

Health scores are shown in:
- `grove dashboard` - Per-worktree and per-repository average
- `grove health <repo>` - Detailed breakdown for all worktrees
- `grove info <repo> [branch]` - Full score breakdown
- `grove status <repo>` - Quick grade indicator

### The `health` Command

Get detailed health information for all worktrees in a repository.

```bash
grove health example-app
```

Output:
```text
🏥 Health Check: example-app

  BRANCH                    GRADE   SCORE   ISSUES
  ─────────────────────────────────────────────────────────
  staging                   A       100     -
  feature/login             B       85      5 behind, 3 uncommitted
  feature/old-work          D       62      25 days old, 15 behind
  bugfix/stale              F       45      45 days old, 32 behind, conflicts

Summary:
  Total worktrees: 4
  Healthy (A/B):   2
  Needs attention: 2

Recommendations:
  • Sync feature/old-work with staging
  • Resolve merge conflicts in bugfix/stale
  • Consider removing bugfix/stale if no longer needed
```

### Improving Health Scores

| Issue | Solution |
|-------|----------|
| Commits behind | Run `grove sync <repo> <branch>` to rebase onto your base branch (default: `origin/staging`) |
| Uncommitted changes | Commit or stash your work |
| Old commits | Make regular commits as you work |
| Merge conflicts | Resolve conflicts and complete the merge |
| Untracked files | Add to `.gitignore` or delete if not needed |

---

## Branch Aliases

Create shortcuts for frequently accessed worktrees. Aliases save you from typing long repository and branch names.

### Creating an Alias

Aliases point to a single `repo/branch` target.

```bash
grove alias add <name> <repo/branch>

# Examples
grove alias add login example-app/feature/user-authentication
grove alias add staging example-app/staging
```

### Using an Alias

Aliases work with navigation commands:

```bash
# These are equivalent
grove code login
grove code example-app feature/user-authentication

# Switch to aliased worktree
cd "$(grove switch login)"

# Open in browser
grove open api
```

### Managing Aliases

```bash
# List all aliases
grove alias
```

Output:
```text
📝 Branch Aliases

  login    → example-app/feature/user-authentication
  staging  → example-app/staging
```

```bash
# Remove an alias
grove alias rm login
```

### Alias Storage

Aliases are stored in `~/.grove/aliases` as simple key-value pairs:

```text
login=example-app/feature/user-authentication
staging=example-app/staging
```

---

## Multi-Repository Operations

The `--all-repos` flag lets you run operations across all repositories at once.

### Supported Commands

| Command | With `--all-repos` |
|---------|-------------------|
| `grove pull-all` | Pull all worktrees in all repos |
| `grove build-all` | Build all worktrees in all repos |
| `grove exec-all` | Run command in all repos |

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
```

```bash
# Run a command in all repos
grove exec-all --all-repos "php artisan cache:clear"
```

### Parallel Execution

Multi-repo operations run in parallel for efficiency. Configure concurrency:

```bash
# In ~/.groverc
GROVE_MAX_PARALLEL=8  # Default: 4
```

---

## Repository Groups

Create named groups of repositories for batch operations.

### Creating a Group

```bash
grove group add frontend example-app example-api
```

### Using Groups

Groups can be used with multi-repo commands using the `@` prefix:

```bash
# Pull all worktrees in all repos in the 'frontend' group
grove pull-all @frontend

# Build all worktrees in the 'backend' group
grove build-all @backend

# Execute command across a group
grove exec-all @frontend "npm run lint"
```

### Managing Groups

```bash
# List all groups
grove group

# Show repos in a group
grove group show frontend

# Delete an entire group
grove group rm frontend
```

To change which repos are in a group, just run `grove group add ...` again with the new list.

### Group Storage

Groups are stored in `~/.grove/groups` as simple key-value pairs:

```text
frontend=example-app example-api
```

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
✖ Branch name 'my-branch' does not match required pattern

Pattern: ^(feature|bugfix|hotfix)/[a-z0-9-]+$

Suggestions:
  • feature/my-branch
  • bugfix/my-branch
  • hotfix/my-branch

Use -f to bypass this check.
```

### Bypassing Validation

Use `-f` when you need to create a branch that doesn't match the pattern:

```bash
grove add -f example-app special-case-branch
```

---

## Self-Update

Keep grove up-to-date with the built-in upgrade command.

### Checking for Updates

```bash
grove --version --check
```

Output:
```text
grove version 4.1.0

Checking for updates...

✔ You are running the latest version
```

Or if an update is available:
```text
grove version 4.1.0

Checking for updates...

⚠ Update available

Run 'grove upgrade' to update.

Release notes: https://github.com/dannyharding10/grove-cli/releases
```

### Upgrading

```bash
grove upgrade
```

Output:
```text
→ Checking for updates...

⚠ Update available

Upgrade now? [Y/n]: y

→ Downloading...
→ Verifying checksum...
→ Installing...
→ Rebuilding from source...

✔ Upgrade complete

Restart your terminal for changes to take effect.
```

### Manual Update

If you cloned the repository, you can also update manually:

```bash
cd ~/Projects/grove-cli
git pull
./build.sh
```

---

## Worktree Templates

Templates let you predefine which setup hooks run when creating worktrees. This is useful when you have different project types or want quick minimal checkouts.

### Listing Templates

```bash
grove templates
```

Output:
```text
📋 Available Templates

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
📋 Template: minimal

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

### Included Example Templates

The installer includes these templates in `examples/templates/`:

| Template | Description |
|----------|-------------|
| `laravel.conf` | Full Laravel setup - database, composer, npm, build, migrations |
| `node.conf` | Node.js projects - npm only, skips PHP and database |
| `minimal.conf` | Git worktree only - skips all setup hooks |
| `backend.conf` | Backend API work - PHP and database, no frontend build |

To install example templates:
```bash
cp examples/templates/*.conf ~/.grove/templates/
```

---

## Testing

The project includes a comprehensive test suite using [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

### Running Tests

```bash
# Run all tests
./run-tests.sh

# Run only unit tests
./run-tests.sh unit

# Run only integration tests
./run-tests.sh integration

# Run a specific test file
./run-tests.sh validation.bats
```

### Test Coverage

The test suite includes **204 tests** covering:

- **Input validation** - Security-critical path traversal, git flag injection, reserved references, dot-based attacks
- **Branch slugification** - Converting branch names to filesystem-safe slugs
- **Database naming** - MySQL 64-character limits, hash suffix for long names, bounds checking
- **URL generation** - Worktree paths and URLs with subdomain support
- **JSON escaping** - Proper escaping for JSON output (including control characters)
- **Config parsing** - Security whitelist enforcement, injection prevention, null byte filtering
- **Template security** - Path traversal prevention, variable injection protection
- **Git ref validation** - Command injection prevention via git refs
- **Age calculations** - Overflow protection for extremely old commits

### Installing BATS

```bash
# macOS (Homebrew)
brew install bats-core

# npm
npm install -g bats

# Or use the bundled version
git clone https://github.com/bats-core/bats-core.git test_modules/bats
```

---

## Developer Guide

This section is for developers who want to contribute to `grove` or understand its internal architecture.

### Modular Architecture

As of v4.0.0, `grove` uses a modular architecture. The source code is split into focused modules in `lib/`, then concatenated into a single `grove` file for distribution.

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
    ├── lifecycle.sh      # add (with cleanup trap), rm, clone, fresh
    ├── git-ops.sh        # pull, pull-all, sync, prune, log, diff, summary
    ├── navigation.sh     # code, open, cd, switch, exec
    ├── info.sh           # ls, status, repos, health, report, dashboard
    ├── maintenance.sh    # doctor, cleanup-herd, unlock, repair, upgrade
    ├── bulk-ops.sh       # build-all, exec-all (with dangerous command detection)
    ├── discovery.sh      # info, recent, clean
    ├── config.sh         # templates, alias, setup, group (with injection prevention)
    └── laravel.sh        # migrate, tinker
```

### Building from Source

The `build.sh` script concatenates all modules into a single executable:

```bash
# Build the grove script
./build.sh

# Build to a custom location
./build.sh --output /path/to/output
```

The build process:
1. Starts with `00-header.sh` (includes shebang)
2. Concatenates modules in order (stripping shebangs)
3. Adds command modules from `lib/commands/`
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

1. Create the module file with appropriate number prefix (e.g., `lib/12-newmodule.sh`)
2. Add a shebang and module comment:
   ```zsh
   #!/usr/bin/env zsh
   # 12-newmodule.sh - Description of module purpose
   ```
3. Add the module to the `MODULES` array in `build.sh`
4. Run `./build.sh` and test

### Test Structure

```text
tests/
├── unit/
│   ├── validation.bats      # Input validation tests
│   ├── slugify.bats         # Branch slugification
│   ├── db-naming.bats       # Database name generation
│   ├── url-generation.bats  # URL/path generation
│   ├── json-escape.bats     # JSON escaping
│   ├── config-parsing.bats  # Config file parsing
│   └── template-security.bats
├── integration/
│   └── commands.bats        # CLI parsing, help, validation
├── test-helper.bash         # Shared test utilities
└── run-tests.sh             # Test runner
```

### Code Style

- Use zsh syntax (this is not a POSIX shell script)
- Prefer `local` for function-scoped variables
- Use `readonly` for constants
- Quote variables: `"$var"` not `$var`
- Use `[[ ]]` for conditionals (not `[ ]`)
- Use meaningful function and variable names
- Add comments for non-obvious logic

---

## Security

`grove` is designed with defense-in-depth security:

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

### Resilience & Safety
- **Race condition prevention** - Proper synchronization in parallel operations
- **Overflow protection** - Age calculations bounded to prevent integer overflow
- **Cleanup traps** - Partial worktree state cleaned up on failure
- **Bounds checking** - Database name truncation validated for minimum length

### Reporting Security Issues

If you discover a security vulnerability, please report it responsibly by opening a private issue or contacting the maintainer directly.

---

## Common Workflows

### Starting work on a new feature

```bash
# Create worktree from staging
grove add example-app feature/new-dashboard

# Open in editor
grove code example-app feature/new-dashboard

# Open in browser
grove open example-app feature/new-dashboard
```

### Reviewing a PR

```bash
# Create worktree for the PR branch
grove add example-app feature/someone-elses-work

# Check it out, run tests, etc.
grove exec example-app feature/someone-elses-work php artisan test

# Clean up when done
grove rm example-app feature/someone-elses-work
```

### Keeping branches up to date

```bash
# Pull all worktrees at once
grove pull-all example-app

# Or sync a specific branch with staging
grove sync example-app feature/login origin/staging
```

### Morning routine

```bash
# See status of all worktrees
grove status example-app

# Update everything
grove pull-all example-app
```

### Cleaning up after merging

```bash
# Remove worktree and delete the branch
grove rm --delete-branch example-app feature/completed-work

# Or just prune stale worktrees
grove prune example-app
```

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

## Tips

### Use aliases for common repos

Add to `~/.zshrc`:

```bash
alias gs="grove status example-app"
alias gl="grove ls example-app"
alias gc="grove code example-app"
```

### Quick navigation function

Add to `~/.zshrc`:

```bash
# Usage: gcd example-app feature/login
gcd() {
  cd "$(grove cd "$@")"
}
```

### Database per worktree

Each worktree can have its own database. In your `.env.example`:

```text
DB_DATABASE=example_app
# (If you use the example hooks, `grove add` will set a per-worktree DB name like:
#  example_app__feature_login)
```

Or manually set different databases in each worktree's `.env`.

### Running commands across worktrees

```bash
# Run migrations on all worktrees
for branch in staging feature/login feature/dashboard; do
  grove exec example-app "$branch" php artisan migrate
done
```

### Stable path for queue workers and schedulers

When using Laravel queue workers or schedulers with LaunchAgents, you need a stable path that doesn't change when you create new worktrees. The `{repo}-current` symlink provides this.

The `09-update-current-link.sh` hook (installed in `~/.grove/hooks/post-add.d/`) automatically updates the symlink whenever you create a new worktree:

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

**Skip the current link update** for a specific worktree by setting:

```bash
GROVE_SKIP_CURRENT_LINK=true grove add example-app hotfix/quick-fix
```

## Repository Structure

This section describes the files in the grove-cli repository itself.

```text
grove-cli/
│
├── grove                          # Built executable (generated by build.sh)
├── _grove                         # Zsh tab completion definitions
├── build.sh                    # Build script - concatenates lib/ into grove
│
├── lib/                        # Source modules (v4.0.0+)
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
│       ├── lifecycle.sh       # add, rm, clone, fresh
│       ├── git-ops.sh         # pull, pull-all, sync, prune
│       ├── navigation.sh      # code, open, cd, switch, exec
│       ├── info.sh            # ls, status, repos, health
│       ├── utility.sh         # doctor, cleanup, repair
│       └── laravel.sh         # migrate, tinker
│
├── tests/                      # BATS test suite (187 tests)
│   ├── unit/                  # Unit tests
│   ├── integration/           # Integration tests
│   ├── test-helper.bash       # Shared utilities
│   └── run-tests.sh           # Test runner
│
├── install.sh                  # Installer - sets up symlinks, config, hooks
├── uninstall.sh                # Uninstaller - removes symlinks, preserves data
│
├── .groverc.example               # Example configuration file
├── README.md                   # This documentation
├── CHANGELOG.md                # Version history and release notes
├── CONTRIBUTING.md             # Contribution guidelines
├── LICENSE                     # MIT license
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
        ├── post-add.d/         # Scripts run after worktree creation
        │   ├── 00-register-project.sh
        │   ├── 01-copy-env.sh
        │   ├── 02-configure-env.sh
        │   ├── 03-create-database.sh
        │   ├── 04-herd-secure.sh
        │   ├── 05-composer-install.sh
        │   ├── 06-npm-install.sh
        │   ├── 07-build-assets.sh
        │   ├── 08-run-migrations.sh
        │   └── example-app/          # Repo-specific hooks example
        │       ├── 01-symlink-env.sh
        │       ├── 02-import-database.sh
        │       └── 03-seed-data.sh
        ├── pre-rm.d/
        │   └── 01-backup-database.sh
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

See [examples/hooks/README.md](examples/hooks/README.md) for detailed hook documentation.

## Troubleshooting

### "Bare repo not found"

You need to clone the repo first:

```bash
grove clone git@github.com:org/repo.git
```

### "Worktree already exists"

The worktree directory already exists. Either:
- Use the existing worktree: `grove cd example-app branch-name`
- Remove it first: `grove rm example-app branch-name`

### Git commands fail with "command not found"

The script uses absolute paths (`/usr/bin/git`, `/usr/bin/ssh`). If your git is installed elsewhere, check:

```bash
which git
which ssh
```

### Branch not found

Fetch the latest branches first:

```bash
git --git-dir="$HOME/Herd/example-app.git" fetch --all
```

### Worktree has uncommitted changes

Before removing or syncing, commit or stash your changes:

```bash
cd "$(grove cd example-app feature/work)"
git stash
# or
git add -A && git commit -m "WIP"
```

### Prune doesn't delete merged branches

Make sure to use the `-f` flag:

```bash
grove prune -f example-app
```

Without `-f`, prune only shows what would be deleted.

### Rebase conflicts during sync

If `grove sync` encounters conflicts:

1. Navigate to the worktree:
   ```bash
   cd "$(grove cd example-app feature/branch)"
   ```

2. Resolve conflicts in your editor

3. Stage resolved files:
   ```bash
   git add <resolved-files>
   ```

4. Continue the rebase:
   ```bash
   git rebase --continue
   ```

5. Or abort if needed:
   ```bash
   git rebase --abort
   ```

### Can't delete branch (checked out in worktree)

A branch can't be deleted while it's checked out. Remove the worktree first:

```bash
grove rm example-app feature/branch
grove prune -f example-app
```

### SSH authentication issues

If git operations fail with SSH errors, ensure your SSH agent is running:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

### Can't remove staging/main/master worktree

Protected branches require the force flag:

```bash
grove rm -f example-app staging
```

To change protected branches, set in `~/.groverc`:

```bash
PROTECTED_BRANCHES="main production"  # Your custom list
```

### fzf picker not working

Install fzf:

```bash
brew install fzf
```

If installed but not working, check it's in your PATH:

```bash
which fzf
```

### Database not created

If the database isn't being created automatically:

1. Check MySQL is running:
   ```bash
   mysql -u root -e "SELECT 1"
   ```

2. If you have a password, set it in `~/.groverc`:
   ```bash
   DB_PASSWORD=your_password
   ```

3. Or disable auto-creation and create manually:
   ```bash
   # In ~/.groverc
   DB_CREATE=false
   ```
   ```bash
   # Create manually
   mysql -u root -e "CREATE DATABASE example_app__feature_login"
   ```

### Database name too long

MySQL database names are limited to 64 characters. If your repo + branch name exceeds this, you may need to use shorter branch names or manually set `DB_DATABASE` in the `.env` file.

## Version

Current version: **4.1.0**

Check with: `grove --version`

### What's New in 4.0.0

**Major architecture overhaul:**
- **Modular architecture** - The 3,162-line monolithic script has been refactored into 18 focused modules in `lib/` for better maintainability
- **Build system** - `build.sh` concatenates modules into a single `grove` file for distribution
- **187 tests** - Expanded test suite covering all new functionality

**Interactive mode:**
- **`grove add --interactive` / `-i`** - Guided worktree creation wizard with 5 steps:
  1. Repository selection (fzf picker)
  2. Base branch selection (fzf picker)
  3. Branch name input with live preview (path, URL, database)
  4. Template selection (optional fzf picker)
  5. Confirmation with full summary

**Progress indicators:**
- **Spinner animation** - Braille-pattern spinner for long operations
- Spinners available for hooks to use in `composer install`, `npm ci`, etc.

**Parallel operations:**
- **`grove build-all <repo>`** - Run `npm run build` on all worktrees
- **`grove exec-all <repo> <cmd>`** - Execute any command across all worktrees
- Configurable concurrency via `GROVE_MAX_PARALLEL` (default: 4)

**Resilience improvements:**
- **`grove repair [repo]`** - Scan for and fix common issues (orphaned worktrees, stale locks)
- **Retry logic** - Exponential backoff for transient failures
- **Lock cleanup** - Automatic detection and removal of stale index locks
- **Disk space checks** - Pre-flight checks before operations

**Developer experience:**
- **`--dry-run` flag** - Preview worktree creation without executing
- **`--pretty` flag** - Colourised JSON output
- **"Did you mean?" suggestions** - Helpful suggestions for mistyped template names

### What's New in 3.7.0

**Generic worktree manager:**
- `grove` is now framework-agnostic - all Laravel-specific functionality has been moved to optional hooks
- Core tool handles only git worktree operations (create, remove, sync, pull, status)
- Install example hooks for Laravel projects, or create custom hooks for any framework

**Hook-based architecture:**
- Comprehensive example hooks for Laravel: env setup, database creation, Herd securing, composer/npm install, migrations
- Repo-specific hooks via subdirectories (e.g., `post-add.d/example-app/` runs only for `example-app` repo)
- Hook control flags: `GROVE_SKIP_DB`, `GROVE_SKIP_COMPOSER`, `GROVE_SKIP_NPM`, etc.
- Per-repository config files: `~/Herd/repo.git/.groveconfig`

**Bug fixes:**
- Fixed hooks not running (zsh glob qualifier order)
- Fixed URL generation to include repository name
- Fixed per-repo config loading for `DEFAULT_BASE`

**Installer improvements:**
- `--merge` mode: Add new hooks without overwriting existing ones
- `--overwrite` mode: Replace all hooks (backs up first)
- `--skip-hooks` mode: Skip hook installation entirely

### What's New in 3.6.0

**New commands:**
- **`grove health <repo>`** - Check repository health (stale worktrees, orphaned databases, missing .env files, branch mismatches)
- **`grove report <repo>`** - Generate markdown status report with worktree summary, status, and hook availability
- **`grove clone` branch argument** - Clone and immediately create worktree for a specific branch: `grove clone <url> [name] [branch]`

**New lifecycle hooks:**
- **`pre-add`** - Runs before worktree creation (can abort with non-zero exit)
- **`pre-rm`** - Runs before worktree removal (can abort with non-zero exit)
- **`post-pull`** - Runs after `grove pull` succeeds
- **`post-sync`** - Runs after `grove sync` succeeds

**Security hardening:**
- **Config file security** - Configuration files are now parsed as key-value pairs instead of sourced, preventing arbitrary code execution via malicious `.groverc` files
- **Hook execution security** - Hooks are verified to be owned by the current user and not world-writable before execution
- **Input validation** - Added protection against absolute paths, git flag injection, reserved git references, and malformed paths

**Other improvements:**
- **Database name limits** - Names exceeding MySQL's 64-character limit are automatically truncated with a hash suffix
- **Fresh command safety** - `grove fresh` now requires confirmation before running `migrate:fresh` (use `-f` to skip)
- **Remote branch fetching** - `origin/...` base branches are now explicitly fetched to ensure the latest version is used

### What's New in 3.5.0

- **Improved remote branch fetching** - When using `origin/...` as a base branch, `grove add` now explicitly fetches the latest version with `--force`. This ensures branches with slashes (e.g., `origin/proj-jl/rethink`) are always up-to-date, even if they weren't properly tracked locally.

### What's New in 3.3.0

- **Branch/directory mismatch detection** - `grove ls` and `grove status` now warn when a worktree's directory name doesn't match its checked-out branch (e.g., if someone ran `git checkout` inside a worktree)
- **Automatic remote tracking setup** - New branches are automatically pushed and set to track their own remote branch (prevents accidental pushes to wrong branch)
- **JSON output includes mismatch field** - `grove ls --json` now includes `"mismatch": true/false`

### What's New in 3.0.0

- **New commands**: `repos`, `doctor`, `fresh`, `switch`, `migrate`, `tinker`, `log`
- **Parallel pull-all**: Pulls all worktrees concurrently for faster updates
- **macOS notifications**: Get notified when long operations complete
- **Auto-create staging**: Clone now automatically creates a staging worktree
- **Branch protection**: Protected branches (staging, main, master) require `-f` to remove
- **Database cleanup**: `--drop-db` flag to drop database after backup
- **Skip backup**: `--no-backup` flag to skip database backup on removal

## Common Workday Scenarios

### Starting your day

```bash
# Check what you were working on
grove status example-app

# Pull all worktrees to get overnight changes
grove pull-all example-app

# Jump straight into your current feature
cd "$(grove switch example-app)"
```

### Starting a new feature

```bash
# Create worktree (auto-creates branch from staging, sets up DB, secures site)
grove add example-app feature/user-avatars

# Opens editor + browser, prints path for cd
cd "$(grove switch example-app feature/user-avatars)"

# Run migrations for the new database
grove migrate example-app feature/user-avatars
```

### Reviewing a colleague's PR

```bash
# Create worktree for their branch
grove add example-app feature/colleague-work

# Open it up
cd "$(grove switch example-app feature/colleague-work)"

# Reset to clean state if needed
grove fresh example-app feature/colleague-work

# When done reviewing, clean up
grove rm --drop-db example-app feature/colleague-work
```

### Quick hotfix on staging

```bash
# Make sure staging is up to date
grove pull example-app staging

# Open staging
cd "$(grove switch example-app staging)"

# Make your fix, commit, then switch back to your feature
cd "$(grove switch example-app feature/current-work)"
```

### Keeping your feature branch up to date

```bash
# Sync your branch with latest staging (fetches + rebases)
grove sync example-app feature/user-avatars

# If there are conflicts, resolve them then:
git rebase --continue

# After syncing, you may need to force push
git push --force-with-lease
```

### Switching between features

```bash
# Quick switch with fzf picker
cd "$(grove switch example-app)"

# Or explicit branch
cd "$(grove switch example-app feature/other-feature)"
```

### Debugging with Tinker

```bash
# Open tinker for a specific worktree
grove tinker example-app feature/user-avatars

# Check recent commits if something looks wrong
grove log example-app feature/user-avatars
```

### End of day cleanup

```bash
# See what branches you have
grove ls example-app

# Remove any branches you're done with (keeps backup)
grove rm example-app feature/completed-work

# Or if you want to drop the database too
grove rm --drop-db example-app feature/completed-work

# Clean up any merged branches
grove prune -f example-app
```

### After a PR is merged

```bash
# Remove the worktree and delete the local branch
grove rm --delete-branch --drop-db example-app feature/merged-feature

# Update staging
grove pull example-app staging

# Sync any other feature branches with the new staging
grove sync example-app feature/other-feature
```

### Setting up a new project

```bash
# Clone the repo (auto-creates staging worktree)
grove clone git@github.com:your-org/example-app.git

# Open it immediately
cd "$(grove switch example-app staging)"

# Check everything is working
grove doctor
```

### Working on multiple related features

```bash
# Create worktrees for each feature
grove add example-app feature/api-endpoints
grove add example-app feature/frontend-components
grove add example-app feature/integration-tests

# See all of them at once
grove status example-app

# Keep them all updated
grove pull-all example-app
```

### Investigating a bug on a specific branch

```bash
# Create worktree for the problematic branch
grove add example-app bugfix/investigate-issue-123

# Open tinker to poke around
grove tinker example-app bugfix/investigate-issue-123

# Check recent commits
grove log example-app bugfix/investigate-issue-123

# Run specific artisan commands
grove exec example-app bugfix/investigate-issue-123 php artisan route:list
```

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

### Tips for Claude Code + Worktrees

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
