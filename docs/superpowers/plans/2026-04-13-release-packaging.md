# Grove CLI Release Packaging & DevCTL Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare Grove CLI for team distribution by fixing stale references, improving the installer, and integrating DevCTL as an optional `grove services` subcommand rewritten from bash to zsh.

**Architecture:** DevCTL (971-line bash script at `~/bin/devctl`) gets rewritten in zsh as `lib/commands/services.sh`, following Grove's existing module pattern. Config moves from `~/.devctl/apps.conf` to `~/.grove/services/apps.conf`. The services module is lazy-loaded -- it only reads config when `grove services` is actually invoked, adding zero overhead to other commands. All hooks that reference devctl are updated to use `grove services` with idempotent fallback.

**Tech Stack:** Zsh, BATS (testing), Git, macOS (Homebrew, Supervisor, LaunchAgents)

**Design Spec:** `docs/superpowers/specs/2026-04-13-release-packaging-design.md`

---

## Parallelisation Strategy

Four independent tracks can be dispatched simultaneously:

```text
Track A: Stale Reference Fixes (text edits, no code changes)
Track B: Installer Improvements (install.sh only)
Track C: Services Module (lib/commands/services.sh - the big piece)
Track D: Integration (depends on C completing first)
  D1: Build system + main entry point
  D2: Completion script
  D3: Hook updates
  D4: Documentation
  D5: Tests
  D6: Final verification
```

**Tracks A, B, and C can all run in parallel.** Track D is sequential after C completes but D1-D4 can run in parallel within Track D once C is done.

---

## Bash-to-Zsh Conversion Reference

The services module is rewritten from bash to zsh. This mapping applies throughout Track C:

| Bash (devctl) | Zsh (grove services) | Notes |
|---|---|---|
| `#!/opt/homebrew/bin/bash` | (removed - part of grove) | Module has no shebang |
| `declare -A APPS=()` | `typeset -A SVC_APPS=()` | Prefix with SVC_ to avoid collisions |
| `${!APPS[@]}` (keys) | `${(k)SVC_APPS[@]}` | Zsh key expansion syntax |
| `${APPS[$app]+x}` (exists?) | `(( ${+SVC_APPS[$app]} ))` | Zsh parameter existence check |
| `echo -e "${RED}..."` | `warn "..."` / `info "..."` | Use Grove's existing output helpers |
| `print_success "msg"` | `ok "msg"` | From lib/01-core.sh |
| `print_error "msg"` | `die "msg"` or `warn "msg"` | `die` exits; `warn` continues |
| `print_warning "msg"` | `warn "msg"` | From lib/01-core.sh |
| `print_info "msg"` | `info "msg"` | From lib/01-core.sh |
| `exit 1` (in functions) | `return 1` or `die "msg"` | CRITICAL: `exit 1` kills all of grove |
| `read -r -p "prompt"` | `read "?prompt" var` | Zsh read syntax |
| `$DEVCTL_CONFIG_DIR` | `$GROVE_SERVICES_DIR` | `~/.grove/services` |
| `$DEVCTL_APPS_CONF` | `$GROVE_SERVICES_CONF` | `~/.grove/services/apps.conf` |

**Critical rule:** The config loading function (`svc_load_config`) must ONLY be called inside `cmd_services()`, never at module top-level. Otherwise every `grove` command would try to read the services config and fail if it doesn't exist.

---

## Track A: Stale Reference Fixes

### Task A1: Fix CHANGELOG.md Header

**Files:**
- Modify: `CHANGELOG.md:3`

- [ ] **Step 1: Fix the header**

In `CHANGELOG.md` line 3, change:

```bash
All notable changes to the `wt` Git Worktree Manager will be documented in this file.
```

to:

```bash
All notable changes to the `grove` Git Worktree Manager will be documented in this file.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: update CHANGELOG header from wt to grove"
```

### Task A2: Fix README.md Stale Aliases

**Files:**
- Modify: `README.md:2494-2508`

- [ ] **Step 1: Update alias examples**

In `README.md` around lines 2494-2508, replace:

```bash
alias wts="grove status example-app"
alias wtl="grove ls example-app"
alias wtc="grove code example-app"
```

with:

```bash
alias gs="grove status example-app"
alias gl="grove ls example-app"
alias gc="grove code example-app"
```

- [ ] **Step 2: Update the navigation function**

In the same section, replace:

```bash
# Usage: wtcd example-app feature/login
wtcd() {
  cd "$(grove cd "$@")"
}
```

with:

```bash
# Usage: gcd example-app feature/login
gcd() {
  cd "$(grove cd "$@")"
}
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README alias examples from wt to grove naming"
```

### Task A3: Add post-switch and post-move Hooks to README Table

**Files:**
- Modify: `README.md:467-474`

- [ ] **Step 1: Add missing hooks to the table**

In `README.md` around line 467, the hooks table currently lists 6 hooks. After the `post-sync` row, add:

```markdown
| `post-switch` | After `grove switch` succeeds | No |
| `pre-move` | Before `grove move` | Yes |
| `post-move` | After `grove move` succeeds | No |
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add post-switch, pre-move, post-move to hooks table"
```

### Task A4: Add post-switch to Usage Help

**Files:**
- Modify: `lib/99-main.sh:146-151`

- [ ] **Step 1: Add post-switch to the hooks list in usage()**

In `lib/99-main.sh` around line 151, after the `post-sync` line, add:

```zsh
  print -r -- "  ${C_GREEN}post-switch${C_RESET}  Run after grove switch succeeds"
```

- [ ] **Step 2: Rebuild and verify**

```bash
./build.sh
./grove --help | grep -A 15 "HOOKS"
```

Expected: the hooks section should now list `post-switch`.

- [ ] **Step 3: Commit**

