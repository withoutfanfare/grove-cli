# grove Tutorials (Onboarding + Recipes)

This document is a **recipe-style onboarding guide** for `grove`. Every command shown is copy/paste-able, and each `grove` command has at least one working example.

If you’re brand new to worktrees, skim the “Golden Rule” section in `README.md` first.

## Quick Start (10 minutes)

```bash
# 1) Install / update grove
git clone https://github.com/dannyharding10/grove-cli.git ~/Projects/grove-cli
cd ~/Projects/grove-cli
./install.sh

# 2) New terminal (so PATH updates), then sanity check
grove --version
grove doctor

# 3) Clone a project into Herd (creates a bare repo + a default worktree)
grove clone git@github.com:org/myapp.git

# 4) Create a new worktree for a feature branch
grove add myapp feature/login

# 5) Jump into it (path printed; you choose how to cd)
cd "$(grove cd myapp feature/login)"
```

## Concepts (the 30-second mental model)

- `grove clone` creates a **bare** git repo at `~/Herd/<repo>.git` (by default).
- Every branch you work on gets its own folder: `~/Herd/<repo>-worktrees/<site-name>/`.
- Main branches (staging/main/master) use the repo name as site-name, feature branches use just the feature name.
- **One branch per worktree**: don't `git checkout` to another branch inside a worktree; use `grove add` / `grove switch` instead.
- **Security**: All user input is validated with defense-in-depth protection against command injection, path traversal, and other attacks. See the Security section in README.md for details.

## Table of Contents

