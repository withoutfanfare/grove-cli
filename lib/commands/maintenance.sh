#!/usr/bin/env zsh
# maintenance.sh - System maintenance and diagnostic commands

# cmd_doctor — Run diagnostic checks on grove installation and configuration
#
# Checks: HERD_ROOT, required tools (git, composer), optional tools
# (mysql, herd, fzf, editor), config files, and hook directories.
#
# Returns:
#   0 if all checks pass, 1 if any issues are found (so CI can gate on it)
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

    # Test connection (use MYSQL_PWD env var for safer password handling).
    # Honour a non-default DB_PORT so the check targets the configured server
    # rather than always probing 3306.
    local mysql_cmd=(mysql -h "$DB_HOST" -u "$DB_USER")
    if [[ -n "${DB_PORT:-}" && "$DB_PORT" != "3306" ]]; then
      mysql_cmd+=(-P "$DB_PORT")
    fi
    if MYSQL_PWD="${DB_PASSWORD:-}" "${mysql_cmd[@]}" -e "SELECT 1" >/dev/null 2>&1; then
      ok "  MySQL connection: OK"
    else
      warn "  MySQL connection: FAILED (check DB_HOST, DB_PORT, DB_USER, DB_PASSWORD)"
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
    print -r -- ""
    # Exit non-zero so CI can gate on a healthy installation.
    return 1
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
  local raw_target=""

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

    # A site still linked in Herd's Sites directory is live whatever its name
    # (a new-layout worktree folder can contain "--" too, e.g. after
    # `grove move`); only Method 2 below may judge a linked site.
    [[ -e "$sites_dir/$folder_name" || -L "$sites_dir/$folder_name" ]] && continue

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
      # readlink may return a RELATIVE target, which would then be tested against
      # grove's cwd and wrongly judged missing. Canonicalise with :A (full symlink
      # resolution) so the existence test runs against the real absolute path.
      raw_target="$(readlink "$site_link" 2>/dev/null)"
      local target="${site_link:A}"

      # Only check sites that point to -worktrees directories
      if [[ "$raw_target" == *"-worktrees/"* && ! -d "$target" ]]; then
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
  local site_ok
  for site_name in "${orphaned[@]}"; do
    local folder_name="${site_name%.test}"
    info "Cleaning ${C_CYAN}$site_name${C_RESET}"
    site_ok=true

    # Remove nginx config. A failed rm (e.g. permissions) must NOT be counted as
    # a successful clean, so track the outcome rather than assuming success.
    local nginx_config="$nginx_dir/$site_name"
    if [[ -f "$nginx_config" ]]; then
      if ! /bin/rm -f "$nginx_config" 2>/dev/null; then
        warn "  Failed to remove nginx config: $nginx_config"
        site_ok=false
      fi
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

    [[ "$site_ok" == true ]] && cleaned=$((cleaned + 1))
  done

  # Restart nginx to apply changes
  info "Restarting Herd nginx..."
  herd restart >/dev/null 2>&1

  print -r -- ""
  ok "Cleaned ${C_BOLD}$cleaned${C_RESET} orphaned config(s)"
  print -r -- ""
}