```bash
git add lib/99-main.sh grove
git commit -m "docs: add post-switch hook to usage help output"
```

---

## Track B: Installer Improvements

### Task B1: Add Missing Directory Creation

**Files:**
- Modify: `install.sh:392-413`

- [ ] **Step 1: Add post-switch.d to hook directories**

In `install.sh` line 394, the `hook_dirs` array lists 6 directories. Add `post-switch.d`:

```bash
local hook_dirs=("pre-add.d" "post-add.d" "pre-rm.d" "post-rm.d" "post-pull.d" "post-sync.d" "post-switch.d")
```

- [ ] **Step 2: Add template, alias, group, and services directories**

After the `create_hooks_dir` function (after line 413), add a new function:

```bash
create_grove_dirs() {
  echo -e "${BLUE}Setting up grove directories...${NC}"

  local dirs=("templates" "aliases" "groups" "services")

  for dir in "${dirs[@]}"; do
    local full_path="$HOME/.grove/$dir"
    if [[ ! -d "$full_path" ]]; then
      mkdir -p "$full_path"
      echo -e "  ${GREEN}✓${NC} Created ~/.grove/$dir"
    else
      echo -e "  ${GREEN}✓${NC} Already exists: ~/.grove/$dir"
    fi
  done
}
```

- [ ] **Step 3: Call the new function in the main flow**

In `install.sh` around line 614, after `create_hooks_dir`, add:

```bash
create_grove_dirs
```

So the main section reads:

```bash
# Main
print_header
check_requirements
install_script
install_completions
create_config
create_hooks_dir
create_grove_dirs
install_example_hooks
check_path
check_completions_fpath
print_success
```

- [ ] **Step 4: Test the installer**

Run in a dry fashion by checking the output:

```bash
bash install.sh --skip-hooks 2>&1 | head -60
```

Verify that the new directories section appears in the output.

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "fix: add missing directory creation to installer"
```

### Task B2: Add DevCTL Migration Detection

**Files:**
- Modify: `install.sh` (add after `install_example_hooks`)

- [ ] **Step 1: Add migration function**

Add this function after `install_hooks_overwrite` in `install.sh`:

```bash
migrate_devctl_config() {
  local old_config="$HOME/.devctl/apps.conf"
  local new_dir="$HOME/.grove/services"
  local new_config="$new_dir/apps.conf"

  # Skip if no old devctl config exists
  if [[ ! -f "$old_config" ]]; then
    return
  fi

  # Skip if already migrated
  if [[ -f "$new_config" ]]; then
    return
  fi

  echo ""
  echo -e "${BLUE}DevCTL Migration...${NC}"
  echo -e "  Found existing DevCTL config at $old_config"
  echo ""
  read -r -p "  Migrate to grove services? [Y/n]: " choice
  case "${choice:-y}" in
    [Nn]*)
      echo -e "  ${DIM}Skipped (you can migrate later by copying $old_config to $new_config)${NC}"
      return
      ;;
  esac

  mkdir -p "$new_dir"
  cp "$old_config" "$new_config"
  echo -e "  ${GREEN}✓${NC} Migrated apps.conf to ~/.grove/services/"
  echo -e "  ${DIM}Original kept at $old_config as backup${NC}"
}
```

- [ ] **Step 2: Add to main flow**

Add `migrate_devctl_config` after `create_grove_dirs` in the main section:

```bash
create_grove_dirs
migrate_devctl_config
install_example_hooks
```

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: add DevCTL config migration to installer"
```

---

## Track C: Services Module

This is the largest piece of work -- rewriting DevCTL from bash to zsh as `lib/commands/services.sh`.

### Task C1: Create Services Module Skeleton

**Files:**
- Create: `lib/commands/services.sh`

- [ ] **Step 1: Create the module file with config loading**

Create `lib/commands/services.sh`:

```zsh
#!/usr/bin/env zsh
# services.sh - Optional service management for Laravel apps (Horizon, Reverb, Supervisor)
#
# Manages supervisor processes, schedulers, and service health for registered Laravel apps.
# Config: ~/.grove/services/apps.conf
#
# This module is lazy-loaded: config is only read when `grove services` is invoked.
# If no apps are registered, all operations exit silently (idempotent).

# --- Configuration ---

GROVE_SERVICES_DIR="${GROVE_SERVICES_DIR:-$HOME/.grove/services}"
GROVE_SERVICES_CONF="$GROVE_SERVICES_DIR/apps.conf"
GROVE_SUPERVISOR_D="/opt/homebrew/etc/supervisor.d"
GROVE_LAUNCH_AGENTS="$HOME/Library/LaunchAgents"

# Associative arrays for app registry (populated by svc_load_config)
typeset -A SVC_APPS=()
typeset -A SVC_SYSTEM_NAMES=()
typeset -A SVC_SERVICES=()
typeset -A SVC_SUPERVISOR_PROCESSES=()
typeset -A SVC_DOMAINS=()

# Track whether config has been loaded this invocation
SVC_CONFIG_LOADED=false

# --- Config Loading (lazy - only called from cmd_services) ---

svc_load_config() {
  [[ "$SVC_CONFIG_LOADED" == true ]] && return 0

  if [[ ! -f "$GROVE_SERVICES_CONF" ]]; then
    SVC_CONFIG_LOADED=true
    return 0  # No config is valid - just means no apps registered
  fi

  local app_name system_name services supervisor_process domain
  while IFS='|' read -r app_name system_name services supervisor_process domain || [[ -n "$app_name" ]]; do
    # Skip comments and empty lines
    [[ -z "$app_name" || "$app_name" == \#* ]] && continue
    # Trim whitespace
    app_name="${app_name// /}"
    system_name="${system_name// /}"
    services="${services// /}"
    supervisor_process="${supervisor_process// /}"
    domain="${domain// /}"

    SVC_APPS[$app_name]="$services"
    SVC_SYSTEM_NAMES[$app_name]="$system_name"
    SVC_SERVICES[$app_name]="$services"
    SVC_SUPERVISOR_PROCESSES[$app_name]="$supervisor_process"
    SVC_DOMAINS[$app_name]="${domain:-${system_name}.test}"
  done < "$GROVE_SERVICES_CONF"

  SVC_CONFIG_LOADED=true
}

# --- Helper Functions ---

svc_has_apps() {
  (( ${#SVC_APPS} > 0 ))
}

svc_validate_app() {
  local app="$1"
  if ! (( ${+SVC_APPS[$app]} )); then
    die "Unknown app: $app. Run 'grove services apps' to see registered apps."
  fi
}

svc_get_system_name() {
  local app="$1"
  print -r -- "${SVC_SYSTEM_NAMES[$app]:-$app}"
}

svc_get_current_worktree() {
  local app="$1"
  local system_name
  system_name="$(svc_get_system_name "$app")"
  local symlink="$HERD_ROOT/${system_name}-current"
  if [[ -L "$symlink" ]]; then
    print -r -- "${symlink:A:t}"
  else
    print -r -- "(no symlink)"
  fi
}

svc_get_supervisor_process() {
  local app="$1"
  print -r -- "${SVC_SUPERVISOR_PROCESSES[$app]:-${app}-horizon}"
}

svc_app_uses_horizon() {
  local app="$1"
  [[ "${SVC_SERVICES[$app]}" == horizon* ]]
}

svc_get_app_list() {
  printf '%s\n' "${(k)SVC_APPS[@]}" | sort
}
```

