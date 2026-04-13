#!/usr/bin/env zsh
# config.sh - Configuration and customization commands

# cmd_config — Show current grove configuration
cmd_config() {
  # Gather configuration values from environment/defaults
  local default_base="${DEFAULT_BASE:-main}"
  local protected="${PROTECTED_BRANCHES:-staging main master}"
  local config_dir="${GROVE_CONFIG_DIR:-$HOME/.grove}"
  local hooks_dir="${GROVE_HOOKS_DIR:-$config_dir/hooks}"
  local repos_dir="${GROVE_REPOS_DIR:-$HOME/Code}"
  local hooks_enabled="true"
  [[ -d "$hooks_dir" ]] || hooks_enabled="false"

  local db_enabled="${DB_CREATE:-false}"
  local db_host="${DB_HOST:-127.0.0.1}"
  local db_user="${DB_USER:-root}"
  local herd_enabled="${HERD_ENABLED:-false}"

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    # Convert protected branches to JSON array using pure Zsh
    local protected_json="[]"
    if [[ -n "$protected" ]]; then
      local -a branches=("${=protected}")  # Split on whitespace
      local json_parts=()
      for b in "${branches[@]}"; do
        [[ -n "$b" ]] && json_parts+=("\"$b\"")
      done
      protected_json="[${(j:,:)json_parts}]"
    fi

    json_escape "$default_base"; local _je_base="$REPLY"
    json_escape "$config_dir"; local _je_cdir="$REPLY"
    json_escape "$hooks_dir"; local _je_hdir="$REPLY"
    json_escape "$repos_dir"; local _je_rdir="$REPLY"
    json_escape "$db_host"; local _je_dbh="$REPLY"
    json_escape "$db_user"; local _je_dbu="$REPLY"
    local url_sub="${GROVE_URL_SUBDOMAIN:-}"
    local url_sub_json="null"
    if [[ -n "$url_sub" ]]; then
      json_escape "$url_sub"; url_sub_json="\"$REPLY\""
    fi
    print -r -- "{\"success\": true, \"data\": {\"default_base_branch\": \"$_je_base\", \"protected_branches\": $protected_json, \"config_dir\": \"$_je_cdir\", \"hooks_dir\": \"$_je_hdir\", \"repos_dir\": \"$_je_rdir\", \"hooks_enabled\": $hooks_enabled, \"database\": {\"enabled\": $db_enabled, \"host\": \"$_je_dbh\", \"user\": \"$_je_dbu\"}, \"herd_enabled\": $herd_enabled, \"url_subdomain\": $url_sub_json}}"
  else
    print -r -- "grove Configuration"
    print -r -- "================"
    print -r -- ""
    print -r -- "Directories:"
    print -r -- "  Config:     $config_dir"
    print -r -- "  Hooks:      $hooks_dir"
    print -r -- "  Repos:      $repos_dir"
    print -r -- ""
    print -r -- "Git:"
    print -r -- "  Base branch:        $default_base"
    print -r -- "  Protected branches: $protected"
    print -r -- "  Hooks enabled:      $hooks_enabled"
    print -r -- ""
    print -r -- "Database:"
    print -r -- "  Enabled: $db_enabled"
    [[ "$db_enabled" == "true" ]] && {
      print -r -- "  Host:    $db_host"
      print -r -- "  User:    $db_user"
    }
    print -r -- ""
    print -r -- "URL:"
    print -r -- "  Subdomain: ${GROVE_URL_SUBDOMAIN:-(none)}"
    print -r -- ""
    print -r -- "Integrations:"
    print -r -- "  Laravel Herd: $herd_enabled"
  fi
}