- [Core workflow](#core-workflow)
- [Command cookbook (all commands)](#command-cookbook-all-commands)
- [Templates](#templates)
- [Hooks](#hooks)
- [Automation (JSON output)](#automation-json-output)
- [Troubleshooting recipes](#troubleshooting-recipes)
- [Development & Testing](#development--testing)

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

# Also delete the git branch (local + remote where possible)
grove rm myapp feature/payments --delete-branch
```

---

## Command cookbook (all commands)

Notes:
- Commands marked “auto-detect” can infer `<repo>` / `<branch>` if you run them *inside a worktree directory*.
- If `fzf` is installed, many commands will let you omit `<branch>` and pick interactively.

### `grove doctor`

```bash
grove doctor
```

### `grove repos`

```bash
grove repos
```

### `grove clone` — clone as a bare repo (and create a default worktree)

```bash
# Uses the repo name inferred from URL ("myapp")
grove clone git@github.com:org/myapp.git

# Explicit name + create a worktree for an initial branch
grove clone git@github.com:org/myapp.git myapp feature/login
```

### `grove add` — create a worktree

```bash
# Create (or check out) a branch worktree
grove add myapp feature/login

# Create using an explicit base
grove add myapp feature/login origin/main

# Preview without changing anything
grove add myapp feature/login --dry-run

# Guided interactive wizard
grove add --interactive
```

If you pass a base (the 3rd argument), `grove` stores it in the worktree’s local git config as `grove.base`. Commands like `grove summary`, `grove diff`, `grove sync`, and `grove log` will use it automatically when you don’t specify a base.

```bash
# View the stored base for a worktree
git -C /path/to/worktree config --local --get grove.base

# Set/change it
git -C /path/to/worktree config --local grove.base origin/main
```

### `grove rm` — remove a worktree

```bash
grove rm myapp feature/login

# Force removal of protected branches (defaults: staging, main, master)
grove rm -f myapp staging

# Also delete the branch (use with care)
grove rm myapp feature/login --delete-branch

# Hook-friendly flags (used by the example hooks)
grove rm myapp feature/login --drop-db
grove rm myapp feature/login --no-backup
```

### `grove move` — rename or move a worktree

Renames a worktree directory, automatically handling Herd SSL certificates.

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
- Unsecures the old site if it had SSL
- Moves the worktree using `git worktree move`
- Re-secures the new site with SSL
- Cleans up old Herd nginx configs

### `grove ls` — list worktrees for a repo

```bash
grove ls myapp
grove ls myapp --json
```

### `grove status` — dashboard for a single repo

```bash
grove status myapp
grove status myapp --json
```

### `grove dashboard` — overview of all repos

```bash
grove dashboard

# Interactive mode with quick actions (requires fzf)
grove dashboard -i
```

In interactive mode, select a worktree and press:
- `p` to pull, `s` to sync, `o` to open in browser
- `c` to open in editor, `r` to remove, `i` for info

### `grove pull` (auto-detect)

```bash
# From inside a worktree: auto-detect repo/branch
grove pull

# Or specify explicitly
grove pull myapp feature/login
```

### `grove pull-all` — pull every worktree (parallel)

```bash
grove pull-all myapp

# Across all repositories
grove pull-all --all-repos
```

### `grove sync` — rebase onto a base branch (auto-detect)

```bash
# From inside a worktree
grove sync

# Explicit base
grove sync myapp feature/login origin/main
```

### `grove diff` — compare against base (auto-detect)

```bash
# From inside a worktree
grove diff

# Explicit base
grove diff myapp feature/login origin/main
```

### `grove summary` — overview vs base (auto-detect)

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

### `grove log` — recent commits (auto-detect)

```bash
# From inside a worktree
grove log

# Explicit
grove log myapp feature/login
```

### `grove prune` — clean up stale worktrees / references

```bash
grove prune myapp
```

### `grove exec` — run any command inside a worktree

```bash
grove exec myapp feature/login php artisan migrate
grove exec myapp feature/login npm test
```

### `grove exec-all` — run a command on all worktrees

```bash
grove exec-all myapp "php artisan about"

# Across all repositories
grove exec-all --all-repos "git status --porcelain"
```

### `grove build-all` — `npm run build` for all worktrees

```bash
grove build-all myapp
grove build-all --all-repos
```

### `grove fresh` — `migrate:fresh --seed` + npm install/build (auto-detect)

```bash
# From inside a worktree
grove fresh

# Or explicit
grove fresh myapp feature/login

# Skip confirmation prompts
grove fresh -f myapp feature/login
```

### `grove migrate` — run `php artisan migrate` (auto-detect)

```bash
grove migrate
grove migrate myapp feature/login
```

### `grove tinker` — run `php artisan tinker` (auto-detect)

```bash
grove tinker
grove tinker myapp feature/login
```

### `grove code` — open worktree in your editor (auto-detect)

```bash
grove code
grove code myapp feature/login
```

### `grove open` — open worktree URL in browser (auto-detect)

```bash
grove open
grove open myapp feature/login
```

### `grove cd` — print the worktree path (auto-detect)

```bash
cd "$(grove cd myapp feature/login)"

# From inside a worktree (prints the current worktree path)
cd "$(grove cd)"
```

### `grove switch` — cd path + open editor + open browser

```bash
# With fzf installed, omit branch to pick interactively
grove switch myapp

# Or explicit
cd "$(grove switch myapp feature/login)"
```

### `grove info` — detailed worktree information (auto-detect)

```bash
grove info myapp feature/login
grove info              # from inside a worktree
```

### `grove recent` — recently accessed worktrees

```bash
grove recent
grove recent 10
```

### `grove clean` — remove `node_modules/` and `vendor/` from inactive worktrees

Reclaim disk space by removing dependency directories from worktrees that haven't been committed to in 30+ days. These can be reinstalled with `npm install` or `composer install` when you return to the worktree.

```bash
# Preview what would be removed (shows sizes)
grove clean myapp --dry-run

# Actually remove node_modules/ and vendor/ from inactive worktrees
grove clean myapp

# Clean across all repositories
grove clean
```

### `grove health` — repository health checks

```bash
grove health myapp
```

### `grove report` — generate a markdown report

```bash
# Print to stdout
grove report myapp

# Save to a file
grove report myapp --output /tmp/grove-report-myapp.md
```

### `grove cleanup-herd` — remove orphaned Herd nginx configs

```bash
grove cleanup-herd
```

### `grove unlock` — remove stale git lock files

```bash
grove unlock myapp

# Across all repositories
grove unlock
```

### `grove repair` — fix common issues

```bash
grove repair
grove repair myapp
```

### `grove templates` — view available templates

```bash
grove templates
grove templates minimal
```

### `grove alias` — manage branch aliases

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

### `grove setup` — first-time configuration wizard

```bash
grove setup
```

Guides you through HERD_ROOT, base branch, database settings, and creates `~/.groverc`.

### `grove share-deps` — share dependencies across worktrees

```bash
# Check status
grove share-deps

# Enable shared deps (from within a worktree)
grove share-deps enable

# Disable and restore local copies
grove share-deps disable

# Clean up unused caches
grove share-deps clean
```

### `grove group` — manage repository groups

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

### `grove upgrade` — self-update

```bash
grove upgrade
```

### `grove --version` / `grove --version --check`

```bash
grove --version
grove --version --check
```

---

## Templates

Templates are small `.conf` files in `~/.grove/templates/` that set `GROVE_SKIP_*` flags for your hooks.

```bash
# Install the example templates shipped with this repo
mkdir -p ~/.grove/templates
cp examples/templates/*.conf ~/.grove/templates/

# List + inspect
grove templates
grove templates laravel

# Use a template when creating a worktree
grove add myapp feature/api --template=backend
```

---

## Hooks

Hooks are optional scripts under `~/.grove/hooks/` that run during the worktree lifecycle (pre/post add, pre/post rm, post pull, post sync).

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
- `post-pull`, `post-sync`

The hook environment includes:
`GROVE_REPO`, `GROVE_BRANCH`, `GROVE_PATH`, `GROVE_URL`, `GROVE_DB_NAME`

### Consolidated Laravel Hooks

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

See [examples/hooks/README.md](examples/hooks/README.md#consolidated-laravel-hooks) for full documentation.

---

## Automation (JSON output)

Some commands support `--json` (and optionally `--pretty`) for scripting.

```bash
grove repos --json
grove ls myapp --json
grove status myapp --json
grove summary myapp feature/login --json

# Pretty-print JSON (useful for humans)
grove ls myapp --json --pretty
```

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

The project includes 204 comprehensive tests covering security validation, git operations, and edge cases:

```bash
# Run all tests (unit + integration)
cd ~/Projects/grove-cli
./run-tests.sh

# Run only unit tests
./run-tests.sh unit

# Run only integration tests
./run-tests.sh integration

# Run a specific test file
./run-tests.sh validation.bats
```

### Building from source

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

See `README.md` Security section for full details.
