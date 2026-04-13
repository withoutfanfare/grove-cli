#!/usr/bin/env zsh
# lifecycle.sh - Worktree creation and removal commands

# cmd_add — Create a new worktree for a branch, optionally from a base ref
cmd_add() {
  local repo="${1:-}"; local branch="${2:-}"; local base_arg="${3:-}"; local base="$base_arg"
  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove add <repo> <branch> [base]" 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  # Validate branch name against configured pattern (if set)
  validate_branch_pattern "$branch"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  # Load repo-specific config (may override DEFAULT_BASE)
  load_repo_config "$git_dir"

  # Load template if specified (sets GROVE_SKIP_* environment variables)
  if [[ -n "$GROVE_TEMPLATE" ]]; then
    load_template "$GROVE_TEMPLATE"
  fi

  # Use provided base or default
  [[ -z "$base" ]] && base="$DEFAULT_BASE"

  # Validate base ref for security
  validate_git_ref "$base" "base ref"

  # Strip origin/ prefix if user accidentally included it (do this early for accurate paths)
  if [[ "$branch" == origin/* ]]; then
    branch="${branch#origin/}"
    warn "Note: 'origin/' prefix will be stripped from branch name"
  fi

  local wt_path; wt_path="$(worktree_path_for "$repo" "$branch")"
  local app_url; app_url="$(url_for "$repo" "$branch")"
  local db_name; db_name="$(db_name_for "$repo" "$branch")"

  # Check if site name was shortened for SSL compatibility
  slugify_branch "$branch"
  local full_slug="$REPLY"
  local full_site_name="${repo}--${full_slug}"
  local actual_site_name="${wt_path:t}"
  if [[ "$full_site_name" != "$actual_site_name" ]]; then
    dim "Site name shortened for SSL compatibility"
    dim "  Full: $full_site_name (${#full_site_name} chars)"
    dim "  Used: $actual_site_name (${#actual_site_name} chars)"
  fi

  # Dry-run mode - show what would happen without executing
  if [[ "$DRY_RUN" == true ]]; then
    print -r -- ""
    print -r -- "${C_BOLD}Dry Run Preview${C_RESET}"
    print -r -- ""
    print -r -- "${C_BOLD}Worktree Details:${C_RESET}"
    print -r -- "  Repository:  ${C_CYAN}$repo${C_RESET}"
    print -r -- "  Branch:      ${C_MAGENTA}$branch${C_RESET}"
    print -r -- "  Base:        ${C_DIM}$base${C_RESET}"
    print -r -- "  Path:        $wt_path"
    print -r -- "  URL:         ${C_CYAN}$app_url${C_RESET}"
    print -r -- "  Database:    ${C_CYAN}$db_name${C_RESET}"
    print -r -- ""
    if [[ -n "$GROVE_TEMPLATE" ]]; then
      print -r -- "${C_BOLD}Template:${C_RESET} $GROVE_TEMPLATE"
      print -r -- "  ${C_DIM}GROVE_SKIP_DB${C_RESET}=${GROVE_SKIP_DB:-false}"
      print -r -- "  ${C_DIM}GROVE_SKIP_COMPOSER${C_RESET}=${GROVE_SKIP_COMPOSER:-false}"
      print -r -- "  ${C_DIM}GROVE_SKIP_NPM${C_RESET}=${GROVE_SKIP_NPM:-false}"
      print -r -- "  ${C_DIM}GROVE_SKIP_BUILD${C_RESET}=${GROVE_SKIP_BUILD:-false}"
      print -r -- "  ${C_DIM}GROVE_SKIP_MIGRATE${C_RESET}=${GROVE_SKIP_MIGRATE:-false}"
      print -r -- "  ${C_DIM}GROVE_SKIP_HERD${C_RESET}=${GROVE_SKIP_HERD:-false}"
      print -r -- ""
    fi
    print -r -- "${C_BOLD}Actions:${C_RESET}"
    print -r -- "  1. Fetch latest branches from remote"
    if git --git-dir="$git_dir" show-ref --quiet "refs/heads/$branch" 2>/dev/null; then
      print -r -- "  2. Create worktree from existing branch: $branch"
    else
      print -r -- "  2. Create new branch '$branch' from '$base'"
      print -r -- "  3. Push branch to remote and set up tracking"
    fi
    print -r -- "  4. Run pre-add hooks"
    print -r -- "  5. Run post-add hooks (environment setup)"
    print -r -- ""
    print -r -- "${C_DIM}Run without --dry-run to execute${C_RESET}"
    return 0
  fi

  # Ensure we can fetch all branches (fix corrupted refspecs)
  ensure_fetch_refspec "$git_dir"

  info "Fetching latest branches from remote..."
  git --git-dir="$git_dir" fetch --all --prune --quiet

  # If base is a remote ref (origin/...), explicitly fetch it to ensure we have the latest
  if [[ "$base" == origin/* ]]; then
    local remote_branch="${base#origin/}"
    dim "  Fetching latest: $remote_branch"
    git --git-dir="$git_dir" fetch origin "$remote_branch:refs/remotes/origin/$remote_branch" --force 2>/dev/null || true
  fi

  # Check if branch exists on remote (using ls-remote for accuracy)
  local branch_on_remote=false
  local branch_local=false

  if git --git-dir="$git_dir" show-ref --quiet "refs/heads/$branch"; then
    branch_local=true
  fi

  if remote_branch_exists "$git_dir" "$branch"; then
    branch_on_remote=true
    # Fetch it to local tracking branch
    if [[ "$branch_local" == false ]]; then
      info "Found branch on remote: ${C_MAGENTA}$branch${C_RESET}"
      dim "  Fetching to local..."
      git --git-dir="$git_dir" fetch origin "$branch:$branch" 2>/dev/null || \
        git --git-dir="$git_dir" fetch origin "$branch:refs/remotes/origin/$branch" 2>/dev/null || true
      # Recheck local
      if git --git-dir="$git_dir" show-ref --quiet "refs/heads/$branch"; then
        branch_local=true
      fi
    fi
  fi

  [[ ! -d "$wt_path" ]] || error_exit "WORKTREE_EXISTS" "worktree already exists at '$wt_path'" 4

  # If branch doesn't exist anywhere, warn the user before creating
  if [[ "$branch_local" == false && "$branch_on_remote" == false ]]; then
    # Verify base branch exists
    if ! git --git-dir="$git_dir" rev-parse --verify "$base" >/dev/null 2>&1; then
      error_exit "BRANCH_NOT_FOUND" "base branch '$base' not found, run: git --git-dir=\"$git_dir\" branch -a" 3
    fi

    warn "Branch ${C_MAGENTA}$branch${C_RESET} does not exist locally or on remote"
    print -r -- ""
    print -r -- "  ${C_BOLD}This will CREATE a new branch${C_RESET} from ${C_DIM}$base${C_RESET}"
    print -r -- ""

    # In non-interactive mode, show how to check out existing branches
    if [[ "$INTERACTIVE" != true && "$FORCE" != true ]]; then
      print -r -- "  ${C_DIM}If you meant to check out an existing branch:${C_RESET}"
      print -r -- "    1. Check available branches: git --git-dir=\"$git_dir\" branch -r"
      print -r -- "    2. Ensure the branch has been pushed to origin"
      print -r -- "    3. Use the exact branch name without 'origin/' prefix"
      print -r -- ""
      print -r -- "  ${C_DIM}To create the new branch anyway, run with --force${C_RESET}"
      error_exit "BRANCH_NOT_FOUND" "aborted: use --force to create new branch, or check the branch name" 3
    fi
  fi

  # Run pre-add hooks (can abort by returning non-zero)
  if ! run_hooks "pre-add" "$repo" "$branch" "$wt_path" "$app_url" "$db_name"; then
    error_exit "HOOK_FAILED" "pre-add hook failed, aborting" 5
  fi

  # Setup cleanup trap for failed operations
  # If worktree creation fails, clean up partial state
  local cleanup_needed=true
  trap '
    if [[ "$cleanup_needed" == true ]]; then
      warn "Worktree creation failed - cleaning up partial state..."
      # Remove worktree if it was created
      if [[ -d "$wt_path" ]]; then
        dim "  Removing worktree directory"
        git --git-dir="$git_dir" worktree remove --force "$wt_path" 2>/dev/null || /bin/rm -rf "$wt_path" 2>/dev/null
      fi
      # Clean up any Herd nginx config that might have been created
      if [[ -n "${app_url:-}" ]]; then
        local site_name="${wt_path:t}"
        cleanup_herd_site "$site_name" 2>/dev/null || true
      fi
      dim "  Cleanup complete"
    fi
  ' EXIT

  local created_from_base=false
  if [[ "$branch_local" == true ]]; then
    info "Creating worktree from existing branch: ${C_MAGENTA}$branch${C_RESET}"
    git --git-dir="$git_dir" worktree add "$wt_path" "$branch"
  elif [[ "$branch_on_remote" == true ]]; then
    # Branch exists on remote but fetch to local failed - try worktree add with remote tracking
    info "Creating worktree tracking remote branch: ${C_MAGENTA}origin/$branch${C_RESET}"
    git --git-dir="$git_dir" worktree add --track -b "$branch" "$wt_path" "origin/$branch"
  else
    created_from_base=true
    info "Creating NEW branch ${C_MAGENTA}$branch${C_RESET} from ${C_DIM}$base${C_RESET}"
    git --git-dir="$git_dir" worktree add --no-track -b "$branch" "$wt_path" "$base"
  fi

  # Ensure config.worktree exists when bare repo uses extensions.worktreeConfig
  ensure_worktree_config "$git_dir" "$wt_path"

  # Set up remote tracking (only push if creating new branch)
  if [[ "$branch_on_remote" == true ]]; then
    # Branch already exists on remote, just set up tracking
    dim "  Branch already exists on remote - setting up tracking"
    /usr/bin/git -C "$wt_path" branch --set-upstream-to="origin/$branch" "$branch" 2>/dev/null || true
  else
    # New branch - push to remote
    info "Pushing new branch to remote..."
    if GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git -C "$wt_path" push -u origin "$branch:$branch" 2>/dev/null; then
      ok "Remote branch created and tracking set"
    else
      dim "  Push failed (may need to push manually later): git push -u origin $branch"
    fi
  fi

  # Store the base ref this worktree should compare against (for summary/diff/sync defaults).
  # Only do this when we definitely created from a base, or when the user explicitly provided a base.
  if [[ "$created_from_base" == true || -n "$base_arg" ]]; then
    set_worktree_base "$wt_path" "$base"
  fi

  # Success - disable cleanup trap
  cleanup_needed=false
  trap - EXIT

  # Run post-add hooks
  run_hooks "post-add" "$repo" "$branch" "$wt_path" "$app_url" "$db_name"

  # Restart Herd services to pick up new site
  restart_herd_service

  if [[ "$JSON_OUTPUT" == true ]]; then
    json_escape "$wt_path"; local _je_path="$REPLY"
    json_escape "$app_url"; local _je_url="$REPLY"
    json_escape "$branch"; local _je_branch="$REPLY"
    json_escape "$db_name"; local _je_db="$REPLY"
    print -r -- "{\"path\": \"$_je_path\", \"url\": \"$_je_url\", \"branch\": \"$_je_branch\", \"database\": \"$_je_db\"}"
  else
    print -r -- ""
    ok "${C_BOLD}Worktree ready${C_RESET}"
    print -r -- "   ${C_DIM}Path${C_RESET}  $wt_path"
    print -r -- "   ${C_DIM}URL${C_RESET}   ${C_CYAN}$app_url${C_RESET}"
    print -r -- "   ${C_DIM}DB${C_RESET}    ${C_CYAN}$db_name${C_RESET}"
    print -r -- ""
  fi
}

# cmd_rm — Remove a worktree and optionally delete its branch
cmd_rm() {
  local repo="${1:-}"; local branch="${2:-}"

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to remove")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove rm [-f] [--delete-branch] <repo> <branch>" 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  local app_url; app_url="$(url_for "$repo" "$branch")"
  local db_name; db_name="$(db_name_for "$repo" "$branch")"
  local site_name="${wt_path:t}"

  ensure_bare_repo "$git_dir"
  [[ -d "$wt_path" ]] || error_exit "WORKTREE_NOT_FOUND" "worktree not found at '$wt_path'" 3

  # Branch protection check
  if is_protected_branch "$branch" && [[ "$FORCE" == false ]]; then
    error_exit "PROTECTED_BRANCH" "branch '$branch' is protected, use -f to force removal" 4
  fi

  # Check for uncommitted changes and confirm (unless --force)
  if [[ "$FORCE" == false ]]; then
    local wt_status; wt_status="$(git -C "$wt_path" status --porcelain 2>/dev/null)" || wt_status=""
    if [[ -n "$wt_status" ]]; then
      local changes; changes="$(count_lines "$wt_status")"
      warn "Worktree has ${C_BOLD}$changes${C_RESET}${C_YELLOW} uncommitted change(s):${C_RESET}"
      git -C "$wt_path" status --short
      print -n "${C_YELLOW}Continue with removal? [y/N]${C_RESET} "
      local response
      read -r response
      [[ "$response" =~ ^[Yy]$ ]] || error_exit "INVALID_INPUT" "aborted by user" 2
    fi
  fi

  # Run pre-rm hooks
  if ! run_hooks "pre-rm" "$repo" "$branch" "$wt_path" "$app_url" "$db_name"; then
    error_exit "HOOK_FAILED" "pre-rm hook failed, aborting" 5
  fi

  info "Removing worktree ${C_CYAN}$wt_path${C_RESET}"
  local remove_output
  if [[ "$FORCE" == true ]]; then
    remove_output="$(git --git-dir="$git_dir" worktree remove --force "$wt_path" 2>&1)" || {
      # Handle "Directory not empty" caused by untracked files left in the worktree directory
      if [[ "$remove_output" == *"Directory not empty"* && -d "$wt_path" ]]; then
        warn "Directory contains untracked files - cleaning up..."
        if ! rm -rf "$wt_path"; then
          error_exit "IO_ERROR" "failed to clean up worktree directory at '$wt_path'" 5
        fi
        if [[ -d "$wt_path" ]]; then
          error_exit "IO_ERROR" "cleanup failed, worktree directory still exists at '$wt_path'" 5
        fi
        # Prune git worktree metadata now that the directory has been removed
        git --git-dir="$git_dir" worktree prune 2>/dev/null || warn "Failed to prune git worktree metadata"
      else
        error_exit "GIT_ERROR" "failed to remove worktree: $remove_output" 4
      fi
    }
  else
    remove_output="$(git --git-dir="$git_dir" worktree remove "$wt_path" 2>&1)" || {
      if [[ "$remove_output" == *"Directory not empty"* && -d "$wt_path" ]]; then
        warn "Directory contains untracked files - use -f to force removal"
        error_exit "GIT_ERROR" "worktree directory not empty" 4
      else
        error_exit "GIT_ERROR" "failed to remove worktree: $remove_output" 4
      fi
    }
  fi

  # Delete branch if requested
  if [[ "$DELETE_BRANCH" == true ]]; then
    info "Deleting branch ${C_MAGENTA}$branch${C_RESET}"
    git --git-dir="$git_dir" branch -D "$branch" 2>/dev/null || warn "Could not delete branch (may not exist locally)"
  fi

  info "Pruning stale worktrees..."
  git --git-dir="$git_dir" worktree prune

  # Run post-rm hooks
  run_hooks "post-rm" "$repo" "$branch" "$wt_path" "$app_url" "$db_name"

  # Restart Herd services to clean up removed site
  restart_herd_service

  if [[ "$JSON_OUTPUT" == true ]]; then
    json_escape "$repo"; local _je_repo="$REPLY"
    json_escape "$branch"; local _je_branch="$REPLY"
    json_escape "$wt_path"; local _je_path="$REPLY"
    format_json "{\"success\": true, \"repo\": \"$_je_repo\", \"branch\": \"$_je_branch\", \"path\": \"$_je_path\", \"branch_deleted\": $DELETE_BRANCH, \"db_dropped\": $DROP_DB}"
  else
    ok "Worktree removed"
    print -r -- ""
  fi
}

# cmd_move — Move a worktree to a new directory name
cmd_move() {
  local repo="${1:-}"; local branch="${2:-}"; local new_name="${3:-}"

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to move")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove move <repo> <branch> <new-name>" 2

  # Prompt for new name if not provided
  if [[ -z "$new_name" ]]; then
    print -n "${C_CYAN}New directory name: ${C_RESET}"
    read -r new_name
    [[ -n "$new_name" ]] || error_exit "INVALID_INPUT" "new directory name is required" 2
  fi

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  # Validate new name using shared validation (checks empty, path traversal, leading dash)
  validate_identifier_common "$new_name" "directory name"
  # Additional check: directory names must not contain slashes
  if [[ "$new_name" == */* ]]; then
    error_exit "INVALID_INPUT" "invalid directory name '$new_name', slashes not allowed" 2
  fi

  local git_dir; git_dir="$(git_dir_for "$repo")"
  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  local wt_parent="${wt_path:h}"
  local old_site_name="${wt_path:t}"
  local new_wt_path="$wt_parent/$new_name"
  local new_site_name="$new_name"

  # Get old URL and database name for hooks
  local old_url; old_url="$(url_for "$repo" "$branch")"
  local db_name; db_name="$(db_name_for "$repo" "$branch")"

  ensure_bare_repo "$git_dir"
  [[ -d "$wt_path" ]] || error_exit "WORKTREE_NOT_FOUND" "worktree not found at '$wt_path'" 3
  [[ ! -d "$new_wt_path" ]] || error_exit "WORKTREE_EXISTS" "destination already exists: '$new_wt_path'" 4

  # Check if old site is secured
  local was_secured=false
  if command -v herd >/dev/null 2>&1; then
    if herd secured 2>/dev/null | grep -q "^| ${old_site_name}.test "; then
      was_secured=true
    fi
  fi

  info "Moving worktree:"
  print -r -- "  ${C_DIM}From:${C_RESET} ${C_CYAN}$wt_path${C_RESET}"
  print -r -- "  ${C_DIM}To:${C_RESET}   ${C_CYAN}$new_wt_path${C_RESET}"

  # Confirm unless --force
  if [[ "$FORCE" == false ]]; then
    print -n "${C_YELLOW}Continue? [y/N]${C_RESET} "
    local response
    read -r response
    [[ "$response" =~ ^[Yy]$ ]] || error_exit "INVALID_INPUT" "aborted by user" 2
  fi

  # Run pre-move hooks (with old path, URL, and db_name)
  if ! run_hooks "pre-move" "$repo" "$branch" "$wt_path" "$old_url" "$db_name"; then
    error_exit "HOOK_FAILED" "pre-move hook failed, aborting" 5
  fi

  # Unsecure old site if it was secured
  if [[ "$was_secured" == true ]]; then
    info "Unsecuring old site ${C_CYAN}${old_site_name}.test${C_RESET}"
    herd unsecure "$old_site_name" >/dev/null 2>&1 || true
  fi

  # Clean up old Herd nginx configs and certificates
  if command -v herd >/dev/null 2>&1; then
    cleanup_herd_site "$old_site_name"
  fi

  # Move the worktree
  info "Moving worktree..."
  if [[ "$FORCE" == true ]]; then
    git --git-dir="$git_dir" worktree move --force "$wt_path" "$new_wt_path"
  else
    git --git-dir="$git_dir" worktree move "$wt_path" "$new_wt_path"
  fi

  # Re-secure new site if old was secured
  if [[ "$was_secured" == true ]]; then
    info "Securing new site ${C_CYAN}${new_site_name}.test${C_RESET}"
    if ! herd secure "$new_site_name" >/dev/null 2>&1; then
      warn "Could not secure new site - you may need to run: herd secure $new_site_name"
    else
      ok "Site secured"
    fi
  fi

  # Calculate new URL (based on new directory name, not repo--branch pattern)
  local new_url="https://${new_site_name}.test"
  if [[ -n "$GROVE_URL_SUBDOMAIN" ]]; then
    new_url="https://${GROVE_URL_SUBDOMAIN}.${new_site_name}.test"
  fi

  # Update APP_URL in .env if it exists
  local env_file="$new_wt_path/.env"
  if [[ -f "$env_file" ]]; then
    local content
    content="$(<"$env_file")"
    if [[ "$content" == *APP_URL=* ]]; then
      content="${content/APP_URL=*/APP_URL=$new_url}"
      print -r -- "$content" > "$env_file"
      dim "  Updated APP_URL in .env"
    fi
  fi

  # Run post-move hooks (with new path, URL, and db_name)
  run_hooks "post-move" "$repo" "$branch" "$new_wt_path" "$new_url" "$db_name"

  print -r -- ""
  ok "Worktree moved successfully"
  print -r -- ""
  print -r -- "  ${C_DIM}Path:${C_RESET} ${C_CYAN}$new_wt_path${C_RESET}"
  print -r -- "  ${C_DIM}URL:${C_RESET}  ${C_CYAN}$new_url${C_RESET}"
  print -r -- ""
}