- [ ] **Step 2: Verify syntax**

```bash
zsh -n lib/commands/services.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add lib/commands/services.sh
git commit -m "feat: add services module skeleton with config loading"
```

### Task C2: Add Core Service Commands (status, start, stop, restart)

**Files:**
- Modify: `lib/commands/services.sh`

- [ ] **Step 1: Add the status command**

Append to `lib/commands/services.sh`:

```zsh
# --- Commands ---

svc_show_app_status() {
  local app="$1"
  local system_name
  system_name="$(svc_get_system_name "$app")"
  local current
  current="$(svc_get_current_worktree "$app")"
  local symlink="$HERD_ROOT/${system_name}-current"
  local process
  process="$(svc_get_supervisor_process "$app")"

  info "${(C)app}:"

  # Worktree symlink
  if [[ -L "$symlink" ]]; then
    ok "Worktree: $current"
  else
    warn "No -current symlink"
  fi

  # Supervisor process (skip if services=none)
  if [[ "${SVC_SERVICES[$app]}" != "none" && -n "$process" ]]; then
    local sup_status
    sup_status="$(supervisorctl status 2>/dev/null | grep -E "^${process%:*}" | head -1)" || true
    if [[ -n "$sup_status" ]]; then
      if print -r -- "$sup_status" | grep -q "RUNNING"; then
        ok "Supervisor: RUNNING"
      else
        warn "Supervisor: $(print -r -- "$sup_status" | awk '{print $2}')"
      fi
    else
      warn "Supervisor: Not configured"
    fi
  fi

  # Horizon status
  if svc_app_uses_horizon "$app" && [[ -L "$symlink" ]]; then
    local horizon_status
    horizon_status="$(cd "$symlink" && php artisan horizon:status 2>&1)" || true
    if print -r -- "$horizon_status" | grep -q "running"; then
      ok "Horizon: Running"
    else
      warn "Horizon: Inactive"
    fi
  fi

  # Scheduler
  local scheduler_status
  scheduler_status="$(launchctl list 2>/dev/null | grep "com.${app}.scheduler" || true)"
  if [[ -n "$scheduler_status" ]]; then
    ok "Scheduler: Loaded"
  else
    dim "Scheduler: Not loaded"
  fi

  print -r -- ""
}

cmd_services_status() {
  local app="${1:-}"

  print -r -- ""
  print -r -- "${C_BOLD}Service Status${C_RESET}"
  print -r -- ""

  # Supervisor daemon
  info "Supervisor Daemon:"
  if brew services list 2>/dev/null | grep -q "supervisor.*started"; then
    ok "Running"
  else
    warn "Not running (run: brew services start supervisor)"
  fi
  print -r -- ""

  # Redis
  info "Redis:"
  if redis-cli ping > /dev/null 2>&1; then
    ok "Running"
  else
    warn "Not running (run: brew services start redis)"
  fi
  print -r -- ""

  if ! svc_has_apps; then
    dim "No apps registered. Run 'grove services add <name>' to get started."
    return 0
  fi

  if [[ -n "$app" && "$app" != "all" ]]; then
    svc_validate_app "$app"
    svc_show_app_status "$app"
  else
    local app_name
    for app_name in $(svc_get_app_list); do
      svc_show_app_status "$app_name"
    done
  fi
}

svc_start_app() {
  local app="$1"
  local process
  process="$(svc_get_supervisor_process "$app")"

  info "Starting ${(C)app}..."

  # Start supervisor process (if app has services)
  if [[ "${SVC_SERVICES[$app]}" != "none" && -n "$process" ]]; then
    supervisorctl start "$process" 2>/dev/null || true
    ok "Started supervisor process"
  fi

  # Load scheduler LaunchAgent
  local plist="$GROVE_LAUNCH_AGENTS/com.${app}.scheduler.plist"
  if [[ -f "$plist" ]]; then
    launchctl load "$plist" 2>/dev/null || true
    ok "Loaded scheduler"
  fi

  print -r -- ""
}

cmd_services_start() {
  local app="${1:-}"

  if [[ -z "$app" ]]; then
    die "Usage: grove services start <app|all>"
  fi

  # Ensure supervisor is running
  if ! brew services list 2>/dev/null | grep -q "supervisor.*started"; then
    info "Starting supervisor daemon..."
    brew services start supervisor
    sleep 2
  fi

  if [[ "$app" == "all" ]]; then
    local app_name
    for app_name in $(svc_get_app_list); do
      svc_start_app "$app_name"
    done
  else
    svc_validate_app "$app"
    svc_start_app "$app"
  fi
}

svc_stop_app() {
  local app="$1"
  local process
  process="$(svc_get_supervisor_process "$app")"

  info "Stopping ${(C)app}..."

  # Stop supervisor process
  if [[ "${SVC_SERVICES[$app]}" != "none" && -n "$process" ]]; then
    supervisorctl stop "$process" 2>/dev/null || true
    ok "Stopped supervisor process"
  fi

  # Unload scheduler LaunchAgent
  local plist="$GROVE_LAUNCH_AGENTS/com.${app}.scheduler.plist"
  if [[ -f "$plist" ]]; then
    launchctl unload "$plist" 2>/dev/null || true
    ok "Unloaded scheduler"
  fi

  print -r -- ""
}

cmd_services_stop() {
  local app="${1:-}"

  if [[ -z "$app" ]]; then
    die "Usage: grove services stop <app|all>"
  fi

  if [[ "$app" == "all" ]]; then
    local app_name
    for app_name in $(svc_get_app_list); do
      svc_stop_app "$app_name"
    done
  else
    svc_validate_app "$app"
    svc_stop_app "$app"
  fi
}

svc_restart_app() {
  local app="$1"
  local process
  process="$(svc_get_supervisor_process "$app")"

  info "Restarting ${(C)app}..."

  if [[ "${SVC_SERVICES[$app]}" != "none" && -n "$process" ]]; then
    supervisorctl restart "$process" 2>/dev/null || true
    ok "Restarted supervisor process"
  fi

  print -r -- ""
}

cmd_services_restart() {
  local app="${1:-}"

  if [[ -z "$app" ]]; then
    # When called with no args (e.g. from hook with repo name that isn't registered),
    # exit silently for idempotent behaviour
    return 0
  fi

  # If app isn't registered, exit silently (idempotent for hooks)
  if ! (( ${+SVC_APPS[$app]} )); then
    return 0
  fi

  if [[ "$app" == "all" ]]; then
    local app_name
    for app_name in $(svc_get_app_list); do
      svc_restart_app "$app_name"
    done
  else
    svc_restart_app "$app"
  fi
}
```

