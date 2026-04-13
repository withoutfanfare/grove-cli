# Changelog

All notable changes to the `wt` Git Worktree Manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Rebranded from `wt` to `grove`** - The tool has been renamed from `wt` (wt-worktree-manager) to `grove` (grove-cli). All commands, environment variables, config files, and directory paths have been updated:
  - Command: `wt` → `grove`
  - Config file: `~/.wtrc` → `~/.groverc`
  - Config dir: `~/.wt/` → `~/.grove/`
  - Environment variables: `WT_*` → `GROVE_*`
  - Git config: `wt.base` → `grove.base`
  - Completion script: `_wt` → `_grove`

## [4.2.0] - 2026-01-10

### Added
- **`wt changes` command** - List uncommitted file changes for a worktree with coloured status indicators (M=modified, A=added, D=deleted, ?=untracked). Supports `--json` output for integration with external tools
- **`wt log` JSON output** - Added `--json` flag to output commit history as structured JSON with sha, message, author, and date fields
- **`wt log -n` flag** - Control the number of commits shown (e.g., `wt log repo branch -n 10`). Default changed from 20 to 5 for more focused output
- **Enhanced `wt ls --json` output** - Added new fields for better worktree state visibility:
  - `lastAccessed` - ISO 8601 timestamp of last filesystem modification
  - `merged` - Boolean indicating if branch is fully merged into base
  - `stale` - Boolean indicating if branch is >50 commits behind base

### Fixed
- **Zsh loop variable declarations** - Fixed spurious debug output caused by `local var; var=value` pattern inside loops across multiple modules (`lib/03-paths.sh`, `lib/04-git.sh`, `lib/09-parallel.sh`, `lib/12-deps.sh`, `lib/commands/*.sh`). Variables are now declared before loops or combined into single declarations

## [4.1.0] - 2026-01-10

### Security
- **Command Injection Fixes** - Fixed critical command injection vulnerabilities in parallel execution, transaction rollback, and alias targets
- **Password Protection** - Database operations now use `MYSQL_PWD` environment variable instead of command-line arguments to prevent password exposure in process listings
- **Input Validation** - Added comprehensive validation for git references, null bytes, and config values to prevent injection attacks
- **Safe Evaluation** - Replaced dangerous `eval` calls with safer execution methods

### Changed

#### New Directory Structure
- **Worktree paths** - Changed from `~/Herd/<repo>--<branch-slug>/` to `~/Herd/<repo>-worktrees/<site-name>/`
  - Main branches (staging/main/master) use repo name: `~/Herd/myapp-worktrees/myapp/`
  - Feature branches use feature name only: `~/Herd/myapp-worktrees/login/` (for `feature/login`)
  - Keeps worktrees organised by repository in subdirectories
- **Site names** - Simplified from `repo--branch-slug` to just the feature name
  - Example: `feature/sms-unsubscribe` → `sms-unsubscribe.test` (was `myapp--feature-sms-unsubscribe.test`)
  - SSL-compatible: Names are automatically truncated with hash suffix if over 59 characters
- **Herd integration** - Updated hooks to use `herd link` before `herd secure` (required for subdirectory worktrees)

### Added
- **`wt restructure`** - New command to migrate existing worktrees to the new directory structure

### Fixed
- **Race conditions** - Fixed race conditions in parallel operations that could cause lost results
- **Regex compatibility** - Fixed regex syntax errors to ensure compatibility with all zsh versions
- **Database names** - Fixed bounds checking to prevent invalid truncation of short database names
- **Cleanup reliability** - Worktree creation failures now reliably clean up partial directories and Herd configs
- **Overflow checks** - Added protection against integer overflow in commit age calculations
- **Arithmetic with `set -e`** - Hardened arithmetic operations to prevent script exits when expressions evaluate to zero (e.g., using `var=$((var + 1))` instead of `((var++))`)
- **Debug output leaks** - Fixed duplicate local variable declarations causing debug output in git cache functions
- **APP_URL extraction** - Improved `.env` parsing to handle leading whitespace before `APP_URL` declarations
- **Branch name sanitisation** - Automatically strips `origin/` prefix from branch names to prevent user input errors
- **Fetch refspec** - Fixed branch fetching to use wildcard refspec ensuring all remote branches are available