# cmd_clone — Clone a repository as a bare repo and optionally create an initial worktree
cmd_clone() {
  local url="${1:-}"; local repo="${2:-}"; local initial_branch="${3:-}"
  [[ -n "$url" ]] || error_exit "INVALID_INPUT" "Usage: grove clone <url> [repo-name] [branch]" 2

  # Extract repo name from URL if not provided
  if [[ -z "$repo" ]]; then
    repo="${url##*/}"
    repo="${repo%.git}"
  fi

  validate_name "$repo" "repository"
  [[ -z "$initial_branch" ]] || validate_name "$initial_branch" "branch"

  local git_dir; git_dir="$(git_dir_for "$repo")"

  [[ ! -d "$git_dir" ]] || error_exit "REPO_EXISTS" "bare repo already exists at '$git_dir'" 3

  # For JSON output, capture errors and output structured response
  if [[ "$JSON_OUTPUT" == true ]]; then
    local clone_output clone_exit=0
    clone_output=$(GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git clone --bare "$url" "$git_dir" 2>&1) || clone_exit=$?

    if [[ $clone_exit -ne 0 ]]; then
      json_escape "$repo"; local _je_repo="$REPLY"
      json_escape "$git_dir"; local _je_dir="$REPLY"
      json_escape "$clone_output"; local _je_msg="$REPLY"
      print -r -- "{\"success\": false, \"repo\": \"$_je_repo\", \"path\": \"$_je_dir\", \"message\": \"$_je_msg\"}"
      return 1
    fi

    # Configure fetch to get all branches
    /usr/bin/git --git-dir="$git_dir" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

    # Fetch all branches (ignore errors for JSON - already cloned)
    GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git --git-dir="$git_dir" fetch --all --prune 2>/dev/null || true

    json_escape "$repo"; local _je_repo2="$REPLY"
    json_escape "$git_dir"; local _je_dir2="$REPLY"
    print -r -- "{\"success\": true, \"repo\": \"$_je_repo2\", \"path\": \"$_je_dir2\", \"message\": \"Repository cloned successfully\"}"
    return 0
  fi

  # Non-JSON output (original behaviour)
  info "Cloning ${C_CYAN}$url${C_RESET} as bare repo..."
  GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git clone --bare "$url" "$git_dir"

  # Configure fetch to get all branches
  /usr/bin/git --git-dir="$git_dir" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

  info "Fetching all branches..."
  GIT_SSH_COMMAND="/usr/bin/ssh" /usr/bin/git --git-dir="$git_dir" fetch --all --prune

  print -r -- ""
  ok "Bare repo created at ${C_CYAN}$git_dir${C_RESET}"

  # If specific branch requested, create worktree for it
  if [[ -n "$initial_branch" ]]; then
    print -r -- ""
    if /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/$initial_branch"; then
      info "Creating worktree for ${C_GREEN}$initial_branch${C_RESET}..."
      cmd_add "$repo" "$initial_branch" "origin/$initial_branch"
    else
      local base_branch=""
      if /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/staging"; then
        base_branch="origin/staging"
      elif /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/main"; then
        base_branch="origin/main"
      elif /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/master"; then
        base_branch="origin/master"
      else
        error_exit "BRANCH_NOT_FOUND" "branch '$initial_branch' not found on remote and no default base branch available" 3
      fi
      info "Creating new branch ${C_GREEN}$initial_branch${C_RESET} from $base_branch..."
      cmd_add "$repo" "$initial_branch" "$base_branch"
    fi
  elif /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/staging"; then
    print -r -- ""
    info "Found staging branch - creating worktree..."
    cmd_add "$repo" "staging" "origin/staging"
  elif /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/main"; then
    print -r -- ""
    info "Found main branch - creating worktree..."
    cmd_add "$repo" "main" "origin/main"
  elif /usr/bin/git --git-dir="$git_dir" show-ref --quiet "refs/remotes/origin/master"; then
    print -r -- ""
    info "Found master branch - creating worktree..."
    cmd_add "$repo" "master" "origin/master"
  else
    dim "  Create a worktree with: grove add $repo <branch>"
    print -r -- ""
  fi

  notify "grove clone" "Repository $repo cloned successfully"
}