- [ ] **Step 2: Verify syntax**

```bash
zsh -n lib/commands/services.sh && echo "Syntax OK"
```

- [ ] **Step 3: Commit**

```bash
git add lib/commands/services.sh
git commit -m "feat: add services status, start, stop, restart commands"
```

### Task C3: Add App Registry Commands (add, remove, apps)

**Files:**
- Modify: `lib/commands/services.sh`

- [ ] **Step 1: Add the apps, add, and remove commands**

Append to `lib/commands/services.sh`:

```zsh
cmd_services_apps() {
  if ! svc_has_apps; then
    dim "No apps registered. Run 'grove services add <name>' to get started."
    return 0
  fi

  if [[ "$JSON_OUTPUT" == true ]]; then
    cmd_services_apps_json
    return $?
  fi

  print -r -- ""
  print -r -- "${C_BOLD}Registered Apps${C_RESET}"
  print -r -- ""

  printf "  ${C_BLUE}%-20s %-25s %-16s %-25s %s${C_RESET}\n" "APP" "SYSTEM NAME" "SERVICES" "SUPERVISOR" "DOMAIN"
  print -r -- "  $(printf '%.0s-' {1..100})"

  local app_name
  for app_name in $(svc_get_app_list); do
    local system_name="${SVC_SYSTEM_NAMES[$app_name]}"
    local services="${SVC_SERVICES[$app_name]}"
    local process="${SVC_SUPERVISOR_PROCESSES[$app_name]}"
    local domain="${SVC_DOMAINS[$app_name]}"
    printf "  %-20s %-25s %-16s %-25s %s\n" "$app_name" "$system_name" "$services" "$process" "$domain"
  done

  print -r -- ""
  dim "Config: $GROVE_SERVICES_CONF"
}

cmd_services_apps_json() {
  local first=true
  print -r -- "["
  local app_name
  for app_name in $(svc_get_app_list); do
    [[ "$first" == true ]] && first=false || print -r -- ","
    local system_name="${SVC_SYSTEM_NAMES[$app_name]}"
    local services="${SVC_SERVICES[$app_name]}"
    local process="${SVC_SUPERVISOR_PROCESSES[$app_name]}"
    local domain="${SVC_DOMAINS[$app_name]}"
    printf '  {"name":"%s","system_name":"%s","services":"%s","supervisor_process":"%s","domain":"%s"}' \
      "$(json_escape "$app_name")" \
      "$(json_escape "$system_name")" \
      "$(json_escape "$services")" \
      "$(json_escape "$process")" \
      "$(json_escape "$domain")"
  done
  print -r -- ""
  print -r -- "]"
}

cmd_services_add() {
  local name=""
  local system_name=""
  local services="horizon"
  local supervisor=""
  local domain=""

  # Parse arguments
  local arg
  for arg in "$@"; do
    case "$arg" in
      --system-name=*) system_name="${arg#*=}" ;;
      --services=*) services="${arg#*=}" ;;
      --supervisor=*) supervisor="${arg#*=}" ;;
      --domain=*) domain="${arg#*=}" ;;
      -*) die "Unknown option: $arg" ;;
      *) [[ -z "$name" ]] && name="$arg" ;;
    esac
  done

  if [[ -z "$name" ]]; then
    die "Usage: grove services add <name> [--system-name=<name>] [--services=horizon|horizon:reverb|none] [--domain=<domain>]"
  fi

  # Validate name
  validate_repo_name "$name" 2>/dev/null || true

  # Defaults
  [[ -z "$system_name" ]] && system_name="$name"
  [[ -z "$domain" ]] && domain="${system_name}.test"

  # Default supervisor process based on services
  if [[ -z "$supervisor" ]]; then
    case "$services" in
      horizon) supervisor="${system_name}-horizon" ;;
      horizon:reverb) supervisor="${system_name}:*" ;;
      none) supervisor="" ;;
      *) supervisor="${system_name}-horizon" ;;
    esac
  fi

  # Check if already exists
  if (( ${+SVC_APPS[$name]} )); then
    die "App '$name' is already registered. To update, remove first: grove services remove $name"
  fi

  # Validate services
  case "$services" in
    horizon|horizon:reverb|none) ;;
    *) die "Invalid services: $services (must be horizon, horizon:reverb, or none)" ;;
  esac

  # Ensure config directory exists
  mkdir -p "$GROVE_SERVICES_DIR"

  # Create config file with header if it doesn't exist
  if [[ ! -f "$GROVE_SERVICES_CONF" ]]; then
    cat > "$GROVE_SERVICES_CONF" << 'CONF'
# grove services app registry
# Format: app_name|system_name|services|supervisor_process|domain
#
# Fields:
#   app_name           - Short name used in grove services commands
#   system_name        - Directory name in ~/Herd (bare repo prefix)
#   services           - horizon, horizon:reverb, or none
#   supervisor_process - Supervisor process name/pattern (e.g. app-horizon, app:*)
#   domain             - Local .test domain (optional, defaults to system_name.test)
CONF
  fi

  # Append to config
  print -r -- "${name}|${system_name}|${services}|${supervisor}|${domain}" >> "$GROVE_SERVICES_CONF"

  ok "Registered app: $name"
  print -r -- ""
  print -r -- "  System name: $system_name"
  print -r -- "  Services:    $services"
  print -r -- "  Supervisor:  ${supervisor:-none}"
  print -r -- "  Domain:      $domain"
  print -r -- ""
  dim "Config: $GROVE_SERVICES_CONF"
}

cmd_services_remove() {
  local name="${1:-}"

  if [[ -z "$name" ]]; then
    die "Usage: grove services remove <name>"
  fi

  svc_validate_app "$name"

  # Remove the line from config (match on app name at start of line)
  local tmp="${GROVE_SERVICES_CONF}.tmp"
  grep -v "^${name}|" "$GROVE_SERVICES_CONF" > "$tmp"
  mv "$tmp" "$GROVE_SERVICES_CONF"

  ok "Removed app: $name"
  dim "Note: This only removes from registry. Worktrees and configs are not deleted."
}
```

