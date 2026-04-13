#!/usr/bin/env zsh
# 12-deps.sh - Dependency sharing (vendor/node_modules cache)

# Shared dependencies directory
: "${GROVE_SHARED_DEPS_DIR:=$HOME/.grove/shared-deps}"

# Calculate an MD5 hash of lockfiles for use as a shared dependency cache key
#
# Arguments:
#   $1 - worktree path
#
# Output:
#   12-character hash string
#
# Returns:
#   0 on success, 1 if no lockfiles found or hashing unavailable
_calculate_lockfile_hash() {
  local wt_path="$1"
  local lockfiles=()

  # Collect existing lockfiles
  [[ -f "$wt_path/composer.lock" ]] && lockfiles+=("$wt_path/composer.lock")
  [[ -f "$wt_path/package-lock.json" ]] && lockfiles+=("$wt_path/package-lock.json")
  [[ -f "$wt_path/yarn.lock" ]] && lockfiles+=("$wt_path/yarn.lock")

  if (( ${#lockfiles[@]} == 0 )); then
    return 1
  fi

  # Generate MD5 hash using streaming (memory-efficient) with cross-platform support
  # macOS uses 'md5', Linux uses 'md5sum'
  if command -v md5sum >/dev/null 2>&1; then
    cat "${lockfiles[@]}" | md5sum | cut -d ' ' -f1 | cut -c1-12
  elif command -v md5 >/dev/null 2>&1; then
    cat "${lockfiles[@]}" | md5 | cut -c1-12
  else
    warn "Neither md5sum nor md5 found"
    return 1
  fi
}

# Check whether dependencies are shared, local, or missing for a worktree
#
# Arguments:
#   $1 - worktree path
#   $2 - dependency type ("vendor" or "node_modules")
#
# Output:
#   "shared", "local", or "missing"
_check_deps_shared() {
  local wt_path="$1"
  local dep_type="$2"  # vendor or node_modules

  local dep_path="$wt_path/$dep_type"

  if [[ -L "$dep_path" ]]; then
    local target; target="$(readlink "$dep_path" 2>/dev/null)"
    if [[ "$target" == "$GROVE_SHARED_DEPS_DIR"/* ]]; then
      print -r -- "shared"
      return 0
    fi
  fi

  if [[ -d "$dep_path" ]]; then
    print -r -- "local"
  else
    print -r -- "missing"
  fi
}

# Enable shared dependencies by replacing a local directory with a symlink to shared cache
#
# Skips vendor/ for PHP projects (autoloader path issues). Moves existing local
# dependencies to the shared cache if no cache exists yet.
#
# Arguments:
#   $1 - worktree path
#   $2 - dependency type ("vendor" or "node_modules")
#   $3 - force flag (optional, default: "false")
#
# Returns:
#   0 on success, 1 on failure
_enable_shared_deps() {
  local wt_path="$1"
  local dep_type="$2"  # vendor or node_modules
  local force="${3:-false}"

  local dep_path="$wt_path/$dep_type"

  # IMPORTANT: Sharing vendor/ breaks PHP/Laravel projects!
  # Composer's autoloader uses relative paths from vendor to find project root.
  # When vendor is symlinked, $baseDir = dirname($vendorDir) resolves incorrectly.
  if [[ "$dep_type" == "vendor" ]]; then
    if [[ -f "$wt_path/composer.json" ]]; then
      warn "  Skipping vendor - sharing breaks PHP autoloader paths"
      dim "  Composer's autoloader uses \$baseDir = dirname(\$vendorDir)"
      dim "  which resolves incorrectly when vendor is symlinked"
      return 0
    fi
  fi

  local hash; hash="$(_calculate_lockfile_hash "$wt_path")"

  if [[ -z "$hash" ]]; then
    warn "No lockfile found for $dep_type"
    return 1
  fi

  local shared_path="$GROVE_SHARED_DEPS_DIR/$dep_type/$hash"

  # Ensure shared deps directory exists
  mkdir -p "$GROVE_SHARED_DEPS_DIR/$dep_type"

  # Check current state
  if [[ -L "$dep_path" ]]; then
    local current_target; current_target="$(readlink "$dep_path" 2>/dev/null)"
    if [[ "$current_target" == "$shared_path" ]]; then
      dim "  Already shared with correct hash"
      return 0
    fi
    # Different hash - remove old symlink
    rm "$dep_path"
  fi

  # If local directory exists, move to shared or use existing shared
  if [[ -d "$dep_path" ]]; then
    if [[ -d "$shared_path" ]]; then
      # Shared cache already exists - remove local and link
      if [[ "$force" == true ]]; then
        rm -rf "$dep_path"
      else
        warn "  Local $dep_type exists but shared cache already populated."
        dim "  Use --force to replace local with shared"
        return 1
      fi
    else
      # Move local to shared
      info "  Moving $dep_type to shared cache..."
      mv "$dep_path" "$shared_path"
    fi
  fi

  # Create shared directory if needed (will be populated on next install)
  if [[ ! -d "$shared_path" ]]; then
    mkdir -p "$shared_path"
    dim "  Shared cache created (run install to populate)"
  fi

  # Create symlink
  ln -s "$shared_path" "$dep_path"
  ok "  Linked $dep_type → $shared_path"
}

# Disable shared dependencies by replacing the symlink with a local copy
#
# Arguments:
#   $1 - worktree path
#   $2 - dependency type ("vendor" or "node_modules")
_disable_shared_deps() {
  local wt_path="$1"
  local dep_type="$2"  # vendor or node_modules

  local dep_path="$wt_path/$dep_type"

  if [[ ! -L "$dep_path" ]]; then
    dim "  $dep_type is not shared"
    return 0
  fi

  local target; target="$(readlink "$dep_path" 2>/dev/null)"

  # Remove symlink
  rm "$dep_path"

  # Copy from shared back to local if it exists
  if [[ -d "$target" ]]; then
    info "  Copying $dep_type back to local..."
    cp -R "$target" "$dep_path"
    ok "  Restored local $dep_type"
  else
    dim "  Shared cache was empty"
  fi
}

# Display the shared dependency status for a worktree (vendor and node_modules)
#
# Arguments:
#   $1 - worktree path
_show_deps_status() {
  local wt_path="$1"

  print -r -- ""
  print -r -- "${C_BOLD}Dependency Status${C_RESET}"
  print -r -- ""

  for dep_type in vendor node_modules; do
    local dep_status; dep_status="$(_check_deps_shared "$wt_path" "$dep_type")"
    local dep_path="$wt_path/$dep_type"

    case "$dep_status" in
      shared)
        local target; target="$(readlink "$dep_path" 2>/dev/null)"
        local hash="${target##*/}"
        print -r -- "  ${C_GREEN}●${C_RESET} $dep_type: ${C_GREEN}shared${C_RESET} ${C_DIM}($hash)${C_RESET}"
        ;;
      local)
        local size_kb; size_kb="$(get_dir_size_kb "$dep_path")"
        local size; size="$(bytes_to_human "$size_kb")"
        print -r -- "  ${C_YELLOW}●${C_RESET} $dep_type: ${C_YELLOW}local${C_RESET} ${C_DIM}($size)${C_RESET}"
        ;;
      missing)
        print -r -- "  ${C_DIM}○${C_RESET} $dep_type: ${C_DIM}not installed${C_RESET}"
        ;;
    esac
  done

  print -r -- ""
}

# Command: manage shared dependency caches for worktrees
#
# Usage: grove share-deps [<repo>] [enable|disable|status]
# Auto-detects repository and branch from current directory if not specified.
cmd_share_deps() {
  local repo="${1:-}"
  local action="${2:-status}"

  # If first arg is an action keyword, shift it to action and clear repo
  if [[ "$repo" == "enable" || "$repo" == "disable" || "$repo" == "status" ]]; then
    action="$repo"
    repo=""
  fi

  # Auto-detect from current directory if no repo specified
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    local branch="$DETECTED_BRANCH"
    dim "  Detected: $repo / $branch"

    local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
    [[ -d "$wt_path" ]] || die "Worktree not found at '$wt_path'"

    case "$action" in
      status)
        _show_deps_status "$wt_path"
        ;;
      enable)
        print -r -- ""
        print -r -- "${C_BOLD}Enabling shared dependencies${C_RESET}"
        print -r -- ""

        for dep_type in vendor node_modules; do
          _enable_shared_deps "$wt_path" "$dep_type" "${FORCE:-false}"
        done

        print -r -- ""
        ok "Shared dependencies enabled"
        dim "  Run 'composer install' and 'npm ci' to populate shared cache"
        print -r -- ""
        ;;
      disable)
        print -r -- ""
        print -r -- "${C_BOLD}Disabling shared dependencies${C_RESET}"
        print -r -- ""

        for dep_type in vendor node_modules; do
          _disable_shared_deps "$wt_path" "$dep_type"
        done

        print -r -- ""
        ok "Shared dependencies disabled"
        print -r -- ""
        ;;
      *)
        die "Unknown action: '$action' (try: status, enable, disable)"
        ;;
    esac
    return 0
  fi

  [[ -n "$repo" ]] || die "Usage: grove share-deps [<repo>] [enable|disable|status]
       Run from within a worktree to auto-detect."

  validate_name "$repo" "repository"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  # Get branch via fzf if available
  local branch=""
  if command -v fzf >/dev/null 2>&1; then
    branch="$(select_branch_fzf "$repo" "Select worktree for shared deps")" || die "No branch selected"
    validate_name "$branch" "branch"
  else
    die "Branch required. Run from within a worktree or install fzf."
  fi

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die "Worktree not found at '$wt_path'"

  # Recursively call with detected worktree
  DETECTED_REPO="$repo"
  DETECTED_BRANCH="$branch"
  cmd_share_deps "" "$action"
}

