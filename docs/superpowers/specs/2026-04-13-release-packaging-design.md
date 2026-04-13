# Grove CLI Release Packaging & DevCTL Integration Design

**Date:** 2026-04-13
**Status:** Approved
**Scope:** Prepare Grove CLI for team distribution, integrate DevCTL as optional `grove services` subcommand

---

## Context

Grove CLI is a zsh git worktree manager with Laravel Herd integration. It was recently renamed from `wt` to `grove`. The tool needs packaging for a small dev team (5-10 people, all macOS) who will self-install via `git clone` + `./install.sh`.

A companion tool, DevCTL (currently a standalone 971-line bash script at `~/bin/devctl`), manages Laravel development services (Supervisor, Horizon, Reverb, scheduler). It will be integrated into Grove as an optional `grove services` subcommand, rewritten from bash to zsh.

### Target Audience

- Small immediate dev team (5-10 people)
- All macOS (Apple Silicon and Intel)
- Mix of technical levels - some less technical devs who need a smooth experience
- All use Homebrew
- All work with Laravel + Herd

### Design Principles

- **Idempotent**: If services aren't configured, all hooks bail silently with exit 0
- **Optional**: Service management is opt-in; core worktree management works without it
- **Single install**: One repo to clone, one installer to run
- **Framework-agnostic core**: Service management is a module, not baked into core logic

---

## Part 1: Grove CLI Pre-release Fixes

### 1.1 Stale "wt" References to Fix

| File | Location | Current | Should Be |
|------|----------|---------|-----------|
| `CHANGELOG.md` | Line 3 | `wt Git Worktree Manager` | `grove Git Worktree Manager` |
| `README.md` | Lines ~2495-2496 | `alias wts="grove status..."` / `alias wtl="grove ls..."` | `alias gs="grove status..."` / `alias gl="grove ls..."` |
| `.git/hooks/pre-commit` | Entire file | Referenced `wt` throughout | **DONE** - Fixed 2026-04-13 |

**Note:** Historical changelog entries (v3.x, v4.x sections) referencing old `wt` commands are acceptable as historical record. The header on line 3 is the only one that needs changing.

### 1.2 Installer Fixes (`install.sh`)

**Missing directory creation** - add after existing `~/.grove/hooks/` creation:

```bash
mkdir -p "$HOME/.grove/templates"
mkdir -p "$HOME/.grove/aliases"
mkdir -p "$HOME/.grove/groups"
mkdir -p "$HOME/.grove/services"    # For new services integration
```

**Missing template installation** - the installer creates the hooks directory structure but should also offer to copy example templates from `examples/templates/` to `~/.grove/templates/` during setup.

**PATH verification** - after installation, verify `grove` is accessible before showing the success message. If not, show explicit instructions for the user's shell.

### 1.3 Documentation Fixes

**README.md:**
- Add `post-switch` to the hooks table (~line 467) - it exists in examples but isn't documented in the main hooks table
- Add brief "Migrating from wt" section pointing to `migrate-from-wt.sh`
- Add "Service Management" section (see Part 2)