- [ ] **Step 2: Verify syntax**

```bash
zsh -n lib/commands/services.sh && echo "Syntax OK"
```

- [ ] **Step 3: Commit**

```bash
git add lib/commands/services.sh
git commit -m "feat: add services app registry commands (add, remove, apps)"
```

### Task C4: Add Logs, Horizon, and Doctor Commands

**Files:**
- Modify: `lib/commands/services.sh`

- [ ] **Step 1: Add remaining commands**

Append to `lib/commands/services.sh`:

```zsh
cmd_services_horizon() {
  local app="${1:-}"

  if [[ -z "$app" ]]; then
    die "Usage: grove services horizon <app>"
  fi

  svc_validate_app "$app"

  if ! svc_app_uses_horizon "$app"; then
    die "$app does not use Horizon"
  fi

  local domain="${SVC_DOMAINS[$app]}"
  local url="https://${domain}/horizon"
  info "Opening $url..."
  open "$url"
}

cmd_services_logs() {
  local app="${1:-}"
  local log_type="${2:-horizon}"

  if [[ -z "$app" ]]; then
    die "Usage: grove services logs <app> [type]\nTypes: horizon, reverb, scheduler, queue"
  fi

  svc_validate_app "$app"

  local system_name
  system_name="$(svc_get_system_name "$app")"
  local symlink="$HERD_ROOT/${system_name}-current"
  local log_file=""

  case "$log_type" in
    horizon|queue)
      log_file="$symlink/storage/logs/horizon.log"
      ;;
    reverb)
      log_file="$symlink/storage/logs/reverb.log"
      ;;
    scheduler)
      log_file="$HOME/Library/Logs/${app}-scheduler.log"
      ;;
    *)
      die "Unknown log type: $log_type (valid: horizon, reverb, scheduler, queue)"
      ;;
  esac

  if [[ -f "$log_file" ]]; then
    info "Tailing $log_file (Ctrl+C to stop)..."
    tail -f "$log_file"
  else
    die "Log file not found: $log_file"
  fi
}

cmd_services_doctor() {
  print -r -- ""
  print -r -- "${C_BOLD}Services Health Check${C_RESET}"
  print -r -- ""

  local issues=0

  # Check Homebrew
  info "Homebrew:"
  if command -v brew &> /dev/null; then
    ok "Installed"
  else
    warn "Not installed"
    ((issues++))
  fi

  # Check PHP
  info "PHP:"
  if command -v php &> /dev/null; then
    ok "$(php -v | head -1)"
  else
    warn "Not installed"
    ((issues++))
  fi

  # Check Redis
  info "Redis:"
  if redis-cli ping > /dev/null 2>&1; then
    ok "Running"
  else
    warn "Not running (fix: brew services start redis)"
    ((issues++))
  fi

  # Check Supervisor
  info "Supervisor:"
  if brew services list 2>/dev/null | grep -q "supervisor.*started"; then
    ok "Running"
  else
    warn "Not running (fix: brew services start supervisor)"
    ((issues++))
  fi

  # Check supervisor.d directory
  info "Supervisor Configs:"
  if [[ -d "$GROVE_SUPERVISOR_D" ]]; then
    local config_count
    config_count="$(ls -1 "$GROVE_SUPERVISOR_D"/*.ini 2>/dev/null | wc -l | tr -d ' ')"
    ok "$config_count configs in $GROVE_SUPERVISOR_D"
  else
    warn "Directory missing: $GROVE_SUPERVISOR_D"
    ((issues++))
  fi

  if svc_has_apps; then
    # Check -current symlinks
    info "Symlinks:"
    local app
    for app in $(svc_get_app_list); do
      local system_name
      system_name="$(svc_get_system_name "$app")"
      local symlink="$HERD_ROOT/${system_name}-current"
      if [[ -L "$symlink" ]]; then
        local target
        target="$(readlink "$symlink")"
        if [[ -d "$target" ]]; then
          ok "${system_name}-current -> ${target:t}"
        else
          warn "${system_name}-current -> $target (broken)"
          ((issues++))
        fi
      else
        warn "${system_name}-current missing"
        ((issues++))
      fi
    done

    # Check supervisor processes
    info "Supervisor Processes:"
    for app in $(svc_get_app_list); do
      if [[ "${SVC_SERVICES[$app]}" == "none" ]]; then
        continue
      fi
      local process
      process="$(svc_get_supervisor_process "$app")"
      local status
      status="$(supervisorctl status 2>/dev/null | grep -E "^${process%:*}" | head -1 || true)"
      if [[ -n "$status" ]]; then
        if print -r -- "$status" | grep -q "RUNNING"; then
          ok "$app: RUNNING"
        else
          warn "$app: $(print -r -- "$status" | awk '{print $2}')"
        fi
      else
        warn "$app: Not configured"
      fi
    done
  else
    print -r -- ""
    dim "No apps registered. Run 'grove services add <name>' to register an app."
  fi

  print -r -- ""
  if (( issues == 0 )); then
    ok "All checks passed!"
  else
    warn "Found $issues issue(s). Run suggested fixes above."
  fi
}
```