### Added

#### Structured Error Handling
- **JSON error responses** - `die_json()` and `error_exit()` provide structured error output with error codes for scripting
- **Error codes** - Consistent error codes across all commands: `INVALID_INPUT`, `INVALID_REPO`, `INVALID_BRANCH`, `REPO_NOT_FOUND`, `WORKTREE_NOT_FOUND`, etc.
- **Exit codes** - Meaningful exit codes (1 for general errors, 2 for input validation errors)

#### New Commands
- **`wt dashboard`** - Visual overview of all repositories with health grades, worktree counts, and status indicators
- **`wt info [repo] [branch]`** - Detailed information about a worktree (path, URL, database, health score, sync status)
- **`wt recent [limit]`** - List recently accessed worktrees sorted by access time (default: 5)
- **`wt clean [repo]`** - Remove `node_modules/` and `vendor/` from inactive worktrees (>30 days) to save disk space
- **`wt alias`** - Manage branch aliases for quick access:
  - `wt alias set <name> <repo> <branch>` - Create an alias
  - `wt alias get <name>` - Show alias target
  - `wt alias list` - List all aliases
  - `wt alias remove <name>` - Delete an alias
- **`wt upgrade`** - Self-update command that downloads the latest version from GitHub
- **`wt version --check`** - Check for available updates without installing
- **`wt summary [repo] [branch] [base]`** - Comprehensive overview of worktree status vs base branch including commit counts, uncommitted changes, recent commits, and diff statistics. Supports `--json` output
- **`wt config`** - Output current configuration as JSON for debugging and scripting
- **`wt branches <repo>`** - List all available branches (local and remote) with worktree status indicators
- **`wt group`** - Manage repository groups for bulk operations:
  - `wt group add <name> <repo1> <repo2> ...` - Create a group
  - `wt group rm <name>` - Remove a group
  - `wt group show <name>` - Show group members
  - `wt group list` - List all groups
- **`wt share-deps`** - Share `vendor/` and `node_modules/` across worktrees to save disk space:
  - `wt share-deps enable [repo]` - Enable dependency sharing
  - `wt share-deps disable [repo]` - Disable and restore local copies
  - `wt share-deps status [repo]` - Show sharing status and space savings

#### Performance Optimisations
- **Git status batching** - Collects worktree statuses in a single pass and caches results for O(1) lookups
- **Associative array lookups** - Replaced O(N²) branch matching loops with O(1) associative array lookups
- **Zsh-native JSON parsing** - Uses Zsh regex instead of spawning grep/cut/sed subprocesses
- **Fetch caching** - Caches git fetch results for 30 seconds to avoid redundant network calls between sequential commands
- **Date caching** - Caches `date +%s` at command start to avoid repeated subprocess spawns
- **`--no-cache` flag** - Bypass fetch cache and always fetch fresh from remote
- **`--refresh` flag** - Clear fetch cache before running command

#### Base Branch Tracking
- **Per-worktree base ref** - Each worktree can store its base branch (e.g., `staging`, `main`) for use in sync, diff, log, and summary commands
- **Automatic detection** - Base branch is auto-detected when creating worktrees and stored in `.wt-base` file
- **Consistent defaults** - All commands that compare against a base now use the worktree's stored base or fall back to `DEFAULT_BASE`

#### Herd Integration Improvements
- **Automatic service restart** - Herd nginx is gracefully reloaded after adding or removing worktrees
- **AppleScript integration** - Herd application is cleanly restarted when needed for configuration changes to take effect
- **Orphaned site cleanup** - Improved detection and removal of stale symlinks for linked sites

