#!/usr/bin/env zsh
# maintenance.sh - System maintenance and diagnostic commands

# cmd_doctor — Run diagnostic checks on grove installation and configuration
#
# Checks: HERD_ROOT, required tools (git, composer), optional tools
# (mysql, herd, fzf, editor), config files, and hook directories.
#
# Returns:
#   0 always (reports issues via output)
cmd_doctor() {
  print -r -- ""
  print -r -- "${C_BOLD}grove doctor${C_RESET}"
  print -r -- ""

  local issues=0

  # Check HERD_ROOT
  print -r -- "${C_BOLD}Configuration${C_RESET}"
  if [[ -d "$HERD_ROOT" ]]; then
    ok "HERD_ROOT: $HERD_ROOT"
  else
    warn "HERD_ROOT does not exist: $HERD_ROOT"
    issues=$((issues + 1))
  fi

  if [[ -d "$DB_BACKUP_DIR" ]]; then
    ok "DB_BACKUP_DIR: $DB_BACKUP_DIR"
  else
    dim "  DB_BACKUP_DIR does not exist (will be created on first backup): $DB_BACKUP_DIR"
  fi

  print -r -- ""
  print -r -- "${C_BOLD}Required Tools${C_RESET}"

  # Check git
  if command -v git >/dev/null 2>&1; then
    local git_version; git_version="$(git --version 2>/dev/null)"
    # Take first line using Zsh parameter expansion
    git_version="${git_version%%$'\n'*}"
    ok "git: $git_version"
  else
    warn "git: not found"
    issues=$((issues + 1))
  fi

  # Check composer
  if command -v composer >/dev/null 2>&1; then
    local composer_version; composer_version="$(composer --version 2>/dev/null)"
    # Take first line using Zsh parameter expansion
    composer_version="${composer_version%%$'\n'*}"
    ok "composer: $composer_version"
  else
    warn "composer: not found"
    issues=$((issues + 1))
  fi

  print -r -- ""
  print -r -- "${C_BOLD}Optional Tools${C_RESET}"

  # Check mysql
  if command -v mysql >/dev/null 2>&1; then
    local mysql_version; mysql_version="$(mysql --version 2>/dev/null)"
    # Take first line using Zsh parameter expansion
    mysql_version="${mysql_version%%$'\n'*}"
    ok "mysql: $mysql_version"

    # Test connection (use MYSQL_PWD env var for safer password handling)
    local mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER")
    if MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" -e "SELECT 1" >/dev/null 2>&1; then
      ok "  MySQL connection: OK"
    else
      warn "  MySQL connection: FAILED (check DB_HOST, DB_USER, DB_PASSWORD)"
    fi
  else
    dim "  mysql: not found (database features disabled)"
  fi

  # Check herd
  if command -v herd >/dev/null 2>&1; then
    ok "herd: installed"
  else
    dim "  herd: not found (site securing disabled)"
  fi

  # Check fzf
  if command -v fzf >/dev/null 2>&1; then
    ok "fzf: installed"
  else
    dim "  fzf: not found (interactive selection disabled)"
  fi

  # Check editor
  if command -v "$DEFAULT_EDITOR" >/dev/null 2>&1; then
    ok "editor: $DEFAULT_EDITOR"
  else
    dim "  editor: $DEFAULT_EDITOR not found"
  fi

  print -r -- ""
  print -r -- "${C_BOLD}Config Files${C_RESET}"

  local config_file="${GROVE_CONFIG:-$HOME/.groverc}"
  if [[ -f "$config_file" ]]; then
    ok "User config: $config_file"
  else
    dim "  User config: $config_file (not found)"
  fi

  if [[ -f "$HERD_ROOT/.groveconfig" ]]; then
    ok "Project config: $HERD_ROOT/.groveconfig"
  else
    dim "  Project config: $HERD_ROOT/.groveconfig (not found)"
  fi

  print -r -- ""
  print -r -- "${C_BOLD}Hooks${C_RESET}"

  if [[ -d "$GROVE_HOOKS_DIR" ]]; then
    ok "Hooks directory: $GROVE_HOOKS_DIR"

    # Check for post-add hook
    if [[ -x "$GROVE_HOOKS_DIR/post-add" ]]; then
      ok "  post-add: enabled"
    elif [[ -f "$GROVE_HOOKS_DIR/post-add" ]]; then
      warn "  post-add: exists but not executable"
    else
      dim "  post-add: not configured"
    fi

    # Check for post-add.d directory
    if [[ -d "$GROVE_HOOKS_DIR/post-add.d" ]]; then
      # Count files using Zsh glob instead of ls | wc
      local hook_files=("$GROVE_HOOKS_DIR/post-add.d"/*(N))
      local hook_count=${#hook_files[@]}
      if (( hook_count > 0 )); then
        ok "  post-add.d/: $hook_count script(s)"
      fi
    fi

    # Check for post-rm hook
    if [[ -x "$GROVE_HOOKS_DIR/post-rm" ]]; then
      ok "  post-rm: enabled"
    elif [[ -f "$GROVE_HOOKS_DIR/post-rm" ]]; then
      warn "  post-rm: exists but not executable"
    else
      dim "  post-rm: not configured"
    fi

    # Check for post-rm.d directory
    if [[ -d "$GROVE_HOOKS_DIR/post-rm.d" ]]; then
      # Count files using Zsh glob instead of ls | wc
      local hook_files=("$GROVE_HOOKS_DIR/post-rm.d"/*(N))
      local hook_count=${#hook_files[@]}
      if (( hook_count > 0 )); then
        ok "  post-rm.d/: $hook_count script(s)"
      fi
    fi
  else
    dim "  Hooks directory: $GROVE_HOOKS_DIR (not found)"
    dim "  Create hooks with: mkdir -p $GROVE_HOOKS_DIR"
  fi

  print -r -- ""
  if (( issues > 0 )); then
    warn "$issues issue(s) found"
  else
    ok "All checks passed!"
  fi
  print -r -- ""
}


# cmd_cleanup_herd — Clean orphaned Laravel Herd nginx configs and certificates
#
# Scans for Herd site configs that reference worktree directories
# which no longer exist, and removes their nginx configs, SSL
# certificates, and site symlinks.
#
# Globals:
#   FORCE - when true, skips confirmation prompt
#
# Returns:
#   0 on success, 1 if nginx directory not found
cmd_cleanup_herd() {
  print -r -- ""
  print -r -- "${C_BOLD}Cleaning orphaned Herd configs${C_RESET}"
  print -r -- ""

  if ! command -v herd >/dev/null 2>&1; then
    error_exit "IO_ERROR" "Herd is not installed" 5
  fi

  local nginx_dir="$HERD_CONFIG/valet/Nginx"
  local cert_dir="$HERD_CONFIG/valet/Certificates"
  local orphaned=()
  local cleaned=0

  if [[ ! -d "$nginx_dir" ]]; then
    warn "Nginx config directory not found: $nginx_dir"
    return 1
  fi

  info "Scanning for orphaned configs..."

  local sites_dir="$HERD_CONFIG/valet/Sites"

  # Method 1: Check old-style worktree sites (contain --)
  for config in "$nginx_dir"/*--*.test(N); do
    [[ -f "$config" ]] || continue
    local site_name="${config:t}"  # e.g., myapp--feature-xyz.test
    local folder_name="${site_name%.test}"  # e.g., myapp--feature-xyz
    local wt_path="$HERD_ROOT/$folder_name"

    # Check if the worktree directory exists
    if [[ ! -d "$wt_path" ]]; then
      orphaned+=("$site_name")
    fi
  done

  # Method 2: Check new-style linked sites (symlinks in Sites directory)
  if [[ -d "$sites_dir" ]]; then
    for site_link in "$sites_dir"/*(N@); do
      [[ -L "$site_link" ]] || continue
      local site_name="${site_link:t}"
      local target; target="$(readlink "$site_link" 2>/dev/null)"

      # Only check sites that point to -worktrees directories
      if [[ "$target" == *"-worktrees/"* && ! -d "$target" ]]; then
        orphaned+=("${site_name}.test")
      fi
    done
  fi

  if (( ${#orphaned[@]} == 0 )); then
    ok "No orphaned configs found"
    print -r -- ""
    return 0
  fi

  print -r -- ""
  warn "Found ${C_BOLD}${#orphaned[@]}${C_RESET}${C_YELLOW} orphaned config(s):${C_RESET}"
  for site in "${orphaned[@]}"; do
    print -r -- "  ${C_DIM}•${C_RESET} $site"
  done
  print -r -- ""

  if [[ "$FORCE" == false ]]; then
    print -n "${C_YELLOW}Remove these orphaned configs? [y/N]${C_RESET} "
    local response
    read -r response
    [[ "$response" =~ ^[Yy]$ ]] || { dim "Aborted"; return 0; }
  fi

  print -r -- ""
  for site_name in "${orphaned[@]}"; do
    local folder_name="${site_name%.test}"
    info "Cleaning ${C_CYAN}$site_name${C_RESET}"

    # Remove nginx config
    local nginx_config="$nginx_dir/$site_name"
    if [[ -f "$nginx_config" ]]; then
      /bin/rm -f "$nginx_config" 2>/dev/null
    fi

    # Remove certificate files
    for ext in crt key csr conf; do
      local cert_file="$cert_dir/${site_name}.${ext}"
      if [[ -f "$cert_file" ]]; then
        /bin/rm -f "$cert_file" 2>/dev/null
      fi
    done

    # Remove site symlink (for new-style linked sites)
    local site_link="$sites_dir/$folder_name"
    if [[ -L "$site_link" ]]; then
      /bin/rm -f "$site_link" 2>/dev/null
    fi

    cleaned=$((cleaned + 1))
  done

  # Restart nginx to apply changes
  info "Restarting Herd nginx..."
  herd restart >/dev/null 2>&1

  print -r -- ""
  ok "Cleaned ${C_BOLD}$cleaned${C_RESET} orphaned config(s)"
  print -r -- ""
}


# cmd_unlock — Remove stale git index lock files from worktrees
#
# Arguments:
#   $1 - (optional) repository name; if omitted, scans all repos
#
# Returns:
#   0 on success
cmd_unlock() {
  local repo="${1:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    dim "  Detected: $repo"
  fi

  if [[ -n "$repo" ]]; then
    # Unlock specific repo
    validate_name "$repo" "repository"
    local git_dir; git_dir="$(git_dir_for "$repo")"
    ensure_bare_repo "$git_dir"

    local worktrees_dir="$git_dir/worktrees"
    if [[ ! -d "$worktrees_dir" ]]; then
      dim "No worktrees directory found for $repo"
      return 0
    fi

    local count=0
    for lock_file in "$worktrees_dir"/*/index.lock(N); do
      if [[ -f "$lock_file" ]]; then
        local wt_name="${${lock_file:h}:t}"
        rm -f "$lock_file"
        ok "Removed lock: ${C_CYAN}$wt_name${C_RESET}"
        count=$((count + 1))
      fi
    done

    if (( count == 0 )); then
      ok "No stale lock files found for ${C_CYAN}$repo${C_RESET}"
    else
      ok "Removed ${C_BOLD}$count${C_RESET} lock file(s)"
    fi
  else
    # Unlock all repos
    info "Scanning all repositories..."
    local total=0

    for git_dir in "$HERD_ROOT"/*.git(N); do
      [[ -d "$git_dir" ]] || continue
      local repo_name="${${git_dir:t}%.git}"
      local worktrees_dir="$git_dir/worktrees"

      [[ -d "$worktrees_dir" ]] || continue

      for lock_file in "$worktrees_dir"/*/index.lock(N); do
        if [[ -f "$lock_file" ]]; then
          local wt_name="${${lock_file:h}:t}"
          rm -f "$lock_file"
          ok "Removed lock: ${C_CYAN}$repo_name${C_RESET} / ${C_MAGENTA}$wt_name${C_RESET}"
          total=$((total + 1))
        fi
      done
    done

    if (( total == 0 )); then
      ok "No stale lock files found"
    else
      ok "Removed ${C_BOLD}$total${C_RESET} lock file(s)"
    fi
  fi
}

# cmd_repair — Scan for and fix common worktree issues
#
# Prunes orphaned worktrees, cleans stale index locks, and checks
# worktree integrity (.git files, gitdir references, HEAD files).
# With --recovery flag, attempts automatic repair of corrupted worktrees.
#
# Arguments:
#   $1 - (optional) repository name; if omitted, repairs all repos
#
# Globals:
#   RECOVERY_MODE - when true, attempts automatic recovery
#
# Returns:
#   0 on success
cmd_repair() {
  local repo="${1:-}"
  local recovery_mode="${RECOVERY_MODE:-false}"

  if [[ "$recovery_mode" == true ]]; then
    info "Running in ${C_YELLOW}recovery mode${C_RESET} - aggressive recovery enabled"
    print -r -- ""
  fi

  if [[ -z "$repo" ]]; then
    # Repair all repos
    info "Scanning all repositories for issues..."
    for git_dir in "$HERD_ROOT"/*.git(N); do
      [[ -d "$git_dir" ]] || continue
      local repo_name="${${git_dir:t}%.git}"
      _repair_repo "$repo_name" "$git_dir" "$recovery_mode"
    done
  else
    validate_name "$repo" "repository"
    local git_dir; git_dir="$(git_dir_for "$repo")"
    ensure_bare_repo "$git_dir"
    _repair_repo "$repo" "$git_dir" "$recovery_mode"
  fi
}

# Repair a single repository's worktrees
#
# Arguments:
#   $1 - repository name
#   $2 - git directory path
#   $3 - recovery mode (true/false)
#
# Returns:
#   0 on success
_repair_repo() {
  local repo="$1"
  local git_dir="$2"
  local recovery_mode="${3:-false}"

  print -r -- ""
  print -r -- "${C_BOLD}Repairing: ${C_CYAN}$repo${C_RESET}"
  print -r -- ""

  local fixed=0

  # 1. Prune orphaned worktrees
  info "Checking for orphaned worktrees..."
  local pruned; pruned="$(git --git-dir="$git_dir" worktree prune -v 2>&1)" || true
  if [[ -n "$pruned" && "$pruned" != *"Nothing to prune"* ]]; then
    print -r -- "$pruned" | while read -r line; do
      ok "  Pruned: $line"
    done
    fixed=$((fixed + 1))
  else
    dim "  No orphaned worktrees"
  fi

  # 2. Clean stale index locks
  info "Checking for stale index locks..."
  local locks_cleaned=0
  check_index_locks "$git_dir" "--auto-clean"
  locks_cleaned=$?
  if (( locks_cleaned > 0 )); then
    fixed=$((fixed + 1))
  else
    dim "  No stale locks"
  fi

  # 3. Check for missing .git files in worktrees
  info "Checking worktree integrity..."
  local out; out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || true
  local wt_path="" branch="" corrupted_worktrees=()

  while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      wt_path="${line#worktree }"
    elif [[ "$line" == branch\ refs/heads/* ]]; then
      branch="${line#branch refs/heads/}"
    elif [[ -z "$line" && -n "$wt_path" && "$wt_path" != *.git ]]; then
      if [[ -d "$wt_path" ]]; then
        local issue=""
        # Check for missing .git file
        if [[ ! -f "$wt_path/.git" ]]; then
          issue="missing .git file"
        # Check for broken gitdir reference
        elif [[ -f "$wt_path/.git" ]]; then
          local gitdir_content; gitdir_content="$(cat "$wt_path/.git" 2>/dev/null)"
          if [[ "$gitdir_content" == gitdir:\ * ]]; then
            local ref_path="${gitdir_content#gitdir: }"
            if [[ ! -d "$ref_path" ]]; then
              issue="broken gitdir reference"
            fi
          else
            issue="malformed .git file"
          fi
        fi

        # Check for missing HEAD
        local worktree_name="${wt_path:t}"
        local wt_git_dir="$git_dir/worktrees/$worktree_name"
        if [[ -d "$wt_git_dir" && ! -f "$wt_git_dir/HEAD" ]]; then
          issue="${issue:+$issue, }missing HEAD"
        fi

        if [[ -n "$issue" ]]; then
          warn "  ${C_YELLOW}$worktree_name${C_RESET}: $issue"
          [[ -n "$branch" ]] && corrupted_worktrees+=("$wt_path|$branch|$issue")
        fi
      fi
      wt_path=""
      branch=""
    fi
  done <<< "$out"

  # Recovery mode: attempt to fix corrupted worktrees
  if [[ "$recovery_mode" == true && ${#corrupted_worktrees[@]} -gt 0 ]]; then
    print -r -- ""
    info "Attempting recovery of ${C_BOLD}${#corrupted_worktrees[@]}${C_RESET} corrupted worktree(s)..."
    print -r -- ""

    for entry in "${corrupted_worktrees[@]}"; do
      local corrupt_path="${entry%%|*}"
      local rest="${entry#*|}"
      local corrupt_branch="${rest%%|*}"
      local corrupt_issue="${rest#*|}"
      local folder="${corrupt_path:t}"

      info "  Recovering: ${C_CYAN}$folder${C_RESET} (${corrupt_branch})"

      if _attempt_worktree_recovery "$repo" "$git_dir" "$corrupt_path" "$corrupt_branch" "$corrupt_issue"; then
        ok "    Recovered successfully"
        fixed=$((fixed + 1))
      else
        warn "    Recovery failed - may need manual intervention"
        dim "    Try: grove rm $repo $corrupt_branch && grove add $repo $corrupt_branch"
      fi
    done
  elif (( ${#corrupted_worktrees[@]} > 0 )); then
    print -r -- ""
    dim "  Use ${C_YELLOW}--recovery${C_RESET} flag to attempt automatic recovery"
  fi

  print -r -- ""
  if (( fixed > 0 )); then
    ok "Fixed $fixed issue(s) in $repo"
  else
    ok "No issues found in $repo"
  fi
}

# Attempt to recover a corrupted worktree by recreating .git and HEAD files
#
# Arguments:
#   $1 - repository name
#   $2 - git directory path
#   $3 - worktree path
#   $4 - branch name
#   $5 - issue description (e.g. "missing .git file", "broken gitdir reference")
#
# Returns:
#   0 if recovery succeeded, 1 if failed
_attempt_worktree_recovery() {
  local repo="$1"
  local git_dir="$2"
  local wt_path="$3"
  local branch="$4"
  local issue="$5"
  local folder="${wt_path:t}"

  case "$issue" in
    "missing .git file")
      # Recreate the .git file pointing to the correct gitdir
      local worktree_git_dir="$git_dir/worktrees/$folder"
      if [[ -d "$worktree_git_dir" ]]; then
        print -r -- "gitdir: $worktree_git_dir" > "$wt_path/.git"
        return 0
      fi
      return 1
      ;;

    "broken gitdir reference")
      # Try to find and fix the gitdir reference
      local worktree_git_dir="$git_dir/worktrees/$folder"
      if [[ -d "$worktree_git_dir" ]]; then
        print -r -- "gitdir: $worktree_git_dir" > "$wt_path/.git"
        return 0
      fi
      return 1
      ;;

    "malformed .git file")
      # Recreate the .git file
      local worktree_git_dir="$git_dir/worktrees/$folder"
      if [[ -d "$worktree_git_dir" ]]; then
        print -r -- "gitdir: $worktree_git_dir" > "$wt_path/.git"
        return 0
      fi
      return 1
      ;;

    *"missing HEAD"*)
      # Try to recreate HEAD file
      local worktree_git_dir="$git_dir/worktrees/$folder"
      if [[ -d "$worktree_git_dir" ]]; then
        print -r -- "ref: refs/heads/$branch" > "$worktree_git_dir/HEAD"
        return 0
      fi
      return 1
      ;;

    *)
      # For compound issues, try the most common fix
      local worktree_git_dir="$git_dir/worktrees/$folder"
      if [[ -d "$worktree_git_dir" ]]; then
        # Fix .git file
        print -r -- "gitdir: $worktree_git_dir" > "$wt_path/.git"
        # Fix HEAD if missing
        if [[ ! -f "$worktree_git_dir/HEAD" ]]; then
          print -r -- "ref: refs/heads/$branch" > "$worktree_git_dir/HEAD"
        fi
        return 0
      fi
      return 1
      ;;
  esac
}

# Parallel commands


# cmd_upgrade — Upgrade grove to the latest version from its git repository
#
# Fetches updates, shows pending commits, and pulls with rebase.
# Aborts rebase on failure to avoid leaving broken state.
# Rebuilds if build.sh is present.
#
# Globals:
#   FORCE - when true, skips confirmation prompt
#
# Returns:
#   0 on success
cmd_upgrade() {
  print -r -- ""
  print -r -- "${C_BOLD}grove upgrade${C_RESET}"
  print -r -- ""

  # Find the grove script location
  local wt_path; wt_path="$(command -v grove 2>/dev/null)"
  if [[ -z "$wt_path" ]]; then
    error_exit "IO_ERROR" "cannot find 'grove' in PATH" 5
  fi

  # Resolve symlink to find repo
  local real_path; real_path="$(readlink "$wt_path" 2>/dev/null || echo "$wt_path")"
  local repo_dir="${real_path:h}"

  # Check if it's a git repo
  if [[ ! -d "$repo_dir/.git" && ! -f "$repo_dir/.git" ]]; then
    # Try parent directory
    repo_dir="${repo_dir:h}"
    if [[ ! -d "$repo_dir/.git" && ! -f "$repo_dir/.git" ]]; then
      error_exit "IO_ERROR" "grove is not installed from a git repository, cannot upgrade" 5
    fi
  fi

  info "Repository: ${C_CYAN}$repo_dir${C_RESET}"

  # Check current version
  local current_version="$VERSION"
  info "Current version: ${C_YELLOW}v$current_version${C_RESET}"

  # Fetch latest
  info "Fetching updates..."
  if ! git -C "$repo_dir" fetch origin --quiet 2>/dev/null; then
    error_exit "IO_ERROR" "failed to fetch updates, check your network connection" 5
  fi

  # Check if we're behind
  local local_head; local_head="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"
  local remote_head; remote_head="$(git -C "$repo_dir" rev-parse origin/main 2>/dev/null || git -C "$repo_dir" rev-parse origin/master 2>/dev/null)"

  if [[ "$local_head" == "$remote_head" ]]; then
    ok "Already up to date!"
    print -r -- ""
    return 0
  fi

  # Show what's new
  local commits_behind; commits_behind="$(git -C "$repo_dir" rev-list --count HEAD..origin/main 2>/dev/null || git -C "$repo_dir" rev-list --count HEAD..origin/master 2>/dev/null || echo 0)"
  info "Updates available: ${C_GREEN}$commits_behind${C_RESET} new commit(s)"
  print -r -- ""

  # Show recent commits
  dim "Recent changes:"
  git -C "$repo_dir" log --oneline HEAD..origin/main 2>/dev/null | head -5 | while read -r line; do
    print -r -- "  ${C_DIM}•${C_RESET} $line"
  done
  print -r -- ""

  # Confirm upgrade
  if [[ "$FORCE" != true ]]; then
    print -n "${C_YELLOW}Upgrade now? [y/N]${C_RESET} "
    local response
    read -r response
    [[ "$response" =~ ^[Yy]$ ]] || { dim "Aborted"; return 0; }
  fi

  # Pull updates
  info "Pulling updates..."
  if ! git -C "$repo_dir" pull --rebase origin main 2>/dev/null && ! git -C "$repo_dir" pull --rebase origin master 2>/dev/null; then
    git -C "$repo_dir" rebase --abort 2>/dev/null
    error_exit "IO_ERROR" "failed to pull updates, you may need to resolve conflicts manually" 5
  fi

  # Rebuild if build.sh exists
  if [[ -x "$repo_dir/build.sh" ]]; then
    info "Rebuilding..."
    if ! "$repo_dir/build.sh" >/dev/null 2>&1; then
      warn "Build failed, try running ./build.sh manually"
    fi
  fi

  # Show new version
  local new_version
  if [[ -f "$repo_dir/lib/00-header.sh" ]]; then
    new_version="$(grep '^VERSION=' "$repo_dir/lib/00-header.sh" 2>/dev/null | cut -d'"' -f2)"
  elif [[ -f "$repo_dir/grove" ]]; then
    new_version="$(grep '^VERSION=' "$repo_dir/grove" 2>/dev/null | head -1 | cut -d'"' -f2)"
  fi
  new_version="${new_version:-unknown}"

  print -r -- ""
  ok "Upgraded: ${C_YELLOW}v$current_version${C_RESET} → ${C_GREEN}v$new_version${C_RESET}"
  print -r -- ""

  # Verify
  dim "Verify with: grove --version"
  print -r -- ""
}


# cmd_version_check — Check if a newer version of grove is available
#
# Fetches from remote and compares HEAD against origin/main.
# Does not modify the installation.
#
# Returns:
#   0 always
cmd_version_check() {
  print -r -- ""
  print -r -- "${C_BOLD}Checking for updates...${C_RESET}"
  print -r -- ""

  local current_version="$VERSION"
  info "Installed: ${C_YELLOW}v$current_version${C_RESET}"

  # Find repo directory
  local wt_path; wt_path="$(command -v grove 2>/dev/null)"
  local real_path; real_path="$(readlink "$wt_path" 2>/dev/null || echo "$wt_path")"
  local repo_dir="${real_path:h}"

  if [[ ! -d "$repo_dir/.git" && ! -f "$repo_dir/.git" ]]; then
    repo_dir="${repo_dir:h}"
  fi

  if [[ -d "$repo_dir/.git" || -f "$repo_dir/.git" ]]; then
    # Fetch and check
    git -C "$repo_dir" fetch origin --quiet 2>/dev/null || true

    local local_head; local_head="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"
    local remote_head; remote_head="$(git -C "$repo_dir" rev-parse origin/main 2>/dev/null || git -C "$repo_dir" rev-parse origin/master 2>/dev/null)"

    if [[ "$local_head" == "$remote_head" ]]; then
      ok "You're running the latest version!"
    else
      local commits_behind; commits_behind="$(git -C "$repo_dir" rev-list --count HEAD..origin/main 2>/dev/null || git -C "$repo_dir" rev-list --count HEAD..origin/master 2>/dev/null || echo "?")"
      warn "Update available: ${C_GREEN}$commits_behind${C_RESET} new commit(s)"
      dim "  Run: grove upgrade"
    fi
  else
    dim "Cannot check for updates (not installed from git)"
  fi

  print -r -- ""
}


