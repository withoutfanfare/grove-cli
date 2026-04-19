# Lifecycle Hooks

grove supports lifecycle hooks that run automatically during worktree operations. All worktree setup (database, .env, composer, npm, Herd) is handled via hooks, making grove highly customisable.

## Quick Start

```bash
# Install all example hooks (recommended for Laravel projects)
./install.sh --merge

# Or manually copy specific hooks
cp examples/hooks/post-add.d/03-create-database.sh ~/.grove/hooks/post-add.d/
cp examples/hooks/post-add.d/05-composer-install.sh ~/.grove/hooks/post-add.d/
```

### Onboarding a new Laravel repo

Once hooks are installed, each Laravel repo needs a one-time setup so that new
worktrees get a matching `.env`, shared storage, and the Laravel-specific
post-add symlinks:

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
  `~/Development/Code/Worktree/<repo>/<repo>-env/`
- Ensures the shared `storage/app/` directory exists

If you forget this step, `pre-add.d/00-laravel-preflight.sh` will print the
exact command to run when you next attempt `grove add`.

## Architecture

grove is a **generic git worktree manager**. All framework-specific setup (Laravel, Node.js, etc.) is handled via hooks:

```text
grove add myapp feature/new
    │
    ├── Git: Create worktree
    ├── Git: Set up remote tracking
    │
    └── Run post-add hooks:
        ├── 01-copy-env.sh         # Copy .env.example → .env
        ├── 02-configure-env.sh    # Set APP_URL (early pass)
        ├── 03-create-database.sh  # Create MySQL database
        ├── 04-herd-secure.sh      # Secure with HTTPS
        ├── 05-composer-install.sh # composer install
        ├── 06-npm-install.sh      # npm install
        ├── 07-build-assets.sh     # npm run build
        ├── 08-run-migrations.sh   # php artisan migrate
        │
        └── myapp/                 # Repo-specific hooks (run last)
            ├── 01-symlink-env.sh  # Override with symlinked .env
            ├── 02-import-database.sh
            ├── 03-seed-data.sh
            └── 04-symlink-storage.sh
```

## Hook Resolution Order

Hooks are discovered and executed in this order:

1. **Single hook file**: `~/.grove/hooks/<hook>` (if exists and executable)
2. **Global hook directory**: `~/.grove/hooks/<hook>.d/*.sh` (alphabetical order)
3. **Repo-specific directory**: `~/.grove/hooks/<hook>.d/<repo>/*.sh` (alphabetical order)

**Important**: Directory scanning is **non-recursive**. Only files directly in these locations are executed—subdirectories are ignored (except the repo-specific `<repo>/` folder).

## Directory Structure

```text
~/.grove/hooks/
├── _lib/                       # Shared utilities
│   └── load-config.sh          # Config loader (global → repo override)
│
├── pre-add                     # Single script (runs first)
├── pre-add.d/                  # Multiple scripts (run in order)
│   └── *.sh
│
├── post-add                    # Single script
├── post-add.d/                 # Multiple scripts
│   ├── 00-register-project.sh  # Register in projects file
│   ├── 01-copy-env.sh          # Copy .env.example → .env
│   ├── 02-configure-env.sh     # Set APP_URL, DB_DATABASE
│   ├── 03-create-database.sh   # Create MySQL database
│   ├── 04-herd-secure.sh       # Secure with Herd HTTPS
│   ├── 05-composer-install.sh  # composer install + key:generate
│   ├── 06-npm-install.sh       # npm install
│   ├── 07-build-assets.sh      # npm run build
│   ├── 08-run-migrations.sh    # php artisan migrate
│   │
│   └── myapp/                  # Repo-specific hooks for 'myapp'
│       ├── 01-symlink-env.sh   # Symlink to pre-built .env
│       ├── 02-import-database.sh
│       ├── 03-seed-data.sh
│       └── 04-symlink-storage.sh
│
├── pre-rm                      # Before worktree removal (can abort)
├── pre-rm.d/
│   ├── 01-backup-database.sh   # Backup database before removal
│   └── 02-backup-env.sh        # Backup .env for review
│
├── post-rm                     # After worktree removal
├── post-rm.d/
│   ├── 01-herd-unsecure.sh     # Remove Herd SSL
│   ├── 02-drop-database.sh     # Drop database (if --drop-db)
│   └── myapp/
│       └── 01-cleanup-symlinks.sh
│
├── post-pull.d/                # After grove pull succeeds
│   └── *.sh
│
├── post-switch.d/              # After grove switch succeeds
│   ├── 01-update-current-link.sh  # Update {repo}-current symlink
│   ├── 02-devctl-restart.sh    # Restart grove services
│   └── myapp/
│       └── 01-configure-env.sh # Set APP_URL + DB_DATABASE
│
└── post-sync.d/                # After grove sync succeeds
    └── *.sh
```