#### Health Score System
- **A-F grades** for worktree health based on:
  - Commits behind base branch (max -30 points)
  - Uncommitted changes (max -20 points)
  - Days since last commit (max -25 points)
  - Merge status (max -10 points)
  - Untracked files (max -5 points)
- Visible in `wt health`, `wt dashboard`, and individual worktree displays
- Coloured output: A/B (green), C/D (yellow), F (red)

#### Multi-Repository Operations
- **`--all-repos` flag** - Apply operations across all repositories:
  - `wt pull-all --all-repos` - Pull all worktrees in all repos
  - `wt build-all --all-repos` - Build all worktrees in all repos
  - `wt exec-all --all-repos <cmd>` - Execute command in all repos

#### Branch Naming Validation
- **Configurable branch patterns** - Set `BRANCH_PATTERN` in config to enforce naming conventions
- **Auto-suggestions** - When a branch name doesn't match the pattern, helpful suggestions are provided
- **`--force` bypass** - Use `-f` to bypass pattern validation when needed

#### Code Modularisation
- **Modular architecture** - The 3,162-line monolithic script has been refactored into 18 focused modules in `lib/` for better maintainability
- **Build system** - `build.sh` concatenates modules into a single `wt` file for distribution
- **Module structure**:
  - `lib/00-header.sh` - Version, global defaults, flags
  - `lib/01-core.sh` - Config loading, colours, output helpers
  - `lib/02-validation.sh` - Input validation, security checks
  - `lib/03-paths.sh` - Path resolution, URL generation
  - `lib/04-git.sh` - Git operations, branch helpers
  - `lib/05-database.sh` - MySQL operations
  - `lib/06-hooks.sh` - Hook system with security verification
  - `lib/07-templates.sh` - Template loading
  - `lib/08-spinner.sh` - Progress indicators
  - `lib/09-parallel.sh` - Parallel execution framework
  - `lib/10-interactive.sh` - Interactive wizard
  - `lib/11-resilience.sh` - Retry logic, transactions, lock cleanup
  - `lib/commands/*.sh` - Command implementations

#### Interactive Mode
- **`wt add --interactive` / `-i`** - Guided worktree creation wizard with 5 steps:
  1. Repository selection (fzf picker)
  2. Base branch selection (fzf picker)
  3. Branch name input with live preview (path, URL, database)
  4. Template selection (optional fzf picker)
  5. Confirmation with full summary
- Requires fzf to be installed

#### Progress Indicators
- **Spinner animation** - Braille-pattern spinner for long operations
- `spinner_start "message"` / `spinner_stop "ok|fail|skip"` - Background spinner control
- `with_spinner "message" command...` - Wrap commands with progress indication
- Step progress indicator for multi-step operations

#### Parallel Operations
- **`wt build-all <repo>`** - Run `npm run build` on all worktrees
- **`wt exec-all <repo> <command>`** - Execute any command across all worktrees
- Configurable concurrency via `WT_MAX_PARALLEL` environment variable (default: 4)

#### Resilience Improvements
- **`wt repair [repo]`** - Scan for and fix common issues:
  - Prunes orphaned worktree entries
  - Removes stale git index locks
  - Checks for missing `.git` files in worktrees
- **Retry logic** - `with_retry <max_attempts> <command>` with exponential backoff
- **Transaction pattern** - Rollback support for failed multi-step operations
- **Disk space checks** - Pre-flight checks before operations
- **Lock cleanup** - Automatic detection and removal of stale index locks (>5 min old)

### Changed
- **Version 4.0.0** - Major version bump for architectural changes
- **Help text** - Updated to show new commands and flags
- **Default parallel limit** - 4 concurrent operations (configurable via `WT_MAX_PARALLEL`)

