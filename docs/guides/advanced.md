# Advanced Guide

> Power features and developer documentation for grove. For getting started, see the [README](../../README.md). For command reference, see [commands.md](../reference/commands.md).

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

## Repository Groups

Create named groups of repositories for batch operations. Groups work alongside the `--all-repos` flag and multi-repository commands.

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

To change which repos are in a group, run `grove group add ...` again with the new list.

### Group Storage

Groups are stored in `~/.grove/groups` as simple key-value pairs:

```text
frontend=example-app example-api
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

# Run a command in all repos
grove exec-all --all-repos "php artisan cache:clear"
```

### Parallel Execution

Multi-repo operations run in parallel for efficiency. Configure concurrency in `~/.groverc`:

```bash
GROVE_MAX_PARALLEL=8  # Default: 4
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

## Dependency Sharing

The `share-deps` command shares `vendor/` and `node_modules/` directories across worktrees with identical lockfiles, saving disk space when working across many worktrees. Dependencies are moved to `~/.grove/shared-deps/` and symlinked back, keyed by a hash of the relevant lockfiles.

```bash
grove share-deps          # Check current sharing status
grove share-deps enable   # Enable shared dependencies (from within a worktree)
grove share-deps disable  # Disable and restore local copies
grove share-deps clean    # Remove unused shared caches
```

Run `composer install` or `npm ci` after enabling to populate the shared cache.

---

## Stable Paths for Services

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

## Developer Guide

This section is for developers who want to contribute to grove or understand its internal architecture.

### Architecture

As of v4.0.0, grove uses a modular architecture. The source code is split into focused modules in `lib/`, then concatenated into a single `grove` file for distribution.

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

1. Create the module file with appropriate number prefix (e.g., `lib/13-newmodule.sh`)
2. Add a shebang and module comment:
   ```zsh
   #!/usr/bin/env zsh
   # 13-newmodule.sh - Description of module purpose
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

See [examples/hooks/README.md](../../examples/hooks/README.md) for detailed hook documentation.