## Execution Order Example

For the `myapp` repo running `grove add myapp feature/login`:

```text
post-add                      (single file, if exists)
00-register-project.sh        (global)
01-copy-env.sh                (global)
02-configure-env.sh           (global)
03-create-database.sh         (global)
04-herd-secure.sh             (global)
05-composer-install.sh        (global)
06-npm-install.sh             (global)
07-build-assets.sh            (global)
08-run-migrations.sh          (global)
myapp/01-symlink-env.sh       (repo-specific)
myapp/02-import-database.sh   (repo-specific)
myapp/03-seed-data.sh         (repo-specific)
myapp/04-symlink-storage.sh   (repo-specific)
```

## Available Hooks

| Hook | When | Can Abort? | Use Case |
|------|------|------------|----------|
| `pre-add` | Before worktree creation | Yes (exit 1) | Validation, resource checks |
| `post-add` | After worktree creation | No | Setup: .env, database, composer, npm |
| `pre-rm` | Before worktree removal | Yes (exit 1) | Database backup, validation |
| `post-rm` | After worktree removal | No | Cleanup: Herd, database drop |
| `post-pull` | After `grove pull` succeeds | No | Cache clear, migrations |
| `post-switch` | After `grove switch` succeeds | No | Configure .env, update symlinks |
| `post-sync` | After `grove sync` succeeds | No | Rebuild after rebase |

## Environment Variables

Available in all hooks:

| Variable | Example | Description |
|----------|---------|-------------|
| `GROVE_REPO` | `myapp` | Repository name |
| `GROVE_BRANCH` | `feature/new-feature` | Branch name |
| `GROVE_BRANCH_SLUG` | `feature-new-feature` | URL-safe branch slug (/ replaced with -) |
| `GROVE_PATH` | `/Users/you/Herd/myapp-worktrees/new-feature` | Worktree directory path |
| `GROVE_URL` | `https://new-feature.test` | Local development URL |
| `GROVE_DB_NAME` | `myapp__feature_new_feature` | Generated database name |
| `GROVE_HOOK_NAME` | `post-add` | Current hook being executed |
| `GROVE_NO_BACKUP` | `true` | Set when `--no-backup` flag used |
| `GROVE_DROP_DB` | `true` | Set when `--drop-db` flag used |

## Example Hooks Included

### Pre-Add Hooks (pre-add.d/)

| Hook | Purpose |
|------|---------|
| `00-laravel-preflight.sh` | Warn (non-blocking) when a Laravel repo is missing setup — unlinked hooks, missing `.env` template, missing primary worktree. Prints exact fix commands. |

### Global Hooks (post-add.d/)

| Hook | Purpose |
|------|---------|
| `00-register-project.sh` | Register worktree in `~/.projects` for quick navigation |
| `01-copy-env.sh` | Copy `.env.example` to `.env` |
| `01a-inherit-db-from-primary.sh` | When `DB_CREATE=false`, sync `DB_DATABASE` from the primary worktree's `.env` (prevents stale `.env.example` DB names cascading into new worktrees) |
| `02-configure-env.sh` | Set `APP_URL` in `.env` (early pass) |
| `03-create-database.sh` | Create MySQL database |
| `04-herd-secure.sh` | Secure site with Herd HTTPS |
| `04-laravel-scaffold.sh` | Create missing Laravel runtime dirs (`bootstrap/cache`, `storage/framework/{cache/data,sessions,testing,views}`, `storage/logs`) before composer runs. Defensive against repos whose `.gitignore` excludes these dirs outright. |
| `05-composer-install.sh` | Run `composer install` + generate app key |
| `06-npm-install.sh` | Run `npm install` |
| `07-build-assets.sh` | Run `npm run build` if build script exists |
| `08-run-migrations.sh` | Run Laravel migrations |

### Shared Laravel Hooks (post-add.d/_laravel/)

Laravel-specific hooks that you opt into per repo by symlinking them via `link-repo.sh`:

| Hook | Purpose |
|------|---------|
| `01-ai-files.sh` | Symlink shared AI/LLM context into the worktree |
| `02-copy-env.sh` | Overwrite `.env` with pre-built template from `~/Development/Code/Worktree/<repo>/<repo>-env/.env` |
| `03-configure-env.sh` | Set `APP_URL`, `VITE_APP_URL`, `SESSION_DOMAIN`, and `DB_DATABASE` for the worktree |
| `04-import-database.sh` | Import gzipped SQL dump from the template folder |
| `05-symlink-storage.sh` | Symlink `storage/app` to a shared directory (preserves uploads across worktrees) |
| `link-repo.sh` | Run once per repo: `bash _laravel/link-repo.sh <repo>` — creates symlinks from `<repo>/*.sh` to `_laravel/*.sh` |