### Removed
- **`wt fresh-all`** - Removed due to destructive nature (runs `migrate:fresh` on all worktrees). Use `wt exec-all <repo> "php artisan migrate:fresh --seed"` if needed.

### Fixed
- **Zsh local variable re-declaration bug** - Fixed spurious debug output appearing in `wt dashboard`, `wt recent`, and other commands with loops. The issue was caused by zsh printing previous values when `local var; var=value` is re-declared inside a loop. Variables are now declared before loops.
- **Variable name conflicts** - Fixed `path` variable colliding with zsh's special `$path` array (lowercase PATH). Renamed to `wt_path` throughout.
- **Recent command folder reference** - Fixed `wt recent` using wrong variable (`${path:t}` instead of `${wt_path:t}`) for folder name extraction.

### Developer Notes
- Modules are sourced in dependency order (00 through 99)
- Each module is self-contained with its shebang stripped during build
- Tests continue to work against the built `wt` file
- Development workflow: edit modules in `lib/`, run `./build.sh`, test with `./wt`

## [3.9.0] - 2025-12-25

### Added
- **`--dry-run` flag for `wt add`** - Preview worktree creation without executing (shows path, URL, database, template settings)
- **`--pretty` flag for JSON output** - Colourised, formatted JSON output for better readability
- **Template listing in help** - Available templates now shown when running `wt --help`
- **"Did you mean?" suggestions** - Helpful suggestions when template names are mistyped
- **Shellcheck integration** - Run `./run-tests.sh lint` for static analysis
- **19 new integration tests** - Command-line parsing, help output, and validation tests
- **187 total tests** - Expanded from 168 to 187 tests

### Changed
- **Consolidated validation functions** - `validate_identifier_common()` helper reduces code duplication
- **Better error messages** - Template not found errors now suggest similar names
- **Help text improvements** - New flags documented, template usage examples added

### Fixed
- Empty validation in both repo/branch and template name validation now checked first

## [3.8.1] - 2025-12-25

### Security
- **Template path traversal prevention** - Template names are now validated to prevent path traversal attacks (e.g., `../etc/passwd`)
- **Template variable injection prevention** - `WT_SKIP_*` variables in templates now only accept `true` or `false` values, preventing command injection
- **Template flag validation** - `--template` and `-t` flags now validate that a non-empty template name is provided

### Fixed
- **Date calculation edge cases** - Future timestamps (from clock skew) are now handled gracefully in age calculations
- **JSON escaping completeness** - Added escaping for `\r`, `\f`, `\b` control characters

### Added
- **Template security tests** - 28 new tests covering path traversal, injection attacks, and input validation
- **168 total tests** - Expanded test suite from 137 to 168 tests

### Changed
- Template name validation now checks for empty names before other validation rules

## [3.8.0] - 2025-12-25

### Added

#### Automated Testing Framework
- **BATS test suite** - Comprehensive automated tests using Bash Automated Testing System
- **137 unit tests** covering:
  - Input validation (`validate_name`) - security-critical path traversal, git flag injection
  - Branch slugification (`slugify_branch`, `extract_feature_name`)
  - Database naming (`db_name_for`) - MySQL 64-char limit, hash suffix
  - URL generation (`url_for`, `wt_path_for`)
  - JSON escaping (`json_escape`)
  - Config parsing security (whitelist enforcement)
- Run tests with `./run-tests.sh` or `./run-tests.sh unit` / `./run-tests.sh integration`

#### Enhanced Status Dashboard
- **AGE column** - Shows human-readable age of last commit (1d, 2w, 3mo, 1y)
- **MERGED column** - Shows ✓ if branch is fully merged into base, - if not
- **STALE indicator** - Red 🔴 marker for branches >50 commits behind base
- **Inactive highlighting** - Yellow age display for branches >30 days since last commit
- **JSON output** - `wt status <repo> --json` for scripting with new fields: `stale`, `age`, `age_days`, `merged`