# Command: remove unused shared dependency caches not linked by any worktree
#
# Scans all worktrees across all repositories to find orphaned cache directories
# and removes them, reporting total space saved.
cmd_share_deps_clean() {
  print -r -- ""
  print -r -- "${C_BOLD}Cleaning unused shared dependencies${C_RESET}"
  print -r -- ""

  [[ -d "$GROVE_SHARED_DEPS_DIR" ]] || { dim "No shared deps directory found"; return 0; }

  local cleaned=0
  local saved_bytes=0
  # Declare loop variables outside loops to avoid zsh re-declaration output
  local type_dir hash_dir hash in_use out wt_path dep_path target size line

  for dep_type in vendor node_modules; do
    type_dir="$GROVE_SHARED_DEPS_DIR/$dep_type"
    [[ -d "$type_dir" ]] || continue

    for hash_dir in "$type_dir"/*(N/); do
      [[ -d "$hash_dir" ]] || continue
      hash="${hash_dir:t}"

      # Check if any worktree is using this hash
      in_use=false
      for git_dir in "$HERD_ROOT"/*.git(N); do
        [[ -d "$git_dir" ]] || continue

        out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || continue
        wt_path=""

        while IFS= read -r line; do
          if [[ "$line" == worktree\ * ]]; then
            wt_path="${line#worktree }"
          elif [[ -z "$line" && -n "$wt_path" && "$wt_path" != *.git && -d "$wt_path" ]]; then
            dep_path="$wt_path/$dep_type"
            if [[ -L "$dep_path" ]]; then
              target="$(readlink "$dep_path" 2>/dev/null)"
              if [[ "$target" == "$hash_dir" ]]; then
                in_use=true
                break 2
              fi
            fi
            wt_path=""
          fi
        done <<< "$out"
      done

      if [[ "$in_use" == false ]]; then
        size="$(du -sk "$hash_dir" 2>/dev/null | cut -f1)"
        saved_bytes=$((saved_bytes + size * 1024))
        rm -rf "$hash_dir"
        ok "  Removed: $dep_type/$hash"
        cleaned=$((cleaned + 1))
      fi
    done
  done

  print -r -- ""
  if (( cleaned > 0 )); then
    local saved_human
    if (( saved_bytes >= 1073741824 )); then
      saved_human="$(( saved_bytes / 1073741824 ))G"
    elif (( saved_bytes >= 1048576 )); then
      saved_human="$(( saved_bytes / 1048576 ))M"
    else
      saved_human="$(( saved_bytes / 1024 ))K"
    fi
    ok "Cleaned $cleaned cache(s), saved $saved_human"
  else
    dim "No unused caches found"
  fi
  print -r -- ""
}
