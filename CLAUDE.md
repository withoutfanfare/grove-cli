# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`grove` is a command-line git worktree manager written in Zsh, designed for managing multiple worktrees with optional Laravel Herd integration. It's framework-agnostic - all framework-specific setup is handled via customisable lifecycle hooks.

## ⚠️ CRITICAL: Build Process

**NEVER edit the `grove` file directly!** The `grove` file is a compiled artifact generated from modular source files in `lib/`.

### Making Changes

1. **Edit source files** in `lib/` directories:
   - Core functionality: `lib/00-header.sh` through `lib/12-deps.sh`
   - Commands: `lib/commands/*.sh`
   - Main entry point: `lib/99-main.sh`

2. **Rebuild the `grove` file** after making changes:
   ```bash
   ./build.sh
   ```

3. **Verify the build** by running tests:
   ```bash
   ./run-tests.sh
   ```

### Why This Matters

- Direct edits to `grove` will be **lost** when the build script runs
- All functionality must be in `lib/` files to survive the build process
- The build process concatenates modules in a specific order (dependencies first)

## ⚠️ CRITICAL: JSON Output Data Contract

**The JSON output is a critical data contract** used by the grove-app Tauri desktop application and potentially other integrations. Breaking changes to JSON output will break dependent applications.

### JSON Output Requirements

1. **Never output debug text before JSON**: Zsh's `local var; var=value` pattern inside loops outputs debug text. Always use `local var="value"` or declare variables outside loops.

2. **Validate JSON output after changes**: After modifying any command that outputs JSON, verify with:
   ```bash
   ./grove <command> --json | python3 -c "import json,sys; json.load(sys.stdin)"
   ```

3. **Test all JSON commands after changes to shared functions**: same check as above, e.g. `./grove repos --json | python3 -c "import json,sys; json.load(sys.stdin)"` — also run for `recent`, `ls <repo>`, `branches <repo>`, `health <repo>`.

4. **Zsh loop variable pattern (IMPORTANT)**:
   ```zsh
   # ❌ WRONG - causes debug output inside loops:
   while IFS= read -r line; do
     local var; var="$(some_command)"  # Outputs "var=..." to stdout!
   done

   # ✓ CORRECT - declare outside loop:
   local var
   while IFS= read -r line; do
     var="$(some_command)"
   done

   # ✓ ALSO CORRECT - combined declaration:
   while IFS= read -r line; do
     local var="$(some_command)"  # OK in if-statements, not in loops
   done
   ```

### Function Placement Guide

**Core Libraries:**
- **Core utilities** (colours, output, notifications) → `lib/01-core.sh`
- **Validation** (input sanitisation, security) → `lib/02-validation.sh`
- **Path generation** (worktree paths, URLs, slugs) → `lib/03-paths.sh`
- **Git operations** (fetch, sync, branch checks) → `lib/04-git.sh`
- **Database operations** (create, backup, remove) → `lib/05-database.sh`
- **Hook execution** → `lib/06-hooks.sh`

**Command Modules:**
- **Worktree lifecycle** (add, rm, move, clone) → `lib/commands/lifecycle.sh`
- **Git operations** (pull, sync, prune, log, diff) → `lib/commands/git-ops.sh`
- **Navigation** (cd, open, edit) → `lib/commands/navigation.sh`
- **Information/reporting** (ls, status, repos, report, health, dashboard) → `lib/commands/info.sh`
- **System maintenance** (doctor, cleanup, unlock, repair, upgrade) → `lib/commands/maintenance.sh`
- **Bulk operations** (build_all, exec_all) → `lib/commands/bulk-ops.sh`
- **Worktree discovery** (recent, clean, info) → `lib/commands/discovery.sh`
- **Configuration** (setup, templates, alias, group) → `lib/commands/config.sh`
- **Laravel-specific** → `lib/commands/laravel.sh`
- **Service management** (services: status/start/stop/restart/add/remove/apps/horizon/logs/doctor — Supervisor, Horizon, Reverb, scheduler) → `lib/commands/services.sh` *(also emits the `services apps --json` and `services status --json` data contracts)*

## Development Commands

```bash
# Run all tests (shellcheck + unit + integration)
./run-tests.sh

# Run specific test categories
./run-tests.sh unit         # Unit tests only
./run-tests.sh integration  # Integration tests only
./run-tests.sh lint         # Shellcheck static analysis only

# Run a specific test file
./run-tests.sh validation.bats

# Install for development (creates symlink, doesn't overwrite installed version)
ln -s "$(pwd)/grove" /usr/local/bin/grove-dev
grove-dev doctor
```

## Architecture

The tool is structured as a single main script (`grove`) **generated from** modular libraries in `lib/`.

**Command pattern:** Each command is a `cmd_<name>()` function. Adding a new command requires:
1. Create `cmd_yourcommand()` function in the appropriate `lib/commands/*.sh` file
2. Add to the `case` statement in `lib/99-main.sh` (main argument parser)
3. Add to `show_help()` in `lib/99-main.sh`
4. Update `_grove` completion script
5. Rebuild with `./build.sh`
6. Document in README.md

## Testing

Uses BATS (Bash Automated Testing System). Test files are in `tests/`:
- `tests/unit/*.bats` - Pure function tests (validation, slugification, JSON escaping)
- `tests/integration/*.bats` - Config parsing, command integration

Run the full suite — count grows constantly. Focuses on security-critical validation, path handling, database naming, hooks, and the .env rewrite used by move/restructure.

## Key Concepts

**Branch slugification:** Branch names like `feature/login-form` become filesystem-safe slugs like `feature-login-form` for directory names.

**Database naming:** `<repo>__<branch_slug>` with MySQL's 64-char limit enforced via hash suffix for long names.

**Protected branches:** `staging`, `main`, `master` require `-f` flag to remove (configurable via `PROTECTED_BRANCHES`).

**Lifecycle hooks:** Scripts in `~/.grove/hooks/{pre-add.d,post-add.d,pre-rm.d,post-rm.d,post-pull.d,post-sync.d}/` run at various points. Repo-specific hooks go in subdirectories matching the repo name.

## Security Considerations

- Input validation prevents path traversal (`../`), git flag injection (`-` prefixed names), and reserved refs (`HEAD`, `refs/`)
- Config files are parsed as key-value pairs with a whitelist, never sourced as shell
- Hooks must be owned by current user and not world-writable
- Template variables only accept `true`/`false` values

## Code Style

- Use existing output helpers: `die()`, `info()`, `ok()`, `warn()`, `dim()`
- JSON output via `--json` flag where applicable