#### Worktree Templates
- **`wt templates`** - List available templates with descriptions
- **`wt templates <name>`** - View detailed template configuration
- **`wt add --template=<name>`** or `-t <name>` - Apply template when creating worktree
- **Template format** - Simple key=value files in `~/.wt/templates/` that set `WT_SKIP_*` variables
- **Example templates included**:
  - `laravel.conf` - Full Laravel setup (database, composer, npm, migrations)
  - `node.conf` - Node.js projects (npm only, skip PHP/database)
  - `minimal.conf` - Git worktree only, skip all setup hooks
  - `backend.conf` - Backend API work (PHP + database, skip npm/build)

### Changed
- Version bump to 3.8.0

## [3.7.0] - 2025-12-25

### Changed
- **Generic worktree manager** - Refactored `wt` to be a framework-agnostic git worktree manager. All Laravel-specific functionality (database creation, composer install, npm, Herd securing, migrations) has been moved into optional hooks
- **Hook-based architecture** - Worktree setup is now fully customisable via lifecycle hooks in `~/.wt/hooks/`. Install the example hooks for Laravel projects, or create your own for any framework

### Added
- **Comprehensive example hooks** for Laravel projects:
  - `00-register-project.sh` - Register worktree in `~/.projects` for quick navigation
  - `01-copy-env.sh` - Copy `.env.example` to `.env`
  - `02-configure-env.sh` - Set `APP_URL` and `DB_DATABASE` in `.env`
  - `03-create-database.sh` - Create MySQL database
  - `04-herd-secure.sh` - Secure site with Herd HTTPS
  - `05-composer-install.sh` - Run `composer install` + generate app key
  - `06-npm-install.sh` - Run `npm install`
  - `07-build-assets.sh` - Run `npm run build`
  - `08-run-migrations.sh` - Run Laravel migrations
  - `pre-rm.d/01-backup-database.sh` - Backup database before removal
  - `post-rm.d/01-herd-unsecure.sh` - Remove Herd SSL config
  - `post-rm.d/02-drop-database.sh` - Drop database (opt-in via `--drop-db`)
- **Repo-specific hooks** - Create subdirectories matching repo names (e.g., `post-add.d/myapp/`) for hooks that only run for specific repositories
- **Per-repository config** - Load `.wtconfig` from bare repo directory (e.g., `~/Herd/myapp.git/.wtconfig`) for repo-specific settings like `DEFAULT_BASE`
- **Hook control flags** - Skip specific hooks via environment variables: `WT_SKIP_DB`, `WT_SKIP_COMPOSER`, `WT_SKIP_NPM`, `WT_SKIP_BUILD`, `WT_SKIP_MIGRATE`, `WT_SKIP_HERD`
- **Installer merge/overwrite modes** - Run `./install.sh --merge` to add new example hooks without overwriting existing ones, or `--overwrite` to replace all hooks (backs up first)

### Fixed
- **Hooks not running** - Fixed zsh glob qualifier order bug where `*(.x)(N)` didn't match executable files. Corrected to `*(N.x)` (null glob must come first)
- **URL generation** - Fixed `url_for()` to include repository name, generating correct URLs like `https://myapp--feature-login.test` instead of just `https://feature-login.test`
- **Repo-specific config loading** - Fixed `DEFAULT_BASE` not being loaded from per-repo `.wtconfig` files

## [3.6.0] - 2025-12-24

### Security
- **Config file hardening** - Configuration files are now parsed as key-value pairs instead of sourced, preventing arbitrary code execution via malicious `.wtrc` files
- **Hook execution security** - Hooks are now verified to be owned by the current user and not world-writable before execution
- **Input validation hardening** - Added protection against absolute paths, git flag injection (branches starting with `-`), reserved git references (`HEAD`, `refs/`), and malformed paths