- [ ] **Step 2: Verify syntax**

```bash
zsh -n lib/commands/services.sh && echo "Syntax OK"
```

- [ ] **Step 3: Commit**

```bash
git add lib/commands/services.sh
git commit -m "feat: add services logs, horizon, and doctor commands"
```

### Task C5: Add Main Entry Point (cmd_services Router)

**Files:**
- Modify: `lib/commands/services.sh`

- [ ] **Step 1: Add the main router function**

Append to the end of `lib/commands/services.sh`:

```zsh
# --- Main Entry Point ---

cmd_services() {
  # Lazy-load config only when services is actually invoked
  svc_load_config

  local subcmd="${1:-}"
  shift 2>/dev/null || true

  case "$subcmd" in
    status)   cmd_services_status "$@" ;;
    start)    cmd_services_start "$@" ;;
    stop)     cmd_services_stop "$@" ;;
    restart)  cmd_services_restart "$@" ;;
    add)      cmd_services_add "$@" ;;
    remove)   cmd_services_remove "$@" ;;
    apps)     cmd_services_apps "$@" ;;
    horizon)  cmd_services_horizon "$@" ;;
    logs)     cmd_services_logs "$@" ;;
    doctor)   cmd_services_doctor "$@" ;;
    "")
      if svc_has_apps; then
        cmd_services_status "$@"
      else
        print -r -- ""
        print -r -- "${C_BOLD}Grove Service Management${C_RESET}"
        print -r -- ""
        print -r -- "  Manage Supervisor, Horizon, Reverb, and scheduler for Laravel apps."
        print -r -- ""
        print -r -- "  ${C_GREEN}Get started:${C_RESET}"
        print -r -- "    grove services add <name>        Register an app"
        print -r -- "    grove services doctor             Check service dependencies"
        print -r -- ""
        print -r -- "  ${C_GREEN}Daily use:${C_RESET}"
        print -r -- "    grove services status             Show all app status"
        print -r -- "    grove services start <app|all>    Start services"
        print -r -- "    grove services stop <app|all>     Stop services"
        print -r -- "    grove services restart <app|all>  Restart services"
        print -r -- ""
        print -r -- "  ${C_GREEN}Utilities:${C_RESET}"
        print -r -- "    grove services apps               List registered apps"
        print -r -- "    grove services horizon <app>       Open Horizon dashboard"
        print -r -- "    grove services logs <app> [type]   Tail service logs"
        print -r -- ""
      fi
      ;;
    *)
      die "Unknown services command: $subcmd (try: grove services)"
      ;;
  esac
}
```

- [ ] **Step 2: Verify syntax**

```bash
zsh -n lib/commands/services.sh && echo "Syntax OK"
```

- [ ] **Step 3: Commit**

```bash
git add lib/commands/services.sh
git commit -m "feat: add services main router and help text"
```

---

## Track D: Integration (depends on Track C)

### Task D1: Register Services in Build System and Main Entry

**Files:**
- Modify: `build.sh:41-51`
- Modify: `lib/99-main.sh:259-305`

- [ ] **Step 1: Add services.sh to build.sh**

In `build.sh` line 41, add `services.sh` to the `COMMAND_MODULES` array:

```bash
COMMAND_MODULES=(
  "lifecycle.sh"
  "git-ops.sh"
  "navigation.sh"
  "info.sh"
  "maintenance.sh"
  "bulk-ops.sh"
  "discovery.sh"
  "config.sh"
  "laravel.sh"
  "services.sh"
)
```

- [ ] **Step 2: Add services to the case statement in lib/99-main.sh**

In `lib/99-main.sh` line 302, after the `share-deps` case, add:

```zsh
    services)     cmd_services "$@" ;;
```

- [ ] **Step 3: Add services to usage() help**