# cmd_templates — List or show details of worktree templates
#
# Arguments:
#   $1 - (optional) template name; if omitted, lists all templates
#
# Returns:
#   0 on success
cmd_templates() {
  local template_name="${1:-}"

  if [[ -z "$template_name" ]]; then
    # List all templates
    print -r -- ""
    print -r -- "${C_BOLD}Available Templates${C_RESET}"
    print -r -- ""
    list_templates
    print -r -- ""
    print -r -- "${C_DIM}Usage: grove templates <name>  - Show template details${C_RESET}"
    print -r -- "${C_DIM}       grove add <repo> <branch> --template=<name>${C_RESET}"
    print -r -- ""
    return 0
  fi

  # Validate template name first (security: prevent path traversal)
  validate_template_name "$template_name"

  # Show specific template details
  local template_file="$GROVE_TEMPLATES_DIR/${template_name}.conf"

  if [[ ! -f "$template_file" ]]; then
    error_exit "INVALID_INPUT" "template not found: '$template_name' (expected: '$template_file')" 2
  fi

  print -r -- ""
  print -r -- "${C_BOLD}Template: ${C_CYAN}$template_name${C_RESET}"
  print -r -- ""

  # Extract description
  local desc; desc="$(extract_template_desc "$template_file")"
  if [[ -n "$desc" ]]; then
    print -r -- "${C_DIM}Description:${C_RESET} $desc"
    print -r -- ""
  fi

  print -r -- "${C_DIM}File:${C_RESET} $template_file"
  print -r -- ""
  print -r -- "${C_BOLD}Settings:${C_RESET}"

  # Show all GROVE_SKIP_* settings
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" || "$key" =~ ^[[:space:]]*$ ]] && continue

    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    case "$key" in
      GROVE_SKIP_*)
        value="${value#\"}"
        value="${value%\"}"
        value="${value%%#*}"
        value="${value%"${value##*[![:space:]]}"}"
        if [[ "$value" == "true" ]]; then
          print -r -- "  ${C_YELLOW}$key${C_RESET} = ${C_RED}true${C_RESET} (skipped)"
        else
          print -r -- "  ${C_GREEN}$key${C_RESET} = ${C_GREEN}false${C_RESET} (enabled)"
        fi
        ;;
    esac
  done < "$template_file"

  print -r -- ""
  print -r -- "${C_DIM}Usage: grove add <repo> <branch> --template=$template_name${C_RESET}"
  print -r -- ""
}