# cmd_fresh — Refresh a worktree by running migrate:fresh, npm ci, and build
cmd_fresh() {
  local repo="${1:-}"; local branch="${2:-}"

  # Auto-detect from current directory if no args
  if [[ -z "$repo" ]] && detect_current_worktree; then
    repo="$DETECTED_REPO"
    branch="$DETECTED_BRANCH"
    dim "  Detected: $repo / $branch"
  fi

  # Handle fzf selection if branch not provided
  if [[ -n "$repo" && -z "$branch" ]] && command -v fzf >/dev/null 2>&1; then
    validate_name "$repo" "repository"
    branch="$(select_branch_fzf "$repo" "Select worktree to refresh")" || error_exit "INVALID_INPUT" "no branch selected" 2
    validate_name "$branch" "branch"
  fi

  [[ -n "$repo" && -n "$branch" ]] || error_exit "INVALID_INPUT" "Usage: grove fresh [<repo> [<branch>]] - Run from within a worktree to auto-detect, or specify repo/branch." 2

  validate_name "$repo" "repository"
  validate_name "$branch" "branch"

  local wt_path; wt_path="$(resolve_worktree_path "$repo" "$branch")"
  [[ -d "$wt_path" ]] || die_wt_not_found "$repo" "$wt_path"

  pushd "$wt_path" >/dev/null || error_exit "IO_ERROR" "failed to cd into '$wt_path'" 5

  print -r -- ""
  print -r -- "${C_BOLD}Refreshing ${C_CYAN}$repo${C_RESET} / ${C_MAGENTA}$branch${C_RESET}"
  print -r -- ""

  # Run migrate:fresh --seed (with confirmation unless forced)
  if [[ -f "artisan" ]]; then
    if [[ "$FORCE" == false ]]; then
      warn "This will DROP ALL TABLES in the database!"
      print -n "${C_YELLOW}Continue with migrate:fresh? [y/N]${C_RESET} "
      local response
      read -r response
      if [[ ! "$response" =~ ^[Yy]$ ]]; then
        warn "Skipping migrate:fresh"
        popd >/dev/null
        return 0
      fi
    fi

    info "Running migrate:fresh --seed..."
    if php artisan migrate:fresh --seed; then
      ok "Database refreshed"
    else
      warn "migrate:fresh --seed failed"
    fi
  fi

  # Run npm ci
  if [[ -f "package.json" ]]; then
    info "Running npm ci..."
    if npm ci; then
      ok "npm dependencies installed"
    else
      warn "npm ci failed"
    fi

    info "Running npm run build..."
    if npm run build; then
      ok "Assets built"
    else
      warn "npm run build failed"
    fi
  fi

  popd >/dev/null

  notify "grove fresh" "Completed for $repo / $branch"
  print -r -- ""
  ok "Fresh complete!"
  print -r -- ""
}