### Repo-Specific Hooks (post-add.d/myapp/)

| Hook | Purpose |
|------|---------|
| `01-symlink-env.sh` | Replace `.env` with symlink to pre-built version |
| `02-import-database.sh` | Import database from gzipped SQL dump |
| `03-seed-data.sh` | Seed database with development data |
| `04-symlink-storage.sh` | Symlink `storage/app` to shared directory |

### Pre-Removal Hooks (pre-rm.d/)

| Hook | Purpose |
|------|---------|
| `01-backup-database.sh` | Backup database before removal (respects DB_BACKUP) |
| `02-backup-env.sh` | Backup .env to template folder for review |

### Post-Removal Hooks (post-rm.d/)

| Hook | Purpose |
|------|---------|
| `01-herd-unsecure.sh` | Remove Herd SSL and nginx config |
| `02-drop-database.sh` | Drop database (only if `--drop-db` flag) |

### Post-Switch Hooks (post-switch.d/)

| Hook | Purpose |
|------|---------|
| `01-update-current-link.sh` | Update `{repo}-current` symlink to point to active worktree |
| `02-devctl-restart.sh` | Restart grove services (Supervisor/Horizon) |

### Repo-Specific Post-Switch (post-switch.d/myapp/)

| Hook | Purpose |
|------|---------|
| `01-configure-env.sh` | Set `APP_URL`, `SESSION_DOMAIN`, and `DB_DATABASE` in `.env` |

## Configuration Hierarchy

Database hooks and other configuration-aware hooks respect a **configuration hierarchy**. Settings are loaded in order, with later values overriding earlier ones:

1. **Defaults** (built into hooks)
2. **Global config** (`~/.groverc`)
3. **Project config** (`$HERD_ROOT/.groveconfig`)
4. **Repo-specific config** (`$HERD_ROOT/<repo>.git/.groveconfig`)