# cmd_alias — Manage branch aliases (list, add, remove)
#
# Arguments:
#   $1 - action: list|add|set|rm|remove|delete (default: list)
#   $2 - alias name (required for add/rm)
#   $3 - target repo/branch (required for add)
#
# Returns:
#   0 on success
cmd_alias() {
  local action="${1:-}"
  local alias_name="${2:-}"
  local target="${3:-}"

  # Ensure aliases file exists
  [[ -d "${GROVE_ALIASES_FILE:h}" ]] || mkdir -p "${GROVE_ALIASES_FILE:h}"
  [[ -f "$GROVE_ALIASES_FILE" ]] || touch "$GROVE_ALIASES_FILE"

  case "$action" in
    ""|list)
      print -r -- ""
      print -r -- "${C_BOLD}Branch Aliases${C_RESET}"
      print -r -- ""
      if [[ -s "$GROVE_ALIASES_FILE" ]]; then
        while IFS='=' read -r name value; do
          [[ -n "$name" && "$name" != \#* ]] && print -r -- "  ${C_GREEN}$name${C_RESET} → ${C_MAGENTA}$value${C_RESET}"
        done < "$GROVE_ALIASES_FILE"
      else
        dim "  No aliases defined"
      fi
      print -r -- ""
      dim "Usage: grove alias add <name> <repo/branch>"
      dim "       grove alias rm <name>"
      print -r -- ""
      ;;

    add|set)
      [[ -n "$alias_name" && -n "$target" ]] || error_exit "INVALID_INPUT" "Usage: grove alias add <name> <repo/branch>" 2

      # Validate alias name (alphanumeric, dash, underscore only)
      if [[ ! "$alias_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error_exit "INVALID_INPUT" "invalid alias name '$alias_name', use alphanumeric, dash, or underscore" 2
      fi

      # Validate target value (must be safe repo/branch format)
      # Prevent path traversal and command injection
      if [[ "$target" == *".."* ]] || [[ "$target" == *";"* ]] || [[ "$target" == *"|"* ]] || \
         [[ "$target" == *"&"* ]] || [[ "$target" == *'$'* ]] || [[ "$target" == *'`'* ]] || \
         [[ "$target" == *'\'* ]]; then
        error_exit "INVALID_INPUT" "invalid alias target '$target', suspicious characters detected" 2
      fi

      # Remove existing alias if present
      if grep -Fq "${alias_name}=" "$GROVE_ALIASES_FILE" 2>/dev/null; then
        local temp_file; temp_file="$(mktemp)"
        grep -Fv "${alias_name}=" "$GROVE_ALIASES_FILE" > "$temp_file"
        mv "$temp_file" "$GROVE_ALIASES_FILE"
      fi

      # Add new alias
      print -r -- "${alias_name}=${target}" >> "$GROVE_ALIASES_FILE"
      ok "Alias created: ${C_GREEN}$alias_name${C_RESET} → ${C_MAGENTA}$target${C_RESET}"
      ;;

    rm|remove|delete)
      [[ -n "$alias_name" ]] || error_exit "INVALID_INPUT" "Usage: grove alias rm <name>" 2

      if grep -Fq "${alias_name}=" "$GROVE_ALIASES_FILE" 2>/dev/null; then
        local temp_file; temp_file="$(mktemp)"
        grep -Fv "${alias_name}=" "$GROVE_ALIASES_FILE" > "$temp_file"
        mv "$temp_file" "$GROVE_ALIASES_FILE"
        ok "Alias removed: ${C_YELLOW}$alias_name${C_RESET}"
      else
        error_exit "INVALID_INPUT" "alias not found: '$alias_name'" 2
      fi
      ;;

    *)
      error_exit "INVALID_INPUT" "unknown action: '$action' (try: list, add, rm)" 2
      ;;
  esac
}

# Resolve an alias name to its repo/branch target
#
# Arguments:
#   $1 - alias name
#
# Output:
#   Prints the target value to stdout
#
# Returns:
#   0 if alias found, 1 if not found
resolve_alias() {
  local alias_name="$1"

  if [[ -f "$GROVE_ALIASES_FILE" ]]; then
    local line
    while IFS= read -r line; do
      if [[ "$line" == "${alias_name}="* ]]; then
        print -r -- "${line#*=}"
        return 0
      fi
    done < "$GROVE_ALIASES_FILE"
  fi
  return 1
}

# ============================================================================
# Setup Wizard - First-time configuration
# ============================================================================


# cmd_setup — Interactive setup wizard for first-time grove configuration
#
# Walks the user through configuring HERD_ROOT, DEFAULT_BASE,
# DEFAULT_EDITOR, database settings, and branch naming patterns.
# Creates ~/.groverc with restrictive permissions (0600).
#
# Returns:
#   0 on success or abort
cmd_setup() {
  print -r -- ""
  print -r -- "${C_BOLD}grove Setup Wizard${C_RESET}"
  print -r -- ""

  local config_file="${GROVE_CONFIG:-$HOME/.groverc}"
  local reconfigure=false

  # Check if config already exists
  if [[ -f "$config_file" ]]; then
    warn "Configuration file already exists: ${C_CYAN}$config_file${C_RESET}"
    print -r -- ""
    print -n "${C_YELLOW}Reconfigure? [y/N]${C_RESET} "
    local response
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      dim "Aborted. Run 'grove doctor' to check your configuration."
      return 0
    fi
    reconfigure=true
    print -r -- ""
  fi

  # Welcome message
  if [[ "$reconfigure" == false ]]; then
    info "This wizard will help you configure grove for first-time use."
    print -r -- ""
  fi

  # -------------------------------------------------------------------------
  # HERD_ROOT - Where worktrees will be stored
  # -------------------------------------------------------------------------
  local default_herd_root="${HERD_ROOT:-$HOME/Herd}"
  print -r -- "${C_BOLD}1. Worktree Directory${C_RESET}"
  print -r -- "   Where should worktrees be stored?"
  print -r -- ""
  print -n "   HERD_ROOT [${C_DIM}$default_herd_root${C_RESET}]: "
  local herd_root_input
  read -r herd_root_input
  local herd_root="${herd_root_input:-$default_herd_root}"

  # Expand ~ if present
  herd_root="${herd_root/#\~/$HOME}"

  # Create directory if it doesn't exist
  if [[ ! -d "$herd_root" ]]; then
    print -n "   ${C_YELLOW}Directory doesn't exist. Create it? [Y/n]${C_RESET} "
    local create_dir
    read -r create_dir
    if [[ ! "$create_dir" =~ ^[Nn]$ ]]; then
      mkdir -p "$herd_root" && ok "   Created: $herd_root" || error_exit "IO_ERROR" "failed to create directory '$herd_root'" 5
    fi
  else
    ok "   Directory exists: $herd_root"
  fi
  print -r -- ""

  # -------------------------------------------------------------------------
  # DEFAULT_BASE - Base branch for rebasing
  # -------------------------------------------------------------------------
  local default_base="${DEFAULT_BASE:-origin/staging}"
  print -r -- "${C_BOLD}2. Default Base Branch${C_RESET}"
  print -r -- "   Which branch should be used as the default base for rebasing?"
  print -r -- "   ${C_DIM}Common options: origin/staging, origin/main, origin/master${C_RESET}"
  print -r -- ""
  print -n "   DEFAULT_BASE [${C_DIM}$default_base${C_RESET}]: "
  local base_input
  read -r base_input
  local base_branch="${base_input:-$default_base}"
  print -r -- ""

  # -------------------------------------------------------------------------
  # DEFAULT_EDITOR - Editor for opening worktrees
  # -------------------------------------------------------------------------
  local default_editor="${DEFAULT_EDITOR:-cursor}"
  print -r -- "${C_BOLD}3. Default Editor${C_RESET}"
  print -r -- "   Which editor should be used to open worktrees?"
  print -r -- "   ${C_DIM}Common options: cursor, code, phpstorm, subl${C_RESET}"
  print -r -- ""

  # Detect available editors
  local detected_editors=()
  for ed in cursor code phpstorm subl vim; do
    command -v "$ed" >/dev/null 2>&1 && detected_editors+=("$ed")
  done
  if (( ${#detected_editors[@]} > 0 )); then
    dim "   Detected: ${detected_editors[*]}"
  fi

  print -n "   DEFAULT_EDITOR [${C_DIM}$default_editor${C_RESET}]: "
  local editor_input
  read -r editor_input
  local editor="${editor_input:-$default_editor}"
  print -r -- ""

  # -------------------------------------------------------------------------
  # Database Settings
  # -------------------------------------------------------------------------
  print -r -- "${C_BOLD}4. Database Settings${C_RESET}"
  print -r -- "   Configure MySQL connection for automatic database creation."
  print -r -- "   ${C_DIM}Leave empty to skip database features.${C_RESET}"
  print -r -- ""

  local default_db_host="${DB_HOST:-127.0.0.1}"
  local default_db_user="${DB_USER:-root}"
  local default_db_create="${DB_CREATE:-true}"

  print -n "   DB_HOST [${C_DIM}$default_db_host${C_RESET}]: "
  local db_host_input
  read -r db_host_input
  local db_host="${db_host_input:-$default_db_host}"

  print -n "   DB_USER [${C_DIM}$default_db_user${C_RESET}]: "
  local db_user_input
  read -r db_user_input
  local db_user="${db_user_input:-$default_db_user}"

  print -n "   DB_PASSWORD [${C_DIM}(hidden)${C_RESET}]: "
  local db_password
  read -rs db_password
  print -r -- ""

  print -n "   Auto-create databases? [Y/n]: "
  local db_create_input
  read -r db_create_input
  local db_create="true"
  [[ "$db_create_input" =~ ^[Nn]$ ]] && db_create="false"
  print -r -- ""

  # Test MySQL connection if credentials provided (use MYSQL_PWD for safer password handling)
  if [[ -n "$db_host" && -n "$db_user" ]]; then
    info "   Testing MySQL connection..."
    local mysql_cmd=(mysql -h "$db_host" -u "$db_user")
    if MYSQL_PWD="${db_password:-}" "${mysql_cmd[@]}" -e "SELECT 1" >/dev/null 2>&1; then
      ok "   MySQL connection successful"
    else
      warn "   MySQL connection failed (check credentials later)"
    fi
    print -r -- ""
  fi

  # -------------------------------------------------------------------------
  # Branch Pattern (optional)
  # -------------------------------------------------------------------------
  print -r -- "${C_BOLD}5. Branch Naming Pattern (optional)${C_RESET}"
  print -r -- "   Enforce a naming convention for new branches."
  print -r -- "   ${C_DIM}Example: ^(feature|bugfix|hotfix)/[a-z0-9-]+$${C_RESET}"
  print -r -- "   ${C_DIM}Leave empty to allow any branch name.${C_RESET}"
  print -r -- ""

  print -n "   BRANCH_PATTERN [${C_DIM}(none)${C_RESET}]: "
  local branch_pattern
  read -r branch_pattern
  print -r -- ""

  # -------------------------------------------------------------------------
  # Create directories
  # -------------------------------------------------------------------------
  print -r -- "${C_BOLD}6. Creating directories...${C_RESET}"

  local grove_dir="$HOME/.grove"
  local hooks_dir="$grove_dir/hooks"
  local templates_dir="$grove_dir/templates"

  for dir in "$grove_dir" "$hooks_dir" "$templates_dir" "$hooks_dir/post-add.d" "$hooks_dir/post-rm.d"; do
    if [[ ! -d "$dir" ]]; then
      mkdir -p "$dir" && ok "   Created: $dir" || warn "   Failed to create: $dir"
    else
      dim "   Exists: $dir"
    fi
  done
  print -r -- ""

  # -------------------------------------------------------------------------
  # Write configuration file
  # -------------------------------------------------------------------------
  print -r -- "${C_BOLD}7. Writing configuration...${C_RESET}"

  # Backup existing config if reconfiguring
  if [[ "$reconfigure" == true && -f "$config_file" ]]; then
    local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$config_file" "$backup_file"
    dim "   Backed up existing config to: $backup_file"
  fi

  # Write config file with restrictive permissions from the start (umask 077)
  # This prevents any window where the file could be world-readable
  (
    umask 077
    cat > "$config_file" << EOF
# grove configuration file
# Generated by grove setup on $(date '+%Y-%m-%d %H:%M:%S')

# Worktree directory (where bare repos and worktrees are stored)
HERD_ROOT="$herd_root"

# Default base branch for rebasing
DEFAULT_BASE="$base_branch"

# Default editor for opening worktrees
DEFAULT_EDITOR="$editor"

# Database settings
DB_HOST="$db_host"
DB_USER="$db_user"
EOF

    # Only write password if provided
    if [[ -n "$db_password" ]]; then
      warn "   Database password will be stored in plain text"
      print -r -- "DB_PASSWORD=\"$db_password\"" >> "$config_file"
    fi

    cat >> "$config_file" << EOF
DB_CREATE="$db_create"

# Database backup settings
DB_BACKUP="true"
DB_BACKUP_DIR="$HOME/.grove/backups"
EOF

    # Add branch pattern if provided
    if [[ -n "$branch_pattern" ]]; then
      cat >> "$config_file" << EOF

# Branch naming pattern (regex)
BRANCH_PATTERN="$branch_pattern"
BRANCH_EXAMPLES="feature/my-feature, bugfix/fix-login"
EOF
    fi
  )

  ok "   Configuration written to: $config_file"
  print -r -- ""

  # -------------------------------------------------------------------------
  # Summary
  # -------------------------------------------------------------------------
  print -r -- "${C_BOLD}${C_GREEN}✓ Setup complete!${C_RESET}"
  print -r -- ""
  print -r -- "${C_BOLD}Summary:${C_RESET}"
  print -r -- "  ${C_DIM}HERD_ROOT:${C_RESET}      $herd_root"
  print -r -- "  ${C_DIM}DEFAULT_BASE:${C_RESET}   $base_branch"
  print -r -- "  ${C_DIM}DEFAULT_EDITOR:${C_RESET} $editor"
  print -r -- "  ${C_DIM}DB_HOST:${C_RESET}        $db_host"
  print -r -- "  ${C_DIM}DB_USER:${C_RESET}        $db_user"
  print -r -- "  ${C_DIM}DB_CREATE:${C_RESET}      $db_create"
  [[ -n "$branch_pattern" ]] && print -r -- "  ${C_DIM}BRANCH_PATTERN:${C_RESET} $branch_pattern"
  print -r -- ""
  print -r -- "${C_BOLD}Next steps:${C_RESET}"
  print -r -- "  1. Clone a repository:  ${C_CYAN}grove clone git@github.com:org/repo.git${C_RESET}"
  print -r -- "  2. Create a worktree:   ${C_CYAN}grove add <repo> <branch>${C_RESET}"
  print -r -- "  3. Check configuration: ${C_CYAN}grove doctor${C_RESET}"
  print -r -- ""
  print -r -- "${C_DIM}Edit configuration manually: $config_file${C_RESET}"
  print -r -- ""
}

# ============================================================================
# Repository Groups - Multi-repo operations
# ============================================================================

readonly GROVE_GROUPS_FILE="$HOME/.grove/groups"


# cmd_group — Manage repository groups for multi-repo operations
#
# Arguments:
#   $1 - action: list|add|rm|remove|delete|show (default: list)
#   $2 - group name (required for add/rm/show)
#   $@ - repository names (required for add)
#
# Returns:
#   0 on success
cmd_group() {
  local action="${1:-}"
  local group_name="${2:-}"
  shift 2 2>/dev/null || true
  local repos=("$@")

  # Ensure groups file exists
  [[ -d "${GROVE_GROUPS_FILE:h}" ]] || mkdir -p "${GROVE_GROUPS_FILE:h}"
  [[ -f "$GROVE_GROUPS_FILE" ]] || touch "$GROVE_GROUPS_FILE"

  case "$action" in
    ""|list)
      print -r -- ""
      print -r -- "${C_BOLD}Repository Groups${C_RESET}"
      print -r -- ""
      if [[ -s "$GROVE_GROUPS_FILE" ]]; then
        while IFS='=' read -r name value; do
          [[ -n "$name" && "$name" != \#* ]] && print -r -- "  ${C_GREEN}@$name${C_RESET} → ${C_CYAN}$value${C_RESET}"
        done < "$GROVE_GROUPS_FILE"
      else
        dim "  No groups defined"
      fi
      print -r -- ""
      dim "Usage: grove group add <name> <repo1> [repo2] ..."
      dim "       grove group rm <name>"
      dim "       grove group show <name>"
      print -r -- ""
      ;;

    add)
      [[ -n "$group_name" && ${#repos[@]} -gt 0 ]] || error_exit "INVALID_INPUT" "Usage: grove group add <name> <repo1> [repo2] ..." 2

      # Validate group name (alphanumeric, dash, underscore only)
      if [[ ! "$group_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error_exit "INVALID_INPUT" "invalid group name '$group_name', use alphanumeric, dash, or underscore" 2
      fi

      # Validate all repos exist
      # Declare loop variable outside loop to avoid zsh re-declaration output
      local git_dir
      for repo in "${repos[@]}"; do
        git_dir="$(git_dir_for "$repo")"
        if [[ ! -d "$git_dir" ]]; then
          error_exit "WORKTREE_NOT_FOUND" "repository not found: '$repo'" 3
        fi
      done

      # Remove existing group if present
      if grep -q "^${group_name}=" "$GROVE_GROUPS_FILE" 2>/dev/null; then
        local temp_file="$(mktemp)"
        grep -v "^${group_name}=" "$GROVE_GROUPS_FILE" > "$temp_file"
        mv "$temp_file" "$GROVE_GROUPS_FILE"
      fi

      # Add new group
      local repos_str="${repos[*]}"
      print -r -- "${group_name}=${repos_str}" >> "$GROVE_GROUPS_FILE"
      ok "Group created: ${C_GREEN}@$group_name${C_RESET} → ${C_CYAN}${repos_str}${C_RESET}"
      ;;

    rm|remove|delete)
      [[ -n "$group_name" ]] || error_exit "INVALID_INPUT" "Usage: grove group rm <name>" 2

      if grep -q "^${group_name}=" "$GROVE_GROUPS_FILE" 2>/dev/null; then
        local temp_file; temp_file="$(mktemp)"
        grep -v "^${group_name}=" "$GROVE_GROUPS_FILE" > "$temp_file"
        mv "$temp_file" "$GROVE_GROUPS_FILE"
        ok "Group removed: ${C_YELLOW}@$group_name${C_RESET}"
      else
        error_exit "INVALID_INPUT" "group not found: '$group_name'" 2
      fi
      ;;

    show)
      [[ -n "$group_name" ]] || error_exit "INVALID_INPUT" "Usage: grove group show <name>" 2

      local repos_str=""
      local grp_line
      while IFS= read -r grp_line; do
        if [[ "$grp_line" == "${group_name}="* ]]; then
          repos_str="${grp_line#*=}"
          break
        fi
      done < "$GROVE_GROUPS_FILE" 2>/dev/null
      if [[ -z "$repos_str" ]]; then
        error_exit "INVALID_INPUT" "group not found: '$group_name'" 2
      fi

      print -r -- ""
      print -r -- "${C_BOLD}Group: ${C_GREEN}@$group_name${C_RESET}"
      print -r -- ""
      # Declare loop variables outside loop to avoid zsh re-declaration output
      local git_dir wt_list wt_count
      for repo in ${=repos_str}; do
        # Validate repo name to prevent injection from tampered group file
        validate_name "$repo" "repository" 2>/dev/null || {
          warn "Invalid repo name in group: $repo (skipping)"
          continue
        }
        git_dir="$(git_dir_for "$repo")"
        if [[ -d "$git_dir" ]]; then
          wt_list="$(git --git-dir="$git_dir" worktree list 2>/dev/null)"
          wt_count="$(count_lines "$wt_list")"
          print -r -- "  ${C_CYAN}$repo${C_RESET} ${C_DIM}($wt_count worktrees)${C_RESET}"
        else
          print -r -- "  ${C_RED}$repo${C_RESET} ${C_DIM}(not found)${C_RESET}"
        fi
      done
      print -r -- ""
      ;;

    *)
      error_exit "INVALID_INPUT" "unknown action: '$action' (try: list, add, rm, show)" 2
      ;;
  esac
}

# Resolve a group name to its space-separated list of repositories
#
# Arguments:
#   $1 - group name
#
# Output:
#   Prints space-separated repo names to stdout
#
# Returns:
#   0 if group found, 1 if not found
resolve_group() {
  local group_name="$1"

  if [[ -f "$GROVE_GROUPS_FILE" ]]; then
    local grp_line
    while IFS= read -r grp_line; do
      if [[ "$grp_line" == "${group_name}="* ]]; then
        print -r -- "${grp_line#*=}"
        return 0
      fi
    done < "$GROVE_GROUPS_FILE"
  fi
  return 1
}