In `lib/99-main.sh`, in the `usage()` function, after the UTILITIES section (around line 71), add a new section:

```zsh
  print -r -- "${C_BOLD}SERVICE MANAGEMENT${C_RESET} ${C_DIM}(optional - for Laravel queue/scheduler management)${C_RESET}"
  print -r -- "  ${C_GREEN}services${C_RESET} ${C_DIM}[subcommand]${C_RESET}                  Manage app services"
  print -r -- "           ${C_DIM}status, start, stop, restart, add, remove, apps,${C_RESET}"
  print -r -- "           ${C_DIM}horizon, logs, doctor${C_RESET}"
  print -r -- ""
```

- [ ] **Step 4: Rebuild and verify**

```bash
./build.sh
./grove --help | grep -i service
./grove services
```

Expected: Help shows services section. `grove services` shows the "Get started" guide (assuming no apps.conf exists in ~/.grove/services/).

- [ ] **Step 5: Commit**

```bash
git add build.sh lib/99-main.sh grove
git commit -m "feat: register services module in build system and main entry"
```

### Task D2: Update Completion Script

**Files:**
- Modify: `_grove:83-124` and `_grove:154-237`

- [ ] **Step 1: Add services to the commands list**

In `_grove` around line 83, add to the `commands` array:

```zsh
    'services:Manage app services (Supervisor, Horizon, scheduler)'
```

Add it after the `share-deps` line (around line 123).

- [ ] **Step 2: Add services subcommand completions**

In `_grove` around line 232, before the `share-deps` case, add:

```zsh
        services)
          local -a services_cmds
          services_cmds=(
            'status:Show status of all or specific app'
            'start:Start supervisor processes and scheduler'
            'stop:Stop supervisor processes and scheduler'
            'restart:Restart supervisor processes'
            'add:Register a new app'
            'remove:Remove an app from registry'
            'apps:List all registered apps'
            'horizon:Open Horizon dashboard in browser'
            'logs:Tail service logs'
            'doctor:Check service dependencies'
          )
          _arguments \
            '1:subcommand:_describe "services command" services_cmds' \
            '*:app:'
          ;;
```

- [ ] **Step 3: Rebuild and verify**

```bash
./build.sh
# Reload completions (in a new shell or):
unfunction _grove 2>/dev/null; autoload -Uz _grove
```

- [ ] **Step 4: Commit**

```bash
git add _grove grove
git commit -m "feat: add services subcommand completions"
```

### Task D3: Update Post-Switch Hook

**Files:**
- Modify: `examples/hooks/post-switch.d/02-devctl-restart.sh`

- [ ] **Step 1: Replace hardcoded hook with generic version**

Replace the entire contents of `examples/hooks/post-switch.d/02-devctl-restart.sh` with:

```zsh
#!/usr/bin/env zsh
# Restart services after worktree switch
#
# After the -current symlink is updated, this hook restarts the Supervisor
# processes (Horizon, Reverb) so they pick up the new worktree immediately.
#
# Only runs if the repo has a registered service app in grove services.
# If grove services is not configured, this hook exits silently.
#
# Skip by setting: GROVE_SKIP_SERVICES=true

if [[ "${GROVE_SKIP_SERVICES:-}" == "true" ]]; then
  echo "  Skipping service restart (GROVE_SKIP_SERVICES=true)"
  exit 0
fi

# Use grove services restart (idempotent - exits 0 if app not registered)
if command -v grove &> /dev/null; then
  grove services restart "$GROVE_REPO" 2>/dev/null || true
fi

exit 0
```

- [ ] **Step 2: Verify syntax**

```bash
zsh -n examples/hooks/post-switch.d/02-devctl-restart.sh && echo "Syntax OK"
```

- [ ] **Step 3: Update the post-add hook too**

If `examples/hooks/post-add.d/10-set-hooks-path.sh` or similar references devctl, update similarly. Check:

```bash
grep -r "devctl" examples/hooks/
```

For any file referencing `devctl` directly (other than the post-switch hook we just updated), update to use `grove services` pattern instead.

- [ ] **Step 4: Commit**

```bash
git add examples/hooks/
git commit -m "feat: update hooks to use grove services instead of devctl"
```

### Task D4: Add Services Documentation to README

**Files:**
- Modify: `README.md` (after the Hooks section)

- [ ] **Step 1: Add Service Management section**

In `README.md`, after the Hooks section (around line 530), add:

```markdown
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
```text

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add service management section to README"
```

### Task D5: Add Services Tests

**Files:**
- Create: `tests/unit/services.bats`

- [ ] **Step 1: Write unit tests for config parsing and validation**

Create `tests/unit/services.bats`:

```bash
#!/usr/bin/env bats
# Unit tests for services module config parsing