# cmd_restructure — Migrate worktrees from flat layout to nested directory structure
cmd_restructure() {
  local repo="${1:-}"

  [[ -n "$repo" ]] || error_exit "INVALID_INPUT" "Usage: grove restructure <repo> - Migrates all worktrees from old structure (repo--branch) to new structure (repo-worktrees/feature-name)" 2

  validate_name "$repo" "repository"

  local git_dir; git_dir="$(git_dir_for "$repo")"
  ensure_bare_repo "$git_dir"

  # Create the new worktrees container if it doesn't exist
  local new_container="$HERD_ROOT/${repo}-worktrees"
  if [[ ! -d "$new_container" ]]; then
    info "Creating worktrees container: ${C_CYAN}$new_container${C_RESET}"
    mkdir -p "$new_container"
  fi

  # Get all worktrees for this repo
  local out; out="$(git --git-dir="$git_dir" worktree list --porcelain 2>/dev/null)" || error_exit "GIT_ERROR" "failed to list worktrees" 4

  local wt_path="" branch=""
  local -i migrated=0 skipped=0
  local line=""
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      if [[ -n "$wt_path" && -n "$branch" && "$wt_path" != *.git ]]; then
        # Check if this worktree needs migration
        local folder="${wt_path:t}"
        local parent="${wt_path:h}"
        local parent_name="${parent:t}"

        # Skip if already in new structure
        if [[ "$parent_name" == "${repo}-worktrees" ]]; then
          dim "  Already migrated: $branch → $folder"
          skipped+=1
        # Migrate if in old structure (at HERD_ROOT level with repo-- prefix)
        elif [[ "$parent" == "$HERD_ROOT" && "$folder" == "${repo}--"* ]]; then
          local new_site_name; new_site_name="$(site_name_for "$repo" "$branch")"
          local new_path="$new_container/$new_site_name"

          if [[ -d "$new_path" ]]; then
            warn "Cannot migrate $branch: destination already exists at $new_path"
          else
            info "Migrating: ${C_MAGENTA}$branch${C_RESET}"
            dim "  From: $wt_path"
            dim "  To:   $new_path"

            # Use git worktree move
            if git --git-dir="$git_dir" worktree move "$wt_path" "$new_path" 2>/dev/null; then
              ok "  Migrated successfully"

              # Update Herd site (unsecure old, secure new)
              if command -v herd >/dev/null 2>&1; then
                herd unsecure "$folder" 2>/dev/null || true
                herd secure "$new_site_name" 2>/dev/null || true
                dim "  Updated Herd SSL for $new_site_name"

                # Update APP_URL in .env if it exists
                local env_file="$new_path/.env"
                if [[ -f "$env_file" ]]; then
                  local new_url="https://${new_site_name}.test"
                  local content
                  content="$(<"$env_file")"
                  if [[ "$content" == *APP_URL=* ]]; then
                    content="${content/APP_URL=*/APP_URL=$new_url}"
                    print -r -- "$content" > "$env_file"
                  fi
                  dim "  Updated APP_URL in .env"
                fi
              fi

              migrated+=1
            else
              warn "  Failed to migrate (try manually: git worktree move)"
            fi
          fi
        else
          dim "  Skipping: $branch (not in old structure)"
          skipped+=1
        fi
      fi
      wt_path=""
      branch=""
      continue
    fi
    [[ "$line" == worktree\ * ]] && wt_path="${line#worktree }"
    [[ "$line" == branch\ refs/heads/* ]] && branch="${line#branch refs/heads/}"
  done <<< "$out"

  # Handle last entry
  if [[ -n "$wt_path" && -n "$branch" && "$wt_path" != *.git ]]; then
    local folder="${wt_path:t}"
    local parent="${wt_path:h}"
    if [[ "$parent" == "$HERD_ROOT" && "$folder" == "${repo}--"* ]]; then
      local new_site_name; new_site_name="$(site_name_for "$repo" "$branch")"
      local new_path="$new_container/$new_site_name"
      if [[ ! -d "$new_path" ]]; then
        info "Migrating: ${C_MAGENTA}$branch${C_RESET}"
        if git --git-dir="$git_dir" worktree move "$wt_path" "$new_path" 2>/dev/null; then
          ok "  Migrated successfully"
          migrated+=1
        fi
      fi
    fi
  fi

  print -r -- ""
  ok "Migration complete: ${C_GREEN}$migrated${C_RESET} migrated, ${C_DIM}$skipped${C_RESET} skipped"
  print -r -- ""
}