**Hooks README (`examples/hooks/README.md`):**
- Document `pre-move` and `post-move` hooks (they exist in code but aren't in docs)
- Add note clarifying which hooks have example implementations vs which are just available
- Mark `02-devctl-restart.sh` as being replaced by `grove services` integration

**Missing but lower priority (not blocking release):**
- Troubleshooting guide (`docs/guides/troubleshooting.md`)
- Team onboarding checklist
- Visual diagrams of worktree/Herd directory structure

### 1.4 Hook Cleanup

**`examples/hooks/post-switch.d/02-devctl-restart.sh`** - Replace hardcoded app names with generic `grove services` call:

```zsh
# Before (hardcoded):
case "$GROVE_REPO" in
  knotbook|scooda|modernprintworks)
    app="$GROVE_REPO"
    ;;
  enneagram|enneagram-assessment)
    app="enneagram"
    ;;
  *)
    exit 0
    ;;
esac

# After (generic):
if command -v grove >/dev/null 2>&1; then
    grove services restart "$GROVE_REPO" 2>/dev/null || true
fi
```

---

## Part 2: DevCTL Integration as `grove services`

### 2.1 Architecture

New command module: `lib/commands/services.sh`

This follows Grove's existing module pattern:
- Functions prefixed with `cmd_services_*` or `svc_*` for helpers
- Loaded by `build.sh` into the compiled `grove` binary
- Added to the `case` statement in `lib/99-main.sh`
- Config stored at `~/.grove/services/apps.conf`

### 2.2 Subcommands

| Command | Description | Notes |
|---------|-------------|-------|
| `grove services` | Show status overview (or setup guide if unconfigured) | Default action |
| `grove services status` | Detailed status of all apps, supervisor, Redis | Same as current `devctl status` |
| `grove services start [app]` | Start supervisor/services for app (or all) | |
| `grove services stop [app]` | Stop supervisor/services for app (or all) | |
| `grove services restart [app]` | Restart services for app (or all) | Used by post-switch hook |
| `grove services add <name>` | Register new app (interactive prompts) | Prompts: system name, services, domain |
| `grove services remove <name>` | Unregister app | Confirms before removing |
| `grove services apps` | List registered apps in table format | Supports `--json` flag |
| `grove services logs <type> [app]` | Tail logs (horizon/reverb/scheduler/queue) | |
| `grove services doctor` | Health check (supervisor, Redis, configs) | |
| `grove services install` | Install supervisor configs to Homebrew etc dir | |
| `grove services switch <app> <worktree>` | Atomic worktree switch with service restart | Optional - may stay as hook |

### 2.3 Config Format

**Location:** `~/.grove/services/apps.conf`

**Format:** Same pipe-delimited format as current `~/.devctl/apps.conf`:

```text
# app_name|system_name|services|supervisor_process|domain
knotbook|knotbook|horizon|knotbook-horizon|knotbook.test
scooda|scooda|horizon|scooda-horizon|scooda.test
modernprintworks|modernprintworks|horizon:reverb|modernprintworks:*|modernprintworks.test
enneagram|enneagram-assessment|horizon:reverb|enneagram-assessment:*|enneagram-assessment.test
```

**Fields:**
- `app_name` - Short name used in commands
- `system_name` - Directory name in ~/Herd (bare repo prefix)
- `services` - Comma-separated: `horizon`, `reverb`, `none`
- `supervisor_process` - Pattern for supervisorctl (e.g., `app-horizon` or `app:*`)
- `domain` - Local .test domain

### 2.4 Bash to Zsh Conversion

The current DevCTL (`~/bin/devctl`) is 971 lines of bash. Key conversion notes:

**Mostly compatible** - most constructs work identically in zsh:
- Variables, functions, conditionals, loops
- Command substitution, parameter expansion
- String manipulation, arrays

**Requires attention:**
- `#!/opt/homebrew/bin/bash` -> removed (runs as part of grove, which is `#!/usr/bin/env zsh`)
- Array indexing: bash is 0-based, zsh is 1-based (or use `setopt KSH_ARRAYS` locally)
- `read -p "prompt"` -> `read "?prompt"` in zsh (or use `vared`)
- `declare -A` associative arrays -> `typeset -A` in zsh
- `[[ $x =~ regex ]]` -> works in zsh but capture groups differ (`$BASH_REMATCH` vs `$match`)
- `local -a` arrays -> `local -a` works in zsh too
- `echo -e` -> `print -P` or just `echo` (zsh echo interprets escapes by default)

**Existing Grove patterns to reuse:**
- Output helpers: `die()`, `info()`, `ok()`, `warn()`, `dim()` from `lib/01-core.sh`
- Config loading: extend `load_config()` for services config
- JSON output: follow existing `--json` patterns
- Spinner: use `lib/08-spinner.sh` for long operations
- Validation: use `lib/02-validation.sh` for input sanitisation

### 2.5 Idempotent Behaviour

**When no apps are registered:**
- `grove services` -> prints brief "No apps configured. Run `grove services add <name>` to get started."
- `grove services restart <repo>` (from hook) -> exits 0 silently
- `grove services status` -> shows infrastructure status (supervisor, Redis) but no apps
- All post-switch hooks that call `grove services` -> exit 0 with no output

**When services aren't needed:**
- The module loads (it's compiled into grove) but takes no action unless invoked
- No startup cost, no background processes, no polling
- `grove doctor` can optionally check services health if apps are registered

### 2.6 Migration from Standalone DevCTL

For existing DevCTL users (Danny's machine):

1. Installer detects `~/.devctl/apps.conf` and offers to migrate
2. Copies config to `~/.grove/services/apps.conf`
3. Keeps `~/.devctl/` as backup (doesn't delete)
4. Updates `~/bin/devctl` symlink to point to `grove services` wrapper (or removes it)
5. Migrates any supervisor configs if format changed

---

## Part 3: Installer Updates

### 3.1 Updated Install Flow

```bash
1. Check dependencies (zsh, git, required tools)
2. Check optional dependencies (fzf, jq, mysql, supervisor)
3. Create symlink: /usr/local/bin/grove -> repo/grove
4. Install zsh completions
5. Create ~/.groverc (if not exists) from .groverc.example
6. Create directory structure:
   - ~/.grove/hooks/{pre-add.d,post-add.d,pre-rm.d,post-rm.d,post-pull.d,post-sync.d,post-switch.d}
   - ~/.grove/templates/
   - ~/.grove/aliases/
   - ~/.grove/groups/
   - ~/.grove/services/
7. Offer to install example hooks (existing merge/overwrite/skip flow)
8. Offer to install example templates
9. [NEW] "Would you like to set up service management? [y/N]"
   - If yes: run grove services doctor, guide through grove services add
   - If no: skip, mention they can set up later
10. [NEW] Detect ~/.devctl/apps.conf and offer migration
11. Verify installation: grove --version
12. Show success message with quick-start guide
```

### 3.2 Config Cleanup

The installer should also:
- Detect `WT_HOOKS_ENABLED` in `~/.groverc` and offer to replace with `GROVE_HOOKS_ENABLED`
- Detect `~/.wtrc` and offer migration via `migrate-from-wt.sh`
- Clean up `.wtconfig.bak.*` files in bare repos (with user confirmation)

---

## Part 4: Documentation Updates

### 4.1 README.md Changes

**Add to hooks table (~line 467):**

| Hook | Timing | Use Case |
|------|--------|----------|
| `post-switch` | After `grove switch` | Update current symlink, restart services |
| `pre-move` | Before `grove move` | Validate new path |
| `post-move` | After `grove move` | Update references |

**Add "Service Management" section** (after Hooks section):

- What it does and who needs it
- Quick setup: `grove services add myapp`
- Daily commands: `grove services status`, `grove services restart`
- How it integrates with `grove switch` via hooks
- Configuration reference for `apps.conf` format

**Add "Migrating from wt" section** (brief, after Installation):

- Point to `migrate-from-wt.sh`
- List what it migrates (config, hooks dir, per-repo configs)

### 4.2 Hooks README Updates

- Document pre-move/post-move hooks
- Clarify which hooks have examples vs are just available
- Update devctl-restart hook documentation

### 4.3 Completion Script (`_grove`)

- Add `services` to the main command completions
- Add subcommand completions for `services start|stop|restart|status|add|remove|apps|logs|doctor|install`

---

## Part 5: Testing

### 5.1 Existing Tests

Run `./run-tests.sh` to verify all 168 existing tests pass after changes. No existing tests should break.

### 5.2 New Tests Needed

**Unit tests (`tests/unit/services.bats`):**
- Config parsing (apps.conf format)
- App name validation
- Service type validation
- Empty config handling (idempotent behaviour)

**Integration tests (`tests/integration/services.bats`):**
- `grove services` with no config shows setup guide
- `grove services apps` with empty config shows empty list
- `grove services apps --json` outputs valid JSON
- `grove services add` validates input
- `grove services restart` with unknown app exits 0

### 5.3 Build Verification

After all changes:
```bash
./build.sh
./run-tests.sh
grove doctor
grove services doctor  # New
```

### 5.4 JSON Contract Verification

```bash
grove repos --json | python3 -c "import json,sys; json.load(sys.stdin)"
grove services apps --json | python3 -c "import json,sys; json.load(sys.stdin)"
```

---

## System Details for Implementation

### Current File Locations

| Item | Path |
|------|------|
| Grove CLI source | `/Users/dannyharding/Development/Code/Project/grove-cli/` |
| Built binary | `grove` (root of repo) |
| Lib modules | `lib/*.sh`, `lib/commands/*.sh` |
| Build script | `build.sh` |
| Installer | `install.sh` |
| Example hooks | `examples/hooks/` |
| Example templates | `examples/templates/` |
| Tests | `tests/unit/*.bats`, `tests/integration/*.bats` |
| Completions | `_grove` |
| Global config | `~/.groverc` |
| User hooks | `~/.grove/hooks/` |
| User templates | `~/.grove/templates/` |
| DevCTL binary | `/Users/dannyharding/bin/devctl` (971 lines, bash) |
| DevCTL config | `~/.devctl/apps.conf` |
| Bare repos | `~/Herd/*.git/` |
| Repo configs | `~/Herd/*.git/.groveconfig` |

### Config Hierarchy (implemented in `lib/01-core.sh`)

1. Global: `~/.groverc` (full whitelist)
2. Herd-wide: `$HERD_ROOT/.groveconfig` (full whitelist, optional)
3. Per-repo: `$HERD_ROOT/<repo>.git/.groveconfig` (restricted whitelist)

### Build Process

1. Edit files in `lib/`
2. Run `./build.sh` (concatenates modules in order into `grove`)
3. Run `./run-tests.sh` (shellcheck + unit + integration)
4. The pre-commit hook auto-rebuilds if lib/ is staged

### Key Patterns to Follow

- Commands are `cmd_<name>()` functions
- New commands need: function in `lib/commands/*.sh`, case in `lib/99-main.sh`, help text in `show_help()`, completion in `_grove`
- Use existing output helpers: `die()`, `info()`, `ok()`, `warn()`, `dim()`
- JSON output via `--json` flag, validate with python3
- 2-space indentation, British English in user-facing text
- Variables declared outside loops to avoid debug output (see CLAUDE.md)

---

## Out of Scope

- Homebrew tap or formula (git clone is sufficient for small team)
- Linux/WSL support (all team members on macOS)
- CI/CD pipeline (can be added later)
- Comprehensive troubleshooting guide (nice-to-have, not blocking)
- Visual documentation diagrams (nice-to-have)