### Added
- **`wt health <repo>`** - New command to check repository health (stale worktrees, orphaned databases, missing .env files, branch mismatches)
- **`wt report <repo>`** - New command to generate markdown status report with worktree summary, status, and hook availability
- **`wt clone` branch argument** - Clone and create worktree for a specific branch in one command: `wt clone <url> [name] [branch]`
  - If branch exists on remote, creates worktree for it
  - If branch doesn't exist, creates new branch from staging/main/master
- **Additional lifecycle hooks** - Added `pre-add`, `pre-rm`, `post-pull`, and `post-sync` hooks alongside existing `post-add` and `post-rm`
  - Pre-hooks can abort operations by returning non-zero exit code
- Database names are now automatically truncated with a hash suffix if they exceed MySQL's 64-character limit
- Confirmation prompt before `wt fresh` runs `migrate:fresh` (use `-f` to skip)

### Fixed
- Explicitly fetch remote base branches when using `origin/...` to ensure the latest version is used
- Branches with slashes (e.g., `origin/proj-jl/rethink`) are now properly fetched before creating worktrees

## [3.4.0] - 2025-12-23

### Added
- `wt cleanup` command to remove orphaned Herd nginx configurations and certificates
- `wt unlock` command to safely remove stale git lock files
- Helper to clean individual Herd site configs when unsecuring sites

### Fixed
- Improved temporary directory handling with explicit paths for safer cleanup during parallel pulls
- Prevents nginx startup failures caused by stale Herd configuration files

## [3.3.1] - 2025-12-21

### Changed
- URLs now use just the feature name instead of repo--branch format
  - Example: `feature/sms-unsubscribe` becomes `sms-unsubscribe.test` (was `scooda--feature-sms-unsubscribe.test`)

### Added
- `WT_URL_SUBDOMAIN` config option for subdomain prefix (e.g., `WT_URL_SUBDOMAIN=api` gives `api.sms-unsubscribe.test`)
- `wt ls` now reads `APP_URL` from `.env` when available

### Documentation
- Added "Golden Rule" section explaining that each worktree is a permanent home for one branch
- Documented safe vs unsafe git operations within worktrees
- Added guidance on fixing accidental branch switches

## [3.3.0] - 2025-12-21

### Added
- Branch/directory mismatch detection in `wt ls` and `wt status`
  - Warns when a worktree's directory name doesn't match its checked-out branch
- Automatic remote tracking setup when creating new branches
  - New branches are pushed and set to track their own remote branch
- JSON output now includes `mismatch` field in `wt ls --json`

### Fixed
- Fixed branch tracking issue where new branches could track wrong remote
- Worktrees now created with `--no-track` to prevent inheriting base branch tracking

## [3.2.1] - 2025-12-21

### Fixed
- Minor bug fixes and stability improvements

## [3.2.0] - 2025-12-20

### Added
- Initial public release
- Core worktree management: `add`, `rm`, `ls`, `repos`
- Navigation commands: `cd`, `code`, `open`, `switch`
- Git operations: `pull`, `pull-all`, `sync`, `status`
- Laravel integration: `fresh`, `migrate`, `tinker`, `log`
- Maintenance: `clone`, `prune`, `exec`, `doctor`
- Automatic `.env` setup with unique `APP_URL` per worktree
- Automatic MySQL database creation per worktree
- Laravel Herd integration with HTTPS via `herd secure`
- fzf integration for interactive branch selection
- Tab completion for zsh
- JSON output mode for scripting
- Protected branch safety (staging, main, master require `-f` to remove)
- Database backup on worktree removal
- macOS desktop notifications for long operations
- Parallel execution for `pull-all`

### Features from 3.0.0 (pre-public development)
- New commands: `repos`, `doctor`, `fresh`, `switch`, `migrate`, `tinker`, `log`
- Parallel `pull-all` for concurrent worktree updates
- Auto-create staging worktree on `clone`
- `--drop-db` flag to drop database after backup
- `--no-backup` flag to skip database backup on removal