This allows you to:
- Disable database management globally (`DB_CREATE=false` in `~/.groverc`)
- Re-enable it for specific repos (`DB_CREATE=true` in repo's `.groveconfig`)

### Shared Config Loader

Hooks that need configuration should source the shared loader:

```bash
#!/bin/bash
# Load configuration (global -> project -> repo-specific)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../_lib/load-config.sh"

# Now these variables are available:
# DB_HOST, DB_USER, DB_PASSWORD, DB_CREATE, DB_BACKUP, DB_BACKUP_DIR
# HERD_ROOT, HERD_CONFIG, DEFAULT_BASE, PROTECTED_BRANCHES
```

### Database Hook Behaviour

| Global `DB_CREATE` | Repo `DB_CREATE` | Result |
|-------------------|------------------|--------|
| `true` (default) | (not set) | Database created, managed by grove |
| `true` | `false` | No database management for this repo |
| `false` | (not set) | No database management |
| `false` | `true` | Database created for this repo only |

## Control Flags

Skip specific hooks by setting environment variables:

```bash
# Skip database creation (one-time)
GROVE_SKIP_DB=true grove add myapp feature/no-db

# Skip composer install
GROVE_SKIP_COMPOSER=true grove add myapp feature/quick

# Skip all npm operations
GROVE_SKIP_NPM=true GROVE_SKIP_BUILD=true grove add myapp feature/backend-only
```

Or disable permanently via configuration:

```bash
# In ~/.groverc (global) or ~/Herd/myapp.git/.groveconfig (per-repo)
DB_CREATE=false    # Disable database creation/management
DB_BACKUP=false    # Disable database backups on removal
```

## Common Patterns

### Pre-built .env Files

Keep your secrets in one place and symlink from worktrees:

```bash
# Create env storage directory
mkdir -p ~/Code/Worktree/myapp/myapp-env

# Create your .env with all secrets
cp /path/to/configured/.env ~/Code/Worktree/myapp/myapp-env/.env

# Create repo-specific hook to symlink it
mkdir -p ~/.grove/hooks/post-add.d/myapp
cat > ~/.grove/hooks/post-add.d/myapp/01-symlink-env.sh << 'EOF'
#!/bin/bash
ENV_SOURCE="$HOME/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-env/.env"
if [[ -f "$ENV_SOURCE" ]]; then
  rm -f "${GROVE_PATH}/.env"
  ln -sf "$ENV_SOURCE" "${GROVE_PATH}/.env"
  echo "  Linked .env → $ENV_SOURCE"
fi
EOF
chmod +x ~/.grove/hooks/post-add.d/myapp/01-symlink-env.sh
```

### Shared Storage Directory

Preserve uploaded files and generated content across worktrees:

```bash
# Create shared storage directory
mkdir -p ~/Code/Worktree/myapp/storage/app/public

# Create repo-specific hook to symlink it
mkdir -p ~/.grove/hooks/post-add.d/myapp
cat > ~/.grove/hooks/post-add.d/myapp/04-symlink-storage.sh << 'EOF'
#!/bin/bash
STORAGE_APP_SOURCE="$HOME/Code/Worktree/${GROVE_REPO}/storage/app"
if [[ -d "$STORAGE_APP_SOURCE" ]]; then
  mkdir -p "${GROVE_PATH}/storage"
  rm -rf "${GROVE_PATH}/storage/app"
  ln -sf "$STORAGE_APP_SOURCE" "${GROVE_PATH}/storage/app"
  echo "  Linked storage/app → $STORAGE_APP_SOURCE"
fi
EOF
chmod +x ~/.grove/hooks/post-add.d/myapp/04-symlink-storage.sh
```

This is useful for:
- User uploads that you need to test with
- Generated PDFs, images, or exports
- Cached files that take time to regenerate
- Any files in `storage/app` you want persisted

### Import Database from SQL Dump

For repos that need a baseline database:

```bash
# Store your SQL dump
mkdir -p ~/Code/Worktree/myapp/myapp-db
mysqldump myapp_reference | gzip > ~/Code/Worktree/myapp/myapp-db/myapp.sql.gz

# Create repo-specific hook
cat > ~/.grove/hooks/post-add.d/myapp/02-import-database.sh << 'EOF'
#!/bin/bash
DB_DUMP="$HOME/Code/Worktree/${GROVE_REPO}/${GROVE_REPO}-db/${GROVE_REPO}.sql.gz"
if [[ -f "$DB_DUMP" ]]; then
  echo "  Importing database..."
  gunzip -c "$DB_DUMP" | mysql "$GROVE_DB_NAME"
fi
EOF
chmod +x ~/.grove/hooks/post-add.d/myapp/02-import-database.sh
```

### Quick Project Navigation

Register worktrees for quick access with `cproj`:

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

### Non-Laravel Projects

For projects without Laravel/PHP, disable those hooks:

```bash
# Create a repo-specific skip file
mkdir -p ~/.grove/hooks/post-add.d/frontend-app
cat > ~/.grove/hooks/post-add.d/frontend-app/00-skip-laravel.sh << 'EOF'
#!/bin/bash
# Skip Laravel-specific hooks for this repo
export GROVE_SKIP_DB=true
export GROVE_SKIP_COMPOSER=true
echo "  Skipping Laravel setup for frontend-only repo"
EOF
chmod +x ~/.grove/hooks/post-add.d/frontend-app/00-skip-laravel.sh
```

Or simply don't install the Laravel hooks and only use what you need.

## Creating Repo-Specific Hooks

To add custom hooks for a specific repository:

1. **Create the repo directory**:
   ```bash
   mkdir -p ~/.grove/hooks/post-add.d/myrepo
   ```

2. **Add your hook scripts**:
   ```bash
   # Use numbered prefixes to control execution order
   cat > ~/.grove/hooks/post-add.d/myrepo/01-custom-setup.sh << 'EOF'
   #!/bin/bash
   echo "  Running custom setup for ${GROVE_REPO}..."
   # Your custom logic here
   EOF
   chmod +x ~/.grove/hooks/post-add.d/myrepo/01-custom-setup.sh
   ```

3. **Copy examples as a starting point** (optional):
   ```bash
   cp examples/hooks/post-add.d/myapp/*.sh ~/.grove/hooks/post-add.d/myrepo/
   # Edit as needed
   ```

Repo-specific hooks run **after** all global hooks, so you can:
- Override earlier setup (e.g., replace copied .env with a symlink)
- Add extra steps specific to that project
- Import project-specific data

## Tips

- **Numbering**: Use `00-`, `01-`, etc. to control execution order
- **Permissions**: All hooks must be executable (`chmod +x`)
- **Conditionals**: Check if files exist before running commands
- **Output**: Prefix messages with spaces (`echo "  message"`) for clean output
- **Failures**: Hooks continue even if one fails (except pre-* hooks which can abort)
- **Security**: Hooks must be owned by you and not world-writable

## Migrating from Built-in Setup

If you were using grove before hooks were introduced, the built-in Laravel setup is now handled by hooks. Run the installer with `--merge` to get the example hooks:

```bash
cd ~/Projects/grove-cli
./install.sh --merge
```

This will install the example hooks without overwriting any custom hooks you may have.