# _unlock_lock_file — Remove one index.lock if it is safe to do so
#
# A lock held by a running process is never removed: deleting it mid-checkout or
# mid-rebase lets a second writer corrupt the index. A lock younger than five
# minutes is probably a live operation that lsof/fuser missed, so it needs -f.
#
# Arguments:
#   $1 - lock file path
#   $2 - label for messages
#
# Returns:
#   0 if removed, 1 if left in place
_unlock_lock_file() {
  local lock_file="$1" label="$2"
  if _lock_file_in_use "$lock_file"; then
    warn "Lock in use by a running process, not removing: $label"
    return 1
  fi
  local lock_age=$(( $(_get_now) - $(file_mtime "$lock_file" || echo 0) ))
  if (( lock_age <= 300 )) && [[ "$FORCE" != true ]]; then
    warn "Lock is under 5 minutes old, not removing: $label ${C_DIM}(use -f if no git command is running)${C_RESET}"
    return 1
  fi
  rm -f "$lock_file"
  ok "Removed lock: $label"
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
      [[ -f "$lock_file" ]] || continue
      _unlock_lock_file "$lock_file" "${C_CYAN}${${lock_file:h}:t}${C_RESET}" && count=$((count + 1))
    done

    if (( count == 0 )); then
      ok "No lock files removed for ${C_CYAN}$repo${C_RESET}"
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
        [[ -f "$lock_file" ]] || continue
        _unlock_lock_file "$lock_file" "${C_CYAN}$repo_name${C_RESET} / ${C_MAGENTA}${${lock_file:h}:t}${C_RESET}" && total=$((total + 1))
      done
    done

    if (( total == 0 )); then
      ok "No lock files removed"
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

  if [[ "$recovery_mode" == true && "$JSON_OUTPUT" != true ]]; then
    info "Running in ${C_YELLOW}recovery mode${C_RESET} - aggressive recovery enabled"
    print -r -- ""
  fi

  if [[ -z "$repo" ]]; then
    # Repair all repos (single-object JSON contract: repo required)
    [[ "$JSON_OUTPUT" == true ]] && error_exit "INVALID_INPUT" "JSON output not supported when repairing all repositories" 2
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
  # In JSON mode all human output is suppressed and a single RepairResult
  # object is emitted on stdout (consumed by the Grove desktop app).
  local json_mode=false
  [[ "$JSON_OUTPUT" == true ]] && json_mode=true

  if [[ "$json_mode" != true ]]; then
    print -r -- ""
    print -r -- "${C_BOLD}Repairing: ${C_CYAN}$repo${C_RESET}"
    print -r -- ""
  fi

  local found=0 fixed=0 damaged=0 recovered=0

  # 1. Clean stale index locks
  [[ "$json_mode" == true ]] || info "Checking for stale index locks..."
  # check_index_locks prints the lock count on STDOUT (exit status is always 0 on
  # success); capture it rather than relying on the old exit-status-as-count.
  local locks_cleaned
  locks_cleaned="$(check_index_locks "$git_dir" "--auto-clean")"
  if (( locks_cleaned > 0 )); then
    found=$((found + 1))
    fixed=$((fixed + 1))
  else
    [[ "$json_mode" == true ]] || dim "  No stale locks"
  fi

  # 2. Check for missing .git files in worktrees. This runs BEFORE pruning:
  # git treats a worktree whose .git file is missing as deleted, so pruning
  # first would destroy the metadata (index, HEAD, grove sidecars) that
  # recovery needs, then report the loss as a fix.
  [[ "$json_mode" == true ]] || info "Checking worktree integrity..."
  local out; out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || true
  local wt_path="" branch="" corrupted_worktrees=()
  # Declared OUTSIDE the loop: `local var;` re-declared inside a loop makes
  # zsh print "var='...'" to stdout from the second iteration onward, which
  # corrupts JSON output (see CLAUDE.md, JSON output data contract).
  local gitdir_content="" wt_git_dir=""

  # The trailing $'\n' preserves the blank line after the final porcelain
  # entry (command substitution strips it), so the last worktree is checked.
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
          gitdir_content="$(cat "$wt_path/.git" 2>/dev/null)"
          if [[ "$gitdir_content" == gitdir:\ * ]]; then
            local ref_path="${gitdir_content#gitdir: }"
            if [[ ! -d "$ref_path" ]]; then
              issue="broken gitdir reference"
            fi
          else
            issue="malformed .git file"
          fi
        fi

        # Check for missing HEAD. git names the admin directory at creation
        # time and `worktree move` keeps it, so find it by its gitdir backlink.
        local worktree_name="${wt_path:t}"
        wt_git_dir="$(_worktree_admin_dir "$git_dir" "$wt_path")" || wt_git_dir=""
        if [[ -n "$wt_git_dir" && ! -f "$wt_git_dir/HEAD" ]]; then
          issue="${issue:+$issue, }missing HEAD"
        fi

        if [[ -n "$issue" ]]; then
          found=$((found + 1))
          damaged=$((damaged + 1))
          [[ "$json_mode" == true ]] || warn "  ${C_YELLOW}$worktree_name${C_RESET}: $issue"
          [[ -n "$branch" ]] && corrupted_worktrees+=("$wt_path|$branch|$issue")
        fi
      fi
      wt_path=""
      branch=""
    fi
  done <<< "$out"$'\n'

  # Recovery mode: attempt to fix corrupted worktrees
  if [[ "$recovery_mode" == true && ${#corrupted_worktrees[@]} -gt 0 ]]; then
    if [[ "$json_mode" != true ]]; then
      print -r -- ""
      info "Attempting recovery of ${C_BOLD}${#corrupted_worktrees[@]}${C_RESET} corrupted worktree(s)..."
      print -r -- ""
    fi

    for entry in "${corrupted_worktrees[@]}"; do
      local corrupt_path="${entry%%|*}"
      local rest="${entry#*|}"
      local corrupt_branch="${rest%%|*}"
      local corrupt_issue="${rest#*|}"
      local folder="${corrupt_path:t}"

      [[ "$json_mode" == true ]] || info "  Recovering: ${C_CYAN}$folder${C_RESET} (${corrupt_branch})"

      if _attempt_worktree_recovery "$repo" "$git_dir" "$corrupt_path" "$corrupt_branch" "$corrupt_issue"; then
        [[ "$json_mode" == true ]] || ok "    Recovered successfully"
        fixed=$((fixed + 1))
        recovered=$((recovered + 1))
      else
        if [[ "$json_mode" != true ]]; then
          warn "    Recovery failed - may need manual intervention"
          dim "    Try: grove rm $repo $corrupt_branch && grove add $repo $corrupt_branch"
        fi
      fi
    done
  elif (( ${#corrupted_worktrees[@]} > 0 )) && [[ "$json_mode" != true ]]; then
    print -r -- ""
    dim "  Use ${C_YELLOW}--recovery${C_RESET} flag to attempt automatic recovery"
  fi

  # 3. Prune orphaned worktrees — only once no damaged worktree remains, so
  # prune never discards the metadata of a worktree that still exists.
  [[ "$json_mode" == true ]] || info "Checking for orphaned worktrees..."
  if (( damaged > recovered )); then
    [[ "$json_mode" == true ]] || dim "  Skipped: damaged worktrees remain and pruning would discard their metadata"
  else
    local pruned; pruned="$(git --git-dir="$git_dir" worktree prune -v 2>&1)" || true
    if [[ -n "$pruned" && "$pruned" != *"Nothing to prune"* ]]; then
      if [[ "$json_mode" != true ]]; then
        print -r -- "$pruned" | while read -r line; do
          ok "  Pruned: $line"
        done
      fi
      found=$((found + 1))
      fixed=$((fixed + 1))
    else
      [[ "$json_mode" == true ]] || dim "  No orphaned worktrees"
    fi
  fi

  if [[ "$json_mode" == true ]]; then
    # RepairResult contract: {success, repo, issues_found, issues_fixed, message}.
    # success is false when issues remain unfixed so consumers surface the message.
    local success=true message
    if (( found == 0 )); then
      message="No issues found in $repo"
    elif (( fixed >= found )); then
      message="Fixed $fixed issue(s) in $repo"
    else
      success=false
      message="Found $found issue(s) in $repo, fixed $fixed - run repair with --recovery to attempt automatic recovery"
    fi
    json_escape "$repo"; local _je_repo="$REPLY"
    json_escape "$message"; local _je_msg="$REPLY"
    format_json "{\"success\": $success, \"repo\": \"$_je_repo\", \"issues_found\": $found, \"issues_fixed\": $fixed, \"message\": \"$_je_msg\"}"
    return 0
  fi

  print -r -- ""
  if (( fixed > 0 )); then
    ok "Fixed $fixed issue(s) in $repo"
  else
    ok "No issues found in $repo"
  fi
}

# _worktree_admin_dir — Print the $git_dir/worktrees/<id> directory that belongs to a worktree
#
# git names the admin directory when the worktree is created, and `git worktree
# move` (used by `grove move`) keeps that name, so the folder name is not a
# reliable key. Match on the admin directory's gitdir backlink instead.
#
# Arguments:
#   $1 - git directory path
#   $2 - worktree path
#
# Returns:
#   0 and prints the directory, or 1 when no admin directory points at the worktree
_worktree_admin_dir() {
  local git_dir="$1"
  local want="${2:A}/.git"
  local admin backlink
  for admin in "$git_dir"/worktrees/*(N/); do
    [[ -f "$admin/gitdir" ]] || continue
    backlink="$(<"$admin/gitdir")"
    if [[ "${backlink:A}" == "$want" ]]; then
      print -r -- "$admin"
      return 0
    fi
  done
  return 1
}

# Attempt to recover a corrupted worktree
#
# .git file problems are repaired by `git worktree repair`, which rewrites each
# worktree's .git file from its admin directory's backlink and so never points
# a worktree at another worktree's metadata. A missing HEAD is recreated in the
# admin directory found by _worktree_admin_dir.
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

  local admin_dir; admin_dir="$(_worktree_admin_dir "$git_dir" "$wt_path")" || return 1

  if [[ "$issue" == *"missing HEAD"* ]]; then
    print -r -- "ref: refs/heads/$branch" > "$admin_dir/HEAD"
  fi

  if [[ "$issue" == *".git file"* || "$issue" == *"gitdir reference"* ]]; then
    # repair exits non-zero on a bare layout (it also reports the bare repo as
    # a broken main worktree), so judge success by the result instead.
    git --git-dir="$git_dir" worktree repair >/dev/null 2>&1 || true
  fi

  # Recovered only if the worktree now resolves to its own admin directory.
  local resolved; resolved="$(git -C "$wt_path" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  [[ "${resolved:A}" == "${admin_dir:A}" ]]
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

  # Resolve symlink to find repo. Use :A (full resolution) rather than a
  # single-level readlink so a chain of symlinks (or a relative link) still
  # lands on the real script directory.
  local real_path="${wt_path:A}"
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

  # Determine the upstream branch ONCE (main, falling back to master) and reuse
  # it for the behind-check, the log preview and the pull. Doing this once keeps
  # all three consistent and avoids comparing HEAD against the wrong ref.
  local upstream_branch
  if git -C "$repo_dir" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    upstream_branch="main"
  elif git -C "$repo_dir" rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
    upstream_branch="master"
  else
    error_exit "IO_ERROR" "cannot find origin/main or origin/master to upgrade from" 5
  fi

  # Refuse to rebase a developer's feature branch onto the upstream default. With
  # the symlink dev install, a contributor working on a feature branch would
  # otherwise have it silently rebased onto $upstream_branch and could lose work.
  local current_branch; current_branch="$(git -C "$repo_dir" symbolic-ref --short -q HEAD 2>/dev/null)"
  if [[ "$current_branch" != "$upstream_branch" ]]; then
    error_exit "IO_ERROR" "grove repo is on '${current_branch:-a detached HEAD}', not the default branch '$upstream_branch'; switch to '$upstream_branch' before upgrading" 5
  fi

  # Refuse to rebase over uncommitted changes — a rebase would clobber them.
  if [[ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]]; then
    error_exit "IO_ERROR" "grove repo has uncommitted changes; commit or stash them before upgrading" 5
  fi

  # Fetch latest
  info "Fetching updates..."
  if ! git -C "$repo_dir" fetch origin --quiet 2>/dev/null; then
    error_exit "IO_ERROR" "failed to fetch updates, check your network connection" 5
  fi

  # Check if we're behind
  local local_head; local_head="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"
  local remote_head; remote_head="$(git -C "$repo_dir" rev-parse "origin/$upstream_branch" 2>/dev/null)"

  if [[ "$local_head" == "$remote_head" ]]; then
    ok "Already up to date!"
    print -r -- ""
    return 0
  fi

  # Show what's new
  local commits_behind; commits_behind="$(git -C "$repo_dir" rev-list --count "HEAD..origin/$upstream_branch" 2>/dev/null || echo 0)"
  info "Updates available: ${C_GREEN}$commits_behind${C_RESET} new commit(s)"
  print -r -- ""

  # Show recent commits
  dim "Recent changes:"
  git -C "$repo_dir" log --oneline "HEAD..origin/$upstream_branch" 2>/dev/null | head -5 | while read -r line; do
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

  # Pull updates. Surface git's stderr so a genuine conflict/error is visible
  # rather than swallowed before we tell the user to resolve it manually.
  info "Pulling updates..."
  local pull_err
  if ! pull_err="$(git -C "$repo_dir" pull --rebase origin "$upstream_branch" 2>&1 >/dev/null)"; then
    git -C "$repo_dir" rebase --abort 2>/dev/null
    [[ -n "$pull_err" ]] && print -r -- "$pull_err" >&2
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

  # Find repo directory. Use :A (full resolution) so a chain of symlinks or a
  # relative link still resolves to the real script directory.
  local wt_path; wt_path="$(command -v grove 2>/dev/null)"
  local real_path="${wt_path:A}"
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


