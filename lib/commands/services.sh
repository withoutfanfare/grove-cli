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
