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
GROVE_LAUNCH_AGENTS="${GROVE_LAUNCH_AGENTS:-$HOME/Library/LaunchAgents}"

# svc_ensure_tool_path — Append Homebrew and Herd bin dirs to PATH when missing.
# GUI/minimal environments (the Grove desktop app's sidecar, cron, launchd)
# start with a bare PATH, so brew/supervisorctl/redis-cli would be "not found"
# and every daemon check would falsely report Not running. Herd's bin dir is
# included for machines with no Homebrew PHP, where the Horizon check would
# otherwise report "Unknown (php not installed)". Appending (not prepending)
# preserves any user-chosen tool versions already on PATH.
svc_ensure_tool_path() {
  local p
  for p in /opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin /usr/local/sbin \
           "$HOME/Library/Application Support/Herd/bin"; do
    if [[ -d "$p" && ":$PATH:" != *":$p:"* ]]; then
      PATH="$PATH:$p"
    fi
  done
  export PATH

  # Herd's PHP binaries locate php.ini via HERD_PHP_<ver>_INI_SCAN_DIR, which
  # Herd's shell rc sets but minimal environments lack. Without it Herd PHP
  # runs with no ini at all and artisan exits silently (status 255, no output),
  # so the Horizon check would misreport Running workers as Inactive.
  local herd_php_config="$HOME/Library/Application Support/Herd/config/php"
  local dir var
  for dir in "$herd_php_config"/<->(N/); do
    var="HERD_PHP_${dir:t}_INI_SCAN_DIR"
    # ${(P)var-} (default-empty) keeps the indirection safe under `set -u`
    if [[ -z "${(P)var-}" ]]; then
      export "$var=$dir/"
    fi
  done
}

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

  local raw app_name system_name services supervisor_process domain
  local -a fields
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    # Skip comments and empty/whitespace-only lines
    [[ -z "${raw// /}" || "$raw" == \#* ]] && continue

    # The registry is a 5-field pipe-delimited format. Reject malformed lines
    # (wrong field count) rather than silently registering a bogus app — a stray
    # '|' would otherwise shift columns and corrupt `services apps --json`.
    fields=("${(@s:|:)raw}")
    if (( ${#fields} != 5 )); then
      warn "Skipping malformed registry line (expected 5 fields, got ${#fields}): $raw" >&2
      continue
    fi

    # Trim leading/trailing whitespace only — internal spaces are preserved.
    svc_trim "${fields[1]}"; app_name="$REPLY"
    svc_trim "${fields[2]}"; system_name="$REPLY"
    svc_trim "${fields[3]}"; services="$REPLY"
    svc_trim "${fields[4]}"; supervisor_process="$REPLY"
    svc_trim "${fields[5]}"; domain="$REPLY"

    # An empty app name has no usable key — skip it.
    if [[ -z "$app_name" ]]; then
      warn "Skipping malformed registry line (empty app name): $raw" >&2
      continue
    fi

    SVC_APPS[$app_name]="$services"
    SVC_SYSTEM_NAMES[$app_name]="$system_name"
    SVC_SERVICES[$app_name]="$services"
    SVC_SUPERVISOR_PROCESSES[$app_name]="$supervisor_process"
    SVC_DOMAINS[$app_name]="${domain:-${system_name}.test}"
  done < "$GROVE_SERVICES_CONF"

  SVC_CONFIG_LOADED=true
}

# --- Helper Functions ---

# svc_trim — Strip leading/trailing whitespace only (internal spaces preserved).
# Uses plain globbing so it works regardless of the EXTENDED_GLOB option.
svc_trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"   # strip leading whitespace
  v="${v%"${v##*[![:space:]]}"}"   # strip trailing whitespace
  REPLY="$v"
}

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

# svc_validate_field — Reject values that would corrupt the pipe-delimited registry.
# A '|' or newline in any persisted field shifts/duplicates columns, which then
# silently corrupts svc_load_config and the `services apps --json` data contract.
svc_validate_field() {
  local label="$1" value="$2"
  if [[ "$value" == *"|"* ]]; then
    die "Invalid $label: '$value' (must not contain '|')"
  fi
  if [[ "$value" == *$'\n'* ]]; then
    die "Invalid $label: '$value' (must not contain newlines)"
  fi
}

# svc_validate_domain — Field check plus a hostname whitelist. A domain is written
# verbatim into the registry and later used to build URLs, so restrict it to the
# characters valid in a hostname (alphanumerics, dash, dot).
svc_validate_domain() {
  local domain="$1"
  svc_validate_field "domain" "$domain"
  if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    die "Invalid domain: '$domain' (only alphanumeric, dash, and dot allowed)"
  fi
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
    sup_status="$(supervisorctl status 2>/dev/null | grep -E "^${process%:*}[: ]" | head -1)" || true
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
    # Don't report Inactive when we simply can't query: php or the app's artisan
    # binary may be missing. Distinguish "can't check" from a real Inactive state.
    if ! command -v php &> /dev/null; then
      warn "Horizon: Unknown (php not installed)"
    elif [[ ! -f "$symlink/artisan" ]]; then
      warn "Horizon: Unknown (artisan not found)"
    else
      local horizon_status
      horizon_status="$(cd "$symlink" && php artisan horizon:status 2>&1)" || true
      if print -r -- "$horizon_status" | grep -q "running"; then
        ok "Horizon: Running"
      else
        warn "Horizon: Inactive"
      fi
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

# cmd_services_status_json — Machine-readable status for the Grove desktop app.
# Emits one object: daemon health plus a per-app array. supervisorctl and
# launchctl are queried once and matched in-process, so cost does not grow
# with the number of registered apps. The Horizon artisan check is skipped:
# it spawns php per app and the supervisor state already covers the worker.
cmd_services_status_json() {
  local app_filter="${1:-}"
  if [[ -n "$app_filter" && "$app_filter" != "all" ]]; then
    svc_validate_app "$app_filter"
  fi

  # Daemon checks. Capture grep output instead of grep -q: under pipefail an
  # early -q exit can SIGPIPE the producer and fail the pipeline on a match.
  local supervisor_running=false redis_running=false matched
  matched="$(brew services list 2>/dev/null | grep "supervisor.*started" || true)"
  [[ -n "$matched" ]] && supervisor_running=true
  if redis-cli ping > /dev/null 2>&1; then
    redis_running=true
  fi

  local supervisor_snapshot launchctl_snapshot
  supervisor_snapshot="$(supervisorctl status 2>/dev/null || true)"
  launchctl_snapshot="$(launchctl list 2>/dev/null || true)"

  # json_escape sets $REPLY — declare everything outside the loop to avoid the
  # zsh `local` re-declaration debug-output pitfall.
  local json_items=()
  local app_name system_name services process domain symlink current
  local proc_line proc_state scheduler_loaded current_json supervisor_status_json
  local je_name je_system je_services je_process je_domain je_current je_state
  for app_name in $(svc_get_app_list); do
    if [[ -n "$app_filter" && "$app_filter" != "all" && "$app_name" != "$app_filter" ]]; then
      continue
    fi
    system_name="${SVC_SYSTEM_NAMES[$app_name]}"
    services="${SVC_SERVICES[$app_name]}"
    process="${SVC_SUPERVISOR_PROCESSES[$app_name]}"
    domain="${SVC_DOMAINS[$app_name]}"

    symlink="$HERD_ROOT/${system_name}-current"
    if [[ -L "$symlink" ]]; then
      current="${symlink:A:t}"
      json_escape "$current"; je_current="$REPLY"
      current_json="\"$je_current\""
    else
      current_json="null"
    fi

    if [[ "$services" == "none" || -z "$process" ]]; then
      supervisor_status_json="null"
    else
      proc_line="$(print -r -- "$supervisor_snapshot" | grep -E "^${process%:*}[: ]" | head -1 || true)"
      if [[ -n "$proc_line" ]]; then
        proc_state="$(print -r -- "$proc_line" | awk '{print $2}')"
      else
        proc_state="NOT_CONFIGURED"
      fi
      json_escape "$proc_state"; je_state="$REPLY"
      supervisor_status_json="\"$je_state\""
    fi

    scheduler_loaded=false
    if [[ "$launchctl_snapshot" == *"com.${app_name}.scheduler"* ]]; then
      scheduler_loaded=true
    fi

    json_escape "$app_name";    je_name="$REPLY"
    json_escape "$system_name"; je_system="$REPLY"
    json_escape "$services";    je_services="$REPLY"
    json_escape "$process";     je_process="$REPLY"
    json_escape "$domain";      je_domain="$REPLY"
    json_items+=("$(printf '{"name":"%s","system_name":"%s","services":"%s","supervisor_process":"%s","domain":"%s","current_worktree":%s,"supervisor_status":%s,"scheduler_loaded":%s}' \
      "$je_name" "$je_system" "$je_services" "$je_process" "$je_domain" \
      "$current_json" "$supervisor_status_json" "$scheduler_loaded")")
  done

  format_json "{\"supervisor_running\":$supervisor_running,\"redis_running\":$redis_running,\"apps\":[${(j:,:)json_items}]}"
}

cmd_services_status() {
  local app="${1:-}"

  if [[ "$JSON_OUTPUT" == true ]]; then
    cmd_services_status_json "$app"
    return $?
  fi

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
    local sup_out
    if sup_out="$(supervisorctl start "$process" 2>&1)"; then
      ok "Started supervisor process"
    else
      warn "Could not start supervisor process '$process': ${sup_out:-unknown error}"
    fi
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
    local sup_out
    if sup_out="$(supervisorctl stop "$process" 2>&1)"; then
      ok "Stopped supervisor process"
    else
      warn "Could not stop supervisor process '$process': ${sup_out:-unknown error}"
    fi
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
    local sup_out
    if sup_out="$(supervisorctl restart "$process" 2>&1)"; then
      ok "Restarted supervisor process"
    else
      warn "Could not restart supervisor process '$process': ${sup_out:-unknown error}"
    fi
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

  # Handle 'all' before the registration guard ('all' is a sentinel, never a registered key)
  if [[ "$app" == "all" ]]; then
    local app_name
    for app_name in $(svc_get_app_list); do
      svc_restart_app "$app_name"
    done
    return 0
  fi

  # If a specific app isn't registered, exit silently (idempotent for hooks)
  if ! (( ${+SVC_APPS[$app]} )); then
    return 0
  fi

  svc_restart_app "$app"
}

cmd_services_apps() {
  # JSON mode must emit valid JSON even when no apps are registered (returns [])
  if [[ "$JSON_OUTPUT" == true ]]; then
    cmd_services_apps_json
    return $?
  fi

  if ! svc_has_apps; then
    dim "No apps registered. Run 'grove services add <name>' to get started."
    return 0
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
  # Build the array of object strings, then emit via format_json so --pretty
  # (PRETTY_JSON) is honoured, matching every other JSON command.
  #
  # json_escape sets $REPLY (it does not print) — declare vars outside the loop and
  # read $REPLY after each call so we never trigger the zsh `local var; var=$(...)`
  # debug-output pitfall that would corrupt the JSON contract.
  local json_items=()
  local app_name system_name services process domain
  local je_name je_system je_services je_process je_domain
  for app_name in $(svc_get_app_list); do
    system_name="${SVC_SYSTEM_NAMES[$app_name]}"
    services="${SVC_SERVICES[$app_name]}"
    process="${SVC_SUPERVISOR_PROCESSES[$app_name]}"
    domain="${SVC_DOMAINS[$app_name]}"
    json_escape "$app_name";     je_name="$REPLY"
    json_escape "$system_name";  je_system="$REPLY"
    json_escape "$services";     je_services="$REPLY"
    json_escape "$process";      je_process="$REPLY"
    json_escape "$domain";       je_domain="$REPLY"
    json_items+=("$(printf '{"name":"%s","system_name":"%s","services":"%s","supervisor_process":"%s","domain":"%s"}' \
      "$je_name" "$je_system" "$je_services" "$je_process" "$je_domain")")
  done
  format_json "[${(j:, :)json_items}]"
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

  # Validate name (enforces the project whitelist: no path traversal, flag injection,
  # or shell/pipe metacharacters that would corrupt the pipe-delimited apps.conf)
  validate_name "$name" "repository"

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

  # Validate the remaining fields before they are written verbatim into the
  # pipe-delimited registry — a '|', newline, or non-hostname character would
  # corrupt svc_load_config and the `services apps --json` data contract.
  svc_validate_field "system name" "$system_name"
  svc_validate_field "supervisor process" "$supervisor"
  svc_validate_domain "$domain"

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

  # Remove the line from config (match on app name at start of line). Use awk with
  # a literal prefix comparison rather than grep — a regex would let a name like
  # 'my.app' also match 'myXapp', removing the wrong entry.
  local tmp="${GROVE_SERVICES_CONF}.tmp"
  awk -v prefix="${name}|" 'substr($0, 1, length(prefix)) != prefix' "$GROVE_SERVICES_CONF" > "$tmp"
  mv "$tmp" "$GROVE_SERVICES_CONF"

  ok "Removed app: $name"
  dim "Note: This only removes from registry. Worktrees and configs are not deleted."
}

# cmd_services_switch — Point an app's -current symlink at a different worktree.
# Ported from devctl switch: stop services, repoint the symlink, clear the
# Laravel config cache, start services — so Horizon/scheduler pick up the new
# worktree immediately.
cmd_services_switch() {
  local app="${1:-}"
  local worktree="${2:-}"

  if [[ -z "$app" || -z "$worktree" ]]; then
    die "Usage: grove services switch <app> <worktree>"
  fi

  svc_validate_app "$app"
  # Worktree directory names are branch slugs — same whitelist as repo names
  # (blocks path traversal and flag injection before the path is built).
  validate_name "$worktree" "worktree"

  local system_name
  system_name="$(svc_get_system_name "$app")"
  local worktree_path="$HERD_ROOT/${system_name}-worktrees/$worktree"
  local symlink="$HERD_ROOT/${system_name}-current"

  if [[ ! -d "$worktree_path" ]]; then
    die "Worktree '$worktree' does not exist for $app (looked in $HERD_ROOT/${system_name}-worktrees)"
  fi

  # Never clobber a real directory: ln -sfn into an existing dir would create
  # the link INSIDE it instead of replacing it.
  if [[ -e "$symlink" && ! -L "$symlink" ]]; then
    die "$symlink exists but is not a symlink — refusing to replace it"
  fi

  info "Switching ${(C)app} to $worktree..."

  svc_stop_app "$app"

  ln -sfn "$worktree_path" "$symlink"
  ok "Updated ${system_name}-current -> $worktree"

  # Clear the config cache so the app doesn't serve paths cached from the
  # previous worktree (Laravel apps only; skip silently otherwise).
  if [[ -f "$worktree_path/artisan" ]] && command -v php &> /dev/null; then
    (cd "$worktree_path" && php artisan config:clear) > /dev/null 2>&1 || true
    ok "Config cache cleared"
  fi

  svc_start_app "$app"

  ok "Switched ${(C)app} to $worktree"
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
    issues=$((issues + 1))
  fi

  # Check PHP
  info "PHP:"
  if command -v php &> /dev/null; then
    ok "$(php -v | head -1)"
  else
    warn "Not installed"
    issues=$((issues + 1))
  fi

  # Check Redis
  info "Redis:"
  if redis-cli ping > /dev/null 2>&1; then
    ok "Running"
  else
    warn "Not running (fix: brew services start redis)"
    issues=$((issues + 1))
  fi

  # Check Supervisor
  info "Supervisor:"
  if brew services list 2>/dev/null | grep -q "supervisor.*started"; then
    ok "Running"
  else
    warn "Not running (fix: brew services start supervisor)"
    issues=$((issues + 1))
  fi

  # Check supervisor.d directory
  info "Supervisor Configs:"
  if [[ -d "$GROVE_SUPERVISOR_D" ]]; then
    # Count via a glob (N: nullglob so an empty dir yields zero matches) rather
    # than parsing `ls | wc -l`, which mishandles odd filenames and an empty dir.
    local -a config_files=("$GROVE_SUPERVISOR_D"/*.ini(N))
    local config_count=${#config_files}
    ok "$config_count configs in $GROVE_SUPERVISOR_D"
  else
    warn "Directory missing: $GROVE_SUPERVISOR_D"
    issues=$((issues + 1))
  fi

  if svc_has_apps; then
    # Check -current symlinks
    # Declare loop-assigned vars once, up front: re-running `local var` on an
    # existing variable inside a loop makes zsh print "var=value" to stdout.
    info "Symlinks:"
    local app system_name symlink target
    for app in $(svc_get_app_list); do
      system_name="$(svc_get_system_name "$app")"
      symlink="$HERD_ROOT/${system_name}-current"
      if [[ -L "$symlink" ]]; then
        target="$(readlink "$symlink")"
        if [[ -d "$target" ]]; then
          ok "${system_name}-current -> ${target:t}"
        else
          warn "${system_name}-current -> $target (broken)"
          issues=$((issues + 1))
        fi
      else
        warn "${system_name}-current missing"
        issues=$((issues + 1))
      fi
    done

    # Check supervisor processes
    info "Supervisor Processes:"
    local process proc_status
    for app in $(svc_get_app_list); do
      if [[ "${SVC_SERVICES[$app]}" == "none" ]]; then
        continue
      fi
      process="$(svc_get_supervisor_process "$app")"
      proc_status="$(supervisorctl status 2>/dev/null | grep -E "^${process%:*}[: ]" | head -1 || true)"
      if [[ -n "$proc_status" ]]; then
        if print -r -- "$proc_status" | grep -q "RUNNING"; then
          ok "$app: RUNNING"
        else
          warn "$app: $(print -r -- "$proc_status" | awk '{print $2}')"
        fi
      else
        warn "$app: Not configured"
      fi
    done

    # Check scheduler LaunchAgents
    info "Scheduler LaunchAgents:"
    local plist scheduler_status
    for app in $(svc_get_app_list); do
      plist="$GROVE_LAUNCH_AGENTS/com.${app}.scheduler.plist"
      if [[ -f "$plist" ]]; then
        # Capture with plain grep rather than grep -q: under pipefail, -q's early
        # exit sends launchctl a SIGPIPE and fails the pipeline on a real match.
        scheduler_status="$(launchctl list 2>/dev/null | grep "com.${app}.scheduler" || true)"
        if [[ -n "$scheduler_status" ]]; then
          ok "$app: Loaded"
        else
          warn "$app: Not loaded"
        fi
      else
        dim "$app: No plist (no scheduler configured)"
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

svc_show_help() {
  print -r -- ""
  print -r -- "${C_BOLD}Grove Service Management${C_RESET}"
  print -r -- ""
  print -r -- "  Manage Supervisor, Horizon, Reverb, and scheduler for Laravel apps."
  print -r -- ""
  print -r -- "  ${C_GREEN}Get started:${C_RESET}"
  print -r -- "    grove services add <name>         Register an app"
  print -r -- "    grove services remove <name>      Remove an app from the registry"
  print -r -- "    grove services doctor             Check service dependencies"
  print -r -- ""
  print -r -- "  ${C_GREEN}Daily use:${C_RESET}"
  print -r -- "    grove services status             Show all app status"
  print -r -- "    grove services start <app|all>    Start services"
  print -r -- "    grove services stop <app|all>     Stop services"
  print -r -- "    grove services restart <app|all>  Restart services"
  print -r -- "    grove services switch <app> <wt>  Point -current at another worktree"
  print -r -- ""
  print -r -- "  ${C_GREEN}Utilities:${C_RESET}"
  print -r -- "    grove services apps               List registered apps"
  print -r -- "    grove services horizon <app>       Open Horizon dashboard"
  print -r -- "    grove services logs <app> [type]   Tail service logs"
  print -r -- ""
}

cmd_services() {
  # Lazy-load config only when services is actually invoked
  svc_load_config

  # Minimal environments (GUI sidecar, cron) lack the Homebrew paths that
  # brew/supervisorctl/redis-cli live in — repair PATH before any check runs.
  svc_ensure_tool_path

  local subcmd="${1:-}"
  shift 2>/dev/null || true

  case "$subcmd" in
    status)   cmd_services_status "$@" ;;
    start)    cmd_services_start "$@" ;;
    stop)     cmd_services_stop "$@" ;;
    restart)  cmd_services_restart "$@" ;;
    switch)   cmd_services_switch "$@" ;;
    add)      cmd_services_add "$@" ;;
    remove)   cmd_services_remove "$@" ;;
    apps)     cmd_services_apps "$@" ;;
    horizon)  cmd_services_horizon "$@" ;;
    logs)     cmd_services_logs "$@" ;;
    doctor)   cmd_services_doctor "$@" ;;
    "")
      # Bare `grove services`: show status if apps are registered, else the help text.
      # (Note: bare `help`/`-h`/`--help` are caught by the global flag parser, which prints
      # the main `grove --help` — that already lists every services subcommand incl. remove.)
      if svc_has_apps; then
        cmd_services_status "$@"
      else
        svc_show_help
      fi
      ;;
    *)
      die "Unknown services command: $subcmd (see 'grove --help' for the services subcommands)"
      ;;
  esac
}