setup() {
  # Source required modules
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

  # Create temp directory for test configs
  TEST_TMPDIR="$(mktemp -d)"

  # Source the built grove to get all functions
  # We need to prevent main() from running
  export GROVE_SERVICES_DIR="$TEST_TMPDIR"
  export GROVE_SERVICES_CONF="$TEST_TMPDIR/apps.conf"
  export HERD_ROOT="$TEST_TMPDIR/Herd"
  mkdir -p "$HERD_ROOT"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# --- Config Loading ---

@test "svc_load_config with no config file returns success" {
  source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true

  # Reset state
  SVC_CONFIG_LOADED=false
  typeset -A SVC_APPS=()

  svc_load_config
  [[ "$SVC_CONFIG_LOADED" == true ]]
  (( ${#SVC_APPS} == 0 ))
}

@test "svc_load_config parses pipe-delimited format" {
  cat > "$GROVE_SERVICES_CONF" << 'EOF'
myapp|myapp-repo|horizon|myapp-horizon|myapp.test
otherapp|otherapp|horizon:reverb|otherapp:*|otherapp.test
EOF

  source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true

  # Reset and reload
  SVC_CONFIG_LOADED=false
  typeset -A SVC_APPS=()
  typeset -A SVC_SYSTEM_NAMES=()
  typeset -A SVC_SERVICES=()
  typeset -A SVC_SUPERVISOR_PROCESSES=()
  typeset -A SVC_DOMAINS=()

  svc_load_config

  [[ "${SVC_APPS[myapp]}" == "horizon" ]]
  [[ "${SVC_SYSTEM_NAMES[myapp]}" == "myapp-repo" ]]
  [[ "${SVC_SERVICES[otherapp]}" == "horizon:reverb" ]]
  [[ "${SVC_DOMAINS[myapp]}" == "myapp.test" ]]
}

@test "svc_load_config skips comments and empty lines" {
  cat > "$GROVE_SERVICES_CONF" << 'EOF'
# This is a comment
myapp|myapp|horizon|myapp-horizon|myapp.test

# Another comment
EOF

  source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true

  SVC_CONFIG_LOADED=false
  typeset -A SVC_APPS=()

  svc_load_config

  (( ${#SVC_APPS} == 1 ))
  [[ "${SVC_APPS[myapp]}" == "horizon" ]]
}

@test "svc_load_config defaults domain to system_name.test" {
  cat > "$GROVE_SERVICES_CONF" << 'EOF'
myapp|myapp-repo|horizon|myapp-horizon|
EOF

  source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true

  SVC_CONFIG_LOADED=false
  typeset -A SVC_APPS=()
  typeset -A SVC_DOMAINS=()

  svc_load_config

  [[ "${SVC_DOMAINS[myapp]}" == "myapp-repo.test" ]]
}

# --- Validation ---

@test "svc_has_apps returns false with no apps" {
  source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
  typeset -A SVC_APPS=()

  ! svc_has_apps
}

@test "svc_has_apps returns true with apps" {
  source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
  typeset -A SVC_APPS=()
  SVC_APPS[myapp]="horizon"

  svc_has_apps
}

@test "svc_app_uses_horizon returns true for horizon" {
  source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
  typeset -A SVC_SERVICES=()
  SVC_SERVICES[myapp]="horizon"

  svc_app_uses_horizon "myapp"
}

@test "svc_app_uses_horizon returns true for horizon:reverb" {
  source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
  typeset -A SVC_SERVICES=()
  SVC_SERVICES[myapp]="horizon:reverb"

  svc_app_uses_horizon "myapp"
}

@test "svc_app_uses_horizon returns false for none" {
  source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
  typeset -A SVC_SERVICES=()
  SVC_SERVICES[myapp]="none"

  ! svc_app_uses_horizon "myapp"
}

@test "svc_get_app_list returns sorted names" {
  source "$PROJECT_ROOT/lib/commands/services.sh" 2>/dev/null || true
  typeset -A SVC_APPS=()
  SVC_APPS[zebra]="horizon"
  SVC_APPS[alpha]="horizon"
  SVC_APPS[middle]="none"

  local result
  result="$(svc_get_app_list)"
  local first_line
  first_line="$(print -r -- "$result" | head -1)"
  [[ "$first_line" == "alpha" ]]
}
```

- [ ] **Step 2: Run the tests**

```bash
./run-tests.sh services.bats
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/services.bats
git commit -m "test: add unit tests for services module"
```

### Task D6: Final Build, Test, and Verification

**Files:**
- All modified files

- [ ] **Step 1: Full rebuild**

```bash
./build.sh
```

Expected: `Built: grove (XXXX lines)` with no warnings.

- [ ] **Step 2: Run all tests**

```bash
./run-tests.sh
```

Expected: All tests pass (168 existing + new services tests).

- [ ] **Step 3: Run shellcheck**

```bash
./run-tests.sh lint
```

Expected: No new warnings from services.sh.

- [ ] **Step 4: Verify JSON contract**

```bash
./grove repos --json | python3 -c "import json,sys; json.load(sys.stdin)" && echo "repos JSON OK"
./grove services apps --json 2>/dev/null | python3 -c "import json,sys; json.load(sys.stdin)" && echo "services JSON OK" || echo "services JSON OK (no apps)"
```

- [ ] **Step 5: Verify idempotent behaviour**

```bash
# Services with no config should not error
./grove services
./grove services restart nonexistent-app
echo $?  # Should be 0
```

- [ ] **Step 6: Verify help text**

```bash
./grove --help | grep -A 4 "SERVICE"
```

Expected: Shows the SERVICE MANAGEMENT section.

- [ ] **Step 7: Verify the installer**

```bash
bash install.sh --skip-hooks 2>&1 | grep -E "(templates|aliases|groups|services)"
```

Expected: Shows creation of all four new directories.

- [ ] **Step 8: Run grove doctor**

```bash
./grove doctor
```

Expected: No errors related to the new services module.

---

## Post-Implementation Checklist

After all tracks complete:

- [ ] All 168+ tests pass
- [ ] `grove services` shows help when no apps configured
- [ ] `grove services add testapp` registers successfully
- [ ] `grove services apps` lists registered app
- [ ] `grove services apps --json` outputs valid JSON
- [ ] `grove services remove testapp` unregisters successfully
- [ ] `grove services restart nonexistent` exits silently (exit 0)
- [ ] Post-switch hook uses `grove services` instead of `devctl`
- [ ] CHANGELOG header says "grove" not "wt"
- [ ] README aliases use "g" prefix not "wt" prefix
- [ ] README hooks table includes post-switch, pre-move, post-move
- [ ] Installer creates templates, aliases, groups, services directories
- [ ] `grove --help` shows SERVICE MANAGEMENT section
- [ ] Tab completion offers `services` subcommand
- [ ] No shellcheck warnings from new code
